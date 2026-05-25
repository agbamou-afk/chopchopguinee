-- 1. Vendor public coordinates (nullable; only set when business shares a public commercial location)
ALTER TABLE public.food_restaurants
  ADD COLUMN IF NOT EXISTS latitude double precision,
  ADD COLUMN IF NOT EXISTS longitude double precision;

ALTER TABLE public.merchant_stores
  ADD COLUMN IF NOT EXISTS latitude double precision,
  ADD COLUMN IF NOT EXISTS longitude double precision;

-- 2. Location search telemetry table
CREATE TABLE IF NOT EXISTS public.location_search_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid,
  query text,
  selected_place_id text,
  selected_label text,
  selected_source text,
  district text,
  latitude double precision,
  longitude double precision,
  confidence text,
  context text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS location_search_events_user_idx
  ON public.location_search_events (user_id, created_at DESC);

ALTER TABLE public.location_search_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users insert own location search events"
  ON public.location_search_events
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users read own location search events"
  ON public.location_search_events
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Admins read all location search events"
  ON public.location_search_events
  FOR SELECT
  TO authenticated
  USING (has_role(auth.uid(), 'admin'::app_role));
