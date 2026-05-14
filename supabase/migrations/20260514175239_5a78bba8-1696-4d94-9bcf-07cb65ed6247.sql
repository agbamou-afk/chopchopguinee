
CREATE OR REPLACE FUNCTION public.demo_seed_ride_offer()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_driver uuid;
  v_client uuid;
  v_ride_id uuid;
  v_offer_id uuid;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Locate the demo driver and demo client by email (auth.users is allowed
  -- here because we're SECURITY DEFINER).
  SELECT id INTO v_driver FROM auth.users
   WHERE lower(email) = 'demo.driver@chopchop.gn' LIMIT 1;
  SELECT id INTO v_client FROM auth.users
   WHERE lower(email) = 'demo.client@chopchop.gn' LIMIT 1;

  IF v_driver IS NULL THEN
    RAISE EXCEPTION 'Demo driver account not found';
  END IF;

  -- Caller must be the demo client, demo driver, or an admin. This keeps the
  -- helper safe outside of the testing environment.
  IF v_caller <> v_driver
     AND (v_client IS NULL OR v_caller <> v_client)
     AND NOT public.is_any_admin(v_caller) THEN
    RAISE EXCEPTION 'Not authorized to seed test offers';
  END IF;

  -- Use the demo client as the ride's client when available, otherwise the
  -- caller themselves so the FK / RLS chain stays valid.
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
    now() + interval '20 seconds'
  ) RETURNING id INTO v_offer_id;

  RETURN jsonb_build_object('ride_id', v_ride_id, 'offer_id', v_offer_id, 'driver_id', v_driver);
END;
$$;

REVOKE ALL ON FUNCTION public.demo_seed_ride_offer() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.demo_seed_ride_offer() TO authenticated;
