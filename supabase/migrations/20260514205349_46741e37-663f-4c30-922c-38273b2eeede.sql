CREATE OR REPLACE FUNCTION public.demo_link_ride(p_ride_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_caller_email text;
  v_driver uuid;
  v_ride rides%ROWTYPE;
  v_offer_id uuid;
  v_expires_at timestamptz := now() + interval '600 seconds';
  v_fare bigint;
  v_earning bigint;
BEGIN
  IF v_caller IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT email INTO v_caller_email FROM auth.users WHERE id = v_caller;

  SELECT * INTO v_ride FROM rides WHERE id = p_ride_id;
  IF v_ride.id IS NULL OR v_ride.client_id <> v_caller THEN
    RETURN NULL;
  END IF;

  IF lower(coalesce(v_caller_email, '')) <> 'demo.client@chopchop.gn' THEN
    RETURN NULL;
  END IF;

  v_driver := public.get_demo_driver();
  IF v_driver IS NULL OR v_driver = v_caller THEN
    RETURN NULL;
  END IF;

  -- Expire any other pending offers for the demo driver to keep the queue clean.
  UPDATE ride_offers
     SET status = 'expired', responded_at = now()
   WHERE driver_id = v_driver
     AND status = 'pending'
     AND ride_id <> p_ride_id;

  v_fare := coalesce(v_ride.fare_gnf, 15000);
  v_earning := (v_fare * 85) / 100;

  INSERT INTO ride_offers (
    ride_id, driver_id, status, expires_at,
    pickup_zone, destination_zone,
    estimated_fare_gnf, estimated_earning_gnf
  ) VALUES (
    p_ride_id, v_driver, 'pending', v_expires_at,
    'Course CHOP CHOP', 'Destination client',
    v_fare, v_earning
  )
  RETURNING id INTO v_offer_id;

  UPDATE rides
     SET metadata = jsonb_set(
                      jsonb_set(
                        jsonb_set(
                          jsonb_set(
                            coalesce(metadata, '{}'::jsonb),
                            '{linked_demo}', 'true'::jsonb, true
                          ),
                          '{demo_driver_id}', to_jsonb(v_driver::text), true
                        ),
                        '{demo_offer_id}', to_jsonb(v_offer_id::text), true
                      ),
                      '{demo_expires_at}', to_jsonb(v_expires_at::text), true
                    )
   WHERE id = p_ride_id;

  RETURN v_offer_id;
END;
$$;