CREATE OR REPLACE FUNCTION public._chop_pay_complete_internal(
  p_source_module text, p_source_id uuid, p_actor uuid, p_from_dispute boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_row public.chop_pay_order_runtime; v_f jsonb; v_p public.merchant_payables;
  v_del jsonb; v_fee jsonb; v_rel jsonb; v_tail jsonb; v_pickup boolean := false;
  v_payout bigint; v_adj jsonb := jsonb_build_object('status','zero','delta_gnf',0);
BEGIN
  SELECT * INTO v_row FROM public.chop_pay_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id FOR UPDATE;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'CHOP_PAY_NOT_AUTHORIZED'; END IF;
  IF v_row.state = 'completed' THEN
    RETURN jsonb_build_object('status','already_completed','order_total_gnf',v_row.order_total_gnf);
  END IF;
  IF v_row.state = 'disputed' AND NOT p_from_dispute THEN RAISE EXCEPTION 'ORDER_IN_DISPUTE'; END IF;
  IF NOT (v_row.state IN ('preparing','merchant_accepted')
          OR (p_from_dispute AND v_row.state = 'disputed')) THEN
    RAISE EXCEPTION 'INVALID_STATE' USING DETAIL = v_row.state;
  END IF;
  IF p_source_module = 'repas' AND NOT p_from_dispute AND v_row.state <> 'preparing' THEN
    RAISE EXCEPTION 'PREPARATION_REQUIRED_BEFORE_DELIVERY';
  END IF;

  SELECT * INTO v_p FROM public.merchant_payables
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND merchant_store_id = v_row.merchant_store_id;
  IF v_p.id IS NULL OR v_p.funded_gnf < v_p.amount_gnf OR v_p.amount_gnf = 0 THEN
    RAISE EXCEPTION 'MERCHANDISE_FUNDING_NOT_SECURED';
  END IF;

  v_f := public._chop_pay_facts(p_source_module, p_source_id);
  v_pickup := COALESCE((v_f->>'is_pickup')::boolean,false) AND v_row.mission_id IS NULL;

  IF v_pickup THEN
    IF v_row.delivery_fee_gnf <> 0 OR v_row.collateral_gnf <> 0 THEN
      RAISE EXCEPTION 'PICKUP_ECONOMICS_CORRUPT';
    END IF;
  ELSE
    IF NOT COALESCE((v_f->>'pickup_confirmed')::boolean,false) THEN
      RAISE EXCEPTION 'CUSTODY_NOT_ESTABLISHED';
    END IF;
    IF COALESCE(v_f->>'mission_state','') NOT IN ('picked_up','heading_to_dropoff','arrived_dropoff','delivered') THEN
      RAISE EXCEPTION 'INVALID_MISSION_STATE' USING DETAIL = COALESCE(v_f->>'mission_state','none');
    END IF;
  END IF;

  v_del := public._chop_pay_customer_capture_internal(
    p_source_module, p_source_id, v_row.delivery_fee_gnf, 'delivery', p_actor);
  v_fee := public._chop_pay_customer_capture_internal(
    p_source_module, p_source_id, v_row.platform_fee_gnf, 'platform_fee', p_actor);

  -- R5: courier compensation is policy truth and independent of the customer
  -- price. Settle any gap against the platform master wallet.
  v_payout := CASE WHEN v_pickup THEN 0
                   ELSE GREATEST(COALESCE((v_f->>'courier_payout_gnf')::bigint,
                                          v_row.delivery_fee_gnf), 0) END;
  IF NOT v_pickup AND v_payout <> v_row.delivery_fee_gnf THEN
    v_adj := public._chop_pay_courier_adjust_internal(
      p_source_module, p_source_id, v_payout - v_row.delivery_fee_gnf,
      (v_f->>'courier_id')::uuid, p_actor);
  END IF;

  v_rel := public._driver_mission_hold_release_internal(
    p_source_module, p_source_id, 'collateral', 'chop_pay_completion', p_actor);
  v_tail := public._chop_pay_customer_release_internal(
    p_source_module, p_source_id, 'chop_pay_completion_residual', p_actor);

  UPDATE public.chop_pay_order_runtime
     SET state='completed', completed_at = now(),
         driver_earning_gnf = v_payout,
         courier_payout_gnf = v_payout,
         platform_revenue_gnf = v_row.platform_fee_gnf,
         merchant_credited_gnf = v_row.merchandise_subtotal_gnf
   WHERE id = v_row.id;

  PERFORM set_config('chopchop.cash_engine','1',true);
  IF p_source_module = 'repas' THEN
    UPDATE public.food_orders SET state='completed', completed_at = now()
     WHERE id = p_source_id AND state <> 'completed';
  ELSE
    UPDATE public.marketplace_offers
       SET fulfillment_status='delivered', fulfilled_at = COALESCE(fulfilled_at, now()),
           completed_at = COALESCE(completed_at, now()), updated_at = now()
     WHERE id = p_source_id;
  END IF;
  PERFORM set_config('chopchop.cash_engine','0',true);

  UPDATE public.missions
     SET state='delivered', dropoff_confirmed_at = COALESCE(dropoff_confirmed_at, now()),
         dropoff_confirmed_by = COALESCE(dropoff_confirmed_by, p_actor)
   WHERE id = v_row.mission_id AND state <> 'delivered';

  RETURN jsonb_build_object('status','completed',
    'customer_captured_gnf', v_row.order_total_gnf,
    'merchant_credited_gnf', v_row.merchandise_subtotal_gnf,
    'customer_delivery_fee_gnf', v_row.delivery_fee_gnf,
    'driver_earning_gnf', v_payout,
    'courier_payout_adjustment', v_adj,
    'platform_revenue_gnf', v_row.platform_fee_gnf,
    'collateral_release', v_rel, 'delivery_capture', v_del,
    'fee_capture', v_fee, 'residual_release', v_tail,
    'pickup', v_pickup,
    'commission_gnf', 0, 'driver_merchandise_advance_gnf', 0);
END; $function$;