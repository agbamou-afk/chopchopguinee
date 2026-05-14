-- Harden demo helpers: also clean up orphan demo rides (driver_id NULL)
-- created by previous demo seeds for this caller, and dedupe pending offers.

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
  v_orphan_count integer := 0;
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

  -- Cancel anything still attached to the demo driver
  UPDATE public.rides
     SET status = 'cancelled',
         updated_at = now(),
         metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('demo_reset', true, 'reset_at', now(), 'reset_by', v_caller)
   WHERE driver_id = v_driver
     AND status NOT IN ('completed', 'cancelled');
  GET DIAGNOSTICS v_cancelled_count = ROW_COUNT;

  -- Cancel orphan demo rides (driver_id NULL) for either demo account.
  -- These are pending rows seeded for prior runs that never matched.
  UPDATE public.rides
     SET status = 'cancelled',
         updated_at = now(),
         metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('demo_reset_orphan', true, 'reset_at', now(), 'reset_by', v_caller)
   WHERE driver_id IS NULL
     AND status = 'pending'
     AND (
       client_id = v_driver
       OR (v_client IS NOT NULL AND client_id = v_client)
       OR coalesce(metadata->>'debug_offer','') = 'true'
       OR coalesce(metadata->>'demo','') = 'true'
     );
  GET DIAGNOSTICS v_orphan_count = ROW_COUNT;

  -- Expire any pending offers for the demo driver
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
    'orphan_rides_cancelled', v_orphan_count,
    'expired_offers', v_expired_count,
    'presence', 'online'
  );
END;
$$;

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
  v_offer_id uuid;
  v_offer public.ride_offers;
  v_cancelled_count integer := 0;
  v_orphan_count integer := 0;
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

  -- Cancel anything attached to this driver
  UPDATE public.rides
     SET status = 'cancelled',
         updated_at = now(),
         metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('debug_reset', true, 'reset_at', now(), 'reset_by', v_caller)
   WHERE driver_id = v_caller
     AND status NOT IN ('completed', 'cancelled');
  GET DIAGNOSTICS v_cancelled_count = ROW_COUNT;

  -- Cancel orphan demo rides for this caller (no driver assigned yet)
  UPDATE public.rides
     SET status = 'cancelled',
         updated_at = now(),
         metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('debug_reset_orphan', true, 'reset_at', now(), 'reset_by', v_caller)
   WHERE driver_id IS NULL
     AND status = 'pending'
     AND (client_id = v_caller
          OR coalesce(metadata->>'debug_offer','') = 'true'
          OR coalesce(metadata->>'demo','') = 'true');
  GET DIAGNOSTICS v_orphan_count = ROW_COUNT;

  -- Expire pending offers for this driver to prevent stacked popups
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

  v_offer_id := v_offer.id;

  RETURN jsonb_build_object(
    'ride_id', v_ride_id,
    'offer_id', v_offer_id,
    'driver_id', v_caller,
    'cancelled_rides', v_cancelled_count,
    'orphan_rides_cancelled', v_orphan_count,
    'expired_offers', v_expired_count,
    'offer', to_jsonb(v_offer)
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.debug_create_offer_for_current_driver() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.debug_create_offer_for_current_driver() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.demo_reset_driver() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.demo_reset_driver() TO authenticated;