-- ============================================================
-- NODE 3 / REPAS R11 — CONAKRY DESTINATION TRUTH + HARDENING
-- ============================================================

ALTER TABLE public.food_orders
  ADD COLUMN IF NOT EXISTS delivery_landmark text,
  ADD COLUMN IF NOT EXISTS delivery_instructions text,
  ADD COLUMN IF NOT EXISTS delivery_location_source text,
  ADD COLUMN IF NOT EXISTS delivery_location_quality text;

ALTER TABLE public.food_orders
  DROP CONSTRAINT IF EXISTS food_orders_delivery_location_source_chk;
ALTER TABLE public.food_orders
  ADD CONSTRAINT food_orders_delivery_location_source_chk
  CHECK (delivery_location_source IS NULL OR delivery_location_source IN
    ('gps','manual_pin','saved_place','typed','unspecified','none'));

ALTER TABLE public.food_orders
  DROP CONSTRAINT IF EXISTS food_orders_delivery_location_quality_chk;
ALTER TABLE public.food_orders
  ADD CONSTRAINT food_orders_delivery_location_quality_chk
  CHECK (delivery_location_quality IS NULL OR delivery_location_quality IN
    ('gps_verified','manually_placed','approximate','landmark_assisted','unverifiable'));

COMMENT ON COLUMN public.food_orders.delivery_location_quality IS
  'R11 server-derived honesty signal. Never client-declared, never fabricated.';

