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

  -- Node 2: Taxi stays fully closed until the `taxi` flag is switched on.
  IF p_mode = 'auto'::public.ride_mode AND NOT public._finance_flag('taxi') THEN
    RAISE EXCEPTION 'TAXI_NOT_ENABLED';
  END IF;

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