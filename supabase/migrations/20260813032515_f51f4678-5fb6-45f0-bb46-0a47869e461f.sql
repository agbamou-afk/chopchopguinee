-- 1) Core expiry logic, callable without a user session (internal only).
CREATE OR REPLACE FUNCTION public._ride_expire_unfulfilled_internal(p_ride_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_ride public.rides; v_age numeric; v_released bigint := 0;
  v_claims text := current_setting('request.jwt.claims', true);
BEGIN
  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id FOR UPDATE;
  IF v_ride.id IS NULL THEN RAISE EXCEPTION 'RIDE_NOT_FOUND'; END IF;

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
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_ride.client_id), true);
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
END $function$;

REVOKE ALL ON FUNCTION public._ride_expire_unfulfilled_internal(uuid) FROM PUBLIC, anon, authenticated;

-- 2) Customer/admin-facing entry point keeps its authorization contract.
CREATE OR REPLACE FUNCTION public.ride_expire_unfulfilled(p_ride_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_client uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  SELECT client_id INTO v_client FROM public.rides WHERE id = p_ride_id;
  IF v_client IS NULL THEN RAISE EXCEPTION 'RIDE_NOT_FOUND'; END IF;
  IF v_client <> v_uid AND NOT public._is_ops_or_god_admin(v_uid) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  RETURN public._ride_expire_unfulfilled_internal(p_ride_id);
END $function$;

REVOKE ALL ON FUNCTION public.ride_expire_unfulfilled(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ride_expire_unfulfilled(uuid) TO authenticated;

-- 3) Autonomous sweeper: closes abandoned searches without any client device.
CREATE OR REPLACE FUNCTION public.ride_sweep_unfulfilled(p_limit int DEFAULT 200)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_id uuid; v_res jsonb; v_expired int := 0; v_seen int := 0;
BEGIN
  -- Fail closed: only the scheduler (no session) or an ops/god admin may sweep.
  IF v_uid IS NOT NULL AND NOT public._is_ops_or_god_admin(v_uid) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  FOR v_id IN
    SELECT id FROM public.rides
     WHERE status = 'pending'
       AND driver_id IS NULL
       AND created_at < now() - interval '60 seconds'
     ORDER BY created_at ASC
     LIMIT GREATEST(COALESCE(p_limit, 200), 1)
  LOOP
    v_seen := v_seen + 1;
    v_res := public._ride_expire_unfulfilled_internal(v_id);
    IF v_res->>'status' = 'no_driver' THEN v_expired := v_expired + 1; END IF;
  END LOOP;

  RETURN jsonb_build_object('scanned', v_seen, 'expired', v_expired, 'at', now());
END $function$;

REVOKE ALL ON FUNCTION public.ride_sweep_unfulfilled(int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ride_sweep_unfulfilled(int) TO service_role;

-- 4) Schedule it every minute.
SELECT cron.unschedule('chopchop-ride-no-driver-sweep')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'chopchop-ride-no-driver-sweep');

SELECT cron.schedule(
  'chopchop-ride-no-driver-sweep',
  '* * * * *',
  $$SELECT public.ride_sweep_unfulfilled(500);$$
);