-- ---------- server-only quality derivation ----------
CREATE OR REPLACE FUNCTION public._repas_location_quality(
  p_source text, p_lat double precision, p_lng double precision,
  p_label text, p_landmark text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN p_lat IS NULL OR p_lng IS NULL THEN
      CASE WHEN COALESCE(NULLIF(btrim(COALESCE(p_landmark,'')),''),
                         NULLIF(btrim(COALESCE(p_label,'')),'')) IS NOT NULL
           THEN 'landmark_assisted' ELSE 'unverifiable' END
    WHEN p_source = 'gps' THEN 'gps_verified'
    WHEN p_source = 'manual_pin' THEN 'manually_placed'
    ELSE 'approximate'
  END
$$;
REVOKE ALL ON FUNCTION public._repas_location_quality(text,double precision,double precision,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._repas_location_quality(text,double precision,double precision,text,text) TO authenticated, service_role;

-- ---------- committed destination is frozen ----------
CREATE OR REPLACE FUNCTION public._repas_destination_immutable()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF NEW.delivery_address        IS DISTINCT FROM OLD.delivery_address
  OR NEW.delivery_lat            IS DISTINCT FROM OLD.delivery_lat
  OR NEW.delivery_lng            IS DISTINCT FROM OLD.delivery_lng
  OR NEW.delivery_landmark       IS DISTINCT FROM OLD.delivery_landmark
  OR NEW.delivery_instructions   IS DISTINCT FROM OLD.delivery_instructions
  OR NEW.delivery_location_source  IS DISTINCT FROM OLD.delivery_location_source
  OR NEW.delivery_location_quality IS DISTINCT FROM OLD.delivery_location_quality THEN
    RAISE EXCEPTION 'REPAS_DESTINATION_IMMUTABLE'
      USING DETAIL = 'a committed order destination snapshot cannot be rewritten';
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_repas_destination_immutable ON public.food_orders;
CREATE TRIGGER trg_repas_destination_immutable
  BEFORE UPDATE ON public.food_orders
  FOR EACH ROW EXECUTE FUNCTION public._repas_destination_immutable();

-- ---------- canonical order creation (R11 destination-aware) ----------
DROP FUNCTION IF EXISTS public.repas_order_create(uuid,jsonb,text,text,uuid,text,double precision,double precision,text);

CREATE OR REPLACE FUNCTION public.repas_order_create(
  p_restaurant_id uuid, p_items jsonb, p_fulfillment text, p_payment_method text,
  p_client_request_id uuid,
  p_delivery_address text DEFAULT NULL, p_delivery_lat double precision DEFAULT NULL,
  p_delivery_lng double precision DEFAULT NULL, p_notes text DEFAULT NULL,
  p_delivery_landmark text DEFAULT NULL, p_delivery_instructions text DEFAULT NULL,
  p_location_source text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
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
  v_land text; v_instr text; v_src text; v_qual text;
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

  v_notes := NULLIF(btrim(COALESCE(p_notes,'')),'');

  -- R11 / D — Retrait carries NO delivery destination whatsoever.
  IF v_pickup THEN
    v_addr := NULL; v_lat := NULL; v_lng := NULL;
    v_land := NULL; v_instr := NULL; v_src := NULL; v_qual := NULL;
  ELSE
    v_addr  := NULLIF(btrim(COALESCE(p_delivery_address,'')),'');
    v_lat   := p_delivery_lat;
    v_lng   := p_delivery_lng;
    v_land  := left(NULLIF(btrim(COALESCE(p_delivery_landmark,'')),''), 240);
    v_instr := left(NULLIF(btrim(COALESCE(p_delivery_instructions,'')),''), 400);
    v_src := CASE
      WHEN v_lat IS NULL OR v_lng IS NULL THEN
        CASE WHEN COALESCE(v_addr, v_land) IS NOT NULL THEN 'typed' ELSE 'none' END
      WHEN p_location_source IN ('gps','manual_pin','saved_place') THEN p_location_source
      ELSE 'unspecified' END;
    v_qual := public._repas_location_quality(v_src, v_lat, v_lng, v_addr, v_land);
  END IF;

  v_fp := md5(
    p_restaurant_id::text || '|' || p_fulfillment || '|' || p_payment_method || '|' ||
    COALESCE(v_addr,'') || '|' ||
    COALESCE(round(v_lat::numeric, 6)::text,'') || '|' ||
    COALESCE(round(v_lng::numeric, 6)::text,'') || '|' ||
    COALESCE(v_land,'') || '|' || COALESCE(v_instr,'') || '|' || COALESCE(v_src,'') || '|' ||
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
      'location_quality', v_existing.delivery_location_quality,
      'order_total_gnf', COALESCE(v_existing.order_total_gnf, v_existing.subtotal_gnf));
  END IF;

  SELECT * INTO v_r FROM public.food_restaurants WHERE id = p_restaurant_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'RESTAURANT_NOT_FOUND'; END IF;
  PERFORM public._repas_assert_orderable_publication(v_r);
  IF NOT COALESCE(v_r.is_open, false) THEN RAISE EXCEPTION 'RESTAURANT_CLOSED'; END IF;
  IF v_pickup AND NOT COALESCE(v_r.pickup_available,false) THEN
    RAISE EXCEPTION 'PICKUP_NOT_AVAILABLE';
  END IF;
  IF NOT v_pickup AND NOT COALESCE(v_r.delivery_available,false) THEN
    RAISE EXCEPTION 'DELIVERY_NOT_AVAILABLE';
  END IF;
  IF NOT v_pickup AND v_addr IS NULL AND v_land IS NULL AND (v_lat IS NULL OR v_lng IS NULL) THEN
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
    ELSIF v_max IS NOT NULL THEN
      RAISE EXCEPTION 'DELIVERY_DISTANCE_UNVERIFIABLE'
        USING DETAIL = 'restaurant location is not mapped; server distance cannot be verified';
    ELSE
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
      delivery_landmark, delivery_instructions,
      delivery_location_source, delivery_location_quality,
      client_request_id, request_fingerprint,
      pricing_policy_id, promotion_id, base_delivery_fee_gnf, delivery_fee_gnf,
      promo_discount_gnf, courier_payout_gnf, delivery_distance_km, pricing_snapshot)
  VALUES (v_uid, p_restaurant_id, p_fulfillment::food_fulfillment,
          p_payment_method::food_payment_method, 0, v_notes,
          v_addr, v_lat, v_lng, 'placed',
          v_land, v_instr, v_src, v_qual,
          p_client_request_id, v_fp,
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
            COALESCE(v_order.delivery_address, v_land),
            v_lat, v_lng,
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
    'location_source', v_src, 'location_quality', v_qual,
    'distance_verified', COALESCE((v_eff->>'distance_verified')::boolean, v_dist IS NOT NULL),
    'authorization', v_auth);
END; $function$;

REVOKE ALL ON FUNCTION public.repas_order_create(uuid,jsonb,text,text,uuid,text,double precision,double precision,text,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.repas_order_create(uuid,jsonb,text,text,uuid,text,double precision,double precision,text,text,text,text) TO authenticated, service_role;

-- ---------- tracking exposes canonical destination truth ----------
CREATE OR REPLACE FUNCTION public.repas_order_tracking(p_order_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_o public.food_orders%ROWTYPE;
  v_r public.food_restaurants%ROWTYPE;
  v_m public.missions%ROWTYPE;
  v_role text; v_pickup boolean; v_terminal boolean;
  v_terminal_reason text := NULL; v_engine_state text := NULL;
  v_dispute_reason text := NULL; v_cash_due bigint := NULL;
  v_actions text[] := '{}'; v_custody jsonb; v_pending text := NULL;
  v_courier jsonb := NULL; v_customer jsonb := NULL; v_base jsonb;
  v_dest jsonb := NULL; v_dest_geo jsonb := NULL;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  SELECT * INTO v_o FROM public.food_orders WHERE id = p_order_id;
  IF v_o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  SELECT * INTO v_r FROM public.food_restaurants WHERE id = v_o.restaurant_id;

  v_pickup := (v_o.fulfillment::text = 'pickup');

  IF NOT v_pickup THEN
    SELECT * INTO v_m FROM public.missions
     WHERE ref_food_order_id = p_order_id ORDER BY created_at DESC LIMIT 1;
  END IF;

  IF v_uid = v_o.user_id THEN v_role := 'customer';
  ELSIF v_uid = v_r.owner_user_id THEN v_role := 'merchant';
  ELSIF v_m.id IS NOT NULL AND v_uid = v_m.courier_id THEN v_role := 'courier';
  ELSIF public._finance_privileged(v_uid) THEN v_role := 'finance';
  ELSE RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  SELECT state, dispute_reason INTO v_engine_state, v_dispute_reason
    FROM public.chop_pay_order_runtime
   WHERE source_module = 'repas' AND source_id = p_order_id;
  IF v_engine_state IS NULL THEN
    SELECT state, dispute_reason, cash_due_gnf
      INTO v_engine_state, v_dispute_reason, v_cash_due
      FROM public.cash_order_runtime
     WHERE source_module = 'repas' AND source_id = p_order_id;
  END IF;

  v_terminal := v_o.state::text IN ('completed','cancelled');
  IF v_o.state::text = 'cancelled' THEN
    v_terminal_reason := COALESCE(v_dispute_reason, 'ORDER_CANCELLED');
  ELSIF v_engine_state = 'disputed' THEN
    v_terminal_reason := COALESCE(v_dispute_reason, 'ORDER_DISPUTED');
  ELSIF NOT v_pickup AND v_m.id IS NOT NULL AND v_m.state::text = 'failed' THEN
    v_terminal_reason := COALESCE(v_m.issue_reason, 'DELIVERY_FAILED');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'kind', c.kind, 'consumed', c.consumed_at IS NOT NULL,
           'locked', c.locked_at IS NOT NULL,
           'holder_is_self', c.holder_user_id = v_uid)), '[]'::jsonb)
    INTO v_custody FROM public.repas_custody_credentials c WHERE c.order_id = p_order_id;

  SELECT c.kind INTO v_pending FROM public.repas_custody_credentials c
   WHERE c.order_id = p_order_id AND c.consumed_at IS NULL AND c.locked_at IS NULL
   ORDER BY c.created_at DESC LIMIT 1;

  IF v_role IN ('merchant','finance') AND NOT v_terminal THEN
    v_actions := CASE v_o.state::text
      WHEN 'placed'    THEN ARRAY['accept','reject']
      WHEN 'confirmed' THEN ARRAY['prepare','reject']
      WHEN 'preparing' THEN ARRAY['ready']
      WHEN 'ready'     THEN CASE WHEN v_pickup THEN ARRAY['pickup_collection'] ELSE '{}'::text[] END
      ELSE '{}'::text[]
    END;
  END IF;

  IF v_role IN ('customer','finance') AND v_m.id IS NOT NULL AND v_m.courier_id IS NOT NULL AND NOT v_terminal THEN
    SELECT jsonb_build_object('full_name', p.full_name, 'phone', p.phone)
      INTO v_courier FROM public.profiles p WHERE p.user_id = v_m.courier_id;
  END IF;
  IF v_role IN ('merchant','courier','finance') THEN
    SELECT jsonb_build_object('full_name', p.full_name, 'phone', p.phone)
      INTO v_customer FROM public.profiles p WHERE p.user_id = v_o.user_id;
  END IF;

  -- R11 — frozen destination snapshot. Never re-derived, never geocoded.
  IF NOT v_pickup THEN
    v_dest := jsonb_build_object(
      'label', v_o.delivery_address,
      'landmark', v_o.delivery_landmark,
      'instructions', v_o.delivery_instructions,
      'location_source', v_o.delivery_location_source,
      'location_quality', v_o.delivery_location_quality,
      'has_coordinates', (v_o.delivery_lat IS NOT NULL AND v_o.delivery_lng IS NOT NULL));
    IF v_role IN ('courier','finance') THEN
      v_dest_geo := jsonb_build_object('lat', v_o.delivery_lat, 'lng', v_o.delivery_lng);
      v_dest := v_dest || jsonb_build_object('coordinates', v_dest_geo);
    END IF;
  END IF;

  v_base := jsonb_build_object(
    'order_id', v_o.id, 'viewer_role', v_role, 'state', v_o.state::text,
    'fulfillment', v_o.fulfillment::text, 'terminal', v_terminal,
    'terminal_reason', v_terminal_reason, 'engine_state', v_engine_state,
    'restaurant', jsonb_build_object(
      'id', v_r.id, 'name', v_r.name, 'district', v_r.district,
      'prep_time_min', v_r.prep_time_min),
    'created_at', v_o.created_at, 'updated_at', v_o.updated_at,
    'completed_at', v_o.completed_at,
    'destination', v_dest,
    'custody', jsonb_build_object('credentials', v_custody, 'pending_kind', v_pending),
    'mission', CASE
      WHEN v_pickup OR v_m.id IS NULL THEN NULL
      ELSE jsonb_build_object(
        'id', v_m.id, 'state', v_m.state::text,
        'courier_assigned', v_m.courier_id IS NOT NULL,
        'pickup_confirmed_at', v_m.pickup_confirmed_at,
        'dropoff_confirmed_at', v_m.dropoff_confirmed_at)
    END);

  IF v_role = 'customer' THEN
    RETURN v_base || jsonb_build_object(
      'payment_method', v_o.payment_method::text,
      'payment_status', v_o.payment_status,
      'order_total_gnf', COALESCE(v_o.order_total_gnf, v_o.subtotal_gnf),
      'delivery_address', v_o.delivery_address,
      'courier', v_courier);
  ELSIF v_role = 'courier' THEN
    RETURN v_base || jsonb_build_object(
      'payment_method', v_o.payment_method::text,
      'cash_due_gnf', v_cash_due, 'customer', v_customer,
      'delivery_address', v_o.delivery_address,
      'pickup_address', v_m.pickup_address);
  ELSE
    RETURN v_base || jsonb_build_object(
      'payment_method', v_o.payment_method::text,
      'payment_status', v_o.payment_status,
      'allowed_actions', to_jsonb(v_actions),
      'customer', v_customer,
      'merchandise_subtotal_gnf', v_o.subtotal_gnf,
      'delivery_address', v_o.delivery_address);
  END IF;
END; $function$;

REVOKE ALL ON FUNCTION public.repas_order_tracking(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.repas_order_tracking(uuid) TO authenticated, service_role;

-- ---------- R10 ops detail surfaces R11 destination posture (read-only) ----------
CREATE OR REPLACE FUNCTION public.repas_ops_case_detail(p_order_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  v_uid uuid := auth.uid(); v_role text;
  v_o public.food_orders%ROWTYPE; v_r public.food_restaurants%ROWTYPE;
  v_m public.missions%ROWTYPE; v_case public.repas_ops_cases%ROWTYPE;
  v_engine text; v_dispute text; v_timeline jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  v_role := public._repas_ops_actor_role(v_uid);
  IF v_role IS NULL THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;

  SELECT * INTO v_o FROM public.food_orders WHERE id = p_order_id;
  IF v_o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  SELECT * INTO v_r FROM public.food_restaurants WHERE id = v_o.restaurant_id;
  SELECT * INTO v_m FROM public.missions WHERE ref_food_order_id = p_order_id
   ORDER BY created_at DESC LIMIT 1;
  SELECT * INTO v_case FROM public.repas_ops_cases WHERE food_order_id = p_order_id
   ORDER BY (status <> 'resolved') DESC, created_at DESC LIMIT 1;

  SELECT state, dispute_reason INTO v_engine, v_dispute FROM public.chop_pay_order_runtime
   WHERE source_module='repas' AND source_id=p_order_id;
  IF v_engine IS NULL THEN
    SELECT state, dispute_reason INTO v_engine, v_dispute FROM public.cash_order_runtime
     WHERE source_module='repas' AND source_id=p_order_id;
  END IF;

  SELECT COALESCE(jsonb_agg(t ORDER BY (t->>'at')), '[]'::jsonb) INTO v_timeline FROM (
    SELECT jsonb_build_object('source','order','at',v_o.created_at,
             'label','order_placed','actor','customer') AS t
    UNION ALL
    SELECT jsonb_build_object('source','custody','at',e.occurred_at,
             'label',e.boundary,'method',e.method,'actor','participant')
      FROM public.repas_custody_events e WHERE e.order_id = p_order_id
    UNION ALL
    SELECT jsonb_build_object('source','ops','at',ev.created_at,'label',ev.action,
             'actor','operator','actor_user_id',ev.actor_user_id,'actor_role',ev.actor_role,
             'reason_code',ev.reason_code,'note',ev.note,
             'finance_result',ev.finance_result)
      FROM public.repas_ops_events ev WHERE ev.food_order_id = p_order_id
  ) z;

  RETURN jsonb_build_object(
    'ok', true, 'actor_role', v_role,
    'order', jsonb_build_object(
      'order_id', v_o.id, 'state', v_o.state::text,
      'fulfillment', v_o.fulfillment::text, 'tender', v_o.payment_method::text,
      'order_total_gnf', v_o.order_total_gnf, 'delivery_fee_gnf', v_o.delivery_fee_gnf,
      'subtotal_gnf', v_o.subtotal_gnf,
      'created_at', v_o.created_at, 'updated_at', v_o.updated_at,
      'client_request_id', v_o.client_request_id,
      'customer_user_id', v_o.user_id,
      'restaurant_id', v_r.id, 'restaurant_name', v_r.name,
      'terminal', v_o.state::text IN ('completed','cancelled')),
    'destination', CASE WHEN v_o.fulfillment::text = 'pickup' THEN NULL
      ELSE jsonb_build_object(
        'label', v_o.delivery_address,
        'landmark', v_o.delivery_landmark,
        'instructions', v_o.delivery_instructions,
        'location_source', v_o.delivery_location_source,
        'location_quality', v_o.delivery_location_quality,
        'has_coordinates', (v_o.delivery_lat IS NOT NULL AND v_o.delivery_lng IS NOT NULL),
        'lat', v_o.delivery_lat, 'lng', v_o.delivery_lng,
        'distance_km', v_o.delivery_distance_km,
        'frozen', true, 'editable', false) END,
    'payment', jsonb_build_object(
      'engine_state', v_engine, 'dispute_reason', v_dispute,
      'settlement_state', v_o.settlement_state,
      'disputed', public._repas_custody_dispute_blocked(p_order_id)),
    'mission', CASE WHEN v_m.id IS NULL THEN NULL ELSE jsonb_build_object(
      'mission_id', v_m.id, 'state', v_m.state::text,
      'courier_id', v_m.courier_id, 'issue_reason', v_m.issue_reason) END,
    'custody', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'kind', c.kind, 'consumed', c.consumed_at IS NOT NULL,
        'locked', c.locked_at IS NOT NULL, 'attempts', c.attempts,
        'issued_at', c.created_at))
      FROM public.repas_custody_credentials c WHERE c.order_id = p_order_id), '[]'::jsonb),
    'case', CASE WHEN v_case.id IS NULL THEN NULL ELSE jsonb_build_object(
      'case_id', v_case.id, 'status', v_case.status, 'reason_code', v_case.reason_code,
      'severity', v_case.severity, 'note', v_case.note,
      'created_by', v_case.created_by, 'created_at', v_case.created_at,
      'resolved_by', v_case.resolved_by, 'resolved_at', v_case.resolved_at,
      'resolution_code', v_case.resolution_code) END,
    'timeline', v_timeline,
    'allowed_actions', to_jsonb(public._repas_ops_allowed_actions(p_order_id, v_uid, v_role)),
    'reassignment_available', false,
    'reassignment_reason', 'NO_CERTIFIED_REASSIGNMENT_PRIMITIVE');
END; $function$;

REVOKE ALL ON FUNCTION public.repas_ops_case_detail(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.repas_ops_case_detail(uuid) TO authenticated, service_role;
