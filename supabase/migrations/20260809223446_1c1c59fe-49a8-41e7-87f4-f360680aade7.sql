-- =========================================================
-- A. wallet_internal_transfer: service/internal only + stable reference
-- =========================================================
DROP FUNCTION IF EXISTS public.wallet_internal_transfer(uuid, text, uuid, text, bigint, text);

CREATE FUNCTION public.wallet_internal_transfer(
  p_from_user_id uuid,
  p_from_party_type text,
  p_to_user_id uuid,
  p_to_party_type text,
  p_amount_gnf bigint,
  p_description text,
  p_reference text DEFAULT NULL
) RETURNS public.wallet_transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_from_wallet public.wallets; v_to_wallet public.wallets; v_tx public.wallet_transactions;
  v_ref text;
BEGIN
  -- Trusted-caller contract: never directly reachable from PostgREST roles.
  IF current_user IN ('anon','authenticated') THEN
    RAISE EXCEPTION 'WALLET_INTERNAL_TRANSFER_INTERNAL_ONLY';
  END IF;

  IF p_amount_gnf <= 0 THEN RAISE EXCEPTION 'Amount must be positive'; END IF;

  v_ref := COALESCE(NULLIF(trim(p_reference), ''), 'itr:' || gen_random_uuid()::text);

  -- Idempotent replay on stable reference keys.
  SELECT * INTO v_tx FROM public.wallet_transactions WHERE reference = v_ref;
  IF v_tx.id IS NOT NULL THEN RETURN v_tx; END IF;

  SELECT * INTO v_from_wallet FROM public.wallets
    WHERE party_type = p_from_party_type::public.party_type
      AND ((p_from_user_id IS NULL AND owner_user_id IS NULL) OR owner_user_id = p_from_user_id)
    FOR UPDATE;
  IF v_from_wallet.id IS NULL THEN RAISE EXCEPTION 'Source wallet not found'; END IF;
  IF v_from_wallet.balance_gnf - v_from_wallet.held_gnf < p_amount_gnf THEN
    RAISE EXCEPTION 'Insufficient funds';
  END IF;

  SELECT * INTO v_to_wallet FROM public.wallets
    WHERE party_type = p_to_party_type::public.party_type
      AND ((p_to_user_id IS NULL AND owner_user_id IS NULL) OR owner_user_id = p_to_user_id)
    FOR UPDATE;
  IF v_to_wallet.id IS NULL THEN RAISE EXCEPTION 'Destination wallet not found'; END IF;

  UPDATE public.wallets SET balance_gnf = balance_gnf - p_amount_gnf WHERE id = v_from_wallet.id;
  UPDATE public.wallets SET balance_gnf = balance_gnf + p_amount_gnf WHERE id = v_to_wallet.id;

  INSERT INTO public.wallet_transactions (
    from_wallet_id, to_wallet_id, amount_gnf, type, status, description, reference
  ) VALUES (
    v_from_wallet.id, v_to_wallet.id, p_amount_gnf, 'transfer', 'completed', p_description, v_ref
  ) RETURNING * INTO v_tx;

  RETURN v_tx;
END $function$;

