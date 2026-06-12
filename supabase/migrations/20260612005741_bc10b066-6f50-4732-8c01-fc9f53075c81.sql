
-- 1) Add mission_earning to txn_type if missing.
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid
    WHERE t.typname='txn_type' AND e.enumlabel='mission_earning'
  ) THEN
    ALTER TYPE public.txn_type ADD VALUE 'mission_earning';
  END IF;
END $$;

-- 2) Secure mission-earning credit RPC.
CREATE OR REPLACE FUNCTION public.wallet_credit_mission_earning(
  p_mission_id uuid,
  p_reason     text DEFAULT 'Mission delivered courier earning'
)
RETURNS public.wallet_transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_m              public.missions;
  v_amount         bigint;
  v_courier_wallet uuid;
  v_master_wallet  uuid;
  v_ref            text;
  v_existing       public.wallet_transactions;
  v_tx             public.wallet_transactions;
BEGIN
  IF p_mission_id IS NULL THEN
    RAISE EXCEPTION 'mission_id_required';
  END IF;

  SELECT * INTO v_m FROM public.missions WHERE id = p_mission_id FOR UPDATE;
  IF v_m.id IS NULL THEN RAISE EXCEPTION 'mission_not_found'; END IF;

  IF v_m.state IS DISTINCT FROM 'delivered'::public.mission_state THEN
    RAISE EXCEPTION 'mission_not_delivered';
  END IF;

  IF v_m.courier_id IS NULL THEN
    RAISE EXCEPTION 'mission_no_courier';
  END IF;

  v_amount := COALESCE(v_m.estimated_earning_gnf, 0);
  IF v_amount <= 0 THEN
    RAISE EXCEPTION 'missing_earning_amount';
  END IF;

  v_ref := 'mission_earning:' || p_mission_id::text;

  -- Idempotency: return existing row.
  SELECT * INTO v_existing FROM public.wallet_transactions
    WHERE reference = v_ref LIMIT 1;
  IF v_existing.id IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  -- Ensure courier driver wallet exists.
  INSERT INTO public.wallets (owner_user_id, party_type)
    VALUES (v_m.courier_id, 'driver')
  ON CONFLICT (owner_user_id, party_type) DO NOTHING;
  SELECT id INTO v_courier_wallet FROM public.wallets
    WHERE owner_user_id = v_m.courier_id AND party_type = 'driver' LIMIT 1;
  IF v_courier_wallet IS NULL THEN
    RAISE EXCEPTION 'courier_wallet_missing';
  END IF;

  SELECT id INTO v_master_wallet FROM public.wallets
    WHERE party_type = 'master' AND owner_user_id IS NULL LIMIT 1;
  IF v_master_wallet IS NULL THEN
    RAISE EXCEPTION 'master_wallet_missing';
  END IF;

  -- Use the hardened transfer rail (idempotent on reference).
  v_tx := public.wallet_internal_transfer_v2(
    p_from_wallet_id => v_master_wallet,
    p_to_wallet_id   => v_courier_wallet,
    p_amount_gnf     => v_amount,
    p_reference      => v_ref,
    p_transfer_type  => 'mission_earning',
    p_description    => COALESCE(p_reason, 'Mission delivered courier earning'),
    p_source_module  => 'missions',
    p_source_id      => p_mission_id::text,
    p_metadata       => jsonb_build_object(
      'mission_id',        p_mission_id,
      'mission_type',      v_m.type::text,
      'courier_user_id',   v_m.courier_id,
      'earning_amount_gnf',v_amount,
      'ref_food_order_id', v_m.ref_food_order_id,
      'ref_market_order_id', v_m.ref_market_order_id,
      'ref_ride_id',       v_m.ref_ride_id,
      'created_by_function','wallet_credit_mission_earning'
    )
  );

  BEGIN
    INSERT INTO public.mission_events(mission_id, kind, payload)
    VALUES (p_mission_id, 'courier_earning_credited',
      jsonb_build_object('amount_gnf', v_amount, 'tx_id', v_tx.id, 'reference', v_ref));
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN v_tx;
END;
$function$;

REVOKE ALL ON FUNCTION public.wallet_credit_mission_earning(uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.wallet_credit_mission_earning(uuid, text) TO service_role;

-- 3) Patch courier delivery confirmations to trigger earning credit (idempotent,
--    error-tolerant so a credit failure cannot block delivery acknowledgement).
CREATE OR REPLACE FUNCTION public.mission_confirm_dropoff(_mission_id uuid)
RETURNS public.missions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE _uid uuid := auth.uid(); _m public.missions;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO _m FROM public.missions WHERE id = _mission_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mission_not_found'; END IF;
  IF _m.courier_id IS DISTINCT FROM _uid AND NOT public.is_any_admin(_uid) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  UPDATE public.missions
     SET state='delivered', dropoff_confirmed_at=now(), dropoff_confirmed_by=_uid
   WHERE id = _mission_id RETURNING * INTO _m;

  BEGIN
    PERFORM public.wallet_credit_mission_earning(_mission_id, 'mission_confirm_dropoff');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.mission_events(mission_id, kind, payload)
    VALUES (_mission_id, 'courier_earning_failed',
      jsonb_build_object('error', SQLERRM));
  END;
  RETURN _m;
