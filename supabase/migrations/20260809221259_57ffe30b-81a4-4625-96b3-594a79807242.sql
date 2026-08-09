-- ============================================================
-- Slice 3: Ride + Bonbonna runtime wired to Chop Pay ledger
-- ============================================================

-- Mission type resolution: moto -> ride, toktok -> bonbonna
CREATE OR REPLACE FUNCTION public._ride_mission_type(p_mode text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT CASE p_mode WHEN 'toktok' THEN 'bonbonna' ELSE 'ride' END
$$;

CREATE OR REPLACE FUNCTION public._finance_flag(p_key text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE((SELECT enabled FROM public.feature_flags WHERE key = p_key), false)
$$;

CREATE OR REPLACE FUNCTION public._ride_payment_mode(p_ride public.rides)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT COALESCE(p_ride.metadata->>'payment_mode',
                  CASE WHEN p_ride.hold_tx_id IS NOT NULL THEN 'choppay' ELSE 'cash' END)
$$;

REVOKE ALL ON FUNCTION public._finance_flag(text) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------
-- Accepted-snapshot immutability
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._ride_snapshot_immutable()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF OLD.metadata ? 'finance_snapshot'
     AND COALESCE(NEW.metadata->'finance_snapshot','null'::jsonb)
         IS DISTINCT FROM OLD.metadata->'finance_snapshot' THEN
    RAISE EXCEPTION 'RIDE_FINANCE_SNAPSHOT_IMMUTABLE';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_ride_snapshot_immutable ON public.rides;
CREATE TRIGGER trg_ride_snapshot_immutable
BEFORE UPDATE ON public.rides
FOR EACH ROW EXECUTE FUNCTION public._ride_snapshot_immutable();

-- ---------------------------------------------------------------
-- ACCEPT: atomic recheck + snapshot freeze + commission reserve
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ride_accept(p_ride_id uuid)
RETURNS public.rides
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ride public.rides;
  v_mtype text; v_pay text; v_snap jsonb; v_gate boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id FOR UPDATE;
  IF v_ride.id IS NULL THEN RAISE EXCEPTION 'Ride not found'; END IF;

  -- Idempotent replay: same driver, still assigned to them.
  IF v_ride.driver_id = v_uid AND v_ride.status = 'pending' THEN
    RETURN v_ride;
  END IF;
  IF v_ride.driver_id IS NOT NULL OR v_ride.status <> 'pending' THEN
    RAISE EXCEPTION 'Ride not available';
  END IF;

  IF NOT public._driver_finance_eligible(v_uid) THEN
    RAISE EXCEPTION 'ACCOUNT_RESTRICTED';
  END IF;

  v_mtype := public._ride_mission_type(v_ride.mode::text);
  v_pay   := public._ride_payment_mode(v_ride);
  v_gate  := public._finance_flag('driver_balance_gate_enabled');

  INSERT INTO public.wallets (owner_user_id, party_type)
  VALUES (v_uid, 'driver') ON CONFLICT (owner_user_id, party_type) DO NOTHING;

  -- Commission reserve (source-attributed, idempotent per mission+kind).
  -- Only enforced when the driver balance gate is enabled.
  IF v_gate THEN
    PERFORM public.driver_mission_hold_place(
      p_mission_type := v_mtype, p_source_module := 'ride', p_source_id := p_ride_id,
      p_value_gnf := v_ride.fare_gnf, p_driver := v_uid, p_is_sandbox := false,
      p_kinds := ARRAY['commission'], p_fare_gnf := v_ride.fare_gnf,
      p_merchandise_subtotal_gnf := 0, p_delivery_fee_gnf := 0,
      p_declared_value_gnf := 0, p_payment_mode := v_pay);
  END IF;

  v_snap := public.finance_policy_snapshot(v_mtype, now(), v_pay, v_ride.fare_gnf, 0, 0, 0, false);

  UPDATE public.rides
     SET driver_id = v_uid,
         status = 'pending',
         metadata = COALESCE(metadata,'{}'::jsonb) || jsonb_build_object(
           'phase', COALESCE(metadata->>'phase','approach'),
           'accepted_at', to_jsonb(now()),
           'payment_mode', v_pay,
           'mission_type', v_mtype,
           'finance_snapshot', COALESCE(metadata->'finance_snapshot', v_snap)
         ),
         updated_at = now()
   WHERE id = p_ride_id AND driver_id IS NULL AND status = 'pending'
   RETURNING * INTO v_ride;

  IF v_ride.id IS NULL THEN RAISE EXCEPTION 'Ride not available'; END IF;
  RETURN v_ride;
END $$;

-- ---------------------------------------------------------------
-- COMPLETE: snapshot-driven commission, no fabricated cash credit
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ride_complete(
  p_ride_id uuid, p_actual_fare_gnf bigint DEFAULT NULL, p_commission_bps integer DEFAULT NULL)
RETURNS public.rides
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ride public.rides;
  v_fare bigint; v_mtype text; v_pay text; v_snap jsonb;
  v_bps int; v_fixed bigint; v_commission bigint; v_driver_earn bigint;
  v_cap jsonb; v_payment public.wallet_transactions; v_commission_tx public.wallet_transactions;
  v_deficit bigint := 0; v_held bigint := 0;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id FOR UPDATE;
  IF v_ride.id IS NULL THEN RAISE EXCEPTION 'Ride not found'; END IF;
  IF v_ride.client_id <> v_uid AND COALESCE(v_ride.driver_id,'00000000-0000-0000-0000-000000000000') <> v_uid
     AND NOT public.has_role(v_uid,'admin') THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  IF v_ride.status = 'completed' THEN
    IF v_ride.driver_id IS NOT NULL THEN
      UPDATE public.driver_profiles SET presence='online', last_seen_at=now()
       WHERE user_id = v_ride.driver_id AND presence='on_trip';
    END IF;
    RETURN v_ride; -- replay is inert
  END IF;
  IF v_ride.status = 'cancelled' THEN RAISE EXCEPTION 'Ride already cancelled'; END IF;

  v_mtype := public._ride_mission_type(v_ride.mode::text);
  v_pay   := public._ride_payment_mode(v_ride);

  -- Server-authoritative fare: only finance/God may override.
  IF p_actual_fare_gnf IS NOT NULL AND public._finance_privileged(v_uid) THEN
    v_fare := GREATEST(p_actual_fare_gnf, 0);
  ELSE
    v_fare := v_ride.fare_gnf;
  END IF;

  -- Accepted snapshot controls the economics. p_commission_bps is ignored.
  v_snap := COALESCE(v_ride.metadata->'finance_snapshot',
                     public.finance_policy_snapshot(v_mtype, now(), v_pay, v_fare, 0, 0, 0, false));
  v_bps   := COALESCE((v_snap->>'commission_bps')::int, 0);
  v_fixed := COALESCE((v_snap->>'fixed_commission_gnf')::bigint, 0);
  v_commission := (v_fare * v_bps) / 10000 + v_fixed;
  v_driver_earn := v_fare - v_commission;

  IF v_pay = 'choppay' AND v_ride.hold_tx_id IS NOT NULL THEN
    -- Customer prepaid: capture at most what is actually held.
    SELECT amount_gnf INTO v_held FROM public.wallet_transactions WHERE id = v_ride.hold_tx_id;
    IF COALESCE(v_held,0) < v_fare THEN
      v_deficit := v_fare - COALESCE(v_held,0);
    END IF;
    BEGIN
      SELECT * INTO v_payment FROM public.wallet_capture(
        p_hold_id := v_ride.hold_tx_id,
        p_to_user_id := v_ride.driver_id,
        p_to_party_type := (CASE WHEN v_ride.driver_id IS NOT NULL THEN 'driver' ELSE 'master' END)::wallet_party_type,
        p_actual_amount_gnf := LEAST(v_fare, COALESCE(v_held, v_fare)),
        p_description := 'Course ' || v_ride.mode::text);
    EXCEPTION WHEN OTHERS THEN v_payment := NULL; END;

    IF v_ride.driver_id IS NOT NULL AND v_commission > 0 AND v_payment.id IS NOT NULL THEN
      BEGIN
        SELECT * INTO v_commission_tx FROM public.wallet_internal_transfer(
          p_from_user_id := v_ride.driver_id, p_from_party_type := 'driver',
          p_to_user_id := NULL, p_to_party_type := 'master',
          p_amount_gnf := v_commission,
          p_description := 'Commission course ' || v_ride.id::text);
      EXCEPTION WHEN OTHERS THEN v_commission_tx := NULL; END;
    END IF;

    -- Commission was taken from the fare: release the driver reserve in full.
    PERFORM public.driver_mission_hold_release('ride', p_ride_id, 'commission',
      'Commission prélevée sur le paiement Chop Pay');
  ELSE
    -- CASH: physical cash stays with the driver. Only the reserve moves.
    v_cap := public.driver_mission_commission_capture('ride', p_ride_id, v_fare);
    IF COALESCE(v_cap->>'status','') = 'captured' THEN
      v_deficit := GREATEST(v_commission - COALESCE((v_cap->>'captured_gnf')::bigint, 0), 0);
    ELSIF COALESCE(v_cap->>'status','') = 'no_hold' THEN
      v_deficit := 0; -- gate off: no reserve was taken at acceptance
    END IF;
  END IF;

  UPDATE public.rides SET
    status = 'completed',
    fare_gnf = v_fare,
    platform_fee_gnf = v_commission,
    driver_earning_gnf = v_driver_earn,
    payment_tx_id = COALESCE(v_payment.id, payment_tx_id),
    metadata = COALESCE(metadata,'{}'::jsonb) || jsonb_build_object(
      'final_fare_gnf', v_fare,
      'commission_gnf', v_commission,
      'economic_driver_earning_gnf', v_driver_earn,
      'cash_collected_gnf', CASE WHEN v_pay='cash' THEN v_fare ELSE 0 END,
      'commission_deficit_gnf', v_deficit,
      'settlement', COALESCE(v_cap, jsonb_build_object('status','choppay_capture'))
    ),
    completed_at = now()
  WHERE id = p_ride_id
  RETURNING * INTO v_ride;

  IF v_ride.driver_id IS NOT NULL THEN
    UPDATE public.driver_profiles SET presence='online', last_seen_at=now()
     WHERE user_id = v_ride.driver_id AND presence='on_trip';
  END IF;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (v_uid,'wallet','ride.settled','ride', v_ride.id::text,
    jsonb_build_object('fare_gnf',v_fare,'payment_mode',v_pay,'commission_gnf',v_commission,
                       'driver_earning_gnf',v_driver_earn,'deficit_gnf',v_deficit,
                       'settlement', v_cap),
    'Règlement course ' || v_ride.mode::text);

  RETURN v_ride;
END $$;

-- ---------------------------------------------------------------
-- CANCEL: snapshot-driven fee, reserve release, debt primitive
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ride_cancel(p_ride_id uuid, p_reason text DEFAULT 'Course annulée')
RETURNS public.rides
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ride public.rides; v_by text; v_stage text; v_mtype text; v_pay text;
  v_snap jsonb; v_bps int; v_fee bigint := 0; v_fee_tx public.wallet_transactions;
  v_release text := 'not_applicable'; v_responsible text; v_debt jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id FOR UPDATE;
  IF v_ride.id IS NULL THEN RAISE EXCEPTION 'Ride not found'; END IF;

  IF v_ride.client_id = v_uid THEN v_by := 'client';
  ELSIF v_ride.driver_id = v_uid THEN v_by := 'driver';
  ELSIF public.has_role(v_uid,'admin') THEN v_by := 'admin';
  ELSE RAISE EXCEPTION 'Not authorized'; END IF;

  IF v_ride.status IN ('completed','cancelled') THEN
    IF v_ride.driver_id IS NOT NULL THEN
      UPDATE public.driver_profiles SET presence='online', last_seen_at=now()
       WHERE user_id = v_ride.driver_id AND presence='on_trip';
    END IF;
    RETURN v_ride; -- idempotent replay
  END IF;
  IF v_ride.status = 'in_progress' AND v_by = 'client' THEN
    RAISE EXCEPTION 'ride_in_progress_cancel_not_allowed';
  END IF;

  v_mtype := public._ride_mission_type(v_ride.mode::text);
  v_pay   := public._ride_payment_mode(v_ride);
  v_stage := CASE WHEN v_ride.driver_id IS NOT NULL THEN 'after_dispatch' ELSE 'before_dispatch' END;
  v_snap  := COALESCE(v_ride.metadata->'finance_snapshot',
                      public.finance_policy_snapshot(v_mtype, now(), v_pay, v_ride.fare_gnf, 0,0,0, false));
  v_bps   := CASE v_stage WHEN 'before_dispatch'
               THEN COALESCE((v_snap->>'cancel_before_dispatch_bps')::int, 500)
               ELSE COALESCE((v_snap->>'cancel_after_dispatch_bps')::int, 1000) END;

  v_responsible := CASE v_by WHEN 'client' THEN 'customer' WHEN 'driver' THEN 'driver' ELSE 'platform' END;

  -- Always release the driver commission reserve: no mission will be performed.
  PERFORM public.driver_mission_hold_release('ride', p_ride_id, 'commission', p_reason);

  IF v_responsible = 'customer' AND v_ride.fare_gnf > 0 THEN
    v_fee := (v_ride.fare_gnf * v_bps) / 10000;
  END IF;

  IF v_pay = 'choppay' AND v_ride.hold_tx_id IS NOT NULL
     AND COALESCE((v_ride.metadata->>'cancellation_fee_gnf')::bigint, 0) = 0 THEN
    IF v_fee > 0 THEN
      BEGIN
        PERFORM public.wallet_ensure_master();
        v_fee_tx := public.wallet_capture(
          p_hold_id := v_ride.hold_tx_id, p_to_user_id := NULL,
          p_to_party_type := 'master'::public.party_type,
          p_actual_amount_gnf := v_fee,
          p_description := 'Frais d''annulation client CHOPCHOP');
        v_release := 'fee_captured';
      EXCEPTION WHEN OTHERS THEN
        v_release := 'fee_capture_error: ' || SQLERRM || ' — fallback release';
        v_fee := 0;
        BEGIN PERFORM public.wallet_release(p_hold_id := v_ride.hold_tx_id, p_reason := p_reason);
        EXCEPTION WHEN OTHERS THEN v_release := v_release || ' — release_error: ' || SQLERRM; END;
      END;
    ELSE
      BEGIN PERFORM public.wallet_release(p_hold_id := v_ride.hold_tx_id, p_reason := p_reason);
        v_release := 'released_no_fee';
      EXCEPTION WHEN OTHERS THEN v_release := 'release_error: ' || SQLERRM; END;
    END IF;
  ELSIF v_pay = 'cash' AND v_ride.fare_gnf > 0 THEN
    -- Server-authoritative cancellation debt (exempt when not customer-caused).
    BEGIN
      v_debt := public.customer_cancellation_debt_create(
        p_source_module := 'ride', p_source_id := p_ride_id, p_customer := v_ride.client_id,
        p_mission_type := v_mtype, p_stage := v_stage, p_fare_gnf := v_ride.fare_gnf,
        p_merchandise_subtotal_gnf := 0, p_delivery_fee_gnf := 0,
        p_preparation_started := false, p_responsible_party := v_responsible,
        p_is_sandbox := false);
      v_release := 'cash_debt:' || COALESCE(v_debt->>'status','unknown');
      v_fee := COALESCE((v_debt->>'amount_gnf')::bigint, 0);
    EXCEPTION WHEN OTHERS THEN
      v_release := 'debt_error: ' || SQLERRM; v_fee := 0;
    END;
  END IF;

  UPDATE public.ride_offers SET status='cancelled', responded_at=COALESCE(responded_at, now())
   WHERE ride_id = p_ride_id AND status='pending';

  UPDATE public.rides SET
    status='cancelled',
    metadata = COALESCE(metadata,'{}'::jsonb) || jsonb_build_object(
      'cancelled_by', v_by, 'cancelled_at', to_jsonb(now()), 'cancel_reason', p_reason,
      'cancel_stage', v_stage, 'cancel_bps', v_bps,
      'responsible_party', v_responsible,
      'hold_release', v_release, 'cancellation_fee_gnf', v_fee,
      'cancellation_fee_tx_id', COALESCE(v_fee_tx.id::text, NULL),
      'driver_deployed_at_cancel', (v_ride.driver_id IS NOT NULL)),
    updated_at = now()
  WHERE id = p_ride_id RETURNING * INTO v_ride;

  IF v_ride.driver_id IS NOT NULL THEN
    UPDATE public.driver_profiles SET presence='online', last_seen_at=now()
     WHERE user_id = v_ride.driver_id AND presence='on_trip';
  END IF;

  IF v_fee > 0 THEN
    INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
    VALUES (v_uid,'wallet','cancellation_fee_charged','ride', p_ride_id::text,
            jsonb_build_object('fee_gnf', v_fee, 'stage', v_stage, 'bps', v_bps,
                               'payment_mode', v_pay, 'responsible', v_responsible),
            'Frais d''annulation CHOPCHOP');
  END IF;

  RETURN v_ride;
END $$;

-- ---------------------------------------------------------------
-- DISPATCH: financial eligibility filter when the gate is enabled
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ride_dispatch(p_ride_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_ride public.rides; v_vehicle public.driver_vehicle_type;
  v_driver uuid; v_offer_id uuid; v_dist_m integer;
  v_gate boolean; v_mtype text;
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

  IF v_driver IS NULL THEN RETURN NULL; END IF;

  INSERT INTO public.ride_offers (
    ride_id, driver_id, status, sent_at, expires_at,
    distance_to_pickup_m, estimated_fare_gnf, estimated_earning_gnf
  ) VALUES (
    p_ride_id, v_driver, 'pending', now(), now() + interval '30 seconds',
    v_dist_m, v_ride.fare_gnf,
    v_ride.fare_gnf - (v_ride.fare_gnf * COALESCE(
      (SELECT commission_bps FROM public.finance_policy_current(v_mtype)), 1000)) / 10000
  ) RETURNING id INTO v_offer_id;

  RETURN v_offer_id;
END $$;

-- ---------------------------------------------------------------
-- OFFER ACCEPT: stale/expired/taken rejection before any money move
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.driver_offer_accept(p_offer_id uuid)
RETURNS public.ride_offers
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid(); v_offer public.ride_offers; v_ride public.rides;
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

  PERFORM public.ride_accept(v_offer.ride_id);

  UPDATE public.ride_offers SET status='accepted', responded_at=now()
   WHERE id = p_offer_id RETURNING * INTO v_offer;
  UPDATE public.driver_profiles SET presence='on_trip', last_seen_at=now() WHERE user_id = v_uid;
  RETURN v_offer;
END $$;
