REVOKE EXECUTE ON FUNCTION public.driver_balance_summary(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.driver_financial_eligibility(text, bigint, uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.finance_mission_requirement(text, bigint) FROM anon;
REVOKE EXECUTE ON FUNCTION public.finance_mission_requirement_v2(text, bigint, bigint, bigint, bigint, text) FROM anon;

CREATE OR REPLACE FUNCTION public._qa_s1c_inner()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  d1 uuid := 'fb8fcfb5-cce8-4b21-9c86-6115f649b6ac';
  d2 uuid := 'a96acf85-3ca4-4cb6-a87e-2916841c01f8';
  s1 uuid := gen_random_uuid();
  s2 uuid := gen_random_uuid();
  res jsonb := '[]'::jsonb;
  base_wallets bigint; base_j bigint; base_h bigint;
  end_wallets bigint; end_j bigint; end_h bigint;
  j_bal bigint;
  r jsonb;
  claims text := json_build_object('sub', 'fb8fcfb5-cce8-4b21-9c86-6115f649b6ac', 'role','authenticated')::text;
BEGIN
  SELECT COALESCE(SUM(balance_gnf),0) INTO base_wallets FROM public.wallets;
  SELECT COUNT(*) INTO base_j FROM public.ledger_journals;
  SELECT COUNT(*) INTO base_h FROM public.mission_financial_holds;

  -- fund the test driver wallet (rolled back)
  UPDATE public.wallets SET balance_gnf = balance_gnf + 500000
   WHERE owner_user_id = d1 AND party_type = 'driver';
  IF NOT FOUND THEN
    INSERT INTO public.wallets (owner_user_id, party_type, balance_gnf, held_gnf, currency, status)
    VALUES (d1, 'driver', 500000, 0, 'GNF', 'active');
  END IF;

  -- Seed holds as the internal/service path (auth.uid() is NULL here).
  PERFORM public.driver_mission_hold_place('ride','ride', s1, 100000, d1, false, NULL, 100000, NULL, NULL, NULL, 'choppay');
  PERFORM public.driver_mission_hold_place('envoyer','package', s2, 0, d2, false, NULL, NULL, NULL, 5000, 200000, 'cash');

  ------------------------------------------------------------------
  -- Abuse tests, executed while impersonating an ordinary driver.
  ------------------------------------------------------------------
  BEGIN
    PERFORM set_config('request.jwt.claims', claims, true);
    PERFORM set_config('role','authenticated', true);
    PERFORM public.driver_mission_hold_release('ride', s1, 'commission', 'abuse');
    res := res || jsonb_build_object('id','A','name','driver releases own commission hold','result','FAIL: allowed');
  EXCEPTION WHEN OTHERS THEN
    res := res || jsonb_build_object('id','A','name','driver releases own commission hold','result','PASS: '||SQLERRM);
  END;

  BEGIN
    PERFORM set_config('request.jwt.claims', claims, true);
    PERFORM set_config('role','authenticated', true);
    PERFORM public.driver_mission_hold_release('ride', s1, 'collateral', 'abuse');
    res := res || jsonb_build_object('id','B','name','driver releases own collateral hold','result','FAIL: allowed');
  EXCEPTION WHEN OTHERS THEN
    res := res || jsonb_build_object('id','B','name','driver releases own collateral hold','result','PASS: '||SQLERRM);
  END;

  BEGIN
    PERFORM set_config('request.jwt.claims', claims, true);
    PERFORM set_config('role','authenticated', true);
    PERFORM public.driver_mission_commission_capture('ride', s1, 0);
    res := res || jsonb_build_object('id','C','name','driver captures commission with final value 0','result','FAIL: allowed');
  EXCEPTION WHEN OTHERS THEN
    res := res || jsonb_build_object('id','C','name','driver captures commission with final value 0','result','PASS: '||SQLERRM);
  END;

  BEGIN
    PERFORM set_config('request.jwt.claims', claims, true);
    PERFORM set_config('role','authenticated', true);
    PERFORM public.driver_mission_commission_capture('ride', s1, 1);
    res := res || jsonb_build_object('id','D','name','driver captures commission with manipulated value','result','FAIL: allowed');
  EXCEPTION WHEN OTHERS THEN
    res := res || jsonb_build_object('id','D','name','driver captures commission with manipulated value','result','PASS: '||SQLERRM);
  END;

  BEGIN
    PERFORM set_config('request.jwt.claims', claims, true);
    PERFORM set_config('role','authenticated', true);
    PERFORM public.driver_mission_fee_capture('ride', s1, 0);
    res := res || jsonb_build_object('id','E','name','driver captures platform fee with basis 0','result','FAIL: allowed');
  EXCEPTION WHEN OTHERS THEN
    res := res || jsonb_build_object('id','E','name','driver captures platform fee with basis 0','result','PASS: '||SQLERRM);
  END;

  BEGIN
    PERFORM set_config('request.jwt.claims', claims, true);
    PERFORM set_config('role','authenticated', true);
    PERFORM public.driver_collateral_resolve('package', s2, 0, 'abuse attempt');
    res := res || jsonb_build_object('id','F','name','driver resolves collateral','result','FAIL: allowed');
  EXCEPTION WHEN OTHERS THEN
    res := res || jsonb_build_object('id','F','name','driver resolves collateral','result','PASS: '||SQLERRM);
  END;

  BEGIN
    PERFORM set_config('request.jwt.claims', claims, true);
    PERFORM set_config('role','authenticated', true);
    PERFORM public.driver_mission_capture_reverse('ride', s1, 'commission', 'abuse attempt', 'x');
    res := res || jsonb_build_object('id','G','name','driver reverses a capture','result','FAIL: allowed');
  EXCEPTION WHEN OTHERS THEN
    res := res || jsonb_build_object('id','G','name','driver reverses a capture','result','PASS: '||SQLERRM);
  END;

  BEGIN
    PERFORM set_config('request.jwt.claims', claims, true);
    PERFORM set_config('role','authenticated', true);
    PERFORM public.driver_mission_hold_release('package', s2, NULL, 'cross-driver abuse');
    res := res || jsonb_build_object('id','H','name','driver releases another drivers hold','result','FAIL: allowed');
  EXCEPTION WHEN OTHERS THEN
    res := res || jsonb_build_object('id','H','name','driver releases another drivers hold','result','PASS: '||SQLERRM);
  END;

  BEGIN
    PERFORM set_config('request.jwt.claims', claims, true);
    PERFORM set_config('role','authenticated', true);
    PERFORM public.merchant_payable_fund('repas', s1, gen_random_uuid(), 'unrestricted');
    res := res || jsonb_build_object('id','I1','name','driver funds a merchant payable','result','FAIL: allowed');
  EXCEPTION WHEN OTHERS THEN
    res := res || jsonb_build_object('id','I1','name','driver funds a merchant payable','result','PASS: '||SQLERRM);
  END;

  BEGIN
    PERFORM set_config('request.jwt.claims', claims, true);
    PERFORM set_config('role','authenticated', true);
    PERFORM public.customer_cancellation_debt_waive(gen_random_uuid(), 'abuse attempt');
    res := res || jsonb_build_object('id','I2','name','driver waives a cancellation debt','result','FAIL: allowed');
  EXCEPTION WHEN OTHERS THEN
    res := res || jsonb_build_object('id','I2','name','driver waives a cancellation debt','result','PASS: '||SQLERRM);
  END;

  BEGIN
    PERFORM set_config('request.jwt.claims', claims, true);
    PERFORM set_config('role','authenticated', true);
    PERFORM public.driver_payout_hold_place(gen_random_uuid(), d1, 100000);
    res := res || jsonb_build_object('id','I3','name','driver places own payout hold','result','FAIL: allowed');
  EXCEPTION WHEN OTHERS THEN
    res := res || jsonb_build_object('id','I3','name','driver places own payout hold','result','PASS: '||SQLERRM);
  END;

  BEGIN
    PERFORM set_config('request.jwt.claims', claims, true);
    PERFORM set_config('role','authenticated', true);
    PERFORM public.merchant_settlement_complete(gen_random_uuid(), 'evidence');
    res := res || jsonb_build_object('id','I4','name','driver completes a merchant settlement','result','FAIL: allowed');
  EXCEPTION WHEN OTHERS THEN
    res := res || jsonb_build_object('id','I4','name','driver completes a merchant settlement','result','PASS: '||SQLERRM);
  END;

  BEGIN
    PERFORM set_config('request.jwt.claims', claims, true);
    PERFORM set_config('role','authenticated', true);
    PERFORM public.claims_reserve_resolve(gen_random_uuid(), 0, 'abuse attempt');
    res := res || jsonb_build_object('id','I5','name','driver resolves a claims reserve','result','FAIL: allowed');
  EXCEPTION WHEN OTHERS THEN
    res := res || jsonb_build_object('id','I5','name','driver resolves a claims reserve','result','PASS: '||SQLERRM);
  END;

  BEGIN
    PERFORM set_config('request.jwt.claims', claims, true);
    PERFORM set_config('role','authenticated', true);
    PERFORM public.driver_starter_credit_grant(d1);
    res := res || jsonb_build_object('id','I6','name','driver grants themselves starter credit','result','FAIL: allowed');
  EXCEPTION WHEN OTHERS THEN
    res := res || jsonb_build_object('id','I6','name','driver grants themselves starter credit','result','PASS: '||SQLERRM);
  END;

  BEGIN
    PERFORM set_config('request.jwt.claims', claims, true);
    PERFORM set_config('role','authenticated', true);
    PERFORM public.driver_funding_allocate(d1, 1000, 'commission');
    res := res || jsonb_build_object('id','I7','name','driver calls internal funding allocator','result','FAIL: allowed');
  EXCEPTION WHEN OTHERS THEN
    res := res || jsonb_build_object('id','I7','name','driver calls internal funding allocator','result','PASS: '||SQLERRM);
  END;

  BEGIN
    PERFORM set_config('request.jwt.claims', claims, true);
    PERFORM set_config('role','authenticated', true);
    PERFORM public._ledger_post('qa','abuse', NULL, 'x', '[]'::jsonb, NULL, NULL, NULL, false, NULL, NULL, NULL);
    res := res || jsonb_build_object('id','I8','name','driver posts directly to the ledger','result','FAIL: allowed');
  EXCEPTION WHEN OTHERS THEN
    res := res || jsonb_build_object('id','I8','name','driver posts directly to the ledger','result','PASS: '||SQLERRM);
  END;

  -- Read-only surface must still work for the driver themselves.
  BEGIN
    PERFORM set_config('request.jwt.claims', claims, true);
    PERFORM set_config('role','authenticated', true);
    PERFORM public.driver_balance_summary(d1);
    res := res || jsonb_build_object('id','K1','name','driver reads own balance summary','result','PASS: allowed (read-only)');
  EXCEPTION WHEN OTHERS THEN
    res := res || jsonb_build_object('id','K1','name','driver reads own balance summary','result','FAIL: '||SQLERRM);
  END;

  BEGIN
    PERFORM set_config('request.jwt.claims', claims, true);
    PERFORM set_config('role','authenticated', true);
    PERFORM public.driver_balance_summary(d2);
    res := res || jsonb_build_object('id','K2','name','driver reads another drivers balance','result','FAIL: allowed');
  EXCEPTION WHEN OTHERS THEN
    res := res || jsonb_build_object('id','K2','name','driver reads another drivers balance','result','PASS: '||SQLERRM);
  END;

  ------------------------------------------------------------------
  -- J: internal / service-role path still works and stays balanced.
  ------------------------------------------------------------------
  r := public.driver_mission_commission_capture('ride', s1, 100000);
  res := res || jsonb_build_object('id','J1','name','service-role commission capture',
    'result', CASE WHEN (r->>'status') IN ('captured','partially_captured','resolved')
                     OR (r->>'captured_gnf') IS NOT NULL
              THEN 'PASS: '||r::text ELSE 'FAIL: '||r::text END);

  r := public.driver_mission_hold_release('ride', s1, NULL, 'qa');
  res := res || jsonb_build_object('id','J2','name','service-role release','result','PASS: '||r::text);

  r := public.driver_mission_hold_release('ride', s1, NULL, 'qa-again');
  res := res || jsonb_build_object('id','J3','name','service-role release is idempotent','result','PASS: '||r::text);

  SELECT COALESCE(SUM(amount_gnf),0) INTO j_bal FROM public.ledger_postings;
  res := res || jsonb_build_object('id','J4','name','all journals zero-sum',
    'result', CASE WHEN j_bal = 0 THEN 'PASS: sum=0' ELSE 'FAIL: sum='||j_bal END);

  SELECT COALESCE(SUM(balance_gnf),0) INTO end_wallets FROM public.wallets;
  SELECT COUNT(*) INTO end_j FROM public.ledger_journals;
  SELECT COUNT(*) INTO end_h FROM public.mission_financial_holds;

  RAISE EXCEPTION 'QA_S1C_RESULT %', jsonb_build_object(
    'tests', res,
    'baseline', jsonb_build_object('wallets_total', base_wallets, 'journals', base_j, 'holds', base_h),
    'in_txn', jsonb_build_object('wallets_total', end_wallets, 'journals', end_j, 'holds', end_h)
  )::text;
END $fn$;

CREATE OR REPLACE FUNCTION public._qa_s1c_run()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE msg text; payload jsonb;
BEGIN
  BEGIN
    PERFORM public._qa_s1c_inner();
    RETURN jsonb_build_object('error','harness did not roll back');
  EXCEPTION WHEN OTHERS THEN
    msg := SQLERRM;
  END;
  IF msg LIKE 'QA_S1C_RESULT %' THEN
    payload := substr(msg, 16)::jsonb;
  ELSE
    payload := jsonb_build_object('harness_error', msg);
  END IF;
  RETURN payload || jsonb_build_object(
    'after_rollback', jsonb_build_object(
      'wallets_total', (SELECT COALESCE(SUM(balance_gnf),0) FROM public.wallets),
      'journals', (SELECT COUNT(*) FROM public.ledger_journals),
      'postings', (SELECT COUNT(*) FROM public.ledger_postings),
      'holds', (SELECT COUNT(*) FROM public.mission_financial_holds),
      'promo_credits', (SELECT COUNT(*) FROM public.driver_promo_credits),
      'payables', (SELECT COUNT(*) FROM public.merchant_payables),
      'debts', (SELECT COUNT(*) FROM public.customer_cancellation_debts),
      'claims', (SELECT COUNT(*) FROM public.claims_reserves)
    ));
END $fn$;

REVOKE ALL ON FUNCTION public._qa_s1c_inner() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._qa_s1c_run() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_s1c_run() TO service_role;