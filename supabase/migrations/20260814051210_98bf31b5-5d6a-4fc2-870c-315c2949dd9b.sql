-- ============================================================
-- R5.D — frozen order economics
-- ============================================================
ALTER TABLE public.food_orders
  ADD COLUMN IF NOT EXISTS pricing_policy_id     uuid,
  ADD COLUMN IF NOT EXISTS promotion_id          uuid REFERENCES public.repas_pricing_promotions(id),
  ADD COLUMN IF NOT EXISTS base_delivery_fee_gnf bigint,
  ADD COLUMN IF NOT EXISTS delivery_fee_gnf      bigint,
  ADD COLUMN IF NOT EXISTS promo_discount_gnf    bigint,
  ADD COLUMN IF NOT EXISTS platform_fee_gnf      bigint,
  ADD COLUMN IF NOT EXISTS courier_payout_gnf    bigint,
  ADD COLUMN IF NOT EXISTS order_total_gnf       bigint,
  ADD COLUMN IF NOT EXISTS delivery_distance_km  numeric(6,3),
  ADD COLUMN IF NOT EXISTS pricing_snapshot      jsonb;

COMMENT ON COLUMN public.food_orders.delivery_fee_gnf IS
  'R5 frozen: what the CUSTOMER pays for delivery (after promotion).';
COMMENT ON COLUMN public.food_orders.courier_payout_gnf IS
  'R5 frozen: what the COURIER is paid. Never reduced by a customer promotion.';

-- ============================================================
-- Platform fee helper (single fee brain, policy fee_basis aware)
-- ============================================================
CREATE OR REPLACE FUNCTION public.repas_platform_fee_gnf(
  p_subtotal_gnf bigint, p_delivery_fee_gnf bigint, p_fee_basis text, p_bps integer)
RETURNS bigint
LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT CASE COALESCE(p_fee_basis,'none')
    WHEN 'none' THEN 0::bigint
    WHEN 'merchandise_subtotal' THEN (GREATEST(COALESCE(p_subtotal_gnf,0),0) * COALESCE(p_bps,0)) / 10000
    WHEN 'delivery_fee' THEN (GREATEST(COALESCE(p_delivery_fee_gnf,0),0) * COALESCE(p_bps,0)) / 10000
    WHEN 'order_total' THEN ((GREATEST(COALESCE(p_subtotal_gnf,0),0)
                              + GREATEST(COALESCE(p_delivery_fee_gnf,0),0)) * COALESCE(p_bps,0)) / 10000
    ELSE 0::bigint END;
