
-- 1) Repair wallet_internal_transfer (column is owner_user_id, not user_id)
CREATE OR REPLACE FUNCTION public.wallet_internal_transfer(
  p_from_user_id uuid,
  p_from_party_type text,
  p_to_user_id uuid,
  p_to_party_type text,
  p_amount_gnf bigint,
  p_description text
) RETURNS public.wallet_transactions
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
DECLARE
  v_from_wallet public.wallets;
  v_to_wallet public.wallets;
  v_tx public.wallet_transactions;
BEGIN
  IF p_amount_gnf <= 0 THEN RAISE EXCEPTION 'Amount must be positive'; END IF;

  SELECT * INTO v_from_wallet FROM public.wallets
    WHERE party_type = p_from_party_type::wallet_party_type
      AND ((p_from_user_id IS NULL AND owner_user_id IS NULL) OR owner_user_id = p_from_user_id)
    FOR UPDATE;
  IF v_from_wallet IS NULL THEN RAISE EXCEPTION 'Source wallet not found'; END IF;
  IF v_from_wallet.balance_gnf - v_from_wallet.held_gnf < p_amount_gnf THEN
    RAISE EXCEPTION 'Insufficient funds';
  END IF;

  SELECT * INTO v_to_wallet FROM public.wallets
    WHERE party_type = p_to_party_type::wallet_party_type
      AND ((p_to_user_id IS NULL AND owner_user_id IS NULL) OR owner_user_id = p_to_user_id)
    FOR UPDATE;
  IF v_to_wallet IS NULL THEN RAISE EXCEPTION 'Destination wallet not found'; END IF;

  UPDATE public.wallets SET balance_gnf = balance_gnf - p_amount_gnf WHERE id = v_from_wallet.id;
  UPDATE public.wallets SET balance_gnf = balance_gnf + p_amount_gnf WHERE id = v_to_wallet.id;

  INSERT INTO public.wallet_transactions (
    from_wallet_id, to_wallet_id, amount_gnf, type, status, description
  ) VALUES (
    v_from_wallet.id, v_to_wallet.id, p_amount_gnf, 'transfer', 'completed', p_description
  ) RETURNING * INTO v_tx;

  RETURN v_tx;
END;
$function$;

