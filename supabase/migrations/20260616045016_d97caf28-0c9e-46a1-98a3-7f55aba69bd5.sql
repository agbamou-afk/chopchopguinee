
CREATE TABLE IF NOT EXISTS public.map_route_observations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_module text NOT NULL CHECK (source_module IN ('ride','mission','repas','marche','manual')),
  source_id uuid NULL,
  driver_user_id uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  origin_lat double precision NOT NULL,
  origin_lng double precision NOT NULL,
  destination_lat double precision NOT NULL,
  destination_lng double precision NOT NULL,
  observed_distance_meters integer NULL,
  observed_duration_seconds integer NULL,
  observed_polyline_geojson jsonb NULL,
  simplified_polyline_geojson jsonb NULL,
  provider_used text NULL,
  fallback_used boolean NOT NULL DEFAULT false,
  confidence_score integer NOT NULL DEFAULT 35,
  verification_status text NOT NULL DEFAULT 'submitted'
    CHECK (verification_status IN ('submitted','field_checked','admin_verified','trusted','needs_review')),
  status text NOT NULL DEFAULT 'recorded'
    CHECK (status IN ('recorded','reviewed','rejected','promoted')),
  notes text NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_map_route_obs_module ON public.map_route_observations(source_module, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_map_route_obs_driver ON public.map_route_observations(driver_user_id);
CREATE INDEX IF NOT EXISTS idx_map_route_obs_status ON public.map_route_observations(status, verification_status);

GRANT SELECT, INSERT, UPDATE ON public.map_route_observations TO authenticated;
GRANT ALL ON public.map_route_observations TO service_role;

ALTER TABLE public.map_route_observations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admins read route observations"
  ON public.map_route_observations FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "admins write route observations"
  ON public.map_route_observations FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "drivers insert own route observations"
  ON public.map_route_observations FOR INSERT TO authenticated
  WITH CHECK (
    driver_user_id = auth.uid()
    OR public.has_role(auth.uid(), 'admin')
  );

CREATE TRIGGER trg_map_route_obs_updated
  BEFORE UPDATE ON public.map_route_observations
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
