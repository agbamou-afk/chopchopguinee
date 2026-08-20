-- =====================================================================
-- NODE 4 · MARCHÉ R13 — CONAKRY HARDENING (server layer)
-- Additive only. No change to frozen R1–R12 economics or lifecycle law.
-- =====================================================================

-- ---------- 1. Landmark-oriented destination (H) ----------
ALTER TABLE public.marche_orders
  ADD COLUMN IF NOT EXISTS destination_label        text,
  ADD COLUMN IF NOT EXISTS destination_landmark     text,
  ADD COLUMN IF NOT EXISTS destination_instructions text,
  ADD COLUMN IF NOT EXISTS destination_quality      text;

-- Server-derived honesty verdict. Landmark prose is never geospatial truth.
CREATE OR REPLACE FUNCTION public._marche_destination_quality(
  p_lat double precision, p_lng double precision, p_source text,
  p_landmark text, p_instructions text, p_label text)
RETURNS text
LANGUAGE sql IMMUTABLE
SET search_path TO 'public'
AS $$
  SELECT CASE
    WHEN p_lat IS NOT NULL AND p_lng IS NOT NULL THEN
      CASE lower(COALESCE(p_source,''))
        WHEN 'gps' THEN 'gps_verified'
        WHEN 'manual_pin' THEN 'manually_placed'
        ELSE 'approximate'
      END
    WHEN COALESCE(btrim(COALESCE(p_landmark,'')),'') <> ''
      OR COALESCE(btrim(COALESCE(p_instructions,'')),'') <> ''
      OR COALESCE(btrim(COALESCE(p_label,'')),'') <> ''
      THEN 'landmark_assisted'
    ELSE 'unverifiable'
  END;
$$;
REVOKE ALL ON FUNCTION public._marche_destination_quality(double precision,double precision,text,text,text,text) FROM PUBLIC, anon, authenticated;

-- ---------- 2. Sanitized order projection carries the destination ----------
CREATE OR REPLACE FUNCTION public.marche_order_json(o marche_orders)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT jsonb_build_object(
    'id', o.id,
    'buyer_user_id', o.buyer_user_id,
    'merchant_store_id', o.merchant_store_id,
    'merchant_user_id', o.merchant_user_id,
    'status', o.status,
    'merchandise_subtotal_gnf', o.merchandise_subtotal_gnf,
    'item_count', o.item_count,
    'line_count', o.line_count,
    'source_offer_id', o.source_offer_id,
    'client_request_id', o.client_request_id,
    'delivery_address', o.delivery_address,
    'dropoff_lat', o.dropoff_lat,
    'dropoff_lng', o.dropoff_lng,
    'destination_label', o.destination_label,
    'destination_landmark', o.destination_landmark,
    'destination_instructions', o.destination_instructions,
    'destination_quality', o.destination_quality,
    'delivery_charge_gnf', o.delivery_charge_gnf,
    'delivery_pricing_state', o.delivery_pricing_state,
    'reservation_expires_at', o.reservation_expires_at,
    'cancelled_at', o.cancelled_at,
    'cancel_reason', o.cancel_reason,
    'created_at', o.created_at,
    'updated_at', o.updated_at,
    'fulfillment_state', o.fulfillment_state,
    'fulfillment_updated_at', o.fulfillment_updated_at,
    'accepted_at', o.accepted_at,
    'ready_at', o.ready_at,
    'delivered_at', o.delivered_at,
    'rejected_at', o.rejected_at,
    'courier_assigned', EXISTS (SELECT 1 FROM public.missions m
                                 WHERE m.id = o.mission_id AND m.courier_id IS NOT NULL),
    'mission_state', (SELECT m.state::text FROM public.missions m WHERE m.id = o.mission_id),
    'items', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', i.id, 'listing_id', i.listing_id, 'store_id', i.store_id_snapshot,
        'title', i.title_snapshot, 'qty', i.qty,
        'unit_price_gnf', i.unit_price_gnf, 'line_total_gnf', i.line_total_gnf,
        'source_offer_id', i.source_offer_id) ORDER BY i.created_at, i.id)
      FROM public.marche_order_items i WHERE i.order_id = o.id), '[]'::jsonb)
  )
  || CASE WHEN auth.uid() IS NOT NULL
            AND (o.merchant_user_id = auth.uid() OR public.is_any_admin(auth.uid()))
          THEN jsonb_build_object(
                 'mission_id', o.mission_id,
                 'reservation_settlement_kind', o.reservation_settlement_kind,
                 'merchant_fee_gnf', o.merchant_fee_gnf,
                 'merchant_payable_gnf', o.merchant_payable_gnf,
                 'merchant_platform_fee_bps', o.merchant_platform_fee_bps,
                 'fee_policy_id', o.fee_policy_id,
                 'fee_policy_effective_from', o.fee_policy_effective_from,
                 'economics_resolved_at', o.economics_resolved_at,
                 'economics_snapshot', o.economics_snapshot)
          ELSE '{}'::jsonb END;
