
-- Route Learning v1 schema extensions
ALTER TABLE public.ride_route_summaries
  ADD COLUMN IF NOT EXISTS phase TEXT,
  ADD COLUMN IF NOT EXISTS day_type TEXT,
  ADD COLUMN IF NOT EXISTS hour_bucket SMALLINT,
  ADD COLUMN IF NOT EXISTS provider TEXT;

ALTER TABLE public.learned_route_segments
  ADD COLUMN IF NOT EXISTS phase TEXT,
  ADD COLUMN IF NOT EXISTS time_window TEXT,
  ADD COLUMN IF NOT EXISTS day_type TEXT,
  ADD COLUMN IF NOT EXISTS origin_district TEXT,
  ADD COLUMN IF NOT EXISTS destination_district TEXT,
  ADD COLUMN IF NOT EXISTS unique_driver_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS median_speed_kmh NUMERIC(6,2),
  ADD COLUMN IF NOT EXISTS provider_median_duration_s INTEGER,
  ADD COLUMN IF NOT EXISTS provider_median_distance_m INTEGER,
  ADD COLUMN IF NOT EXISTS average_time_saved_s INTEGER,
  ADD COLUMN IF NOT EXISTS average_distance_delta_m INTEGER,
  ADD COLUMN IF NOT EXISTS deviation_frequency NUMERIC(5,3),
  ADD COLUMN IF NOT EXISTS first_observed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'collecting',
  ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS reviewed_by UUID;

-- New v1 grouping uniqueness (keeps legacy unique index intact)
CREATE UNIQUE INDEX IF NOT EXISTS uq_lrs_v1_group
  ON public.learned_route_segments(origin_district, destination_district, phase, time_window, day_type)
  WHERE origin_district IS NOT NULL AND destination_district IS NOT NULL AND phase IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_lrs_status ON public.learned_route_segments(status, last_observed_at DESC);

-- Admin can update learned segments (review / mark rejected)
DROP POLICY IF EXISTS "Admins update learned segments" ON public.learned_route_segments;
CREATE POLICY "Admins update learned segments"
  ON public.learned_route_segments FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

