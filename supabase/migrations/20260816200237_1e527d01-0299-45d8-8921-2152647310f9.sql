-- ============================================================
-- NODE 4 — MARCHE R3: order commitment / basket / price / stock truth
-- ============================================================

-- ---------- A. reserved stock on listings ----------
ALTER TABLE public.marketplace_listings
  ADD COLUMN IF NOT EXISTS quantity_reserved integer NOT NULL DEFAULT 0;

ALTER TABLE public.marketplace_listings DROP CONSTRAINT IF EXISTS marketplace_listings_qty_reserved_nonneg;
ALTER TABLE public.marketplace_listings ADD CONSTRAINT marketplace_listings_qty_reserved_nonneg
  CHECK (quantity_reserved >= 0);

ALTER TABLE public.marketplace_listings DROP CONSTRAINT IF EXISTS marketplace_listings_qty_reserved_within_stock;
ALTER TABLE public.marketplace_listings ADD CONSTRAINT marketplace_listings_qty_reserved_within_stock
  CHECK (quantity_in_stock IS NULL OR quantity_reserved <= quantity_in_stock);

-- ---------- B. canonical truth accounts for reservations ----------
CREATE OR REPLACE VIEW public.v_marche_listing_truth AS
SELECT listing_id,
    seller_id,
    store_id,
    kind,
    status,
    visibility,
    availability,
    quantity_in_stock,
    photo_count,
    price_gnf,
    pricing_mode,
    store_ok,
    is_demo,
    seller_banned,
    refusal_reason,
    refusal_reason IS NULL AS is_orderable,
    quantity_reserved,
    quantity_available
   FROM ( SELECT l.id AS listing_id,
            l.seller_id,
            l.store_id,
            l.kind,
            l.status,
            l.visibility,
            l.availability,
            l.quantity_in_stock,
            l.photo_count,
            l.price_gnf,
            l.pricing_mode,
            s.id IS NOT NULL AND s.status = 'active'::text AND s.onboarding_status = 'approved'::text AS store_ok,
            marche_is_demo_seller(l.seller_id) AS is_demo,
            marche_seller_banned(l.seller_id) AS seller_banned,
            l.quantity_reserved,
            CASE WHEN l.quantity_in_stock IS NULL THEN NULL::integer
                 ELSE l.quantity_in_stock - COALESCE(l.quantity_reserved,0) END AS quantity_available,
                CASE
                    WHEN l.store_id IS NULL OR l.kind <> 'merchant'::listing_kind THEN 'MERCHANT_STORE_REQUIRED'::text
                    WHEN l.status = 'removed'::listing_status THEN 'LISTING_REMOVED'::text
                    WHEN l.status = 'sold'::listing_status OR l.availability = 'sold'::listing_availability THEN 'LISTING_SOLD'::text
                    WHEN l.status = 'paused'::listing_status THEN 'LISTING_PAUSED'::text
                    WHEN l.visibility <> 'public'::text THEN 'LISTING_PRIVATE'::text
                    WHEN marche_seller_banned(l.seller_id) THEN 'SELLER_NOT_ELIGIBLE'::text
                    WHEN NOT (s.id IS NOT NULL AND s.status = 'active'::text AND s.onboarding_status = 'approved'::text) THEN 'STORE_NOT_APPROVED'::text
                    WHEN marche_is_demo_seller(l.seller_id) THEN 'DEMO_SUPPLY'::text
                    WHEN l.quantity_in_stock IS NOT NULL AND (l.quantity_in_stock - COALESCE(l.quantity_reserved,0)) <= 0 THEN 'OUT_OF_STOCK'::text
                    WHEN l.pricing_mode = 'fixed'::text AND l.kind = 'merchant'::listing_kind AND COALESCE(l.price_gnf, 0::bigint) <= 0 THEN 'INVALID_PRICE'::text
                    ELSE NULL::text
                END AS refusal_reason
           FROM marketplace_listings l
             LEFT JOIN merchant_stores s ON s.id = l.store_id) t;

CREATE OR REPLACE FUNCTION public.marche_listing_truth(p_listing_id uuid)
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT jsonb_build_object(
    'listing_id', v.listing_id,
    'is_orderable', v.is_orderable,
    'refusal_reason', v.refusal_reason,
    'is_demo', v.is_demo,
    'store_ok', v.store_ok,
    'has_photo', COALESCE(v.photo_count,0) > 0,
    'quantity_in_stock', v.quantity_in_stock,
    'quantity_reserved', v.quantity_reserved,
    'quantity_available', v.quantity_available
  )
  FROM public.v_marche_listing_truth v
  WHERE v.listing_id = p_listing_id;
