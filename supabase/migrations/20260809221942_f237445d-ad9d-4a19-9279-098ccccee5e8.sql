CREATE OR REPLACE FUNCTION public.ride_dispatch(p_ride_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_ride public.rides; v_vehicle public.driver_vehicle_type;
  v_driver uuid; v_offer_id uuid; v_dist_m integer;
  v_gate boolean; v_mtype text; v_bps int;
  v_claims text := current_setting('request.jwt.claims', true);
BEGIN
  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id;
  IF v_ride.id IS NULL OR v_ride.status <> 'pending' OR v_ride.driver_id IS NOT NULL THEN
    RETURN NULL;
  END IF;

  v_gate  := public._finance_flag('driver_balance_gate_enabled');
  v_mtype := public._ride_mission_type(v_ride.mode::text);
  v_vehicle := CASE v_ride.mode::text
                 WHEN 'moto' THEN 'moto'::public.driver_vehicle_type
                 WHEN 'toktok' THEN 'toktok'::public.driver_vehicle_type
                 ELSE 'moto'::public.driver_vehicle_type END;

  -- Trusted context: eligibility resolution reads ledger truth.
  PERFORM set_config('request.jwt.claims', '', true);

  SELECT dl.user_id,
         (6371000 * acos(greatest(-1, least(1,
            cos(radians(v_ride.pickup_lat)) * cos(radians(dl.lat)) *
            cos(radians(dl.lng) - radians(v_ride.pickup_lng)) +
            sin(radians(v_ride.pickup_lat)) * sin(radians(dl.lat))))))::integer
    INTO v_driver, v_dist_m
    FROM public.driver_locations dl
    JOIN public.driver_profiles dp ON dp.user_id = dl.user_id
   WHERE dp.status='approved' AND dp.vehicle_type = v_vehicle
     AND dp.presence='online' AND dl.status='online'
     AND NOT EXISTS (SELECT 1 FROM public.ride_offers o
                      WHERE o.ride_id = p_ride_id AND o.driver_id = dl.user_id)
     AND public._driver_finance_eligible(dl.user_id)
     AND (NOT v_gate OR COALESCE(
            (public.driver_financial_eligibility(v_mtype, v_ride.fare_gnf, dl.user_id)->>'eligible')::boolean,
            false))
   ORDER BY 2 ASC LIMIT 1;

  SELECT commission_bps INTO v_bps FROM public.finance_policy_current(v_mtype);

  PERFORM set_config('request.jwt.claims', COALESCE(v_claims,''), true);

  IF v_driver IS NULL THEN RETURN NULL; END IF;

  INSERT INTO public.ride_offers (
    ride_id, driver_id, status, sent_at, expires_at,
    distance_to_pickup_m, estimated_fare_gnf, estimated_earning_gnf
  ) VALUES (
    p_ride_id, v_driver, 'pending', now(), now() + interval '30 seconds',
    v_dist_m, v_ride.fare_gnf,
    v_ride.fare_gnf - (v_ride.fare_gnf * COALESCE(v_bps, 1000)) / 10000
  ) RETURNING id INTO v_offer_id;

  RETURN v_offer_id;
END $$;