REVOKE ALL ON FUNCTION public.wallet_internal_transfer(uuid,text,uuid,text,bigint,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.wallet_internal_transfer(uuid,text,uuid,text,bigint,text,text) FROM anon;
REVOKE ALL ON FUNCTION public.wallet_internal_transfer(uuid,text,uuid,text,bigint,text,text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.wallet_internal_transfer(uuid,text,uuid,text,bigint,text,text) TO service_role;

-- =========================================================
-- B. ride_accept: internal helper only (offer contract enforced upstream)
-- =========================================================
CREATE OR REPLACE FUNCTION public.ride_accept(p_ride_id uuid)
RETURNS public.rides
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_claims text := current_setting('request.jwt.claims', true);
  v_ride public.rides;
  v_mtype text; v_pay text; v_snap jsonb; v_gate boolean;
BEGIN
  IF current_user IN ('anon','authenticated') THEN
    RAISE EXCEPTION 'RIDE_ACCEPT_INTERNAL_ONLY';
  END IF;
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id FOR UPDATE;
  IF v_ride.id IS NULL THEN RAISE EXCEPTION 'Ride not found'; END IF;
  IF v_ride.driver_id = v_uid AND v_ride.status = 'pending' THEN RETURN v_ride; END IF;
  IF v_ride.driver_id IS NOT NULL OR v_ride.status <> 'pending' THEN
    RAISE EXCEPTION 'Ride not available';
  END IF;

  -- Offer contract: the accepting driver must hold a live offer for this ride.
  IF NOT EXISTS (
    SELECT 1 FROM public.ride_offers o
     WHERE o.ride_id = p_ride_id AND o.driver_id = v_uid
       AND o.status = 'pending' AND o.expires_at >= now()
  ) THEN
    RAISE EXCEPTION 'OFFER_CONTRACT_REQUIRED';
  END IF;

  IF NOT public._driver_finance_eligible(v_uid) THEN RAISE EXCEPTION 'ACCOUNT_RESTRICTED'; END IF;

  v_mtype := public._ride_mission_type(v_ride.mode::text);
  v_pay   := public._ride_payment_mode(v_ride);
  v_gate  := public._finance_flag('driver_balance_gate_enabled');

  INSERT INTO public.wallets (owner_user_id, party_type)
  VALUES (v_uid, 'driver') ON CONFLICT (owner_user_id, party_type) DO NOTHING;

  IF v_gate THEN
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      PERFORM public.driver_mission_hold_place(
        p_mission_type := v_mtype, p_source_module := 'ride', p_source_id := p_ride_id,
        p_value_gnf := v_ride.fare_gnf, p_driver := v_uid, p_is_sandbox := false,
        p_kinds := ARRAY['commission'], p_fare_gnf := v_ride.fare_gnf,
        p_merchandise_subtotal_gnf := 0, p_delivery_fee_gnf := 0, p_declared_value_gnf := 0,
        p_payment_mode := CASE WHEN v_pay='chop_pay' THEN 'choppay' ELSE 'cash' END);
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config('request.jwt.claims', COALESCE(v_claims,''), true);
      RAISE;
    END;
    PERFORM set_config('request.jwt.claims', COALESCE(v_claims,''), true);
  END IF;

  v_snap := public.finance_policy_snapshot(v_mtype, now(), v_pay, v_ride.fare_gnf, 0, 0, 0, false);

  UPDATE public.rides
     SET driver_id = v_uid, status = 'pending',
         metadata = COALESCE(metadata,'{}'::jsonb) || jsonb_build_object(
           'phase', COALESCE(metadata->>'phase','approach'),
           'accepted_at', to_jsonb(now()),
           'payment_mode', v_pay, 'mission_type', v_mtype,
           'finance_snapshot', COALESCE(metadata->'finance_snapshot', v_snap)),
         updated_at = now()
   WHERE id = p_ride_id AND driver_id IS NULL AND status = 'pending'
   RETURNING * INTO v_ride;
  IF v_ride.id IS NULL THEN RAISE EXCEPTION 'Ride not available'; END IF;
  RETURN v_ride;
END $function$;

REVOKE ALL ON FUNCTION public.ride_accept(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ride_accept(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.ride_accept(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.ride_accept(uuid) TO service_role;

-- Driver-facing helper: accept the caller's live offer for a given ride.
CREATE OR REPLACE FUNCTION public.driver_offer_accept_for_ride(p_ride_id uuid)
RETURNS public.ride_offers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid(); v_offer_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT id INTO v_offer_id FROM public.ride_offers
   WHERE ride_id = p_ride_id AND driver_id = v_uid AND status IN ('pending','accepted')
   ORDER BY sent_at DESC LIMIT 1;
  IF v_offer_id IS NULL THEN RAISE EXCEPTION 'OFFER_CONTRACT_REQUIRED'; END IF;
  RETURN public.driver_offer_accept(v_offer_id);
END $function$;

REVOKE ALL ON FUNCTION public.driver_offer_accept_for_ride(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.driver_offer_accept_for_ride(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.driver_offer_accept_for_ride(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.driver_offer_accept_for_ride(uuid) TO service_role;

-- =========================================================
-- D. ride_dispatch: trusted/internal only + checked customer entry point
-- =========================================================
REVOKE ALL ON FUNCTION public.ride_dispatch(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ride_dispatch(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.ride_dispatch(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.ride_dispatch(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.ride_request_dispatch(p_ride_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid(); v_ride public.rides;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id;
  IF v_ride.id IS NULL THEN RAISE EXCEPTION 'Ride not found'; END IF;
  IF v_ride.client_id <> v_uid AND NOT public.has_role(v_uid,'admin') THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF v_ride.status <> 'pending' OR v_ride.driver_id IS NOT NULL THEN RETURN NULL; END IF;
  RETURN public.ride_dispatch(p_ride_id);
END $function$;

REVOKE ALL ON FUNCTION public.ride_request_dispatch(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ride_request_dispatch(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.ride_request_dispatch(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ride_request_dispatch(uuid) TO service_role;

-- =========================================================
-- C + E. ride_complete: custody state machine + no silent overdraft
-- =========================================================
CREATE OR REPLACE FUNCTION public.ride_complete(
  p_ride_id uuid, p_actual_fare_gnf bigint DEFAULT NULL::bigint, p_commission_bps integer DEFAULT NULL::integer)
RETURNS public.rides
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_claims text := current_setting('request.jwt.claims', true);
  v_ride public.rides;
  v_fare bigint; v_mtype text; v_pay text; v_snap jsonb;
  v_bps int; v_fixed bigint; v_commission bigint; v_driver_earn bigint;
  v_cap jsonb; v_payment public.wallet_transactions; v_commission_tx public.wallet_transactions;
  v_deficit bigint := 0; v_held bigint := 0; v_err text := NULL;
  v_is_admin boolean; v_phase text; v_confirmed_by text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id FOR UPDATE;
  IF v_ride.id IS NULL THEN RAISE EXCEPTION 'Ride not found'; END IF;

  v_is_admin := public.has_role(v_uid,'admin') OR public._is_god_admin();

  -- Replay is inert regardless of caller.
  IF v_ride.status = 'completed' THEN
    IF v_ride.driver_id IS NOT NULL THEN
      UPDATE public.driver_profiles SET presence='online', last_seen_at=now()
       WHERE user_id = v_ride.driver_id AND presence='on_trip';
    END IF;
    RETURN v_ride;
  END IF;
  IF v_ride.status = 'cancelled' THEN RAISE EXCEPTION 'Ride already cancelled'; END IF;

  -- Ordinary completion is DRIVER-ONLY for the assigned driver.
  IF NOT v_is_admin THEN
    IF v_ride.driver_id IS NULL OR v_ride.driver_id <> v_uid THEN
      RAISE EXCEPTION 'ONLY_ASSIGNED_DRIVER_CAN_COMPLETE';
    END IF;
    v_phase := COALESCE(v_ride.metadata->>'phase','');
    v_confirmed_by := COALESCE(v_ride.metadata->>'pickup_confirmed_by','');
    IF v_ride.status <> 'in_progress' OR v_phase <> 'on_trip' OR v_confirmed_by <> 'customer' THEN
      RAISE EXCEPTION 'PICKUP_CONFIRMATION_REQUIRED';
    END IF;
  END IF;

  v_mtype := public._ride_mission_type(v_ride.mode::text);
  v_pay   := public._ride_payment_mode(v_ride);

  IF p_actual_fare_gnf IS NOT NULL AND public._finance_privileged(v_uid) THEN
    v_fare := GREATEST(p_actual_fare_gnf, 0);
  ELSE v_fare := v_ride.fare_gnf; END IF;

  v_snap := COALESCE(v_ride.metadata->'finance_snapshot',
                     public.finance_policy_snapshot(v_mtype, now(), v_pay, v_fare, 0, 0, 0, false));
  v_bps   := COALESCE((v_snap->>'commission_bps')::int, 0);
  v_fixed := COALESCE((v_snap->>'fixed_commission_gnf')::bigint, 0);
  v_commission := (v_fare * v_bps) / 10000 + v_fixed;
  v_driver_earn := v_fare - v_commission;

  IF v_pay = 'chop_pay' AND v_ride.hold_tx_id IS NOT NULL THEN
    SELECT amount_gnf INTO v_held FROM public.wallet_transactions WHERE id = v_ride.hold_tx_id;
    -- No silent overdraft / no partial settlement pretending success.
    IF COALESCE(v_held,0) < v_fare THEN
      RAISE EXCEPTION 'SETTLEMENT_REQUIRED_INSUFFICIENT_HOLD: held=% fare=%', COALESCE(v_held,0), v_fare;
    END IF;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_ride.client_id), true);
    BEGIN
      SELECT * INTO v_payment FROM public.wallet_capture(
        p_hold_id := v_ride.hold_tx_id, p_to_user_id := v_ride.driver_id,
        p_to_party_type := (CASE WHEN v_ride.driver_id IS NOT NULL THEN 'driver' ELSE 'master' END)::public.party_type,
        p_actual_amount_gnf := v_fare,
        p_description := 'Course ' || v_ride.mode::text);
    EXCEPTION WHEN OTHERS THEN v_payment := NULL; v_err := 'capture:'||SQLERRM; END;

    IF v_ride.driver_id IS NOT NULL AND v_commission > 0 AND v_payment.id IS NOT NULL THEN
      PERFORM set_config('request.jwt.claims', '', true);
      BEGIN
        SELECT * INTO v_commission_tx FROM public.wallet_internal_transfer(
          p_from_user_id := v_ride.driver_id, p_from_party_type := 'driver',
          p_to_user_id := NULL, p_to_party_type := 'master',
          p_amount_gnf := v_commission, p_description := 'Commission course ' || v_ride.id::text,
          p_reference := 'ride:' || v_ride.id::text || ':commission');
      EXCEPTION WHEN OTHERS THEN v_commission_tx := NULL;
        v_err := COALESCE(v_err||' | ','')||'commission:'||SQLERRM; END;
    END IF;

    PERFORM set_config('request.jwt.claims', '', true);
    PERFORM public.driver_mission_hold_release('ride', p_ride_id, 'commission',
      'Commission prélevée sur le paiement Chop Pay');
    PERFORM set_config('request.jwt.claims', COALESCE(v_claims,''), true);
  ELSE
    PERFORM set_config('request.jwt.claims', '', true);
    v_cap := public.driver_mission_commission_capture('ride', p_ride_id, v_fare);
    PERFORM set_config('request.jwt.claims', COALESCE(v_claims,''), true);
    IF COALESCE(v_cap->>'status','') = 'captured' THEN
      v_deficit := GREATEST(v_commission - COALESCE((v_cap->>'captured_gnf')::bigint,0), 0);
    END IF;
  END IF;

  UPDATE public.rides SET
    status='completed', fare_gnf=v_fare, platform_fee_gnf=v_commission,
    driver_earning_gnf=v_driver_earn, payment_tx_id=COALESCE(v_payment.id, payment_tx_id),
    metadata = COALESCE(metadata,'{}'::jsonb) || jsonb_build_object(
      'final_fare_gnf', v_fare, 'commission_gnf', v_commission,
      'economic_driver_earning_gnf', v_driver_earn,
      'cash_collected_gnf', CASE WHEN v_pay='cash' THEN v_fare ELSE 0 END,
      'commission_deficit_gnf', v_deficit, 'settlement_error', v_err,
      'completed_by', CASE WHEN v_is_admin AND v_ride.driver_id IS DISTINCT FROM v_uid THEN 'admin_override' ELSE 'driver' END,
      'settlement', COALESCE(v_cap, jsonb_build_object('status','chop_pay_capture'))),
    completed_at = now()
  WHERE id = p_ride_id RETURNING * INTO v_ride;

  IF v_ride.driver_id IS NOT NULL THEN
    UPDATE public.driver_profiles SET presence='online', last_seen_at=now()
     WHERE user_id = v_ride.driver_id AND presence='on_trip';
  END IF;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (v_uid,'wallet',
    CASE WHEN v_is_admin AND v_ride.driver_id IS DISTINCT FROM v_uid THEN 'ride.settled.admin_override' ELSE 'ride.settled' END,
    'ride', v_ride.id::text,
    jsonb_build_object('fare_gnf',v_fare,'payment_mode',v_pay,'commission_gnf',v_commission,
                       'driver_earning_gnf',v_driver_earn,'deficit_gnf',v_deficit,'settlement',v_cap),
    'Règlement course ' || v_ride.mode::text);
  RETURN v_ride;
END $function$;

REVOKE ALL ON FUNCTION public.ride_complete(uuid,bigint,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ride_complete(uuid,bigint,integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.ride_complete(uuid,bigint,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ride_complete(uuid,bigint,integer) TO service_role;
