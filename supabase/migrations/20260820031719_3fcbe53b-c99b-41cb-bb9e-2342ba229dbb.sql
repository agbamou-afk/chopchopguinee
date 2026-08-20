-- 1) QA role probes must restore the exact effective role, not RESET to session_user.
CREATE OR REPLACE FUNCTION public._qa_r6_err(p_role text, p_uid uuid, p_sql text)
 RETURNS text LANGUAGE plpgsql SET search_path TO 'public'
AS $function$
DECLARE v_err text := 'OK'; v_prev text := current_user;
BEGIN
  PERFORM set_config('request.jwt.claims',
    CASE WHEN p_uid IS NULL THEN '{"role":"anon"}' ELSE public._as_user_claims(p_uid) END, true);
  EXECUTE 'SET LOCAL ROLE ' || quote_ident(p_role);
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM;
  END;
  EXECUTE 'SET LOCAL ROLE ' || quote_ident(v_prev);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN v_err;
EXCEPTION WHEN OTHERS THEN
  EXECUTE 'SET LOCAL ROLE ' || quote_ident(v_prev);
  RETURN 'HARNESS_ERROR:' || SQLERRM;
END $function$;

CREATE OR REPLACE FUNCTION public._qa_node4_probe(p_role text, p_uid uuid, p_sql text)
 RETURNS integer LANGUAGE plpgsql SET search_path TO 'public'
AS $function$
DECLARE n integer; v_prev text := current_user;
BEGIN
  PERFORM set_config('request.jwt.claims',
    CASE WHEN p_uid IS NULL THEN '{"role":"anon"}' ELSE public._as_user_claims(p_uid) END, true);
  EXECUTE 'SET LOCAL ROLE ' || quote_ident(p_role);
  EXECUTE p_sql INTO n;
  EXECUTE 'SET LOCAL ROLE ' || quote_ident(v_prev);
  RETURN n;
EXCEPTION WHEN OTHERS THEN
  EXECUTE 'SET LOCAL ROLE ' || quote_ident(v_prev);
  RETURN -1;
END $function$;

CREATE OR REPLACE FUNCTION public._qa_s13_om_rolecall(p_role text, p_uid uuid, p_sql text, p_a1 text, p_a2 text)
 RETURNS text LANGUAGE plpgsql SET search_path TO 'public'
AS $function$
DECLARE v_err text := 'NO_ERROR'; v_prev text := current_user;
BEGIN
  PERFORM set_config('request.jwt.claims',
    CASE WHEN p_uid IS NULL THEN '' ELSE public._as_user_claims(p_uid) END, true);
  EXECUTE format('SET LOCAL ROLE %I', p_role);
  BEGIN
    EXECUTE p_sql USING p_a1, p_a2;
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM;
  END;
  EXECUTE 'SET LOCAL ROLE ' || quote_ident(v_prev);
  PERFORM set_config('request.jwt.claims','',true);
  RETURN v_err;
END $function$;

CREATE OR REPLACE FUNCTION public._qa_s13_rls_probe(p_role text, p_uid uuid, p_op text, p_bucket text, p_name text)
 RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'public'
AS $function$
DECLARE v_n bigint := -1; v_err text := 'NO_ERROR'; v_prev text := current_user;
BEGIN
  PERFORM set_config('request.jwt.claims',
    CASE WHEN p_uid IS NULL THEN '' ELSE public._as_user_claims(p_uid) END, true);
  EXECUTE format('SET LOCAL ROLE %I', p_role);
  BEGIN
    IF p_op = 'select' THEN
      SELECT count(*) INTO v_n FROM storage.objects o
       WHERE o.bucket_id = p_bucket AND o.name = p_name;
    ELSIF p_op = 'insert' THEN
      INSERT INTO storage.objects(bucket_id, name, owner, owner_id)
      VALUES (p_bucket, p_name, p_uid, p_uid::text);
      v_n := 1;
    ELSIF p_op = 'update' THEN
      UPDATE storage.objects SET metadata = COALESCE(metadata,'{}'::jsonb) || '{"qa":true}'::jsonb
       WHERE bucket_id = p_bucket AND name = p_name;
      GET DIAGNOSTICS v_n = ROW_COUNT;
    ELSIF p_op = 'delete' THEN
      DELETE FROM storage.objects WHERE bucket_id = p_bucket AND name = p_name;
      GET DIAGNOSTICS v_n = ROW_COUNT;
    ELSIF p_op = 'photos' THEN
      SELECT count(*) INTO v_n FROM public.package_evidence_photos WHERE storage_path = p_name;
    ELSE
      v_err := 'unknown_op';
    END IF;
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM;
  END;
  EXECUTE 'SET LOCAL ROLE ' || quote_ident(v_prev);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN jsonb_build_object('count', v_n, 'error', v_err);
