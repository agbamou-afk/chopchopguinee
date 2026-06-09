
-- 1) Idempotent, ride-aware wallet_release
CREATE OR REPLACE FUNCTION public.wallet_release(p_hold_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS wallet_transactions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_caller uuid := auth.uid();
  v_hold public.wallet_transactions;
  v_wallet public.wallets;
  v_authorized boolean := false;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_hold FROM public.wallet_transactions
   WHERE id = p_hold_id FOR UPDATE;

  -- Idempotent: missing hold is treated as a no-op so cancellation never breaks.
  IF v_hold.id IS NULL THEN
    RETURN NULL::public.wallet_transactions;
  END IF;

  -- Authorization: original holder, admin, or the client/driver of a ride
  -- whose hold_tx_id points at this transaction. The ride-link covers the
  -- driver_cancel case where auth.uid() is the driver, not the holder.
  IF v_hold.related_user_id = v_caller OR public.has_role(v_caller, 'admin') THEN
    v_authorized := true;
  ELSE
    SELECT true INTO v_authorized
      FROM public.rides r
     WHERE r.hold_tx_id = v_hold.id
       AND (r.client_id = v_caller OR r.driver_id = v_caller)
     LIMIT 1;
    v_authorized := COALESCE(v_authorized, false);
  END IF;

  IF NOT v_authorized THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  IF v_hold.type <> 'hold' THEN
    -- Not a hold at all — nothing to release. Idempotent no-op.
    RETURN v_hold;
  END IF;

  -- Hold already captured (converted to a payment): cannot silently release.
  IF v_hold.status = 'completed' THEN
    RAISE EXCEPTION 'Hold already captured, refund required';
  END IF;

  -- Already released / cancelled / expired → idempotent success.
  IF v_hold.status <> 'pending' THEN
    RETURN v_hold;
  END IF;

  SELECT * INTO v_wallet FROM public.wallets WHERE id = v_hold.from_wallet_id FOR UPDATE;
  IF v_wallet.id IS NOT NULL THEN
    UPDATE public.wallets SET held_gnf = greatest(held_gnf - v_hold.amount_gnf, 0)
     WHERE id = v_wallet.id;
  END IF;

  UPDATE public.wallet_transactions
     SET status = 'cancelled', completed_at = now(),
         description = coalesce(p_reason, description)
   WHERE id = v_hold.id
   RETURNING * INTO v_hold;

  RETURN v_hold;
END $function$;

-- 2) ride_cancel: tolerant of inactive holds, records cancelled_by, expires offers
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

  -- Idempotent release: never let an inactive hold block cancellation.
  IF v_ride.hold_tx_id IS NOT NULL THEN
    BEGIN
      PERFORM public.wallet_release(p_hold_id := v_ride.hold_tx_id, p_reason := p_reason);
      v_release_status := 'released_or_noop';
    EXCEPTION WHEN OTHERS THEN
      -- Captured holds or genuine integrity failures are logged in metadata
      -- but must NOT block cancelling the ride for the user.
      v_release_status := 'release_error: ' || SQLERRM;
    END;
  END IF;

  -- Expire any outstanding offers so drivers stop seeing this ride.
  UPDATE public.ride_offers
     SET status = 'expired'
   WHERE ride_id = p_ride_id
     AND status IN ('offered','pending');

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
