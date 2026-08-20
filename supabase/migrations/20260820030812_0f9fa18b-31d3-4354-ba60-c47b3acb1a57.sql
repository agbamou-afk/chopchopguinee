-- Back-compat: the pre-R10 6-argument discovery call must keep working.
CREATE OR REPLACE FUNCTION public.marche_listings_discover(
  p_search text DEFAULT NULL,
  p_category text DEFAULT NULL,
  p_store_id uuid DEFAULT NULL,
  p_sort text DEFAULT 'recent',
  p_limit integer DEFAULT 60,
  p_offset integer DEFAULT 0)
RETURNS TABLE(id uuid, title text, price_gnf bigint, is_negotiable boolean, is_urgent boolean,
  delivery_available boolean, neighborhood text, commune text, created_at timestamptz, kind text,
  availability text, fulfillment_options text[], photo_count integer, condition text,
  description text, category text, store_id uuid, cover_url text,
  rank_score_bps integer, rank_distance_m numeric, rank_evidence jsonb)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT * FROM public.marche_listings_discover(
    p_search, p_category, p_store_id, p_sort, p_limit, p_offset, NULL, NULL);
$$;
REVOKE ALL ON FUNCTION public.marche_listings_discover(text,text,uuid,text,integer,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.marche_listings_discover(text,text,uuid,text,integer,integer)
  TO anon, authenticated, service_role;

GRANT EXECUTE ON FUNCTION public._qa_s13_ok(text, boolean, text) TO service_role;