-- DEF-S4-003: audit_logs uses (module, target_type, target_id, after), not (entity_type, entity_id, metadata)
CREATE OR REPLACE FUNCTION public.admin_cash_order_dispute_resolve(
  p_source_module text, p_source_id uuid, p_outcome text, p_reason text DEFAULT NULL::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE v_caller uuid := auth.uid(); v_row public.cash_order_runtime; v_res jsonb;
BEGIN
  IF NOT public._finance_privileged(v_caller) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_outcome NOT IN ('complete_as_delivered','release_driver_funding','close_no_value') THEN
    RAISE EXCEPTION 'INVALID_DISPUTE_OUTCOME';
  END IF;

  SELECT * INTO v_row FROM public.cash_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id FOR UPDATE;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'CASH_ORDER_NOT_ACCEPTED'; END IF;
  IF v_row.state = 'dispute_resolved' THEN
    RETURN jsonb_build_object('status','already_resolved','resolution',v_row.dispute_resolution);
  END IF;
  IF v_row.state <> 'disputed' THEN RAISE EXCEPTION 'NOT_IN_DISPUTE' USING DETAIL = v_row.state; END IF;

  IF p_outcome = 'complete_as_delivered' THEN
    v_res := public._cash_order_capture_platform_fee(p_source_module, p_source_id, v_caller);
  ELSIF p_outcome = 'release_driver_funding' THEN
    v_res := public._driver_mission_hold_release_internal(
      p_source_module, p_source_id, NULL, COALESCE(p_reason,'dispute_resolution'), v_caller);
  ELSE
    v_res := jsonb_build_object('status','closed_no_value');
  END IF;

  UPDATE public.cash_order_runtime
     SET state = 'dispute_resolved', resolved_by = v_caller, resolved_at = now(),
         dispute_resolution = jsonb_build_object('outcome',p_outcome,'reason',p_reason,'result',v_res)
   WHERE id = v_row.id;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (v_caller, 'finance', 'cash_order_dispute_resolved', 'cash_order_runtime', v_row.id::text,
          jsonb_build_object('outcome',p_outcome,'result',v_res), p_reason);

  RETURN jsonb_build_object('status','resolved','outcome',p_outcome,'result',v_res);
END; $function$;