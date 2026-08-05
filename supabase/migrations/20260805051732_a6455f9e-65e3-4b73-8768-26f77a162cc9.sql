CREATE OR REPLACE FUNCTION public._qa_slice1_run()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  r jsonb := '[]'::jsonb;
  d uuid := gen_random_uuid();
  c uuid := gen_random_uuid();
  store uuid;
  sid1 uuid := gen_random_uuid();
  sid2 uuid := gen_random_uuid();
  sid3 uuid := gen_random_uuid();
  sid4 uuid := gen_random_uuid();
  payid uuid; debtid uuid;
  j jsonb; e text; n int; b bigint;

  PROCEDURE_NOOP int;
BEGIN
  -- ---------- fixtures ----------
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data)
  VALUES
   (d,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
    'qa-driver-'||d::text||'@qa.invalid','x',now(),now(),now(),'{}','{}'),
   (c,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
    'qa-client-'||c::text||'@qa.invalid','x',now(),now(),now(),'{}','{}');

  INSERT INTO public.profiles (user_id, full_name, phone)
  VALUES (d,'QA Driver','+224600000001'),(c,'QA Client','+224600000002')
  ON CONFLICT (user_id) DO UPDATE SET phone = EXCLUDED.phone;

  INSERT INTO public.driver_profiles (user_id, status, vehicle_type, id_doc_url, vehicle_photo_url)
  VALUES (d,'approved','moto','qa://id','qa://veh')
  ON CONFLICT (user_id) DO UPDATE SET status='approved', id_doc_url='qa://id', vehicle_photo_url='qa://veh';

  INSERT INTO public.wallets (owner_user_id, party_type) VALUES (d,'driver'),(c,'client')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.wallets (owner_user_id, party_type) VALUES (NULL,'master')
  ON CONFLICT DO NOTHING;

  SELECT id INTO store FROM public.merchant_stores LIMIT 1;

  UPDATE public.feature_flags SET enabled = true WHERE key = 'driver_starter_credit_enabled';

  -- ---------- 1. restricted starter credit ----------
  j := public.driver_starter_credit_grant(d);
  r := r || jsonb_build_object('case','1 starter credit granted once',
        'expected','granted 25000','actual',j,
        'pass', j->>'status' = 'granted' AND (j->>'granted_gnf')::bigint = 25000);

  j := public.driver_starter_credit_grant(d);
  r := r || jsonb_build_object('case','2 starter credit replay is inert',
        'expected','already_granted','actual',j,'pass', j->>'status' = 'already_granted');

  -- ---------- 3. restricted funds are not withdrawable ----------
  j := public.driver_balance_summary(d);
  r := r || jsonb_build_object('case','3 restricted excluded from withdrawable',
        'expected','withdrawable 0 of 25000','actual',j,
        'pass', COALESCE((j->>'withdrawable_gnf')::bigint, -1) = 0);

  BEGIN
    PERFORM public.driver_payout_hold_place(gen_random_uuid(), d, 10000);
    e := 'NO_ERROR';
  EXCEPTION WHEN OTHERS THEN e := SQLERRM;
  END;
  r := r || jsonb_build_object('case','4 payout cannot reserve restricted credit',
        'expected','INSUFFICIENT_WITHDRAWABLE_BALANCE','actual',e,
        'pass', e LIKE '%INSUFFICIENT_WITHDRAWABLE_BALANCE%');

  -- fixture: unrestricted earnings
  UPDATE public.wallets SET balance_gnf = balance_gnf + 200000
   WHERE owner_user_id = d AND party_type = 'driver';
  UPDATE public.wallets SET balance_gnf = balance_gnf + 300000
   WHERE owner_user_id = c AND party_type = 'client';

  -- ---------- 5-8. basis correctness ----------
  j := public.finance_mission_requirement_v2('envoyer',0,0,20000,500000,'choppay');
  r := r || jsonb_build_object('case','5 Envoyer collateral 75% of declared value',
        'expected','375000','actual',j->'collateral_gnf',
        'pass',(j->>'collateral_gnf')::bigint = 375000);
  r := r || jsonb_build_object('case','6 Envoyer fee basis is the delivery fee',
        'expected','fee_basis delivery_fee, fee 200 on 20000','actual',
        jsonb_build_object('fee_basis',j->>'fee_basis','fee',j->>'platform_fee_gnf'),
        'pass', j->>'fee_basis' = 'delivery_fee' AND (j->>'platform_fee_gnf')::bigint = 200);
  r := r || jsonb_build_object('case','7 Envoyer delivery commission is 0%',
        'expected','0','actual',j->'commission_gnf','pass',(j->>'commission_gnf')::bigint = 0);

  j := public.finance_mission_requirement_v2('envoyer',0,0,20000,600000,'choppay');
  r := r || jsonb_build_object('case','8 declared value above cap is rejected',
        'expected','true','actual',j->'declared_value_exceeds_cap',
        'pass',(j->>'declared_value_exceeds_cap')::boolean);

  j := public.finance_mission_requirement_v2('repas',0,120000,20000,0,'choppay');
  r := r || jsonb_build_object('case','9 Repas Chop Pay collateral 50% of subtotal only',
        'expected','60000 collateral, fee 1200 on subtotal, no cash funding','actual',
        jsonb_build_object('collateral',j->>'collateral_gnf','fee',j->>'platform_fee_gnf',
                           'cash',j->>'cash_funding_gnf'),
        'pass',(j->>'collateral_gnf')::bigint = 60000
           AND (j->>'platform_fee_gnf')::bigint = 1200
           AND (j->>'cash_funding_gnf')::bigint = 0);

  j := public.finance_mission_requirement_v2('repas',0,120000,20000,0,'cash');
  r := r || jsonb_build_object('case','10 Repas cash order funds 100% of subtotal, no collateral',
        'expected','cash 120000, collateral 0','actual',
        jsonb_build_object('cash',j->>'cash_funding_gnf','collateral',j->>'collateral_gnf'),
        'pass',(j->>'cash_funding_gnf')::bigint = 120000 AND (j->>'collateral_gnf')::bigint = 0);

  j := public.finance_mission_requirement_v2('ride',50000,0,0,0,'cash');
  r := r || jsonb_build_object('case','11 Ride commission 10% of fare, no transaction fee',
        'expected','5000 / 0','actual',
        jsonb_build_object('commission',j->>'commission_gnf','fee',j->>'platform_fee_gnf'),
        'pass',(j->>'commission_gnf')::bigint = 5000 AND (j->>'platform_fee_gnf')::bigint = 0);

  -- ---------- 12-15. driver hold lifecycle ----------
  j := public.driver_mission_hold_place('ride','ride',sid1,0,d,false,ARRAY['commission'],50000,0,0,0,'cash');
  r := r || jsonb_build_object('case','12 commission reserve placed once',
        'expected','held 5000','actual',j,
        'pass', j->>'status' = 'held' AND (j->>'total_gnf')::bigint = 5000);

  j := public.driver_mission_hold_place('ride','ride',sid1,0,d,false,ARRAY['commission'],50000,0,0,0,'cash');
  r := r || jsonb_build_object('case','13 replayed placement writes nothing',
        'expected','already_held','actual',j,'pass', j->>'status' = 'already_held');

  SELECT promo_gnf INTO b FROM public.mission_financial_holds
   WHERE source_id = sid1 AND kind = 'commission';
  r := r || jsonb_build_object('case','14 hold records its restricted/unrestricted source',
        'expected','promo portion attributed','actual',b,'pass', b IS NOT NULL);

  j := public.driver_mission_commission_capture('ride',sid1,40000);
  r := r || jsonb_build_object('case','15 capture uses the snapshot and releases the excess',
        'expected','captured 4000, released 1000','actual',j,
        'pass',(j->>'captured_gnf')::bigint = 4000 AND (j->>'released_excess_gnf')::bigint = 1000);

  j := public.driver_mission_commission_capture('ride',sid1,40000);
  r := r || jsonb_build_object('case','16 capture cannot run twice',
        'expected','already_resolved','actual',j,'pass', j->>'status' = 'already_resolved');

  -- ---------- 17. release returns to the original bucket ----------
  PERFORM public.driver_mission_hold_place('envoyer','package',sid2,0,d,false,
            ARRAY['collateral'],0,0,20000,100000,'choppay');
  j := public.driver_mission_hold_release('package',sid2,'collateral','QA release');
  r := r || jsonb_build_object('case','17 collateral release returns full amount',
        'expected','75000','actual',j,'pass',(j->>'released_gnf')::bigint = 75000);

  -- ---------- 18-20. customer Chop Pay order ----------
  j := public.chop_pay_customer_hold_place('repas',sid3,140000,'repas',c,false);
  r := r || jsonb_build_object('case','18 customer order hold placed',
        'expected','held 140000','actual',j,'pass', j->>'status' = 'held');

  BEGIN
    PERFORM public.chop_pay_customer_capture('repas',sid3,store,120000,d,20000,0,1200,false);
    e := 'NO_ERROR';
  EXCEPTION WHEN OTHERS THEN e := SQLERRM;
  END;
  r := r || jsonb_build_object('case','19 an inexact split is refused',
        'expected','SPLIT_MUST_BE_EXACT or SPLIT_EXCEEDS_HOLD','actual',e,
        'pass', e LIKE '%SPLIT%');

  j := public.chop_pay_customer_capture('repas',sid3,store,118800,d,20000,0,1200,false);
  r := r || jsonb_build_object('case','20 exact split captures merchant + earning + fee',
        'expected','140000 captured','actual',j,
        'pass',(j->>'captured_gnf')::bigint = 140000);

  -- ---------- 21-24. merchant payable ----------
  IF store IS NOT NULL THEN
    j := public.merchant_payable_create('repas',sid3,store,118800,0,'repas','{}',false);
    payid := (j->>'payable_id')::uuid;
    r := r || jsonb_build_object('case','21 merchant payable created',
          'expected','created','actual',j,'pass', j->>'status' = 'created');

    j := public.merchant_payable_fund('repas',sid3,store,'customer_choppay');
    r := r || jsonb_build_object('case','22 payable funded before preparation is authorised',
          'expected','funded + preparation_authorized','actual',j,
          'pass', j->>'status' = 'funded' AND (j->>'preparation_authorized')::boolean);

    PERFORM public.merchant_settlement_hold(payid);
    BEGIN
      PERFORM public.merchant_settlement_complete(payid, '');
      e := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN e := SQLERRM;
    END;
    r := r || jsonb_build_object('case','23 settlement without evidence is refused',
          'expected','SETTLEMENT_EVIDENCE_REQUIRED','actual',e,
          'pass', e LIKE '%SETTLEMENT_EVIDENCE_REQUIRED%');

    j := public.merchant_settlement_complete(payid,'OM-REF-QA-0001');
    r := r || jsonb_build_object('case','24 settlement with evidence succeeds once',
          'expected','settled','actual',j,'pass', j->>'status' = 'settled');
  END IF;

  -- ---------- 25-26. cancellation debt ----------
  j := public.customer_cancellation_debt_create('ride','ride',sid4,c,'ride','after_dispatch',50000,NULL,false);
  debtid := (j->>'debt_id')::uuid;
  r := r || jsonb_build_object('case','25 cancellation charge 10% after dispatch',
        'expected','5000','actual',j,'pass',(j->>'amount_gnf')::bigint = 5000);

  j := public.customer_cancellation_debt_collect(debtid);
  r := r || jsonb_build_object('case','26 cancellation debt collectable from Chop Pay',
        'expected','collected 5000','actual',j,'pass',(j->>'collected_gnf')::bigint = 5000);

  -- ---------- 27. claims reserve is never automatic ----------
  BEGIN
    PERFORM public.claims_reserve_allocate('package',sid2,100000,'ev','QA reason',c,d,100000,'envoyer',false);
    e := 'NO_ERROR';
  EXCEPTION WHEN OTHERS THEN e := SQLERRM;
  END;
  r := r || jsonb_build_object('case','27 claims reserve requires an explicit God Admin decision',
        'expected','rejected for a non-God-Admin caller','actual',e,
        'pass', e LIKE '%God Admin%');

  -- ---------- 28-30. journal invariants ----------
  SET CONSTRAINTS ALL IMMEDIATE;

  SELECT count(*) INTO n FROM (
    SELECT journal_id FROM public.ledger_postings
     GROUP BY journal_id HAVING sum(amount_gnf) <> 0) x;
  r := r || jsonb_build_object('case','28 every journal entry balances to zero',
        'expected','0 unbalanced','actual',n,'pass', n = 0);

  SELECT count(*) INTO n FROM public.ledger_journals;
  r := r || jsonb_build_object('case','29 journal entries were actually written',
        'expected','> 0','actual',n,'pass', n > 0);

  SELECT count(*) INTO n FROM public.ledger_journals g
   WHERE NOT EXISTS (SELECT 1 FROM public.ledger_postings p WHERE p.journal_id = g.id);
  r := r || jsonb_build_object('case','30 no journal entry exists without postings',
        'expected','0','actual',n,'pass', n = 0);

  RAISE EXCEPTION 'QA_RESULT:%', r::text;
END;
$fn$;

REVOKE ALL ON FUNCTION public._qa_slice1_run() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_slice1_run() TO service_role;