-- ride_complete: run trusted money primitives in service context
CREATE OR REPLACE FUNCTION public.ride_complete(
  p_ride_id uuid, p_actual_fare_gnf bigint DEFAULT NULL, p_commission_bps integer DEFAULT NULL)
RETURNS public.rides
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_claims text := current_setting('request.jwt.claims', true);
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
    RETURN v_ride;
  END IF;
  IF v_ride.status = 'cancelled' THEN RAISE EXCEPTION 'Ride already cancelled'; END IF;

  v_mtype := public._ride_mission_type(v_ride.mode::text);
  v_pay   := public._ride_payment_mode(v_ride);

  IF p_actual_fare_gnf IS NOT NULL AND public._finance_privileged(v_uid) THEN
    v_fare := GREATEST(p_actual_fare_gnf, 0);
  ELSE
    v_fare := v_ride.fare_gnf;
  END IF;

  v_snap := COALESCE(v_ride.metadata->'finance_snapshot',
                     public.finance_policy_snapshot(v_mtype, now(), v_pay, v_fare, 0, 0, 0, false));
  v_bps   := COALESCE((v_snap->>'commission_bps')::int, 0);
  v_fixed := COALESCE((v_snap->>'fixed_commission_gnf')::bigint, 0);
  v_commission := (v_fare * v_bps) / 10000 + v_fixed;
  v_driver_earn := v_fare - v_commission;

  -- Trusted service context for money primitives.
  PERFORM set_config('request.jwt.claims', '', true);

  IF v_pay = 'choppay' AND v_ride.hold_tx_id IS NOT NULL THEN
    SELECT amount_gnf INTO v_held FROM public.wallet_transactions WHERE id = v_ride.hold_tx_id;
    IF COALESCE(v_held,0) < v_fare THEN v_deficit := v_fare - COALESCE(v_held,0); END IF;
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

    PERFORM public.driver_mission_hold_release('ride', p_ride_id, 'commission',
      'Commission prélevée sur le paiement Chop Pay');
  ELSE
    v_cap := public.driver_mission_commission_capture('ride', p_ride_id, v_fare);
    IF COALESCE(v_cap->>'status','') = 'captured' THEN
      v_deficit := GREATEST(v_commission - COALESCE((v_cap->>'captured_gnf')::bigint,0), 0);
    END IF;
  END IF;

  PERFORM set_config('request.jwt.claims', COALESCE(v_claims,''), true);

  UPDATE public.rides SET
    status='completed', fare_gnf=v_fare, platform_fee_gnf=v_commission,
    driver_earning_gnf=v_driver_earn,
    payment_tx_id = COALESCE(v_payment.id, payment_tx_id),
    metadata = COALESCE(metadata,'{}'::jsonb) || jsonb_build_object(
      'final_fare_gnf', v_fare, 'commission_gnf', v_commission,
      'economic_driver_earning_gnf', v_driver_earn,
      'cash_collected_gnf', CASE WHEN v_pay='cash' THEN v_fare ELSE 0 END,
      'commission_deficit_gnf', v_deficit,
      'settlement', COALESCE(v_cap, jsonb_build_object('status','choppay_capture'))),
    completed_at = now()
  WHERE id = p_ride_id RETURNING * INTO v_ride;

  IF v_ride.driver_id IS NOT NULL THEN
    UPDATE public.driver_profiles SET presence='online', last_seen_at=now()
     WHERE user_id = v_ride.driver_id AND presence='on_trip';
  END IF;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (v_uid,'wallet','ride.settled','ride', v_ride.id::text,
    jsonb_build_object('fare_gnf',v_fare,'payment_mode',v_pay,'commission_gnf',v_commission,
                       'driver_earning_gnf',v_driver_earn,'deficit_gnf',v_deficit,'settlement',v_cap),
    'Règlement course ' || v_ride.mode::text);

  RETURN v_ride;
END $$;

