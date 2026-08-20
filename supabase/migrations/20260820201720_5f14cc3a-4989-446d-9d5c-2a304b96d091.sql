-- ===== FINDING 1: least privilege on Marche tables =====
REVOKE TRUNCATE, TRIGGER, REFERENCES ON
  public.marketplace_offers,
  public.marketplace_listings,
  public.merchant_stores,
  public.listing_images,
  public.listing_interests,
  public.listing_saves,
  public.listing_reports,
  public.listing_metrics,
  public.saved_listings,
  public.market_onboarding_assignments,
  public.market_onboarding_campaigns
FROM anon, authenticated, PUBLIC;

-- anon: read-only everywhere on the Marche surface
REVOKE INSERT, UPDATE, DELETE ON
  public.merchant_stores,
  public.listing_images,
  public.listing_interests,
  public.listing_saves,
  public.listing_reports,
  public.saved_listings,
  public.market_onboarding_assignments,
  public.market_onboarding_campaigns
FROM anon;

-- authenticated: keep only the direct Data API writes the client actually uses
REVOKE DELETE ON public.merchant_stores FROM authenticated;          -- stores are never client-deleted
REVOKE UPDATE ON public.listing_images FROM authenticated;           -- images are insert/delete only
REVOKE DELETE ON public.listing_interests FROM authenticated;        -- interests are append + state update
REVOKE INSERT, UPDATE, DELETE ON public.listing_saves FROM authenticated;
REVOKE UPDATE, DELETE ON public.listing_reports FROM authenticated;  -- reports are append-only for users
REVOKE UPDATE ON public.saved_listings FROM authenticated;           -- save/unsave = insert/delete
REVOKE INSERT, UPDATE, DELETE ON
  public.market_onboarding_assignments,
  public.market_onboarding_campaigns
FROM authenticated;

-- ===== FINDING 3: null-safe cockpit authorization guard =====
CREATE OR REPLACE FUNCTION public.marche_merchant_orders_cockpit(
  p_store_id uuid DEFAULT NULL::uuid, p_bucket text DEFAULT NULL::text,
  p_limit integer DEFAULT 40, p_offset integer DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  caller uuid := auth.uid();
  v_limit int := LEAST(GREATEST(COALESCE(p_limit,40),1),100);
  v_offset int := GREATEST(COALESCE(p_offset,0),0);
  v_counts jsonb;
  v_items jsonb;
BEGIN
  -- Fail closed: an unauthenticated caller is refused explicitly, never by
  -- three-valued logic on a privilege predicate evaluated over NULL.
  IF caller IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF p_bucket IS NOT NULL AND p_bucket NOT IN
     ('action_required','preparing','in_delivery','completed','cancelled') THEN
    RAISE EXCEPTION 'UNKNOWN_BUCKET' USING DETAIL = p_bucket;
  END IF;

  WITH scoped AS (
    SELECT o.* FROM public.marche_orders o
     WHERE (p_store_id IS NULL OR o.merchant_store_id = p_store_id)
       AND public._marche_merchant_ops_authorized(o, caller)
  )
  SELECT jsonb_object_agg(b, n) INTO v_counts FROM (
    SELECT public._marche_order_ops_bucket(s.*) AS b, count(*) AS n
      FROM scoped s GROUP BY 1) q(b,n);

  WITH scoped AS (
    SELECT o.* FROM public.marche_orders o
     WHERE (p_store_id IS NULL OR o.merchant_store_id = p_store_id)
       AND public._marche_merchant_ops_authorized(o, caller)
  ), filtered AS (
    SELECT s.* FROM scoped s
     WHERE p_bucket IS NULL OR public._marche_order_ops_bucket(s.*) = p_bucket
     ORDER BY s.created_at DESC
     LIMIT v_limit OFFSET v_offset
  )
  SELECT COALESCE(jsonb_agg(public.marche_merchant_order_ops(f.id) ORDER BY f.created_at DESC), '[]'::jsonb)
    INTO v_items FROM filtered f;

  RETURN jsonb_build_object('counts', COALESCE(v_counts,'{}'::jsonb),
                            'items', COALESCE(v_items,'[]'::jsonb));
END $function$;

-- ===== FINDING 2: merchant ask coherence (historical price truth) =====
-- Root cause: marche_listing_create derives asking_price_gnf from price_gnf,
-- but marche_listing_update let the two diverge. The effective merchant ask is
-- COALESCE(asking_price_gnf, price_gnf), so a merchant moving price_gnf alone
-- never changed the effective ask and every ingest reported ALREADY_OBSERVED.
CREATE OR REPLACE FUNCTION public.marche_listing_update(p_listing_id uuid, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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

  -- Ask coherence: the public ask follows the catalogue price unless the caller
  -- states an explicit asking price in the same payload.
  IF (p_payload ? 'price_gnf') AND NOT (p_payload ? 'asking_price_gnf') THEN
    nxt.asking_price_gnf := nxt.price_gnf;
  END IF;

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
$function$;