
-- Helper: resolve the demo driver's user_id by email
CREATE OR REPLACE FUNCTION public.get_demo_driver()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT id FROM auth.users WHERE lower(email) = 'demo.driver@chopchop.gn' LIMIT 1;
$$;

-- Link a freshly-created ride to the demo driver by inserting a real ride_offer.
-- Allowed for the demo client account, or for any authenticated owner who passes
-- the explicit ?demo=linked flag (we still verify ownership of the ride).
CREATE OR REPLACE FUNCTION public.demo_link_ride(p_ride_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_caller_email text;
  v_driver uuid;
  v_ride public.rides;
  v_offer_id uuid;
  v_earning bigint;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT lower(email) INTO v_caller_email FROM auth.users WHERE id = v_uid;

  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id FOR UPDATE;
  IF v_ride IS NULL THEN
    RAISE EXCEPTION 'Ride % not found', p_ride_id;
  END IF;

  -- Only the ride owner may link.
  IF v_ride.client_id <> v_uid THEN
    RAISE EXCEPTION 'Not authorized to link this ride';
  END IF;

  v_driver := public.get_demo_driver();
  IF v_driver IS NULL THEN
    RAISE NOTICE 'Demo driver not provisioned; skipping link';
    RETURN NULL;
  END IF;

  -- Don't offer to the driver if they're the same as the client.
  IF v_driver = v_uid THEN
    RETURN NULL;
  END IF;

  -- Expire any other pending offers for the demo driver to keep the queue clean.
  UPDATE public.ride_offers
  SET status = 'expired', responded_at = now(), decline_reason = 'demo_relink'
  WHERE driver_id = v_driver
    AND status = 'pending'
    AND ride_id <> p_ride_id;

  -- Skip if an offer for this exact ride+driver already exists and is pending.
  SELECT id INTO v_offer_id
  FROM public.ride_offers
  WHERE ride_id = p_ride_id AND driver_id = v_driver AND status = 'pending'
  LIMIT 1;

  IF v_offer_id IS NOT NULL THEN
    RETURN v_offer_id;
  END IF;

  v_earning := GREATEST(((COALESCE(v_ride.fare_gnf, 0)::numeric) * 0.85)::bigint, 0);

  INSERT INTO public.ride_offers (
    ride_id, driver_id, status,
    estimated_fare_gnf, estimated_earning_gnf,
    pickup_zone, destination_zone,
    distance_to_pickup_m, expires_at
  ) VALUES (
    p_ride_id, v_driver, 'pending',
    v_ride.fare_gnf, v_earning,
    'Course CHOP CHOP', 'Destination client',
    1200, now() + interval '90 seconds'
  )
  RETURNING id INTO v_offer_id;

  -- Tag the ride for downstream guards / admin readability.
  UPDATE public.rides
  SET metadata = COALESCE(metadata, '{}'::jsonb) ||
                 jsonb_build_object('linked_demo', true, 'linked_at', now())
  WHERE id = p_ride_id;

  RETURN v_offer_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_demo_driver() TO authenticated;
GRANT EXECUTE ON FUNCTION public.demo_link_ride(uuid) TO authenticated;
