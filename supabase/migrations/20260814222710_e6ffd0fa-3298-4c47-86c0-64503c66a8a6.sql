-- ============================================================
-- NODE 4 MARCHE R1 — canonical listing & publication truth
-- ============================================================

-- ---------- A. demo supply derivation (deterministic, by auth account) ----------
CREATE OR REPLACE FUNCTION public.marche_is_demo_seller(p_seller_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM auth.users u
     WHERE u.id = p_seller_id
       AND lower(u.email) LIKE 'demo.%@chopchop.gn'
  );
$$;

CREATE OR REPLACE FUNCTION public.marche_seller_banned(p_seller_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.account_bans b
     WHERE b.user_id = p_seller_id
       AND b.status = 'active'
       AND (b.expires_at IS NULL OR b.expires_at > now())
  );
$$;

-- ---------- A. canonical truth view ----------
DROP VIEW IF EXISTS public.v_marche_listing_truth;
CREATE VIEW public.v_marche_listing_truth AS
SELECT
  t.listing_id,
  t.seller_id,
  t.store_id,
  t.kind,
  t.status,
  t.visibility,
  t.availability,
  t.quantity_in_stock,
  t.photo_count,
  t.price_gnf,
  t.pricing_mode,
  t.store_ok,
  t.is_demo,
  t.seller_banned,
  t.refusal_reason,
  (t.refusal_reason IS NULL) AS is_orderable
FROM (
  SELECT
    l.id                AS listing_id,
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
    (s.id IS NOT NULL AND s.status = 'active' AND s.onboarding_status = 'approved') AS store_ok,
    public.marche_is_demo_seller(l.seller_id) AS is_demo,
    public.marche_seller_banned(l.seller_id)  AS seller_banned,
    CASE
      WHEN l.status = 'removed'                                     THEN 'LISTING_REMOVED'
      WHEN l.status = 'sold' OR l.availability = 'sold'             THEN 'LISTING_SOLD'
      WHEN l.status = 'paused'                                      THEN 'LISTING_PAUSED'
      WHEN l.visibility <> 'public'                                 THEN 'LISTING_PRIVATE'
      WHEN public.marche_seller_banned(l.seller_id)                 THEN 'SELLER_NOT_ELIGIBLE'
      WHEN l.store_id IS NOT NULL
       AND NOT (s.id IS NOT NULL AND s.status = 'active' AND s.onboarding_status = 'approved')
                                                                    THEN 'STORE_NOT_APPROVED'
      WHEN public.marche_is_demo_seller(l.seller_id)                THEN 'DEMO_SUPPLY'
      WHEN l.quantity_in_stock IS NOT NULL AND l.quantity_in_stock <= 0 THEN 'OUT_OF_STOCK'
      WHEN l.pricing_mode = 'fixed' AND l.kind = 'merchant'
       AND COALESCE(l.price_gnf, 0) <= 0                            THEN 'INVALID_PRICE'
      ELSE NULL
    END AS refusal_reason
  FROM public.marketplace_listings l
  LEFT JOIN public.merchant_stores s ON s.id = l.store_id
) t;