$function$;

-- ---------- 3. Commitment accepts landmark intent, still server-authoritative (E,H) ----------
CREATE OR REPLACE FUNCTION public.marche_order_commit(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  caller uuid := auth.uid();
  v_req text;
  v_items jsonb;
  v_it jsonb;
  v_ids uuid[] := '{}';
  v_fp text;
  v_norm jsonb := '[]'::jsonb;
  v_lines_json jsonb := '[]'::jsonb;
  v_existing public.marche_orders;
  v_order_id uuid;
  l public.marketplace_listings;
  t public.v_marche_listing_truth%ROWTYPE;
  o public.marketplace_offers;
  v_store uuid; v_seller uuid;
  v_qty int; v_unit bigint; v_avail int;
  v_subtotal bigint := 0; v_items_n int := 0; v_lines int := 0;
  v_offer uuid; v_single_offer uuid; v_offer_count int := 0;
  v_addr text; v_lat double precision; v_lng double precision;
  v_label text; v_landmark text; v_instr text; v_src text; v_quality text;
  v_dest_extra text;
  pol public.finance_policies;
  v_now timestamptz := now();
  v_bps int; v_fee bigint; v_payable bigint; v_econ jsonb;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;

  IF p_payload ? 'merchandise_subtotal_gnf' OR p_payload ? 'total_gnf' OR p_payload ? 'subtotal_gnf' THEN
    RAISE EXCEPTION 'CLIENT_PRICE_NOT_ALLOWED';
  END IF;
  IF p_payload ? 'merchant_fee_gnf' OR p_payload ? 'merchant_payable_gnf'
     OR p_payload ? 'merchant_platform_fee_bps' OR p_payload ? 'fee_policy_id'
     OR p_payload ? 'delivery_charge_gnf' OR p_payload ? 'economics_snapshot' THEN
    RAISE EXCEPTION 'CLIENT_ECONOMICS_NOT_ALLOWED';
  END IF;
  -- R13: location quality is a server verdict, never a client assertion.
  IF p_payload ? 'destination_quality' OR p_payload ? 'location_quality' THEN
    RAISE EXCEPTION 'CLIENT_LOCATION_QUALITY_NOT_ALLOWED';
  END IF;

  v_req := NULLIF(btrim(COALESCE(p_payload->>'client_request_id','')), '');
  IF v_req IS NULL OR length(v_req) < 8 OR length(v_req) > 128 THEN RAISE EXCEPTION 'CLIENT_REQUEST_ID_REQUIRED'; END IF;

  v_items := p_payload->'items';
  IF v_items IS NULL OR jsonb_typeof(v_items) <> 'array' OR jsonb_array_length(v_items) = 0 THEN
    RAISE EXCEPTION 'EMPTY_BASKET';
  END IF;
  IF jsonb_array_length(v_items) > 20 THEN RAISE EXCEPTION 'BASKET_TOO_LARGE'; END IF;

  v_addr := NULLIF(btrim(COALESCE(p_payload->>'delivery_address','')), '');
  v_lat := NULLIF(p_payload->>'dropoff_lat','')::double precision;
  v_lng := NULLIF(p_payload->>'dropoff_lng','')::double precision;
  v_label    := NULLIF(btrim(COALESCE(p_payload->>'destination_label','')), '');
  v_landmark := NULLIF(btrim(COALESCE(p_payload->>'destination_landmark','')), '');
  v_instr    := NULLIF(btrim(COALESCE(p_payload->>'destination_instructions','')), '');
  v_src      := lower(NULLIF(btrim(COALESCE(p_payload->>'location_source','')), ''));
  IF length(COALESCE(v_label,'')) > 160 OR length(COALESCE(v_landmark,'')) > 160
     OR length(COALESCE(v_instr,'')) > 400 THEN
    RAISE EXCEPTION 'DESTINATION_TEXT_TOO_LONG';
  END IF;
  IF v_src IS NOT NULL AND v_src NOT IN ('gps','manual_pin','typed','unspecified') THEN
    RAISE EXCEPTION 'INVALID_LOCATION_SOURCE';
  END IF;
  v_quality := public._marche_destination_quality(v_lat, v_lng, v_src, v_landmark, v_instr, v_label);

  FOR v_it IN SELECT * FROM jsonb_array_elements(v_items) LOOP
    IF v_it ? 'unit_price_gnf' OR v_it ? 'line_total_gnf' OR v_it ? 'price_gnf' THEN
      RAISE EXCEPTION 'CLIENT_PRICE_NOT_ALLOWED';
    END IF;
    IF NULLIF(v_it->>'listing_id','') IS NULL THEN RAISE EXCEPTION 'LISTING_REQUIRED'; END IF;
    v_qty := COALESCE((v_it->>'qty')::int, 0);
    IF v_qty <= 0 OR v_qty > 100 THEN RAISE EXCEPTION 'INVALID_QUANTITY'; END IF;
    IF (v_it->>'listing_id')::uuid = ANY(v_ids) THEN RAISE EXCEPTION 'DUPLICATE_LINE'; END IF;
    v_ids := v_ids || (v_it->>'listing_id')::uuid;
  END LOOP;

  SELECT jsonb_agg(jsonb_build_object(
           'listing_id', x->>'listing_id', 'qty', (x->>'qty')::int,
           'offer_id', COALESCE(x->>'offer_id','')) ORDER BY x->>'listing_id')
    INTO v_norm FROM jsonb_array_elements(v_items) x;

  -- Backward-compatible fingerprint: the landmark segment only participates
  -- when the customer actually supplied landmark intent, so pre-R13 durable
  -- keys still replay to the same fingerprint.
  v_dest_extra := CASE
    WHEN COALESCE(v_label,'') = '' AND COALESCE(v_landmark,'') = '' AND COALESCE(v_instr,'') = ''
      THEN ''
    ELSE '|' || COALESCE(v_label,'') || '|' || COALESCE(v_landmark,'') || '|' || COALESCE(v_instr,'')
  END;
  v_fp := md5(v_norm::text || '|' || COALESCE(v_addr,'') || '|' || COALESCE(v_lat::text,'') || '|' || COALESCE(v_lng::text,'') || v_dest_extra);

  SELECT * INTO v_existing FROM public.marche_orders
   WHERE buyer_user_id = caller AND client_request_id = v_req;
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.request_fingerprint <> v_fp THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT'; END IF;
    RETURN public.marche_order_json(v_existing);
  END IF;

  PERFORM 1 FROM public.marketplace_listings WHERE id = ANY(v_ids) ORDER BY id FOR UPDATE;

  v_order_id := gen_random_uuid();

  FOR v_it IN SELECT * FROM jsonb_array_elements(v_norm) LOOP
    SELECT * INTO l FROM public.marketplace_listings WHERE id = (v_it->>'listing_id')::uuid;
    IF l.id IS NULL THEN RAISE EXCEPTION 'LISTING_NOT_FOUND'; END IF;
    SELECT * INTO t FROM public.v_marche_listing_truth WHERE listing_id = l.id;
    IF NOT t.is_orderable THEN RAISE EXCEPTION '%', t.refusal_reason; END IF;
    IF l.seller_id = caller THEN RAISE EXCEPTION 'SELF_PURCHASE_NOT_ALLOWED'; END IF;

    IF v_store IS NULL THEN v_store := l.store_id; v_seller := l.seller_id;
    ELSIF v_store <> l.store_id THEN RAISE EXCEPTION 'SINGLE_STORE_ONLY';
    END IF;

    v_qty := (v_it->>'qty')::int;
    v_offer := NULLIF(v_it->>'offer_id','')::uuid;

    IF l.pricing_mode = 'fixed' THEN
      IF v_offer IS NOT NULL THEN RAISE EXCEPTION 'OFFER_NOT_APPLICABLE'; END IF;
      v_unit := l.price_gnf;
      IF COALESCE(v_unit,0) <= 0 THEN RAISE EXCEPTION 'INVALID_PRICE'; END IF;
    ELSIF l.pricing_mode = 'negotiable' THEN
      IF v_offer IS NULL THEN RAISE EXCEPTION 'OFFER_REQUIRED'; END IF;
      SELECT * INTO o FROM public.marketplace_offers WHERE id = v_offer;
      IF o.id IS NULL THEN RAISE EXCEPTION 'OFFER_NOT_FOUND'; END IF;
      IF o.buyer_user_id <> caller OR o.listing_id <> l.id OR o.merchant_store_id IS DISTINCT FROM l.store_id THEN
        RAISE EXCEPTION 'OFFER_NOT_FOR_THIS_BUYER';
      END IF;
      IF o.status <> 'accepted' OR o.agreed_amount_gnf IS NULL OR public.marche_offer_is_expired(o) THEN
        RAISE EXCEPTION 'OFFER_NOT_AGREED';
      END IF;
      v_unit := o.agreed_amount_gnf;
      v_offer_count := v_offer_count + 1;
      v_single_offer := o.id;
    ELSIF l.pricing_mode = 'quote' THEN
      RAISE EXCEPTION 'QUOTE_NOT_ORDERABLE';
    ELSE
      RAISE EXCEPTION 'UNSUPPORTED_PRICING_MODE';
    END IF;

    IF l.quantity_in_stock IS NOT NULL THEN
      v_avail := l.quantity_in_stock - COALESCE(l.quantity_reserved,0);
      IF v_avail <= 0 THEN RAISE EXCEPTION 'OUT_OF_STOCK'; END IF;
      IF v_qty > v_avail THEN RAISE EXCEPTION 'INSUFFICIENT_STOCK'; END IF;
      PERFORM set_config('marche.rpc','1', true);
      UPDATE public.marketplace_listings
         SET quantity_reserved = COALESCE(quantity_reserved,0) + v_qty
       WHERE id = l.id;
      PERFORM set_config('marche.rpc','', true);
    END IF;

    v_lines_json := v_lines_json || jsonb_build_array(jsonb_build_object(
      'listing_id', l.id, 'store_id', l.store_id, 'title', l.title,
      'qty', v_qty, 'unit', v_unit, 'total', v_unit * v_qty, 'offer_id', v_offer,
      'category', NULLIF(btrim(COALESCE(l.category,'')),'')));

    v_subtotal := v_subtotal + (v_unit * v_qty);
    v_items_n := v_items_n + v_qty;
    v_lines := v_lines + 1;
  END LOOP;

  SELECT * INTO pol FROM public.finance_policy_at('marche', v_now);
  IF pol.id IS NULL THEN RAISE EXCEPTION 'NO_ACTIVE_POLICY'; END IF;
  v_bps := pol.merchant_platform_fee_bps;
  IF v_bps IS NULL THEN RAISE EXCEPTION 'MERCHANT_FEE_POLICY_MISSING'; END IF;
  IF v_bps < 0 OR v_bps > 10000 THEN RAISE EXCEPTION 'INVALID_MERCHANT_PLATFORM_FEE_BPS'; END IF;

  v_fee := public.marche_merchant_fee_gnf(v_subtotal, v_bps);
  v_payable := v_subtotal - v_fee;
  IF v_fee < 0 OR v_fee > v_subtotal OR v_payable < 0 THEN RAISE EXCEPTION 'ECONOMICS_INVARIANT_VIOLATION'; END IF;

  v_econ := jsonb_build_object(
    'schema', 'chopchop.marche.order_economics',
    'version', 1,
    'resolved_at', v_now,
    'policy_id', pol.id,
    'policy_mission_type', pol.mission_type,
    'policy_effective_from', pol.effective_from,
    'merchant_platform_fee_bps', v_bps,
    'merchant_platform_fee_basis', 'merchandise_subtotal',
    'rounding', 'floor_gnf_clamped_to_subtotal',
    'merchandise_subtotal_gnf', v_subtotal,
    'merchant_platform_fee_gnf', v_fee,
    'merchant_payable_gnf', v_payable,
    'delivery_pricing_state', 'unresolved',
    'customer_delivery_charge_gnf', NULL,
    'policy_snapshot', public.finance_policy_snapshot('marche', v_now, 'chop_pay', 0, v_subtotal));

  INSERT INTO public.marche_orders(id, buyer_user_id, merchant_store_id, merchant_user_id,
    status, merchandise_subtotal_gnf, item_count, line_count, source_offer_id,
    client_request_id, request_fingerprint, delivery_address, dropoff_lat, dropoff_lng,
    destination_label, destination_landmark, destination_instructions, destination_quality,
    merchant_fee_gnf, merchant_payable_gnf, merchant_platform_fee_bps,
    fee_policy_id, fee_policy_effective_from, economics_snapshot, economics_resolved_at,
    delivery_charge_gnf, delivery_pricing_state)
  VALUES (v_order_id, caller, v_store, v_seller, 'committed', v_subtotal, v_items_n, v_lines,
    CASE WHEN v_offer_count = 1 THEN v_single_offer ELSE NULL END,
    v_req, v_fp, v_addr, v_lat, v_lng,
    v_label, v_landmark, v_instr, v_quality,
    v_fee, v_payable, v_bps, pol.id, pol.effective_from, v_econ, v_now,
    NULL, 'unresolved')
  RETURNING * INTO v_existing;

  INSERT INTO public.marche_order_items(order_id, listing_id, store_id_snapshot, title_snapshot,
    qty, unit_price_gnf, line_total_gnf, source_offer_id, category_snapshot)
  SELECT v_order_id, (x->>'listing_id')::uuid, (x->>'store_id')::uuid, x->>'title',
         (x->>'qty')::int, (x->>'unit')::bigint, (x->>'total')::bigint,
         NULLIF(x->>'offer_id','')::uuid, NULLIF(x->>'category','')
    FROM jsonb_array_elements(v_lines_json) x;

  PERFORM public.marche_fulfillment_profile_create(v_order_id);
  PERFORM public.marche_fulfillment_event_append(
    v_order_id, 'ORDER_COMMITTED', v_existing.created_at,
    'marche_order_commit', v_order_id::text, 'commit', 'system');

  RETURN public.marche_order_json(v_existing);
END $function$;

-- ---------- 4. Pre-commitment revalidation (C,D,E,L) — READ ONLY ----------
CREATE OR REPLACE FUNCTION public.marche_basket_revalidate(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  caller uuid := auth.uid();
  v_items jsonb; v_it jsonb;
  l public.marketplace_listings;
  t public.v_marche_listing_truth%ROWTYPE;
  v_lines jsonb := '[]'::jsonb;
  v_store uuid; v_multi boolean := false;
  v_qty int; v_unit bigint; v_avail int;
  v_cached bigint; v_status text; v_reason text;
  v_subtotal bigint := 0; v_items_n int := 0; v_lines_n int := 0;
  v_ok boolean := true; v_material boolean := false; v_block text;
  v_ids uuid[] := '{}';
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF p_payload ? 'merchandise_subtotal_gnf' OR p_payload ? 'total_gnf' OR p_payload ? 'subtotal_gnf' THEN
    RAISE EXCEPTION 'CLIENT_PRICE_NOT_ALLOWED';
  END IF;

  v_items := p_payload->'items';
  IF v_items IS NULL OR jsonb_typeof(v_items) <> 'array' OR jsonb_array_length(v_items) = 0 THEN
    RAISE EXCEPTION 'EMPTY_BASKET';
  END IF;
  IF jsonb_array_length(v_items) > 20 THEN RAISE EXCEPTION 'BASKET_TOO_LARGE'; END IF;

  FOR v_it IN SELECT * FROM jsonb_array_elements(v_items) LOOP
    IF NULLIF(v_it->>'listing_id','') IS NULL THEN RAISE EXCEPTION 'LISTING_REQUIRED'; END IF;
    IF (v_it->>'listing_id')::uuid = ANY(v_ids) THEN RAISE EXCEPTION 'DUPLICATE_LINE'; END IF;
    v_ids := v_ids || (v_it->>'listing_id')::uuid;

    v_qty := GREATEST(COALESCE((v_it->>'qty')::int, 0), 0);
    -- A cached price is accepted ONLY to report drift. It never becomes truth.
    v_cached := NULLIF(v_it->>'cached_unit_price_gnf','')::bigint;
    v_status := 'ok'; v_reason := NULL; v_unit := NULL; v_avail := NULL;

    SELECT * INTO l FROM public.marketplace_listings WHERE id = (v_it->>'listing_id')::uuid;
    IF l.id IS NULL THEN
      v_status := 'not_found'; v_reason := 'LISTING_NOT_FOUND';
    ELSE
      SELECT * INTO t FROM public.v_marche_listing_truth WHERE listing_id = l.id;
      IF NOT COALESCE(t.is_orderable,false) THEN
        v_status := 'unavailable'; v_reason := COALESCE(t.refusal_reason,'NOT_ORDERABLE');
      ELSIF l.seller_id = caller THEN
        v_status := 'unavailable'; v_reason := 'SELF_PURCHASE_NOT_ALLOWED';
      ELSIF v_qty <= 0 OR v_qty > 100 THEN
        v_status := 'quantity_unavailable'; v_reason := 'INVALID_QUANTITY';
      ELSE
        IF v_store IS NULL THEN v_store := l.store_id;
        ELSIF v_store IS DISTINCT FROM l.store_id THEN v_multi := true;
        END IF;

        IF l.pricing_mode = 'quote' THEN
          v_status := 'unavailable'; v_reason := 'QUOTE_NOT_ORDERABLE';
        ELSIF l.pricing_mode = 'negotiable' THEN
          v_status := 'review_required'; v_reason := 'OFFER_REQUIRED';
          v_unit := NULL;
        ELSE
          v_unit := l.price_gnf;
          IF COALESCE(v_unit,0) <= 0 THEN
            v_status := 'unavailable'; v_reason := 'INVALID_PRICE'; v_unit := NULL;
          END IF;
        END IF;

        IF v_status IN ('ok') AND l.quantity_in_stock IS NOT NULL THEN
          v_avail := GREATEST(l.quantity_in_stock - COALESCE(l.quantity_reserved,0), 0);
          IF v_avail <= 0 THEN
            v_status := 'unavailable'; v_reason := 'OUT_OF_STOCK';
          ELSIF v_qty > v_avail THEN
            v_status := 'quantity_unavailable'; v_reason := 'INSUFFICIENT_STOCK';
          END IF;
        END IF;

        IF v_status = 'ok' AND v_cached IS NOT NULL AND v_cached <> v_unit THEN
          v_status := 'price_changed'; v_reason := 'PRICE_CHANGED';
        END IF;
      END IF;
    END IF;

    IF v_status = 'ok' THEN
      v_subtotal := v_subtotal + (v_unit * v_qty);
      v_items_n := v_items_n + v_qty;
      v_lines_n := v_lines_n + 1;
    ELSIF v_status = 'price_changed' THEN
      v_subtotal := v_subtotal + (v_unit * v_qty);
      v_items_n := v_items_n + v_qty;
      v_lines_n := v_lines_n + 1;
      v_material := true;
    ELSE
      v_ok := false; v_material := true;
      IF v_block IS NULL THEN v_block := v_reason; END IF;
    END IF;

    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'listing_id', COALESCE(l.id, (v_it->>'listing_id')::uuid),
      'title', l.title,
      'store_id', l.store_id,
      'status', v_status,
      'reason', v_reason,
      'requested_qty', v_qty,
      'available_qty', v_avail,
      'unit_price_gnf', v_unit,
      'cached_unit_price_gnf', v_cached,
      'price_changed', (v_cached IS NOT NULL AND v_unit IS NOT NULL AND v_cached <> v_unit)));
  END LOOP;

  IF v_multi THEN v_ok := false; v_material := true; v_block := COALESCE(v_block,'SINGLE_STORE_ONLY'); END IF;

  RETURN jsonb_build_object(
    'schema','chopchop.marche.basket_revalidation',
    'version', 1,
    'revalidated_at', now(),
    'ok', v_ok,
    'material_change', v_material,
    'blocking_reason', v_block,
    'store_id', v_store,
    -- Server-computed presentation total. Only marche_order_commit freezes money.
    'merchandise_subtotal_gnf', CASE WHEN v_ok THEN v_subtotal ELSE NULL END,
    'item_count', v_items_n,
    'line_count', v_lines_n,
    'lines', v_lines);
