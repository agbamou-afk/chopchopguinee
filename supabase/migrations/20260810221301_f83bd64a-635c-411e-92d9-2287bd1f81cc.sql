-- Slice 5 hardening: privilege + defect closure

-- DEF-S5-01: admin wrappers must never trust a NULL caller
CREATE OR REPLACE FUNCTION public.admin_chop_pay_cancel(p_source_module text, p_source_id uuid, p_responsible_party text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_caller uuid := auth.uid();
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT (public.is_god_admin(v_caller)
          OR public.has_admin_role(v_caller, 'finance_admin'::admin_role)) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF p_responsible_party NOT IN ('customer','merchant','driver','platform') THEN
    RAISE EXCEPTION 'Invalid responsible party';
  END IF;
  RETURN public._chop_pay_cancel_internal(p_source_module, p_source_id, p_responsible_party, p_reason, v_caller);
END; $function$;

CREATE OR REPLACE FUNCTION public.admin_chop_pay_dispute_resolve(p_source_module text, p_source_id uuid, p_outcome text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_caller uuid := auth.uid(); v_row public.chop_pay_order_runtime;
  v_res jsonb; v_rev jsonb; v_col jsonb; v_ref jsonb; v_final text;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT (public.is_god_admin(v_caller)
          OR public.has_admin_role(v_caller, 'finance_admin'::admin_role)) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF p_outcome NOT IN ('complete_as_delivered','refund_customer','close_no_value') THEN
    RAISE EXCEPTION 'INVALID_DISPUTE_OUTCOME';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(format('choppay:%s:%s',p_source_module,p_source_id), 0));
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
                                'customer_refund',v_ref,'platform_fee_captured_gnf',0,
                                'driver_earning_gnf',0);
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
END; $function$;

-- DEF-S5-02: dispute may only be opened while the order is funded / preparing
CREATE OR REPLACE FUNCTION public.chop_pay_dispute_open(p_source_module text, p_source_id uuid, p_reason text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_caller uuid := auth.uid(); v_row public.chop_pay_order_runtime;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_row FROM public.chop_pay_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id FOR UPDATE;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'CHOP_PAY_NOT_AUTHORIZED'; END IF;
  IF NOT (v_caller = v_row.customer_user_id
          OR v_caller = v_row.driver_user_id
          OR v_caller = v_row.merchant_user_id
          OR public.is_god_admin(v_caller)
          OR public.has_admin_role(v_caller, 'finance_admin'::admin_role)) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF v_row.state IN ('disputed','dispute_resolved') THEN
    RETURN jsonb_build_object('status','already_disputed','state',v_row.state);
  END IF;
  IF v_row.state NOT IN ('merchant_accepted','preparing') THEN
    RAISE EXCEPTION 'DISPUTE_REQUIRES_FUNDED_ORDER' USING DETAIL = v_row.state;
  END IF;
  UPDATE public.chop_pay_order_runtime
     SET state='disputed', disputed_at = now(), dispute_reason = p_reason, dispute_opened_by = v_caller
   WHERE id = v_row.id;
  RETURN jsonb_build_object('status','disputed','economic_state','frozen');
END; $function$;

-- DEF-S5-03: the runtime row was unreadable by the product (no table grant)
GRANT SELECT ON public.chop_pay_order_runtime TO authenticated;
GRANT ALL ON public.chop_pay_order_runtime TO service_role;

DROP POLICY IF EXISTS chop_pay_runtime_participant_select ON public.chop_pay_order_runtime;
CREATE POLICY chop_pay_runtime_participant_select
  ON public.chop_pay_order_runtime FOR SELECT TO authenticated
  USING (
    auth.uid() IS NOT NULL AND (
      auth.uid() = customer_user_id
      OR auth.uid() = driver_user_id
      OR auth.uid() = merchant_user_id
      OR public.is_god_admin(auth.uid())
      OR public.has_admin_role(auth.uid(), 'finance_admin'::admin_role)
    )
  );

-- DEF-S5-04: money-moving drop-off confirmation must not be anonymous
REVOKE EXECUTE ON FUNCTION public.mission_confirm_dropoff(uuid) FROM anon;

-- DEF-S5-05: raw customer hold primitive is service/finance only
REVOKE EXECUTE ON FUNCTION public.chop_pay_customer_hold_place(text, uuid, bigint, text, uuid, boolean, jsonb) FROM authenticated;

REVOKE EXECUTE ON FUNCTION public.admin_chop_pay_cancel(text, uuid, text, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_chop_pay_dispute_resolve(text, uuid, text, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.chop_pay_dispute_open(text, uuid, text) FROM anon;