$function$;

-- ---------- C. order tables ----------
CREATE TABLE IF NOT EXISTS public.marche_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  buyer_user_id uuid NOT NULL,
  merchant_store_id uuid NOT NULL REFERENCES public.merchant_stores(id),
  merchant_user_id uuid NOT NULL,
  status text NOT NULL DEFAULT 'committed',
  merchandise_subtotal_gnf bigint NOT NULL,
  item_count integer NOT NULL,
  line_count integer NOT NULL,
  source_offer_id uuid NULL REFERENCES public.marketplace_offers(id),
  client_request_id text NOT NULL,
  request_fingerprint text NOT NULL,
  delivery_address text NULL,
  dropoff_lat double precision NULL,
  dropoff_lng double precision NULL,
  merchant_fee_gnf bigint NULL,
  delivery_charge_gnf bigint NULL,
  fee_policy_id uuid NULL,
  reservation_expires_at timestamptz NULL,
  cancelled_at timestamptz NULL,
  cancel_reason text NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT marche_orders_status_legal CHECK (status IN ('committed','cancelled','expired')),
  CONSTRAINT marche_orders_subtotal_positive CHECK (merchandise_subtotal_gnf > 0),
  CONSTRAINT marche_orders_counts_positive CHECK (item_count > 0 AND line_count > 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS marche_orders_buyer_request_key
  ON public.marche_orders(buyer_user_id, client_request_id);
CREATE INDEX IF NOT EXISTS marche_orders_buyer_idx ON public.marche_orders(buyer_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS marche_orders_store_idx ON public.marche_orders(merchant_store_id, created_at DESC);
CREATE INDEX IF NOT EXISTS marche_orders_status_idx ON public.marche_orders(status);

CREATE TABLE IF NOT EXISTS public.marche_order_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.marche_orders(id) ON DELETE CASCADE,
  listing_id uuid NOT NULL REFERENCES public.marketplace_listings(id),
  store_id_snapshot uuid NOT NULL,
  title_snapshot text NOT NULL,
  qty integer NOT NULL,
  unit_price_gnf bigint NOT NULL,
  line_total_gnf bigint NOT NULL,
  source_offer_id uuid NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT marche_order_items_qty_positive CHECK (qty > 0),
  CONSTRAINT marche_order_items_price_positive CHECK (unit_price_gnf > 0),
  CONSTRAINT marche_order_items_total_exact CHECK (line_total_gnf = unit_price_gnf * qty)
);

CREATE INDEX IF NOT EXISTS marche_order_items_order_idx ON public.marche_order_items(order_id);
CREATE INDEX IF NOT EXISTS marche_order_items_listing_idx ON public.marche_order_items(listing_id);

REVOKE ALL ON public.marche_orders FROM anon, authenticated, PUBLIC;
REVOKE ALL ON public.marche_order_items FROM anon, authenticated, PUBLIC;
GRANT ALL ON public.marche_orders TO service_role;
GRANT ALL ON public.marche_order_items TO service_role;

ALTER TABLE public.marche_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.marche_order_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "orders service only" ON public.marche_orders FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "order items service only" ON public.marche_order_items FOR ALL TO service_role USING (true) WITH CHECK (true);

-- ---------- D. immutability / transition guards ----------
CREATE OR REPLACE FUNCTION public.marche_order_guard()
 RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public'
AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF COALESCE(current_setting('marche.rpc', true),'') = '1' THEN RETURN OLD; END IF;
    RAISE EXCEPTION 'ORDER_IMMUTABLE';
  END IF;

  IF NEW.buyer_user_id IS DISTINCT FROM OLD.buyer_user_id
     OR NEW.merchant_store_id IS DISTINCT FROM OLD.merchant_store_id
     OR NEW.merchant_user_id IS DISTINCT FROM OLD.merchant_user_id
     OR NEW.merchandise_subtotal_gnf IS DISTINCT FROM OLD.merchandise_subtotal_gnf
     OR NEW.item_count IS DISTINCT FROM OLD.item_count
     OR NEW.line_count IS DISTINCT FROM OLD.line_count
     OR NEW.source_offer_id IS DISTINCT FROM OLD.source_offer_id
     OR NEW.client_request_id IS DISTINCT FROM OLD.client_request_id
     OR NEW.request_fingerprint IS DISTINCT FROM OLD.request_fingerprint
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
     OR NEW.delivery_address IS DISTINCT FROM OLD.delivery_address
     OR NEW.dropoff_lat IS DISTINCT FROM OLD.dropoff_lat
     OR NEW.dropoff_lng IS DISTINCT FROM OLD.dropoff_lng THEN
    RAISE EXCEPTION 'ORDER_IMMUTABLE';
  END IF;

  -- R3 carries no finance: these stay server-owned and NULL.
  IF NEW.merchant_fee_gnf IS NOT NULL OR NEW.delivery_charge_gnf IS NOT NULL OR NEW.fee_policy_id IS NOT NULL THEN
    RAISE EXCEPTION 'FINANCE_NOT_IN_R3';
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF OLD.status <> 'committed' THEN RAISE EXCEPTION 'ORDER_TERMINAL'; END IF;
    IF NEW.status NOT IN ('cancelled','expired') THEN RAISE EXCEPTION 'ILLEGAL_ORDER_TRANSITION'; END IF;
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END $function$;

DROP TRIGGER IF EXISTS trg_marche_order_guard ON public.marche_orders;
CREATE TRIGGER trg_marche_order_guard BEFORE UPDATE OR DELETE ON public.marche_orders
  FOR EACH ROW EXECUTE FUNCTION public.marche_order_guard();

CREATE OR REPLACE FUNCTION public.marche_order_item_guard()
 RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public'
AS $function$
BEGIN
  IF COALESCE(current_setting('marche.rpc', true),'') = '1' AND TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RAISE EXCEPTION 'ORDER_LINE_IMMUTABLE';
END $function$;

DROP TRIGGER IF EXISTS trg_marche_order_item_guard ON public.marche_order_items;
CREATE TRIGGER trg_marche_order_item_guard BEFORE UPDATE OR DELETE ON public.marche_order_items
  FOR EACH ROW EXECUTE FUNCTION public.marche_order_item_guard();

-- ---------- E. sanitized serializer ----------
CREATE OR REPLACE FUNCTION public.marche_order_json(o public.marche_orders)
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
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
    'merchant_fee_gnf', o.merchant_fee_gnf,
    'delivery_charge_gnf', o.delivery_charge_gnf,
    'fee_policy_id', o.fee_policy_id,
    'reservation_expires_at', o.reservation_expires_at,
    'cancelled_at', o.cancelled_at,
    'cancel_reason', o.cancel_reason,
    'created_at', o.created_at,
    'updated_at', o.updated_at,
    'items', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', i.id, 'listing_id', i.listing_id, 'store_id', i.store_id_snapshot,
        'title', i.title_snapshot, 'qty', i.qty,
        'unit_price_gnf', i.unit_price_gnf, 'line_total_gnf', i.line_total_gnf,
        'source_offer_id', i.source_offer_id) ORDER BY i.created_at, i.id)
      FROM public.marche_order_items i WHERE i.order_id = o.id), '[]'::jsonb)
  );
