CREATE OR REPLACE FUNCTION public.ride_cancel(p_ride_id uuid, p_reason text DEFAULT 'Course annulée'::text)
 RETURNS rides
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_ride public.rides;
  v_cancelled_by text;
  v_release_status text := 'not_applicable';
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id FOR UPDATE;
  IF v_ride.id IS NULL THEN RAISE EXCEPTION 'Ride not found'; END IF;

  IF v_ride.client_id = v_uid THEN
    v_cancelled_by := 'client';
  ELSIF v_ride.driver_id = v_uid THEN
    v_cancelled_by := 'driver';
  ELSIF public.has_role(v_uid, 'admin') THEN
    v_cancelled_by := 'admin';
  ELSE
    RAISE EXCEPTION 'Not authorized';
  END IF;

  IF v_ride.status IN ('completed','cancelled') THEN RETURN v_ride; END IF;

  IF v_ride.hold_tx_id IS NOT NULL THEN
    BEGIN
      PERFORM public.wallet_release(p_hold_id := v_ride.hold_tx_id, p_reason := p_reason);
      v_release_status := 'released_or_noop';
    EXCEPTION WHEN OTHERS THEN
      v_release_status := 'release_error: ' || SQLERRM;
    END;
  END IF;

  -- Cancel any outstanding pending offers so drivers stop seeing this ride.
  -- ride_offer_status enum values: pending, accepted, declined, missed, expired, cancelled.
  -- The previous version included the invalid label 'offered', which raised
  -- "invalid input value for enum ride_offer_status".
  UPDATE public.ride_offers
     SET status = 'cancelled',
         responded_at = COALESCE(responded_at, now())
   WHERE ride_id = p_ride_id
     AND status = 'pending';

  UPDATE public.rides
     SET status = 'cancelled',
         metadata = COALESCE(metadata,'{}'::jsonb) || jsonb_build_object(
           'cancelled_by', v_cancelled_by,
           'cancelled_at', to_jsonb(now()),
           'cancel_reason', p_reason,
           'hold_release', v_release_status
         ),
         updated_at = now()
   WHERE id = p_ride_id
   RETURNING * INTO v_ride;

  RETURN v_ride;
END $function$;