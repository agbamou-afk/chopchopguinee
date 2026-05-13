
-- driver_locations
CREATE TABLE public.driver_locations (
  user_id uuid PRIMARY KEY,
  lat double precision NOT NULL,
  lng double precision NOT NULL,
  heading double precision,
  speed double precision,
  status text NOT NULL DEFAULT 'online',
  zone text,
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX driver_locations_status_idx ON public.driver_locations(status);
CREATE INDEX driver_locations_zone_idx ON public.driver_locations(zone);
ALTER TABLE public.driver_locations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Drivers upsert own location"
  ON public.driver_locations FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Drivers update own location"
  ON public.driver_locations FOR UPDATE TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Drivers read own location"
  ON public.driver_locations FOR SELECT TO authenticated
  USING (auth.uid() = user_id);
CREATE POLICY "Admins read all driver locations"
  ON public.driver_locations FOR SELECT TO authenticated
  USING (public.is_any_admin(auth.uid()));
CREATE POLICY "Clients read assigned driver location"
  ON public.driver_locations FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.rides r
    WHERE r.driver_id = driver_locations.user_id
      AND r.client_id = auth.uid()
      AND r.status IN ('pending','in_progress')
  ));

ALTER PUBLICATION supabase_realtime ADD TABLE public.driver_locations;
ALTER TABLE public.driver_locations REPLICA IDENTITY FULL;

-- maps_request_log
CREATE TABLE public.maps_request_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid,
  provider text NOT NULL,
  action text NOT NULL,
  input jsonb NOT NULL DEFAULT '{}'::jsonb,
  output_summary jsonb,
  status text NOT NULL DEFAULT 'ok',
  error_message text,
  latency_ms integer,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX maps_request_log_user_idx ON public.maps_request_log(user_id, created_at DESC);
ALTER TABLE public.maps_request_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins read maps log"
  ON public.maps_request_log FOR SELECT TO authenticated
  USING (public.is_any_admin(auth.uid()));

-- maps_rate_limits
CREATE TABLE public.maps_rate_limits (
  user_id uuid NOT NULL,
  window_kind text NOT NULL,
  window_start timestamptz NOT NULL,
  count integer NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, window_kind, window_start)
);
ALTER TABLE public.maps_rate_limits ENABLE ROW LEVEL SECURITY;

-- map_provider_settings (single-row pattern)
CREATE TABLE public.map_provider_settings (
  id integer PRIMARY KEY DEFAULT 1,
  routing_provider text NOT NULL DEFAULT 'google',
  style_url text NOT NULL DEFAULT 'mapbox://styles/mapbox/light-v11',
  default_lat double precision NOT NULL DEFAULT 9.6412,
  default_lng double precision NOT NULL DEFAULT -13.5784,
  default_zoom double precision NOT NULL DEFAULT 12,
  flags jsonb NOT NULL DEFAULT '{"heatmap":false,"surge":false,"clustering":true}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT map_provider_settings_singleton CHECK (id = 1)
);
ALTER TABLE public.map_provider_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone read map settings"
  ON public.map_provider_settings FOR SELECT TO anon, authenticated
  USING (true);
CREATE POLICY "Admins manage map settings"
  ON public.map_provider_settings FOR ALL TO authenticated
  USING (public.is_any_admin(auth.uid()))
  WITH CHECK (public.is_any_admin(auth.uid()));

INSERT INTO public.map_provider_settings (id) VALUES (1) ON CONFLICT DO NOTHING;