END;
$function$;

CREATE OR REPLACE FUNCTION public.mission_confirm_dropoff_with_proof(
  _mission_id uuid, _photo_url text, _customer_code text
)
RETURNS public.missions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE _uid uuid := auth.uid(); _m public.missions;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF _photo_url IS NULL OR length(trim(_photo_url)) = 0 THEN RAISE EXCEPTION 'photo_required'; END IF;

  SELECT * INTO _m FROM public.missions WHERE id = _mission_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mission_not_found'; END IF;
  IF _m.courier_id IS DISTINCT FROM _uid AND NOT public.is_any_admin(_uid) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF _m.customer_handoff_code IS NOT NULL THEN
    IF _customer_code IS NULL OR _customer_code <> _m.customer_handoff_code THEN
      RAISE EXCEPTION 'invalid_customer_code';
    END IF;
  END IF;

  UPDATE public.missions
     SET state = 'delivered'::public.mission_state,
         dropoff_confirmed_at = now(),
         dropoff_confirmed_by = _uid,
         delivery_photo_url = _photo_url
   WHERE id = _mission_id
   RETURNING * INTO _m;

  INSERT INTO public.mission_events(mission_id, kind, payload)
  VALUES (_mission_id, 'dropoff_confirmed', jsonb_build_object('photo_url', _photo_url));

  BEGIN
    PERFORM public.wallet_credit_mission_earning(_mission_id, 'mission_confirm_dropoff_with_proof');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.mission_events(mission_id, kind, payload)
    VALUES (_mission_id, 'courier_earning_failed',
      jsonb_build_object('error', SQLERRM));
  END;
  RETURN _m;
END;
$function$;

CREATE OR REPLACE FUNCTION public.mission_set_state(_mission_id uuid, _state public.mission_state)
RETURNS public.missions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  _uid uuid := auth.uid();
  _m public.missions;
  _prev public.mission_state;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO _m FROM public.missions WHERE id = _mission_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mission_not_found'; END IF;
  IF _m.courier_id IS DISTINCT FROM _uid AND NOT public.is_any_admin(_uid) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF _state NOT IN ('heading_to_pickup','arrived_pickup','picked_up','heading_to_dropoff','arrived_dropoff','delivered') THEN
    RAISE EXCEPTION 'state_not_allowed';
  END IF;
  _prev := _m.state;
  UPDATE public.missions SET state = _state WHERE id = _mission_id RETURNING * INTO _m;

  IF _state = 'delivered'::public.mission_state
     AND _prev IS DISTINCT FROM 'delivered'::public.mission_state THEN
    BEGIN
      PERFORM public.wallet_credit_mission_earning(_mission_id, 'mission_set_state.delivered');
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO public.mission_events(mission_id, kind, payload)
      VALUES (_mission_id, 'courier_earning_failed',
        jsonb_build_object('error', SQLERRM));
    END;
  END IF;
  RETURN _m;
END;
$function$;

-- 4) Admin consistency helper: delivered missions without earning row.
CREATE OR REPLACE FUNCTION public.admin_preview_missing_mission_earnings()
RETURNS TABLE(
  mission_id uuid,
  mission_type text,
  courier_id uuid,
  delivered_at timestamptz,
  earning_amount_gnf bigint,
  eligible boolean,
  reason text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR NOT (
    public.has_role(v_uid, 'god_admin'::public.app_role)
    OR public.has_role(v_uid, 'finance_admin'::public.app_role)
    OR public.has_role(v_uid, 'admin'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'forbidden: admin role required';
  END IF;

  RETURN QUERY
  SELECT
    m.id,
    m.type::text,
    m.courier_id,
    m.dropoff_confirmed_at,
    COALESCE(m.estimated_earning_gnf, 0)::bigint,
    (m.courier_id IS NOT NULL AND COALESCE(m.estimated_earning_gnf,0) > 0) AS eligible,
    CASE
      WHEN m.courier_id IS NULL THEN 'no_courier'
      WHEN COALESCE(m.estimated_earning_gnf,0) <= 0 THEN 'missing_earning_amount'
      ELSE 'ok'
    END AS reason
  FROM public.missions m
  WHERE m.state = 'delivered'::public.mission_state
    AND NOT EXISTS (
      SELECT 1 FROM public.wallet_transactions wt
       WHERE wt.reference = 'mission_earning:' || m.id::text
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_preview_missing_mission_earnings()
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_preview_missing_mission_earnings()
  TO authenticated, service_role;