$$;
REVOKE ALL ON FUNCTION public.repas_platform_fee_gnf(bigint, bigint, text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.repas_platform_fee_gnf(bigint, bigint, text, integer) TO authenticated, service_role;

-- ============================================================
-- R5.C — the only customer-facing pricing preview
-- ============================================================
DROP FUNCTION IF EXISTS public.repas_quote_preview(uuid, jsonb, text);

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
  v_reason text := NULL;
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
    v_max  := NULLIF(v_eff->>'delivery_max_distance_km','')::numeric;
    v_dist := public.repas_delivery_distance_km(p_restaurant_id, p_delivery_lat, p_delivery_lng);
    IF v_max IS NOT NULL THEN
      IF v_dist IS NULL THEN
        v_eligible := (p_delivery_lat IS NULL AND p_delivery_lng IS NULL);
        IF NOT v_eligible THEN v_reason := 'DISTANCE_UNKNOWN'; END IF;
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
REVOKE ALL ON FUNCTION public.repas_quote_preview(uuid, jsonb, text, double precision, double precision) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.repas_quote_preview(uuid, jsonb, text, double precision, double precision) TO authenticated, service_role;

-- ============================================================
-- R5.D — commitment recomputes and freezes
-- ============================================================
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
  v_payout bigint := 0; v_max numeric; v_dist numeric := NULL;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF p_client_request_id IS NULL THEN RAISE EXCEPTION 'CLIENT_REQUEST_ID_REQUIRED'; END IF;
  IF p_payment_method NOT IN ('cash','choppay') THEN
    RAISE EXCEPTION 'UNSUPPORTED_TENDER' USING DETAIL = COALESCE(p_payment_method,'null');
  END IF;
  IF p_fulfillment NOT IN ('pickup','delivery') THEN RAISE EXCEPTION 'INVALID_FULFILLMENT'; END IF;
  v_pickup := (p_fulfillment = 'pickup');

  -- R4.5-C preserved: cash pickup has no canonical fee-collection primitive.
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

  -- R5: server recomputes pricing from the effective policy. Client input is ignored.
  v_eff   := public.repas_pricing_effective(p_fulfillment, now());
  v_base  := COALESCE((v_eff->>'base_delivery_fee_gnf')::bigint, 0);
  v_del   := COALESCE((v_eff->>'customer_delivery_fee_gnf')::bigint, 0);
  v_disc  := COALESCE((v_eff->>'promo_discount_gnf')::bigint, 0);
  v_payout:= COALESCE((v_eff->>'courier_payout_gnf')::bigint, 0);

  -- R5.B: authoritative, configured delivery-zone enforcement (server-side only).
  IF NOT v_pickup THEN
    v_max := NULLIF(v_eff->>'delivery_max_distance_km','')::numeric;
    IF v_max IS NOT NULL THEN
      v_dist := public.repas_delivery_distance_km(p_restaurant_id, v_lat, v_lng);
      IF v_dist IS NULL THEN
        RAISE EXCEPTION 'DELIVERY_DISTANCE_UNVERIFIABLE'
          USING DETAIL = 'restaurant or destination coordinates missing';
      END IF;
      IF v_dist > v_max THEN
        RAISE EXCEPTION 'OUTSIDE_DELIVERY_ZONE'
          USING DETAIL = format('%s km > %s km', v_dist, v_max);
      END IF;
    ELSE
      v_dist := public.repas_delivery_distance_km(p_restaurant_id, v_lat, v_lng);
    END IF;

    -- Cash rail settles the courier out of the collected delivery cash; a
    -- customer price that differs from courier pay has no canonical cash
    -- primitive. Fail closed rather than mis-account.
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
    'authorization', v_auth);
END; $$;

