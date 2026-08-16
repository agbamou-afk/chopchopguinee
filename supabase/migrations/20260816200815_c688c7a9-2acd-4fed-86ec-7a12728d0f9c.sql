CREATE OR REPLACE FUNCTION public.marche_order_commit(p_payload jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
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
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;

  IF p_payload ? 'merchandise_subtotal_gnf' OR p_payload ? 'total_gnf' OR p_payload ? 'subtotal_gnf' THEN
    RAISE EXCEPTION 'CLIENT_PRICE_NOT_ALLOWED';
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

  v_fp := md5(v_norm::text || '|' || COALESCE(v_addr,'') || '|' || COALESCE(v_lat::text,'') || '|' || COALESCE(v_lng::text,''));

  SELECT * INTO v_existing FROM public.marche_orders
   WHERE buyer_user_id = caller AND client_request_id = v_req;
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.request_fingerprint <> v_fp THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT'; END IF;
    RETURN public.marche_order_json(v_existing);
  END IF;

  -- deterministic row locking (oversell protection)
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
      'qty', v_qty, 'unit', v_unit, 'total', v_unit * v_qty, 'offer_id', v_offer));

    v_subtotal := v_subtotal + (v_unit * v_qty);
    v_items_n := v_items_n + v_qty;
    v_lines := v_lines + 1;
  END LOOP;

  INSERT INTO public.marche_orders(id, buyer_user_id, merchant_store_id, merchant_user_id,
    status, merchandise_subtotal_gnf, item_count, line_count, source_offer_id,
    client_request_id, request_fingerprint, delivery_address, dropoff_lat, dropoff_lng)
  VALUES (v_order_id, caller, v_store, v_seller, 'committed', v_subtotal, v_items_n, v_lines,
    CASE WHEN v_offer_count = 1 THEN v_single_offer ELSE NULL END,
    v_req, v_fp, v_addr, v_lat, v_lng)
  RETURNING * INTO v_existing;

  INSERT INTO public.marche_order_items(order_id, listing_id, store_id_snapshot, title_snapshot,
    qty, unit_price_gnf, line_total_gnf, source_offer_id)
  SELECT v_order_id, (x->>'listing_id')::uuid, (x->>'store_id')::uuid, x->>'title',
         (x->>'qty')::int, (x->>'unit')::bigint, (x->>'total')::bigint,
         NULLIF(x->>'offer_id','')::uuid
    FROM jsonb_array_elements(v_lines_json) x;

  RETURN public.marche_order_json(v_existing);
END $function$;