-- ride_cancel: same trusted-context treatment
CREATE OR REPLACE FUNCTION public.ride_cancel(p_ride_id uuid, p_reason text DEFAULT 'Course annulée')
RETURNS public.rides
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_claims text := current_setting('request.jwt.claims', true);
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
    RETURN v_ride;
  END IF;
  IF v_ride.status='in_progress' AND v_by='client' THEN
    RAISE EXCEPTION 'ride_in_progress_cancel_not_allowed';
  END IF;

  v_mtype := public._ride_mission_type(v_ride.mode::text);
  v_pay   := public._ride_payment_mode(v_ride);
  v_stage := CASE WHEN v_ride.driver_id IS NOT NULL THEN 'after_dispatch' ELSE 'before_dispatch' END;
  v_snap  := COALESCE(v_ride.metadata->'finance_snapshot',
                      public.finance_policy_snapshot(v_mtype, now(), v_pay, v_ride.fare_gnf,0,0,0,false));
  v_bps   := CASE v_stage WHEN 'before_dispatch'
               THEN COALESCE((v_snap->>'cancel_before_dispatch_bps')::int, 500)
               ELSE COALESCE((v_snap->>'cancel_after_dispatch_bps')::int, 1000) END;
  v_responsible := CASE v_by WHEN 'client' THEN 'customer' WHEN 'driver' THEN 'driver' ELSE 'platform' END;

  PERFORM set_config('request.jwt.claims', '', true);

  PERFORM public.driver_mission_hold_release('ride', p_ride_id, 'commission', p_reason);

  IF v_responsible='customer' AND v_ride.fare_gnf > 0 THEN
    v_fee := (v_ride.fare_gnf * v_bps) / 10000;
  END IF;

  IF v_pay='choppay' AND v_ride.hold_tx_id IS NOT NULL
     AND COALESCE((v_ride.metadata->>'cancellation_fee_gnf')::bigint,0)=0 THEN
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
        v_release := 'fee_capture_error: ' || SQLERRM || ' — fallback release'; v_fee := 0;
        BEGIN PERFORM public.wallet_release(p_hold_id := v_ride.hold_tx_id, p_reason := p_reason);
        EXCEPTION WHEN OTHERS THEN v_release := v_release || ' — release_error: ' || SQLERRM; END;
      END;
    ELSE
      BEGIN PERFORM public.wallet_release(p_hold_id := v_ride.hold_tx_id, p_reason := p_reason);
        v_release := 'released_no_fee';
      EXCEPTION WHEN OTHERS THEN v_release := 'release_error: ' || SQLERRM; END;
    END IF;
  ELSIF v_pay='cash' AND v_ride.fare_gnf > 0 THEN
    BEGIN
      v_debt := public.customer_cancellation_debt_create(
        p_source_module := 'ride', p_source_id := p_ride_id, p_customer := v_ride.client_id,
        p_mission_type := v_mtype, p_stage := v_stage, p_fare_gnf := v_ride.fare_gnf,
        p_merchandise_subtotal_gnf := 0, p_delivery_fee_gnf := 0,
        p_preparation_started := false, p_responsible_party := v_responsible, p_is_sandbox := false);
      v_release := 'cash_debt:' || COALESCE(v_debt->>'status','unknown');
      v_fee := COALESCE((v_debt->>'amount_gnf')::bigint, 0);
    EXCEPTION WHEN OTHERS THEN v_release := 'debt_error: ' || SQLERRM; v_fee := 0; END;
  END IF;

  PERFORM set_config('request.jwt.claims', COALESCE(v_claims,''), true);

  UPDATE public.ride_offers SET status='cancelled', responded_at=COALESCE(responded_at, now())
   WHERE ride_id = p_ride_id AND status='pending';

  UPDATE public.rides SET status='cancelled',
    metadata = COALESCE(metadata,'{}'::jsonb) || jsonb_build_object(
      'cancelled_by', v_by, 'cancelled_at', to_jsonb(now()), 'cancel_reason', p_reason,
      'cancel_stage', v_stage, 'cancel_bps', v_bps, 'responsible_party', v_responsible,
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
            jsonb_build_object('fee_gnf',v_fee,'stage',v_stage,'bps',v_bps,
                               'payment_mode',v_pay,'responsible',v_responsible),
            'Frais d''annulation CHOPCHOP');
  END IF;

  RETURN v_ride;
END $$;
