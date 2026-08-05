CREATE OR REPLACE FUNCTION public.driver_balance_summary(p_driver uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $function$
DECLARE
  v_caller uuid := auth.uid();
  v_target uuid := COALESCE(p_driver, auth.uid());
  v_w public.wallets;
  v_collateral bigint := 0; v_commission bigint := 0; v_fee bigint := 0; v_cash bigint := 0;
  v_promo jsonb; v_available bigint; v_promo_avail bigint;
BEGIN
  IF v_target IS NULL THEN RAISE EXCEPTION 'Driver required'; END IF;
  IF v_target <> COALESCE(v_caller, v_target) AND NOT public._finance_privileged(v_caller) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF v_caller IS NULL AND NOT public._finance_privileged(NULL) THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_w FROM public.wallets WHERE owner_user_id = v_target AND party_type = 'driver';

  SELECT COALESCE(SUM(amount_gnf) FILTER (WHERE kind = 'collateral'), 0),
         COALESCE(SUM(amount_gnf) FILTER (WHERE kind = 'commission'), 0),
         COALESCE(SUM(amount_gnf) FILTER (WHERE kind = 'platform_fee'), 0),
         COALESCE(SUM(amount_gnf) FILTER (WHERE kind = 'cash_funding'), 0)
    INTO v_collateral, v_commission, v_fee, v_cash
    FROM public.mission_financial_holds
   WHERE driver_user_id = v_target AND state IN ('held','frozen','partially_captured');

  v_promo := public.driver_promo_balance(v_target);
  v_promo_avail := COALESCE((v_promo->>'promo_available_gnf')::bigint, 0);
  v_available := GREATEST(COALESCE(v_w.balance_gnf, 0) - COALESCE(v_w.held_gnf, 0), 0);

  RETURN jsonb_build_object(
    'wallet_id', v_w.id,
    'balance_gnf', COALESCE(v_w.balance_gnf, 0),
    'held_gnf', COALESCE(v_w.held_gnf, 0),
    'available_gnf', v_available,
    'promo_remaining_gnf', (v_promo->>'promo_remaining_gnf')::bigint,
    'promo_held_gnf', (v_promo->>'promo_held_gnf')::bigint,
    'promo_available_gnf', v_promo_avail,
    'unrestricted_available_gnf', GREATEST(v_available - v_promo_avail, 0),
    'withdrawable_gnf', GREATEST(v_available - v_promo_avail, 0),
    'collateral_held_gnf', v_collateral,
    'commission_held_gnf', v_commission,
    'platform_fee_held_gnf', v_fee,
    'cash_funding_held_gnf', v_cash,
    'status', COALESCE(v_w.status::text, 'active'));
END;
$function$;

-- Trusted server context may drive mission holds.
CREATE OR REPLACE FUNCTION public.driver_payout_hold_place(
  p_request_id uuid, p_driver uuid, p_amount_gnf bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid(); v_w public.wallets; v_promo bigint; v_withdrawable bigint; v_key text;
BEGIN
  IF NOT public._finance_privileged(v_caller) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF EXISTS (SELECT 1 FROM public.mission_financial_holds
              WHERE source_module = 'cashout' AND source_id = p_request_id AND kind = 'cashout') THEN
    RETURN jsonb_build_object('status','already_held');
  END IF;

  SELECT * INTO v_w FROM public.wallets
   WHERE owner_user_id = p_driver AND party_type = 'driver' FOR UPDATE;
  IF v_w.id IS NULL THEN RAISE EXCEPTION 'Driver wallet not found'; END IF;

  v_promo := COALESCE((public.driver_promo_balance(p_driver)->>'promo_available_gnf')::bigint, 0);
  v_withdrawable := GREATEST(v_w.balance_gnf - v_w.held_gnf - v_promo, 0);
  IF v_withdrawable < p_amount_gnf THEN
    RAISE EXCEPTION 'INSUFFICIENT_WITHDRAWABLE_BALANCE'
      USING DETAIL = format('withdrawable=%s requested=%s restricted=%s', v_withdrawable, p_amount_gnf, v_promo);
  END IF;

  v_key := 'cashout-hold:' || p_request_id::text;
  UPDATE public.wallets SET held_gnf = held_gnf + p_amount_gnf, updated_at = now() WHERE id = v_w.id;

  PERFORM public._ledger_post(v_key, 'cashout', p_request_id, 'payout_hold',
    jsonb_build_array(
      jsonb_build_object('account','L_DRIVER_UNRESTRICTED','amount_gnf',p_amount_gnf,
                         'party_type','driver','party_user_id',p_driver,'memo','payout reserved'),
      jsonb_build_object('account','L_HOLD_CASHOUT','amount_gnf',-p_amount_gnf,
                         'party_type','driver','party_user_id',p_driver,'memo','pending payout')),
    NULL, v_caller, jsonb_build_object('restricted_excluded_gnf', v_promo), false);

  INSERT INTO public.mission_financial_holds
    (driver_user_id, party_type, party_user_id, mission_type, source_module, source_id, kind,
     amount_gnf, unrestricted_gnf, policy_snapshot, basis_value_gnf, journal_key)
  VALUES (p_driver,'driver',p_driver,'ride','cashout',p_request_id,'cashout',
          p_amount_gnf, p_amount_gnf, jsonb_build_object('restricted_excluded_gnf', v_promo),
          p_amount_gnf, v_key);

  RETURN jsonb_build_object('status','held','amount_gnf',p_amount_gnf,'restricted_excluded_gnf',v_promo);
END;
$$;

-- Relax the "must be signed in" guard on the mission-hold family so trusted
-- server code can drive them; end users remain scoped to themselves.
CREATE OR REPLACE FUNCTION public.driver_mission_hold_place(
  p_mission_type text, p_source_module text, p_source_id uuid,
  p_value_gnf bigint DEFAULT 0, p_driver uuid DEFAULT NULL, p_is_sandbox boolean DEFAULT false,
  p_kinds text[] DEFAULT NULL, p_fare_gnf bigint DEFAULT NULL,
  p_merchandise_subtotal_gnf bigint DEFAULT NULL, p_delivery_fee_gnf bigint DEFAULT NULL,
  p_declared_value_gnf bigint DEFAULT NULL, p_payment_mode text DEFAULT 'choppay')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_driver uuid := COALESCE(p_driver, auth.uid());
  v_req jsonb; v_wallet public.wallets; v_avail bigint; v_total bigint := 0; v_existing int;
  v_kind text; v_amount bigint; v_alloc jsonb; v_u bigint; v_p bigint;
  v_tx public.wallet_transactions; v_key text; v_ids jsonb := '[]'::jsonb;
  v_kinds text[] := COALESCE(p_kinds, ARRAY['commission','collateral']);
BEGIN
  IF v_driver IS NULL THEN RAISE EXCEPTION 'Driver required'; END IF;
  IF v_driver <> COALESCE(v_caller, v_driver) AND NOT public._finance_privileged(v_caller) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF public.is_user_banned(v_driver) OR public.is_user_frozen(v_driver) THEN
    RAISE EXCEPTION 'ACCOUNT_RESTRICTED';
  END IF;

  SELECT count(*) INTO v_existing FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id AND kind = ANY(v_kinds);
  IF v_existing > 0 THEN
    RETURN jsonb_build_object('status', 'already_held', 'source_id', p_source_id);
  END IF;

  v_req := public.finance_mission_requirement_v2(
    p_mission_type,
    COALESCE(p_fare_gnf, CASE WHEN p_mission_type IN ('ride','bonbonna') THEN p_value_gnf ELSE 0 END),
    COALESCE(p_merchandise_subtotal_gnf, CASE WHEN p_mission_type IN ('repas','marche') THEN p_value_gnf ELSE 0 END),
    COALESCE(p_delivery_fee_gnf, 0),
    COALESCE(p_declared_value_gnf, CASE WHEN p_mission_type = 'envoyer' THEN p_value_gnf ELSE 0 END),
    COALESCE(p_payment_mode, 'choppay'));

  IF (v_req->>'declared_value_exceeds_cap')::boolean THEN
    RAISE EXCEPTION 'DECLARED_VALUE_ABOVE_CAP' USING DETAIL = format('max=%s', v_req->>'max_declared_value_gnf');
  END IF;

  INSERT INTO public.wallets (owner_user_id, party_type) VALUES (v_driver, 'driver')
  ON CONFLICT (owner_user_id, party_type) DO NOTHING;
  SELECT * INTO v_wallet FROM public.wallets
   WHERE owner_user_id = v_driver AND party_type = 'driver' FOR UPDATE;
  IF v_wallet.status <> 'active' THEN RAISE EXCEPTION 'Wallet not active'; END IF;

  v_avail := GREATEST(v_wallet.balance_gnf - v_wallet.held_gnf, 0);
  IF v_avail < (v_req->>'required_available_gnf')::bigint THEN
    RAISE EXCEPTION 'INSUFFICIENT_DRIVER_BALANCE'
      USING DETAIL = format('required=%s available=%s', v_req->>'required_available_gnf', v_avail);
  END IF;

  FOREACH v_kind IN ARRAY v_kinds LOOP
    v_amount := CASE v_kind
      WHEN 'commission'   THEN (v_req->>'commission_gnf')::bigint
      WHEN 'collateral'   THEN (v_req->>'collateral_gnf')::bigint
      WHEN 'platform_fee' THEN (v_req->>'platform_fee_gnf')::bigint
      WHEN 'cash_funding' THEN (v_req->>'cash_funding_gnf')::bigint
      ELSE 0 END;
    CONTINUE WHEN COALESCE(v_amount, 0) <= 0;

    v_alloc := public.driver_funding_allocate(v_driver, v_amount, v_kind);
    IF NOT (v_alloc->>'ok')::boolean THEN
      RAISE EXCEPTION '%', COALESCE(v_alloc->>'reason', 'INSUFFICIENT_DRIVER_BALANCE');
    END IF;
    v_u := (v_alloc->>'unrestricted_gnf')::bigint;
    v_p := (v_alloc->>'promo_gnf')::bigint;
    v_key := format('mfh:%s:%s:%s', p_source_module, p_source_id, v_kind);

    INSERT INTO public.wallet_transactions
      (reference, type, status, amount_gnf, from_wallet_id, related_user_id,
       related_entity, description, metadata)
    VALUES (v_key, 'hold', 'pending', v_amount, v_wallet.id, v_driver,
       p_source_module || ':' || p_source_id::text,
       CASE v_kind
         WHEN 'commission'   THEN 'Réserve de commission mission'
         WHEN 'collateral'   THEN 'Caution mission'
         WHEN 'platform_fee' THEN 'Frais de service CHOPCHOP'
         ELSE 'Avance marchandise (commande espèces)' END,
       jsonb_build_object('mission_type', p_mission_type, 'kind', v_kind,
                          'is_sandbox', p_is_sandbox, 'unrestricted_gnf', v_u, 'promo_gnf', v_p))
    RETURNING * INTO v_tx;

    UPDATE public.wallets SET held_gnf = held_gnf + v_amount, updated_at = now() WHERE id = v_wallet.id;

    PERFORM public._ledger_post(
      v_key, p_source_module, p_source_id, 'hold_' || v_kind,
      jsonb_build_array(
        jsonb_build_object('account','L_DRIVER_UNRESTRICTED','amount_gnf',v_u,
                           'party_type','driver','party_user_id',v_driver,'memo','hold from unrestricted'),
        jsonb_build_object('account','L_DRIVER_PROMO','amount_gnf',v_p,
                           'party_type','driver','party_user_id',v_driver,'memo','hold from restricted credit'),
        jsonb_build_object('account',public._hold_account(v_kind),'amount_gnf',-v_amount,
                           'party_type','driver','party_user_id',v_driver,'memo',v_kind||' hold')),
      p_mission_type, v_caller, COALESCE(v_req->'policy_snapshot','{}'::jsonb), p_is_sandbox);

    INSERT INTO public.mission_financial_holds
      (driver_user_id, party_type, party_user_id, mission_type, source_module, source_id, kind,
       amount_gnf, unrestricted_gnf, promo_gnf, hold_tx_id, policy_id,
       policy_snapshot, basis_value_gnf, is_sandbox, journal_key)
    VALUES (v_driver, 'driver', v_driver, p_mission_type, p_source_module, p_source_id, v_kind,
       v_amount, v_u, v_p, v_tx.id, (v_req->>'policy_id')::uuid,
       COALESCE(v_req->'policy_snapshot', '{}'::jsonb),
       CASE v_kind
         WHEN 'commission' THEN (v_req->>'commission_basis_gnf')::bigint
         WHEN 'collateral' THEN (v_req->>'collateral_basis_gnf')::bigint
         WHEN 'platform_fee' THEN (v_req->>'fee_basis_gnf')::bigint
         ELSE (v_req->>'merchandise_subtotal_gnf')::bigint END,
       p_is_sandbox, v_key);

    v_total := v_total + v_amount;
    v_ids := v_ids || jsonb_build_object('kind', v_kind, 'amount_gnf', v_amount,
                                         'unrestricted_gnf', v_u, 'promo_gnf', v_p);
  END LOOP;

  RETURN jsonb_build_object('status','held','total_gnf',v_total,'holds',v_ids,'requirement',v_req);
END;
$$;

CREATE OR REPLACE FUNCTION public.driver_mission_hold_release(
  p_source_module text, p_source_id uuid, p_kind text DEFAULT NULL, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid(); v_h public.mission_financial_holds;
  v_released bigint := 0; v_wallet_id uuid; v_open bigint; v_u bigint; v_p bigint;
BEGIN
  FOR v_h IN
    SELECT * FROM public.mission_financial_holds
     WHERE source_module = p_source_module AND source_id = p_source_id
       AND (p_kind IS NULL OR kind = p_kind)
       AND state IN ('held','partially_captured','frozen')
     ORDER BY created_at FOR UPDATE
  LOOP
    IF v_h.driver_user_id <> COALESCE(v_caller, v_h.driver_user_id)
       AND NOT public._finance_privileged(v_caller)
       AND NOT public.has_admin_role(v_caller, 'operations_admin'::admin_role) THEN
      RAISE EXCEPTION 'Not authorized';
    END IF;

    v_open := v_h.amount_gnf - v_h.captured_gnf - v_h.released_gnf;
    CONTINUE WHEN v_open <= 0;

    v_p := LEAST(v_open, GREATEST(v_h.promo_gnf - LEAST(v_h.captured_gnf, v_h.promo_gnf), 0));
    v_u := v_open - v_p;

    SELECT id INTO v_wallet_id FROM public.wallets
     WHERE owner_user_id = v_h.driver_user_id AND party_type = 'driver' FOR UPDATE;

    UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - v_open, 0), updated_at = now()
     WHERE id = v_wallet_id;
    UPDATE public.wallet_transactions SET status = 'cancelled', completed_at = now()
     WHERE id = v_h.hold_tx_id AND status = 'pending';

    PERFORM public._ledger_post(
      format('mfh-release:%s:%s:%s', p_source_module, p_source_id, v_h.kind),
      p_source_module, p_source_id, 'release_' || v_h.kind,
      jsonb_build_array(
        jsonb_build_object('account', public._hold_account(v_h.kind), 'amount_gnf', v_open,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','release hold'),
        jsonb_build_object('account','L_DRIVER_PROMO','amount_gnf',-v_p,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','restored to restricted credit'),
        jsonb_build_object('account','L_DRIVER_UNRESTRICTED','amount_gnf',-v_u,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','restored to unrestricted')),
      v_h.mission_type, v_caller, v_h.policy_snapshot, v_h.is_sandbox, p_reason);

    UPDATE public.mission_financial_holds
       SET state = 'released', released_gnf = released_gnf + v_open,
           reason = COALESCE(p_reason, reason), resolved_at = now(), resolved_by = v_caller
     WHERE id = v_h.id;

    v_released := v_released + v_open;
  END LOOP;

  RETURN jsonb_build_object('status', 'released', 'released_gnf', v_released);
END;
$$;