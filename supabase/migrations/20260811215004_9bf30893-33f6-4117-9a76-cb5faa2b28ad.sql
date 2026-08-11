CREATE OR REPLACE FUNCTION public._qa_s13_run7()
RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'public' AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_master0 bigint; v_master1 bigint; v_flags0 jsonb; v_flags1 jsonb;
  v_sfx text; v_t0 timestamptz;
  v_c1 uuid; v_c2 uuid; v_d1 uuid; v_d2 uuid; v_m1 uuid; v_god uuid;
  v_s1 uuid; v_acct uuid;
  v_err text; v_n bigint; v_b bigint; v_b0 bigint; v_b1 bigint;
  v_res jsonb; v_ov0 jsonb; v_ov1 jsonb; v_ov2 jsonb; v_ex jsonb; v_dd jsonb;
  v_row public.rides; v_ride uuid;
  v_mw0 bigint; v_mw1 bigint;
  v_debt uuid; v_debt_amt bigint;
  v_req uuid; v_ord uuid; v_reqR uuid; v_ordR uuid;
  v_q jsonb; v_qid uuid; v_pkg uuid; v_mis uuid; v_pcode text; v_dcode text;
  v_qid2 uuid; v_pkg2 uuid; v_mis2 uuid;
  v_case jsonb; v_topup uuid; v_evt uuid; v_tx uuid;
  v_phone1 text := '+224620000701'; v_phone2 text := '+224620000702';
  v_code text; v_ex_master jsonb; v_ex_pick jsonb;
  v_ptx public.wallet_transactions;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;

  BEGIN
    v_t0 := now() - interval '1 second';
    v_sfx := upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
    v_c1 := gen_random_uuid(); v_c2 := gen_random_uuid();
    v_d1 := gen_random_uuid(); v_d2 := gen_random_uuid();
    v_m1 := gen_random_uuid(); v_god := gen_random_uuid();

    PERFORM public._qa_s13_user(v_c1,'p7c1');
    PERFORM public._qa_s13_user(v_c2,'p7c2');
    PERFORM public._qa_s13_user(v_m1,'p7m1');
    PERFORM public._qa_s13_user(v_god,'p7god');
    PERFORM public._qa_s13_admin(v_god);
    INSERT INTO public.user_roles(user_id, role) VALUES (v_god,'god_admin') ON CONFLICT DO NOTHING;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    v_ov0 := public.finance_treasury_overview();
    PERFORM set_config('request.jwt.claims','',true);

    PERFORM public._qa_s13_driver(v_d1,'p7d1', 300000);
    PERFORM public._qa_s13_driver(v_d2,'p7d2', 300000);

    BEGIN
      UPDATE public.profiles SET phone = v_phone1 WHERE user_id = v_c1;
      IF NOT FOUND THEN INSERT INTO public.profiles(user_id, phone) VALUES (v_c1, v_phone1); END IF;
      UPDATE public.profiles SET phone = v_phone2 WHERE user_id = v_c2;
      IF NOT FOUND THEN INSERT INTO public.profiles(user_id, phone) VALUES (v_c2, v_phone2); END IF;
    EXCEPTION WHEN OTHERS THEN NULL; END;

    PERFORM public._qa_s13_wallet(v_c1,'client', 500000, 0);
    PERFORM public._qa_s13_wallet(v_c2,'client', 500000, 0);
    PERFORM public._qa_s13_wallet(v_m1,'merchant', 400000, 0);

    INSERT INTO public.merchant_stores (owner_user_id, slug, name, phone)
    VALUES (v_m1, 'qa-s13-p7-'||lower(v_sfx), 'QA S13 P7 Store', v_phone1)
    RETURNING id INTO v_s1;
    INSERT INTO public.merchant_payables
      (payable_key, source_module, source_id, merchant_store_id, merchant_user_id,
       subtotal_gnf, amount_gnf, funded_gnf, state, funding_source)
    VALUES ('qa-s13-p7:'||v_sfx||':1','qa_s13', gen_random_uuid(), v_s1, v_m1,
            400000, 400000, 400000, 'funded','platform');
    INSERT INTO public.payment_receiving_accounts(label, phone_e164, is_active, created_by)
    VALUES ('QA S13 P7 OM', '+224610000700', true, v_god) RETURNING id INTO v_acct;

    ---------------------------------------------------------------- A. treasury truth
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    v_ov1 := public.finance_treasury_overview();
    r := r || public._qa_s13_ok('A1 customer Chop Pay liability rises by exactly the funded customer balances',
      (v_ov1->>'total_customer_liability_gnf')::bigint - (v_ov0->>'total_customer_liability_gnf')::bigint = 1000000,
      format('%s -> %s', v_ov0->>'total_customer_liability_gnf', v_ov1->>'total_customer_liability_gnf'));
    r := r || public._qa_s13_ok('A2 driver liability rises by exactly the funded driver balances',
      (v_ov1->>'total_driver_liability_gnf')::bigint - (v_ov0->>'total_driver_liability_gnf')::bigint = 600000,
      format('%s -> %s', v_ov0->>'total_driver_liability_gnf', v_ov1->>'total_driver_liability_gnf'));
    r := r || public._qa_s13_ok('A3 outstanding merchant payables rise by exactly the funded payable',
      (v_ov1->>'merchant_payable_outstanding_gnf')::bigint - (v_ov0->>'merchant_payable_outstanding_gnf')::bigint = 400000,
      format('%s -> %s', v_ov0->>'merchant_payable_outstanding_gnf', v_ov1->>'merchant_payable_outstanding_gnf'));
    r := r || public._qa_s13_ok('A4 coverage delta equals verified assets minus covered obligations, with no plug',
      (v_ov1->>'treasury_coverage_delta_gnf')::bigint
        = (v_ov1->>'verified_assets_gnf')::bigint - (v_ov1->>'covered_obligations_gnf')::bigint,
      format('assets=%s covered=%s delta=%s', v_ov1->>'verified_assets_gnf',
             v_ov1->>'covered_obligations_gnf', v_ov1->>'treasury_coverage_delta_gnf'));

    SELECT COALESCE(jsonb_agg(to_jsonb(t)),'[]'::jsonb) INTO v_ex FROM public.finance_treasury_exceptions() t;
    SELECT x INTO v_ex_master FROM jsonb_array_elements(v_ex) x WHERE x->>'code' = 'MASTER_WALLET_DEFICIT' LIMIT 1;
    r := r || public._qa_s13_ok('A5 DEF-FIN-001 is still surfaced as its own named master-wallet exception',
      v_ex_master IS NOT NULL AND abs((v_ex_master->>'amount_gnf')::bigint) = 100435,
      COALESCE(v_ex_master::text,'missing'));
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s13_ok('A6 the master wallet deficit is never silently reset or normalised',
      v_b = -100435, v_b::text);
    SELECT count(*) INTO v_n FROM jsonb_array_elements(v_ex) x
     WHERE COALESCE(x->>'code','') = '' OR COALESCE(x->>'severity','') = ''
        OR COALESCE(x->>'source_module','') = '' OR (x->>'amount_gnf') IS NULL;
    r := r || public._qa_s13_ok('A7 every treasury exception is named, classified and quantified',
      v_n = 0, v_n::text);

    SELECT x INTO v_ex_pick FROM jsonb_array_elements(v_ex) x
     WHERE COALESCE((x->>'entity_count')::int,0) > 0 LIMIT 1;
    IF v_ex_pick IS NULL THEN
      r := r || public._qa_s13_ok('A8 an exception with source records exists to trace', false, 'none');
    ELSE
      SELECT COALESCE(jsonb_agg(to_jsonb(t)),'[]'::jsonb) INTO v_dd
        FROM public.finance_treasury_drilldown(v_ex_pick->>'code', 50) t;
      r := r || public._qa_s13_ok('A8 an exception with source records drills down to identifiable source rows',
        jsonb_array_length(v_dd) > 0
        AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_dd) y
                        WHERE COALESCE(y->>'ref','')='' OR (y->>'amount_gnf') IS NULL
                           OR COALESCE(y->>'source_module','')=''),
        format('%s rows for %s', jsonb_array_length(v_dd), v_ex_pick->>'code'));
    END IF;
    PERFORM set_config('request.jwt.claims','',true);

    ---------------------------------------------------------------- ride: capture + replay
    PERFORM public._qa_s13_flag('driver_balance_gate_enabled', true);
    INSERT INTO public.rides(client_id, mode, pickup_lat, pickup_lng, dest_lat, dest_lng, fare_gnf, metadata)
    VALUES (v_c1,'moto',9.5,-13.7,9.6,-13.6,100000,'{"payment_mode":"cash"}'::jsonb)
    RETURNING id INTO v_ride;
    INSERT INTO public.ride_offers(ride_id, driver_id, status, expires_at)
    VALUES (v_ride, v_d1, 'pending', now() + interval '5 min');
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_d1), true);
    v_row := public.ride_accept(v_ride);
    v_row := public.ride_accept(v_ride);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds WHERE source_id = v_ride AND kind='commission';
    r := r || public._qa_s13_ok('C1 a duplicated ride acceptance creates no second commission hold',
      v_n = 1, v_n::text);

    UPDATE public.rides SET status='in_progress',
      metadata = metadata || '{"phase":"on_trip","pickup_confirmed_by":"customer"}'::jsonb
     WHERE id = v_ride;
    SELECT balance_gnf INTO v_mw0 FROM public.wallets WHERE party_type='master' LIMIT 1;
    v_row := public.ride_complete(v_ride, NULL, NULL);
    SELECT balance_gnf INTO v_mw1 FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s13_ok('A9 a completed cash ride captures exactly the 10 percent commission to the master wallet',
      v_mw1 - v_mw0 = 10000, format('%s -> %s', v_mw0, v_mw1));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    v_ov2 := public.finance_treasury_overview();
    r := r || public._qa_s13_ok('A10 captured platform revenue rises by exactly the captured commission',
      (v_ov2->>'captured_revenue_gnf')::bigint - (v_ov1->>'captured_revenue_gnf')::bigint = 10000,
      format('%s -> %s', v_ov1->>'captured_revenue_gnf', v_ov2->>'captured_revenue_gnf'));
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_d1), true);

    v_b0 := v_mw1;
    BEGIN v_row := public.ride_complete(v_ride, NULL, NULL); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT balance_gnf INTO v_b1 FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s13_ok('C2 replaying ride completion moves zero additional GNF',
      v_b1 = v_b0, format('%s (%s)', v_b1, v_err));

    ---------------------------------------------------------------- cancellation debt + replay
    PERFORM public._qa_s13_flag('cancellation_policy_enabled', true);
    PERFORM set_config('request.jwt.claims','',true);
    v_res := public.customer_cancellation_debt_create('qa_s13_p7', gen_random_uuid(), v_c2,
             'ride', 'after_accept', 100000, 0, 0, false, 'customer', false, NULL);
    v_debt := (v_res->>'debt_id')::uuid;
    SELECT amount_gnf INTO v_debt_amt FROM public.customer_cancellation_debts WHERE id = v_debt;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    v_ov1 := public.finance_treasury_overview();
    PERFORM set_config('request.jwt.claims','',true);
    r := r || public._qa_s13_ok('A11 an open cancellation debt appears as a receivable, never as cash or revenue',
      v_debt IS NOT NULL AND v_debt_amt > 0
      AND (v_ov1->>'cancellation_debt_receivable_gnf')::bigint
          - (v_ov2->>'cancellation_debt_receivable_gnf')::bigint = v_debt_amt
      AND (v_ov1->>'captured_revenue_gnf')::bigint = (v_ov2->>'captured_revenue_gnf')::bigint,
      format('debt=%s', v_debt_amt));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_c2), true);
    SELECT balance_gnf INTO v_b0 FROM public.wallets WHERE owner_user_id=v_c2 AND party_type='client';
    v_res := public.customer_cancellation_debt_repay(v_debt, NULL);
    SELECT balance_gnf INTO v_b1 FROM public.wallets WHERE owner_user_id=v_c2 AND party_type='client';
    r := r || public._qa_s13_ok('C3 repaying a cancellation debt debits exactly the debt amount once',
      v_b0 - v_b1 = v_debt_amt, format('%s -> %s (debt %s)', v_b0, v_b1, v_debt_amt));
    BEGIN v_res := public.customer_cancellation_debt_repay(v_debt, NULL); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT balance_gnf INTO v_b0 FROM public.wallets WHERE owner_user_id=v_c2 AND party_type='client';
    r := r || public._qa_s13_ok('C4 replaying the repayment moves zero additional GNF',
      v_b0 = v_b1, format('%s (%s)', v_b0, v_err));

    ---------------------------------------------------------------- merchant settlement + manual OM replay
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_m1), true);
    v_res := public.merchant_settlement_request_create(100000, 'qa-p7-a-'||v_sfx, v_s1, 'P7');
    v_req := (v_res->>'request_id')::uuid; v_ord := (v_res->>'payout_order_id')::uuid;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    v_ov2 := public.finance_treasury_overview();
    r := r || public._qa_s13_ok('A12 a settlement reservation is reported as reserved and debits no payable',
      (v_ov2->>'merchant_settlement_reserved_gnf')::bigint
        - (v_ov1->>'merchant_settlement_reserved_gnf')::bigint = 100000
      AND (v_ov2->>'merchant_payable_outstanding_gnf')::bigint
        = (v_ov1->>'merchant_payable_outstanding_gnf')::bigint,
      format('reserved %s -> %s', v_ov1->>'merchant_settlement_reserved_gnf', v_ov2->>'merchant_settlement_reserved_gnf'));

    PERFORM public._qa_s13_flag('merchant_om_settlement_enabled', true);
    SELECT balance_gnf INTO v_b0 FROM public.wallets WHERE owner_user_id=v_m1 AND party_type='merchant';
    v_res := public.finance_confirm_manual_om_payout(v_ord, 'OM-P7-'||v_sfx||'-A', true, NULL);
    SELECT balance_gnf INTO v_b1 FROM public.wallets WHERE owner_user_id=v_m1 AND party_type='merchant';
    r := r || public._qa_s13_ok('C5 an attested manual Orange Money settlement debits the merchant exactly once',
      COALESCE(v_res->>'status','') = 'settled' AND v_b0 - v_b1 = 100000,
      format('%s %s->%s', v_res->>'status', v_b0, v_b1));
    v_res := public.finance_confirm_manual_om_payout(v_ord, 'OM-P7-'||v_sfx||'-A', true, NULL);
    SELECT balance_gnf INTO v_b0 FROM public.wallets WHERE owner_user_id=v_m1 AND party_type='merchant';
    SELECT count(*) INTO v_n FROM public.payout_provider_evidence WHERE payout_order_id = v_ord;
    r := r || public._qa_s13_ok('C6 replaying the manual settlement moves zero GNF and creates no second evidence row',
      COALESCE(v_res->>'status','') = 'already_settled' AND v_b0 = v_b1 AND v_n = 1,
      format('%s bal=%s evidence=%s', v_res->>'status', v_b0, v_n));
    SELECT count(*) INTO v_n FROM public.payout_provider_evidence
     WHERE payout_order_id = v_ord AND evidence_source = 'finance_manual_om' AND provider_verified = false;
    r := r || public._qa_s13_ok('C7 manual evidence is stored as operator-attested and never as provider-verified',
      v_n = 1, v_n::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_m1), true);
    v_res := public.merchant_settlement_request_create(50000, 'qa-p7-b-'||v_sfx, v_s1, 'P7 reject');
    v_reqR := (v_res->>'request_id')::uuid; v_ordR := (v_res->>'payout_order_id')::uuid;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    SELECT balance_gnf INTO v_b0 FROM public.wallets WHERE owner_user_id=v_m1 AND party_type='merchant';
    PERFORM public.payout_reject_release(v_ordR, 'qa p7 release');
    BEGIN PERFORM public.payout_reject_release(v_ordR, 'qa p7 release replay'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT balance_gnf INTO v_b1 FROM public.wallets WHERE owner_user_id=v_m1 AND party_type='merchant';
    SELECT count(*) INTO v_n FROM public.payout_orders WHERE id = v_ordR AND status IN ('released','rejected');
    r := r || public._qa_s13_ok('C8 replaying a rejected settlement release moves no money and releases once',
      v_b1 = v_b0 AND v_n = 1, format('bal=%s status_rows=%s err=%s', v_b1, v_n, v_err));

    ---------------------------------------------------------------- Envoyer replay + claims replay
    PERFORM public._qa_s13_flag('envoyer_enabled', true);
    PERFORM public._qa_s13_flag('envoyer_declared_value_enabled', true);
    PERFORM public._qa_s13_flag('envoyer_claims_enabled', true);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_c1), true);
    v_q := public.package_delivery_quote(9.5370,-13.6785, 9.5570,-13.6560,'small_parcel','A','B');
    v_qid := (v_q->>'quote_id')::uuid;
    PERFORM public.package_evidence_register(v_qid, v_c1::text||'/'||v_qid::text||'/p1.jpg','item','image/jpeg',1024);
    v_res := public.package_delivery_create_checkout(v_qid,'Ami Diallo','622000001',
      NULL,NULL,'p7pkg-'||v_sfx,'622000002','orange_money',false,NULL, 200000, 'chop_pay', true,
      'Je declare la valeur de mon colis');
    v_pkg := (v_res->>'package_id')::uuid;
    SELECT mission_id INTO v_mis FROM public.package_deliveries WHERE id = v_pkg;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_d1), true);
    PERFORM public.mission_claim(v_mis);
    SELECT pickup_code, delivery_code INTO v_pcode, v_dcode
      FROM public.package_delivery_secrets WHERE package_id = v_pkg;
    BEGIN PERFORM public.package_verify_pickup(v_pkg, '000000'); EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN v_res := public.package_verify_pickup(v_pkg, '000000');
    EXCEPTION WHEN OTHERS THEN v_res := jsonb_build_object('ok', false, 'error', SQLERRM); END;
    SELECT count(*) INTO v_n FROM public.package_delivery_secrets
     WHERE package_id = v_pkg AND pickup_verified_at IS NULL;
    r := r || public._qa_s13_ok('C9 repeated wrong pickup codes never establish custody',
      COALESCE((v_res->>'ok')::boolean,false) = false AND v_n = 1, v_res::text);
    PERFORM public.package_verify_pickup(v_pkg, v_pcode);
    SELECT balance_gnf INTO v_b0 FROM public.wallets WHERE owner_user_id=v_d1 AND party_type='driver';
    v_res := public.package_verify_delivery(v_pkg, v_dcode, 'Ami Diallo');
    SELECT balance_gnf INTO v_b1 FROM public.wallets WHERE owner_user_id=v_d1 AND party_type='driver';
    r := r || public._qa_s13_ok('C10 a verified delivery settles the courier once',
      COALESCE((v_res->>'ok')::boolean,false) AND v_b1 > v_b0, format('%s -> %s', v_b0, v_b1));
    BEGIN v_res := public.package_verify_delivery(v_pkg, v_dcode, 'Ami Diallo'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT balance_gnf INTO v_b0 FROM public.wallets WHERE owner_user_id=v_d1 AND party_type='driver';
    r := r || public._qa_s13_ok('C11 replaying the delivery confirmation pays the courier nothing extra',
      v_b0 = v_b1, format('%s (%s)', v_b0, v_err));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_c1), true);
    v_q := public.package_delivery_quote(9.5370,-13.6785, 9.5570,-13.6560,'small_parcel','A','B');
    v_qid2 := (v_q->>'quote_id')::uuid;
    PERFORM public.package_evidence_register(v_qid2, v_c1::text||'/'||v_qid2::text||'/p2.jpg','item','image/jpeg',1024);
    v_res := public.package_delivery_create_checkout(v_qid2,'Ami Diallo','622000001',
      NULL,NULL,'p7pkg2-'||v_sfx,'622000002','orange_money',false,NULL, 200000, 'chop_pay', true,
      'Je declare la valeur de mon colis');
    v_pkg2 := (v_res->>'package_id')::uuid;
    SELECT mission_id INTO v_mis2 FROM public.package_deliveries WHERE id = v_pkg2;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_d2), true);
    PERFORM public.mission_claim(v_mis2);
    SELECT pickup_code INTO v_pcode FROM public.package_delivery_secrets WHERE package_id = v_pkg2;
    PERFORM public.package_verify_pickup(v_pkg2, v_pcode);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_c1), true);
    PERFORM public.package_claim_open(v_pkg2, 'colis perdu');
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    SELECT balance_gnf INTO v_b0 FROM public.wallets WHERE owner_user_id=v_c1 AND party_type='client';
    v_res := public.admin_package_claim_resolve(v_pkg2,'customer_upheld','qa p7 claim','evidence/p7.jpg', 50000);
    SELECT balance_gnf INTO v_b1 FROM public.wallets WHERE owner_user_id=v_c1 AND party_type='client';
    r := r || public._qa_s13_ok('C12 a claim adjudication compensates the customer exactly once',
      v_b1 - v_b0 = 50000, format('%s -> %s', v_b0, v_b1));
    BEGIN v_res := public.admin_package_claim_resolve(v_pkg2,'customer_upheld','qa p7 replay','evidence/p7.jpg', 50000);
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT balance_gnf INTO v_b0 FROM public.wallets WHERE owner_user_id=v_c1 AND party_type='client';
    r := r || public._qa_s13_ok('C13 replaying the claim adjudication pays zero additional compensation',
      v_b0 = v_b1, format('%s (%s)', v_b0, v_err));

    ---------------------------------------------------------------- Orange Money inbound replay + sandbox isolation
    v_code := 'P7OM'||v_sfx;
    v_case := public._qa_s13_om_case(v_c1, v_god, 'client', 75000, v_acct, v_code, 75000, v_phone1, v_acct);
    v_topup := (v_case->>'topup_id')::uuid; v_evt := (v_case->>'event_id')::uuid;
    r := r || public._qa_s13_ok('C14 an exactly matching Orange Money receipt credits the customer once',
      (v_case->>'delta')::bigint = 75000 AND COALESCE(v_case->>'status','') = 'credited', v_case::text);
    SELECT balance_gnf INTO v_b0 FROM public.wallets WHERE owner_user_id=v_c1 AND party_type='client';
    PERFORM set_config('request.jwt.claims','',true);
    BEGIN PERFORM public.wallet_topup_om_credit(v_evt, v_topup); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT balance_gnf INTO v_b1 FROM public.wallets WHERE owner_user_id=v_c1 AND party_type='client';
    r := r || public._qa_s13_ok('C15 replaying the Orange Money credit moves zero additional GNF',
      v_b1 = v_b0, format('%s (%s)', v_b1, v_err));
    SELECT count(*) INTO v_n FROM public.wallet_transactions
     WHERE metadata->>'topup_request_id' = v_topup::text;
    r := r || public._qa_s13_ok('C16 at most one wallet transaction exists for the credited top-up',
      v_n <= 1, v_n::text);

    INSERT INTO public.payment_provider_events
      (provider, provider_transaction_id, payer_phone, amount_gnf, status,
       om_code_normalized, receiving_account_id, is_sandbox, environment)
    VALUES ('orange_money','P7SBX-'||v_sfx, v_phone2, 90000, 'successful',
            'P7SBX'||v_sfx, v_acct, true, 'sandbox')
    RETURNING id INTO v_evt;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_c2), true);
    v_res := to_jsonb(public.wallet_topup_om_create(90000, v_acct));
    v_topup := (v_res->>'id')::uuid;
    PERFORM public.submit_customer_om_code(v_topup, 'P7SBX'||v_sfx);
    PERFORM set_config('request.jwt.claims','',true);
    SELECT balance_gnf INTO v_b0 FROM public.wallets WHERE owner_user_id=v_c2 AND party_type='client';
    BEGIN v_res := public.om_auto_match(v_evt);
    EXCEPTION WHEN OTHERS THEN v_res := jsonb_build_object('status','rejected','error',SQLERRM); END;
    SELECT balance_gnf INTO v_b1 FROM public.wallets WHERE owner_user_id=v_c2 AND party_type='client';
    SELECT status::text INTO v_err FROM public.topup_requests WHERE id = v_topup;
    r := r || public._qa_s13_ok('D1 a sandbox provider receipt never credits a production top-up',
      v_b1 = v_b0 AND v_err <> 'credited', format('%s %s %s', v_res->>'status', v_err, v_b1));
    r := r || public._qa_s13_ok('D2 the environment mismatch is refused explicitly, not silently remapped',
      COALESCE(v_res->>'status','') IN ('awaiting_customer_code','needs_review','rejected','no_match'), v_res::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_c2), true);
    BEGIN
      PERFORM public.om_sandbox_create_ride_intent('moto'::ride_mode, 9.5,-13.7,9.6,-13.6, gen_random_uuid(), NULL, NULL);
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT count(*) INTO v_n FROM public.payment_intents WHERE is_sandbox = true AND created_at >= v_t0;
    r := r || public._qa_s13_ok('D3 with the sandbox rail OFF no sandbox financial object can be created',
      v_err <> 'NO_ERROR' AND v_n = 0, format('%s intents=%s', v_err, v_n));

    ---------------------------------------------------------------- P2P replay under an isolated stage
    PERFORM public._qa_s13_flag('chop_pay_p2p_enabled', true);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_c1), true);
    SELECT balance_gnf INTO v_b0 FROM public.wallets WHERE owner_user_id=v_c1 AND party_type='client';
    v_ptx := public.wallet_p2p_transfer(v_c2, 10000, 'qa p7', 'p7-idem-'||v_sfx);
    SELECT balance_gnf INTO v_b1 FROM public.wallets WHERE owner_user_id=v_c1 AND party_type='client';
    r := r || public._qa_s13_ok('C17 a P2P transfer debits the sender exactly once',
      v_b0 - v_b1 = 10000, format('%s -> %s', v_b0, v_b1));
    BEGIN v_ptx := public.wallet_p2p_transfer(v_c2, 10000, 'qa p7', 'p7-idem-'||v_sfx); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT balance_gnf INTO v_b0 FROM public.wallets WHERE owner_user_id=v_c1 AND party_type='client';
    SELECT count(*) INTO v_n FROM public.wallet_transactions
     WHERE metadata->>'idempotency_key' = 'p7-idem-'||v_sfx;
    r := r || public._qa_s13_ok('C18 replaying the same P2P idempotency key moves zero additional GNF',
      v_b0 = v_b1 AND v_n = 1, format('bal=%s tx=%s err=%s', v_b0, v_n, v_err));
    PERFORM public._qa_s13_flag('chop_pay_p2p_enabled', false);

    ---------------------------------------------------------------- B. security / authorization
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_c2), true);
    SELECT id INTO v_tx FROM public.wallet_transactions
     WHERE to_wallet_id = (SELECT id FROM public.wallets WHERE owner_user_id=v_c1 AND party_type='client')
     ORDER BY created_at DESC LIMIT 1;
    BEGIN v_res := public.customer_receipt(v_tx); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; v_res := NULL; END;
    r := r || public._qa_s13_ok('B1 a customer cannot open another customer receipt',
      v_tx IS NOT NULL AND (v_err <> 'NO_ERROR' OR v_res IS NULL OR COALESCE(v_res->>'transaction_id','') = ''),
      format('%s %s', v_err, COALESCE(v_res::text,'null')));
    v_res := public.customer_finance_overview();
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE owner_user_id=v_c2 AND party_type='client';
    r := r || public._qa_s13_ok('B2 the customer finance overview only ever describes the caller',
      (v_res->>'balance_gnf')::bigint = v_b, format('%s vs %s', v_res->>'balance_gnf', v_b));
    BEGIN PERFORM public.merchant_settlement_request_create(10000,'qa-p7-x-'||v_sfx, v_s1, 'x'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B3 a non-owner cannot request a settlement for another merchant store',
      v_err <> 'NO_ERROR', v_err);
    BEGIN v_res := public.driver_balance_summary(v_d1); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; v_res := NULL; END;
    r := r || public._qa_s13_ok('B4 a customer cannot read a driver financial summary',
      v_err <> 'NO_ERROR' OR v_res IS NULL OR COALESCE(v_res->>'driver_user_id','') <> v_d1::text,
      format('%s %s', v_err, COALESCE(v_res::text,'null')));
    BEGIN PERFORM public.finance_confirm_manual_om_payout(v_ord, 'OM-P7-X', true, NULL); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B5 an ordinary customer cannot confirm a Finance payout',
      v_err = 'NOT_AUTHORIZED', v_err);
    r := r || public._qa_s13_ok('B6 an unauthenticated caller never gains Finance privilege',
      public._finance_privileged(NULL) = false, NULL);
    PERFORM set_config('request.jwt.claims','',true);

    UPDATE public.wallets SET status='frozen' WHERE owner_user_id=v_c2 AND party_type='client';
    PERFORM public._qa_s13_flag('chop_pay_p2p_enabled', true);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_c2), true);
    BEGIN PERFORM public.wallet_p2p_transfer(v_c1, 5000, 'qa frozen', 'p7-frozen-'||v_sfx); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B7 a frozen wallet is blocked before any money mutation',
      v_err <> 'NO_ERROR', v_err);
    PERFORM public._qa_s13_flag('chop_pay_p2p_enabled', false);
    UPDATE public.wallets SET status='active' WHERE owner_user_id=v_c2 AND party_type='client';
    PERFORM set_config('request.jwt.claims','',true);

    SELECT count(*) INTO v_n FROM pg_proc p
     WHERE p.pronamespace='public'::regnamespace AND p.prosecdef
       AND (p.proname LIKE 'finance\_%' OR p.proname LIKE 'wallet\_%' OR p.proname LIKE 'payout\_%'
            OR p.proname LIKE 'merchant\_settlement\_%' OR p.proname LIKE 'om\_%' OR p.proname LIKE 'package\_%')
       AND (p.proconfig IS NULL OR NOT EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%'));
    r := r || public._qa_s13_ok('B8 every finance security-definer function pins a fixed search path', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM pg_proc p
     WHERE p.pronamespace='public'::regnamespace
       AND (p.proname LIKE '\_ledger\_%' OR p.proname LIKE '\_payout\_%' OR p.proname LIKE '\_merchant\_%'
            OR p.proname LIKE '\_chop\_pay\_%' OR p.proname LIKE '\_cash\_order\_%' OR p.proname LIKE '\_package\_%'
            OR p.proname LIKE '\_driver\_%' OR p.proname LIKE '\_customer\_cancellation\_%')
       AND (has_function_privilege('anon', p.oid,'EXECUTE') OR has_function_privilege('authenticated', p.oid,'EXECUTE'));
    r := r || public._qa_s13_ok('B9 raw money-moving primitives stay service-role only', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM pg_proc p
     WHERE p.pronamespace='public'::regnamespace AND p.proname LIKE '\_qa\_s13%'
       AND (has_function_privilege('anon', p.oid,'EXECUTE') OR has_function_privilege('authenticated', p.oid,'EXECUTE'));
    r := r || public._qa_s13_ok('B10 no QA harness helper is executable by anon or signed-in users', v_n = 0, v_n::text);

    SELECT count(*) INTO v_n FROM (
      SELECT t FROM unnest(ARRAY['ledger_journals','ledger_postings','wallets','wallet_transactions',
        'merchant_payables','payout_orders','payout_provider_evidence','payout_settlement_allocations',
        'claims_reserves','customer_cancellation_debts','driver_promo_credits','finance_policies',
        'provider_fee_schedules','payment_provider_events','merchant_settlement_requests']) t
       WHERE has_table_privilege('anon','public.'||t,'SELECT')
          OR has_table_privilege('anon','public.'||t,'INSERT')
          OR has_table_privilege('anon','public.'||t,'UPDATE')
          OR has_table_privilege('anon','public.'||t,'DELETE')) z;
    r := r || public._qa_s13_ok('B11 anonymous callers hold no privilege on any finance truth table', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM (
      SELECT t FROM unnest(ARRAY['ledger_journals','ledger_postings','wallets','wallet_transactions',
        'merchant_payables','payout_orders','payout_provider_evidence','payout_settlement_allocations',
        'claims_reserves','customer_cancellation_debts','driver_promo_credits','finance_policies',
        'provider_fee_schedules','payment_provider_events']) t
       WHERE has_table_privilege('authenticated','public.'||t,'INSERT')
          OR has_table_privilege('authenticated','public.'||t,'UPDATE')
          OR has_table_privilege('authenticated','public.'||t,'DELETE')) z;
    r := r || public._qa_s13_ok('B12 signed-in users can never write a finance truth table directly', v_n = 0, v_n::text);

    SELECT count(*) INTO v_n FROM storage.buckets WHERE id='package-evidence' AND public = false;
    r := r || public._qa_s13_ok('B13 the Envoyer evidence bucket is private', v_n = 1, v_n::text);

    ---------------------------------------------------------------- H. accounting truth inside the fixture
    SELECT count(*) INTO v_n FROM (
      SELECT j.id FROM public.ledger_journals j
       JOIN public.ledger_postings p ON p.journal_id = j.id
       GROUP BY j.id HAVING sum(p.amount_gnf) <> 0) z;
    r := r || public._qa_s13_ok('H1 no imbalanced journal exists anywhere inside the fixture', v_n = 0, v_n::text);
    SELECT COALESCE(sum(amount_gnf),0) INTO v_n FROM public.ledger_postings;
    r := r || public._qa_s13_ok('H2 the global ledger posting sum is zero inside the fixture', v_n = 0, v_n::text);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    v_ov2 := public.finance_treasury_overview();
    r := r || public._qa_s13_ok('H3 the treasury still reports a balanced global ledger after every movement',
      (v_ov2->>'ledger_global_sum_gnf')::bigint = 0, v_ov2->>'ledger_global_sum_gnf');
    SELECT count(*) INTO v_n FROM public.finance_treasury_exceptions() t
     WHERE t.code IN ('LEDGER_GLOBAL_IMBALANCE','LEDGER_JOURNAL_IMBALANCE');
    r := r || public._qa_s13_ok('H4 no ledger imbalance exception is raised for the fixture activity', v_n = 0, v_n::text);
    PERFORM set_config('request.jwt.claims','',true);

    RAISE EXCEPTION 'QA_S13_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_S13_ROLLBACK' THEN
      r := r || public._qa_s13_ok('HARNESS_PART7_UNEXPECTED_ABORT', false, SQLERRM);
    END IF;
  END;

  PERFORM set_config('request.jwt.claims','',true);
  SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;
  r := r || public._qa_s13_ok('Z7.1 the master wallet is exactly back to its live balance after rollback',
    v_master1 = v_master0 AND v_master1 = -100435, v_master1::text);
  SELECT held_gnf INTO v_n FROM public.wallets WHERE party_type='master';
  r := r || public._qa_s13_ok('Z7.2 the master wallet holds nothing after rollback', v_n = 0, v_n::text);
  SELECT COALESCE(sum(amount_gnf),0) INTO v_n FROM public.ledger_postings;
  r := r || public._qa_s13_ok('Z7.3 the global ledger posting sum is zero after rollback', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM (
    SELECT j.id FROM public.ledger_journals j
     JOIN public.ledger_postings p ON p.journal_id = j.id
     GROUP BY j.id HAVING sum(p.amount_gnf) <> 0) z;
  r := r || public._qa_s13_ok('Z7.4 no imbalanced journal survives the rollback', v_n = 0, v_n::text);
  r := r || public._qa_s13_ok('Z7.5 live feature flags are byte-identical after the fixture', v_flags1 = v_flags0, NULL);
  r := r || public._qa_s13_ok('Z7.6 Stage 5, Stage 6 and Stage 7 are OFF in production after the run',
    NOT public._finance_flag('merchant_om_settlement_enabled')
    AND NOT public._finance_flag('driver_cashout_enabled')
    AND NOT public._finance_flag('chop_pay_p2p_enabled'), NULL);
  r := r || public._qa_s13_ok('Z7.7 the Orange Money top-up rail is still ON',
    public._finance_flag('om_topup_enabled'), NULL);
  r := r || public._qa_s13_ok('Z7.8 the Orange Money sandbox rail is OFF in production',
    NOT public._finance_flag('om_sandbox_enabled'), NULL);
  SELECT count(*) INTO v_n FROM auth.users WHERE email LIKE 'qa-s13-p7%@qa.invalid';
  r := r || public._qa_s13_ok('Z7.9 no QA user survives the rollback', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.merchant_stores WHERE slug LIKE 'qa-s13-p7-%';
  r := r || public._qa_s13_ok('Z7.10 no QA merchant store survives the rollback', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.merchant_payables WHERE source_module='qa_s13';
  r := r || public._qa_s13_ok('Z7.11 no QA merchant payable survives the rollback', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.payout_orders;
  r := r || public._qa_s13_ok('Z7.12 no payout order survives the rollback', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.payout_provider_evidence;
  r := r || public._qa_s13_ok('Z7.13 no payout evidence survives the rollback', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.payment_provider_events WHERE om_code_normalized LIKE 'P7%';
  r := r || public._qa_s13_ok('Z7.14 no QA provider event survives the rollback', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.payment_receiving_accounts WHERE label LIKE 'QA S13 P7%';
  r := r || public._qa_s13_ok('Z7.15 no QA receiving account survives the rollback', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.customer_cancellation_debts WHERE source_module='qa_s13_p7';
  r := r || public._qa_s13_ok('Z7.16 no QA cancellation debt survives the rollback', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.package_deliveries WHERE idempotency_key LIKE 'p7pkg%';
  r := r || public._qa_s13_ok('Z7.17 no QA shipment survives the rollback', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM pg_proc p
   WHERE p.pronamespace='public'::regnamespace AND p.proname LIKE '\_qa\_s13%'
     AND (has_function_privilege('anon', p.oid,'EXECUTE') OR has_function_privilege('authenticated', p.oid,'EXECUTE'));
  r := r || public._qa_s13_ok('Z7.18 no QA harness function is executable by anon or authenticated', v_n = 0, v_n::text);

  RETURN public._qa_s13_summary(7, r);
END $function$;

REVOKE ALL ON FUNCTION public._qa_s13_run7() FROM PUBLIC, anon, authenticated;

SELECT public._qa_s13_run7();