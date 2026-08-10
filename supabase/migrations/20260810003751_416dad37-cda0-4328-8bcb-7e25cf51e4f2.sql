-- DEF-S4-002: 'cancelled' is not a valid merchant_payables.state; the canonical
-- terminal state for an unfunded, voided payable is 'reversed'.
CREATE OR REPLACE FUNCTION public.cash_order_merchant_reject(
  p_source_module text, p_source_id uuid, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_caller uuid := auth.uid(); v_row public.cash_order_runtime; v_rel jsonb;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_row FROM public.cash_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id FOR UPDATE;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'CASH_ORDER_NOT_ACCEPTED'; END IF;
  IF v_caller IS DISTINCT FROM v_row.merchant_user_id AND NOT public._finance_privileged(v_caller) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF v_row.state = 'merchant_rejected' THEN
    RETURN jsonb_build_object('status','already_rejected');
  END IF;
  IF v_row.state <> 'accepted' THEN
    RAISE EXCEPTION 'MERCHANT_REJECTION_AFTER_FUNDING'
      USING DETAIL = 'Use the dispute path once funding or preparation has started';
  END IF;

  v_rel := public._driver_mission_hold_release_internal(
    p_source_module, p_source_id, NULL,
    COALESCE(p_reason, 'merchant_rejected_before_preparation'), v_caller);

  UPDATE public.merchant_payables
     SET state = 'reversed', reason = COALESCE(p_reason,'merchant_rejected'), updated_at = now()
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND state = 'pending_funding' AND funded_gnf = 0;

  UPDATE public.cash_order_runtime
     SET state = 'merchant_rejected', cancelled_at = now(),
         dispute_reason = COALESCE(p_reason, dispute_reason)
   WHERE id = v_row.id;

  IF p_source_module = 'repas' THEN
    UPDATE public.food_orders SET state = 'cancelled'
     WHERE id = p_source_id AND state IN ('placed','confirmed');
  END IF;

  RETURN jsonb_build_object('status','merchant_rejected','release',v_rel,
                            'customer_debt_created', false, 'platform_fee_revenue_gnf', 0);
END; $$;

CREATE OR REPLACE FUNCTION public.cash_order_customer_cancel(
  p_source_module text, p_source_id uuid, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_caller uuid := auth.uid(); v_row public.cash_order_runtime; v_f jsonb; v_e jsonb;
  v_debt jsonb; v_rel jsonb; v_stage text; v_snap jsonb; v_sub bigint; v_del bigint;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(format('%s:%s', p_source_module, p_source_id), 0));

  v_f := public._cash_order_facts(p_source_module, p_source_id);
  IF v_caller <> (v_f->>'customer_user_id')::uuid THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF NOT (v_f->>'is_cash')::boolean THEN RAISE EXCEPTION 'NOT_A_CASH_ORDER'; END IF;

  SELECT * INTO v_row FROM public.cash_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id FOR UPDATE;

  IF v_row.id IS NULL THEN
    v_e := public._cash_order_economics(v_f);
    v_stage := 'before_dispatch';
    v_snap := COALESCE(v_e->'policy_snapshot','{}'::jsonb);
    v_sub := (v_e->>'merchandise_subtotal_gnf')::bigint;
    v_del := (v_e->>'delivery_fee_gnf')::bigint;
  ELSE
    IF v_row.state = 'cancelled' THEN
      RETURN jsonb_build_object('status','already_cancelled');
    END IF;
    IF v_row.state IN ('preparing','completed','disputed','dispute_resolved') THEN
      RAISE EXCEPTION 'CASH_ORDER_PREPARATION_LOCKED'
        USING DETAIL = 'Preparation has started; open a dispute instead';
    END IF;
    IF v_row.state = 'merchant_accepted' THEN
      RAISE EXCEPTION 'CASH_ORDER_ALREADY_FUNDED'
        USING DETAIL = 'Merchandise funding is secured; open a dispute instead';
    END IF;
    v_stage := 'after_dispatch';
    v_snap := v_row.policy_snapshot;
    v_sub := v_row.merchandise_subtotal_gnf;
    v_del := v_row.delivery_fee_gnf;
  END IF;

  v_debt := public._customer_cancellation_debt_create_internal(
    p_source_module, p_source_id, v_caller, v_f->>'mission_type', v_stage,
    0, v_sub, v_del, false, 'customer', false, v_snap, v_caller);

  IF v_row.id IS NOT NULL THEN
    v_rel := public._driver_mission_hold_release_internal(
      p_source_module, p_source_id, NULL,
      COALESCE(p_reason,'customer_cancelled'), v_caller);
    UPDATE public.merchant_payables
       SET state = 'reversed', updated_at = now()
     WHERE source_module = p_source_module AND source_id = p_source_id
       AND state = 'pending_funding' AND funded_gnf = 0;
    UPDATE public.cash_order_runtime
       SET state = 'cancelled', cancelled_at = now() WHERE id = v_row.id;
  END IF;

  IF p_source_module = 'repas' THEN
    UPDATE public.food_orders SET state = 'cancelled'
     WHERE id = p_source_id AND state IN ('placed','confirmed');
  END IF;

  RETURN jsonb_build_object('status','cancelled','stage',v_stage,'debt',v_debt,'release',v_rel);
END; $$;