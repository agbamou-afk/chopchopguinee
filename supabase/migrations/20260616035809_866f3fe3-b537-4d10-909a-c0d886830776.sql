
-- ============ Indexes for performance ============
CREATE INDEX IF NOT EXISTS idx_map_places_latlng ON public.map_places (lat, lng);
CREATE INDEX IF NOT EXISTS idx_map_places_lower_name ON public.map_places (lower(name));
CREATE INDEX IF NOT EXISTS idx_map_places_verification_status ON public.map_places (verification_status);
CREATE INDEX IF NOT EXISTS idx_map_places_duplicate_of ON public.map_places (duplicate_of);
CREATE INDEX IF NOT EXISTS idx_map_places_active ON public.map_places (active);

-- ============ Candidate table ============
CREATE TABLE IF NOT EXISTS public.map_place_duplicate_candidates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  place_a_id uuid NOT NULL REFERENCES public.map_places(id) ON DELETE CASCADE,
  place_b_id uuid NOT NULL REFERENCES public.map_places(id) ON DELETE CASCADE,
  score integer NOT NULL DEFAULT 0,
  reason_codes text[] NOT NULL DEFAULT '{}',
  distance_meters numeric,
  name_similarity numeric,
  phone_match boolean NOT NULL DEFAULT false,
  category_match boolean NOT NULL DEFAULT false,
  commune_match boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'open'
    CHECK (status IN ('open','confirmed_duplicate','dismissed','merged','needs_field_check')),
  reviewed_by uuid,
  reviewed_at timestamptz,
  merge_target_place_id uuid REFERENCES public.map_places(id) ON DELETE SET NULL,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT map_place_dup_distinct CHECK (place_a_id <> place_b_id)
);

-- normalized pair uniqueness (least/greatest) to avoid duplicate pair rows
CREATE UNIQUE INDEX IF NOT EXISTS uq_map_place_dup_pair
  ON public.map_place_duplicate_candidates (
    LEAST(place_a_id, place_b_id),
    GREATEST(place_a_id, place_b_id)
  );

CREATE INDEX IF NOT EXISTS idx_map_place_dup_status ON public.map_place_duplicate_candidates (status);
CREATE INDEX IF NOT EXISTS idx_map_place_dup_score ON public.map_place_duplicate_candidates (score DESC);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.map_place_duplicate_candidates TO authenticated;
GRANT ALL ON public.map_place_duplicate_candidates TO service_role;

ALTER TABLE public.map_place_duplicate_candidates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admins read dup candidates"
  ON public.map_place_duplicate_candidates FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "admins write dup candidates"
  ON public.map_place_duplicate_candidates FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

CREATE TRIGGER trg_map_place_dup_updated
  BEFORE UPDATE ON public.map_place_duplicate_candidates
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============ Helper: haversine meters ============
CREATE OR REPLACE FUNCTION public._map_distance_meters(
  a_lat double precision, a_lng double precision,
  b_lat double precision, b_lng double precision
) RETURNS double precision
LANGUAGE sql IMMUTABLE
AS $$
  SELECT 2 * 6371000 * asin(
    sqrt(
      sin(radians((b_lat - a_lat)/2))^2 +
      cos(radians(a_lat)) * cos(radians(b_lat)) *
      sin(radians((b_lng - a_lng)/2))^2
    )
  );
$$;

