-- Shared reservation constant: one source of truth for preview and commitment.
CREATE OR REPLACE FUNCTION public.ride_reservation_amount_gnf(p_fare_gnf bigint)
RETURNS bigint
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $$
  -- D3: finance_policies exposes no ride reservation-buffer field, so today's
  -- 1.10 buffer is preserved as a named SERVER-SIDE constant (11000 bps).
  SELECT CASE
           WHEN p_fare_gnf IS NULL OR p_fare_gnf <= 0 THEN 0::bigint
           ELSE ceil((p_fare_gnf::numeric * 11000) / 10000)::bigint
         END;
$$;

REVOKE ALL ON FUNCTION public.ride_reservation_amount_gnf(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ride_reservation_amount_gnf(bigint) TO authenticated, service_role;

-- Preview-only quote: extended, not replaced. Same engine, same constant.
CREATE OR REPLACE FUNCTION public.ride_get_quote(p_mode ride_mode, p_pickup_lat numeric, p_pickup_lng numeric, p_dest_lat numeric DEFAULT NULL::numeric, p_dest_lng numeric DEFAULT NULL::numeric)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_fare bigint;
BEGIN
  IF auth.uid() IS NULL AND current_setting('request.jwt.claim.role', true) IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED';
  END IF;

  v_fare := public.ride_compute_quote_gnf(p_mode, p_pickup_lat, p_pickup_lng, p_dest_lat, p_dest_lng);
  RETURN jsonb_build_object(
    'mode', p_mode::text,
    'pickup_lat', p_pickup_lat, 'pickup_lng', p_pickup_lng,
    'dest_lat', p_dest_lat, 'dest_lng', p_dest_lng,
    'fare_gnf', v_fare,
    'chop_pay_hold_gnf', public.ride_reservation_amount_gnf(v_fare),
    'reservation_buffer_bps', 11000,
    'currency', 'GNF',
    'preview_only', true,
    'authoritative', true,
    'source', 'server:ride_compute_quote_gnf'
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.ride_get_quote(ride_mode, numeric, numeric, numeric, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ride_get_quote(ride_mode, numeric, numeric, numeric, numeric) TO authenticated, service_role;

-- ride_request_create: identical behaviour, now derives the reservation from the
-- shared helper so preview and commitment can never drift.
CREATE OR REPLACE FUNCTION public.ride_request_create(p_mode ride_mode, p_pickup_lat numeric, p_pickup_lng numeric, p_dest_lat numeric, p_dest_lng numeric, p_payment_mode text, p_client_request_id uuid, p_pickup_label text DEFAULT NULL::text, p_dest_label text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  C_RESERVATION_BUFFER_BPS constant integer := 11000;
  v_uid  uuid := auth.uid();
  v_pay  text;
  v_fare bigint;
  v_hold bigint := 0;
  v_hold_tx public.wallet_transactions;
  v_ride public.rides;
  v_prev public.rides;
  v_snap jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF p_client_request_id IS NULL THEN RAISE EXCEPTION 'CLIENT_REQUEST_ID_REQUIRED'; END IF;

  v_pay := lower(COALESCE(p_payment_mode,''));
  IF v_pay = 'choppay' THEN v_pay := 'chop_pay'; END IF;
  IF v_pay NOT IN ('cash','chop_pay') THEN RAISE EXCEPTION 'INVALID_PAYMENT_MODE'; END IF;

  IF p_pickup_lat IS NULL OR p_pickup_lng IS NULL
     OR p_dest_lat IS NULL OR p_dest_lng IS NULL THEN
    RAISE EXCEPTION 'COORDINATES_REQUIRED';
  END IF;
  IF p_pickup_lat NOT BETWEEN 7 AND 13 OR p_pickup_lng NOT BETWEEN -15.5 AND -7
     OR p_dest_lat NOT BETWEEN 7 AND 13 OR p_dest_lng NOT BETWEEN -15.5 AND -7 THEN
    RAISE EXCEPTION 'COORDINATES_OUT_OF_SERVICE_AREA';
  END IF;

  SELECT * INTO v_prev FROM public.rides
   WHERE client_id = v_uid
     AND metadata->>'client_request_id' = p_client_request_id::text
   ORDER BY created_at
   LIMIT 1;
  IF v_prev.id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'status','already_created',
      'ride_id', v_prev.id,
      'fare_gnf', v_prev.fare_gnf,
      'hold_amount_gnf', COALESCE((v_prev.metadata->>'hold_amount_gnf')::bigint, 0),
      'payment_mode', public._ride_payment_mode(v_prev));
  END IF;

  PERFORM 1 FROM public.rides
   WHERE client_id = v_uid AND status IN ('pending','in_progress') LIMIT 1;
  IF FOUND THEN RAISE EXCEPTION 'ACTIVE_RIDE_EXISTS'; END IF;

  v_fare := public.ride_compute_quote_gnf(
              p_mode, p_pickup_lat, p_pickup_lng, p_dest_lat, p_dest_lng);

  v_snap := public.finance_policy_snapshot(
              public._ride_mission_type(p_mode::text), now(), v_pay, v_fare, 0, 0, 0, false);

  IF v_pay = 'chop_pay' THEN
    v_hold := public.ride_reservation_amount_gnf(v_fare);
    SELECT * INTO v_hold_tx FROM public.wallet_hold(
      p_amount_gnf := v_hold,
      p_reference  := 'ride_request:' || p_client_request_id::text,
      p_description := 'Réservation course ' || p_mode::text);
    IF v_hold_tx.id IS NULL THEN RAISE EXCEPTION 'HOLD_FAILED'; END IF;
  END IF;

  INSERT INTO public.rides (
    client_id, driver_id, mode, pickup_lat, pickup_lng, dest_lat, dest_lng,
    fare_gnf, hold_tx_id, status, metadata
  ) VALUES (
    v_uid, NULL, p_mode, p_pickup_lat, p_pickup_lng, p_dest_lat, p_dest_lng,
    v_fare,
    CASE WHEN v_pay = 'chop_pay' THEN v_hold_tx.id ELSE NULL END,
    'pending',
    jsonb_strip_nulls(jsonb_build_object(
      'client_request_id', p_client_request_id::text,
      'payment_mode', v_pay,
      'fare_source', 'server:ride_compute_quote_gnf',
      'fare_authority', 'server',
      'request_channel', 'ride_request_create',
      'reservation_buffer_bps', CASE WHEN v_pay='chop_pay' THEN C_RESERVATION_BUFFER_BPS END,
      'hold_amount_gnf', CASE WHEN v_pay='chop_pay' THEN v_hold END,
      'pickup_label', p_pickup_label,
      'dest_label', p_dest_label,
      'finance_snapshot', v_snap))
  ) RETURNING * INTO v_ride;

  RETURN jsonb_build_object(
    'status','created',
    'ride_id', v_ride.id,
    'fare_gnf', v_fare,
    'hold_amount_gnf', v_hold,
    'payment_mode', v_pay,
    'currency','GNF',
    'fare_source','server:ride_compute_quote_gnf');
END;
$function$;

REVOKE ALL ON FUNCTION public.ride_request_create(ride_mode, numeric, numeric, numeric, numeric, text, uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ride_request_create(ride_mode, numeric, numeric, numeric, numeric, text, uuid, text, text) TO authenticated, service_role;