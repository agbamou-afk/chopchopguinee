CREATE OR REPLACE FUNCTION public.debug_create_offer_for_current_driver()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_email text;
  v_ride_id uuid;
  v_offer public.ride_offers;
  v_cancelled_count integer := 0;
  v_expired_count integer := 0;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT lower(email) INTO v_email FROM auth.users WHERE id = v_caller LIMIT 1;

  IF NOT EXISTS (SELECT 1 FROM public.driver_profiles WHERE user_id = v_caller) THEN
    RAISE EXCEPTION 'Current user is not a driver';
  END IF;

  IF v_email IS DISTINCT FROM 'demo.driver@chopchop.gn' AND NOT public.is_any_admin(v_caller) THEN
    RAISE EXCEPTION 'Only the demo driver or admins can create debug offers';
  END IF;

  UPDATE public.rides
     SET status = 'cancelled',
         updated_at = now(),
         metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('debug_reset', true, 'reset_at', now(), 'reset_by', v_caller)
   WHERE driver_id = v_caller
     AND status NOT IN ('completed', 'cancelled');
  GET DIAGNOSTICS v_cancelled_count = ROW_COUNT;

  UPDATE public.ride_offers
     SET status = 'expired',
         responded_at = coalesce(responded_at, now())
   WHERE driver_id = v_caller
     AND status = 'pending';
  GET DIAGNOSTICS v_expired_count = ROW_COUNT;

  UPDATE public.driver_profiles
     SET presence = 'online',
         last_seen_at = now(),
         updated_at = now()
   WHERE user_id = v_caller;

  INSERT INTO public.driver_locations (user_id, lat, lng, status, zone, updated_at)
  VALUES (v_caller, 9.6412, -13.5784, 'online', 'Marché Madina', now())
  ON CONFLICT (user_id) DO UPDATE
    SET lat = excluded.lat,
        lng = excluded.lng,
        status = excluded.status,
        zone = excluded.zone,
        updated_at = now();

  INSERT INTO public.rides (
    client_id, driver_id, mode, status,
    pickup_lat, pickup_lng, dest_lat, dest_lng,
    fare_gnf, metadata
  ) VALUES (
    v_caller, NULL, 'moto', 'pending',
    9.6412, -13.5784, 9.5731, -13.6122,
    25000, jsonb_build_object('debug_offer', true, 'created_by', v_caller)
  ) RETURNING id INTO v_ride_id;

  SELECT * INTO v_offer
    FROM public.ride_offers
   WHERE ride_id = v_ride_id
     AND driver_id = v_caller
   ORDER BY sent_at DESC
   LIMIT 1;

  IF v_offer.id IS NULL THEN
    INSERT INTO public.ride_offers (
      ride_id, driver_id, status,
      estimated_fare_gnf, estimated_earning_gnf,
      pickup_zone, destination_zone, distance_to_pickup_m,
      expires_at
    ) VALUES (
      v_ride_id, v_caller, 'pending',
      25000, 21250,
      'Marché Madina', 'Aéroport Conakry', 1500,
      now() + interval '60 seconds'
    ) RETURNING * INTO v_offer;
  ELSE
    UPDATE public.ride_offers
       SET status = 'pending',
           estimated_fare_gnf = 25000,
           estimated_earning_gnf = 21250,
           pickup_zone = 'Marché Madina',
           destination_zone = 'Aéroport Conakry',
           distance_to_pickup_m = 1500,
           expires_at = now() + interval '60 seconds',
           responded_at = NULL
     WHERE id = v_offer.id
     RETURNING * INTO v_offer;
  END IF;

  RETURN jsonb_build_object(
    'ride_id', v_ride_id,
    'offer_id', v_offer.id,
    'driver_id', v_caller,
    'cancelled_rides', v_cancelled_count,
    'expired_offers', v_expired_count,
    'offer', to_jsonb(v_offer)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.debug_create_offer_for_current_driver() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.debug_create_offer_for_current_driver() TO authenticated;