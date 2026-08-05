CREATE OR REPLACE FUNCTION public._qa_s1x_run()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $qa$
DECLARE
  v_out jsonb := '[]'::jsonb;
  v_god uuid := '2e547148-69f3-43f6-80f8-264de2d8fa67';
  v_drv uuid := '19fe6432-ad9d-4f8c-b75d-ec1146a88244';
  v_drv2 uuid := 'a96acf85-3ca4-4cb6-a87e-2916841c01f8';
  v_cust uuid := 'cb5d2b1f-591e-4f14-a8d4-d5ef387fbcbe';
  v_store uuid := '7e6613d1-9956-4522-88d9-1aa5e0ed0e6b';
  v_mowner uuid;
  v_sid uuid; v_sid2 uuid; v_sid3 uuid;
  v_r text; v_j jsonb; v_a bigint; v_b bigint; v_c bigint; v_d bigint;
  v_before_wallets bigint; v_after_wallets bigint;
  v_before_j int; v_after_j int; v_post_sum bigint;
  v_pid uuid; v_claim uuid; v_debt uuid;
  v_ok boolean;
BEGIN
  SELECT COALESCE(SUM(balance_gnf),0) INTO v_before_wallets FROM public.wallets;
  SELECT count(*) INTO v_before_j FROM public.ledger_journals;

  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_god)::text, true);
    SELECT owner_user_id INTO v_mowner FROM public.merchant_stores WHERE id = v_store;

    -- ================= A. JOURNAL INVARIANTS =================
    BEGIN
      PERFORM public._ledger_post('qa:unbal', 'qa', gen_random_uuid(), 'qa',
        jsonb_build_array(jsonb_build_object('account','EQ_PLATFORM','amount_gnf',100),
                          jsonb_build_object('account','R_COMMISSION','amount_gnf',-50)));
      v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','A1','case','unbalanced journal rejected','obs',v_r,
      'r', CASE WHEN v_r LIKE 'LEDGER_UNBALANCED%' THEN 'PASS' ELSE 'FAIL' END);

    BEGIN
      PERFORM public._ledger_post('qa:empty', 'qa', gen_random_uuid(), 'qa', '[]'::jsonb);
      v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','A2','case','empty journal rejected','obs',v_r,
      'r', CASE WHEN v_r LIKE 'LEDGER_EMPTY_JOURNAL%' THEN 'PASS' ELSE 'FAIL' END);

    BEGIN
      PERFORM public._ledger_post('qa:one', 'qa', gen_random_uuid(), 'qa',
        jsonb_build_array(jsonb_build_object('account','EQ_PLATFORM','amount_gnf',100)));
      v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','A3','case','single-posting journal rejected','obs',v_r,
      'r', CASE WHEN v_r LIKE 'LEDGER_EMPTY_JOURNAL%' THEN 'PASS' ELSE 'FAIL' END);

    BEGIN
      PERFORM public._ledger_post('qa:zeros', 'qa', gen_random_uuid(), 'qa',
        jsonb_build_array(jsonb_build_object('account','EQ_PLATFORM','amount_gnf',0),
                          jsonb_build_object('account','R_COMMISSION','amount_gnf',0)));
      v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','A4','case','all-zero journal rejected','obs',v_r,
      'r', CASE WHEN v_r LIKE 'LEDGER_EMPTY_JOURNAL%' THEN 'PASS' ELSE 'FAIL' END);

    SELECT count(*) INTO v_a FROM public.ledger_journals WHERE journal_key LIKE 'qa:%';
    v_out := v_out || jsonb_build_object('id','A5','case','no rows persisted by rejected journals',
      'obs', v_a, 'r', CASE WHEN v_a = 0 THEN 'PASS' ELSE 'FAIL' END);

    -- DB-level guard: a journal with zero postings cannot commit.
    BEGIN
      SET CONSTRAINTS ALL IMMEDIATE;
      BEGIN
        INSERT INTO public.ledger_journals (journal_key, source_module, source_id, action)
        VALUES ('qa:direct-empty','qa',gen_random_uuid(),'qa');
        v_r := 'no error';
      EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
      SET CONSTRAINTS ALL DEFERRED;
    END;
    v_out := v_out || jsonb_build_object('id','A6','case','DB trigger rejects zero-posting journal','obs',v_r,
      'r', CASE WHEN v_r LIKE 'LEDGER_EMPTY_JOURNAL%' THEN 'PASS' ELSE 'FAIL' END);

    -- ================= B. MERCHANT PAYABLE SINGLE FUNDING =================
    v_sid := gen_random_uuid();
    UPDATE public.wallets SET balance_gnf = balance_gnf + 200000 WHERE owner_user_id = v_cust AND party_type='client';
    PERFORM public.chop_pay_customer_hold_place('qa_order', v_sid, 100000, 'repas', v_cust, true, '{}'::jsonb);

    BEGIN
      PERFORM public.chop_pay_customer_capture('qa_order', v_sid, v_store, 70000, v_drv, 20000, 0, 1000);
      v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','B1','case','capture without payable rejected','obs',v_r,
      'r', CASE WHEN v_r LIKE 'MERCHANT_PAYABLE_REQUIRED%' THEN 'PASS' ELSE 'FAIL' END);

    PERFORM public.merchant_payable_create('qa_order', v_sid, v_store, 70000, 0, 'repas', '{}'::jsonb, true);
    SELECT COALESCE(balance_gnf,0) INTO v_a FROM public.wallets WHERE owner_user_id = v_mowner AND party_type='merchant';
    v_a := COALESCE(v_a,0);
    v_j := public.chop_pay_customer_capture('qa_order', v_sid, v_store, 70000, v_drv, 20000, 0, 1000);
    SELECT COALESCE(balance_gnf,0) INTO v_b FROM public.wallets WHERE owner_user_id = v_mowner AND party_type='merchant';
    SELECT COALESCE(SUM(amount_gnf),0) INTO v_c FROM public.ledger_postings p
      JOIN public.ledger_journals j ON j.id = p.journal_id
     WHERE j.source_id = v_sid AND p.account_code = 'L_MERCHANT_PAYABLE';
    SELECT funded_gnf, state INTO v_d, v_r FROM public.merchant_payables
     WHERE source_id = v_sid AND merchant_store_id = v_store;
    v_out := v_out || jsonb_build_object('id','B2','case','capture funds merchant exactly once',
      'obs', jsonb_build_object('wallet_delta', v_b - v_a, 'payable_liability', v_c,
                                'funded_gnf', v_d, 'state', v_r),
      'r', CASE WHEN (v_b - v_a) = 70000 AND v_c = -70000 AND v_d = 70000 AND v_r = 'funded'
                THEN 'PASS' ELSE 'FAIL' END);

    v_j := public.chop_pay_customer_capture('qa_order', v_sid, v_store, 70000, v_drv, 20000, 0, 1000);
    SELECT COALESCE(balance_gnf,0) INTO v_c FROM public.wallets WHERE owner_user_id = v_mowner AND party_type='merchant';
    v_out := v_out || jsonb_build_object('id','B3','case','capture replay is inert',
      'obs', jsonb_build_object('status', v_j->>'status', 'wallet_delta_after_replay', v_c - v_b),
      'r', CASE WHEN v_j->>'status' = 'already_resolved' AND v_c = v_b THEN 'PASS' ELSE 'FAIL' END);

    BEGIN
      PERFORM public.merchant_payable_fund('qa_order', v_sid, v_store, 'customer_choppay');
      v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','B4','case','customer_choppay refund path blocked','obs',v_r,
      'r', CASE WHEN v_r LIKE 'CUSTOMER_CHOPPAY_FUNDED_AT_CAPTURE%' THEN 'PASS' ELSE 'FAIL' END);

    v_j := public.merchant_payable_fund('qa_order', v_sid, v_store, 'platform');
    SELECT COALESCE(balance_gnf,0) INTO v_d FROM public.wallets WHERE owner_user_id = v_mowner AND party_type='merchant';
    v_out := v_out || jsonb_build_object('id','B5','case','no second funding of a funded payable',
      'obs', jsonb_build_object('status', v_j->>'status','wallet_delta', v_d - v_b),
      'r', CASE WHEN v_j->>'status' = 'already_funded' AND v_d = v_b THEN 'PASS' ELSE 'FAIL' END);

    -- ================= C. CAPTURE REVERSAL BUCKETS =================
    v_sid2 := gen_random_uuid();
    INSERT INTO public.wallets (owner_user_id, party_type) VALUES (v_drv,'driver')
      ON CONFLICT (owner_user_id, party_type) DO NOTHING;
    UPDATE public.wallets SET balance_gnf = 50000, held_gnf = 0 WHERE owner_user_id = v_drv AND party_type='driver';
    INSERT INTO public.driver_promo_credits (driver_user_id, grant_key, granted_gnf, granted_by, reason)
    VALUES (v_drv, 'qa-promo:'||v_sid2::text, 20000, v_god, 'QA restricted bonus');

    v_j := public.driver_mission_hold_place('ride','qa_ride', v_sid2, 250000, v_drv, true, ARRAY['commission']);
    v_j := public.driver_mission_commission_capture('qa_ride', v_sid2, 250000);
    SELECT captured_promo_gnf, captured_unrestricted_gnf INTO v_a, v_b
      FROM public.mission_financial_holds WHERE source_id = v_sid2 AND kind='commission';
    v_out := v_out || jsonb_build_object('id','C1','case','mixed-source capture stores exact attribution',
      'obs', jsonb_build_object('captured_promo', v_a, 'captured_unrestricted', v_b),
      'r', CASE WHEN v_a = 20000 AND v_b = 5000 THEN 'PASS' ELSE 'FAIL' END);

    SELECT COALESCE(SUM(consumed_gnf),0) INTO v_c FROM public.driver_promo_credits WHERE driver_user_id = v_drv;
    SELECT balance_gnf INTO v_d FROM public.wallets WHERE owner_user_id = v_drv AND party_type='driver';
    v_j := public.driver_mission_capture_reverse('qa_ride', v_sid2, 'commission', 'QA reversal check');
    SELECT COALESCE(SUM(consumed_gnf),0) INTO v_a FROM public.driver_promo_credits WHERE driver_user_id = v_drv;
    SELECT balance_gnf, held_gnf INTO v_b, v_post_sum FROM public.wallets WHERE owner_user_id = v_drv AND party_type='driver';
    v_out := v_out || jsonb_build_object('id','C2','case','reversal restores exact restricted/unrestricted buckets',
      'obs', jsonb_build_object('consumed_before', v_c, 'consumed_after', v_a,
                                'balance_before', v_d, 'balance_after', v_b,
                                'promo_available', (public.driver_promo_balance(v_drv)->>'promo_available_gnf')::bigint,
                                'held', v_post_sum),
      'r', CASE WHEN v_c = 20000 AND v_a = 0 AND v_b = v_d + 25000 AND v_b = 50000
                     AND (public.driver_promo_balance(v_drv)->>'promo_available_gnf')::bigint = 20000
                THEN 'PASS' ELSE 'FAIL' END);

    v_j := public.driver_mission_capture_reverse('qa_ride', v_sid2, 'commission', 'QA reversal replay');
    SELECT balance_gnf INTO v_c FROM public.wallets WHERE owner_user_id = v_drv AND party_type='driver';
    v_out := v_out || jsonb_build_object('id','C3','case','reversal replay is inert',
      'obs', jsonb_build_object('status', v_j->>'status','balance', v_c),
      'r', CASE WHEN v_j->>'status' = 'already_reversed' AND v_c = v_b THEN 'PASS' ELSE 'FAIL' END);

    SELECT COALESCE(SUM(p.amount_gnf),0) INTO v_post_sum
      FROM public.ledger_postings p JOIN public.ledger_journals j ON j.id = p.journal_id
     WHERE j.source_id = v_sid2;
    v_out := v_out || jsonb_build_object('id','C4','case','ride journals zero-sum after reversal',
      'obs', v_post_sum, 'r', CASE WHEN v_post_sum = 0 THEN 'PASS' ELSE 'FAIL' END);

    -- ================= D. POLICY BASES =================
    SELECT count(*) INTO v_a FROM (VALUES
        ('ride','none','fare'),('bonbonna','none','fare'),
        ('repas','merchandise_subtotal','merchandise_plus_delivery'),
        ('marche','merchandise_subtotal','merchandise_plus_delivery'),
        ('envoyer','declared_value','delivery_fee')) x(mt, cb, kb)
      CROSS JOIN LATERAL public.finance_policy_current(x.mt) c
     WHERE c.collateral_basis = x.cb AND c.cancel_basis = x.kb;
    SELECT count(*) INTO v_b FROM public.finance_policy_current('envoyer') c WHERE c.fee_basis='delivery_fee';
    v_out := v_out || jsonb_build_object('id','D1','case','all 5 services carry explicit bases',
      'obs', jsonb_build_object('matched', v_a, 'envoyer_fee_basis_delivery_fee', v_b),
      'r', CASE WHEN v_a = 5 AND v_b = 1 THEN 'PASS' ELSE 'FAIL' END);

    BEGIN
      PERFORM public.admin_set_finance_policy('repas', 0, 5000, 'percentage', 5000, 0, 0, NULL, 0, false,
        now(), 'QA', 'none');
      v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','D2','case','policy editor rejects collateral without basis','obs',v_r,
      'r', CASE WHEN v_r LIKE 'COLLATERAL_BASIS_REQUIRED%' THEN 'PASS' ELSE 'FAIL' END);

    BEGIN
      PERFORM public.admin_set_finance_policy('repas', 0, 5000, 'percentage', 5000, 0, 0, NULL, 0, false,
        now(), 'QA', 'merchandise_subtotal', 100, 'merchandise_subtotal', 500, 1000, 'merchandise_plus_delivery');
      SELECT c.collateral_basis || '/' || c.cancel_basis INTO v_r FROM public.finance_policy_current('repas') c;
    EXCEPTION WHEN OTHERS THEN v_r := 'ERR: ' || SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','D3','case','God Admin can persist explicit bases','obs',v_r,
      'r', CASE WHEN v_r = 'merchandise_subtotal/merchandise_plus_delivery' THEN 'PASS' ELSE 'FAIL' END);

    -- ================= E. CANCELLATION DEBT =================
    v_sid3 := gen_random_uuid();
    v_j := public.customer_cancellation_debt_create('qa_cancel', v_sid3, v_cust, 'ride', 'before_dispatch',
             100000, 0, 0, false, 'customer', true);
    v_out := v_out || jsonb_build_object('id','E1','case','ride before dispatch = 5% of fare',
      'obs', v_j, 'r', CASE WHEN (v_j->>'basis_kind')='fare' AND (v_j->>'amount_gnf')::bigint = 5000
                            THEN 'PASS' ELSE 'FAIL' END);

    v_j := public.customer_cancellation_debt_create('qa_cancel', gen_random_uuid(), v_cust, 'ride', 'after_dispatch',
             100000, 0, 0, false, 'customer', true);
    v_out := v_out || jsonb_build_object('id','E2','case','ride after dispatch = 10% of fare',
      'obs', v_j, 'r', CASE WHEN (v_j->>'amount_gnf')::bigint = 10000 THEN 'PASS' ELSE 'FAIL' END);

    v_j := public.customer_cancellation_debt_create('qa_cancel', gen_random_uuid(), v_cust, 'repas', 'after_dispatch',
             0, 80000, 20000, false, 'customer', true);
    v_out := v_out || jsonb_build_object('id','E3','case','repas basis = merchandise + delivery',
      'obs', v_j, 'r', CASE WHEN (v_j->>'basis_gnf')::bigint = 100000 AND (v_j->>'amount_gnf')::bigint = 10000
                            THEN 'PASS' ELSE 'FAIL' END);

    v_j := public.customer_cancellation_debt_create('qa_cancel', gen_random_uuid(), v_cust, 'envoyer', 'before_dispatch',
             0, 400000, 30000, false, 'customer', true);
    v_out := v_out || jsonb_build_object('id','E4','case','envoyer basis = delivery fee only',
      'obs', v_j, 'r', CASE WHEN (v_j->>'basis_gnf')::bigint = 30000 AND (v_j->>'amount_gnf')::bigint = 1500
                            THEN 'PASS' ELSE 'FAIL' END);

    BEGIN
      PERFORM public.customer_cancellation_debt_create('qa_cancel', gen_random_uuid(), v_cust, 'repas',
        'after_dispatch', 0, 80000, 20000, true, 'customer', true);
      v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    SELECT count(*) INTO v_a FROM public.customer_cancellation_debts
     WHERE source_module='qa_cancel' AND policy_snapshot->>'preparation_started' = 'true';
    v_out := v_out || jsonb_build_object('id','E5','case','repas preparation lock rejects and writes nothing',
      'obs', jsonb_build_object('err', v_r, 'rows', v_a),
      'r', CASE WHEN v_r LIKE 'REPAS_CANCELLATION_LOCKED%' AND v_a = 0 THEN 'PASS' ELSE 'FAIL' END);

    v_j := public.customer_cancellation_debt_create('qa_cancel', gen_random_uuid(), v_cust, 'ride', 'after_dispatch',
             100000, 0, 0, false, 'driver', true);
    v_out := v_out || jsonb_build_object('id','E6','case','driver-caused failure is exempt',
      'obs', v_j, 'r', CASE WHEN (v_j->>'status')='exempt' AND (v_j->>'amount_gnf')::bigint = 0
                            THEN 'PASS' ELSE 'FAIL' END);

    v_j := public.customer_cancellation_debt_create('qa_cancel', v_sid3, v_cust, 'ride', 'before_dispatch',
             100000, 0, 0, false, 'customer', true);
    v_out := v_out || jsonb_build_object('id','E7','case','cancellation replay is inert',
      'obs', v_j->>'status', 'r', CASE WHEN v_j->>'status'='already_exists' THEN 'PASS' ELSE 'FAIL' END);

    SELECT id INTO v_debt FROM public.customer_cancellation_debts WHERE source_id = v_sid3;
    v_j := public.customer_cancellation_debt_collect(v_debt);
    v_out := v_out || jsonb_build_object('id','E8','case','cancellation debt collection',
      'obs', v_j, 'r', CASE WHEN (v_j->>'collected_gnf')::bigint = 5000 THEN 'PASS' ELSE 'FAIL' END);
    v_j := public.customer_cancellation_debt_collect(v_debt);
    v_out := v_out || jsonb_build_object('id','E9','case','collection replay is inert',
      'obs', v_j->>'status', 'r', CASE WHEN v_j->>'status'='not_outstanding' THEN 'PASS' ELSE 'FAIL' END);

    SELECT id INTO v_debt FROM public.customer_cancellation_debts
     WHERE source_module='qa_cancel' AND state='outstanding' LIMIT 1;
    v_j := public.customer_cancellation_debt_waive(v_debt, 'QA goodwill waiver');
    v_out := v_out || jsonb_build_object('id','E10','case','cancellation debt waiver',
      'obs', v_j, 'r', CASE WHEN v_j->>'status'='waived' THEN 'PASS' ELSE 'FAIL' END);

    -- ================= F. ROLE AUTHORITY =================
    INSERT INTO public.user_roles (user_id, role) VALUES (v_drv2, 'operations_admin')
      ON CONFLICT DO NOTHING;
    INSERT INTO public.admin_users (user_id, admin_role, status)
      VALUES (v_drv2, 'operations_admin', 'active') ON CONFLICT DO NOTHING;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_drv2)::text, true);

    v_sid := gen_random_uuid();
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_god)::text, true);
    UPDATE public.wallets SET balance_gnf = 50000, held_gnf = 0 WHERE owner_user_id = v_drv AND party_type='driver';
    PERFORM public.driver_mission_hold_place('ride','qa_ops', v_sid, 100000, v_drv, true, ARRAY['commission']);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_drv2)::text, true);
    BEGIN
      PERFORM public.driver_mission_hold_release('qa_ops', v_sid, 'commission', 'ops attempt');
      v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','F1','case','operations_admin cannot release funds','obs',v_r,
      'r', CASE WHEN v_r = 'Not authorized' THEN 'PASS' ELSE 'FAIL' END);

    BEGIN
      PERFORM public.driver_collateral_resolve('qa_ops', v_sid, 1000, 'ops attempt at capture');
      v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','F2','case','operations_admin cannot capture collateral','obs',v_r,
      'r', CASE WHEN v_r = 'Not authorized' THEN 'PASS' ELSE 'FAIL' END);

    BEGIN
      PERFORM public.driver_starter_credit_grant(v_drv);
      v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','F3','case','operations_admin cannot grant starting bonus','obs',v_r,
      'r', CASE WHEN v_r LIKE 'STARTER_CREDIT_NOT_AUTHORIZED%' THEN 'PASS' ELSE 'FAIL' END);

    -- finance_admin persona
    UPDATE public.admin_users SET admin_role = 'finance_admin' WHERE user_id = v_drv2;
    DELETE FROM public.user_roles WHERE user_id = v_drv2 AND role = 'operations_admin';
    INSERT INTO public.user_roles (user_id, role) VALUES (v_drv2, 'finance_admin') ON CONFLICT DO NOTHING;

    BEGIN
      PERFORM public.driver_starter_credit_grant(v_drv);
      v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','F4','case','finance_admin cannot grant starting bonus','obs',v_r,
      'r', CASE WHEN v_r LIKE 'STARTER_CREDIT_NOT_AUTHORIZED%' THEN 'PASS' ELSE 'FAIL' END);

    BEGIN
      PERFORM public.admin_reverse_starter_credit(v_drv, 'finance attempt at reversal');
      v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','F5','case','finance_admin cannot reverse starting bonus','obs',v_r,
      'r', CASE WHEN v_r <> 'no error' THEN 'PASS' ELSE 'FAIL' END);

    BEGIN
      PERFORM public.admin_set_finance_policy('ride', 900);
      v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','F6','case','finance_admin cannot change finance policy','obs',v_r,
      'r', CASE WHEN v_r LIKE 'Only a God Admin%' THEN 'PASS' ELSE 'FAIL' END);

    BEGIN
      PERFORM public.driver_mission_capture_reverse('qa_ride', v_sid2, 'commission', 'finance attempt');
      v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','F7','case','finance_admin cannot reverse a capture','obs',v_r,
      'r', CASE WHEN v_r LIKE 'Only a God Admin%' THEN 'PASS' ELSE 'FAIL' END);

    -- self-service attempt
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_drv)::text, true);
    BEGIN
      PERFORM public.driver_starter_credit_grant(v_drv);
      v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','F8','case','driver cannot self-grant the bonus','obs',v_r,
      'r', CASE WHEN v_r LIKE 'STARTER_CREDIT_NOT_AUTHORIZED%' THEN 'PASS' ELSE 'FAIL' END);

    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_god)::text, true);
    v_j := public.driver_mission_hold_release('qa_ops', v_sid, 'commission', 'god release');
    v_out := v_out || jsonb_build_object('id','F9','case','God Admin can release',
      'obs', v_j, 'r', CASE WHEN (v_j->>'released_gnf')::bigint = 10000 THEN 'PASS' ELSE 'FAIL' END);

    -- ================= G. FREEZE + CLAIMS =================
    v_sid := gen_random_uuid();
    UPDATE public.wallets SET balance_gnf = 500000, held_gnf = 0 WHERE owner_user_id = v_drv AND party_type='driver';
    v_j := public.driver_mission_hold_place('envoyer','qa_env', v_sid, 0, v_drv, true,
             ARRAY['collateral'], NULL, NULL, 20000, 200000, 'choppay');
    SELECT amount_gnf INTO v_a FROM public.mission_financial_holds WHERE source_id=v_sid AND kind='collateral';
    v_out := v_out || jsonb_build_object('id','G1','case','envoyer collateral = 75% of declared value',
      'obs', v_a, 'r', CASE WHEN v_a = 150000 THEN 'PASS' ELSE 'FAIL' END);

    BEGIN
      PERFORM public.claims_reserve_allocate('qa_env', v_sid, 50000, 'QA-EVID-1', 'QA claim before freeze',
        v_cust, v_drv, 200000, 'envoyer', true);
      v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','G2','case','claim denied without frozen collateral','obs',v_r,
      'r', CASE WHEN v_r LIKE 'COLLATERAL_FREEZE_REQUIRED%' THEN 'PASS' ELSE 'FAIL' END);

    SELECT balance_gnf, held_gnf INTO v_a, v_b FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    v_j := public.driver_mission_hold_freeze('qa_env', v_sid, 'QA dispute opened');
    SELECT balance_gnf, held_gnf INTO v_c, v_d FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    v_out := v_out || jsonb_build_object('id','G3','case','freeze moves no value',
      'obs', jsonb_build_object('status', v_j->>'status','balance_delta', v_c-v_a, 'held_delta', v_d-v_b),
      'r', CASE WHEN v_j->>'status'='frozen' AND v_c=v_a AND v_d=v_b THEN 'PASS' ELSE 'FAIL' END);

    v_j := public.driver_mission_hold_freeze('qa_env', v_sid, 'QA dispute replay');
    v_out := v_out || jsonb_build_object('id','G4','case','freeze replay is idempotent',
      'obs', v_j->>'status', 'r', CASE WHEN v_j->>'status'='already_frozen' THEN 'PASS' ELSE 'FAIL' END);

    v_j := public.claims_reserve_allocate('qa_env', v_sid, 50000, 'QA-EVID-1', 'QA claim after freeze',
             v_cust, v_drv, 200000, 'envoyer', true);
    v_claim := (v_j->>'claim_id')::uuid;
    v_out := v_out || jsonb_build_object('id','G5','case','claim allowed once collateral is frozen',
      'obs', v_j->>'status', 'r', CASE WHEN v_j->>'status'='allocated' THEN 'PASS' ELSE 'FAIL' END);

    v_j := public.claims_reserve_allocate('qa_env', v_sid, 50000, 'QA-EVID-1', 'QA claim replay',
             v_cust, v_drv, 200000, 'envoyer', true);
    v_out := v_out || jsonb_build_object('id','G6','case','claim replay is inert',
      'obs', v_j->>'status', 'r', CASE WHEN v_j->>'status'='already_exists' THEN 'PASS' ELSE 'FAIL' END);

    BEGIN
      PERFORM public.driver_mission_hold_unfreeze('qa_env', v_sid, 'QA premature unfreeze');
      v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','G7','case','cannot unfreeze while a claim is open','obs',v_r,
      'r', CASE WHEN v_r LIKE 'CLAIM_OPEN_CANNOT_UNFREEZE%' THEN 'PASS' ELSE 'FAIL' END);

    v_j := public.claims_reserve_resolve(v_claim, 999999, 'QA overpayment attempt');
    v_out := v_out || jsonb_build_object('id','G8','case','claim payout clamped to authorised amount',
      'obs', v_j, 'r', CASE WHEN (v_j->>'paid_gnf')::bigint = 50000 THEN 'PASS' ELSE 'FAIL' END);
    v_j := public.claims_reserve_resolve(v_claim, 50000, 'QA resolve replay');
    v_out := v_out || jsonb_build_object('id','G9','case','claim resolve replay is inert',
      'obs', v_j->>'status', 'r', CASE WHEN v_j->>'status'='already_resolved' THEN 'PASS' ELSE 'FAIL' END);

    v_j := public.driver_mission_hold_unfreeze('qa_env', v_sid, 'QA unfreeze after resolution');
    v_out := v_out || jsonb_build_object('id','G10','case','unfreeze returns hold to held',
      'obs', v_j, 'r', CASE WHEN v_j->>'status'='unfrozen' THEN 'PASS' ELSE 'FAIL' END);

    -- ================= H. PAYOUT / SETTLEMENT SAFETY =================
    UPDATE public.wallets SET balance_gnf = 500000, held_gnf = 0 WHERE owner_user_id = v_drv AND party_type='driver';
    UPDATE public.mission_financial_holds SET state='released', released_gnf = amount_gnf
      WHERE source_id = v_sid AND state IN ('held','frozen');
    v_sid := gen_random_uuid(); v_sid2 := gen_random_uuid();
    v_j := public.driver_payout_hold_place(v_sid, v_drv, 100000);
    BEGIN
      PERFORM public.driver_payout_hold_place(v_sid2, v_drv, 50000);
      v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','H1','case','one pending payout hold per driver','obs',v_r,
      'r', CASE WHEN v_r <> 'no error' THEN 'PASS' ELSE 'FAIL' END);

    v_j := public.driver_payout_confirm(v_sid, 'OM-QA-REF-0001');
    v_out := v_out || jsonb_build_object('id','H2','case','payout confirm with evidence',
      'obs', v_j, 'r', CASE WHEN v_j->>'status'='paid' THEN 'PASS' ELSE 'FAIL' END);

    v_j := public.driver_payout_hold_place(v_sid2, v_drv, 50000);
    BEGIN
      PERFORM public.driver_payout_confirm(v_sid2, 'om-qa-ref-0001');
      v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','H3','case','duplicate payout evidence denied','obs',v_r,
      'r', CASE WHEN v_r LIKE 'EVIDENCE_ALREADY_USED%' THEN 'PASS' ELSE 'FAIL' END);

    SELECT balance_gnf INTO v_a FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    v_j := public.driver_payout_cancel(v_sid2, 'QA cancel pending payout');
    SELECT balance_gnf, held_gnf INTO v_b, v_c FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    v_out := v_out || jsonb_build_object('id','H4','case','payout cancel releases hold without debit',
      'obs', jsonb_build_object('status', v_j->>'status','balance_delta', v_b-v_a,'held', v_c),
      'r', CASE WHEN v_j->>'status'='cancelled' AND v_b = v_a AND v_c = 0 THEN 'PASS' ELSE 'FAIL' END);

    -- settlement reusing the same external reference
    SELECT id INTO v_pid FROM public.merchant_payables WHERE source_module='qa_order' LIMIT 1;
    v_j := public.merchant_settlement_hold(v_pid);
    BEGIN
      PERFORM public.merchant_settlement_complete(v_pid, 'OM-QA-REF-0001');
      v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','H5','case','settlement cannot reuse a payout reference','obs',v_r,
      'r', CASE WHEN v_r LIKE 'EVIDENCE_ALREADY_USED%' THEN 'PASS' ELSE 'FAIL' END);

    v_j := public.merchant_settlement_fail(v_pid, 'QA provider rejection');
    v_out := v_out || jsonb_build_object('id','H6','case','failed settlement returns payable to due',
      'obs', v_j->>'status', 'r', CASE WHEN v_j->>'status'='returned_to_due' THEN 'PASS' ELSE 'FAIL' END);
    PERFORM public.merchant_settlement_hold(v_pid);
    v_j := public.merchant_settlement_complete(v_pid, 'OM-QA-SETTLE-9001');
    v_out := v_out || jsonb_build_object('id','H7','case','settlement succeeds once with fresh evidence',
      'obs', v_j, 'r', CASE WHEN v_j->>'status'='settled' THEN 'PASS' ELSE 'FAIL' END);
    v_j := public.merchant_settlement_complete(v_pid, 'OM-QA-SETTLE-9002');
    v_out := v_out || jsonb_build_object('id','H8','case','settlement replay is inert',
      'obs', v_j->>'status', 'r', CASE WHEN v_j->>'status'='already_settled' THEN 'PASS' ELSE 'FAIL' END);

    -- ================= I. BONUS / SECURITY =================
    UPDATE public.feature_flags SET enabled = true WHERE key = 'driver_starter_credit_enabled';
    BEGIN
      v_j := public.driver_starter_credit_grant(v_drv);
      v_r := v_j->>'status';
    EXCEPTION WHEN OTHERS THEN v_r := 'ERR: ' || SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','I1','case','reversed/existing bonus never re-grants','obs',v_r,
      'r', CASE WHEN v_r = 'already_granted' THEN 'PASS' ELSE 'FAIL' END);

    UPDATE public.driver_profiles SET status = 'suspended' WHERE user_id = v_drv;
    BEGIN
      PERFORM public.driver_mission_hold_place('ride','qa_susp', gen_random_uuid(), 100000, v_drv, true, ARRAY['commission']);
      v_r := 'no error';
    EXCEPTION WHEN OTHERS THEN v_r := SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','I2','case','suspended driver cannot create holds','obs',v_r,
      'r', CASE WHEN v_r = 'ACCOUNT_RESTRICTED' THEN 'PASS' ELSE 'FAIL' END);

    BEGIN
      v_j := public.driver_starter_credit_grant(v_drv2);
      v_r := (v_j->>'status') || '/' || COALESCE(v_j->>'reason','');
    EXCEPTION WHEN OTHERS THEN v_r := 'ERR: ' || SQLERRM; END;
    v_out := v_out || jsonb_build_object('id','I3','case','non-approved / restricted driver gets zero','obs',v_r,
      'r', CASE WHEN v_r LIKE 'not_eligible%' OR v_r LIKE 'needs_review%' THEN 'PASS' ELSE 'FAIL' END);
    UPDATE public.driver_profiles SET status = 'approved' WHERE user_id = v_drv;
    UPDATE public.feature_flags SET enabled = false WHERE key = 'driver_starter_credit_enabled';

    SELECT NOT (has_function_privilege('authenticated','public.driver_funding_allocate(uuid,bigint,text)','execute')
             OR has_function_privilege('authenticated','public._promo_consume(uuid,bigint)','execute')
             OR has_function_privilege('authenticated','public._promo_restore(uuid,bigint)','execute')
             OR has_function_privilege('authenticated','public._finance_evidence_claim(text,text,uuid,bigint,uuid)','execute'))
      INTO v_ok;
    v_out := v_out || jsonb_build_object('id','I4','case','internal helpers not executable by authenticated',
      'obs', v_ok, 'r', CASE WHEN v_ok THEN 'PASS' ELSE 'FAIL' END);

    SELECT count(*) = 0 INTO v_ok FROM public.wallets WHERE balance_gnf - held_gnf < 0;
    v_out := v_out || jsonb_build_object('id','I5','case','no wallet has negative available balance',
      'obs', v_ok, 'r', CASE WHEN v_ok THEN 'PASS' ELSE 'FAIL' END);

    -- ================= J. GLOBAL INVARIANTS =================
    SELECT COALESCE(SUM(p.amount_gnf),0) INTO v_post_sum FROM public.ledger_postings p;
    v_out := v_out || jsonb_build_object('id','J1','case','all ledger postings sum to zero',
      'obs', v_post_sum, 'r', CASE WHEN v_post_sum = 0 THEN 'PASS' ELSE 'FAIL' END);

    SELECT count(*) INTO v_a FROM public.ledger_journals j
     WHERE (SELECT count(*) FROM public.ledger_postings p WHERE p.journal_id = j.id) < 2;
    v_out := v_out || jsonb_build_object('id','J2','case','no journal has fewer than two postings',
      'obs', v_a, 'r', CASE WHEN v_a = 0 THEN 'PASS' ELSE 'FAIL' END);

    SELECT count(*) INTO v_a FROM public.feature_flags
     WHERE key <> 'om_topup_enabled' AND enabled = true
       AND key IN ('chop_pay_enabled','chop_pay_checkout_enabled','chop_pay_p2p_enabled',
                   'driver_balance_gate_enabled','driver_starter_credit_enabled',
                   'cash_order_funding_enabled','driver_cashout_enabled',
                   'merchant_om_settlement_enabled','om_direct_checkout_enabled');
    v_out := v_out || jsonb_build_object('id','J3','case','all Chop Pay activation flags remain OFF',
      'obs', v_a, 'r', CASE WHEN v_a = 0 THEN 'PASS' ELSE 'FAIL' END);

    RAISE EXCEPTION 'QA_ROLLBACK_SENTINEL';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_ROLLBACK_SENTINEL' THEN
      v_out := v_out || jsonb_build_object('id','FATAL','case','harness aborted','obs',SQLERRM,'r','FAIL');
    END IF;
  END;

  SELECT COALESCE(SUM(balance_gnf),0) INTO v_after_wallets FROM public.wallets;
  SELECT count(*) INTO v_after_j FROM public.ledger_journals;

  RETURN jsonb_build_object(
    'results', v_out,
    'rollback_proof', jsonb_build_object(
      'wallet_total_before', v_before_wallets, 'wallet_total_after', v_after_wallets,
      'journals_before', v_before_j, 'journals_after', v_after_j,
      'clean', (v_before_wallets = v_after_wallets AND v_before_j = v_after_j)));
END; $qa$;

REVOKE ALL ON FUNCTION public._qa_s1x_run() FROM public, anon, authenticated;