END $function$;

-- 2) Discovery: keep the frozen 6-argument public contract callable, unambiguously.
--    The ranked form requires both coordinates explicitly (no defaults) so a
--    6-argument call can only ever resolve to the compatibility wrapper.
DROP FUNCTION IF EXISTS public.marche_listings_discover(text,text,uuid,text,integer,integer,double precision,double precision);

CREATE FUNCTION public.marche_listings_discover(
  p_search text, p_category text, p_store_id uuid, p_sort text,
  p_limit integer, p_offset integer,
  p_lat double precision, p_lng double precision)
RETURNS TABLE(id uuid, title text, price_gnf bigint, is_negotiable boolean, is_urgent boolean,
  delivery_available boolean, neighborhood text, commune text, created_at timestamptz, kind text,
  availability text, fulfillment_options text[], photo_count integer, condition text,
  description text, category text, store_id uuid, cover_url text,
  rank_score_bps integer, rank_distance_m numeric, rank_evidence jsonb)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_sort text := lower(COALESCE(p_sort, 'recent'));
  v_limit int := GREATEST(1, LEAST(COALESCE(p_limit, 60), 200));
  v_offset int := GREATEST(0, COALESCE(p_offset, 0));
  pol jsonb;
BEGIN
  IF v_sort NOT IN ('recent','price_asc','price_desc','recommended') THEN
    v_sort := 'recent';
  END IF;

  -- Manual sorts are exact user overrides: never reordered, never annotated.
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
             'qualified_components', s.ev->'qualified_components',
             'cold_start', s.ev->'cold_start',
             'why_ranked', s.ev->'why_ranked'
           )
      FROM scored s
     ORDER BY (s.ev->>'score_bps')::int DESC NULLS LAST, s.created_at DESC, s.id
     LIMIT v_limit OFFSET v_offset;
END;
$function$;

CREATE OR REPLACE FUNCTION public.marche_listings_discover(
  p_search text DEFAULT NULL, p_category text DEFAULT NULL, p_store_id uuid DEFAULT NULL,
  p_sort text DEFAULT 'recent', p_limit integer DEFAULT 60, p_offset integer DEFAULT 0)
RETURNS TABLE(id uuid, title text, price_gnf bigint, is_negotiable boolean, is_urgent boolean,
  delivery_available boolean, neighborhood text, commune text, created_at timestamptz, kind text,
  availability text, fulfillment_options text[], photo_count integer, condition text,
  description text, category text, store_id uuid, cover_url text,
  rank_score_bps integer, rank_distance_m numeric, rank_evidence jsonb)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT * FROM public.marche_listings_discover(
    p_search, p_category, p_store_id, p_sort, p_limit, p_offset,
    NULL::double precision, NULL::double precision);
$function$;

REVOKE ALL ON FUNCTION public.marche_listings_discover(text,text,uuid,text,integer,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.marche_listings_discover(text,text,uuid,text,integer,integer,double precision,double precision) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.marche_listings_discover(text,text,uuid,text,integer,integer) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.marche_listings_discover(text,text,uuid,text,integer,integer,double precision,double precision) TO anon, authenticated, service_role;

-- The temporary QA grant added while diagnosing the runner is not part of frozen truth.
REVOKE EXECUTE ON FUNCTION public._qa_s13_ok(text, boolean, text) FROM service_role;