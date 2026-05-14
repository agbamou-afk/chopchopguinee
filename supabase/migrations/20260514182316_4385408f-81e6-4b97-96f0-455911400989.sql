CREATE OR REPLACE FUNCTION public.demo_reset_driver()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_driver uuid;
  v_client uuid;
  v_cancelled_count integer := 0;
  v_expired_count integer := 0;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT id INTO v_driver FROM auth.users
   WHERE lower(email) = 'demo.driver@chopchop.gn' LIMIT 1;
  SELECT id INTO v_client FROM auth.users
   WHERE lower(email) = 'demo.client@chopchop.gn' LIMIT 1;

  IF v_driver IS NULL THEN
    RAISE EXCEPTION 'Demo driver account not found';
  END IF;

  IF v_caller <> v_driver
     AND (v_client IS NULL OR v_caller <> v_client)
     AND NOT public.is_any_admin(v_caller) THEN
    RAISE EXCEPTION 'Not authorized to reset demo driver';
  END IF;

  UPDATE public.rides
     SET status = 'cancelled',
         updated_at = now(),
         metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('demo_reset', true, 'reset_at', now(), 'reset_by', v_caller)
   WHERE driver_id = v_driver
     AND status NOT IN ('completed', 'cancelled');
  GET DIAGNOSTICS v_cancelled_count = ROW_COUNT;

  UPDATE public.ride_offers
     SET status = 'expired',
         responded_at = coalesce(responded_at, now())
   WHERE driver_id = v_driver
     AND status = 'pending';
  GET DIAGNOSTICS v_expired_count = ROW_COUNT;

  UPDATE public.driver_profiles
     SET presence = 'online',
         last_seen_at = now(),
         updated_at = now()
   WHERE user_id = v_driver;

  INSERT INTO public.driver_locations (user_id, lat, lng, status, zone, updated_at)
  VALUES (v_driver, 9.6412, -13.5784, 'online', 'Marché Madina', now())
  ON CONFLICT (user_id) DO UPDATE
    SET lat = excluded.lat,
        lng = excluded.lng,
        status = excluded.status,
        zone = excluded.zone,
        updated_at = now();

  RETURN jsonb_build_object(
    'driver_id', v_driver,
    'cancelled_rides', v_cancelled_count,
    'expired_offers', v_expired_count,
    'presence', 'online'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.demo_seed_ride_offer()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_driver uuid;
  v_client uuid;
  v_ride_id uuid;
  v_offer_id uuid;
  v_reset jsonb;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT id INTO v_driver FROM auth.users
   WHERE lower(email) = 'demo.driver@chopchop.gn' LIMIT 1;
  SELECT id INTO v_client FROM auth.users
   WHERE lower(email) = 'demo.client@chopchop.gn' LIMIT 1;

  IF v_driver IS NULL THEN
    RAISE EXCEPTION 'Demo driver account not found';
  END IF;

  IF v_caller <> v_driver
     AND (v_client IS NULL OR v_caller <> v_client)
     AND NOT public.is_any_admin(v_caller) THEN
    RAISE EXCEPTION 'Not authorized to seed test offers';
  END IF;

  v_reset := public.demo_reset_driver();

  IF v_client IS NULL THEN v_client := v_caller; END IF;

  INSERT INTO public.rides (
    client_id, driver_id, mode, status,
    pickup_lat, pickup_lng, dest_lat, dest_lng,
    fare_gnf, metadata
  ) VALUES (
    v_client, NULL, 'moto', 'pending',
    9.6412, -13.5784, 9.5731, -13.6122,
    25000, jsonb_build_object('demo', true, 'seeded_by', v_caller)
  ) RETURNING id INTO v_ride_id;

  INSERT INTO public.ride_offers (
    ride_id, driver_id, status,
    estimated_fare_gnf, estimated_earning_gnf,
    pickup_zone, destination_zone, distance_to_pickup_m,
    expires_at
  ) VALUES (
    v_ride_id, v_driver, 'pending',
    25000, 21250,
    'Marché Madina', 'Aéroport Conakry', 1500,
    now() + interval '30 seconds'
  ) RETURNING id INTO v_offer_id;

  RETURN jsonb_build_object(
    'ride_id', v_ride_id,
    'offer_id', v_offer_id,
    'driver_id', v_driver,
    'reset', v_reset
  );
END;
$$;