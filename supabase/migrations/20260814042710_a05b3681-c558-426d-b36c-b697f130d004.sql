-- ============================================================
-- NODE 3 REPAS — R1–R4 MICRO-CLOSEOUT (MC1..MC6)
-- No flag changes. No economics changes. No new money primitives.
-- ============================================================

-- ---------- MC1 + MC2 + MC3: commitment authority ----------
CREATE OR REPLACE FUNCTION public.repas_order_create(
  p_restaurant_id uuid, p_items jsonb, p_fulfillment text, p_payment_method text,
  p_client_request_id uuid, p_delivery_address text DEFAULT NULL::text,
  p_delivery_lat double precision DEFAULT NULL::double precision,
  p_delivery_lng double precision DEFAULT NULL::double precision,
  p_notes text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_r public.food_restaurants%ROWTYPE;
  v_it jsonb; v_mi public.food_menu_items%ROWTYPE;
  v_qty int; v_sub bigint := 0;
  v_fp text; v_existing public.food_orders%ROWTYPE;
  v_order public.food_orders%ROWTYPE;
  v_mission_id uuid; v_del bigint := 0;
  v_auth jsonb := NULL; v_count int := 0;
  v_notes text; v_addr text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF p_client_request_id IS NULL THEN RAISE EXCEPTION 'CLIENT_REQUEST_ID_REQUIRED'; END IF;
  IF p_payment_method NOT IN ('cash','choppay') THEN
    RAISE EXCEPTION 'UNSUPPORTED_TENDER' USING DETAIL = COALESCE(p_payment_method,'null');
  END IF;
  IF p_fulfillment NOT IN ('pickup','delivery') THEN RAISE EXCEPTION 'INVALID_FULFILLMENT'; END IF;

  -- MC3: pickup is not a supported product yet (R4.5). Fail closed before any
  -- row, mission or money is created. This guard is removed by the R4.5 slice.
  IF p_fulfillment = 'pickup' THEN
    RAISE EXCEPTION 'PICKUP_NOT_YET_SUPPORTED'
      USING DETAIL = 'Repas pickup ships in R4.5; delivery is the only supported fulfillment';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'EMPTY_CART';
  END IF;
  IF jsonb_array_length(p_items) > 40 THEN RAISE EXCEPTION 'CART_TOO_LARGE'; END IF;

  v_notes := NULLIF(trim(COALESCE(p_notes,'')),'');
  v_addr  := NULLIF(trim(COALESCE(p_delivery_address,'')),'');

  -- MC1: deterministic fingerprint of the FULL authoritative customer intent.
  -- Coordinates are normalised to 6 decimals so float noise cannot forge a
  -- conflict, but a materially different drop-off point always does.
  v_fp := md5(
    p_restaurant_id::text || '|' || p_fulfillment || '|' || p_payment_method || '|' ||
    COALESCE(v_addr,'') || '|' ||
    COALESCE(round(p_delivery_lat::numeric, 6)::text,'') || '|' ||
    COALESCE(round(p_delivery_lng::numeric, 6)::text,'') || '|' ||
    COALESCE(v_notes,'') || '|' ||
    (SELECT COALESCE(string_agg(x.k, ','), '')
       FROM (SELECT (e->>'menu_item_id') || ':' || (e->>'qty') AS k
               FROM jsonb_array_elements(p_items) e ORDER BY 1) x)
  );

  SELECT * INTO v_existing FROM public.food_orders
   WHERE user_id = v_uid AND client_request_id = p_client_request_id FOR UPDATE;
  IF FOUND THEN
    IF v_existing.request_fingerprint IS DISTINCT FROM v_fp THEN
      RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT';
    END IF;
    SELECT id INTO v_mission_id FROM public.missions
      WHERE ref_food_order_id = v_existing.id ORDER BY created_at DESC LIMIT 1;
    RETURN jsonb_build_object('ok', true, 'replay', true, 'order_id', v_existing.id,
      'subtotal_gnf', v_existing.subtotal_gnf, 'state', v_existing.state,
      'payment_method', v_existing.payment_method, 'mission_id', v_mission_id);
  END IF;

  SELECT * INTO v_r FROM public.food_restaurants WHERE id = p_restaurant_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'RESTAURANT_NOT_FOUND'; END IF;
  IF v_r.status <> 'active' THEN RAISE EXCEPTION 'RESTAURANT_NOT_ORDERABLE'; END IF;
  IF NOT COALESCE(v_r.is_open, false) THEN RAISE EXCEPTION 'RESTAURANT_CLOSED'; END IF;
  IF p_fulfillment = 'delivery' AND NOT COALESCE(v_r.delivery_available,false) THEN
    RAISE EXCEPTION 'DELIVERY_NOT_AVAILABLE';
  END IF;
  IF p_fulfillment = 'delivery' AND v_addr IS NULL
     AND (p_delivery_lat IS NULL OR p_delivery_lng IS NULL) THEN
    RAISE EXCEPTION 'DELIVERY_LOCATION_REQUIRED';
  END IF;

  -- Rails must be enabled BEFORE any row is written.
  IF p_payment_method = 'choppay' AND NOT public._finance_flag('chop_pay_checkout_enabled') THEN
    RAISE EXCEPTION 'CHOP_PAY_CHECKOUT_DISABLED';
  END IF;
  -- MC2: a committed cash order is a promise the Slice 4 engine must be able
  -- to honour at courier engagement. If the funding rail is OFF, refuse now.
  IF p_payment_method = 'cash' AND NOT public._finance_flag('cash_order_funding_enabled') THEN
    RAISE EXCEPTION 'CASH_ORDER_FUNDING_DISABLED'
      USING DETAIL = 'cash order funding rail is disabled; commitment refused';
  END IF;

  INSERT INTO public.food_orders(
      user_id, restaurant_id, fulfillment, payment_method, subtotal_gnf, notes,
      delivery_address, delivery_lat, delivery_lng, state,
      client_request_id, request_fingerprint)
  VALUES (v_uid, p_restaurant_id, p_fulfillment::food_fulfillment,
          p_payment_method::food_payment_method, 0, v_notes,
          v_addr, p_delivery_lat, p_delivery_lng,
          'placed', p_client_request_id, v_fp)
  RETURNING * INTO v_order;

  FOR v_it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_qty := COALESCE((v_it->>'qty')::int, 0);
    IF v_qty <= 0 OR v_qty > 50 THEN RAISE EXCEPTION 'INVALID_QUANTITY'; END IF;
    SELECT * INTO v_mi FROM public.food_menu_items WHERE id = (v_it->>'menu_item_id')::uuid;
    IF NOT FOUND THEN RAISE EXCEPTION 'MENU_ITEM_NOT_FOUND'; END IF;
    IF v_mi.restaurant_id <> p_restaurant_id THEN RAISE EXCEPTION 'ITEM_WRONG_RESTAURANT'; END IF;
    IF NOT COALESCE(v_mi.is_available,false) THEN RAISE EXCEPTION 'ITEM_UNAVAILABLE'; END IF;
    INSERT INTO public.food_order_items(order_id, menu_item_id, name_snapshot, unit_price_gnf, qty)
    VALUES (v_order.id, v_mi.id, v_mi.name, v_mi.price_gnf, v_qty);
    v_sub := v_sub + (v_mi.price_gnf::bigint * v_qty);
    v_count := v_count + 1;
  END LOOP;
  IF v_count = 0 THEN RAISE EXCEPTION 'EMPTY_CART'; END IF;

  UPDATE public.food_orders SET subtotal_gnf = v_sub, updated_at = now()
   WHERE id = v_order.id RETURNING * INTO v_order;

  IF p_fulfillment = 'delivery' THEN
    v_del := public.repas_delivery_earning_gnf();
    INSERT INTO public.missions(type, customer_id, merchant_id, pickup_address,
        dropoff_address, dropoff_lat, dropoff_lng, payload_summary,
        estimated_earning_gnf, ref_food_order_id)
    VALUES ('food_delivery', v_uid, v_r.owner_user_id,
            COALESCE(NULLIF(v_r.district,''), '') || CASE WHEN COALESCE(v_r.district,'') <> ''
              THEN ' · ' ELSE '' END || v_r.name,
            v_order.delivery_address, p_delivery_lat, p_delivery_lng,
            v_r.name || ' · ' || v_count::text || ' article(s) · ' || v_sub::text || ' GNF',
            v_del, v_order.id)
    RETURNING id INTO v_mission_id;
  END IF;

  IF p_payment_method = 'choppay' THEN
    v_auth := public.chop_pay_authorize_order('repas', v_order.id);
  END IF;

  RETURN jsonb_build_object('ok', true, 'replay', false, 'order_id', v_order.id,
    'subtotal_gnf', v_sub, 'state', v_order.state, 'payment_method', p_payment_method,
    'mission_id', v_mission_id, 'delivery_fee_gnf', v_del, 'authorization', v_auth);
END; $function$;

-- ---------- MC4: cancellation routes on committed tender truth ----------
CREATE OR REPLACE FUNCTION public.repas_customer_cancel_order(
  p_order_id uuid, p_reason text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid(); v_o public.food_orders%ROWTYPE;
  v_res jsonb := NULL; v_cur text; v_tender text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  SELECT * INTO v_o FROM public.food_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  IF v_o.user_id <> v_uid THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  v_cur := v_o.state::text;
  IF v_cur = 'cancelled' THEN
    RETURN jsonb_build_object('ok', true, 'idempotent', true, 'state', v_cur);
  END IF;
  IF v_cur IN ('preparing','ready','out_for_delivery','completed') THEN
    RAISE EXCEPTION 'REPAS_PREPARATION_LOCKED' USING DETAIL = v_cur;
  END IF;

  -- Route on the tender committed at checkout, NOT on runtime existence.
  -- A pre-dispatch cash cancellation has no runtime yet but still owes the
  -- canonical Slice 8 cancellation policy.
  v_tender := v_o.payment_method::text;
  IF v_tender = 'cash' THEN
    v_res := public.cash_order_customer_cancel('repas', p_order_id, p_reason);
  ELSIF v_tender = 'choppay' THEN
    v_res := public.chop_pay_customer_cancel('repas', p_order_id, p_reason);
  ELSE
    RAISE EXCEPTION 'UNSUPPORTED_TENDER' USING DETAIL = COALESCE(v_tender,'null');
  END IF;

  PERFORM set_config('chopchop.cash_engine','1',true);
  UPDATE public.food_orders SET state = 'cancelled', updated_at = now()
   WHERE id = p_order_id AND state <> 'cancelled';
  PERFORM set_config('chopchop.cash_engine','0',true);

  UPDATE public.missions SET state = 'failed', updated_at = now()
   WHERE ref_food_order_id = p_order_id AND courier_id IS NULL AND state = 'assigned';

  RETURN jsonb_build_object('ok', true, 'idempotent', false, 'state', 'cancelled', 'engine', v_res);
END; $function$;

-- ---------- MC4b: completion is owned by the delivery/settlement engine ----------
CREATE OR REPLACE FUNCTION public.repas_merchant_transition(
  p_order_id uuid, p_action text, p_reason text DEFAULT NULL::text)
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
  v_engine_state text;
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
    v_next := 'ready';

  ELSIF p_action = 'handoff' THEN
    IF v_cur IN ('out_for_delivery','completed') THEN
      RETURN jsonb_build_object('ok', true, 'idempotent', true, 'state', v_cur);
    END IF;
    IF v_cur <> 'ready' THEN RAISE EXCEPTION 'ILLEGAL_TRANSITION' USING DETAIL = v_cur; END IF;
    v_next := 'out_for_delivery';

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
    -- MC4b: a merchant may not settle a funded rail by hand. Completion of a
    -- cash / Chop Pay order is owned by the courier delivery confirmation,
    -- which drives the locked Slice 4 / Slice 5 engines.
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

REVOKE ALL ON FUNCTION public.repas_order_create(uuid,jsonb,text,text,uuid,text,double precision,double precision,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.repas_customer_cancel_order(uuid,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.repas_merchant_transition(uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.repas_order_create(uuid,jsonb,text,text,uuid,text,double precision,double precision,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.repas_customer_cancel_order(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.repas_merchant_transition(uuid,text,text) TO authenticated;