-- 2) Extend ride_complete: reset driver presence + credit driver wallet
--    when ride has no hold (cash/demo). Idempotent via related_entity.
CREATE OR REPLACE FUNCTION public.ride_complete(
  p_ride_id uuid,
  p_actual_fare_gnf bigint DEFAULT NULL,
  p_commission_bps integer DEFAULT 1500
) RETURNS public.rides
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_ride public.rides;
  v_fare bigint;
  v_platform bigint;
  v_driver_earn bigint;
  v_payment public.wallet_transactions;
  v_commission public.wallet_transactions;
  v_to_party text;
  v_earning_tx public.wallet_transactions;
  v_already boolean;
  v_driver_wallet_id uuid;
  v_master_wallet_id uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id FOR UPDATE;
  IF v_ride IS NULL THEN RAISE EXCEPTION 'Ride not found'; END IF;
  IF v_ride.client_id <> v_uid AND v_ride.driver_id <> v_uid AND NOT public.has_role(v_uid, 'admin') THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF v_ride.status = 'completed' THEN
    -- Still ensure presence reset on retry.
    IF v_ride.driver_id IS NOT NULL THEN
      UPDATE public.driver_profiles SET presence = 'online', last_seen_at = now()
        WHERE user_id = v_ride.driver_id AND presence = 'on_trip';
    END IF;
    RETURN v_ride;
  END IF;
  IF v_ride.status = 'cancelled' THEN RAISE EXCEPTION 'Ride already cancelled'; END IF;

  v_fare := COALESCE(p_actual_fare_gnf, v_ride.fare_gnf);
  v_platform := (v_fare * p_commission_bps) / 10000;
  v_driver_earn := v_fare - v_platform;

  IF v_ride.driver_id IS NOT NULL THEN v_to_party := 'driver';
  ELSE v_to_party := 'master'; END IF;

  -- Capture flow when an escrow hold exists.
  IF v_ride.hold_tx_id IS NOT NULL THEN
    BEGIN
      SELECT * INTO v_payment FROM public.wallet_capture(
        p_hold_id := v_ride.hold_tx_id,
        p_to_user_id := v_ride.driver_id,
        p_to_party_type := v_to_party::wallet_party_type,
        p_actual_amount_gnf := v_fare,
        p_description := 'Course ' || v_ride.mode::text
      );
    EXCEPTION WHEN OTHERS THEN
      v_payment := NULL;
    END;

    IF v_ride.driver_id IS NOT NULL AND v_platform > 0 AND v_payment.id IS NOT NULL THEN
      BEGIN
        SELECT * INTO v_commission FROM public.wallet_internal_transfer(
          p_from_user_id := v_ride.driver_id, p_from_party_type := 'driver',
          p_to_user_id := NULL, p_to_party_type := 'master',
          p_amount_gnf := v_platform,
          p_description := 'Commission course ' || v_ride.id::text
        );
      EXCEPTION WHEN OTHERS THEN
        v_commission := NULL;
      END;
    END IF;
  END IF;

  -- Cash / no-hold ride: ensure driver still gets a ledger-backed credit
  -- for their net earning from the master wallet. Idempotent per ride.
  IF v_ride.hold_tx_id IS NULL AND v_ride.driver_id IS NOT NULL AND v_driver_earn > 0 THEN
    SELECT EXISTS(
      SELECT 1 FROM public.wallet_transactions
       WHERE related_entity = 'ride:' || v_ride.id::text
         AND type = 'ride_earning'
    ) INTO v_already;

    IF NOT v_already THEN
      -- Make sure both wallets exist.
      INSERT INTO public.wallets (owner_user_id, party_type)
        VALUES (v_ride.driver_id, 'driver') ON CONFLICT (owner_user_id, party_type) DO NOTHING;

      SELECT id INTO v_driver_wallet_id FROM public.wallets
        WHERE owner_user_id = v_ride.driver_id AND party_type = 'driver' LIMIT 1;
      SELECT id INTO v_master_wallet_id FROM public.wallets
        WHERE party_type = 'master' AND owner_user_id IS NULL LIMIT 1;

      IF v_driver_wallet_id IS NOT NULL AND v_master_wallet_id IS NOT NULL THEN
        UPDATE public.wallets SET balance_gnf = balance_gnf - v_driver_earn
          WHERE id = v_master_wallet_id;
        UPDATE public.wallets SET balance_gnf = balance_gnf + v_driver_earn
          WHERE id = v_driver_wallet_id;

        INSERT INTO public.wallet_transactions (
          from_wallet_id, to_wallet_id, amount_gnf, type, status,
          related_user_id, related_entity, description, metadata
        ) VALUES (
          v_master_wallet_id, v_driver_wallet_id, v_driver_earn,
          'ride_earning', 'completed',
          v_ride.driver_id, 'ride:' || v_ride.id::text,
          'Gain de course ' || v_ride.mode::text,
          jsonb_build_object(
            'ride_id', v_ride.id,
            'driver_user_id', v_ride.driver_id,
            'source', 'ride_completed',
            'gross_fare_gnf', v_fare,
            'platform_fee_gnf', v_platform,
            'net_earning_gnf', v_driver_earn
          )
        ) RETURNING * INTO v_earning_tx;
      END IF;
    END IF;
  END IF;

  UPDATE public.rides SET
    status = 'completed',
    fare_gnf = v_fare,
    driver_earning_gnf = v_driver_earn,
    payment_tx_id = COALESCE(v_payment.id, v_earning_tx.id, payment_tx_id),
    completed_at = now()
  WHERE id = p_ride_id
  RETURNING * INTO v_ride;

  -- Reset driver presence so they immediately become eligible for new offers.
  IF v_ride.driver_id IS NOT NULL THEN
    UPDATE public.driver_profiles SET presence = 'online', last_seen_at = now()
      WHERE user_id = v_ride.driver_id AND presence = 'on_trip';
  END IF;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (
    v_uid, 'wallet', 'ride.payment_captured', 'ride', v_ride.id::text,
    jsonb_build_object(
      'ride_id', v_ride.id,
      'fare_gnf', v_fare,
      'driver_earning_gnf', v_driver_earn,
      'platform_fee_gnf', v_platform,
      'payment_tx_id', v_payment.id,
      'earning_tx_id', v_earning_tx.id,
      'client_id', v_ride.client_id,
      'driver_id', v_ride.driver_id,
      'had_hold', v_ride.hold_tx_id IS NOT NULL
    ),
    'Capture wallet pour course ' || v_ride.mode::text
  );

  RETURN v_ride;
END $function$;

-- 3) ride_cancel: also reset driver presence so they stay dispatchable.
CREATE OR REPLACE FUNCTION public.ride_cancel(
  p_ride_id uuid,
  p_reason text DEFAULT 'Course annulée'
) RETURNS public.rides
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
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

  IF v_ride.client_id = v_uid THEN v_cancelled_by := 'client';
  ELSIF v_ride.driver_id = v_uid THEN v_cancelled_by := 'driver';
  ELSIF public.has_role(v_uid, 'admin') THEN v_cancelled_by := 'admin';
  ELSE RAISE EXCEPTION 'Not authorized'; END IF;

  IF v_ride.status IN ('completed','cancelled') THEN
    -- Defensive: still un-stick presence on retry.
    IF v_ride.driver_id IS NOT NULL THEN
      UPDATE public.driver_profiles SET presence = 'online', last_seen_at = now()
        WHERE user_id = v_ride.driver_id AND presence = 'on_trip';
    END IF;
    RETURN v_ride;
  END IF;

  IF v_ride.hold_tx_id IS NOT NULL THEN
    BEGIN
      PERFORM public.wallet_release(p_hold_id := v_ride.hold_tx_id, p_reason := p_reason);
      v_release_status := 'released_or_noop';
    EXCEPTION WHEN OTHERS THEN
      v_release_status := 'release_error: ' || SQLERRM;
    END;
  END IF;

  UPDATE public.ride_offers
     SET status = 'cancelled', responded_at = COALESCE(responded_at, now())
   WHERE ride_id = p_ride_id AND status = 'pending';

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

  -- Reset driver presence so they remain dispatchable for new rides.
  IF v_ride.driver_id IS NOT NULL THEN
    UPDATE public.driver_profiles SET presence = 'online', last_seen_at = now()
      WHERE user_id = v_ride.driver_id AND presence = 'on_trip';
  END IF;

  RETURN v_ride;
END $function$;
