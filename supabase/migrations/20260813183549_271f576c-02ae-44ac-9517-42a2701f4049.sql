-- T3: fail-closed vehicle eligibility resolution for ride dispatch + acceptance.
CREATE OR REPLACE FUNCTION public._ride_required_vehicle(p_mode text)
RETURNS public.driver_vehicle_type
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'public'
AS $function$
BEGIN
  RETURN CASE p_mode
           WHEN 'moto'   THEN 'moto'::public.driver_vehicle_type
           WHEN 'toktok' THEN 'toktok'::public.driver_vehicle_type
           WHEN 'auto'   THEN 'auto'::public.driver_vehicle_type
         END;
END $function$;

REVOKE ALL ON FUNCTION public._ride_required_vehicle(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._ride_required_vehicle(text) TO service_role;

CREATE OR REPLACE FUNCTION public.ride_dispatch(p_ride_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  -- Fail closed: never silently dispatch an unmapped mode to moto drivers.
  v_vehicle := public._ride_required_vehicle(v_ride.mode::text);
  IF v_vehicle IS NULL THEN
    RAISE EXCEPTION 'RIDE_MODE_NOT_DISPATCHABLE: %', v_ride.mode::text;
  END IF;

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
END $function$;

CREATE OR REPLACE FUNCTION public.driver_offer_accept(p_offer_id uuid)
 RETURNS ride_offers
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid(); v_offer public.ride_offers; v_ride public.rides;
  v_dp public.driver_profiles; v_required public.driver_vehicle_type;
  v_claims text := current_setting('request.jwt.claims', true);
  v_eligible boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_offer FROM public.ride_offers WHERE id = p_offer_id FOR UPDATE;
  IF v_offer.id IS NULL THEN RAISE EXCEPTION 'Offer not found'; END IF;
  IF v_offer.driver_id <> v_uid THEN RAISE EXCEPTION 'Not your offer'; END IF;

  IF v_offer.status = 'accepted' THEN
    RETURN v_offer; -- idempotent replay
  END IF;
  IF v_offer.status <> 'pending' THEN RAISE EXCEPTION 'OFFER_NO_LONGER_PENDING'; END IF;
  IF v_offer.expires_at < now() THEN
    UPDATE public.ride_offers SET status='expired', responded_at=now() WHERE id=p_offer_id;
    RAISE EXCEPTION 'OFFER_EXPIRED';
  END IF;

  SELECT * INTO v_ride FROM public.rides WHERE id = v_offer.ride_id;
  IF v_ride.id IS NULL OR v_ride.status <> 'pending' OR v_ride.driver_id IS NOT NULL THEN
    UPDATE public.ride_offers SET status='cancelled', responded_at=now() WHERE id=p_offer_id;
    RAISE EXCEPTION 'MISSION_NO_LONGER_AVAILABLE';
  END IF;

  -- Vehicle / status eligibility is re-validated at acceptance, not only at dispatch.
  PERFORM set_config('request.jwt.claims', '', true);
  SELECT * INTO v_dp FROM public.driver_profiles WHERE user_id = v_uid;
  v_eligible := public._driver_finance_eligible(v_uid);
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims,''), true);

  IF v_dp.user_id IS NULL OR v_dp.status <> 'approved' THEN
    RAISE EXCEPTION 'DRIVER_NOT_APPROVED';
  END IF;
  IF NOT v_eligible THEN
    RAISE EXCEPTION 'DRIVER_NOT_ELIGIBLE';
  END IF;
  -- Fail closed: an unmapped mode must never skip the vehicle check.
  v_required := public._ride_required_vehicle(v_ride.mode::text);
  IF v_required IS NULL OR v_dp.vehicle_type <> v_required THEN
    RAISE EXCEPTION 'DRIVER_VEHICLE_NOT_ELIGIBLE';
  END IF;

  PERFORM public.ride_accept(v_offer.ride_id);

  UPDATE public.ride_offers SET status='accepted', responded_at=now()
   WHERE id = p_offer_id RETURNING * INTO v_offer;
  UPDATE public.driver_profiles SET presence='on_trip', last_seen_at=now() WHERE user_id = v_uid;
  RETURN v_offer;
END $function$;