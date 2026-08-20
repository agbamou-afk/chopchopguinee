-- R10 Part B: recommended discovery + sanitized public transparency reads.

DROP FUNCTION IF EXISTS public.marche_listings_discover(text, text, uuid, text, integer, integer);

CREATE OR REPLACE FUNCTION public.marche_listings_discover(
  p_search text DEFAULT NULL,
  p_category text DEFAULT NULL,
  p_store_id uuid DEFAULT NULL,
  p_sort text DEFAULT 'recent',
  p_limit integer DEFAULT 60,
  p_offset integer DEFAULT 0,
  p_lat double precision DEFAULT NULL,
  p_lng double precision DEFAULT NULL
) RETURNS TABLE(
  id uuid, title text, price_gnf bigint, is_negotiable boolean, is_urgent boolean,
  delivery_available boolean, neighborhood text, commune text, created_at timestamptz,
  kind text, availability text, fulfillment_options text[], photo_count integer,
  condition text, description text, category text, store_id uuid, cover_url text,
  rank_score_bps integer, rank_distance_m numeric, rank_evidence jsonb
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_sort text := lower(COALESCE(p_sort, 'recent'));
  v_limit int := GREATEST(1, LEAST(COALESCE(p_limit, 60), 200));
  v_offset int := GREATEST(0, COALESCE(p_offset, 0));
  pol jsonb;
BEGIN
  IF v_sort NOT IN ('recent','price_asc','price_desc','recommended') THEN
    v_sort := 'recent';
  END IF;

  -- Manual sorts are exact user overrides: never reordered by ranking.
  IF v_sort <> 'recommended' THEN
    RETURN QUERY
      SELECT l.id, l.title, l.price_gnf, l.is_negotiable, l.is_urgent, l.delivery_available,
             l.neighborhood, l.commune, l.created_at, l.kind::text, l.availability::text,
             l.fulfillment_options, l.photo_count, l.condition, l.description, l.category,
             l.store_id,
             (SELECT i.url FROM public.listing_images i
               WHERE i.listing_id = l.id
               ORDER BY i.is_primary DESC, i.position ASC LIMIT 1) AS cover_url,
             NULL::integer, NULL::numeric, NULL::jsonb
        FROM public.marketplace_listings l
        JOIN public.v_marche_listing_truth v ON v.listing_id = l.id AND v.is_orderable
       WHERE (p_category IS NULL OR l.category = p_category)
         AND (p_store_id IS NULL OR l.store_id = p_store_id)
         AND (p_search IS NULL OR btrim(p_search) = '' OR l.title ILIKE '%' || btrim(p_search) || '%')
       ORDER BY
         CASE WHEN v_sort = 'price_asc'  THEN l.price_gnf END ASC NULLS LAST,
         CASE WHEN v_sort = 'price_desc' THEN l.price_gnf END DESC NULLS LAST,
         l.created_at DESC, l.id
       LIMIT v_limit OFFSET v_offset;
    RETURN;
  END IF;

  pol := public._marche_ranking_policy(now());

  RETURN QUERY
    WITH candidates AS (
      SELECT l.*
        FROM public.marketplace_listings l
        JOIN public.v_marche_listing_truth v ON v.listing_id = l.id AND v.is_orderable
       WHERE (p_category IS NULL OR l.category = p_category)
         AND (p_store_id IS NULL OR l.store_id = p_store_id)
         AND (p_search IS NULL OR btrim(p_search) = '' OR l.title ILIKE '%' || btrim(p_search) || '%')
       ORDER BY l.created_at DESC, l.id
       LIMIT 400
    ), scored AS (
      SELECT c.*, public._marche_rank_evidence(c.id, p_lat, p_lng, pol) AS ev
        FROM candidates c
    )
    SELECT s.id, s.title, s.price_gnf, s.is_negotiable, s.is_urgent, s.delivery_available,
           s.neighborhood, s.commune, s.created_at, s.kind::text, s.availability::text,
           s.fulfillment_options, s.photo_count, s.condition, s.description, s.category,
           s.store_id,
           (SELECT i.url FROM public.listing_images i
             WHERE i.listing_id = s.id
             ORDER BY i.is_primary DESC, i.position ASC LIMIT 1) AS cover_url,
           (s.ev->>'score_bps')::int,
           NULLIF(s.ev#>>'{components,distance,distance_m}', '')::numeric,
           jsonb_build_object(
             'policy_version', s.ev->'policy_version',
             'score_bps', s.ev->'score_bps',
             'evidence_completeness', s.ev->'evidence_completeness',
             'cold_start', s.ev->'cold_start',
             'components', s.ev->'components'
           )
      FROM scored s
     ORDER BY (s.ev->>'score_bps')::int DESC NULLS LAST, s.created_at DESC, s.id
     LIMIT v_limit OFFSET v_offset;
END;
$$;

GRANT EXECUTE ON FUNCTION public.marche_listings_discover(text, text, uuid, text, integer, integer, double precision, double precision) TO anon, authenticated, service_role;

-- Sanitized public transparency: what the ranking policy currently is.
CREATE OR REPLACE FUNCTION public.marche_ranking_policy_public()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE pol jsonb := public._marche_ranking_policy(now());
BEGIN
  IF pol IS NULL THEN
    RETURN jsonb_build_object('available', false, 'reason', 'NO_EFFECTIVE_RANKING_POLICY');
  END IF;
  RETURN jsonb_build_object(
    'available', true,
    'version', (pol->>'version')::int,
    'label', pol->>'label',
    'effective_from', pol->>'effective_from',
    'weights_bps', jsonb_build_object(
      'price', (pol->>'w_price')::int,
      'reputation', (pol->>'w_reputation')::int,
      'reliability', (pol->>'w_reliability')::int,
      'distance', (pol->>'w_distance')::int,
      'freshness', (pol->>'w_freshness')::int),
    'thresholds', jsonb_build_object(
      'min_price_observations', (pol->>'min_price_observations')::int,
      'min_reputation_events', (pol->>'min_reputation_events')::int,
      'min_fulfillment_history', (pol->>'min_fulfillment_history')::int,
      'distance_max_m', (pol->>'distance_max_m')::int,
      'freshness_half_life_days', (pol->>'freshness_half_life_days')::int),
    'doctrine', 'Classement fondé sur des preuves. Aucune mise en avant payante.',
    'availability_accuracy_collected', false,
    'distance_method', 'haversine_great_circle'
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.marche_ranking_policy_public() TO anon, authenticated, service_role;

-- Sanitized per-listing explanation (aggregates + honest reasons only, no PII).
CREATE OR REPLACE FUNCTION public.marche_listing_rank_explain(
  p_listing_id uuid,
  p_lat double precision DEFAULT NULL,
  p_lng double precision DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE ev jsonb; ok boolean;
BEGIN
  SELECT v.is_orderable INTO ok
    FROM public.v_marche_listing_truth v WHERE v.listing_id = p_listing_id;
  IF ok IS NOT TRUE THEN
    RETURN jsonb_build_object('listing_id', p_listing_id, 'ranked', false,
                              'reason', 'LISTING_NOT_ORDERABLE');
  END IF;
  ev := public._marche_rank_evidence(p_listing_id, p_lat, p_lng, NULL);
  RETURN ev - 'policy_id';
END;
$$;
GRANT EXECUTE ON FUNCTION public.marche_listing_rank_explain(uuid, double precision, double precision) TO anon, authenticated, service_role;