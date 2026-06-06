
CREATE OR REPLACE FUNCTION public.get_nearby_available_drivers(
  p_lat double precision,
  p_lng double precision,
  p_radius_m integer DEFAULT 3000,
  p_vehicle_type text DEFAULT NULL,
  p_limit integer DEFAULT 25
)
RETURNS TABLE(
  driver_ref text,
  approx_lat double precision,
  approx_lng double precision,
  distance_m integer,
  vehicle_type text,
  heading double precision,
  last_seen_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH origin AS (
    SELECT p_lat::double precision AS lat, p_lng::double precision AS lng
  ),
  candidates AS (
    SELECT
      dl.user_id,
      dl.lat,
      dl.lng,
      dl.heading,
      dl.updated_at,
      dp.vehicle_type::text AS vehicle_type,
      (2 * 6371000 * asin(sqrt(
        power(sin(radians((dl.lat - o.lat)/2)), 2) +
        cos(radians(o.lat)) * cos(radians(dl.lat)) *
        power(sin(radians((dl.lng - o.lng)/2)), 2)
      )))::int AS distance_m
    FROM public.driver_locations dl
    JOIN public.driver_profiles dp ON dp.user_id = dl.user_id
    CROSS JOIN origin o
    WHERE dp.status = 'approved'
      AND dl.status = 'online'
      AND dl.updated_at > now() - interval '120 seconds'
      AND (p_vehicle_type IS NULL OR dp.vehicle_type::text = p_vehicle_type)
  )
  SELECT
    md5(user_id::text || date_trunc('hour', now())::text) AS driver_ref,
    round(lat::numeric, 3)::double precision AS approx_lat,
    round(lng::numeric, 3)::double precision AS approx_lng,
    distance_m,
    vehicle_type,
    heading,
    updated_at AS last_seen_at
  FROM candidates
  WHERE distance_m <= p_radius_m
  ORDER BY distance_m ASC
  LIMIT GREATEST(1, LEAST(p_limit, 50));
$$;

REVOKE ALL ON FUNCTION public.get_nearby_available_drivers(double precision, double precision, integer, text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_nearby_available_drivers(double precision, double precision, integer, text, integer) TO authenticated;