REVOKE ALL ON public.v_marche_listing_truth FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.marche_listing_truth(p_listing_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT jsonb_build_object(
    'listing_id', v.listing_id,
    'is_orderable', v.is_orderable,
    'refusal_reason', v.refusal_reason,
    'is_demo', v.is_demo,
    'store_ok', v.store_ok,
    'has_photo', COALESCE(v.photo_count,0) > 0
  )
  FROM public.v_marche_listing_truth v
  WHERE v.listing_id = p_listing_id;
$$;

CREATE OR REPLACE FUNCTION public.marche_listing_is_public(p_listing_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT COALESCE((SELECT v.is_orderable FROM public.v_marche_listing_truth v
                    WHERE v.listing_id = p_listing_id), false);
$$;

GRANT EXECUTE ON FUNCTION public.marche_listing_truth(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_listing_is_public(uuid) TO authenticated, anon;

-- ---------- B. one unified publication guard ----------
DROP TRIGGER IF EXISTS enforce_listing_visibility_trg ON public.marketplace_listings;
DROP TRIGGER IF EXISTS trg_marche_enforce_pending_privacy ON public.marketplace_listings;

CREATE OR REPLACE FUNCTION public.marche_publication_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  s_status text;
  s_onboard text;
BEGIN
  -- Seller eligibility applies to every listing kind (community included).
  IF public.marche_seller_banned(NEW.seller_id) THEN
    NEW.visibility := 'private';
    IF NEW.status = 'active' THEN NEW.status := 'paused'; END IF;
    RETURN NEW;
  END IF;

  IF NEW.store_id IS NOT NULL THEN
    SELECT status, onboarding_status INTO s_status, s_onboard
      FROM public.merchant_stores WHERE id = NEW.store_id;
    IF s_onboard IS DISTINCT FROM 'approved'
       OR s_status IS NULL
       OR s_status NOT IN ('active', 'paused') THEN
      NEW.visibility := 'private';
      IF NEW.status = 'active' THEN NEW.status := 'paused'; END IF;
    END IF;
  END IF;

  IF NEW.visibility NOT IN ('public','private') THEN
    RAISE EXCEPTION 'INVALID_VISIBILITY';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_marche_publication_guard
BEFORE INSERT OR UPDATE ON public.marketplace_listings
FOR EACH ROW EXECUTE FUNCTION public.marche_publication_guard();

DROP FUNCTION IF EXISTS public.enforce_listing_visibility();
DROP FUNCTION IF EXISTS public.marche_enforce_pending_merchant_privacy();

-- ---------- C. protected-column trigger honours certified RPC path ----------
CREATE OR REPLACE FUNCTION public.prevent_seller_protected_columns()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF public.has_role(auth.uid(), 'admin'::app_role) THEN
    RETURN NEW;
  END IF;
  IF COALESCE(current_setting('marche.rpc', true), '') = '1' THEN
    -- Certified server primitive: ownership/store/kind still immutable.
    IF NEW.seller_id IS DISTINCT FROM OLD.seller_id THEN RAISE EXCEPTION 'Not allowed to modify seller_id'; END IF;
    IF NEW.store_id  IS DISTINCT FROM OLD.store_id  THEN RAISE EXCEPTION 'Not allowed to modify store_id'; END IF;
    IF NEW.kind      IS DISTINCT FROM OLD.kind      THEN RAISE EXCEPTION 'Not allowed to modify kind'; END IF;
    IF NEW.promoted  IS DISTINCT FROM OLD.promoted  THEN RAISE EXCEPTION 'Not allowed to modify promoted'; END IF;
    RETURN NEW;
  END IF;

  IF NEW.promoted     IS DISTINCT FROM OLD.promoted     THEN RAISE EXCEPTION 'Not allowed to modify promoted'; END IF;
  IF NEW.status       IS DISTINCT FROM OLD.status       THEN RAISE EXCEPTION 'Not allowed to modify status'; END IF;
  IF NEW.sold_count   IS DISTINCT FROM OLD.sold_count   THEN RAISE EXCEPTION 'Not allowed to modify sold_count'; END IF;
  IF NEW.view_count   IS DISTINCT FROM OLD.view_count   THEN RAISE EXCEPTION 'Not allowed to modify view_count'; END IF;
  IF NEW.photo_count  IS DISTINCT FROM OLD.photo_count  THEN RAISE EXCEPTION 'Not allowed to modify photo_count'; END IF;
  IF NEW.seller_id    IS DISTINCT FROM OLD.seller_id    THEN RAISE EXCEPTION 'Not allowed to modify seller_id'; END IF;
  IF NEW.store_id     IS DISTINCT FROM OLD.store_id     THEN RAISE EXCEPTION 'Not allowed to modify store_id'; END IF;
  IF NEW.kind         IS DISTINCT FROM OLD.kind         THEN RAISE EXCEPTION 'Not allowed to modify kind'; END IF;
  RETURN NEW;
END;
$$;

-- ---------- C. shared invariant validator ----------
CREATE OR REPLACE FUNCTION public._marche_listing_assert_valid(l public.marketplace_listings)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'public'
AS $$
BEGIN
  IF l.pricing_mode NOT IN ('fixed','negotiable','quote') THEN
    RAISE EXCEPTION 'INVALID_PRICING_MODE';
  END IF;
  IF l.allow_offers AND l.pricing_mode NOT IN ('negotiable','quote') THEN
    RAISE EXCEPTION 'OFFERS_REQUIRE_NEGOTIABLE_PRICING';
  END IF;
  IF l.quantity_in_stock IS NOT NULL AND l.quantity_in_stock < 0 THEN
    RAISE EXCEPTION 'NEGATIVE_STOCK';
  END IF;
  IF l.price_gnf IS NOT NULL AND l.price_gnf < 0 THEN RAISE EXCEPTION 'INVALID_PRICE'; END IF;
  IF l.asking_price_gnf IS NOT NULL AND l.asking_price_gnf < 0 THEN RAISE EXCEPTION 'INVALID_PRICE'; END IF;
  IF l.minimum_price_gnf IS NOT NULL AND l.minimum_price_gnf < 0 THEN RAISE EXCEPTION 'INVALID_PRICE'; END IF;
  IF l.kind = 'merchant' AND l.pricing_mode = 'fixed'
     AND COALESCE(l.price_gnf, 0) <= 0 THEN
    RAISE EXCEPTION 'INVALID_PRICE';
  END IF;
  IF l.minimum_price_gnf IS NOT NULL
     AND COALESCE(l.asking_price_gnf, l.price_gnf) IS NOT NULL
     AND l.minimum_price_gnf > COALESCE(l.asking_price_gnf, l.price_gnf) THEN
    RAISE EXCEPTION 'MINIMUM_ABOVE_ASKING';
  END IF;
  IF l.title IS NULL OR length(btrim(l.title)) < 3 THEN
    RAISE EXCEPTION 'INVALID_TITLE';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public._marche_listing_authz(p_listing_id uuid)
RETURNS public.marketplace_listings
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE l public.marketplace_listings;
BEGIN
  SELECT * INTO l FROM public.marketplace_listings WHERE id = p_listing_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'LISTING_NOT_FOUND'; END IF;
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF l.seller_id <> auth.uid() AND NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'NOT_LISTING_OWNER';
  END IF;
  RETURN l;
END;
$$;

-- ---------- C. mutation primitives ----------
CREATE OR REPLACE FUNCTION public.marche_listing_create(p_payload jsonb)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_store_id uuid;
  v_kind listing_kind;
  l public.marketplace_listings;
  v_publish boolean := COALESCE((p_payload->>'publish')::boolean, true);
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;

  v_store_id := NULLIF(p_payload->>'store_id','')::uuid;
  IF v_store_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.merchant_stores s
                    WHERE s.id = v_store_id AND s.owner_user_id = v_uid) THEN
      RAISE EXCEPTION 'NOT_STORE_OWNER';
    END IF;
    v_kind := 'merchant';
  ELSE
    v_kind := COALESCE(NULLIF(p_payload->>'kind','')::listing_kind, 'community');
    IF v_kind = 'merchant' THEN v_kind := 'community'; END IF;
  END IF;

  l.id                 := gen_random_uuid();
  l.seller_id          := v_uid;
  l.store_id           := v_store_id;
  l.kind               := v_kind;
  l.category           := COALESCE(NULLIF(p_payload->>'category',''), 'Autre');
  l.title              := btrim(COALESCE(p_payload->>'title',''));
  l.description        := NULLIF(btrim(COALESCE(p_payload->>'description','')), '');
  l.price_gnf          := NULLIF(p_payload->>'price_gnf','')::bigint;
  l.asking_price_gnf   := COALESCE(NULLIF(p_payload->>'asking_price_gnf','')::bigint,
                                   NULLIF(p_payload->>'price_gnf','')::bigint);
  l.pricing_mode       := COALESCE(NULLIF(p_payload->>'pricing_mode',''), 'fixed');
  l.allow_offers       := COALESCE((p_payload->>'allow_offers')::boolean, false);
  l.minimum_price_gnf  := NULLIF(p_payload->>'minimum_price_gnf','')::bigint;
  l.quantity_in_stock  := NULLIF(p_payload->>'quantity_in_stock','')::int;
  l.barcode            := NULLIF(btrim(COALESCE(p_payload->>'barcode','')), '');
  l.is_negotiable      := COALESCE((p_payload->>'is_negotiable')::boolean, false);
  l.is_urgent          := COALESCE((p_payload->>'is_urgent')::boolean, false);
  l.delivery_available := COALESCE((p_payload->>'delivery_available')::boolean, false);
  l.condition          := NULLIF(btrim(COALESCE(p_payload->>'condition','')), '');
  l.neighborhood       := NULLIF(btrim(COALESCE(p_payload->>'neighborhood','')), '');
  l.commune            := NULLIF(btrim(COALESCE(p_payload->>'commune','')), '');
  l.landmark           := NULLIF(btrim(COALESCE(p_payload->>'landmark','')), '');
  l.availability       := COALESCE(NULLIF(p_payload->>'availability','')::listing_availability, 'to_confirm');
  l.fulfillment_options:= COALESCE(
      ARRAY(SELECT jsonb_array_elements_text(CASE WHEN jsonb_typeof(p_payload->'fulfillment_options')='array'
                                                  THEN p_payload->'fulfillment_options' ELSE '[]'::jsonb END)),
      ARRAY['to_confirm']::text[]);
  IF array_length(l.fulfillment_options,1) IS NULL THEN
    l.fulfillment_options := ARRAY['to_confirm']::text[];
  END IF;
  IF NOT l.allow_offers THEN l.minimum_price_gnf := NULL; END IF;
  l.status     := CASE WHEN v_publish THEN 'active'::listing_status ELSE 'paused'::listing_status END;
  l.visibility := CASE WHEN v_publish THEN 'public' ELSE 'private' END;

  PERFORM public._marche_listing_assert_valid(l);

  PERFORM set_config('marche.rpc','1', true);
  INSERT INTO public.marketplace_listings (
    id, seller_id, store_id, kind, category, title, description, price_gnf,
    asking_price_gnf, minimum_price_gnf, pricing_mode, allow_offers,
    quantity_in_stock, barcode, is_negotiable, is_urgent, delivery_available,
    condition, neighborhood, commune, landmark, availability, fulfillment_options,
    status, visibility
  ) VALUES (
    l.id, l.seller_id, l.store_id, l.kind, l.category, l.title, l.description, l.price_gnf,
    l.asking_price_gnf, l.minimum_price_gnf, l.pricing_mode, l.allow_offers,
    l.quantity_in_stock, l.barcode, l.is_negotiable, l.is_urgent, l.delivery_available,
    l.condition, l.neighborhood, l.commune, l.landmark, l.availability, l.fulfillment_options,
    l.status, l.visibility
  );
  PERFORM set_config('marche.rpc','', true);
  RETURN l.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.marche_listing_update(p_listing_id uuid, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  cur public.marketplace_listings;
  nxt public.marketplace_listings;
BEGIN
  cur := public._marche_listing_authz(p_listing_id);
  nxt := cur;

  IF p_payload ? 'title'             THEN nxt.title := btrim(COALESCE(p_payload->>'title','')); END IF;
  IF p_payload ? 'description'       THEN nxt.description := NULLIF(btrim(COALESCE(p_payload->>'description','')),''); END IF;
  IF p_payload ? 'category'          THEN nxt.category := COALESCE(NULLIF(p_payload->>'category',''), cur.category); END IF;
  IF p_payload ? 'price_gnf'         THEN nxt.price_gnf := NULLIF(p_payload->>'price_gnf','')::bigint; END IF;
  IF p_payload ? 'asking_price_gnf'  THEN nxt.asking_price_gnf := NULLIF(p_payload->>'asking_price_gnf','')::bigint; END IF;
  IF p_payload ? 'minimum_price_gnf' THEN nxt.minimum_price_gnf := NULLIF(p_payload->>'minimum_price_gnf','')::bigint; END IF;
  IF p_payload ? 'pricing_mode'      THEN nxt.pricing_mode := COALESCE(NULLIF(p_payload->>'pricing_mode',''), cur.pricing_mode); END IF;
  IF p_payload ? 'allow_offers'      THEN nxt.allow_offers := COALESCE((p_payload->>'allow_offers')::boolean,false); END IF;
  IF p_payload ? 'quantity_in_stock' THEN nxt.quantity_in_stock := NULLIF(p_payload->>'quantity_in_stock','')::int; END IF;
  IF p_payload ? 'barcode'           THEN nxt.barcode := NULLIF(btrim(COALESCE(p_payload->>'barcode','')),''); END IF;
  IF p_payload ? 'is_negotiable'     THEN nxt.is_negotiable := COALESCE((p_payload->>'is_negotiable')::boolean,false); END IF;
  IF p_payload ? 'is_urgent'         THEN nxt.is_urgent := COALESCE((p_payload->>'is_urgent')::boolean,false); END IF;
  IF p_payload ? 'delivery_available'THEN nxt.delivery_available := COALESCE((p_payload->>'delivery_available')::boolean,false); END IF;
  IF p_payload ? 'condition'         THEN nxt.condition := NULLIF(btrim(COALESCE(p_payload->>'condition','')),''); END IF;
  IF p_payload ? 'neighborhood'      THEN nxt.neighborhood := NULLIF(btrim(COALESCE(p_payload->>'neighborhood','')),''); END IF;
  IF p_payload ? 'commune'           THEN nxt.commune := NULLIF(btrim(COALESCE(p_payload->>'commune','')),''); END IF;
  IF p_payload ? 'landmark'          THEN nxt.landmark := NULLIF(btrim(COALESCE(p_payload->>'landmark','')),''); END IF;
  IF p_payload ? 'availability'      THEN nxt.availability := NULLIF(p_payload->>'availability','')::listing_availability; END IF;

  IF NOT nxt.allow_offers THEN nxt.minimum_price_gnf := NULL; END IF;

  PERFORM public._marche_listing_assert_valid(nxt);

  PERFORM set_config('marche.rpc','1', true);
  UPDATE public.marketplace_listings SET
    title = nxt.title, description = nxt.description, category = nxt.category,
    price_gnf = nxt.price_gnf, asking_price_gnf = nxt.asking_price_gnf,
    minimum_price_gnf = nxt.minimum_price_gnf, pricing_mode = nxt.pricing_mode,
    allow_offers = nxt.allow_offers, quantity_in_stock = nxt.quantity_in_stock,
    barcode = nxt.barcode, is_negotiable = nxt.is_negotiable, is_urgent = nxt.is_urgent,
    delivery_available = nxt.delivery_available, condition = nxt.condition,
    neighborhood = nxt.neighborhood, commune = nxt.commune, landmark = nxt.landmark,
    availability = COALESCE(nxt.availability, cur.availability)
  WHERE id = p_listing_id;
  PERFORM set_config('marche.rpc','', true);

  RETURN public.marche_listing_truth(p_listing_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.marche_listing_set_stock(p_listing_id uuid, p_quantity integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE cur public.marketplace_listings;
BEGIN
  cur := public._marche_listing_authz(p_listing_id);
  IF p_quantity IS NULL OR p_quantity < 0 THEN RAISE EXCEPTION 'NEGATIVE_STOCK'; END IF;
  PERFORM set_config('marche.rpc','1', true);
  UPDATE public.marketplace_listings SET quantity_in_stock = p_quantity WHERE id = p_listing_id;
  PERFORM set_config('marche.rpc','', true);
  RETURN p_quantity;
END;
$$;

CREATE OR REPLACE FUNCTION public.marche_listing_adjust_stock(p_listing_id uuid, p_delta integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE cur public.marketplace_listings; v_next integer;
BEGIN
  cur := public._marche_listing_authz(p_listing_id);
  v_next := GREATEST(0, COALESCE(cur.quantity_in_stock,0) + COALESCE(p_delta,0));
  PERFORM set_config('marche.rpc','1', true);
  UPDATE public.marketplace_listings SET quantity_in_stock = v_next WHERE id = p_listing_id;
  PERFORM set_config('marche.rpc','', true);
  RETURN v_next;
END;
$$;

CREATE OR REPLACE FUNCTION public.marche_listing_set_availability(p_listing_id uuid, p_availability text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE cur public.marketplace_listings;
BEGIN
  cur := public._marche_listing_authz(p_listing_id);
  IF p_availability IS NULL OR p_availability NOT IN ('available','limited','to_confirm','reserved','sold') THEN
    RAISE EXCEPTION 'INVALID_AVAILABILITY';
  END IF;
  PERFORM set_config('marche.rpc','1', true);
  UPDATE public.marketplace_listings
     SET availability = p_availability::listing_availability
   WHERE id = p_listing_id;
  PERFORM set_config('marche.rpc','', true);
  RETURN public.marche_listing_truth(p_listing_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.marche_listing_publish(p_listing_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE cur public.marketplace_listings;
BEGIN
  cur := public._marche_listing_authz(p_listing_id);
  IF cur.status = 'removed' THEN RAISE EXCEPTION 'LISTING_REMOVED'; END IF;
  PERFORM public._marche_listing_assert_valid(cur);
  PERFORM set_config('marche.rpc','1', true);
  UPDATE public.marketplace_listings
     SET status = 'active'::listing_status, visibility = 'public'
   WHERE id = p_listing_id;
  PERFORM set_config('marche.rpc','', true);
  RETURN public.marche_listing_truth(p_listing_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.marche_listing_unpublish(p_listing_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE cur public.marketplace_listings;
BEGIN
  cur := public._marche_listing_authz(p_listing_id);
  PERFORM set_config('marche.rpc','1', true);
  UPDATE public.marketplace_listings
     SET status = CASE WHEN cur.status = 'removed' THEN cur.status ELSE 'paused'::listing_status END,
         visibility = 'private'
   WHERE id = p_listing_id;
  PERFORM set_config('marche.rpc','', true);
  RETURN public.marche_listing_truth(p_listing_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.marche_listing_archive(p_listing_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE cur public.marketplace_listings;
BEGIN
  cur := public._marche_listing_authz(p_listing_id);
  PERFORM set_config('marche.rpc','1', true);
  UPDATE public.marketplace_listings
     SET status = 'removed'::listing_status, visibility = 'private'
   WHERE id = p_listing_id;
  PERFORM set_config('marche.rpc','', true);
  RETURN public.marche_listing_truth(p_listing_id);
END;
$$;

REVOKE ALL ON FUNCTION public.marche_listing_create(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_listing_update(uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_listing_set_stock(uuid, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_listing_adjust_stock(uuid, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_listing_set_availability(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_listing_publish(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_listing_unpublish(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_listing_archive(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_listing_create(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_listing_update(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_listing_set_stock(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_listing_adjust_stock(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_listing_set_availability(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_listing_publish(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_listing_unpublish(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_listing_archive(uuid) TO authenticated;

-- ---------- D. canonical discovery read model ----------
CREATE OR REPLACE FUNCTION public.marche_listings_discover(
  p_search text DEFAULT NULL,
  p_category text DEFAULT NULL,
  p_store_id uuid DEFAULT NULL,
  p_sort text DEFAULT 'recent',
  p_limit integer DEFAULT 60,
  p_offset integer DEFAULT 0
)
RETURNS TABLE (
  id uuid, title text, price_gnf bigint, is_negotiable boolean, is_urgent boolean,
  delivery_available boolean, neighborhood text, commune text, created_at timestamptz,
  kind text, availability text, fulfillment_options text[], photo_count integer,
  condition text, description text, category text, store_id uuid, cover_url text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT l.id, l.title, l.price_gnf, l.is_negotiable, l.is_urgent, l.delivery_available,
         l.neighborhood, l.commune, l.created_at, l.kind::text, l.availability::text,
         l.fulfillment_options, l.photo_count, l.condition, l.description, l.category,
         l.store_id,
         (SELECT i.url FROM public.listing_images i
           WHERE i.listing_id = l.id
           ORDER BY i.is_primary DESC, i.position ASC LIMIT 1) AS cover_url
    FROM public.marketplace_listings l
    JOIN public.v_marche_listing_truth v ON v.listing_id = l.id AND v.is_orderable
   WHERE (p_category IS NULL OR l.category = p_category)
     AND (p_store_id IS NULL OR l.store_id = p_store_id)
     AND (p_search IS NULL OR btrim(p_search) = '' OR l.title ILIKE '%' || btrim(p_search) || '%')
   ORDER BY
     CASE WHEN p_sort = 'price_asc'  THEN l.price_gnf END ASC NULLS LAST,
     CASE WHEN p_sort = 'price_desc' THEN l.price_gnf END DESC NULLS LAST,
     l.created_at DESC
   LIMIT GREATEST(1, LEAST(COALESCE(p_limit,60), 200))
  OFFSET GREATEST(0, COALESCE(p_offset,0));
$$;

CREATE OR REPLACE FUNCTION public.marche_listing_public(p_listing_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v public.v_marche_listing_truth%ROWTYPE;
  l public.marketplace_listings;
  v_allowed boolean;
BEGIN
  SELECT * INTO v FROM public.v_marche_listing_truth WHERE listing_id = p_listing_id;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO l FROM public.marketplace_listings WHERE id = p_listing_id;

  v_allowed := v.is_orderable
    OR (auth.uid() IS NOT NULL AND (l.seller_id = auth.uid() OR public.has_role(auth.uid(),'admin'::app_role)));
  IF NOT v_allowed THEN RETURN NULL; END IF;

  RETURN jsonb_build_object(
    'id', l.id, 'seller_id', l.seller_id, 'store_id', l.store_id, 'kind', l.kind,
    'category', l.category, 'title', l.title, 'description', l.description,
    'price_gnf', l.price_gnf, 'is_negotiable', l.is_negotiable, 'is_urgent', l.is_urgent,
    'delivery_available', l.delivery_available, 'condition', l.condition,
    'neighborhood', l.neighborhood, 'commune', l.commune, 'landmark', l.landmark,
    'created_at', l.created_at, 'availability', l.availability,
    'fulfillment_options', to_jsonb(l.fulfillment_options), 'photo_count', l.photo_count,
    'pricing_mode', l.pricing_mode, 'asking_price_gnf', l.asking_price_gnf,
    'allow_offers', l.allow_offers, 'quantity_in_stock', l.quantity_in_stock,
    'is_orderable', v.is_orderable, 'refusal_reason', v.refusal_reason,
    'images', COALESCE((SELECT jsonb_agg(i.url ORDER BY i.is_primary DESC, i.position ASC)
                          FROM public.listing_images i WHERE i.listing_id = l.id), '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.marche_store_listing_previews(p_store_ids uuid[])
RETURNS TABLE (store_id uuid, listing_count integer, sample_photos text[])
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT l.store_id,
         count(*)::int,
         (ARRAY_REMOVE(ARRAY_AGG(
            (SELECT i.url FROM public.listing_images i
              WHERE i.listing_id = l.id
              ORDER BY i.is_primary DESC, i.position ASC LIMIT 1)
            ORDER BY l.created_at DESC), NULL))[1:3]
    FROM public.marketplace_listings l
    JOIN public.v_marche_listing_truth v ON v.listing_id = l.id AND v.is_orderable
   WHERE l.store_id = ANY(p_store_ids)
   GROUP BY l.store_id;
$$;

CREATE OR REPLACE FUNCTION public.marche_listings_owner(p_limit integer DEFAULT 200)
RETURNS TABLE (
  id uuid, seller_id uuid, store_id uuid, title text, description text, category text,
  price_gnf bigint, quantity_in_stock integer, barcode text, status text, visibility text,
  photo_count integer, availability text, created_at timestamptz, updated_at timestamptz,
  pricing_mode text, asking_price_gnf bigint, allow_offers boolean, kind text,
  is_orderable boolean, refusal_reason text, cover_url text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT l.id, l.seller_id, l.store_id, l.title, l.description, l.category, l.price_gnf,
         l.quantity_in_stock, l.barcode, l.status::text, l.visibility, l.photo_count,
         l.availability::text, l.created_at, l.updated_at, l.pricing_mode, l.asking_price_gnf,
         l.allow_offers, l.kind::text, v.is_orderable, v.refusal_reason,
         (SELECT i.url FROM public.listing_images i WHERE i.listing_id = l.id
           ORDER BY i.is_primary DESC, i.position ASC LIMIT 1)
    FROM public.marketplace_listings l
    JOIN public.v_marche_listing_truth v ON v.listing_id = l.id
   WHERE auth.uid() IS NOT NULL AND l.seller_id = auth.uid()
   ORDER BY l.created_at DESC
   LIMIT GREATEST(1, LEAST(COALESCE(p_limit,200), 500));
$$;

CREATE OR REPLACE FUNCTION public.marche_store_listings_owner(p_store_id uuid, p_limit integer DEFAULT 500)
RETURNS TABLE (
  id uuid, seller_id uuid, store_id uuid, title text, description text, category text,
  price_gnf bigint, quantity_in_stock integer, barcode text, status text, visibility text,
  photo_count integer, availability text, created_at timestamptz, updated_at timestamptz,
  pricing_mode text, asking_price_gnf bigint, allow_offers boolean, kind text,
  is_orderable boolean, refusal_reason text, cover_url text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT l.id, l.seller_id, l.store_id, l.title, l.description, l.category, l.price_gnf,
         l.quantity_in_stock, l.barcode, l.status::text, l.visibility, l.photo_count,
         l.availability::text, l.created_at, l.updated_at, l.pricing_mode, l.asking_price_gnf,
         l.allow_offers, l.kind::text, v.is_orderable, v.refusal_reason,
         (SELECT i.url FROM public.listing_images i WHERE i.listing_id = l.id
           ORDER BY i.is_primary DESC, i.position ASC LIMIT 1)
    FROM public.marketplace_listings l
    JOIN public.v_marche_listing_truth v ON v.listing_id = l.id
    JOIN public.merchant_stores s ON s.id = l.store_id
   WHERE l.store_id = p_store_id
     AND auth.uid() IS NOT NULL
     AND (s.owner_user_id = auth.uid() OR public.has_role(auth.uid(),'admin'::app_role))
   ORDER BY l.created_at DESC
   LIMIT GREATEST(1, LEAST(COALESCE(p_limit,500), 1000));
$$;

GRANT EXECUTE ON FUNCTION public.marche_listings_discover(text, text, uuid, text, integer, integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.marche_listing_public(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.marche_store_listing_previews(uuid[]) TO anon, authenticated;
REVOKE ALL ON FUNCTION public.marche_listings_owner(integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_store_listings_owner(uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_listings_owner(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_store_listings_owner(uuid, integer) TO authenticated;

-- ---------- C. revoke direct write authority ----------
DROP POLICY IF EXISTS "Sellers create own listings" ON public.marketplace_listings;
DROP POLICY IF EXISTS "Sellers update own listings" ON public.marketplace_listings;
DROP POLICY IF EXISTS "Sellers delete own listings" ON public.marketplace_listings;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.marketplace_listings FROM anon, authenticated;
GRANT SELECT ON public.marketplace_listings TO anon, authenticated;

-- ---------- F. media privacy ----------
DROP POLICY IF EXISTS "Anyone can view listing images" ON public.listing_images;
CREATE POLICY "Public read images of public listings"
ON public.listing_images FOR SELECT
TO anon, authenticated
USING (
  public.marche_listing_is_public(listing_id)
  OR EXISTS (SELECT 1 FROM public.marketplace_listings l
              WHERE l.id = listing_images.listing_id AND l.seller_id = auth.uid())
  OR public.has_role(auth.uid(), 'admin'::app_role)
);

REVOKE INSERT, UPDATE, DELETE ON public.listing_images FROM anon;
REVOKE INSERT, UPDATE, DELETE ON public.listing_metrics FROM anon, authenticated;

-- ---------- G. anon surface trim ----------
REVOKE ALL ON FUNCTION public.marche_toggle_listing_save(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.withdraw_marketplace_offer(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.get_listing_minimum_price(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.get_merchant_listing_full(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.set_primary_listing_image(uuid) FROM anon;