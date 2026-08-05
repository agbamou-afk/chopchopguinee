CREATE OR REPLACE FUNCTION public._qa_s1x_run2()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $qa$
DECLARE
  v_out jsonb := '[]'::jsonb;
  v_god uuid := '2e547148-69f3-43f6-80f8-264de2d8fa67';
  v_drv uuid := '19fe6432-ad9d-4f8c-b75d-ec1146a88244';
  v_fin uuid := 'a96acf85-3ca4-4cb6-a87e-2916841c01f8';
  v_cust uuid := 'cb5d2b1f-591e-4f14-a8d4-d5ef387fbcbe';
  v_store uuid := '7e6613d1-9956-4522-88d9-1aa5e0ed0e6b';
  v_mowner uuid; v_sid uuid; v_sid2 uuid; v_pid uuid; v_claim uuid;
  v_r text; v_j jsonb; v_a bigint; v_b bigint; v_c bigint; v_ok boolean;
  v_bw bigint; v_aw bigint; v_bj int; v_aj int;
BEGIN
  SELECT COALESCE(SUM(balance_gnf),0) INTO v_bw FROM public.wallets;
  SELECT count(*) INTO v_bj FROM public.ledger_journals;

  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_god)::text, true);
    SELECT owner_user_id INTO v_mowner FROM public.merchant_stores WHERE id = v_store;

    -- Finance persona provisioned by God Admin.
    INSERT INTO public.user_roles (user_id, role) VALUES (v_fin,'finance_admin') ON CONFLICT DO NOTHING;
    INSERT INTO public.admin_users (user_id, admin_role, status)
      VALUES (v_fin,'finance_admin','active') ON CONFLICT DO NOTHING;

    -- Captured commission fixture for the reversal-authority test.
    v_sid := gen_random_uuid();
    UPDATE public.wallets SET balance_gnf = 50000, held_gnf = 0
      WHERE owner_user_id = v_drv AND party_type='driver';
    PERFORM public.driver_mission_hold_place('ride','qa2_ride', v_sid, 100000, v_drv, true, ARRAY['commission']);
    PERFORM public.driver_mission_commission_capture('qa2_ride', v_sid, 100000);

    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_fin)::text, true);

    BEGIN PERFORM public.driver_starter_credit_grant(v_drv); v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','F4','case','finance_admin cannot grant starting bonus','obs',v_r,
      'r', CASE WHEN v_r LIKE 'STARTER_CREDIT_NOT_AUTHORIZED%' THEN 'PASS' ELSE 'FAIL' END);

    BEGIN PERFORM public.admin_reverse_starter_credit(v_drv,'finance attempt at reversal'); v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','F5','case','finance_admin cannot reverse starting bonus','obs',v_r,
      'r', CASE WHEN v_r <> 'no error' THEN 'PASS' ELSE 'FAIL' END);

    BEGIN PERFORM public.admin_set_finance_policy('ride', 900); v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','F6','case','finance_admin cannot change finance policy','obs',v_r,
      'r', CASE WHEN v_r LIKE 'Only a God Admin%' THEN 'PASS' ELSE 'FAIL' END);

    BEGIN PERFORM public.driver_mission_capture_reverse('qa2_ride', v_sid,'commission','finance attempt'); v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','F7','case','finance_admin cannot reverse a capture','obs',v_r,
      'r', CASE WHEN v_r LIKE 'Only a God Admin%' THEN 'PASS' ELSE 'FAIL' END);

    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_drv)::text, true);
    BEGIN PERFORM public.driver_starter_credit_grant(v_drv); v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','F8','case','driver cannot self-grant the bonus','obs',v_r,
      'r', CASE WHEN v_r LIKE 'STARTER_CREDIT_NOT_AUTHORIZED%' THEN 'PASS' ELSE 'FAIL' END);

    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_god)::text, true);
    v_sid2 := gen_random_uuid();
    UPDATE public.wallets SET balance_gnf = 50000, held_gnf = 0 WHERE owner_user_id = v_drv AND party_type='driver';
    PERFORM public.driver_mission_hold_place('ride','qa2_rel', v_sid2, 100000, v_drv, true, ARRAY['commission']);
    v_j := public.driver_mission_hold_release('qa2_rel', v_sid2, 'commission', 'god release');
    v_out := v_out || jsonb_build_object('id','F9','case','God Admin can release a hold',
      'obs', v_j, 'r', CASE WHEN (v_j->>'released_gnf')::bigint = 10000 THEN 'PASS' ELSE 'FAIL' END);

    -- ============ G. FREEZE + CLAIMS ============
    v_sid := gen_random_uuid();
    UPDATE public.wallets SET balance_gnf = 500000, held_gnf = 0 WHERE owner_user_id = v_drv AND party_type='driver';
    PERFORM public.driver_mission_hold_place('envoyer','qa2_env', v_sid, 0, v_drv, true,
      ARRAY['collateral'], NULL, NULL, 20000, 200000, 'choppay');
    SELECT amount_gnf INTO v_a FROM public.mission_financial_holds WHERE source_id=v_sid AND kind='collateral';
    v_out := v_out || jsonb_build_object('id','G1','case','envoyer collateral = 75% of declared value',
      'obs', v_a, 'r', CASE WHEN v_a = 150000 THEN 'PASS' ELSE 'FAIL' END);

    BEGIN
      PERFORM public.claims_reserve_allocate('qa2_env', v_sid, 50000, 'QA-EVID-1','QA claim before freeze',
        v_cust, v_drv, 200000, 'envoyer', true);
      v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','G2','case','claim denied without frozen collateral','obs',v_r,
      'r', CASE WHEN v_r LIKE 'COLLATERAL_FREEZE_REQUIRED%' THEN 'PASS' ELSE 'FAIL' END);

    SELECT balance_gnf, held_gnf INTO v_a, v_b FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    v_j := public.driver_mission_hold_freeze('qa2_env', v_sid, 'QA dispute opened');
    SELECT balance_gnf, held_gnf INTO v_c, v_ok FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    v_out := v_out || jsonb_build_object('id','G3','case','freeze moves no value',
      'obs', jsonb_build_object('status', v_j->>'status','balance_delta', v_c - v_a),
      'r', CASE WHEN v_j->>'status'='frozen' AND v_c = v_a THEN 'PASS' ELSE 'FAIL' END);

    v_j := public.driver_mission_hold_freeze('qa2_env', v_sid, 'QA dispute replay');
    v_out := v_out || jsonb_build_object('id','G4','case','freeze replay is idempotent',
      'obs', v_j->>'status', 'r', CASE WHEN v_j->>'status'='already_frozen' THEN 'PASS' ELSE 'FAIL' END);

    v_j := public.claims_reserve_allocate('qa2_env', v_sid, 50000, 'QA-EVID-1','QA claim after freeze',
             v_cust, v_drv, 200000, 'envoyer', true);
    v_claim := (v_j->>'claim_id')::uuid;
    v_out := v_out || jsonb_build_object('id','G5','case','claim allowed once collateral is frozen',
      'obs', v_j->>'status', 'r', CASE WHEN v_j->>'status'='allocated' THEN 'PASS' ELSE 'FAIL' END);

    v_j := public.claims_reserve_allocate('qa2_env', v_sid, 50000, 'QA-EVID-1','QA claim replay',
             v_cust, v_drv, 200000, 'envoyer', true);
    v_out := v_out || jsonb_build_object('id','G6','case','claim replay is inert',
      'obs', v_j->>'status', 'r', CASE WHEN v_j->>'status'='already_exists' THEN 'PASS' ELSE 'FAIL' END);

    BEGIN PERFORM public.driver_mission_hold_unfreeze('qa2_env', v_sid,'QA premature unfreeze'); v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','G7','case','cannot unfreeze while a claim is open','obs',v_r,
      'r', CASE WHEN v_r LIKE 'CLAIM_OPEN_CANNOT_UNFREEZE%' THEN 'PASS' ELSE 'FAIL' END);

    v_j := public.claims_reserve_resolve(v_claim, 999999, 'QA overpayment attempt');
    v_out := v_out || jsonb_build_object('id','G8','case','claim payout clamped to authorised amount',
      'obs', v_j, 'r', CASE WHEN (v_j->>'paid_gnf')::bigint = 50000 THEN 'PASS' ELSE 'FAIL' END);
    v_j := public.claims_reserve_resolve(v_claim, 50000, 'QA resolve replay');
    v_out := v_out || jsonb_build_object('id','G9','case','claim resolve replay is inert',
      'obs', v_j->>'status', 'r', CASE WHEN v_j->>'status'='already_resolved' THEN 'PASS' ELSE 'FAIL' END);

    v_j := public.driver_mission_hold_unfreeze('qa2_env', v_sid,'QA unfreeze after resolution');
    v_out := v_out || jsonb_build_object('id','G10','case','unfreeze returns hold to held',
      'obs', v_j->>'status', 'r', CASE WHEN v_j->>'status'='unfrozen' THEN 'PASS' ELSE 'FAIL' END);
    PERFORM public.driver_mission_hold_release('qa2_env', v_sid, 'collateral', 'QA cleanup release');

    -- ============ H. PAYOUT / SETTLEMENT ============
    UPDATE public.wallets SET balance_gnf = 500000, held_gnf = 0 WHERE owner_user_id = v_drv AND party_type='driver';
    v_sid := gen_random_uuid(); v_sid2 := gen_random_uuid();
    PERFORM public.driver_payout_hold_place(v_sid, v_drv, 100000);
    BEGIN PERFORM public.driver_payout_hold_place(v_sid2, v_drv, 50000); v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','H1','case','one pending payout hold per driver','obs',v_r,
      'r', CASE WHEN v_r <> 'no error' THEN 'PASS' ELSE 'FAIL' END);

    v_j := public.driver_payout_confirm(v_sid, 'OM-QA-REF-0001');
    v_out := v_out || jsonb_build_object('id','H2','case','payout confirm with fresh evidence',
      'obs', v_j->>'status', 'r', CASE WHEN v_j->>'status'='paid' THEN 'PASS' ELSE 'FAIL' END);

    PERFORM public.driver_payout_hold_place(v_sid2, v_drv, 50000);
    BEGIN PERFORM public.driver_payout_confirm(v_sid2, 'om-qa-ref-0001'); v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','H3','case','duplicate payout evidence denied','obs',v_r,
      'r', CASE WHEN v_r LIKE 'EVIDENCE_ALREADY_USED%' THEN 'PASS' ELSE 'FAIL' END);

    SELECT balance_gnf INTO v_a FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    v_j := public.driver_payout_cancel(v_sid2, 'QA cancel pending payout');
    SELECT balance_gnf, held_gnf INTO v_b, v_c FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    v_out := v_out || jsonb_build_object('id','H4','case','payout cancel releases hold without debit',
      'obs', jsonb_build_object('status', v_j->>'status','balance_delta', v_b - v_a, 'held', v_c),
      'r', CASE WHEN v_j->>'status'='cancelled' AND v_b = v_a AND v_c = 0 THEN 'PASS' ELSE 'FAIL' END);

    -- settlement path
    v_sid := gen_random_uuid();
    UPDATE public.wallets SET balance_gnf = balance_gnf + 200000 WHERE owner_user_id = v_cust AND party_type='client';
    PERFORM public.chop_pay_customer_hold_place('qa2_order', v_sid, 100000, 'repas', v_cust, true, '{}'::jsonb);
    PERFORM public.merchant_payable_create('qa2_order', v_sid, v_store, 70000, 0, 'repas', '{}'::jsonb, true);
    PERFORM public.chop_pay_customer_capture('qa2_order', v_sid, v_store, 70000, v_drv, 29000, 0, 1000);
    SELECT id INTO v_pid FROM public.merchant_payables WHERE source_id = v_sid;
    PERFORM public.merchant_settlement_hold(v_pid);
    BEGIN PERFORM public.merchant_settlement_complete(v_pid, 'OM-QA-REF-0001'); v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','H5','case','settlement cannot reuse a payout reference','obs',v_r,
      'r', CASE WHEN v_r LIKE 'EVIDENCE_ALREADY_USED%' THEN 'PASS' ELSE 'FAIL' END);

    v_j := public.merchant_settlement_fail(v_pid, 'QA provider rejection');
    v_out := v_out || jsonb_build_object('id','H6','case','failed settlement returns payable to due',
      'obs', v_j->>'status', 'r', CASE WHEN v_j->>'status'='returned_to_due' THEN 'PASS' ELSE 'FAIL' END);
    PERFORM public.merchant_settlement_hold(v_pid);
    v_j := public.merchant_settlement_complete(v_pid, 'OM-QA-SETTLE-9001');
    v_out := v_out || jsonb_build_object('id','H7','case','settlement succeeds once with fresh evidence',
      'obs', v_j->>'status', 'r', CASE WHEN v_j->>'status'='settled' THEN 'PASS' ELSE 'FAIL' END);
    v_j := public.merchant_settlement_complete(v_pid, 'OM-QA-SETTLE-9002');
    v_out := v_out || jsonb_build_object('id','H8','case','settlement replay is inert',
      'obs', v_j->>'status', 'r', CASE WHEN v_j->>'status'='already_settled' THEN 'PASS' ELSE 'FAIL' END);

    -- ============ I. BONUS / SECURITY ============
    UPDATE public.feature_flags SET enabled = true WHERE key = 'driver_starter_credit_enabled';
    INSERT INTO public.driver_promo_credits (driver_user_id, grant_key, granted_gnf, granted_by, reason, state, reversed_gnf)
    VALUES (v_drv, 'qa2-reversed', 25000, v_god, 'QA reversed bonus', 'reversed', 25000);
    BEGIN v_j := public.driver_starter_credit_grant(v_drv); v_r := v_j->>'status';
    EXCEPTION WHEN OTHERS THEN v_r := 'ERR: ' || SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','I1','case','a reversed bonus does not restore eligibility','obs',v_r,
      'r', CASE WHEN v_r = 'already_granted' THEN 'PASS' ELSE 'FAIL' END);

    UPDATE public.driver_profiles SET status='suspended' WHERE user_id = v_drv;
    BEGIN
      PERFORM public.driver_mission_hold_place('ride','qa2_susp', gen_random_uuid(), 100000, v_drv, true, ARRAY['commission']);
      v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','I2','case','suspended driver cannot create new holds','obs',v_r,
      'r', CASE WHEN v_r = 'ACCOUNT_RESTRICTED' THEN 'PASS' ELSE 'FAIL' END);

    BEGIN v_j := public.driver_starter_credit_grant(v_drv); v_r := (v_j->>'status')||'/'||COALESCE(v_j->>'reason','');
    EXCEPTION WHEN OTHERS THEN v_r := 'ERR: '||SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','I3','case','suspended driver bonus request returns zero','obs',v_r,
      'r', CASE WHEN v_r LIKE 'already_granted%' OR v_r LIKE 'not_eligible%' THEN 'PASS' ELSE 'FAIL' END);
    UPDATE public.driver_profiles SET status='approved' WHERE user_id = v_drv;
    UPDATE public.feature_flags SET enabled = false WHERE key = 'driver_starter_credit_enabled';

    SELECT NOT (has_function_privilege('authenticated','public.driver_funding_allocate(uuid,bigint,text)','execute')
             OR has_function_privilege('authenticated','public._promo_consume(uuid,bigint)','execute')
             OR has_function_privilege('authenticated','public._promo_restore(uuid,bigint)','execute')
             OR has_function_privilege('authenticated','public._finance_evidence_claim(text,text,uuid,bigint,uuid)','execute')
             OR has_function_privilege('authenticated','public.driver_promo_balance(uuid)','execute'))
      INTO v_ok;
    v_out := v_out || jsonb_build_object('id','I4','case','internal helpers not executable by ordinary users',
      'obs', v_ok, 'r', CASE WHEN v_ok THEN 'PASS' ELSE 'FAIL' END);

    SELECT count(*) = 0 INTO v_ok FROM public.wallets WHERE balance_gnf - held_gnf < 0;
    v_out := v_out || jsonb_build_object('id','I5','case','no wallet has a negative available balance',
      'obs', v_ok, 'r', CASE WHEN v_ok THEN 'PASS' ELSE 'FAIL' END);

    SELECT count(*) = 0 INTO v_ok FROM public.mission_financial_holds
     WHERE captured_promo_gnf + captured_unrestricted_gnf > captured_gnf;
    v_out := v_out || jsonb_build_object('id','I6','case','capture attribution never exceeds captured amount',
      'obs', v_ok, 'r', CASE WHEN v_ok THEN 'PASS' ELSE 'FAIL' END);

    -- ============ J. GLOBAL INVARIANTS ============
    SELECT COALESCE(SUM(amount_gnf),0) INTO v_a FROM public.ledger_postings;
    v_out := v_out || jsonb_build_object('id','J1','case','all ledger postings sum to zero',
      'obs', v_a, 'r', CASE WHEN v_a = 0 THEN 'PASS' ELSE 'FAIL' END);

    SELECT count(*) INTO v_b FROM public.ledger_journals j
     WHERE (SELECT count(*) FROM public.ledger_postings p WHERE p.journal_id = j.id) < 2;
    v_out := v_out || jsonb_build_object('id','J2','case','no journal has fewer than two postings',
      'obs', v_b, 'r', CASE WHEN v_b = 0 THEN 'PASS' ELSE 'FAIL' END);

    SELECT count(*) INTO v_c FROM public.feature_flags
     WHERE enabled = true AND key IN ('chop_pay_enabled','chop_pay_checkout_enabled','chop_pay_p2p_enabled',
       'driver_balance_gate_enabled','driver_starter_credit_enabled','cash_order_funding_enabled',
       'driver_cashout_enabled','merchant_om_settlement_enabled','om_direct_checkout_enabled');
    v_out := v_out || jsonb_build_object('id','J3','case','all Chop Pay activation flags remain OFF',
      'obs', v_c, 'r', CASE WHEN v_c = 0 THEN 'PASS' ELSE 'FAIL' END);

    RAISE EXCEPTION 'QA_ROLLBACK_SENTINEL';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_ROLLBACK_SENTINEL' THEN
      v_out := v_out || jsonb_build_object('id','FATAL','case','harness aborted','obs',SQLERRM,'r','FAIL');
    END IF;
  END;

  SELECT COALESCE(SUM(balance_gnf),0) INTO v_aw FROM public.wallets;
  SELECT count(*) INTO v_aj FROM public.ledger_journals;
  RETURN jsonb_build_object('results', v_out, 'rollback_proof',
    jsonb_build_object('wallet_total_before',v_bw,'wallet_total_after',v_aw,
                       'journals_before',v_bj,'journals_after',v_aj,
                       'clean',(v_bw = v_aw AND v_bj = v_aj)));
END; $qa$;

REVOKE ALL ON FUNCTION public._qa_s1x_run2() FROM public, anon, authenticated;