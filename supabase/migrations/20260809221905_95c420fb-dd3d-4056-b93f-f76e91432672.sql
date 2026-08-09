CREATE OR REPLACE FUNCTION public.ride_accept(p_ride_id uuid)
RETURNS public.rides
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_claims text := current_setting('request.jwt.claims', true);
  v_ride public.rides;
  v_mtype text; v_pay text; v_snap jsonb; v_gate boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id FOR UPDATE;
  IF v_ride.id IS NULL THEN RAISE EXCEPTION 'Ride not found'; END IF;

  IF v_ride.driver_id = v_uid AND v_ride.status = 'pending' THEN
    RETURN v_ride; -- idempotent replay
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

  IF v_gate THEN
    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN
      PERFORM public.driver_mission_hold_place(
        p_mission_type := v_mtype, p_source_module := 'ride', p_source_id := p_ride_id,
        p_value_gnf := v_ride.fare_gnf, p_driver := v_uid, p_is_sandbox := false,
        p_kinds := ARRAY['commission'], p_fare_gnf := v_ride.fare_gnf,
        p_merchandise_subtotal_gnf := 0, p_delivery_fee_gnf := 0,
        p_declared_value_gnf := 0, p_payment_mode := v_pay);
    EXCEPTION WHEN OTHERS THEN
      PERFORM set_config('request.jwt.claims', COALESCE(v_claims,''), true);
      RAISE;
    END;
    PERFORM set_config('request.jwt.claims', COALESCE(v_claims,''), true);
  END IF;

  v_snap := public.finance_policy_snapshot(v_mtype, now(), v_pay, v_ride.fare_gnf, 0, 0, 0, false);

  UPDATE public.rides
     SET driver_id = v_uid, status = 'pending',
         metadata = COALESCE(metadata,'{}'::jsonb) || jsonb_build_object(
           'phase', COALESCE(metadata->>'phase','approach'),
           'accepted_at', to_jsonb(now()),
           'payment_mode', v_pay, 'mission_type', v_mtype,
           'finance_snapshot', COALESCE(metadata->'finance_snapshot', v_snap)),
         updated_at = now()
   WHERE id = p_ride_id AND driver_id IS NULL AND status = 'pending'
   RETURNING * INTO v_ride;

  IF v_ride.id IS NULL THEN RAISE EXCEPTION 'Ride not available'; END IF;
  RETURN v_ride;
END $$;