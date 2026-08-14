-- Supabase default-privileges grant EXECUTE to anon on new public functions;
-- revoke explicitly on the R5 surface.
REVOKE EXECUTE ON FUNCTION public.repas_quote_preview(uuid, jsonb, text, double precision, double precision) FROM anon;
REVOKE EXECUTE ON FUNCTION public.repas_pricing_effective(text, timestamptz) FROM anon;
REVOKE EXECUTE ON FUNCTION public.repas_delivery_distance_km(uuid, double precision, double precision) FROM anon;
REVOKE EXECUTE ON FUNCTION public.repas_platform_fee_gnf(bigint, bigint, text, integer) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_set_repas_promotion(text, text, timestamptz, timestamptz, text, bigint, bigint) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_disable_repas_promotion(uuid, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.admin_set_finance_policy(
  text, integer, bigint, text, integer, bigint, bigint, bigint, bigint, boolean,
  timestamptz, text, text, integer, text, integer, integer, text, text, integer,
  bigint, bigint, bigint, bigint, numeric, integer, bigint) FROM anon;

-- Honest zone enforcement: verify when verifiable, refuse a missing customer
-- destination, never fabricate a distance for a restaurant with no location.
CREATE OR REPLACE FUNCTION public.repas_order_create(
  p_restaurant_id uuid, p_items jsonb, p_fulfillment text, p_payment_method text,
  p_client_request_id uuid, p_delivery_address text DEFAULT NULL,
  p_delivery_lat double precision DEFAULT NULL, p_delivery_lng double precision DEFAULT NULL,
  p_notes text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_r public.food_restaurants%ROWTYPE;
  v_it jsonb; v_mi public.food_menu_items%ROWTYPE;
  v_qty int; v_sub bigint := 0;
  v_fp text; v_existing public.food_orders%ROWTYPE;
  v_order public.food_orders%ROWTYPE;
  v_mission_id uuid; v_del bigint := 0;
  v_auth jsonb := NULL; v_count int := 0;
  v_notes text; v_addr text; v_pickup boolean;
  v_lat double precision; v_lng double precision;
  v_eff jsonb; v_base bigint := 0; v_disc bigint := 0; v_fee bigint := 0;
  v_payout bigint := 0; v_max numeric; v_dist numeric := NULL; v_geo boolean := false;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF p_client_request_id IS NULL THEN RAISE EXCEPTION 'CLIENT_REQUEST_ID_REQUIRED'; END IF;
  IF p_payment_method NOT IN ('cash','choppay') THEN
    RAISE EXCEPTION 'UNSUPPORTED_TENDER' USING DETAIL = COALESCE(p_payment_method,'null');
  END IF;
  IF p_fulfillment NOT IN ('pickup','delivery') THEN RAISE EXCEPTION 'INVALID_FULFILLMENT'; END IF;
  v_pickup := (p_fulfillment = 'pickup');

  IF v_pickup AND p_payment_method = 'cash' THEN
    RAISE EXCEPTION 'PICKUP_CASH_NOT_SUPPORTED'
      USING DETAIL = 'cash pickup awaits a canonical merchant-fee primitive';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'EMPTY_CART';
  END IF;
  IF jsonb_array_length(p_items) > 40 THEN RAISE EXCEPTION 'CART_TOO_LARGE'; END IF;

  v_notes := NULLIF(trim(COALESCE(p_notes,'')),'');
  v_addr := CASE WHEN v_pickup THEN NULL ELSE NULLIF(trim(COALESCE(p_delivery_address,'')),'') END;
  v_lat  := CASE WHEN v_pickup THEN NULL ELSE p_delivery_lat END;
  v_lng  := CASE WHEN v_pickup THEN NULL ELSE p_delivery_lng END;

  v_fp := md5(
    p_restaurant_id::text || '|' || p_fulfillment || '|' || p_payment_method || '|' ||
    COALESCE(v_addr,'') || '|' ||
    COALESCE(round(v_lat::numeric, 6)::text,'') || '|' ||
    COALESCE(round(v_lng::numeric, 6)::text,'') || '|' ||
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
      'payment_method', v_existing.payment_method, 'mission_id', v_mission_id,
      'fulfillment', v_existing.fulfillment,
      'delivery_fee_gnf', COALESCE(v_existing.delivery_fee_gnf,0),
      'platform_fee_gnf', COALESCE(v_existing.platform_fee_gnf,0),
      'order_total_gnf', COALESCE(v_existing.order_total_gnf, v_existing.subtotal_gnf));
  END IF;

  SELECT * INTO v_r FROM public.food_restaurants WHERE id = p_restaurant_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'RESTAURANT_NOT_FOUND'; END IF;
  IF v_r.status <> 'active' THEN RAISE EXCEPTION 'RESTAURANT_NOT_ORDERABLE'; END IF;
  IF NOT COALESCE(v_r.is_open, false) THEN RAISE EXCEPTION 'RESTAURANT_CLOSED'; END IF;
  IF v_pickup AND NOT COALESCE(v_r.pickup_available,false) THEN
    RAISE EXCEPTION 'PICKUP_NOT_AVAILABLE';
  END IF;
  IF NOT v_pickup AND NOT COALESCE(v_r.delivery_available,false) THEN
    RAISE EXCEPTION 'DELIVERY_NOT_AVAILABLE';
  END IF;
  IF NOT v_pickup AND v_addr IS NULL AND (v_lat IS NULL OR v_lng IS NULL) THEN
    RAISE EXCEPTION 'DELIVERY_LOCATION_REQUIRED';
  END IF;

  IF p_payment_method = 'choppay' AND NOT public._finance_flag('chop_pay_checkout_enabled') THEN
    RAISE EXCEPTION 'CHOP_PAY_CHECKOUT_DISABLED';
  END IF;
  IF p_payment_method = 'cash' AND NOT public._finance_flag('cash_order_funding_enabled') THEN
    RAISE EXCEPTION 'CASH_ORDER_FUNDING_DISABLED'
      USING DETAIL = 'cash order funding rail is disabled; commitment refused';
  END IF;

  v_eff   := public.repas_pricing_effective(p_fulfillment, now());
  v_base  := COALESCE((v_eff->>'base_delivery_fee_gnf')::bigint, 0);
  v_del   := COALESCE((v_eff->>'customer_delivery_fee_gnf')::bigint, 0);
  v_disc  := COALESCE((v_eff->>'promo_discount_gnf')::bigint, 0);
  v_payout:= COALESCE((v_eff->>'courier_payout_gnf')::bigint, 0);

  IF NOT v_pickup THEN
    v_geo := (v_r.latitude IS NOT NULL AND v_r.longitude IS NOT NULL);
    v_max := NULLIF(v_eff->>'delivery_max_distance_km','')::numeric;
    IF v_max IS NOT NULL AND v_geo THEN
      IF v_lat IS NULL OR v_lng IS NULL THEN
        RAISE EXCEPTION 'DELIVERY_DISTANCE_UNVERIFIABLE'
          USING DETAIL = 'destination coordinates required for this restaurant';
      END IF;
      v_dist := public.repas_delivery_distance_km(p_restaurant_id, v_lat, v_lng);
      IF v_dist IS NULL THEN
        RAISE EXCEPTION 'DELIVERY_DISTANCE_UNVERIFIABLE';
      END IF;
      IF v_dist > v_max THEN
        RAISE EXCEPTION 'OUTSIDE_DELIVERY_ZONE'
          USING DETAIL = format('%s km > %s km', v_dist, v_max);
      END IF;
    ELSE
      -- Restaurant has no mapped location yet: distance stays honestly unknown.
      v_dist := public.repas_delivery_distance_km(p_restaurant_id, v_lat, v_lng);
      v_eff := v_eff || jsonb_build_object('distance_verified', false);
    END IF;

    IF p_payment_method = 'cash' AND v_del <> v_payout THEN
      RAISE EXCEPTION 'CASH_DELIVERY_PRICING_UNSUPPORTED'
        USING DETAIL = format('customer=%s courier=%s', v_del, v_payout);
    END IF;
  END IF;

  INSERT INTO public.food_orders(
      user_id, restaurant_id, fulfillment, payment_method, subtotal_gnf, notes,
      delivery_address, delivery_lat, delivery_lng, state,
      client_request_id, request_fingerprint,
      pricing_policy_id, promotion_id, base_delivery_fee_gnf, delivery_fee_gnf,
      promo_discount_gnf, courier_payout_gnf, delivery_distance_km, pricing_snapshot)
  VALUES (v_uid, p_restaurant_id, p_fulfillment::food_fulfillment,
          p_payment_method::food_payment_method, 0, v_notes,
          v_addr, v_lat, v_lng,
          'placed', p_client_request_id, v_fp,
          NULLIF(v_eff->>'policy_id','')::uuid,
          NULLIF(v_eff->>'promotion_id','')::uuid,
          v_base, v_del, v_disc, CASE WHEN v_pickup THEN 0 ELSE v_payout END,
          v_dist, v_eff)
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

  v_fee := public.repas_platform_fee_gnf(v_sub, v_del, v_eff->>'fee_basis',
                                         (v_eff->>'platform_fee_bps')::int);

  UPDATE public.food_orders
     SET subtotal_gnf = v_sub, platform_fee_gnf = v_fee,
         order_total_gnf = v_sub + v_del + v_fee, updated_at = now()
   WHERE id = v_order.id RETURNING * INTO v_order;

  IF NOT v_pickup THEN
    INSERT INTO public.missions(type, customer_id, merchant_id, pickup_address,
        dropoff_address, dropoff_lat, dropoff_lng, payload_summary,
        estimated_earning_gnf, ref_food_order_id)
    VALUES ('food_delivery', v_uid, v_r.owner_user_id,
            COALESCE(NULLIF(v_r.district,''), '') || CASE WHEN COALESCE(v_r.district,'') <> ''
              THEN ' · ' ELSE '' END || v_r.name,
            v_order.delivery_address, v_lat, v_lng,
            v_r.name || ' · ' || v_count::text || ' article(s) · ' || v_sub::text || ' GNF',
            v_payout, v_order.id)
    RETURNING id INTO v_mission_id;
  END IF;

  IF p_payment_method = 'choppay' THEN
    v_auth := public.chop_pay_authorize_order('repas', v_order.id);
  END IF;

  RETURN jsonb_build_object('ok', true, 'replay', false, 'order_id', v_order.id,
    'subtotal_gnf', v_sub, 'state', v_order.state, 'payment_method', p_payment_method,
    'fulfillment', p_fulfillment,
    'mission_id', v_mission_id,
    'base_delivery_fee_gnf', v_base, 'delivery_fee_gnf', v_del,
    'promo_discount_gnf', v_disc, 'platform_fee_gnf', v_fee,
    'courier_payout_gnf', CASE WHEN v_pickup THEN 0 ELSE v_payout END,
    'order_total_gnf', v_sub + v_del + v_fee,
    'delivery_distance_km', v_dist,
    'distance_verified', COALESCE((v_eff->>'distance_verified')::boolean, v_dist IS NOT NULL),
    'authorization', v_auth);
END; $$;
REVOKE ALL ON FUNCTION public.repas_order_create(uuid, jsonb, text, text, uuid, text, double precision, double precision, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.repas_order_create(uuid, jsonb, text, text, uuid, text, double precision, double precision, text) TO authenticated, service_role;

-- Same honesty in the preview.
CREATE OR REPLACE FUNCTION public.repas_quote_preview(
  p_restaurant_id uuid, p_items jsonb, p_fulfillment text,
  p_delivery_lat double precision DEFAULT NULL,
  p_delivery_lng double precision DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid(); v_r public.food_restaurants%ROWTYPE;
  v_it jsonb; v_mi public.food_menu_items%ROWTYPE; v_qty int;
  v_sub bigint := 0; v_pickup boolean; v_eff jsonb;
  v_del bigint; v_fee bigint; v_max numeric; v_dist numeric; v_eligible boolean := true;
  v_reason text := NULL; v_geo boolean := false;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF p_fulfillment NOT IN ('pickup','delivery') THEN RAISE EXCEPTION 'INVALID_FULFILLMENT'; END IF;
  v_pickup := (p_fulfillment = 'pickup');

  SELECT * INTO v_r FROM public.food_restaurants WHERE id = p_restaurant_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'RESTAURANT_NOT_FOUND'; END IF;
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'EMPTY_CART';
  END IF;

  FOR v_it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_qty := COALESCE((v_it->>'qty')::int, 0);
    IF v_qty <= 0 OR v_qty > 50 THEN RAISE EXCEPTION 'INVALID_QUANTITY'; END IF;
    SELECT * INTO v_mi FROM public.food_menu_items WHERE id = (v_it->>'menu_item_id')::uuid;
    IF NOT FOUND THEN RAISE EXCEPTION 'MENU_ITEM_NOT_FOUND'; END IF;
    IF v_mi.restaurant_id <> p_restaurant_id THEN RAISE EXCEPTION 'ITEM_WRONG_RESTAURANT'; END IF;
    v_sub := v_sub + (v_mi.price_gnf::bigint * v_qty);
  END LOOP;

  v_eff := public.repas_pricing_effective(p_fulfillment, now());
  v_del := COALESCE((v_eff->>'customer_delivery_fee_gnf')::bigint, 0);
  v_fee := public.repas_platform_fee_gnf(v_sub, v_del, v_eff->>'fee_basis',
                                         (v_eff->>'platform_fee_bps')::int);

  IF NOT v_pickup THEN
    v_geo := (v_r.latitude IS NOT NULL AND v_r.longitude IS NOT NULL);
    v_max  := NULLIF(v_eff->>'delivery_max_distance_km','')::numeric;
    v_dist := public.repas_delivery_distance_km(p_restaurant_id, p_delivery_lat, p_delivery_lng);
    IF v_max IS NOT NULL AND v_geo THEN
      IF p_delivery_lat IS NULL OR p_delivery_lng IS NULL THEN
        v_eligible := false; v_reason := 'DESTINATION_REQUIRED';
      ELSIF v_dist IS NULL THEN
        v_eligible := false; v_reason := 'DISTANCE_UNKNOWN';
      ELSIF v_dist > v_max THEN
        v_eligible := false; v_reason := 'OUTSIDE_DELIVERY_ZONE';
      END IF;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'fulfillment', p_fulfillment,
    'merchandise_subtotal_gnf', v_sub,
    'base_delivery_fee_gnf', COALESCE((v_eff->>'base_delivery_fee_gnf')::bigint,0),
    'delivery_fee_gnf', v_del,
    'promo_discount_gnf', COALESCE((v_eff->>'promo_discount_gnf')::bigint,0),
    'promotion_id', v_eff->>'promotion_id',
    'promotion_name', v_eff->>'promotion_name',
    'platform_fee_gnf', v_fee,
    'order_total_gnf', v_sub + v_del + v_fee,
    'courier_payout_gnf', COALESCE((v_eff->>'courier_payout_gnf')::bigint,0),
    'delivery_distance_km', v_dist,
    'delivery_max_distance_km', v_max,
    'distance_verified', v_geo,
    'delivery_eligible', v_eligible,
    'ineligible_reason', v_reason,
    'pickup_available', COALESCE(v_r.pickup_available,false),
    'delivery_available', COALESCE(v_r.delivery_available,false),
    'chop_pay_enabled', public._finance_flag('chop_pay_checkout_enabled'),
    'cash_enabled', public._finance_flag('cash_order_funding_enabled'),
    'cash_pickup_supported', false,
    'policy_id', v_eff->>'policy_id',
    'policy_effective_from', v_eff->>'policy_effective_from',
    'transaction_fee_bps', (v_eff->>'platform_fee_bps')::int);
END; $$;
REVOKE ALL ON FUNCTION public.repas_quote_preview(uuid, jsonb, text, double precision, double precision) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.repas_quote_preview(uuid, jsonb, text, double precision, double precision) TO authenticated, service_role;

-- Re-run the board.
DELETE FROM public._qa_s13_results WHERE part BETWEEN 501 AND 506;
INSERT INTO public._qa_s13_results(part, result)
SELECT 501, jsonb_build_object('suite','node3_repas_r5',
  'pass', count(*) FILTER (WHERE ok), 'fail', count(*) FILTER (WHERE NOT ok),
  'failures', COALESCE(jsonb_agg(jsonb_build_object('section',section,'name',name,'detail',detail))
                        FILTER (WHERE NOT ok), '[]'::jsonb))
FROM public._qa_node3_repas_r5();

INSERT INTO public._qa_s13_results(part, result)
VALUES (502, jsonb_build_object('suite','node3_repas_r1_r4','result', public._qa_node3_repas_r1_r4())),
       (503, jsonb_build_object('suite','node3_repas_pickup','result', public._qa_node3_repas_pickup())),
       (504, jsonb_build_object('suite','node0_course','result', public._qa_node0_course())),
       (505, jsonb_build_object('suite','node1_bonbonna_full','result', public._qa_node1_bonbonna_full())),
       (506, jsonb_build_object('suite','node2_taxi_full','result', public._qa_node2_taxi_full()));