-- ============ Detection RPC ============
CREATE OR REPLACE FUNCTION public.map_detect_place_duplicates(
  p_place_id uuid DEFAULT NULL,
  p_radius_meters integer DEFAULT 150
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inserted integer := 0;
  v_admin boolean;
BEGIN
  v_admin := public.has_role(auth.uid(), 'admin');
  IF NOT v_admin AND auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  WITH base AS (
    SELECT * FROM public.map_places
    WHERE active = true AND duplicate_of IS NULL
      AND lat IS NOT NULL AND lng IS NOT NULL
      AND (p_place_id IS NULL OR id = p_place_id)
    ORDER BY updated_at DESC
    LIMIT CASE WHEN p_place_id IS NULL THEN 200 ELSE 1 END
  ),
  pairs AS (
    SELECT
      a.id AS a_id, b.id AS b_id,
      a.name AS a_name, b.name AS b_name,
      a.category AS a_cat, b.category AS b_cat,
      a.commune AS a_com, b.commune AS b_com,
      public._map_distance_meters(a.lat, a.lng, b.lat, b.lng) AS dist
    FROM base a
    JOIN public.map_places b
      ON b.id <> a.id
      AND b.active = true
      AND b.duplicate_of IS NULL
      AND b.lat IS NOT NULL AND b.lng IS NOT NULL
    WHERE public._map_distance_meters(a.lat, a.lng, b.lat, b.lng) <= p_radius_meters
  ),
  scored AS (
    SELECT
      LEAST(a_id, b_id) AS pa,
      GREATEST(a_id, b_id) AS pb,
      dist,
      (lower(a_name) = lower(b_name)) AS name_eq,
      (a_cat IS NOT NULL AND a_cat = b_cat) AS cat_eq,
      (a_com IS NOT NULL AND a_com = b_com) AS com_eq,
      a_name, b_name
    FROM pairs
  ),
  ranked AS (
    SELECT pa, pb,
      MIN(dist) AS dist,
      bool_or(name_eq) AS name_eq,
      bool_or(cat_eq) AS cat_eq,
      bool_or(com_eq) AS com_eq
    FROM scored
    GROUP BY pa, pb
  )
  INSERT INTO public.map_place_duplicate_candidates
    (place_a_id, place_b_id, score, reason_codes, distance_meters,
     name_similarity, category_match, commune_match, status)
  SELECT
    pa, pb,
    LEAST(100,
      CASE WHEN dist <= 25 THEN 60 WHEN dist <= 75 THEN 40 ELSE 20 END
      + CASE WHEN name_eq THEN 30 ELSE 0 END
      + CASE WHEN cat_eq THEN 10 ELSE 0 END
      + CASE WHEN com_eq THEN 5 ELSE 0 END
    ) AS score,
    ARRAY_REMOVE(ARRAY[
      'nearby_coordinates',
      CASE WHEN name_eq THEN 'similar_name' END,
      CASE WHEN cat_eq THEN 'same_category' END,
      CASE WHEN com_eq THEN 'same_commune' END
    ], NULL) AS reason_codes,
    dist,
    CASE WHEN name_eq THEN 1.0 ELSE 0.0 END,
    cat_eq, com_eq,
    'open'
  FROM ranked
  ON CONFLICT DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  RETURN v_inserted;
END;
$$;

REVOKE ALL ON FUNCTION public.map_detect_place_duplicates(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.map_detect_place_duplicates(uuid, integer) TO authenticated, service_role;

-- ============ Mark duplicate (no reference moves) ============
CREATE OR REPLACE FUNCTION public.map_mark_place_duplicate(
  p_source_place_id uuid,
  p_target_place_id uuid,
  p_candidate_id uuid DEFAULT NULL,
  p_reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'admin only';
  END IF;
  IF p_source_place_id = p_target_place_id THEN
    RAISE EXCEPTION 'source and target must differ';
  END IF;

  PERFORM 1 FROM public.map_places WHERE id = p_target_place_id FOR UPDATE;
  PERFORM 1 FROM public.map_places WHERE id = p_source_place_id FOR UPDATE;

  UPDATE public.map_places
     SET verification_status = 'duplicate',
         duplicate_of = p_target_place_id,
         active = false,
         updated_at = now()
   WHERE id = p_source_place_id;

  IF p_candidate_id IS NOT NULL THEN
    UPDATE public.map_place_duplicate_candidates
       SET status = 'confirmed_duplicate',
           reviewed_by = auth.uid(),
           reviewed_at = now(),
           merge_target_place_id = p_target_place_id,
           notes = COALESCE(p_reason, notes)
     WHERE id = p_candidate_id;
  END IF;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
  VALUES (auth.uid(), 'map_mark_duplicate', 'map_place', p_source_place_id,
          jsonb_build_object(
            'target_place_id', p_target_place_id,
            'candidate_id', p_candidate_id,
            'reason', p_reason
          ));
END;
$$;

REVOKE ALL ON FUNCTION public.map_mark_place_duplicate(uuid, uuid, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.map_mark_place_duplicate(uuid, uuid, uuid, text) TO authenticated, service_role;

-- ============ Merge places (moves references) ============
CREATE OR REPLACE FUNCTION public.map_merge_places(
  p_source_place_id uuid,
  p_target_place_id uuid,
  p_candidate_id uuid DEFAULT NULL,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_source public.map_places%ROWTYPE;
  v_target public.map_places%ROWTYPE;
  v_moved_stores integer := 0;
  v_moved_reports integer := 0;
  v_new_aliases text[];
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'admin only';
  END IF;
  IF p_source_place_id = p_target_place_id THEN
    RAISE EXCEPTION 'source and target must differ';
  END IF;

  SELECT * INTO v_source FROM public.map_places WHERE id = p_source_place_id FOR UPDATE;
  SELECT * INTO v_target FROM public.map_places WHERE id = p_target_place_id FOR UPDATE;
  IF v_source.id IS NULL OR v_target.id IS NULL THEN
    RAISE EXCEPTION 'place not found';
  END IF;

  -- merge aliases: target.aliases ∪ {source.name} ∪ source.aliases
  v_new_aliases := (
    SELECT ARRAY(SELECT DISTINCT x FROM unnest(
      COALESCE(v_target.aliases, '{}') ||
      ARRAY[v_source.name] ||
      COALESCE(v_source.aliases, '{}')
    ) AS x WHERE x IS NOT NULL AND x <> '' AND lower(x) <> lower(v_target.name))
  );

  UPDATE public.map_places
     SET aliases = v_new_aliases,
         -- only fill target notes if currently empty; never overwrite
         pickup_note = COALESCE(pickup_note, v_source.pickup_note),
         entrance_note = COALESCE(entrance_note, v_source.entrance_note),
         landmark_note = COALESCE(landmark_note, v_source.landmark_note),
         operational_note = COALESCE(operational_note, v_source.operational_note),
         updated_at = now()
   WHERE id = p_target_place_id;

  -- soft-deactivate source
  UPDATE public.map_places
     SET verification_status = 'duplicate',
         duplicate_of = p_target_place_id,
         active = false,
         updated_at = now()
   WHERE id = p_source_place_id;

  -- move merchant_store references
  UPDATE public.merchant_stores
     SET map_place_id = p_target_place_id,
         updated_at = now()
   WHERE map_place_id = p_source_place_id;
  GET DIAGNOSTICS v_moved_stores = ROW_COUNT;

  -- move driver reports
  UPDATE public.map_driver_reports
     SET place_id = p_target_place_id
   WHERE place_id = p_source_place_id;
  GET DIAGNOSTICS v_moved_reports = ROW_COUNT;

  IF p_candidate_id IS NOT NULL THEN
    UPDATE public.map_place_duplicate_candidates
       SET status = 'merged',
           reviewed_by = auth.uid(),
           reviewed_at = now(),
           merge_target_place_id = p_target_place_id,
           notes = COALESCE(p_reason, notes)
     WHERE id = p_candidate_id;
  END IF;

  INSERT INTO public.audit_logs (actor_id, action, entity_type, entity_id, metadata)
  VALUES (auth.uid(), 'map_merge_places', 'map_place', p_source_place_id,
          jsonb_build_object(
            'target_place_id', p_target_place_id,
            'candidate_id', p_candidate_id,
            'reason', p_reason,
            'moved_stores', v_moved_stores,
            'moved_reports', v_moved_reports,
            'source_name', v_source.name,
            'target_name', v_target.name
          ));

  RETURN jsonb_build_object(
    'source_place_id', p_source_place_id,
    'target_place_id', p_target_place_id,
    'moved_stores', v_moved_stores,
    'moved_reports', v_moved_reports
  );
END;
$$;

REVOKE ALL ON FUNCTION public.map_merge_places(uuid, uuid, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.map_merge_places(uuid, uuid, uuid, text) TO authenticated, service_role;
