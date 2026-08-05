-- ---------- account map for hold kinds ----------
CREATE OR REPLACE FUNCTION public._hold_account(p_kind text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT CASE p_kind
    WHEN 'commission'          THEN 'L_HOLD_COMMISSION'
    WHEN 'collateral'          THEN 'L_HOLD_COLLATERAL'
    WHEN 'cash_funding'        THEN 'L_HOLD_CASH_FUNDING'
    WHEN 'platform_fee'        THEN 'L_HOLD_PLATFORM_FEE'
    WHEN 'customer_payment'    THEN 'L_CUSTOMER_HOLD'
    WHEN 'cashout'             THEN 'L_HOLD_CASHOUT'
    WHEN 'merchant_settlement' THEN 'L_HOLD_SETTLEMENT'
    WHEN 'claims_reserve'      THEN 'L_CLAIMS_RESERVE'
  END;
$$;

CREATE OR REPLACE FUNCTION public._capture_revenue_account(p_kind text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT CASE p_kind
    WHEN 'commission'   THEN 'R_COMMISSION'
    WHEN 'platform_fee' THEN 'R_TRANSACTION_FEE'
    WHEN 'collateral'   THEN 'R_COLLATERAL_LOSS'
    ELSE 'EQ_PLATFORM'
  END;
$$;

-- =====================================================================
-- Authoritative requirement resolver with DISTINCT basis components.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.finance_mission_requirement_v2(
  p_mission_type text,
  p_fare_gnf bigint DEFAULT 0,
  p_merchandise_subtotal_gnf bigint DEFAULT 0,
  p_delivery_fee_gnf bigint DEFAULT 0,
  p_declared_value_gnf bigint DEFAULT 0,
  p_payment_mode text DEFAULT 'cash'
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_p public.finance_policies;
  v_fare bigint := GREATEST(COALESCE(p_fare_gnf,0),0);
  v_sub  bigint := GREATEST(COALESCE(p_merchandise_subtotal_gnf,0),0);
  v_del  bigint := GREATEST(COALESCE(p_delivery_fee_gnf,0),0);
  v_dec  bigint := GREATEST(COALESCE(p_declared_value_gnf,0),0);
  v_mode text := COALESCE(p_payment_mode,'cash');
  v_comm_basis bigint := 0;
  v_col_basis  bigint := 0;
  v_fee_basis  bigint := 0;
  v_commission bigint := 0;
  v_collateral bigint := 0;
  v_fee bigint := 0;
  v_cash bigint := 0;
  v_capped boolean := false;
BEGIN
  SELECT * INTO v_p FROM public.finance_policy_current(p_mission_type);
  IF v_p.id IS NULL THEN
    RETURN jsonb_build_object('has_policy', false, 'mission_type', p_mission_type,
      'commission_gnf',0,'collateral_gnf',0,'platform_fee_gnf',0,'cash_funding_gnf',0,
      'min_balance_gnf',0,'required_hold_gnf',0,'required_available_gnf',0,
      'declared_value_exceeds_cap', false);
  END IF;

  -- Commission basis: fare for ride/Bonbonna, delivery fee for delivery missions.
  v_comm_basis := CASE WHEN p_mission_type IN ('ride','bonbonna') THEN v_fare ELSE v_del END;

  v_col_basis := CASE v_p.collateral_basis
    WHEN 'fare' THEN v_fare
    WHEN 'merchandise_subtotal' THEN v_sub
    WHEN 'declared_value' THEN v_dec
    ELSE CASE WHEN p_mission_type = 'envoyer' THEN v_dec
              WHEN p_mission_type IN ('repas','marche') THEN v_sub
              ELSE v_fare END
  END;

  v_fee_basis := CASE v_p.fee_basis
    WHEN 'fare' THEN v_fare
    WHEN 'merchandise_subtotal' THEN v_sub
    WHEN 'delivery_fee' THEN v_del
    WHEN 'declared_value' THEN v_dec
    WHEN 'order_total' THEN v_sub + v_del
    WHEN 'transfer_amount' THEN v_fare
    ELSE 0
  END;

  IF p_mission_type = 'envoyer' AND v_p.max_declared_value_gnf IS NOT NULL
     AND v_dec > v_p.max_declared_value_gnf THEN
    v_capped := true;
  END IF;

  v_commission := (v_comm_basis * v_p.commission_bps) / 10000 + v_p.fixed_commission_gnf;
  v_fee := CASE WHEN v_p.fee_basis = 'none' THEN 0
                ELSE (v_fee_basis * v_p.transaction_fee_bps) / 10000 END;

  IF v_p.collateral_mode = 'fixed' THEN
    v_collateral := v_p.collateral_fixed_gnf;
  ELSIF v_p.collateral_mode = 'percentage' THEN
    v_collateral := (v_col_basis * v_p.collateral_pct_bps) / 10000;
  END IF;
  IF v_p.collateral_mode <> 'none' THEN
    v_collateral := GREATEST(v_collateral, v_p.collateral_min_gnf);
    IF v_p.collateral_max_gnf IS NOT NULL THEN
      v_collateral := LEAST(v_collateral, v_p.collateral_max_gnf);
    END IF;
  END IF;

  -- Chop Pay orders use collateral; CASH orders use 100% merchandise funding.
  IF v_p.cash_funding_mode = 'merchandise_subtotal' AND v_mode = 'cash' THEN
    v_cash := (v_sub * v_p.cash_funding_pct_bps) / 10000;
    IF v_p.cash_funding_max_gnf IS NOT NULL THEN
      v_cash := LEAST(v_cash, v_p.cash_funding_max_gnf);
    END IF;
    v_collateral := 0;  -- funding replaces collateral on cash orders
  END IF;

  RETURN jsonb_build_object(
    'has_policy', true,
    'policy_id', v_p.id,
    'mission_type', p_mission_type,
    'payment_mode', v_mode,
    'fare_gnf', v_fare,
    'merchandise_subtotal_gnf', v_sub,
    'delivery_fee_gnf', v_del,
    'declared_value_gnf', v_dec,
    'commission_basis_gnf', v_comm_basis,
    'collateral_basis_gnf', v_col_basis,
    'fee_basis_gnf', v_fee_basis,
    'commission_gnf', v_commission,
    'collateral_gnf', v_collateral,
    'platform_fee_gnf', v_fee,
    'cash_funding_gnf', v_cash,
    'fee_basis', v_p.fee_basis,
    'collateral_basis', v_p.collateral_basis,
    'cancel_basis', v_p.cancel_basis,
    'transaction_fee_bps', v_p.transaction_fee_bps,
    'cancel_before_dispatch_bps', v_p.cancel_before_dispatch_bps,
    'cancel_after_dispatch_bps', v_p.cancel_after_dispatch_bps,
    'max_declared_value_gnf', v_p.max_declared_value_gnf,
    'declared_value_exceeds_cap', v_capped,
    'min_balance_gnf', v_p.min_driver_balance_gnf,
    'required_hold_gnf', v_commission + v_collateral + v_cash,
    'required_available_gnf', GREATEST(v_commission + v_collateral + v_cash, v_p.min_driver_balance_gnf),
    'require_collateral_before_offer', v_p.require_collateral_before_offer,
    'policy_snapshot', jsonb_build_object(
      'policy_id', v_p.id,
      'commission_bps', v_p.commission_bps,
      'fixed_commission_gnf', v_p.fixed_commission_gnf,
      'collateral_mode', v_p.collateral_mode,
      'collateral_basis', v_p.collateral_basis,
      'collateral_pct_bps', v_p.collateral_pct_bps,
      'collateral_min_gnf', v_p.collateral_min_gnf,
      'collateral_max_gnf', v_p.collateral_max_gnf,
      'transaction_fee_bps', v_p.transaction_fee_bps,
      'fee_basis', v_p.fee_basis,
      'cash_funding_mode', v_p.cash_funding_mode,
      'cash_funding_pct_bps', v_p.cash_funding_pct_bps,
      'cancel_basis', v_p.cancel_basis,
      'cancel_before_dispatch_bps', v_p.cancel_before_dispatch_bps,
      'cancel_after_dispatch_bps', v_p.cancel_after_dispatch_bps,
      'max_declared_value_gnf', v_p.max_declared_value_gnf,
      'min_driver_balance_gnf', v_p.min_driver_balance_gnf,
      'effective_from', v_p.effective_from));
END;
$$;

GRANT EXECUTE ON FUNCTION public.finance_mission_requirement_v2(text,bigint,bigint,bigint,bigint,text) TO authenticated, service_role;

-- Backwards-compatible single-value wrapper: routes the legacy value into the
-- correct basis component for the mission type (no more ambiguous sharing).
CREATE OR REPLACE FUNCTION public.finance_mission_requirement(p_mission_type text, p_value_gnf bigint DEFAULT 0)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.finance_mission_requirement_v2(
    p_mission_type,
    CASE WHEN p_mission_type IN ('ride','bonbonna') THEN GREATEST(COALESCE(p_value_gnf,0),0) ELSE 0 END,
    CASE WHEN p_mission_type IN ('repas','marche')  THEN GREATEST(COALESCE(p_value_gnf,0),0) ELSE 0 END,
    0,
    CASE WHEN p_mission_type = 'envoyer'            THEN GREATEST(COALESCE(p_value_gnf,0),0) ELSE 0 END,
    'choppay');
$$;

-- =====================================================================
-- Driver hold placement (journal-backed, source-attributed)
-- =====================================================================
DROP FUNCTION IF EXISTS public.driver_mission_hold_place(text,text,uuid,bigint,uuid,boolean,text[]);

CREATE OR REPLACE FUNCTION public.driver_mission_hold_place(
  p_mission_type text,
  p_source_module text,
  p_source_id uuid,
  p_value_gnf bigint DEFAULT 0,
  p_driver uuid DEFAULT NULL,
  p_is_sandbox boolean DEFAULT false,
  p_kinds text[] DEFAULT NULL,
  p_fare_gnf bigint DEFAULT NULL,
  p_merchandise_subtotal_gnf bigint DEFAULT NULL,
  p_delivery_fee_gnf bigint DEFAULT NULL,
  p_declared_value_gnf bigint DEFAULT NULL,
  p_payment_mode text DEFAULT 'choppay'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_driver uuid := COALESCE(p_driver, auth.uid());
  v_req jsonb;
  v_wallet public.wallets;
  v_avail bigint;
  v_total bigint := 0;
  v_existing int;
  v_kind text;
  v_amount bigint;
  v_alloc jsonb;
  v_u bigint; v_p bigint;
  v_tx public.wallet_transactions;
  v_key text;
  v_ids jsonb := '[]'::jsonb;
  v_kinds text[] := COALESCE(p_kinds, ARRAY['commission','collateral']);
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF v_driver <> v_caller AND NOT public.is_god_admin(v_caller)
     AND NOT public.has_admin_role(v_caller, 'finance_admin'::admin_role) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF public.is_user_banned(v_driver) OR public.is_user_frozen(v_driver) THEN
    RAISE EXCEPTION 'ACCOUNT_RESTRICTED';
  END IF;

  SELECT count(*) INTO v_existing FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND kind = ANY(v_kinds);
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
    RAISE EXCEPTION 'DECLARED_VALUE_ABOVE_CAP'
      USING DETAIL = format('max=%s', v_req->>'max_declared_value_gnf');
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
    VALUES
      (v_key, 'hold', 'pending', v_amount, v_wallet.id, v_driver,
       p_source_module || ':' || p_source_id::text,
       CASE v_kind
         WHEN 'commission'   THEN 'Réserve de commission mission'
         WHEN 'collateral'   THEN 'Caution mission'
         WHEN 'platform_fee' THEN 'Frais de service CHOPCHOP'
         ELSE 'Avance marchandise (commande espèces)' END,
       jsonb_build_object('mission_type', p_mission_type, 'kind', v_kind,
                          'is_sandbox', p_is_sandbox,
                          'unrestricted_gnf', v_u, 'promo_gnf', v_p))
    RETURNING * INTO v_tx;

    UPDATE public.wallets SET held_gnf = held_gnf + v_amount, updated_at = now()
     WHERE id = v_wallet.id;

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
    VALUES
      (v_driver, 'driver', v_driver, p_mission_type, p_source_module, p_source_id, v_kind,
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

  RETURN jsonb_build_object('status', 'held', 'total_gnf', v_total, 'holds', v_ids,
                            'requirement', v_req);
END;
$$;

-- =====================================================================
-- Release (returns each amount to its EXACT original bucket)
-- =====================================================================
CREATE OR REPLACE FUNCTION public.driver_mission_hold_release(
  p_source_module text, p_source_id uuid, p_kind text DEFAULT NULL, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_h public.mission_financial_holds;
  v_released bigint := 0;
  v_wallet_id uuid;
  v_open bigint; v_u bigint; v_p bigint;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  FOR v_h IN
    SELECT * FROM public.mission_financial_holds
     WHERE source_module = p_source_module AND source_id = p_source_id
       AND (p_kind IS NULL OR kind = p_kind)
       AND state IN ('held','partially_captured')
     ORDER BY created_at
     FOR UPDATE
  LOOP
    IF v_h.driver_user_id <> v_caller
       AND NOT public.is_god_admin(v_caller)
       AND NOT public.has_admin_role(v_caller, 'finance_admin'::admin_role)
       AND NOT public.has_admin_role(v_caller, 'operations_admin'::admin_role) THEN
      RAISE EXCEPTION 'Not authorized';
    END IF;

    v_open := v_h.amount_gnf - v_h.captured_gnf - v_h.released_gnf;
    CONTINUE WHEN v_open <= 0;

    -- Deterministic source attribution: promo is restored first so restricted
    -- value never silently becomes unrestricted.
    v_p := LEAST(v_open, GREATEST(v_h.promo_gnf - (v_h.captured_gnf * v_h.promo_gnf) / GREATEST(v_h.amount_gnf,1), 0));
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
           reason = COALESCE(p_reason, reason),
           resolved_at = now(), resolved_by = v_caller
     WHERE id = v_h.id;

    v_released := v_released + v_open;
  END LOOP;

  RETURN jsonb_build_object('status', 'released', 'released_gnf', v_released);
END;
$$;

-- =====================================================================
-- Commission capture (partial capture + excess release, journal-backed)
-- =====================================================================
CREATE OR REPLACE FUNCTION public.driver_mission_commission_capture(
  p_source_module text, p_source_id uuid, p_final_value_gnf bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_h public.mission_financial_holds;
  v_snap jsonb;
  v_due bigint; v_capture bigint; v_excess bigint;
  v_cp bigint := 0; v_cu bigint := 0; v_rp bigint := 0; v_ru bigint := 0;
  v_dw public.wallets; v_master public.wallets; v_tx public.wallet_transactions;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_h FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id AND kind = 'commission'
   FOR UPDATE;
  IF v_h.id IS NULL THEN RETURN jsonb_build_object('status','no_hold','captured_gnf',0); END IF;
  IF v_h.state <> 'held' THEN
    RETURN jsonb_build_object('status','already_resolved','captured_gnf',v_h.captured_gnf);
  END IF;

  v_snap := v_h.policy_snapshot;
  v_due := (GREATEST(COALESCE(p_final_value_gnf,0),0) * COALESCE((v_snap->>'commission_bps')::int,0)) / 10000
           + COALESCE((v_snap->>'fixed_commission_gnf')::bigint,0);
  v_capture := LEAST(v_due, v_h.amount_gnf);
  v_excess := v_h.amount_gnf - v_capture;

  -- Source attribution: promotional credit is consumed first (canonical waterfall).
  v_cp := LEAST(v_h.promo_gnf, v_capture);
  v_cu := v_capture - v_cp;
  v_rp := v_h.promo_gnf - v_cp;
  v_ru := v_excess - v_rp;

  SELECT * INTO v_dw FROM public.wallets
   WHERE owner_user_id = v_h.driver_user_id AND party_type = 'driver' FOR UPDATE;
  SELECT * INTO v_master FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;

  UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - v_h.amount_gnf, 0), updated_at = now()
   WHERE id = v_dw.id;

  IF v_capture > 0 THEN
    UPDATE public.wallets SET balance_gnf = balance_gnf - v_capture, updated_at = now() WHERE id = v_dw.id;
    IF v_master.id IS NOT NULL THEN
      UPDATE public.wallets SET balance_gnf = balance_gnf + v_capture, updated_at = now() WHERE id = v_master.id;
    END IF;
    IF v_cp > 0 THEN PERFORM public._promo_consume(v_h.driver_user_id, v_cp); END IF;
  END IF;

  INSERT INTO public.wallet_transactions
    (reference, type, status, amount_gnf, from_wallet_id, to_wallet_id, related_user_id,
     related_entity, description, metadata, completed_at)
  VALUES
    (format('mfh-capture:%s:%s', p_source_module, p_source_id), 'commission', 'completed',
     GREATEST(v_capture,1), v_dw.id, v_master.id, v_h.driver_user_id,
     p_source_module || ':' || p_source_id::text, 'Commission CHOPCHOP',
     jsonb_build_object('mission_type', v_h.mission_type, 'final_value_gnf', p_final_value_gnf,
                        'reserved_gnf', v_h.amount_gnf, 'captured_gnf', v_capture,
                        'released_excess_gnf', v_excess, 'promo_consumed_gnf', v_cp,
                        'unrestricted_consumed_gnf', v_cu, 'is_sandbox', v_h.is_sandbox), now())
  RETURNING * INTO v_tx;

  UPDATE public.wallet_transactions SET status = 'completed', completed_at = now()
   WHERE id = v_h.hold_tx_id AND status = 'pending';

  IF v_capture > 0 THEN
    PERFORM public._ledger_post(
      format('mfh-capture:%s:%s:commission', p_source_module, p_source_id),
      p_source_module, p_source_id, 'capture_commission',
      jsonb_build_array(
        jsonb_build_object('account','L_HOLD_COMMISSION','amount_gnf',v_capture,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','consume commission hold'),
        jsonb_build_object('account','R_COMMISSION','amount_gnf',-v_capture,'memo','commission revenue')),
      v_h.mission_type, v_caller, v_snap, v_h.is_sandbox);
  END IF;

  IF v_excess > 0 THEN
    PERFORM public._ledger_post(
      format('mfh-release:%s:%s:commission', p_source_module, p_source_id),
      p_source_module, p_source_id, 'release_commission',
      jsonb_build_array(
        jsonb_build_object('account','L_HOLD_COMMISSION','amount_gnf',v_excess,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','release excess reserve'),
        jsonb_build_object('account','L_DRIVER_PROMO','amount_gnf',-v_rp,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','restored to restricted credit'),
        jsonb_build_object('account','L_DRIVER_UNRESTRICTED','amount_gnf',-v_ru,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','restored to unrestricted')),
      v_h.mission_type, v_caller, v_snap, v_h.is_sandbox);
  END IF;

  UPDATE public.mission_financial_holds
     SET state = 'captured', captured_gnf = v_capture, released_gnf = v_excess,
         resolution_tx_id = v_tx.id, resolved_at = now(), resolved_by = v_caller
   WHERE id = v_h.id;

  RETURN jsonb_build_object('status','captured','captured_gnf',v_capture,
                            'promo_consumed_gnf',v_cp,'unrestricted_consumed_gnf',v_cu,
                            'released_excess_gnf',v_excess);
END;
$$;

-- =====================================================================
-- Capture reversal (compensating, once)
-- =====================================================================
CREATE OR REPLACE FUNCTION public.driver_mission_capture_reverse(
  p_source_module text, p_source_id uuid, p_kind text, p_reason text, p_evidence text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_h public.mission_financial_holds;
  v_key text;
  v_res jsonb;
  v_dw public.wallets; v_master public.wallets;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.is_god_admin(v_caller) THEN
    RAISE EXCEPTION 'Only a God Admin can reverse a capture';
  END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) < 5 THEN
    RAISE EXCEPTION 'A documented reason is required';
  END IF;

  SELECT * INTO v_h FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id AND kind = p_kind FOR UPDATE;
  IF v_h.id IS NULL THEN RAISE EXCEPTION 'Hold not found'; END IF;
  IF v_h.state = 'reversed' THEN
    RETURN jsonb_build_object('status','already_reversed');
  END IF;
  IF v_h.captured_gnf <= 0 THEN
    RETURN jsonb_build_object('status','nothing_to_reverse');
  END IF;

  v_key := format('mfh-capture:%s:%s:%s', p_source_module, p_source_id, p_kind);
  v_res := public._ledger_reverse(v_key, p_reason, p_evidence, v_caller);
  IF v_res->>'status' = 'replayed' THEN
    RETURN jsonb_build_object('status','already_reversed');
  END IF;

  -- Restore the captured value to the driver, back into its original buckets.
  SELECT * INTO v_dw FROM public.wallets
   WHERE owner_user_id = v_h.driver_user_id AND party_type = 'driver' FOR UPDATE;
  SELECT * INTO v_master FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;
  UPDATE public.wallets SET balance_gnf = balance_gnf + v_h.captured_gnf, updated_at = now() WHERE id = v_dw.id;
  IF v_master.id IS NOT NULL THEN
    UPDATE public.wallets SET balance_gnf = balance_gnf - v_h.captured_gnf, updated_at = now() WHERE id = v_master.id;
  END IF;

  UPDATE public.mission_financial_holds
     SET state = 'reversed', reason = p_reason, resolved_at = now(), resolved_by = v_caller
   WHERE id = v_h.id;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, before, after, note)
  VALUES (v_caller, 'wallet', 'capture_reversed', 'mission',
          p_source_module || ':' || p_source_id::text,
          to_jsonb(v_h), v_res, p_reason);

  RETURN jsonb_build_object('status','reversed','reversed_gnf',v_h.captured_gnf,'journal',v_res);
END;
$$;

GRANT EXECUTE ON FUNCTION public.driver_mission_capture_reverse(text,uuid,text,text,text) TO authenticated, service_role;

-- =====================================================================
-- Collateral resolve (freeze -> authorised loss / release), journal-backed
-- =====================================================================
CREATE OR REPLACE FUNCTION public.driver_collateral_resolve(
  p_source_module text, p_source_id uuid, p_capture_gnf bigint, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_h public.mission_financial_holds;
  v_capture bigint; v_excess bigint;
  v_cp bigint := 0; v_cu bigint := 0; v_rp bigint := 0; v_ru bigint := 0;
  v_dw public.wallets; v_master public.wallets; v_tx public.wallet_transactions;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT (public.is_god_admin(v_caller) OR public.has_admin_role(v_caller,'finance_admin'::admin_role)) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) < 5 THEN
    RAISE EXCEPTION 'A documented reason is required';
  END IF;

  SELECT * INTO v_h FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id AND kind = 'collateral' FOR UPDATE;
  IF v_h.id IS NULL THEN RAISE EXCEPTION 'Collateral hold not found'; END IF;
  IF v_h.state NOT IN ('held','frozen') THEN
    RETURN jsonb_build_object('status','already_resolved','captured_gnf',v_h.captured_gnf);
  END IF;

  v_capture := LEAST(GREATEST(COALESCE(p_capture_gnf,0),0), v_h.amount_gnf);
  v_excess := v_h.amount_gnf - v_capture;
  v_cp := LEAST(v_h.promo_gnf, v_capture);
  v_cu := v_capture - v_cp;
  v_rp := v_h.promo_gnf - v_cp;
  v_ru := v_excess - v_rp;

  SELECT * INTO v_dw FROM public.wallets
   WHERE owner_user_id = v_h.driver_user_id AND party_type = 'driver' FOR UPDATE;
  SELECT * INTO v_master FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;

  UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - v_h.amount_gnf, 0), updated_at = now()
   WHERE id = v_dw.id;

  IF v_capture > 0 THEN
    UPDATE public.wallets SET balance_gnf = balance_gnf - v_capture, updated_at = now() WHERE id = v_dw.id;
    IF v_master.id IS NOT NULL THEN
      UPDATE public.wallets SET balance_gnf = balance_gnf + v_capture, updated_at = now() WHERE id = v_master.id;
    END IF;
    IF v_cp > 0 THEN PERFORM public._promo_consume(v_h.driver_user_id, v_cp); END IF;

    PERFORM public._ledger_post(
      format('mfh-capture:%s:%s:collateral', p_source_module, p_source_id),
      p_source_module, p_source_id, 'capture_collateral',
      jsonb_build_array(
        jsonb_build_object('account','L_HOLD_COLLATERAL','amount_gnf',v_capture,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','authorised collateral loss'),
        jsonb_build_object('account','R_COLLATERAL_LOSS','amount_gnf',-v_capture,'memo','recovered collateral')),
      v_h.mission_type, v_caller, v_h.policy_snapshot, v_h.is_sandbox, p_reason);
  END IF;

  IF v_excess > 0 THEN
    PERFORM public._ledger_post(
      format('mfh-release:%s:%s:collateral', p_source_module, p_source_id),
      p_source_module, p_source_id, 'release_collateral',
      jsonb_build_array(
        jsonb_build_object('account','L_HOLD_COLLATERAL','amount_gnf',v_excess,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','release collateral'),
        jsonb_build_object('account','L_DRIVER_PROMO','amount_gnf',-v_rp,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','restored to restricted credit'),
        jsonb_build_object('account','L_DRIVER_UNRESTRICTED','amount_gnf',-v_ru,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','restored to unrestricted')),
      v_h.mission_type, v_caller, v_h.policy_snapshot, v_h.is_sandbox, p_reason);
  END IF;

  INSERT INTO public.wallet_transactions
    (reference, type, status, amount_gnf, from_wallet_id, to_wallet_id, related_user_id,
     related_entity, description, metadata, completed_at)
  VALUES
    (format('mfh-collateral:%s:%s', p_source_module, p_source_id), 'adjustment', 'completed',
     GREATEST(v_capture,1), v_dw.id, v_master.id, v_h.driver_user_id,
     p_source_module || ':' || p_source_id::text, 'Résolution de caution mission',
     jsonb_build_object('reason', p_reason, 'held_gnf', v_h.amount_gnf, 'captured_gnf', v_capture,
                        'promo_consumed_gnf', v_cp, 'unrestricted_consumed_gnf', v_cu,
                        'is_sandbox', v_h.is_sandbox), now())
  RETURNING * INTO v_tx;

  UPDATE public.wallet_transactions SET status='completed', completed_at=now()
   WHERE id = v_h.hold_tx_id AND status = 'pending';

  UPDATE public.mission_financial_holds
     SET state = CASE WHEN v_capture > 0 THEN 'captured' ELSE 'released' END,
         captured_gnf = v_capture, released_gnf = v_excess, resolution_tx_id = v_tx.id,
         reason = p_reason, resolved_at = now(), resolved_by = v_caller
   WHERE id = v_h.id;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, before, after, note)
  VALUES (v_caller, 'wallet', 'collateral_resolve', 'mission',
          p_source_module || ':' || p_source_id::text,
          jsonb_build_object('held_gnf',v_h.amount_gnf,'promo_gnf',v_h.promo_gnf),
          jsonb_build_object('captured_gnf',v_capture,'promo_consumed_gnf',v_cp), p_reason);

  RETURN jsonb_build_object('status','resolved','captured_gnf',v_capture,
                            'promo_consumed_gnf',v_cp,'released_gnf',v_excess);
END;
$$;

-- =====================================================================
-- Restricted starter credit: journal-backed + hardened authorization
-- =====================================================================
CREATE OR REPLACE FUNCTION public.driver_starter_credit_grant(p_driver uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_driver uuid := COALESCE(p_driver, auth.uid());
  v_policy public.driver_starter_credit_policies;
  v_dp public.driver_profiles;
  v_flag boolean; v_identity text; v_key text;
  v_wallet public.wallets; v_master public.wallets;
  v_tx public.wallet_transactions; v_row public.driver_promo_credits;
  v_dupes int; v_ever int;
BEGIN
  -- Trusted path only: God Admin, or an internal/service caller (auth.uid() IS NULL).
  IF v_caller IS NOT NULL AND NOT public.is_god_admin(v_caller) THEN
    RAISE EXCEPTION 'STARTER_CREDIT_NOT_AUTHORIZED: only a God Admin or the approval service may issue the starting credit';
  END IF;
  IF v_driver IS NULL THEN RAISE EXCEPTION 'Driver required'; END IF;

  SELECT enabled INTO v_flag FROM public.feature_flags WHERE key = 'driver_starter_credit_enabled';
  IF NOT COALESCE(v_flag,false) THEN
    RETURN jsonb_build_object('status','disabled','granted_gnf',0);
  END IF;

  SELECT * INTO v_policy FROM public.starter_credit_policy_current();
  IF v_policy.id IS NULL OR v_policy.amount_gnf <= 0 THEN
    RETURN jsonb_build_object('status','no_policy','granted_gnf',0);
  END IF;

  SELECT * INTO v_dp FROM public.driver_profiles WHERE user_id = v_driver;
  IF v_dp.user_id IS NULL OR v_dp.status <> 'approved' THEN
    RETURN jsonb_build_object('status','not_eligible','reason','driver_not_approved','granted_gnf',0);
  END IF;
  IF v_dp.id_doc_url IS NULL OR v_dp.vehicle_photo_url IS NULL THEN
    RETURN jsonb_build_object('status','not_eligible','reason','identity_or_vehicle_incomplete','granted_gnf',0);
  END IF;
  IF public.is_user_banned(v_driver) OR public.is_user_frozen(v_driver) THEN
    RETURN jsonb_build_object('status','not_eligible','reason','account_restricted','granted_gnf',0);
  END IF;

  -- Permanent entitlement: ANY prior credit row, including a reversed one.
  SELECT count(*) INTO v_ever FROM public.driver_promo_credits WHERE driver_user_id = v_driver;
  IF v_ever > 0 THEN
    SELECT * INTO v_row FROM public.driver_promo_credits
     WHERE driver_user_id = v_driver ORDER BY created_at LIMIT 1;
    RETURN jsonb_build_object('status','already_granted','granted_gnf',v_row.granted_gnf,'credit_id',v_row.id);
  END IF;

  SELECT public._normalize_guinea_phone(phone) INTO v_identity
    FROM public.profiles WHERE user_id = v_driver;

  IF v_identity IS NOT NULL THEN
    SELECT count(*) INTO v_dupes FROM public.profiles
     WHERE public._normalize_guinea_phone(phone) = v_identity AND user_id <> v_driver;
    IF v_dupes = 0 THEN
      SELECT count(*) INTO v_dupes FROM public.driver_promo_credits
       WHERE identity_key = v_identity AND driver_user_id <> v_driver;
    END IF;
    IF v_dupes > 0 THEN
      INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
      VALUES (v_caller, 'wallet', 'starter_credit_denied', 'driver', v_driver::text,
              jsonb_build_object('reason','duplicate_identity','identity_key',v_identity),
              'Duplicate identity signal — routed to review');
      RETURN jsonb_build_object('status','needs_review','reason','duplicate_identity','granted_gnf',0);
    END IF;
  END IF;

  v_key := 'starter:' || v_driver::text || ':' || v_policy.id::text;

  INSERT INTO public.wallets (owner_user_id, party_type) VALUES (v_driver, 'driver')
  ON CONFLICT (owner_user_id, party_type) DO NOTHING;
  SELECT * INTO v_wallet FROM public.wallets
   WHERE owner_user_id = v_driver AND party_type = 'driver' FOR UPDATE;
  IF v_wallet.status <> 'active' THEN
    RETURN jsonb_build_object('status','not_eligible','reason','wallet_not_active','granted_gnf',0);
  END IF;
  SELECT * INTO v_master FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;

  INSERT INTO public.driver_promo_credits
    (driver_user_id, policy_id, identity_key, grant_key, granted_gnf, granted_by, reason)
  VALUES (v_driver, v_policy.id, v_identity, v_key, v_policy.amount_gnf, v_caller,
          'Bonus de démarrage CHOPCHOP')
  ON CONFLICT (grant_key) DO NOTHING
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    RETURN jsonb_build_object('status','already_granted','granted_gnf',0);
  END IF;

  UPDATE public.wallets SET balance_gnf = balance_gnf + v_policy.amount_gnf, updated_at = now()
   WHERE id = v_wallet.id;
  IF v_master.id IS NOT NULL THEN
    UPDATE public.wallets SET balance_gnf = balance_gnf - v_policy.amount_gnf, updated_at = now()
     WHERE id = v_master.id;
  END IF;

  PERFORM public._ledger_post(
    v_key, 'promo', v_row.id, 'starter_credit_grant',
    jsonb_build_array(
      jsonb_build_object('account','E_PROMOTIONAL_CREDIT','amount_gnf',v_policy.amount_gnf,
                         'memo','restricted starting credit issued'),
      jsonb_build_object('account','L_DRIVER_PROMO','amount_gnf',-v_policy.amount_gnf,
                         'party_type','driver','party_user_id',v_driver,'memo','Bonus de démarrage CHOPCHOP')),
    NULL, v_caller, jsonb_build_object('policy_id',v_policy.id,'amount_gnf',v_policy.amount_gnf),
    false, 'Restricted promotional liability — not a top-up, not earnings');

  INSERT INTO public.wallet_transactions
    (reference, type, status, amount_gnf, from_wallet_id, to_wallet_id, related_user_id,
     related_entity, description, metadata, completed_at)
  VALUES (v_key, 'adjustment', 'completed', v_policy.amount_gnf, v_master.id, v_wallet.id,
          v_driver, 'promo:starter_credit', 'Bonus de démarrage CHOPCHOP (restreint)',
          jsonb_build_object('source_module','promo','restricted',true,
                             'accounting','promotional_expense','policy_id',v_policy.id,
                             'credit_id',v_row.id), now())
  RETURNING * INTO v_tx;

  UPDATE public.driver_promo_credits SET grant_tx_id = v_tx.id, updated_at = now() WHERE id = v_row.id;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (v_caller, 'wallet', 'starter_credit_granted', 'driver', v_driver::text,
          jsonb_build_object('amount_gnf',v_policy.amount_gnf,'policy_id',v_policy.id,'credit_id',v_row.id),
          'Restricted starting credit — not withdrawable, not transferable');

  RETURN jsonb_build_object('status','granted','granted_gnf',v_policy.amount_gnf,'credit_id',v_row.id);
END;
$$;

-- Reversal must post a compensating journal and never restore eligibility.
CREATE OR REPLACE FUNCTION public.admin_reverse_starter_credit(p_driver uuid, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_row public.driver_promo_credits;
  v_open int; v_reversible bigint; v_take bigint;
  v_wallet public.wallets; v_master public.wallets;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.is_god_admin(v_caller) THEN
    RAISE EXCEPTION 'Only a God Admin can reverse a promotional credit';
  END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) < 5 THEN
    RAISE EXCEPTION 'A documented reason is required';
  END IF;

  SELECT * INTO v_row FROM public.driver_promo_credits
   WHERE driver_user_id = p_driver AND state <> 'reversed' FOR UPDATE;
  IF v_row.id IS NULL THEN RETURN jsonb_build_object('status','nothing_to_reverse'); END IF;

  SELECT count(*) INTO v_open FROM public.mission_financial_holds
   WHERE driver_user_id = p_driver AND state IN ('held','frozen','partially_captured') AND promo_gnf > 0;
  IF v_open > 0 THEN
    RETURN jsonb_build_object('status','blocked','reason','outstanding_promo_holds','open_holds',v_open);
  END IF;

  v_reversible := v_row.granted_gnf - v_row.consumed_gnf - v_row.reversed_gnf;

  SELECT * INTO v_wallet FROM public.wallets
   WHERE owner_user_id = p_driver AND party_type = 'driver' FOR UPDATE;
  SELECT * INTO v_master FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;

  -- Only the UNUSED restricted grant may be clawed back; never unrestricted earnings.
  v_take := LEAST(v_reversible, GREATEST(COALESCE(v_wallet.balance_gnf,0) - COALESCE(v_wallet.held_gnf,0), 0));

  IF v_take > 0 THEN
    UPDATE public.wallets SET balance_gnf = balance_gnf - v_take, updated_at = now() WHERE id = v_wallet.id;
    IF v_master.id IS NOT NULL THEN
      UPDATE public.wallets SET balance_gnf = balance_gnf + v_take, updated_at = now() WHERE id = v_master.id;
    END IF;
    PERFORM public._ledger_post(
      'promo-reversal:' || v_row.id::text, 'promo', v_row.id, 'starter_credit_reversed',
      jsonb_build_array(
        jsonb_build_object('account','L_DRIVER_PROMO','amount_gnf',v_take,
                           'party_type','driver','party_user_id',p_driver,'memo','unused restricted credit withdrawn'),
        jsonb_build_object('account','E_PROMOTIONAL_CREDIT','amount_gnf',-v_take,'memo','promotional expense reversed')),
      NULL, v_caller, '{}'::jsonb, false, p_reason);

    INSERT INTO public.wallet_transactions
      (reference, type, status, amount_gnf, from_wallet_id, to_wallet_id, related_user_id,
       related_entity, description, metadata, completed_at)
    VALUES ('promo-reversal:' || v_row.id::text, 'adjustment', 'completed', v_take,
            v_wallet.id, v_master.id, p_driver, 'promo:starter_credit',
            'Annulation auditée du bonus de démarrage',
            jsonb_build_object('source_module','promo','reason',p_reason,'credit_id',v_row.id), now());
  END IF;

  UPDATE public.driver_promo_credits
     SET reversed_gnf = reversed_gnf + v_take, state = 'reversed', reason = p_reason, updated_at = now()
   WHERE id = v_row.id;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, before, after, note)
  VALUES (v_caller, 'wallet', 'starter_credit_reversed', 'driver', p_driver::text,
          to_jsonb(v_row), jsonb_build_object('reversed_gnf',v_take), p_reason);

  RETURN jsonb_build_object('status','reversed','reversed_gnf',v_take,'consumed_gnf',v_row.consumed_gnf);
END;
$$;

-- ============ internal helpers are no longer directly callable ============
REVOKE ALL ON FUNCTION public.driver_funding_allocate(uuid,bigint,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._promo_consume(uuid,bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.driver_promo_balance(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._hold_account(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public._capture_revenue_account(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.driver_funding_allocate(uuid,bigint,text) TO service_role;
GRANT EXECUTE ON FUNCTION public._promo_consume(uuid,bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.driver_promo_balance(uuid) TO service_role;