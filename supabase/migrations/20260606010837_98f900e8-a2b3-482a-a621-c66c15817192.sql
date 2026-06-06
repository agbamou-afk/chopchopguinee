
-- ============ driver_route_traces ============
CREATE TABLE IF NOT EXISTS public.driver_route_traces (
  id BIGSERIAL PRIMARY KEY,
  ride_id UUID REFERENCES public.rides(id) ON DELETE CASCADE,
  mission_id UUID,
  driver_id UUID NOT NULL,
  phase TEXT NOT NULL CHECK (phase IN ('to_pickup','to_destination')),
  lat NUMERIC(10,6) NOT NULL,
  lng NUMERIC(10,6) NOT NULL,
  accuracy_m NUMERIC(8,2),
  heading NUMERIC(6,2),
  speed_mps NUMERIC(7,2),
  planned_route_hash TEXT,
  provider TEXT,
  observed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_drt_ride ON public.driver_route_traces(ride_id, observed_at);
CREATE INDEX IF NOT EXISTS idx_drt_driver_time ON public.driver_route_traces(driver_id, observed_at DESC);

GRANT SELECT, INSERT ON public.driver_route_traces TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.driver_route_traces_id_seq TO authenticated;
GRANT ALL ON public.driver_route_traces TO service_role;
GRANT ALL ON SEQUENCE public.driver_route_traces_id_seq TO service_role;

ALTER TABLE public.driver_route_traces ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Drivers insert own trace for active ride"
  ON public.driver_route_traces FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = driver_id
    AND ride_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.rides r
      WHERE r.id = ride_id
        AND r.driver_id = auth.uid()
        AND r.status IN ('pending','in_progress')
    )
  );

CREATE POLICY "Drivers read own traces"
  ON public.driver_route_traces FOR SELECT TO authenticated
  USING (auth.uid() = driver_id);

CREATE POLICY "Admins read all traces"
  ON public.driver_route_traces FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

-- ============ ride_route_summaries ============
CREATE TABLE IF NOT EXISTS public.ride_route_summaries (
  ride_id UUID PRIMARY KEY REFERENCES public.rides(id) ON DELETE CASCADE,
  driver_id UUID,
  planned_route_distance_m INTEGER,
  planned_route_duration_s INTEGER,
  actual_route_distance_m INTEGER,
  actual_route_duration_s INTEGER,
  deviation_count INTEGER NOT NULL DEFAULT 0,
  average_speed_kmh NUMERIC(6,2),
  start_district TEXT,
  end_district TEXT,
  time_window TEXT,
  route_confidence NUMERIC(4,3),
  point_count INTEGER NOT NULL DEFAULT 0,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_rrs_driver ON public.ride_route_summaries(driver_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_rrs_districts ON public.ride_route_summaries(start_district, end_district);

GRANT SELECT, INSERT, UPDATE ON public.ride_route_summaries TO authenticated;
GRANT ALL ON public.ride_route_summaries TO service_role;

ALTER TABLE public.ride_route_summaries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Drivers read own ride summaries"
  ON public.ride_route_summaries FOR SELECT TO authenticated
  USING (auth.uid() = driver_id);

CREATE POLICY "Admins read all ride summaries"
  ON public.ride_route_summaries FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

-- Drivers may upsert summary for a ride they own that is pending/in_progress/completed.
CREATE POLICY "Drivers insert own ride summary"
  ON public.ride_route_summaries FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = driver_id
    AND EXISTS (
      SELECT 1 FROM public.rides r
      WHERE r.id = ride_id AND r.driver_id = auth.uid()
    )
  );

CREATE POLICY "Drivers update own ride summary"
  ON public.ride_route_summaries FOR UPDATE TO authenticated
  USING (auth.uid() = driver_id)
  WITH CHECK (auth.uid() = driver_id);

-- ============ learned_route_segments (aggregate) ============
CREATE TABLE IF NOT EXISTS public.learned_route_segments (
  id BIGSERIAL PRIMARY KEY,
  origin_geohash TEXT NOT NULL,
  destination_geohash TEXT NOT NULL,
  segment_hash TEXT,
  observed_count INTEGER NOT NULL DEFAULT 0,
  median_duration_s INTEGER,
  median_distance_m INTEGER,
  confidence_score NUMERIC(4,3) NOT NULL DEFAULT 0,
  notes TEXT,
  source TEXT NOT NULL DEFAULT 'learning_v0',
  last_observed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (origin_geohash, destination_geohash, segment_hash)
);

CREATE INDEX IF NOT EXISTS idx_lrs_pair ON public.learned_route_segments(origin_geohash, destination_geohash);

GRANT SELECT ON public.learned_route_segments TO authenticated;
GRANT ALL ON public.learned_route_segments TO service_role;

ALTER TABLE public.learned_route_segments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins read learned segments"
  ON public.learned_route_segments FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

-- update_updated_at triggers
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END $$;

DROP TRIGGER IF EXISTS trg_rrs_updated_at ON public.ride_route_summaries;
CREATE TRIGGER trg_rrs_updated_at BEFORE UPDATE ON public.ride_route_summaries
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_lrs_updated_at ON public.learned_route_segments;
CREATE TRIGGER trg_lrs_updated_at BEFORE UPDATE ON public.learned_route_segments
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
