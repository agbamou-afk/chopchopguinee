
CREATE OR REPLACE FUNCTION public.ride_set_phase(p_ride_id uuid, p_phase text)
 RETURNS rides
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_ride public.rides;
  v_code text;
  v_meta jsonb;
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

  v_meta := COALESCE(v_ride.metadata,'{}'::jsonb) || jsonb_build_object('phase', p_phase);

  IF p_phase = 'arrived' AND COALESCE(v_meta->>'pickup_code','') = '' THEN
    -- 6-char alphanumeric code derived from a random UUID (no pgcrypto dependency)
    v_code := upper(substr(translate(replace(gen_random_uuid()::text,'-',''),'oil01',''),1,6));
    v_meta := v_meta || jsonb_build_object('pickup_code', v_code, 'arrived_at', to_jsonb(now()));
  END IF;

  UPDATE public.rides
     SET metadata = v_meta,
         updated_at = now()
   WHERE id = p_ride_id RETURNING * INTO v_ride;
  RETURN v_ride;
END; $function$;
