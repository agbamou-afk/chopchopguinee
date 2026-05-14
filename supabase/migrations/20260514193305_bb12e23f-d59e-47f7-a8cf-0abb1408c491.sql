
CREATE OR REPLACE FUNCTION public.ride_confirm_pickup(p_ride_id uuid, p_code text)
RETURNS public.rides
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ride public.rides;
  v_expected text;
  v_provided text;
  v_phase text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF p_code IS NULL OR length(trim(p_code)) = 0 THEN
    RAISE EXCEPTION 'Pickup code required';
  END IF;

  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id FOR UPDATE;
  IF v_ride.id IS NULL THEN RAISE EXCEPTION 'Ride not found'; END IF;

  IF v_ride.client_id <> v_uid AND NOT public.has_role(v_uid,'admin') THEN
    RAISE EXCEPTION 'Only the customer can confirm pickup';
  END IF;
  IF v_ride.driver_id IS NULL THEN
    RAISE EXCEPTION 'No driver assigned';
  END IF;
  IF v_ride.status NOT IN ('pending','in_progress') THEN
    RAISE EXCEPTION 'Ride not in pickup phase';
  END IF;

  v_phase := COALESCE(v_ride.metadata->>'phase','');
  IF v_phase <> 'arrived' THEN
    RAISE EXCEPTION 'Driver has not arrived yet';
  END IF;

  v_expected := upper(COALESCE(v_ride.metadata->>'pickup_code',''));
  v_provided := upper(trim(p_code));
  IF v_provided LIKE 'CHOP-PICKUP-%' THEN
    v_provided := substr(v_provided, length('CHOP-PICKUP-') + 1);
    IF position('-' in v_provided) > 0 THEN
      v_provided := split_part(v_provided, '-', 1);
    END IF;
  END IF;
  IF v_expected = '' OR v_provided <> v_expected THEN
    RAISE EXCEPTION 'Code de prise en charge invalide';
  END IF;

  UPDATE public.rides
     SET status = 'in_progress',
         metadata = COALESCE(metadata,'{}'::jsonb) || jsonb_build_object(
           'phase','on_trip',
           'pickup_confirmed_at', to_jsonb(now()),
           'pickup_confirmed_by','customer'
         ),
         updated_at = now()
   WHERE id = p_ride_id RETURNING * INTO v_ride;
  RETURN v_ride;
END $$;

GRANT EXECUTE ON FUNCTION public.ride_confirm_pickup(uuid, text) TO authenticated;
