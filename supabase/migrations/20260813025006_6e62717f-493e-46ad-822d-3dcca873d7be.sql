CREATE OR REPLACE FUNCTION public.ride_expire_unfulfilled(p_ride_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ride public.rides; v_age numeric; v_released bigint := 0;
  v_claims text := current_setting('request.jwt.claims', true);
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id FOR UPDATE;
  IF v_ride.id IS NULL THEN RAISE EXCEPTION 'RIDE_NOT_FOUND'; END IF;
  IF v_ride.client_id <> v_uid AND NOT public._is_ops_or_god_admin(v_uid) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  IF v_ride.driver_id IS NOT NULL THEN
    RETURN jsonb_build_object('status','assigned','ride_id',p_ride_id);
  END IF;
  IF v_ride.status <> 'pending' THEN
    RETURN jsonb_build_object('status', v_ride.status::text, 'ride_id', p_ride_id,
      'released_gnf', COALESCE((v_ride.metadata->>'no_driver_released_gnf')::bigint, 0));
  END IF;

  v_age := EXTRACT(EPOCH FROM (now() - v_ride.created_at));
  IF v_age < 60 THEN
    RETURN jsonb_build_object('status','searching','ride_id',p_ride_id,
      'seconds_remaining', ceil(60 - v_age)::int);
  END IF;

  UPDATE public.ride_offers SET status='expired', responded_at=now()
   WHERE ride_id = p_ride_id AND status = 'pending';

  -- Full release, no cancellation fee: the customer did not cause this.
  IF public._ride_payment_mode(v_ride) = 'chop_pay' AND v_ride.hold_tx_id IS NOT NULL
     AND NOT (v_ride.metadata ? 'no_driver_released_at') THEN
    PERFORM set_config('request.jwt.claims', '', true);
    PERFORM public.wallet_release(v_ride.hold_tx_id);
    PERFORM set_config('request.jwt.claims', COALESCE(v_claims,''), true);
    v_released := COALESCE((v_ride.metadata->>'hold_amount_gnf')::bigint, 0);
  END IF;

  UPDATE public.rides
     SET status = 'cancelled',
         metadata = COALESCE(metadata,'{}'::jsonb) || jsonb_build_object(
           'phase','cancelled',
           'cancelled_by','system',
           'cancel_reason','no_driver_available',
           'cancellation_fee_gnf', 0,
           'no_driver_released_at', now(),
           'no_driver_released_gnf', v_released)
   WHERE id = p_ride_id;

  RETURN jsonb_build_object('status','no_driver','ride_id',p_ride_id,'released_gnf',v_released);
END $$;

REVOKE ALL ON FUNCTION public.ride_expire_unfulfilled(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ride_expire_unfulfilled(uuid) TO authenticated, service_role;

DELETE FROM public._qa_s13_results WHERE part = 101;
INSERT INTO public._qa_s13_results(part, result)
SELECT 101, public._qa_node1_bonbonna();