-- ============ Analysis function (admin-only) ============
CREATE OR REPLACE FUNCTION public.analyze_route_learning_v1(p_window_days INTEGER DEFAULT 30)
RETURNS TABLE(processed_summaries INTEGER, upserted_segments INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_upserted INTEGER := 0;
  v_processed INTEGER := 0;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  WITH src AS (
    SELECT
      COALESCE(NULLIF(start_district,''), 'unknown') AS od,
      COALESCE(NULLIF(end_district,''),   'unknown') AS dd,
      COALESCE(NULLIF(phase,''),          'overall') AS ph,
      COALESCE(NULLIF(time_window,''),
        CASE
          WHEN EXTRACT(HOUR FROM created_at) BETWEEN 6  AND 10 THEN 'morning'
          WHEN EXTRACT(HOUR FROM created_at) BETWEEN 11 AND 14 THEN 'midday'
          WHEN EXTRACT(HOUR FROM created_at) BETWEEN 15 AND 19 THEN 'evening'
          ELSE 'night'
        END) AS tw,
      COALESCE(NULLIF(day_type,''),
        CASE WHEN EXTRACT(ISODOW FROM created_at) >= 6 THEN 'weekend' ELSE 'weekday' END) AS dt,
      driver_id,
      planned_route_duration_s AS pdur,
      planned_route_distance_m AS pdist,
      actual_route_duration_s  AS adur,
      actual_route_distance_m  AS adist,
      deviation_count,
      average_speed_kmh,
      created_at
    FROM public.ride_route_summaries
    WHERE created_at > now() - (p_window_days || ' days')::interval
      AND actual_route_duration_s IS NOT NULL
  ),
  agg AS (
    SELECT
      od, dd, ph, tw, dt,
      COUNT(*)::int                                                          AS obs_count,
      COUNT(DISTINCT driver_id)::int                                         AS uniq_drivers,
      percentile_cont(0.5) WITHIN GROUP (ORDER BY adur)::int                 AS med_dur,
      percentile_cont(0.5) WITHIN GROUP (ORDER BY adist)::int                AS med_dist,
      percentile_cont(0.5) WITHIN GROUP (ORDER BY average_speed_kmh)         AS med_kmh,
      percentile_cont(0.5) WITHIN GROUP (ORDER BY pdur)::int                 AS prov_med_dur,
      percentile_cont(0.5) WITHIN GROUP (ORDER BY pdist)::int                AS prov_med_dist,
      AVG(GREATEST(COALESCE(pdur,adur) - adur, 0))::int                      AS avg_saved,
      AVG(COALESCE(adist,0) - COALESCE(pdist,0))::int                        AS avg_dist_delta,
      AVG(CASE WHEN deviation_count > 0 THEN 1.0 ELSE 0.0 END)::numeric(5,3) AS dev_freq,
      MIN(created_at)                                                        AS first_obs,
      MAX(created_at)                                                        AS last_obs
    FROM src
    GROUP BY od, dd, ph, tw, dt
  ),
  ups AS (
    INSERT INTO public.learned_route_segments (
      origin_geohash, destination_geohash, origin_district, destination_district,
      phase, time_window, day_type, observed_count, unique_driver_count,
      median_duration_s, median_distance_m, median_speed_kmh,
      provider_median_duration_s, provider_median_distance_m,
      average_time_saved_s, average_distance_delta_m, deviation_frequency,
      confidence_score, status, source, first_observed_at, last_observed_at, updated_at
    )
    SELECT
      od, dd, od, dd, ph, tw, dt,
      obs_count, uniq_drivers,
      med_dur, med_dist, med_kmh,
      prov_med_dur, prov_med_dist,
      avg_saved, avg_dist_delta, dev_freq,
      LEAST(1.0,
        (LEAST(obs_count,10)::numeric  / 10.0) * 0.6 +
        (LEAST(uniq_drivers,3)::numeric / 3.0)  * 0.4
      )::numeric(4,3),
      CASE
        WHEN obs_count >= 10 AND uniq_drivers >= 3 THEN 'trusted'
        WHEN obs_count >= 3  AND uniq_drivers >= 2 THEN 'candidate'
        ELSE 'collecting'
      END,
      'learning_v1', first_obs, last_obs, now()
    FROM agg
    ON CONFLICT (origin_district, destination_district, phase, time_window, day_type)
    WHERE origin_district IS NOT NULL AND destination_district IS NOT NULL AND phase IS NOT NULL
    DO UPDATE SET
      observed_count             = EXCLUDED.observed_count,
      unique_driver_count        = EXCLUDED.unique_driver_count,
      median_duration_s          = EXCLUDED.median_duration_s,
      median_distance_m          = EXCLUDED.median_distance_m,
      median_speed_kmh           = EXCLUDED.median_speed_kmh,
      provider_median_duration_s = EXCLUDED.provider_median_duration_s,
      provider_median_distance_m = EXCLUDED.provider_median_distance_m,
      average_time_saved_s       = EXCLUDED.average_time_saved_s,
      average_distance_delta_m   = EXCLUDED.average_distance_delta_m,
      deviation_frequency        = EXCLUDED.deviation_frequency,
      confidence_score           = EXCLUDED.confidence_score,
      status = CASE
        WHEN public.learned_route_segments.status = 'rejected' THEN 'rejected'
        ELSE EXCLUDED.status
      END,
      last_observed_at = EXCLUDED.last_observed_at,
      source = 'learning_v1',
      updated_at = now()
    RETURNING 1
  )
  SELECT COUNT(*)::int INTO v_upserted FROM ups;

  SELECT COUNT(*)::int INTO v_processed
  FROM public.ride_route_summaries
  WHERE created_at > now() - (p_window_days || ' days')::interval;

  RETURN QUERY SELECT v_processed, v_upserted;
END;
$$;

REVOKE ALL ON FUNCTION public.analyze_route_learning_v1(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.analyze_route_learning_v1(INTEGER) TO authenticated;

-- ============ Admin review action ============
CREATE OR REPLACE FUNCTION public.review_learned_route_segment(
  p_id BIGINT, p_status TEXT, p_notes TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN RAISE EXCEPTION 'forbidden'; END IF;
  IF p_status NOT IN ('collecting','candidate','trusted','rejected') THEN
    RAISE EXCEPTION 'invalid status %', p_status;
  END IF;
  UPDATE public.learned_route_segments
     SET status = p_status,
         notes = COALESCE(p_notes, notes),
         reviewed_at = now(),
         reviewed_by = auth.uid(),
         updated_at = now()
   WHERE id = p_id;
  RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION public.review_learned_route_segment(BIGINT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.review_learned_route_segment(BIGINT, TEXT, TEXT) TO authenticated;