END $function$;
REVOKE ALL ON FUNCTION public.marche_basket_revalidate(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_basket_revalidate(jsonb) TO authenticated;

-- ---------- 5. Lost-response recovery (F) ----------
CREATE OR REPLACE FUNCTION public.marche_order_recover(p_client_request_id text)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  caller uuid := auth.uid();
  v_req text;
  o public.marche_orders;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  v_req := NULLIF(btrim(COALESCE(p_client_request_id,'')), '');
  IF v_req IS NULL OR length(v_req) < 8 OR length(v_req) > 128 THEN
    RAISE EXCEPTION 'CLIENT_REQUEST_ID_REQUIRED';
  END IF;

  SELECT * INTO o FROM public.marche_orders
   WHERE buyer_user_id = caller AND client_request_id = v_req;

  IF o.id IS NULL THEN
    RETURN jsonb_build_object('schema','chopchop.marche.order_recovery','version',1,
      'found', false, 'client_request_id', v_req, 'order', NULL);
  END IF;

  RETURN jsonb_build_object('schema','chopchop.marche.order_recovery','version',1,
    'found', true, 'client_request_id', v_req, 'order', public.marche_order_json(o));
END $function$;
REVOKE ALL ON FUNCTION public.marche_order_recover(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_order_recover(text) TO authenticated;
