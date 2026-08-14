CREATE OR REPLACE FUNCTION public.repas_merchant_transition(p_order_id uuid, p_action text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_o public.food_orders%ROWTYPE;
  v_r public.food_restaurants%ROWTYPE;
  v_tender text; v_res jsonb := NULL; v_next text := NULL; v_cur text;
  v_engine_state text; v_pickup boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  SELECT * INTO v_o FROM public.food_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  SELECT * INTO v_r FROM public.food_restaurants WHERE id = v_o.restaurant_id;
  IF v_r.owner_user_id IS DISTINCT FROM v_uid AND NOT public._finance_privileged(v_uid) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  v_tender := v_o.payment_method::text;
  v_cur := v_o.state::text;
  v_pickup := (v_o.fulfillment::text = 'pickup');

  IF p_action = 'accept' THEN
    IF v_cur IN ('confirmed','preparing','ready','out_for_delivery','completed') THEN
      RETURN jsonb_build_object('ok', true, 'idempotent', true, 'state', v_cur);
    END IF;
    IF v_cur <> 'placed' THEN RAISE EXCEPTION 'ILLEGAL_TRANSITION' USING DETAIL = v_cur; END IF;
    IF v_tender = 'cash' THEN v_res := public.cash_order_merchant_accept('repas', p_order_id);
    ELSIF v_tender = 'choppay' THEN v_res := public.chop_pay_merchant_accept('repas', p_order_id);
    ELSE RAISE EXCEPTION 'UNSUPPORTED_TENDER'; END IF;
    v_next := 'confirmed';

  ELSIF p_action = 'prepare' THEN
    IF v_cur IN ('preparing','ready','out_for_delivery','completed') THEN
      RETURN jsonb_build_object('ok', true, 'idempotent', true, 'state', v_cur);
    END IF;
    IF v_cur <> 'confirmed' THEN RAISE EXCEPTION 'ILLEGAL_TRANSITION' USING DETAIL = v_cur; END IF;
    IF v_tender = 'cash' THEN v_res := public.cash_order_merchant_prepare('repas', p_order_id);
    ELSIF v_tender = 'choppay' THEN v_res := public.chop_pay_merchant_prepare('repas', p_order_id);
    ELSE RAISE EXCEPTION 'UNSUPPORTED_TENDER'; END IF;
    v_next := 'preparing';

  ELSIF p_action = 'ready' THEN
    IF v_cur IN ('ready','out_for_delivery','completed') THEN
      RETURN jsonb_build_object('ok', true, 'idempotent', true, 'state', v_cur);
    END IF;
    IF v_cur <> 'preparing' THEN RAISE EXCEPTION 'ILLEGAL_TRANSITION' USING DETAIL = v_cur; END IF;
    -- R6: mint the one-time custody credential for the correct holder.
    IF v_pickup THEN
      PERFORM public._repas_custody_issue(p_order_id, 'customer_pickup', v_o.user_id);
    ELSE
      PERFORM public._repas_custody_issue(p_order_id, 'restaurant_handoff', v_r.owner_user_id);
    END IF;
    v_next := 'ready';

  ELSIF p_action = 'handoff' THEN
    IF v_pickup THEN
      RAISE EXCEPTION 'PICKUP_HAS_NO_COURIER_HANDOFF';
    END IF;
    IF v_cur IN ('out_for_delivery','completed') THEN
      RETURN jsonb_build_object('ok', true, 'idempotent', true, 'state', v_cur);
    END IF;
    -- R6: possession changes only when the assigned courier proves the handoff.
    RAISE EXCEPTION 'HANDOFF_OWNED_BY_COURIER_CUSTODY'
      USING DETAIL = 'courier must call repas_custody_confirm_handoff';

  ELSIF p_action = 'reject' THEN
    IF v_cur = 'cancelled' THEN
      RETURN jsonb_build_object('ok', true, 'idempotent', true, 'state', v_cur);
    END IF;
    IF v_cur NOT IN ('placed','confirmed') THEN
      RAISE EXCEPTION 'ILLEGAL_TRANSITION' USING DETAIL = v_cur;
    END IF;
    IF v_tender = 'cash' AND EXISTS (SELECT 1 FROM public.cash_order_runtime
        WHERE source_module='repas' AND source_id=p_order_id) THEN
      v_res := public.cash_order_merchant_reject('repas', p_order_id, p_reason);
    ELSIF v_tender = 'choppay' AND EXISTS (SELECT 1 FROM public.chop_pay_order_runtime
        WHERE source_module='repas' AND source_id=p_order_id) THEN
      v_res := public.chop_pay_merchant_reject('repas', p_order_id, p_reason);
    END IF;
    v_next := 'cancelled';

  ELSIF p_action = 'complete' THEN
    IF v_pickup AND v_tender = 'choppay' THEN
      IF v_cur = 'completed' THEN
        RETURN jsonb_build_object('ok', true, 'idempotent', true, 'state', v_cur);
      END IF;
      -- R6: counter collection must be proven with the customer-held code.
      RAISE EXCEPTION 'PICKUP_REQUIRES_CUSTOMER_CODE'
        USING DETAIL = 'use repas_custody_confirm_pickup_collection';
    END IF;
    IF v_tender IN ('cash','choppay') THEN
      SELECT state INTO v_engine_state FROM public.cash_order_runtime
       WHERE source_module='repas' AND source_id=p_order_id;
      IF v_engine_state IS NULL THEN
        SELECT state INTO v_engine_state FROM public.chop_pay_order_runtime
         WHERE source_module='repas' AND source_id=p_order_id;
      END IF;
      IF COALESCE(v_engine_state,'none') <> 'completed' THEN
        RAISE EXCEPTION 'COMPLETION_OWNED_BY_DELIVERY_ENGINE'
          USING DETAIL = COALESCE(v_engine_state,'no_runtime');
      END IF;
    END IF;
    RETURN public.repas_complete_order(p_order_id, COALESCE(p_reason,'Restaurant completed order'));
  ELSE
    RAISE EXCEPTION 'UNKNOWN_ACTION' USING DETAIL = COALESCE(p_action,'null');
  END IF;

  IF v_next IS NOT NULL THEN
    PERFORM set_config('chopchop.cash_engine','1',true);
    UPDATE public.food_orders SET state = v_next::food_order_state, updated_at = now()
     WHERE id = p_order_id AND state::text <> v_next;
    PERFORM set_config('chopchop.cash_engine','0',true);
    IF v_next = 'cancelled' THEN
      UPDATE public.missions SET state = 'failed', updated_at = now()
       WHERE ref_food_order_id = p_order_id AND courier_id IS NULL AND state = 'assigned';
    END IF;
  END IF;

  RETURN jsonb_build_object('ok', true, 'idempotent', false, 'state', v_next, 'engine', v_res);
END; $function$;

REVOKE ALL ON FUNCTION public.repas_merchant_transition(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.repas_merchant_transition(uuid, text, text) TO authenticated, service_role;
