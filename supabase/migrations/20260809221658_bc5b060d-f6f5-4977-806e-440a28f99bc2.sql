-- Fix: wallet_capture takes public.party_type (wallet_party_type never existed,
-- so the Chop Pay capture branch was silently dead).
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
  v_deficit bigint := 0; v_held bigint := 0; v_err text := NULL;
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

  PERFORM set_config('request.jwt.claims', '', true);

  IF v_pay = 'choppay' AND v_ride.hold_tx_id IS NOT NULL THEN
    SELECT amount_gnf INTO v_held FROM public.wallet_transactions WHERE id = v_ride.hold_tx_id;
    IF COALESCE(v_held,0) < v_fare THEN v_deficit := v_fare - COALESCE(v_held,0); END IF;
    BEGIN
      SELECT * INTO v_payment FROM public.wallet_capture(
        p_hold_id := v_ride.hold_tx_id,
        p_to_user_id := v_ride.driver_id,
        p_to_party_type := (CASE WHEN v_ride.driver_id IS NOT NULL THEN 'driver' ELSE 'master' END)::public.party_type,
        p_actual_amount_gnf := LEAST(v_fare, COALESCE(v_held, v_fare)),
        p_description := 'Course ' || v_ride.mode::text);
    EXCEPTION WHEN OTHERS THEN v_payment := NULL; v_err := 'capture:'||SQLERRM; END;

    IF v_ride.driver_id IS NOT NULL AND v_commission > 0 AND v_payment.id IS NOT NULL THEN
      BEGIN
        SELECT * INTO v_commission_tx FROM public.wallet_internal_transfer(
          p_from_user_id := v_ride.driver_id, p_from_party_type := 'driver',
          p_to_user_id := NULL, p_to_party_type := 'master',
          p_amount_gnf := v_commission,
          p_description := 'Commission course ' || v_ride.id::text);
      EXCEPTION WHEN OTHERS THEN v_commission_tx := NULL; v_err := COALESCE(v_err||' | ','')||'commission:'||SQLERRM; END;
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
      'settlement_error', v_err,
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

-- ============================================================
-- TEMPORARY self-rolling-back QA harness (dropped after the run)
-- ============================================================
CREATE OR REPLACE FUNCTION public._qa_s3_inner()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r jsonb := '[]'::jsonb;
  v_drv uuid; v_drv2 uuid; v_cli uuid;
  v_ride uuid; v_ride2 uuid; v_ride3 uuid; v_ride4 uuid;
  v_hold record; v_cnt int; v_bal bigint; v_master_before bigint; v_master_after bigint;
  v_drv_before bigint; v_drv_after bigint; v_tmp jsonb; v_txt text; v_off uuid;
  v_sum numeric;
  PROCEDURE_dummy int;
