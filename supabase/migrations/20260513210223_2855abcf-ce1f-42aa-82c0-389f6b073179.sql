CREATE OR REPLACE FUNCTION public.ride_set_phase(p_ride_id uuid, p_phase text)
RETURNS public.rides LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_ride public.rides;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF p_phase NOT IN ('approach','arrived','on_trip','at_destination') THEN
    RAISE EXCEPTION 'Invalid phase %', p_phase;
  END IF;
  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id FOR UPDATE;
  IF v_ride IS NULL THEN RAISE EXCEPTION 'Ride not found'; END IF;
  IF v_ride.driver_id <> v_uid AND v_ride.client_id <> v_uid AND NOT public.has_role(v_uid,'admin') THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  UPDATE public.rides
     SET metadata = COALESCE(metadata,'{}'::jsonb) || jsonb_build_object('phase', p_phase),
         updated_at = now()
   WHERE id = p_ride_id RETURNING * INTO v_ride;
  RETURN v_ride;
END; $$;

CREATE OR REPLACE FUNCTION public.ride_start(p_ride_id uuid)
RETURNS public.rides LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_ride public.rides;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id FOR UPDATE;
  IF v_ride IS NULL THEN RAISE EXCEPTION 'Ride not found'; END IF;
  IF v_ride.driver_id <> v_uid AND NOT public.has_role(v_uid,'admin') THEN
    RAISE EXCEPTION 'Only the assigned driver can start the trip';
  END IF;
  IF v_ride.status = 'completed' THEN RAISE EXCEPTION 'Ride already completed'; END IF;
  IF v_ride.status = 'cancelled' THEN RAISE EXCEPTION 'Ride already cancelled'; END IF;
  UPDATE public.rides
     SET status = 'in_progress',
         metadata = COALESCE(metadata,'{}'::jsonb) || jsonb_build_object('phase','on_trip','started_at', to_jsonb(now())),
         updated_at = now()
   WHERE id = p_ride_id RETURNING * INTO v_ride;
  RETURN v_ride;
END; $$;

REVOKE EXECUTE ON FUNCTION public.ride_set_phase(uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.ride_start(uuid)           FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.ride_set_phase(uuid, text) TO authenticated;
GRANT  EXECUTE ON FUNCTION public.ride_start(uuid)           TO authenticated;