$function$;

-- ---------- F. commit primitive ----------
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

  -- normalize + validate shape (no prices accepted from the client)
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

    INSERT INTO public.marche_order_items(order_id, listing_id, store_id_snapshot, title_snapshot,
      qty, unit_price_gnf, line_total_gnf, source_offer_id)
    VALUES (v_order_id, l.id, l.store_id, l.title, v_qty, v_unit, v_unit * v_qty, v_offer);

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

  RETURN public.marche_order_json(v_existing);
END $function$;

-- ---------- G. cancel + release ----------
CREATE OR REPLACE FUNCTION public.marche_order_cancel(p_order_id uuid, p_reason text DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE caller uuid := auth.uid(); o public.marche_orders; i record;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  SELECT * INTO o FROM public.marche_orders WHERE id = p_order_id FOR UPDATE;
  IF o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  IF o.buyer_user_id <> caller AND o.merchant_user_id <> caller AND NOT public.is_any_admin(caller) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  IF o.status <> 'committed' THEN
    RETURN public.marche_order_json(o); -- idempotent replay, no second release
  END IF;

  PERFORM set_config('marche.rpc','1', true);
  FOR i IN SELECT listing_id, qty FROM public.marche_order_items WHERE order_id = o.id LOOP
    UPDATE public.marketplace_listings
       SET quantity_reserved = GREATEST(COALESCE(quantity_reserved,0) - i.qty, 0)
     WHERE id = i.listing_id AND quantity_in_stock IS NOT NULL;
  END LOOP;
  UPDATE public.marche_orders
     SET status = 'cancelled', cancelled_at = now(),
         cancel_reason = NULLIF(btrim(COALESCE(p_reason,'')),'')
   WHERE id = o.id RETURNING * INTO o;
  PERFORM set_config('marche.rpc','', true);

  RETURN public.marche_order_json(o);
END $function$;

CREATE OR REPLACE FUNCTION public.marche_order_release_expired(p_limit integer DEFAULT 100)
 RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE o public.marche_orders; i record; n int := 0;
BEGIN
  FOR o IN SELECT * FROM public.marche_orders
            WHERE status = 'committed' AND reservation_expires_at IS NOT NULL
              AND reservation_expires_at <= now()
            ORDER BY reservation_expires_at LIMIT GREATEST(COALESCE(p_limit,100),1)
            FOR UPDATE
  LOOP
    PERFORM set_config('marche.rpc','1', true);
    FOR i IN SELECT listing_id, qty FROM public.marche_order_items WHERE order_id = o.id LOOP
      UPDATE public.marketplace_listings
         SET quantity_reserved = GREATEST(COALESCE(quantity_reserved,0) - i.qty, 0)
       WHERE id = i.listing_id AND quantity_in_stock IS NOT NULL;
    END LOOP;
    UPDATE public.marche_orders SET status = 'expired', cancelled_at = now(),
           cancel_reason = 'RESERVATION_EXPIRED' WHERE id = o.id;
    PERFORM set_config('marche.rpc','', true);
    n := n + 1;
  END LOOP;
  RETURN n;
END $function$;

-- ---------- H. sanitized reads ----------
CREATE OR REPLACE FUNCTION public.marche_order_get(p_order_id uuid)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE caller uuid := auth.uid(); o public.marche_orders;
BEGIN
  IF caller IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO o FROM public.marche_orders WHERE id = p_order_id;
  IF o.id IS NULL THEN RETURN NULL; END IF;
  IF o.buyer_user_id <> caller AND o.merchant_user_id <> caller AND NOT public.is_any_admin(caller) THEN
    RETURN NULL;
  END IF;
  RETURN public.marche_order_json(o);
END $function$;

CREATE OR REPLACE FUNCTION public.marche_orders_for_buyer(p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT COALESCE(jsonb_agg(public.marche_order_json(o) ORDER BY o.created_at DESC), '[]'::jsonb)
  FROM (SELECT * FROM public.marche_orders WHERE auth.uid() IS NOT NULL AND buyer_user_id = auth.uid()
         ORDER BY created_at DESC LIMIT LEAST(COALESCE(p_limit,50),200) OFFSET GREATEST(COALESCE(p_offset,0),0)) o;
$function$;

CREATE OR REPLACE FUNCTION public.marche_orders_for_merchant(p_store_id uuid DEFAULT NULL, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT COALESCE(jsonb_agg(public.marche_order_json(o) ORDER BY o.created_at DESC), '[]'::jsonb)
  FROM (SELECT mo.* FROM public.marche_orders mo
          JOIN public.merchant_stores s ON s.id = mo.merchant_store_id
         WHERE auth.uid() IS NOT NULL
           AND s.owner_user_id = auth.uid()
           AND (p_store_id IS NULL OR mo.merchant_store_id = p_store_id)
         ORDER BY mo.created_at DESC
         LIMIT LEAST(COALESCE(p_limit,50),200) OFFSET GREATEST(COALESCE(p_offset,0),0)) o;
$function$;

CREATE OR REPLACE FUNCTION public.marche_orders_admin(p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT COALESCE(jsonb_agg(public.marche_order_json(o) ORDER BY o.created_at DESC), '[]'::jsonb)
  FROM (SELECT * FROM public.marche_orders
         WHERE public.is_any_admin(auth.uid())
         ORDER BY created_at DESC LIMIT LEAST(COALESCE(p_limit,100),500) OFFSET GREATEST(COALESCE(p_offset,0),0)) o;
$function$;

-- ---------- I. execute ACLs ----------
REVOKE ALL ON FUNCTION public.marche_order_commit(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_order_cancel(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_order_get(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_orders_for_buyer(integer, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_orders_for_merchant(uuid, integer, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_orders_admin(integer, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_order_release_expired(integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.marche_order_json(public.marche_orders) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.marche_order_commit(jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.marche_order_cancel(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.marche_order_get(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.marche_orders_for_buyer(integer, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.marche_orders_for_merchant(uuid, integer, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.marche_orders_admin(integer, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.marche_order_release_expired(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.marche_order_json(public.marche_orders) TO service_role;