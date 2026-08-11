CREATE OR REPLACE FUNCTION public._qa_s13_run2()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r jsonb := '[]'::jsonb;
  v_cust uuid; v_d1 uuid; v_d2 uuid; v_d3 uuid; v_god uuid;
  v_ride uuid; v_ride2 uuid; v_err text; v_n bigint; v_res jsonb; v_row public.rides;
  v_master0 bigint; v_master1 bigint; v_flags0 jsonb; v_flags1 jsonb;
  v_bal0 bigint; v_bal1 bigint; v_held bigint; v_mb0 bigint; v_mb1 bigint;
  v_q jsonb; v_promo bigint;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;

  BEGIN
    v_cust := gen_random_uuid(); v_d1 := gen_random_uuid(); v_d2 := gen_random_uuid();
    v_d3 := gen_random_uuid(); v_god := gen_random_uuid();
    PERFORM public._qa_s13_user(v_cust,'cust');
    PERFORM public._qa_s13_user(v_d1,'d1');
    PERFORM public._qa_s13_user(v_d2,'d2');
    PERFORM public._qa_s13_user(v_d3,'d3');
    PERFORM public._qa_s13_user(v_god,'god');
    PERFORM public._qa_s13_admin(v_god);

    INSERT INTO public.driver_profiles(user_id,status,vehicle_type,id_doc_url,vehicle_photo_url)
    VALUES (v_d1,'approved','moto','x','y'),(v_d2,'approved','moto','x','y'),(v_d3,'pending','moto',NULL,NULL)
    ON CONFLICT (user_id) DO UPDATE SET status=EXCLUDED.status;

    PERFORM public._qa_s13_wallet(v_cust,'client',900000,0);
    PERFORM public._qa_s13_wallet(v_d1,'driver',100000,0);
    PERFORM public._qa_s13_wallet(v_d2,'driver',1000,0);   -- insufficient
    PERFORM public._qa_s13_wallet(v_d3,'driver',100000,0);

    PERFORM public._qa_s13_flag('driver_balance_gate_enabled', true);

    -- ---------- A1/A2/A3/A4: acceptance under the Stage 1 gate ----------
    INSERT INTO public.rides(client_id, mode, pickup_lat, pickup_lng, dest_lat, dest_lng, fare_gnf, metadata)
    VALUES (v_cust,'moto',9.5,-13.7,9.6,-13.6,100000,'{"payment_mode":"cash"}'::jsonb)
    RETURNING id INTO v_ride;
    INSERT INTO public.ride_offers(ride_id, driver_id, status, expires_at)
    VALUES (v_ride, v_d1, 'pending', now() + interval '5 min'),
           (v_ride, v_d2, 'pending', now() + interval '5 min');

    -- insufficient balance denies BEFORE any mutation
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_d2), true);
    BEGIN v_row := public.ride_accept(v_ride); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A2.1 insufficient driver balance denies acceptance',
      v_err LIKE '%INSUFFICIENT_DRIVER_BALANCE%', v_err);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds WHERE source_id = v_ride;
    r := r || public._qa_s13_ok('A2.2 denial created zero holds', v_n = 0, v_n::text);
    SELECT driver_id IS NULL INTO v_err FROM public.rides WHERE id = v_ride;
    r := r || public._qa_s13_ok('A2.3 denial left the ride unassigned',
      (SELECT driver_id IS NULL FROM public.rides WHERE id = v_ride));

    -- sufficient balance reserves exactly the frozen commission
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_d1), true);
    v_row := public.ride_accept(v_ride);
    SELECT count(*), COALESCE(sum(amount_gnf),0) INTO v_n, v_held
      FROM public.mission_financial_holds WHERE source_id = v_ride AND kind='commission';
    r := r || public._qa_s13_ok('A1.1 exactly one commission hold created', v_n = 1, v_n::text);
    r := r || public._qa_s13_ok('A1.2 reserve = 10% of fare (10000)', v_held = 10000, v_held::text);
    SELECT held_gnf INTO v_held FROM public.wallets WHERE owner_user_id=v_d1 AND party_type='driver';
    r := r || public._qa_s13_ok('A1.3 wallet held_gnf reflects the reserve', v_held = 10000, v_held::text);

    -- duplicate acceptance is inert
    v_row := public.ride_accept(v_ride);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds WHERE source_id = v_ride;
    r := r || public._qa_s13_ok('A3.1 duplicate accept creates no second hold', v_n = 1, v_n::text);

    -- competing driver cannot take over
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_d2), true);
    BEGIN v_row := public.ride_accept(v_ride); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A4.1 competing acceptance cannot create double ownership',
      v_err <> 'NO_ERROR', v_err);

    -- ---------- A11: pickup verification required before money moves ----------
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_d1), true);
    BEGIN v_row := public.ride_complete(v_ride, NULL, NULL); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A11.1 unverified pickup cannot advance money',
      v_err LIKE '%PICKUP_CONFIRMATION_REQUIRED%', v_err);
    SELECT state INTO v_err FROM public.mission_financial_holds WHERE source_id=v_ride AND kind='commission';
    r := r || public._qa_s13_ok('A11.2 commission hold untouched by the refused completion',
      v_err = 'held', v_err);

    -- ---------- A5/A6: completion captures exactly once ----------
    UPDATE public.rides SET status='in_progress',
      metadata = metadata || '{"phase":"on_trip","pickup_confirmed_by":"customer"}'::jsonb
     WHERE id = v_ride;
    SELECT balance_gnf INTO v_bal0 FROM public.wallets WHERE owner_user_id=v_d1 AND party_type='driver';
    SELECT balance_gnf INTO v_mb0 FROM public.wallets WHERE party_type='master' LIMIT 1;
    v_row := public.ride_complete(v_ride, NULL, NULL);
    SELECT balance_gnf INTO v_bal1 FROM public.wallets WHERE owner_user_id=v_d1 AND party_type='driver';
    SELECT balance_gnf INTO v_mb1 FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s13_ok('A5.1 cash ride commission taken from driver balance (10000)',
      v_bal0 - v_bal1 = 10000, format('%s -> %s', v_bal0, v_bal1));
    r := r || public._qa_s13_ok('A5.2 commission lands in the platform master wallet (10000)',
      v_mb1 - v_mb0 = 10000, format('%s -> %s', v_mb0, v_mb1));
    SELECT held_gnf INTO v_held FROM public.wallets WHERE owner_user_id=v_d1 AND party_type='driver';
    r := r || public._qa_s13_ok('A5.3 reserve fully consumed, nothing left held', v_held = 0, v_held::text);

    -- offline retry / duplicate completion
    v_row := public.ride_complete(v_ride, NULL, NULL);
    v_row := public.ride_complete(v_ride, NULL, NULL);
    r := r || public._qa_s13_ok('A6.1 duplicate completion returns authoritative existing result',
      v_row.status = 'completed', v_row.status::text);
    SELECT balance_gnf INTO v_bal0 FROM public.wallets WHERE owner_user_id=v_d1 AND party_type='driver';
    SELECT balance_gnf INTO v_mb0 FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s13_ok('A6.2 duplicate completion moved 0 additional GNF (driver)',
      v_bal0 = v_bal1, format('%s vs %s', v_bal0, v_bal1));
    r := r || public._qa_s13_ok('A6.3 duplicate completion moved 0 additional GNF (master)',
      v_mb0 = v_mb1, format('%s vs %s', v_mb0, v_mb1));
    SELECT count(*) INTO v_n FROM public.mission_financial_holds WHERE source_id=v_ride AND kind='commission';
    r := r || public._qa_s13_ok('A6.4 still exactly one commission hold record', v_n = 1, v_n::text);

    -- ---------- A10: restricted account cannot create new exposure ----------
    UPDATE public.driver_profiles SET status='suspended' WHERE user_id = v_d2;
    INSERT INTO public.rides(client_id, mode, pickup_lat, pickup_lng, dest_lat, dest_lng, fare_gnf, metadata)
    VALUES (v_cust,'moto',9.5,-13.7,9.6,-13.6,100000,'{"payment_mode":"cash"}'::jsonb)
    RETURNING id INTO v_ride2;
    INSERT INTO public.ride_offers(ride_id, driver_id, status, expires_at)
    VALUES (v_ride2, v_d2, 'pending', now() + interval '5 min');
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_d2), true);
    BEGIN v_row := public.ride_accept(v_ride2); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A10.1 suspended driver cannot create new financial exposure',
      v_err <> 'NO_ERROR', v_err);

    -- ---------- A9: starter credit entitlement ----------
    PERFORM public._qa_s13_flag('driver_starter_credit_enabled', true);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    v_res := public.driver_starter_credit_grant(v_d3);
    r := r || public._qa_s13_ok('A9.1 unapproved/unverified driver gets no starting credit',
      v_res->>'status' = 'not_eligible', v_res::text);

    v_res := public.driver_starter_credit_grant(v_d1);
    r := r || public._qa_s13_ok('A9.2 approved + verified driver granted exactly 25000 GNF restricted',
      v_res->>'status' = 'granted' AND (v_res->>'granted_gnf')::bigint = 25000, v_res::text);
    v_res := public.driver_starter_credit_grant(v_d1);
    r := r || public._qa_s13_ok('A9.3 second grant attempt is inert (already_granted)',
      v_res->>'status' = 'already_granted', v_res::text);
    SELECT COALESCE(sum(granted_gnf),0) INTO v_promo FROM public.driver_promo_credits WHERE driver_user_id=v_d1;
    r := r || public._qa_s13_ok('A9.4 exactly one promo grant of 25000 exists', v_promo = 25000, v_promo::text);

    -- duplicate identity routes to review, never a second grant
    INSERT INTO public.profiles(user_id, phone) VALUES (v_d2,'+224622000111'), (v_god,'+224622000111')
      ON CONFLICT (user_id) DO UPDATE SET phone = EXCLUDED.phone;
    UPDATE public.driver_profiles SET status='approved', id_doc_url='x', vehicle_photo_url='y' WHERE user_id=v_d2;
    v_res := public.driver_starter_credit_grant(v_d2);
    r := r || public._qa_s13_ok('A9.5 duplicate identity signal routes to review, grants 0',
      v_res->>'status' = 'needs_review' AND (v_res->>'granted_gnf')::bigint = 0, v_res::text);

    -- ---------- A12: cancellation responsibility + frozen fee bases ----------
    PERFORM public._qa_s13_flag('cancellation_policy_enabled', true);
    v_q := public._cancellation_compute(
      public.finance_policy_snapshot('ride', now(), 'cash', 100000, 0, 0, 0, false),
      'before_dispatch', 100000, 0, 0, 'customer');
    r := r || public._qa_s13_ok('A12.1 customer cancellation before dispatch = 5% of fare (5000)',
      (v_q->>'fee_gnf')::bigint = 5000, v_q::text);
    v_q := public._cancellation_compute(
      public.finance_policy_snapshot('ride', now(), 'cash', 100000, 0, 0, 0, false),
      'after_dispatch', 100000, 0, 0, 'customer');
    r := r || public._qa_s13_ok('A12.2 customer cancellation after dispatch = 10% of fare (10000)',
      (v_q->>'fee_gnf')::bigint = 10000, v_q::text);
    v_q := public._cancellation_compute(
      public.finance_policy_snapshot('ride', now(), 'cash', 100000, 0, 0, 0, false),
      'after_dispatch', 100000, 0, 0, 'driver');
    r := r || public._qa_s13_ok('A12.3 driver-caused failure waives the customer fee',
      (v_q->>'fee_gnf')::bigint = 0, v_q::text);
    v_q := public._cancellation_compute(
      public.finance_policy_snapshot('ride', now(), 'cash', 100000, 0, 0, 0, false),
      'after_dispatch', 100000, 0, 0, 'platform');
    r := r || public._qa_s13_ok('A12.4 platform/provider-caused failure waives the customer fee',
      (v_q->>'fee_gnf')::bigint = 0, v_q::text);

    -- ---------- A13: every fixture journal is zero-sum ----------
    SELECT count(*) INTO v_n FROM (
      SELECT j.id FROM public.ledger_journals j
       JOIN public.ledger_postings p ON p.journal_id = j.id
       GROUP BY j.id HAVING sum(p.amount_gnf) <> 0) z;
    r := r || public._qa_s13_ok('A13.1 no imbalanced journal after ride fixtures', v_n = 0, v_n::text);
    SELECT COALESCE(sum(amount_gnf),0) INTO v_n FROM public.ledger_postings;
    r := r || public._qa_s13_ok('A13.2 global ledger sum is zero', v_n = 0, v_n::text);

    RAISE EXCEPTION 'QA_S13_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_S13_ROLLBACK' THEN
      r := r || public._qa_s13_ok('HARNESS_PART2_UNEXPECTED_ABORT', false, SQLERRM);
    END IF;
  END;

  PERFORM set_config('request.jwt.claims', '', true);
  SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;
  r := r || public._qa_s13_ok('Z2.1 master wallet DEF-FIN-001 unchanged (-100435)',
    v_master1 = v_master0 AND v_master1 = -100435, v_master1::text);
  r := r || public._qa_s13_ok('Z2.2 live feature flags byte-identical after fixture rollback',
    v_flags1 = v_flags0, NULL);

  RETURN public._qa_s13_summary(2, r);
END $$;
REVOKE ALL ON FUNCTION public._qa_s13_run2() FROM PUBLIC, anon, authenticated;

SELECT public._qa_s13_run2();