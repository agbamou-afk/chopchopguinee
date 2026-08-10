-- Fix 1: never release the customer hold through the driver-hold helper.
CREATE OR REPLACE FUNCTION public.chop_pay_merchant_reject(
  p_source_module text, p_source_id uuid, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_caller uuid := auth.uid(); v_row public.chop_pay_order_runtime;
        v_rel jsonb; v_ref jsonb;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_row FROM public.chop_pay_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id FOR UPDATE;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'CHOP_PAY_NOT_AUTHORIZED'; END IF;
  IF v_caller IS DISTINCT FROM v_row.merchant_user_id AND NOT public._finance_privileged(v_caller) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF v_row.state = 'merchant_rejected' THEN RETURN jsonb_build_object('status','already_rejected'); END IF;
  IF v_row.state NOT IN ('authorized','accepted') THEN
    RAISE EXCEPTION 'MERCHANT_REJECTION_AFTER_FUNDING'
      USING DETAIL = 'Use the dispute path once funding or preparation has started';
  END IF;

  v_rel := public._driver_mission_hold_release_internal(
    p_source_module, p_source_id, 'collateral',
    COALESCE(p_reason,'merchant_rejected_before_preparation'), v_caller);
  v_ref := public._chop_pay_customer_release_internal(
    p_source_module, p_source_id, COALESCE(p_reason,'merchant_rejected'), v_caller);

  UPDATE public.merchant_payables
     SET state='reversed', reason=COALESCE(p_reason,'merchant_rejected'), updated_at = now()
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND state = 'pending_funding' AND funded_gnf = 0;

  UPDATE public.chop_pay_order_runtime
     SET state='merchant_rejected', cancelled_at = now(),
         customer_refunded_gnf = COALESCE((v_ref->>'released_gnf')::bigint,0),
         dispute_reason = COALESCE(p_reason, dispute_reason)
   WHERE id = v_row.id;

  PERFORM public._chop_pay_deactivate_source(p_source_module, p_source_id, v_row.mission_id);

  RETURN jsonb_build_object('status','merchant_rejected','collateral_release',v_rel,
    'customer_refund',v_ref,'platform_fee_revenue_gnf',0,'driver_earning_gnf',0);
END; $$;

CREATE OR REPLACE FUNCTION public._chop_pay_cancel_internal(
  p_source_module text, p_source_id uuid, p_responsible_party text, p_reason text, p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row public.chop_pay_order_runtime; v_snap jsonb; v_stage text; v_bps int;
  v_basis bigint; v_charge bigint := 0; v_open bigint; v_rev jsonb;
  v_col jsonb; v_ref jsonb; v_chg jsonb := jsonb_build_object('status','none','captured_gnf',0);
  v_basis_kind text;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(format('choppay:%s:%s',p_source_module,p_source_id), 0));
  SELECT * INTO v_row FROM public.chop_pay_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id FOR UPDATE;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'CHOP_PAY_NOT_AUTHORIZED'; END IF;
  IF v_row.state IN ('cancelled','merchant_rejected') THEN
    RETURN jsonb_build_object('status','already_cancelled');
  END IF;
  IF v_row.state IN ('preparing','completed','disputed','dispute_resolved') THEN
    RAISE EXCEPTION 'CHOP_PAY_PREPARATION_LOCKED'
      USING DETAIL = 'Preparation has started; open a dispute instead';
  END IF;

  v_snap := v_row.policy_snapshot;
  v_stage := CASE WHEN v_row.state = 'authorized' THEN 'before_dispatch' ELSE 'after_dispatch' END;
  v_basis_kind := COALESCE(v_snap->>'cancel_basis','none');
  v_basis := CASE v_basis_kind
    WHEN 'merchandise_plus_delivery' THEN v_row.merchandise_subtotal_gnf + v_row.delivery_fee_gnf
    WHEN 'delivery_fee' THEN v_row.delivery_fee_gnf
    WHEN 'merchandise_subtotal' THEN v_row.merchandise_subtotal_gnf
    ELSE 0 END;
  v_bps := CASE v_stage
    WHEN 'before_dispatch' THEN COALESCE((v_snap->>'cancel_before_dispatch_bps')::int,0)
    ELSE COALESCE((v_snap->>'cancel_after_dispatch_bps')::int,0) END;

  IF p_responsible_party = 'customer' AND public._finance_flag('cancellation_policy_enabled') THEN
    v_charge := (v_basis * v_bps) / 10000;
  ELSE
    v_charge := 0;
  END IF;

  IF v_row.state = 'merchant_accepted' THEN
    v_rev := public._chop_pay_merchant_capture_reverse_internal(
      p_source_module, p_source_id, COALESCE(p_reason,'chop_pay_cancelled'), p_actor);
    IF v_rev->>'status' = 'reconciliation_required' THEN
      RAISE EXCEPTION 'FINANCE_RECONCILIATION_REQUIRED'
        USING DETAIL = COALESCE(v_rev->>'detail','merchant liability not recoverable');
    END IF;
  END IF;

  SELECT GREATEST(amount_gnf - captured_gnf - released_gnf, 0) INTO v_open
    FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id AND kind = 'customer_payment';
  v_charge := LEAST(COALESCE(v_charge,0), COALESCE(v_open,0));

  IF v_charge > 0 THEN
    v_chg := public._chop_pay_customer_capture_internal(
      p_source_module, p_source_id, v_charge, 'cancellation_fee', p_actor);
  END IF;

  v_col := public._driver_mission_hold_release_internal(
    p_source_module, p_source_id, 'collateral', COALESCE(p_reason,'chop_pay_cancelled'), p_actor);
  v_ref := public._chop_pay_customer_release_internal(
    p_source_module, p_source_id, COALESCE(p_reason,'chop_pay_cancelled'), p_actor);

  UPDATE public.merchant_payables
     SET state='reversed', reason=COALESCE(p_reason,'chop_pay_cancelled'), updated_at = now()
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND state = 'pending_funding' AND funded_gnf = 0;

  UPDATE public.chop_pay_order_runtime
     SET state='cancelled', cancelled_at = now(),
         cancellation_charge_gnf = v_charge,
         merchant_credited_gnf = CASE WHEN v_rev->>'status' = 'reversed' THEN 0 ELSE merchant_credited_gnf END,
         customer_refunded_gnf = COALESCE((v_ref->>'released_gnf')::bigint,0)
                                 + COALESCE((v_rev->>'reversed_gnf')::bigint,0)
   WHERE id = v_row.id;

  PERFORM public._chop_pay_deactivate_source(p_source_module, p_source_id, v_row.mission_id);

  RETURN jsonb_build_object('status','cancelled','stage',v_stage,
    'responsible_party',p_responsible_party,
    'cancel_basis_kind',v_basis_kind,'basis_gnf',v_basis,'applied_bps',v_bps,
    'cancellation_charge_gnf',v_charge,'charge_capture',v_chg,
    'merchant_reversal',v_rev,'collateral_release',v_col,'customer_refund',v_ref,
    'cash_debt_created', false);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_chop_pay_dispute_resolve(
  p_source_module text, p_source_id uuid, p_outcome text, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_caller uuid := auth.uid(); v_row public.chop_pay_order_runtime;
  v_res jsonb; v_rev jsonb; v_col jsonb; v_ref jsonb; v_final text;
BEGIN
  IF NOT public._finance_privileged(v_caller) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_outcome NOT IN ('complete_as_delivered','refund_customer','close_no_value') THEN
    RAISE EXCEPTION 'INVALID_DISPUTE_OUTCOME';
  END IF;

  SELECT * INTO v_row FROM public.chop_pay_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id FOR UPDATE;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'CHOP_PAY_NOT_AUTHORIZED'; END IF;
  IF v_row.dispute_resolution IS NOT NULL THEN
    RETURN jsonb_build_object('status','already_resolved','resolution',v_row.dispute_resolution);
  END IF;
  IF v_row.state <> 'disputed' THEN RAISE EXCEPTION 'NOT_IN_DISPUTE' USING DETAIL = v_row.state; END IF;

  IF p_outcome = 'complete_as_delivered' THEN
    v_res := public._chop_pay_complete_internal(p_source_module, p_source_id, v_caller, true);
    v_final := 'completed';

  ELSIF p_outcome = 'refund_customer' THEN
    v_rev := public._chop_pay_merchant_capture_reverse_internal(
      p_source_module, p_source_id, COALESCE(p_reason,'dispute_refund_customer'), v_caller);
    IF v_rev->>'status' = 'reconciliation_required' THEN
      RAISE EXCEPTION 'FINANCE_RECONCILIATION_REQUIRED'
        USING DETAIL = COALESCE(v_rev->>'detail','merchant liability not recoverable');
    END IF;
    v_col := public._driver_mission_hold_release_internal(
      p_source_module, p_source_id, 'collateral', COALESCE(p_reason,'dispute_resolution'), v_caller);
    v_ref := public._chop_pay_customer_release_internal(
      p_source_module, p_source_id, COALESCE(p_reason,'dispute_refund_customer'), v_caller);
    v_res := jsonb_build_object('merchant_reversal',v_rev,'collateral_release',v_col,
                                'customer_refund',v_ref,'platform_fee_captured_gnf',0);
    v_final := 'dispute_resolved';
    PERFORM public._chop_pay_deactivate_source(p_source_module, p_source_id, v_row.mission_id);

  ELSE
    v_col := public._driver_mission_hold_release_internal(
      p_source_module, p_source_id, 'collateral', COALESCE(p_reason,'dispute_close_no_value'), v_caller);
    v_ref := public._chop_pay_customer_release_internal(
      p_source_module, p_source_id, COALESCE(p_reason,'dispute_close_no_value'), v_caller);
    v_res := jsonb_build_object('status','closed_no_value','collateral_release',v_col,
      'customer_hold_release',v_ref,'merchant_principal_change_gnf',0,
      'platform_fee_captured_gnf',0,'driver_earning_gnf',0);
    v_final := 'dispute_resolved';
  END IF;

  UPDATE public.chop_pay_order_runtime
     SET state = v_final, resolved_by = v_caller, resolved_at = now(),
         dispute_resolution = jsonb_build_object('outcome',p_outcome,'reason',p_reason,'result',v_res)
   WHERE id = v_row.id;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (v_caller,'finance','chop_pay_dispute_resolved','chop_pay_order_runtime', v_row.id::text,
          jsonb_build_object('outcome',p_outcome,'result',v_res,'final_state',v_final), p_reason);

  RETURN jsonb_build_object('status','resolved','outcome',p_outcome,'final_state',v_final,'result',v_res);
END; $$;

-- Fix 2: explicit dispute participant authorization.
CREATE OR REPLACE FUNCTION public.chop_pay_dispute_open(
  p_source_module text, p_source_id uuid, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_caller uuid := auth.uid(); v_row public.chop_pay_order_runtime;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_row FROM public.chop_pay_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id FOR UPDATE;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'CHOP_PAY_NOT_AUTHORIZED'; END IF;
  IF NOT (v_caller = v_row.customer_user_id
          OR v_caller = v_row.driver_user_id
          OR v_caller = v_row.merchant_user_id
          OR public._finance_privileged(v_caller)) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF v_row.state IN ('disputed','dispute_resolved') THEN
    RETURN jsonb_build_object('status','already_disputed','state',v_row.state);
  END IF;
  IF v_row.state NOT IN ('merchant_accepted','preparing','completed') THEN
    RAISE EXCEPTION 'DISPUTE_REQUIRES_FUNDED_ORDER' USING DETAIL = v_row.state;
  END IF;
  UPDATE public.chop_pay_order_runtime
     SET state='disputed', disputed_at = now(), dispute_reason = p_reason, dispute_opened_by = v_caller
   WHERE id = v_row.id;
  RETURN jsonb_build_object('status','disputed','economic_state','frozen');
END; $$;

-- Fix 3: delivery capture requires an assigned courier.
CREATE OR REPLACE FUNCTION public._chop_pay_customer_capture_internal(
  p_source_module text, p_source_id uuid, p_amount bigint, p_purpose text, p_actor uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_h public.mission_financial_holds; v_open bigint; v_cw public.wallets;
  v_row public.chop_pay_order_runtime; v_target uuid; v_target_wallet public.wallets;
  v_key text; v_account text; v_desc text; v_ttype public.party_type;
BEGIN
  IF p_purpose NOT IN ('merchandise','delivery','platform_fee','cancellation_fee') THEN
    RAISE EXCEPTION 'INVALID_CAPTURE_PURPOSE';
  END IF;
  IF COALESCE(p_amount,0) <= 0 THEN
    RETURN jsonb_build_object('status','zero','captured_gnf',0);
  END IF;

  SELECT * INTO v_row FROM public.chop_pay_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'CHOP_PAY_NOT_AUTHORIZED'; END IF;
  IF p_purpose = 'delivery' AND v_row.driver_user_id IS NULL THEN
    RAISE EXCEPTION 'NO_ASSIGNED_COURIER';
  END IF;
  IF p_purpose = 'merchandise' AND v_row.merchant_user_id IS NULL THEN
    RAISE EXCEPTION 'MERCHANT_OWNER_MISSING';
  END IF;

  v_key := format('cph-capture:%s:%s:%s', p_source_module, p_source_id, p_purpose);
  IF EXISTS (SELECT 1 FROM public.ledger_journals WHERE journal_key = v_key) THEN
    RETURN jsonb_build_object('status','already_captured','captured_gnf',0);
  END IF;

  SELECT * INTO v_h FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND kind = 'customer_payment' FOR UPDATE;
  IF v_h.id IS NULL THEN RAISE EXCEPTION 'CHOP_PAY_HOLD_MISSING'; END IF;
  v_open := v_h.amount_gnf - v_h.captured_gnf - v_h.released_gnf;
  IF v_open < p_amount THEN
    RAISE EXCEPTION 'CHOP_PAY_HOLD_INSUFFICIENT'
      USING DETAIL = format('open=%s requested=%s', v_open, p_amount);
  END IF;

  SELECT * INTO v_cw FROM public.wallets
   WHERE owner_user_id = v_row.customer_user_id AND party_type = 'client' FOR UPDATE;
  UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - p_amount,0),
                            balance_gnf = balance_gnf - p_amount, updated_at = now()
   WHERE id = v_cw.id;

  IF p_purpose = 'merchandise' THEN
    v_target := v_row.merchant_user_id; v_ttype := 'merchant';
    v_account := 'L_MERCHANT_PAYABLE'; v_desc := 'Règlement marchandise Chop Pay';
  ELSIF p_purpose = 'delivery' THEN
    v_target := v_row.driver_user_id; v_ttype := 'driver';
    v_account := 'L_DRIVER_UNRESTRICTED'; v_desc := 'Gain de livraison Chop Pay';
  ELSIF p_purpose = 'platform_fee' THEN
    v_target := NULL; v_ttype := NULL;
    v_account := 'R_TRANSACTION_FEE'; v_desc := 'Frais de transaction CHOPCHOP';
  ELSE
    v_target := NULL; v_ttype := NULL;
    v_account := 'R_CANCELLATION_FEE'; v_desc := 'Frais d''annulation Chop Pay';
  END IF;

  IF v_target IS NOT NULL THEN
    INSERT INTO public.wallets (owner_user_id, party_type) VALUES (v_target, v_ttype)
    ON CONFLICT (owner_user_id, party_type) DO NOTHING;
    UPDATE public.wallets SET balance_gnf = balance_gnf + p_amount, updated_at = now()
     WHERE owner_user_id = v_target AND party_type = v_ttype
     RETURNING * INTO v_target_wallet;
  ELSE
    SELECT * INTO v_target_wallet FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;
    IF v_target_wallet.id IS NULL THEN RAISE EXCEPTION 'MASTER_WALLET_MISSING'; END IF;
    UPDATE public.wallets SET balance_gnf = balance_gnf + p_amount, updated_at = now()
     WHERE id = v_target_wallet.id;
  END IF;

  INSERT INTO public.wallet_transactions
    (reference, type, status, amount_gnf, from_wallet_id, to_wallet_id, related_user_id,
     related_entity, description, metadata, completed_at)
  VALUES (v_key, 'capture','completed', p_amount, v_cw.id, v_target_wallet.id,
     v_row.customer_user_id, p_source_module || ':' || p_source_id::text, v_desc,
     jsonb_build_object('purpose',p_purpose,'mission_type',v_row.mission_type,
                        'tender','chop_pay','is_sandbox',v_row.is_sandbox), now());

  PERFORM public._ledger_post(v_key, p_source_module, p_source_id, 'capture_customer_'||p_purpose,
    jsonb_build_array(
      jsonb_build_object('account','L_CUSTOMER_HOLD','amount_gnf',p_amount,
                         'party_type','client','party_user_id',v_row.customer_user_id,
                         'memo','consume customer hold'),
      jsonb_build_object('account',v_account,'amount_gnf',-p_amount,
                         'party_type', v_ttype, 'party_user_id', v_target,
                         'merchant_store_id', CASE WHEN p_purpose='merchandise' THEN v_row.merchant_store_id END,
                         'memo', v_desc)),
    v_row.mission_type, p_actor, v_row.policy_snapshot, v_row.is_sandbox);

  UPDATE public.mission_financial_holds
     SET captured_gnf = captured_gnf + p_amount,
         state = CASE WHEN captured_gnf + p_amount + released_gnf >= amount_gnf
                      THEN 'captured' ELSE 'partially_captured' END,
         resolved_at = CASE WHEN captured_gnf + p_amount + released_gnf >= amount_gnf
                            THEN now() ELSE resolved_at END
   WHERE id = v_h.id;

  UPDATE public.wallet_transactions SET status = 'completed', completed_at = now()
   WHERE id = v_h.hold_tx_id AND status = 'pending'
     AND EXISTS (SELECT 1 FROM public.mission_financial_holds h
                  WHERE h.id = v_h.id AND h.captured_gnf + h.released_gnf >= h.amount_gnf);

  RETURN jsonb_build_object('status','captured','captured_gnf',p_amount,'purpose',p_purpose);
END; $$;

REVOKE ALL ON FUNCTION public._chop_pay_customer_capture_internal(text,uuid,bigint,text,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._chop_pay_customer_capture_internal(text,uuid,bigint,text,uuid) TO service_role;
REVOKE ALL ON FUNCTION public._chop_pay_cancel_internal(text,uuid,text,text,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._chop_pay_cancel_internal(text,uuid,text,text,uuid) TO service_role;
REVOKE ALL ON FUNCTION public.chop_pay_merchant_reject(text,uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chop_pay_merchant_reject(text,uuid,text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.chop_pay_dispute_open(text,uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chop_pay_dispute_open(text,uuid,text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_chop_pay_dispute_resolve(text,uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_chop_pay_dispute_resolve(text,uuid,text,text) TO authenticated, service_role;