BEGIN
  SELECT user_id INTO v_drv FROM public.driver_profiles ORDER BY created_at LIMIT 1;
  SELECT user_id INTO v_drv2 FROM public.driver_profiles WHERE user_id <> v_drv ORDER BY created_at LIMIT 1;
  SELECT id INTO v_cli FROM public.profiles WHERE id NOT IN (COALESCE(v_drv,'00000000-0000-0000-0000-000000000000'::uuid)) LIMIT 1;
  IF v_drv IS NULL OR v_cli IS NULL THEN RAISE EXCEPTION 'QA_S3_RESULT:%', jsonb_build_object('error','no test users'); END IF;

  PERFORM public.wallet_ensure_master();
  UPDATE public.feature_flags SET enabled = true WHERE key='driver_balance_gate_enabled';
  INSERT INTO public.feature_flags(key, enabled) VALUES ('driver_balance_gate_enabled', true)
    ON CONFLICT (key) DO UPDATE SET enabled = true;

  INSERT INTO public.wallets(owner_user_id, party_type) VALUES (v_drv,'driver')
    ON CONFLICT (owner_user_id, party_type) DO NOTHING;
  INSERT INTO public.wallets(owner_user_id, party_type) VALUES (v_cli,'client')
    ON CONFLICT (owner_user_id, party_type) DO NOTHING;
  UPDATE public.wallets SET balance_gnf = 500000, held_gnf = 0, status='active'
    WHERE owner_user_id = v_drv AND party_type='driver';
  UPDATE public.wallets SET balance_gnf = 300000, held_gnf = 0, status='active'
    WHERE owner_user_id = v_cli AND party_type='client';

  -- ---------- B1/B2/B4: cash ride 100k ----------
  INSERT INTO public.rides(client_id, mode, pickup_lat, pickup_lng, dest_lat, dest_lng, fare_gnf, status, metadata)
  VALUES (v_cli,'moto',9.5,-13.7,9.6,-13.6,100000,'pending', jsonb_build_object('payment_mode','cash'))
  RETURNING id INTO v_ride;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_drv)::text, true);
  PERFORM public.ride_accept(v_ride);
  SELECT * INTO v_hold FROM public.mission_financial_holds WHERE source_module='ride' AND source_id=v_ride AND kind='commission';
  r := r || jsonb_build_object('id','A_RESERVE','pass', v_hold.amount_gnf = 10000, 'got', v_hold.amount_gnf);

  PERFORM public.ride_accept(v_ride); -- A6 replay
  SELECT count(*) INTO v_cnt FROM public.mission_financial_holds WHERE source_module='ride' AND source_id=v_ride;
  r := r || jsonb_build_object('id','A6','pass', v_cnt = 1, 'got', v_cnt);

  SELECT balance_gnf INTO v_drv_before FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
  SELECT balance_gnf INTO v_master_before FROM public.wallets WHERE party_type='master' LIMIT 1;
  PERFORM public.ride_complete(v_ride);
  SELECT captured_gnf, state INTO v_hold FROM public.mission_financial_holds WHERE source_module='ride' AND source_id=v_ride AND kind='commission';
  r := r || jsonb_build_object('id','B1','pass', v_hold.captured_gnf = 10000, 'got', v_hold.captured_gnf);
  SELECT balance_gnf INTO v_drv_after FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
  SELECT balance_gnf INTO v_master_after FROM public.wallets WHERE party_type='master' LIMIT 1;
  r := r || jsonb_build_object('id','B4','pass', (v_drv_before - v_drv_after) = 10000, 'delta', v_drv_before - v_drv_after);
  r := r || jsonb_build_object('id','B1b','pass', (v_master_after - v_master_before) = 10000, 'delta', v_master_after - v_master_before);
  SELECT count(*) INTO v_cnt FROM public.wallet_transactions WHERE related_entity = 'ride:'||v_ride::text AND type='ride_earning';
  r := r || jsonb_build_object('id','B4b_no_fake_earning','pass', v_cnt = 0, 'got', v_cnt);

  PERFORM public.ride_complete(v_ride); -- B2 replay
  SELECT balance_gnf INTO v_bal FROM public.wallets WHERE party_type='master' LIMIT 1;
  r := r || jsonb_build_object('id','B2','pass', v_bal = v_master_after, 'got', v_bal - v_master_after);

  -- ---------- B5: reserve 12k, final fare 10k lower ----------
  INSERT INTO public.rides(client_id, mode, pickup_lat, pickup_lng, fare_gnf, status, metadata)
  VALUES (v_cli,'moto',9.5,-13.7,120000,'pending', jsonb_build_object('payment_mode','cash'))
  RETURNING id INTO v_ride2;
  PERFORM public.ride_accept(v_ride2);
  UPDATE public.rides SET fare_gnf = 100000 WHERE id = v_ride2; -- authoritative final fare
  PERFORM public.ride_complete(v_ride2);
  SELECT captured_gnf, released_gnf INTO v_hold FROM public.mission_financial_holds
   WHERE source_module='ride' AND source_id=v_ride2 AND kind='commission';
  r := r || jsonb_build_object('id','B5','pass', v_hold.captured_gnf=10000 AND v_hold.released_gnf=2000,
                               'captured', v_hold.captured_gnf, 'released', v_hold.released_gnf);

  -- ---------- B7: Bonbonna ----------
  INSERT INTO public.rides(client_id, mode, pickup_lat, pickup_lng, fare_gnf, status, metadata)
  VALUES (v_cli,'toktok',9.5,-13.7,100000,'pending', jsonb_build_object('payment_mode','cash'))
  RETURNING id INTO v_ride3;
  PERFORM public.ride_accept(v_ride3);
  SELECT mission_type, amount_gnf INTO v_hold FROM public.mission_financial_holds
   WHERE source_module='ride' AND source_id=v_ride3 AND kind='commission';
  r := r || jsonb_build_object('id','B7','pass', v_hold.mission_type='bonbonna' AND v_hold.amount_gnf=10000,
                               'type', v_hold.mission_type, 'amount', v_hold.amount_gnf);

  -- ---------- B8: policy change after acceptance ----------
  PERFORM set_config('request.jwt.claims','',true);
  INSERT INTO public.finance_policies(mission_type, commission_bps, effective_from, enabled, note)
  VALUES ('bonbonna', 3000, now() - interval '1 second', true, 'QA S3 temp');
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_drv)::text, true);
  PERFORM public.ride_complete(v_ride3);
  SELECT captured_gnf INTO v_hold FROM public.mission_financial_holds
   WHERE source_module='ride' AND source_id=v_ride3 AND kind='commission';
  r := r || jsonb_build_object('id','B8','pass', v_hold.captured_gnf = 10000, 'got', v_hold.captured_gnf);

  -- ---------- A2 / E1: eligibility from ledger truth ----------
  UPDATE public.wallets SET balance_gnf = 0, held_gnf = 0 WHERE owner_user_id=v_drv AND party_type='driver';
  v_tmp := public.driver_financial_eligibility('ride', 100000, v_drv);
  r := r || jsonb_build_object('id','A2','pass', (v_tmp->>'eligible')::boolean = false, 'got', v_tmp->>'available_gnf');
  UPDATE public.wallets SET balance_gnf = 50000 WHERE owner_user_id=v_drv AND party_type='driver';
  v_tmp := public.driver_financial_eligibility('ride', 100000, v_drv);
  r := r || jsonb_build_object('id','E1','pass', (v_tmp->>'eligible')::boolean = true, 'got', v_tmp->>'available_gnf');

  -- ---------- A3: accept denied when balance consumed ----------
  UPDATE public.wallets SET balance_gnf = 0 WHERE owner_user_id=v_drv AND party_type='driver';
  INSERT INTO public.rides(client_id, mode, pickup_lat, pickup_lng, fare_gnf, status, metadata)
  VALUES (v_cli,'moto',9.5,-13.7,100000,'pending', jsonb_build_object('payment_mode','cash'))
  RETURNING id INTO v_ride4;
  BEGIN
    PERFORM public.ride_accept(v_ride4);
    r := r || jsonb_build_object('id','A3','pass', false, 'got','accepted');
  EXCEPTION WHEN OTHERS THEN
    SELECT count(*) INTO v_cnt FROM public.mission_financial_holds WHERE source_id=v_ride4;
    r := r || jsonb_build_object('id','A3','pass', v_cnt=0, 'err', SQLERRM);
  END;
  UPDATE public.wallets SET balance_gnf = 500000 WHERE owner_user_id=v_drv AND party_type='driver';

  -- ---------- A4: expired offer ----------
  INSERT INTO public.ride_offers(ride_id, driver_id, status, sent_at, expires_at, estimated_fare_gnf)
  VALUES (v_ride4, v_drv, 'pending', now() - interval '5 minutes', now() - interval '4 minutes', 100000)
  RETURNING id INTO v_off;
  BEGIN
    PERFORM public.driver_offer_accept(v_off);
    r := r || jsonb_build_object('id','A4','pass', false);
  EXCEPTION WHEN OTHERS THEN
    SELECT count(*) INTO v_cnt FROM public.mission_financial_holds WHERE source_id=v_ride4;
    r := r || jsonb_build_object('id','A4','pass', v_cnt=0 AND SQLERRM LIKE '%EXPIRED%', 'err', SQLERRM);
  END;

  -- ---------- A5: competing accept ----------
  PERFORM public.ride_accept(v_ride4);
  IF v_drv2 IS NOT NULL THEN
    INSERT INTO public.wallets(owner_user_id, party_type) VALUES (v_drv2,'driver')
      ON CONFLICT (owner_user_id, party_type) DO NOTHING;
    UPDATE public.wallets SET balance_gnf=500000, held_gnf=0, status='active'
      WHERE owner_user_id=v_drv2 AND party_type='driver';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_drv2)::text, true);
    BEGIN
      PERFORM public.ride_accept(v_ride4);
      r := r || jsonb_build_object('id','A5','pass', false);
    EXCEPTION WHEN OTHERS THEN
      SELECT count(*) INTO v_cnt FROM public.mission_financial_holds WHERE source_id=v_ride4 AND kind='commission';
      r := r || jsonb_build_object('id','A5','pass', v_cnt=1, 'err', SQLERRM);
    END;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_drv)::text, true);
  END IF;

  -- ---------- F1: driver cannot call settlement primitive ----------
  BEGIN
    PERFORM public.driver_mission_commission_capture('ride', v_ride4, 100000);
    r := r || jsonb_build_object('id','F1','pass', false);
  EXCEPTION WHEN OTHERS THEN
    r := r || jsonb_build_object('id','F1','pass', SQLERRM LIKE '%Not authorized%', 'err', SQLERRM);
  END;

  -- ---------- F2: driver cannot force final fare ----------
  PERFORM public.ride_complete(v_ride4, 999999999);
  SELECT captured_gnf INTO v_hold FROM public.mission_financial_holds
   WHERE source_module='ride' AND source_id=v_ride4 AND kind='commission';
  r := r || jsonb_build_object('id','F2','pass', v_hold.captured_gnf = 10000, 'got', v_hold.captured_gnf);

  -- ---------- F4: snapshot immutable ----------
  BEGIN
    UPDATE public.rides SET metadata = metadata || jsonb_build_object('finance_snapshot', '{"commission_bps":0}'::jsonb)
     WHERE id = v_ride4;
    r := r || jsonb_build_object('id','F4','pass', false);
  EXCEPTION WHEN OTHERS THEN
    r := r || jsonb_build_object('id','F4','pass', SQLERRM LIKE '%IMMUTABLE%', 'err', SQLERRM);
  END;

  -- ---------- D1/D2/D3: cancellation ----------
  INSERT INTO public.rides(client_id, mode, pickup_lat, pickup_lng, fare_gnf, status, metadata)
  VALUES (v_cli,'moto',9.5,-13.7,100000,'pending', jsonb_build_object('payment_mode','cash'))
  RETURNING id INTO v_ride;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_cli)::text, true);
  PERFORM public.ride_cancel(v_ride, 'QA before dispatch');
  SELECT amount_gnf, stage INTO v_hold FROM public.customer_cancellation_debts WHERE source_id = v_ride;
  r := r || jsonb_build_object('id','D1','pass', v_hold.amount_gnf=5000 AND v_hold.stage='before_dispatch','got',v_hold.amount_gnf);

  INSERT INTO public.rides(client_id, mode, pickup_lat, pickup_lng, fare_gnf, status, metadata)
  VALUES (v_cli,'moto',9.5,-13.7,100000,'pending', jsonb_build_object('payment_mode','cash'))
  RETURNING id INTO v_ride2;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_drv)::text, true);
  PERFORM public.ride_accept(v_ride2);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_cli)::text, true);
  PERFORM public.ride_cancel(v_ride2, 'QA after dispatch');
  SELECT amount_gnf, stage INTO v_hold FROM public.customer_cancellation_debts WHERE source_id = v_ride2;
  r := r || jsonb_build_object('id','D2','pass', v_hold.amount_gnf=10000 AND v_hold.stage='after_dispatch','got',v_hold.amount_gnf);
  SELECT state INTO v_txt FROM public.mission_financial_holds WHERE source_id=v_ride2 AND kind='commission';
  r := r || jsonb_build_object('id','D_reserve_released','pass', v_txt='released','got',v_txt);

  INSERT INTO public.rides(client_id, mode, pickup_lat, pickup_lng, fare_gnf, status, metadata)
  VALUES (v_cli,'moto',9.5,-13.7,100000,'pending', jsonb_build_object('payment_mode','cash'))
  RETURNING id INTO v_ride3;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_drv)::text, true);
  PERFORM public.ride_accept(v_ride3);
  PERFORM public.ride_cancel(v_ride3, 'QA driver caused');
  SELECT amount_gnf, state INTO v_hold FROM public.customer_cancellation_debts WHERE source_id = v_ride3;
  r := r || jsonb_build_object('id','D3_D4','pass', COALESCE(v_hold.amount_gnf,0)=0 AND v_hold.state='exempt','got',v_hold.amount_gnf);
  PERFORM public.ride_cancel(v_ride3, 'QA replay');
  SELECT count(*) INTO v_cnt FROM public.customer_cancellation_debts WHERE source_id=v_ride3;
  r := r || jsonb_build_object('id','D5','pass', v_cnt=1,'got',v_cnt);

  -- ---------- C1/C2: Chop Pay completion ----------
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_cli)::text, true);
  UPDATE public.wallets SET balance_gnf=300000, held_gnf=0 WHERE owner_user_id=v_cli AND party_type='client';
  SELECT id INTO v_off FROM public.wallet_hold(100000, 'qa-s3-choppay', 'QA Chop Pay ride hold');
  INSERT INTO public.rides(client_id, mode, pickup_lat, pickup_lng, fare_gnf, status, hold_tx_id, metadata)
  VALUES (v_cli,'moto',9.5,-13.7,100000,'pending', v_off, jsonb_build_object('payment_mode','choppay'))
  RETURNING id INTO v_ride4;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_drv)::text, true);
  PERFORM public.ride_accept(v_ride4);
  SELECT balance_gnf INTO v_drv_before FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
  SELECT balance_gnf INTO v_master_before FROM public.wallets WHERE party_type='master' LIMIT 1;
  PERFORM public.ride_complete(v_ride4);
  SELECT balance_gnf INTO v_drv_after FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
  SELECT balance_gnf INTO v_master_after FROM public.wallets WHERE party_type='master' LIMIT 1;
  r := r || jsonb_build_object('id','C1','pass', (v_drv_after - v_drv_before)=90000 AND (v_master_after-v_master_before)=10000,
                               'driver_delta', v_drv_after-v_drv_before, 'master_delta', v_master_after-v_master_before,
                               'settlement_error', (SELECT metadata->>'settlement_error' FROM public.rides WHERE id=v_ride4));
  PERFORM public.ride_complete(v_ride4);
  SELECT balance_gnf INTO v_bal FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
  r := r || jsonb_build_object('id','C2','pass', v_bal = v_drv_after, 'got', v_bal - v_drv_after);
  SELECT state INTO v_txt FROM public.mission_financial_holds WHERE source_id=v_ride4 AND kind='commission';
  r := r || jsonb_build_object('id','C_reserve_released','pass', v_txt='released', 'got', v_txt);

  -- ---------- G1: journals zero-sum ----------
  SELECT COALESCE(sum(amount_gnf),0) INTO v_sum FROM public.ledger_postings p
   WHERE p.journal_id IN (SELECT id FROM public.ledger_journals WHERE source_module='ride');
  r := r || jsonb_build_object('id','G1','pass', v_sum = 0, 'got', v_sum);

  RAISE EXCEPTION 'QA_S3_RESULT:%', r::text;
END $$;

CREATE OR REPLACE FUNCTION public._qa_s3_run()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_msg text;
BEGIN
  BEGIN
    PERFORM public._qa_s3_inner();
    RETURN jsonb_build_object('error','harness did not raise');
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
  END;
  IF position('QA_S3_RESULT:' in v_msg) > 0 THEN
    RETURN jsonb_build_object('results', substr(v_msg, position('QA_S3_RESULT:' in v_msg) + 13)::jsonb);
  END IF;
  RETURN jsonb_build_object('fatal', v_msg);
END $$;