-- ============================================================
-- R5.E — Chop Pay reads FROZEN Repas economics
-- ============================================================
CREATE OR REPLACE FUNCTION public._chop_pay_facts(p_source_module text, p_source_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_customer uuid; v_store uuid; v_owner uuid; v_sub bigint := 0;
  v_is_cp boolean := false; v_mixed boolean := false; v_pstate text;
  v_mission public.missions; v_del bigint := 0; v_tender text; v_ful text := 'delivery';
  v_frozen_del bigint; v_frozen_fee bigint; v_payout bigint;
BEGIN
  IF p_source_module = 'repas' THEN
    SELECT fo.user_id, r.merchant_store_id, COALESCE(r.owner_user_id, ms.owner_user_id),
           fo.subtotal_gnf, (fo.payment_method::text = 'choppay'),
           (fo.captured_intent_id IS NOT NULL),
           fo.state::text, fo.payment_method::text, fo.fulfillment::text,
           fo.delivery_fee_gnf, fo.platform_fee_gnf, fo.courier_payout_gnf
      INTO v_customer, v_store, v_owner, v_sub, v_is_cp, v_mixed, v_pstate, v_tender, v_ful,
           v_frozen_del, v_frozen_fee, v_payout
      FROM public.food_orders fo
      JOIN public.food_restaurants r ON r.id = fo.restaurant_id
      LEFT JOIN public.merchant_stores ms ON ms.id = r.merchant_store_id
     WHERE fo.id = p_source_id;
    SELECT * INTO v_mission FROM public.missions
     WHERE ref_food_order_id = p_source_id ORDER BY created_at DESC LIMIT 1;
  ELSIF p_source_module = 'marche' THEN
    SELECT mo.buyer_user_id, mo.merchant_store_id, mo.merchant_user_id,
           COALESCE(mo.counter_amount_gnf, mo.offer_amount_gnf),
           (mo.metadata->>'payment_method') = 'choppay',
           (mo.payment_intent_id IS NOT NULL),
           mo.status, mo.metadata->>'payment_method'
      INTO v_customer, v_store, v_owner, v_sub, v_is_cp, v_mixed, v_pstate, v_tender
      FROM public.marketplace_offers mo WHERE mo.id = p_source_id;
    v_ful := 'delivery';
    SELECT * INTO v_mission FROM public.missions
     WHERE ref_market_order_id = p_source_id ORDER BY created_at DESC LIMIT 1;
  ELSE
    RAISE EXCEPTION 'UNSUPPORTED_CHOP_PAY_MODULE';
  END IF;

  IF v_customer IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;

  -- Customer-facing delivery price: frozen Repas truth when present, else legacy
  -- (mission estimated earning) for marche / pre-R5 rows.
  v_del := GREATEST(COALESCE(v_frozen_del, v_mission.estimated_earning_gnf, 0), 0);

  RETURN jsonb_build_object(
    'source_module', p_source_module, 'source_id', p_source_id,
    'mission_type', p_source_module,
    'customer_user_id', v_customer,
    'merchant_store_id', v_store, 'merchant_user_id', v_owner,
    'merchandise_subtotal_gnf', GREATEST(COALESCE(v_sub,0),0),
    'delivery_fee_gnf', v_del,
    'frozen_platform_fee_gnf', v_frozen_fee,
    'courier_payout_gnf', GREATEST(COALESCE(v_payout, v_del), 0),
    'tender', v_tender,
    'fulfillment', v_ful,
    'is_pickup', (v_ful = 'pickup'),
    'is_chop_pay', COALESCE(v_is_cp,false),
    'mixed_tender', COALESCE(v_mixed,false),
    'product_state', v_pstate,
    'mission_id', v_mission.id,
    'mission_state', v_mission.state::text,
    'courier_id', v_mission.courier_id,
    'pickup_confirmed', v_mission.pickup_confirmed_at IS NOT NULL);
END; $$;

CREATE OR REPLACE FUNCTION public._chop_pay_economics(p_facts jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_req jsonb; v_snap jsonb; v_sub bigint; v_del bigint; v_fee bigint; v_col bigint;
BEGIN
  v_sub := (p_facts->>'merchandise_subtotal_gnf')::bigint;
  v_del := (p_facts->>'delivery_fee_gnf')::bigint;
  v_req := public.finance_mission_requirement_v2(p_facts->>'mission_type', 0, v_sub, v_del, 0, 'chop_pay');
  -- R5: Repas platform fee is frozen at commitment; never recomputed from live policy.
  v_fee := COALESCE((p_facts->>'frozen_platform_fee_gnf')::bigint,
                    (v_req->>'platform_fee_gnf')::bigint, 0);
  v_col := COALESCE((v_req->>'collateral_gnf')::bigint, 0);
  IF COALESCE((v_req->>'cash_funding_gnf')::bigint,0) <> 0 THEN
    RAISE EXCEPTION 'CHOP_PAY_MUST_NOT_FUND_CASH';
  END IF;
  IF COALESCE((v_req->>'commission_gnf')::bigint,0) <> 0 THEN
    RAISE EXCEPTION 'CHOP_PAY_NO_DELIVERY_COMMISSION';
  END IF;
  v_snap := public.finance_policy_snapshot(p_facts->>'mission_type', now(), 'chop_pay', 0, v_sub, v_del, 0, false);
  RETURN jsonb_build_object(
    'merchandise_subtotal_gnf', v_sub, 'delivery_fee_gnf', v_del,
    'platform_fee_gnf', v_fee, 'collateral_gnf', v_col,
    'courier_payout_gnf', COALESCE((p_facts->>'courier_payout_gnf')::bigint, v_del),
    'order_total_gnf', v_sub + v_del + v_fee,
    'requirement', v_req, 'policy_snapshot', v_snap);
END; $$;

-- Courier compensation is independent of the customer price: settle the gap
-- against the platform master wallet so the ledger stays zero-sum.
ALTER TABLE public.chop_pay_order_runtime
  ADD COLUMN IF NOT EXISTS courier_payout_gnf bigint;

CREATE OR REPLACE FUNCTION public._chop_pay_courier_adjust_internal(
  p_source_module text, p_source_id uuid, p_delta bigint, p_driver uuid, p_actor uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_key text; v_master public.wallets; v_dw public.wallets; v_abs bigint;
BEGIN
  IF COALESCE(p_delta,0) = 0 THEN RETURN jsonb_build_object('status','zero','delta_gnf',0); END IF;
  IF p_driver IS NULL THEN RAISE EXCEPTION 'NO_ASSIGNED_COURIER'; END IF;
  v_abs := abs(p_delta);
  v_key := format('cph-courier-adjust:%s:%s', p_source_module, p_source_id);
  IF EXISTS (SELECT 1 FROM public.ledger_journals WHERE journal_key = v_key) THEN
    RETURN jsonb_build_object('status','already_adjusted','delta_gnf',0);
  END IF;

  SELECT * INTO v_master FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;
  IF v_master.id IS NULL THEN RAISE EXCEPTION 'MASTER_WALLET_MISSING'; END IF;
  INSERT INTO public.wallets (owner_user_id, party_type) VALUES (p_driver, 'driver')
  ON CONFLICT (owner_user_id, party_type) DO NOTHING;
  SELECT * INTO v_dw FROM public.wallets
   WHERE owner_user_id = p_driver AND party_type = 'driver' FOR UPDATE;

  IF p_delta > 0 THEN   -- platform subsidises the courier
    UPDATE public.wallets SET balance_gnf = balance_gnf - v_abs, updated_at = now() WHERE id = v_master.id;
    UPDATE public.wallets SET balance_gnf = balance_gnf + v_abs, updated_at = now() WHERE id = v_dw.id;
  ELSE                  -- platform keeps the delivery margin
    UPDATE public.wallets SET balance_gnf = balance_gnf - v_abs, updated_at = now() WHERE id = v_dw.id;
    UPDATE public.wallets SET balance_gnf = balance_gnf + v_abs, updated_at = now() WHERE id = v_master.id;
  END IF;

  INSERT INTO public.wallet_transactions
    (reference, type, status, amount_gnf, from_wallet_id, to_wallet_id, related_user_id,
     related_entity, description, metadata, completed_at)
  VALUES (v_key, 'adjustment', 'completed', v_abs,
     CASE WHEN p_delta > 0 THEN v_master.id ELSE v_dw.id END,
     CASE WHEN p_delta > 0 THEN v_dw.id ELSE v_master.id END,
     p_driver, p_source_module || ':' || p_source_id::text,
     CASE WHEN p_delta > 0 THEN 'Subvention CHOPCHOP sur rémunération coursier'
          ELSE 'Marge CHOPCHOP sur livraison' END,
     jsonb_build_object('purpose','courier_payout_adjustment','delta_gnf',p_delta), now());

  PERFORM public._ledger_post(v_key, p_source_module, p_source_id, 'courier_payout_adjustment',
    CASE WHEN p_delta > 0 THEN
      jsonb_build_array(
        jsonb_build_object('account','R_DELIVERY_SUBSIDY','amount_gnf',v_abs,
                           'memo','subvention livraison CHOPCHOP'),
        jsonb_build_object('account','L_DRIVER_UNRESTRICTED','amount_gnf',-v_abs,
                           'party_type','driver','party_user_id',p_driver,
                           'memo','complément rémunération coursier'))
    ELSE
      jsonb_build_array(
        jsonb_build_object('account','L_DRIVER_UNRESTRICTED','amount_gnf',v_abs,
                           'party_type','driver','party_user_id',p_driver,
                           'memo','marge livraison retenue'),
        jsonb_build_object('account','R_DELIVERY_MARGIN','amount_gnf',-v_abs,
                           'memo','marge livraison CHOPCHOP'))
    END,
    p_actor);

  RETURN jsonb_build_object('status','adjusted','delta_gnf',p_delta);
END; $$;
REVOKE ALL ON FUNCTION public._chop_pay_courier_adjust_internal(text, uuid, bigint, uuid, uuid) FROM PUBLIC, anon, authenticated;

INSERT INTO public.ledger_accounts(code, name, kind)
SELECT * FROM (VALUES
  ('R_DELIVERY_SUBSIDY','Subvention livraison CHOPCHOP','revenue'),
  ('R_DELIVERY_MARGIN','Marge livraison CHOPCHOP','revenue')) v(code,name,kind)
WHERE NOT EXISTS (SELECT 1 FROM public.ledger_accounts la WHERE la.code = v.code);