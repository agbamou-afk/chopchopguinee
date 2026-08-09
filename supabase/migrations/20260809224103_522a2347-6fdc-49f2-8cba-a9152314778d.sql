CREATE OR REPLACE FUNCTION public._qa_s3b_ok(p boolean) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$ SELECT CASE WHEN p THEN 'PASS' ELSE 'FAIL' END $$;

CREATE OR REPLACE FUNCTION public._qa_s3b_run() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  res jsonb := '{}'::jsonb;
  v_owner text := current_user;
  dv1 uuid := gen_random_uuid();
  dv2 uuid := gen_random_uuid();
  cu1 uuid := gen_random_uuid();
  q1 uuid; q2 uuid; q3 uuid; q4 uuid; q5 uuid;
  o uuid; t uuid;
  v jsonb; e jsonb; x bigint; y bigint; z bigint;
  m0 bigint; m1 bigint; d0 bigint; d1 bigint; c0 bigint; c1 bigint;
  v_master uuid; v_dw uuid; v_cw uuid;
  v_hold public.wallet_transactions;
  v_txt text;
  v_bad int;
BEGIN
  PERFORM public.wallet_ensure_master();
  SELECT id INTO v_master FROM public.wallets WHERE party_type='master' LIMIT 1;

  -- S1. PRIVILEGE MATRIX
  res := res || jsonb_build_object(
    'A.grant.wallet_internal_transfer.authenticated_denied',
      public._qa_s3b_ok(NOT has_function_privilege('authenticated','public.wallet_internal_transfer(uuid,text,uuid,text,bigint,text,text)','EXECUTE')),
    'A.grant.wallet_internal_transfer.anon_denied',
      public._qa_s3b_ok(NOT has_function_privilege('anon','public.wallet_internal_transfer(uuid,text,uuid,text,bigint,text,text)','EXECUTE')),
    'A.grant.wallet_internal_transfer.service_role_allowed',
      public._qa_s3b_ok(has_function_privilege('service_role','public.wallet_internal_transfer(uuid,text,uuid,text,bigint,text,text)','EXECUTE')),
    'B.grant.ride_accept.authenticated_denied',
      public._qa_s3b_ok(NOT has_function_privilege('authenticated','public.ride_accept(uuid)','EXECUTE')),
    'B.grant.driver_offer_accept.authenticated_allowed',
      public._qa_s3b_ok(has_function_privilege('authenticated','public.driver_offer_accept(uuid)','EXECUTE')),
    'D.grant.ride_dispatch.anon_denied',
      public._qa_s3b_ok(NOT has_function_privilege('anon','public.ride_dispatch(uuid)','EXECUTE')),
    'D.grant.ride_dispatch.authenticated_denied',
      public._qa_s3b_ok(NOT has_function_privilege('authenticated','public.ride_dispatch(uuid)','EXECUTE')),
    'D.grant.ride_request_dispatch.authenticated_allowed',
      public._qa_s3b_ok(has_function_privilege('authenticated','public.ride_request_dispatch(uuid)','EXECUTE')));

  -- S2. GUARD BODIES under role=authenticated
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    BEGIN
      PERFORM public.wallet_internal_transfer(dv1,'driver',NULL,'master',1000,'qa',NULL);
      res := res || jsonb_build_object('A.guard.direct_transfer_blocked','FAIL');
    EXCEPTION WHEN OTHERS THEN
      res := res || jsonb_build_object('A.guard.direct_transfer_blocked','PASS','A.guard.err',left(SQLERRM,60));
    END;
    BEGIN
      PERFORM public.ride_accept(gen_random_uuid());
      res := res || jsonb_build_object('B.guard.direct_ride_accept_blocked','FAIL');
    EXCEPTION WHEN OTHERS THEN
      res := res || jsonb_build_object('B.guard.direct_ride_accept_blocked','PASS','B.guard.err',left(SQLERRM,60));
    END;
    EXECUTE format('SET LOCAL ROLE %I', v_owner);
  EXCEPTION WHEN OTHERS THEN
    EXECUTE format('SET LOCAL ROLE %I', v_owner);
    res := res || jsonb_build_object('S2.role_switch_error', left(SQLERRM,90));
  END;

  -- FIXTURES
  INSERT INTO public.driver_profiles(user_id,status,vehicle_type,presence,capabilities)
  VALUES (dv1,'approved','moto','online',ARRAY['rides_moto']),
         (dv2,'approved','moto','online',ARRAY['rides_moto']);
  INSERT INTO public.driver_locations(user_id,lat,lng,status) VALUES (dv1,9.53,-13.68,'online');
  INSERT INTO public.wallets(owner_user_id,party_type,balance_gnf) VALUES (dv1,'driver',50000) RETURNING id INTO v_dw;
  INSERT INTO public.wallets(owner_user_id,party_type,balance_gnf) VALUES (dv2,'driver',50000);
  INSERT INTO public.wallets(owner_user_id,party_type,balance_gnf) VALUES (cu1,'client',200000) RETURNING id INTO v_cw;

  UPDATE public.feature_flags SET enabled=true WHERE key='driver_balance_gate_enabled';

  -- S3. ELIGIBILITY
  PERFORM set_config('request.jwt.claims','',true);
  e := public.driver_financial_eligibility('ride',100000,dv1);
  res := res || jsonb_build_object('A1.sufficient_balance_eligible', public._qa_s3b_ok((e->>'eligible')::boolean),
                               'A1.required_gnf', e->>'required_gnf', 'A1.available_gnf', e->>'available_gnf');

  UPDATE public.wallets SET balance_gnf=10000 WHERE id=v_dw;
  INSERT INTO public.driver_promo_credits(driver_user_id,identity_key,grant_key,granted_gnf,state,reason)
  VALUES (dv1,'qa:'||dv1::text,'qa-grant:'||dv1::text,10000,'active','qa');
  e := public.driver_financial_eligibility('ride',100000,dv1);
  res := res || jsonb_build_object('A7.promo_only_eligible', public._qa_s3b_ok((e->>'eligible')::boolean),
                               'A7.promo_available', (e->'balance')->>'promo_available_gnf');

  UPDATE public.wallets SET balance_gnf=15000 WHERE id=v_dw;
  e := public.driver_financial_eligibility('ride',100000,dv1);
  res := res || jsonb_build_object('A8.mixed_sources_eligible', public._qa_s3b_ok((e->>'eligible')::boolean),
    'A8.unrestricted_available', (e->'balance')->>'unrestricted_available_gnf',
    'A8.promo_available', (e->'balance')->>'promo_available_gnf');

  UPDATE public.wallets SET held_gnf=15000 WHERE id=v_dw;
  e := public.driver_financial_eligibility('ride',100000,dv1);
  res := res || jsonb_build_object('A9.held_funds_excluded', public._qa_s3b_ok(NOT (e->>'eligible')::boolean),
                               'A9.available_gnf', e->>'available_gnf');
  UPDATE public.wallets SET held_gnf=0, balance_gnf=50000 WHERE id=v_dw;

  UPDATE public.driver_profiles SET status='suspended' WHERE user_id=dv1;
  res := res || jsonb_build_object('A10.suspended_denied', public._qa_s3b_ok(NOT public._driver_finance_eligible(dv1)));
  UPDATE public.driver_profiles SET status='approved' WHERE user_id=dv1;
  DELETE FROM public.driver_promo_credits WHERE driver_user_id=dv1;

  -- S4. CASH RIDE 100k EXIT GATE
  INSERT INTO public.rides(client_id,mode,pickup_lat,pickup_lng,dest_lat,dest_lng,fare_gnf,metadata)
  VALUES (cu1,'moto',9.531,-13.681,9.55,-13.70,100000,jsonb_build_object('sandbox','true','payment_mode','cash'))
  RETURNING id INTO q1;

  PERFORM set_config('request.jwt.claims', public._as_user_claims(cu1), true);
  o := public.ride_request_dispatch(q1);
  res := res || jsonb_build_object('D.trusted_dispatch_creates_offer', public._qa_s3b_ok(o IS NOT NULL));

  PERFORM set_config('request.jwt.claims', public._as_user_claims(dv2), true);
  BEGIN
    PERFORM public.driver_offer_accept(o);
    res := res || jsonb_build_object('F3.cross_driver_offer_denied','FAIL');
  EXCEPTION WHEN OTHERS THEN
    res := res || jsonb_build_object('F3.cross_driver_offer_denied','PASS');
  END;

  PERFORM set_config('request.jwt.claims', public._as_user_claims(dv1), true);
  PERFORM public.driver_offer_accept(o);
  SELECT amount_gnf INTO x FROM public.mission_financial_holds
   WHERE source_module='ride' AND source_id=q1 AND kind='commission';
  res := res || jsonb_build_object('H.cash.reserve_gnf', x, 'H.cash.reserve_is_10000', public._qa_s3b_ok(x=10000));

  BEGIN
    PERFORM public.ride_complete(q1,NULL,NULL);
    res := res || jsonb_build_object('C.premature_complete_denied','FAIL');
  EXCEPTION WHEN OTHERS THEN
    res := res || jsonb_build_object('C.premature_complete_denied','PASS','C.premature_err',left(SQLERRM,60));
  END;

  PERFORM public.ride_set_phase(q1,'arrived');
  BEGIN
    PERFORM public.ride_complete(q1,NULL,NULL);
    res := res || jsonb_build_object('C.arrived_but_unconfirmed_complete_denied','FAIL');
  EXCEPTION WHEN OTHERS THEN
    res := res || jsonb_build_object('C.arrived_but_unconfirmed_complete_denied','PASS');
  END;

  SELECT metadata->>'pickup_code' INTO v_txt FROM public.rides WHERE id=q1;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(cu1), true);
  PERFORM public.ride_confirm_pickup(q1, v_txt);
  SELECT public._qa_s3b_ok(status='in_progress' AND metadata->>'phase'='on_trip'
      AND metadata->>'pickup_confirmed_by'='customer') INTO v_txt FROM public.rides WHERE id=q1;
  res := res || jsonb_build_object('G4.pickup_handshake', v_txt);

  BEGIN
    PERFORM public.ride_complete(q1,NULL,NULL);
    res := res || jsonb_build_object('C.customer_complete_denied','FAIL');
  EXCEPTION WHEN OTHERS THEN
    res := res || jsonb_build_object('C.customer_complete_denied','PASS');
  END;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(dv2), true);
  BEGIN
    PERFORM public.ride_complete(q1,NULL,NULL);
    res := res || jsonb_build_object('C.cross_driver_complete_denied','FAIL');
  EXCEPTION WHEN OTHERS THEN
    res := res || jsonb_build_object('C.cross_driver_complete_denied','PASS');
  END;

  SELECT balance_gnf INTO m0 FROM public.wallets WHERE id=v_master;
  SELECT balance_gnf INTO d0 FROM public.wallets WHERE id=v_dw;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(dv1), true);
  PERFORM public.ride_start(q1);
  PERFORM public.ride_complete(q1,NULL,NULL);
  SELECT balance_gnf INTO m1 FROM public.wallets WHERE id=v_master;
  SELECT balance_gnf INTO d1 FROM public.wallets WHERE id=v_dw;
  res := res || jsonb_build_object(
    'H.cash.platform_captured_10000', public._qa_s3b_ok(m1-m0=10000),
    'H.cash.platform_delta', m1-m0,
    'H.cash.driver_wallet_delta', d1-d0,
    'H.cash.no_90000_wallet_credit', public._qa_s3b_ok(d1-d0 = -10000));
  SELECT driver_earning_gnf, platform_fee_gnf INTO y, z FROM public.rides WHERE id=q1;
  res := res || jsonb_build_object('H.cash.economic_driver_earning_90000', public._qa_s3b_ok(y=90000),
                               'H.cash.recorded_commission_10000', public._qa_s3b_ok(z=10000));

  PERFORM public.ride_complete(q1,NULL,NULL);
  PERFORM public.ride_complete(q1,NULL,NULL);
  SELECT balance_gnf INTO x FROM public.wallets WHERE id=v_master;
  res := res || jsonb_build_object('G2.cash_replay_adds_zero', public._qa_s3b_ok(x=m1));

  SELECT jsonb_build_object('captured',captured_gnf,'promo',captured_promo_gnf,
                            'unrestricted',captured_unrestricted_gnf,'released',released_gnf,'state',state)
    INTO v FROM public.mission_financial_holds WHERE source_module='ride' AND source_id=q1 AND kind='commission';
  res := res || jsonb_build_object('B6.capture_attribution', v);

  SELECT count(*) INTO v_bad FROM (
    SELECT j.id FROM public.ledger_journals j JOIN public.ledger_postings p ON p.journal_id=j.id
     WHERE j.source_module='ride' AND j.source_id=q1 GROUP BY j.id HAVING SUM(p.amount_gnf)<>0) s;
  SELECT count(*) INTO x FROM public.ledger_journals WHERE source_module='ride' AND source_id=q1;
  res := res || jsonb_build_object('B3.cash_journals_count', x, 'B3.cash_journals_zero_sum', public._qa_s3b_ok(v_bad=0));

  BEGIN
    UPDATE public.ledger_postings SET amount_gnf = amount_gnf + 1
     WHERE journal_id IN (SELECT id FROM public.ledger_journals WHERE source_module='ride' AND source_id=q1);
    res := res || jsonb_build_object('T11.posting_update_denied','FAIL');
  EXCEPTION WHEN OTHERS THEN res := res || jsonb_build_object('T11.posting_update_denied','PASS'); END;
  BEGIN
    DELETE FROM public.ledger_journals WHERE source_module='ride' AND source_id=q1;
    res := res || jsonb_build_object('T11.journal_delete_denied','FAIL');
  EXCEPTION WHEN OTHERS THEN res := res || jsonb_build_object('T11.journal_delete_denied','PASS'); END;

  -- S4b. BONBONNA
  UPDATE public.wallets SET balance_gnf=50000, held_gnf=0 WHERE id=v_dw;
  UPDATE public.driver_profiles SET presence='online' WHERE user_id=dv1;
  INSERT INTO public.rides(client_id,mode,pickup_lat,pickup_lng,dest_lat,dest_lng,fare_gnf,metadata)
  VALUES (cu1,'toktok',9.531,-13.681,9.55,-13.70,100000,jsonb_build_object('sandbox','true','payment_mode','cash'))
  RETURNING id INTO q2;
  INSERT INTO public.ride_offers(ride_id,driver_id,status,sent_at,expires_at,estimated_fare_gnf)
  VALUES (q2,dv1,'pending',now(),now()+interval '60 seconds',100000) RETURNING id INTO o;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(dv1), true);
  PERFORM public.driver_offer_accept(o);
  SELECT amount_gnf, mission_type INTO x, v_txt FROM public.mission_financial_holds
   WHERE source_module='ride' AND source_id=q2 AND kind='commission';
  res := res || jsonb_build_object('H.bonbonna.reserve_10000', public._qa_s3b_ok(x=10000),
                               'H.bonbonna.mission_type', v_txt);
  PERFORM public.ride_set_phase(q2,'arrived');
  SELECT metadata->>'pickup_code' INTO v_txt FROM public.rides WHERE id=q2;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(cu1), true);
  PERFORM public.ride_confirm_pickup(q2, v_txt);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(dv1), true);
  PERFORM public.ride_start(q2);
  SELECT balance_gnf INTO m0 FROM public.wallets WHERE id=v_master;
  PERFORM public.ride_complete(q2,NULL,NULL);
  SELECT balance_gnf INTO m1 FROM public.wallets WHERE id=v_master;
  res := res || jsonb_build_object('H.bonbonna.platform_delta_10000', public._qa_s3b_ok(m1-m0=10000));

  -- S5. CHOP PAY RIDE 100k
  UPDATE public.wallets SET balance_gnf=50000, held_gnf=0 WHERE id=v_dw;
  UPDATE public.driver_profiles SET presence='online' WHERE user_id=dv1;
  INSERT INTO public.rides(client_id,mode,pickup_lat,pickup_lng,dest_lat,dest_lng,fare_gnf,metadata)
  VALUES (cu1,'moto',9.531,-13.681,9.55,-13.70,100000,jsonb_build_object('sandbox','true','payment_mode','chop_pay'))
  RETURNING id INTO q3;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(cu1), true);
  v_hold := public.wallet_hold(100000,'Course Chop Pay QA','ride:'||q3::text);
  UPDATE public.rides SET hold_tx_id=v_hold.id WHERE id=q3;
  INSERT INTO public.ride_offers(ride_id,driver_id,status,sent_at,expires_at,estimated_fare_gnf)
  VALUES (q3,dv1,'pending',now(),now()+interval '60 seconds',100000) RETURNING id INTO o;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(dv1), true);
  PERFORM public.driver_offer_accept(o);

  PERFORM set_config('request.jwt.claims','',true);
  BEGIN
    INSERT INTO public.finance_policies(mission_type, commission_bps, effective_from, notes)
    VALUES ('ride', 3000, now() - interval '1 minute', 'qa post-acceptance edit');
    res := res || jsonb_build_object('C4.policy_edit_applied','yes');
  EXCEPTION WHEN OTHERS THEN res := res || jsonb_build_object('C4.policy_edit_applied','skipped:'||left(SQLERRM,60)); END;

  PERFORM public.ride_set_phase(q3,'arrived');
  SELECT metadata->>'pickup_code' INTO v_txt FROM public.rides WHERE id=q3;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(cu1), true);
  PERFORM public.ride_confirm_pickup(q3, v_txt);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(dv1), true);
  PERFORM public.ride_start(q3);
  SELECT balance_gnf INTO m0 FROM public.wallets WHERE id=v_master;
  SELECT balance_gnf INTO d0 FROM public.wallets WHERE id=v_dw;
  SELECT balance_gnf INTO c0 FROM public.wallets WHERE id=v_cw;
  PERFORM public.ride_complete(q3,NULL,NULL);
  SELECT balance_gnf INTO m1 FROM public.wallets WHERE id=v_master;
  SELECT balance_gnf INTO d1 FROM public.wallets WHERE id=v_dw;
  SELECT balance_gnf INTO c1 FROM public.wallets WHERE id=v_cw;
  SELECT platform_fee_gnf INTO z FROM public.rides WHERE id=q3;
  res := res || jsonb_build_object(
    'H.choppay.customer_debit', c0-c1,
    'H.choppay.customer_capture_100000', public._qa_s3b_ok(c0-c1=100000),
    'H.choppay.driver_net_delta', d1-d0,
    'H.choppay.driver_net_90000', public._qa_s3b_ok(d1-d0=90000),
    'H.choppay.platform_delta', m1-m0,
    'H.choppay.platform_10000', public._qa_s3b_ok(m1-m0=10000),
    'C4.snapshot_split_unchanged_10pct', public._qa_s3b_ok(z=10000));
  SELECT state INTO v_txt FROM public.mission_financial_holds WHERE source_module='ride' AND source_id=q3 AND kind='commission';
  res := res || jsonb_build_object('H.choppay.reserve_state', v_txt);
  PERFORM public.ride_complete(q3,NULL,NULL);
  SELECT balance_gnf INTO x FROM public.wallets WHERE id=v_master;
  res := res || jsonb_build_object('G2.choppay_replay_adds_zero', public._qa_s3b_ok(x=m1));
  SELECT count(*) INTO v_bad FROM (
    SELECT j.id FROM public.ledger_journals j JOIN public.ledger_postings p ON p.journal_id=j.id
     WHERE j.source_module='ride' AND j.source_id=q3 GROUP BY j.id HAVING SUM(p.amount_gnf)<>0) s;
  res := res || jsonb_build_object('C3.choppay_journals_zero_sum', public._qa_s3b_ok(v_bad=0));
  DELETE FROM public.finance_policies WHERE notes='qa post-acceptance edit';

  -- C5. INSUFFICIENT HOLD
  UPDATE public.wallets SET balance_gnf=50000, held_gnf=0 WHERE id=v_dw;
  UPDATE public.driver_profiles SET presence='online' WHERE user_id=dv1;
  INSERT INTO public.rides(client_id,mode,pickup_lat,pickup_lng,dest_lat,dest_lng,fare_gnf,metadata)
  VALUES (cu1,'moto',9.531,-13.681,9.55,-13.70,100000,jsonb_build_object('sandbox','true','payment_mode','chop_pay'))
  RETURNING id INTO q4;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(cu1), true);
  v_hold := public.wallet_hold(40000,'Hold insuffisant QA','ride:'||q4::text);
  UPDATE public.rides SET hold_tx_id=v_hold.id WHERE id=q4;
  INSERT INTO public.ride_offers(ride_id,driver_id,status,sent_at,expires_at,estimated_fare_gnf)
  VALUES (q4,dv1,'pending',now(),now()+interval '60 seconds',100000) RETURNING id INTO o;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(dv1), true);
  PERFORM public.driver_offer_accept(o);
  PERFORM public.ride_set_phase(q4,'arrived');
  SELECT metadata->>'pickup_code' INTO v_txt FROM public.rides WHERE id=q4;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(cu1), true);
  PERFORM public.ride_confirm_pickup(q4, v_txt);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(dv1), true);
  PERFORM public.ride_start(q4);
  SELECT balance_gnf INTO m0 FROM public.wallets WHERE id=v_master;
  SELECT balance_gnf INTO d0 FROM public.wallets WHERE id=v_dw;
  BEGIN
    PERFORM public.ride_complete(q4,NULL,NULL);
    res := res || jsonb_build_object('C5.insufficient_hold_blocked','FAIL');
  EXCEPTION WHEN OTHERS THEN
    res := res || jsonb_build_object('C5.insufficient_hold_blocked','PASS','C5.err',left(SQLERRM,70));
  END;
  SELECT status::text INTO v_txt FROM public.rides WHERE id=q4;
  SELECT balance_gnf INTO m1 FROM public.wallets WHERE id=v_master;
  SELECT balance_gnf INTO d1 FROM public.wallets WHERE id=v_dw;
  res := res || jsonb_build_object('C5.ride_not_completed', public._qa_s3b_ok(v_txt<>'completed'),
     'C5.no_platform_capture', public._qa_s3b_ok(m1=m0),
     'C5.no_driver_credit', public._qa_s3b_ok(d1=d0));

  -- S6. CANCELLATIONS
  UPDATE public.feature_flags SET enabled=true WHERE key='cancellation_policy_enabled';
  INSERT INTO public.rides(client_id,mode,pickup_lat,pickup_lng,fare_gnf,metadata)
  VALUES (cu1,'moto',9.531,-13.681,100000,jsonb_build_object('sandbox','true','payment_mode','cash'))
  RETURNING id INTO q5;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(cu1), true);
  PERFORM public.ride_cancel(q5,'qa before dispatch');
  SELECT (metadata->>'cancellation_fee_gnf')::bigint INTO x FROM public.rides WHERE id=q5;
  res := res || jsonb_build_object('H.cancel.before_dispatch_5000', public._qa_s3b_ok(x=5000), 'H.cancel.before_fee', x);
  PERFORM public.ride_cancel(q5,'qa replay');
  SELECT count(*) INTO v_bad FROM public.customer_cancellation_debts WHERE source_id=q5;
  res := res || jsonb_build_object('H.cancel.replay_no_duplicate_debt', public._qa_s3b_ok(v_bad<=1));

  UPDATE public.wallets SET balance_gnf=50000, held_gnf=0 WHERE id=v_dw;
  UPDATE public.driver_profiles SET presence='online' WHERE user_id=dv1;
  INSERT INTO public.rides(client_id,mode,pickup_lat,pickup_lng,fare_gnf,metadata)
  VALUES (cu1,'moto',9.531,-13.681,100000,jsonb_build_object('sandbox','true','payment_mode','cash'))
  RETURNING id INTO q5;
  INSERT INTO public.ride_offers(ride_id,driver_id,status,sent_at,expires_at,estimated_fare_gnf)
  VALUES (q5,dv1,'pending',now(),now()+interval '60 seconds',100000) RETURNING id INTO o;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(dv1), true);
  PERFORM public.driver_offer_accept(o);
  PERFORM set_config('request.jwt.claims','',true);
  BEGIN
    INSERT INTO public.finance_policies(mission_type, commission_bps, cancel_after_dispatch_bps, effective_from, notes)
    VALUES ('ride', 1000, 4000, now() - interval '1 minute', 'qa cancel policy edit');
  EXCEPTION WHEN OTHERS THEN NULL; END;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(cu1), true);
  PERFORM public.ride_cancel(q5,'qa after dispatch');
  SELECT (metadata->>'cancellation_fee_gnf')::bigint INTO x FROM public.rides WHERE id=q5;
  res := res || jsonb_build_object('H.cancel.after_dispatch_10000', public._qa_s3b_ok(x=10000),
                               'D6.snapshot_survives_policy_change', public._qa_s3b_ok(x=10000),
                               'H.cancel.after_fee', x);
  DELETE FROM public.finance_policies WHERE notes='qa cancel policy edit';

  UPDATE public.wallets SET balance_gnf=50000, held_gnf=0 WHERE id=v_dw;
  UPDATE public.driver_profiles SET presence='online' WHERE user_id=dv1;
  INSERT INTO public.rides(client_id,mode,pickup_lat,pickup_lng,fare_gnf,metadata)
  VALUES (cu1,'moto',9.531,-13.681,100000,jsonb_build_object('sandbox','true','payment_mode','cash'))
  RETURNING id INTO q5;
  INSERT INTO public.ride_offers(ride_id,driver_id,status,sent_at,expires_at,estimated_fare_gnf)
  VALUES (q5,dv1,'pending',now(),now()+interval '60 seconds',100000) RETURNING id INTO o;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(dv1), true);
  PERFORM public.driver_offer_accept(o);
  PERFORM public.ride_cancel(q5,'qa driver caused');
  SELECT (metadata->>'cancellation_fee_gnf')::bigint INTO x FROM public.rides WHERE id=q5;
  SELECT count(*) INTO v_bad FROM public.customer_cancellation_debts WHERE source_id=q5;
  res := res || jsonb_build_object('D3.driver_caused_zero_fee', public._qa_s3b_ok(COALESCE(x,0)=0),
                               'D3.no_customer_debt', public._qa_s3b_ok(v_bad=0));
  UPDATE public.feature_flags SET enabled=false WHERE key='cancellation_policy_enabled';

  -- S7. TOP-UP RECOVERY
  UPDATE public.wallets SET balance_gnf=0, held_gnf=0 WHERE owner_user_id=dv1 AND party_type='driver';
  PERFORM set_config('request.jwt.claims','',true);
  e := public.driver_financial_eligibility('ride',100000,dv1);
  res := res || jsonb_build_object('E1.blocked_when_insufficient', public._qa_s3b_ok(NOT (e->>'eligible')::boolean));
  BEGIN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(dv1), true);
    SELECT (public.wallet_topup_om_create(50000, NULL)->>'id')::uuid INTO t;
    PERFORM set_config('request.jwt.claims','',true);
    PERFORM public.wallet_topup_om_credit(t, NULL);
    res := res || jsonb_build_object('E2.topup_pathway','executed');
  EXCEPTION WHEN OTHERS THEN
    res := res || jsonb_build_object('E2.topup_pathway','error:'||left(SQLERRM,120));
  END;
  SELECT balance_gnf INTO x FROM public.wallets WHERE owner_user_id=dv1 AND party_type='driver';
  PERFORM set_config('request.jwt.claims','',true);
  e := public.driver_financial_eligibility('ride',100000,dv1);
  res := res || jsonb_build_object('E2.balance_after_topup', x,
    'E2.eligible_after_topup', public._qa_s3b_ok((e->>'eligible')::boolean));

  -- G5 FLAGS
  UPDATE public.feature_flags SET enabled=false WHERE key='driver_balance_gate_enabled';
  SELECT jsonb_agg(key ORDER BY key) INTO v FROM public.feature_flags
   WHERE enabled AND key IN ('cancellation_policy_enabled','cash_order_funding_enabled','chop_pay_balance_enabled',
     'chop_pay_checkout_enabled','chop_pay_ecosystem_spend_enabled','chop_pay_enabled','chop_pay_p2p_enabled',
     'driver_balance_gate_enabled','driver_cashout_enabled','driver_starter_credit_enabled','envoyer_claims_enabled',
     'merchant_om_settlement_enabled','merchant_wallet_enabled','non_ride_transaction_fee_enabled',
     'om_topup_enabled','om_direct_checkout_enabled','wallet_public_enabled');
  res := res || jsonb_build_object('G5.enabled_finance_flags', v,
    'G5.only_om_topup', public._qa_s3b_ok(v = '["om_topup_enabled"]'::jsonb));

  RAISE EXCEPTION 'QA_S3B_RESULT %', res::text;
END $fn$;

REVOKE ALL ON FUNCTION public._qa_s3b_run() FROM PUBLIC;
REVOKE ALL ON FUNCTION public._qa_s3b_run() FROM anon;
REVOKE ALL ON FUNCTION public._qa_s3b_run() FROM authenticated;