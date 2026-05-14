
-- Fix ride_complete to gracefully handle rides without a wallet hold
CREATE OR REPLACE FUNCTION public.ride_complete(p_ride_id uuid, p_actual_fare_gnf bigint DEFAULT NULL::bigint, p_commission_bps integer DEFAULT 1500)
 RETURNS rides
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_ride public.rides;
  v_fare BIGINT;
  v_platform BIGINT;
  v_driver_earn BIGINT;
  v_payment public.wallet_transactions;
  v_commission public.wallet_transactions;
  v_to_party TEXT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id FOR UPDATE;
  IF v_ride IS NULL THEN RAISE EXCEPTION 'Ride not found'; END IF;
  IF v_ride.client_id <> v_uid AND v_ride.driver_id <> v_uid AND NOT public.has_role(v_uid, 'admin') THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF v_ride.status = 'completed' THEN RETURN v_ride; END IF;
  IF v_ride.status = 'cancelled' THEN RAISE EXCEPTION 'Ride already cancelled'; END IF;

  v_fare := COALESCE(p_actual_fare_gnf, v_ride.fare_gnf);
  v_platform := (v_fare * p_commission_bps) / 10000;
  v_driver_earn := v_fare - v_platform;

  IF v_ride.driver_id IS NOT NULL THEN
    v_to_party := 'driver';
  ELSE
    v_to_party := 'master';
  END IF;

  -- Only attempt wallet capture when there is an active hold to release.
  -- Demo / cash rides without an escrow simply close out without a payment txn.
  IF v_ride.hold_tx_id IS NOT NULL THEN
    BEGIN
      SELECT * INTO v_payment FROM public.wallet_capture(
        p_hold_id := v_ride.hold_tx_id,
        p_to_user_id := v_ride.driver_id,
        p_to_party_type := v_to_party::party_type,
        p_actual_amount_gnf := v_fare,
        p_description := 'Course ' || v_ride.mode::text
      );
    EXCEPTION WHEN OTHERS THEN
      -- Hold may have already been released (double tap) or stale; continue.
      v_payment := NULL;
    END;

    IF v_ride.driver_id IS NOT NULL AND v_platform > 0 AND v_payment.id IS NOT NULL THEN
      SELECT * INTO v_commission FROM public.wallet_internal_transfer(
        p_from_user_id := v_ride.driver_id,
        p_from_party_type := 'driver',
        p_to_user_id := NULL,
        p_to_party_type := 'master',
        p_amount_gnf := v_platform,
        p_description := 'Commission course ' || v_ride.id::text
      );
    END IF;
  END IF;

  UPDATE public.rides SET
    status = 'completed',
    fare_gnf = v_fare,
    platform_fee_gnf = v_platform,
    driver_earning_gnf = v_driver_earn,
    payment_tx_id = COALESCE(v_payment.id, payment_tx_id),
    completed_at = now()
  WHERE id = p_ride_id
  RETURNING * INTO v_ride;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (
    v_uid, 'wallet', 'ride.payment_captured', 'ride', v_ride.id::text,
    jsonb_build_object(
      'ride_id', v_ride.id,
      'fare_gnf', v_fare,
      'driver_earning_gnf', v_driver_earn,
      'platform_fee_gnf', v_platform,
      'payment_tx_id', v_payment.id,
      'client_id', v_ride.client_id,
      'driver_id', v_ride.driver_id,
      'had_hold', v_ride.hold_tx_id IS NOT NULL
    ),
    'Capture wallet pour course ' || v_ride.mode::text
  );

  IF v_commission.id IS NOT NULL THEN
    INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
    VALUES (
      v_uid, 'wallet', 'ride.commission_collected', 'ride', v_ride.id::text,
      jsonb_build_object(
        'ride_id', v_ride.id,
        'amount_gnf', v_platform,
        'commission_tx_id', v_commission.id,
        'driver_id', v_ride.driver_id
      ),
      'Commission CHOP CHOP'
    );
  END IF;

  RETURN v_ride;
END $function$;

-- Accept rotating QR payloads of the form CHOP-PICKUP-<code>-<anything>
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
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id FOR UPDATE;
  IF v_ride.id IS NULL THEN RAISE EXCEPTION 'Ride not found'; END IF;
  IF v_ride.client_id <> v_uid AND NOT public.has_role(v_uid, 'admin') THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF v_ride.status NOT IN ('accepted','arriving') THEN
    RAISE EXCEPTION 'Ride not in pickup phase';
  END IF;

  v_expected := upper(COALESCE(v_ride.metadata->>'pickup_code',''));
  v_provided := upper(trim(COALESCE(p_code,'')));
  IF v_provided LIKE 'CHOP-PICKUP-%' THEN
    v_provided := substr(v_provided, length('CHOP-PICKUP-') + 1);
    -- Strip optional rotating suffix (e.g. timestamp) after the code
    IF position('-' in v_provided) > 0 THEN
      v_provided := split_part(v_provided, '-', 1);
    END IF;
  END IF;
  IF v_expected = '' OR v_provided <> v_expected THEN
    RAISE EXCEPTION 'Code de prise en charge invalide';
  END IF;

  UPDATE public.rides
     SET status = 'in_progress',
         started_at = COALESCE(started_at, now()),
         metadata = COALESCE(metadata,'{}'::jsonb) || jsonb_build_object(
           'phase','on_trip',
           'pickup_confirmed_at', to_jsonb(now()),
           'pickup_confirmed_by','customer'
         )
   WHERE id = p_ride_id
   RETURNING * INTO v_ride;
  RETURN v_ride;
END $$;

GRANT EXECUTE ON FUNCTION public.ride_confirm_pickup(uuid, text) TO authenticated;
