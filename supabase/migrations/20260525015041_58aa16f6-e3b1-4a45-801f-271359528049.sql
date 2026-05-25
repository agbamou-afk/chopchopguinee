-- navigation_events: telemetry for driver/customer navigation actions
CREATE TABLE public.navigation_events (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID,
  ride_id UUID,
  mission_id UUID,
  event_name TEXT NOT NULL,
  surface TEXT,
  provider TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_navigation_events_user ON public.navigation_events(user_id);
CREATE INDEX idx_navigation_events_ride ON public.navigation_events(ride_id);
CREATE INDEX idx_navigation_events_created ON public.navigation_events(created_at DESC);

ALTER TABLE public.navigation_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Insert own navigation events"
ON public.navigation_events
FOR INSERT
TO anon, authenticated
WITH CHECK (
  ((auth.uid() IS NULL) AND (user_id IS NULL))
  OR ((auth.uid() IS NOT NULL) AND (user_id = auth.uid()))
);

CREATE POLICY "Users read own navigation events"
ON public.navigation_events
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Admins read all navigation events"
ON public.navigation_events
FOR SELECT
TO authenticated
USING (is_any_admin(auth.uid()));