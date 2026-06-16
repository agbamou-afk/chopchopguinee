
-- Map Phase 2F: Driver Location Signals + Route Observation Hooks
-- Latest-only signal table (no history v1) + secure upsert RPC.

CREATE TABLE IF NOT EXISTS public.driver_location_signals (
  driver_user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  lat double precision NOT NULL,
  lng double precision NOT NULL,
  accuracy_meters numeric,
  heading numeric,
  speed_mps numeric,
  source text NOT NULL DEFAULT 'driver_app'
    CHECK (source IN ('driver_app','mission','ride','manual')),
  status text NOT NULL DEFAULT 'online_idle'
    CHECK (status IN ('online_idle','active_ride','active_mission','offline')),
  active_ride_id uuid,
  active_mission_id uuid,
  service_zone_id uuid,
  capabilities jsonb,
  last_ping_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE ON public.driver_location_signals TO authenticated;
GRANT ALL ON public.driver_location_signals TO service_role;

ALTER TABLE public.driver_location_signals ENABLE ROW LEVEL SECURITY;

CREATE POLICY "driver_signals_self_select"
  ON public.driver_location_signals FOR SELECT TO authenticated
  USING (driver_user_id = auth.uid());

CREATE POLICY "driver_signals_admin_select"
  ON public.driver_location_signals FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

CREATE POLICY "driver_signals_service_all"
  ON public.driver_location_signals FOR ALL TO service_role
  USING (true) WITH CHECK (true);

CREATE INDEX IF NOT EXISTS idx_driver_signals_status_ping
  ON public.driver_location_signals (status, last_ping_at DESC);
CREATE INDEX IF NOT EXISTS idx_driver_signals_zone
  ON public.driver_location_signals (service_zone_id);

DROP TRIGGER IF EXISTS trg_driver_signals_updated ON public.driver_location_signals;
CREATE TRIGGER trg_driver_signals_updated
  BEFORE UPDATE ON public.driver_location_signals
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Secure upsert RPC
CREATE OR REPLACE FUNCTION public.driver_update_location_signal(
  p_lat numeric,
  p_lng numeric,
  p_accuracy_meters numeric DEFAULT NULL,
  p_heading numeric DEFAULT NULL,
  p_speed_mps numeric DEFAULT NULL,
  p_active_ride_id uuid DEFAULT NULL,
  p_active_mission_id uuid DEFAULT NULL,
  p_source text DEFAULT 'driver_app'
)
RETURNS public.driver_location_signals
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_status text := 'online_idle';
  v_zone uuid;
  v_row public.driver_location_signals;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'auth required' USING ERRCODE = '42501';
  END IF;
  IF p_lat IS NULL OR p_lng IS NULL
     OR abs(p_lat) > 90 OR abs(p_lng) > 180 THEN
    RAISE EXCEPTION 'invalid coordinates' USING ERRCODE = '22023';
  END IF;
  IF p_source NOT IN ('driver_app','mission','ride','manual') THEN
    RAISE EXCEPTION 'invalid source' USING ERRCODE = '22023';
  END IF;

  -- Verify ride/mission assignment to prevent spoofing
  IF p_active_ride_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.rides
      WHERE id = p_active_ride_id AND driver_id = v_uid
    ) THEN
      RAISE EXCEPTION 'ride not assigned to driver' USING ERRCODE = '42501';
    END IF;
    v_status := 'active_ride';
  ELSIF p_active_mission_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.missions
      WHERE id = p_active_mission_id AND courier_id = v_uid
    ) THEN
      RAISE EXCEPTION 'mission not assigned to driver' USING ERRCODE = '42501';
    END IF;
    v_status := 'active_mission';
  END IF;

  -- Best-effort zone match (active polygon containing the point)
  BEGIN
    SELECT id INTO v_zone
    FROM public.map_service_zones
    WHERE status = 'active'
      AND polygon_geojson IS NOT NULL
    LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_zone := NULL;
  END;

  INSERT INTO public.driver_location_signals AS s (
    driver_user_id, lat, lng, accuracy_meters, heading, speed_mps,
    source, status, active_ride_id, active_mission_id, service_zone_id,
    last_ping_at
  ) VALUES (
    v_uid, p_lat, p_lng, p_accuracy_meters, p_heading, p_speed_mps,
    p_source, v_status, p_active_ride_id, p_active_mission_id, v_zone,
    now()
  )
  ON CONFLICT (driver_user_id) DO UPDATE SET
    lat = EXCLUDED.lat,
    lng = EXCLUDED.lng,
    accuracy_meters = EXCLUDED.accuracy_meters,
    heading = EXCLUDED.heading,
    speed_mps = EXCLUDED.speed_mps,
    source = EXCLUDED.source,
    status = EXCLUDED.status,
    active_ride_id = EXCLUDED.active_ride_id,
    active_mission_id = EXCLUDED.active_mission_id,
    service_zone_id = EXCLUDED.service_zone_id,
    last_ping_at = now(),
    updated_at = now()
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.driver_update_location_signal(
  numeric,numeric,numeric,numeric,numeric,uuid,uuid,text
) TO authenticated;

-- Mark driver offline (clears precise coords on offline)
CREATE OR REPLACE FUNCTION public.driver_mark_offline_signal()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'auth required' USING ERRCODE='42501';
  END IF;
  UPDATE public.driver_location_signals
     SET status='offline',
         active_ride_id=NULL,
         active_mission_id=NULL,
         speed_mps=NULL,
         heading=NULL,
         last_ping_at=now(),
         updated_at=now()
   WHERE driver_user_id = auth.uid();
END;
$$;
GRANT EXECUTE ON FUNCTION public.driver_mark_offline_signal() TO authenticated;
