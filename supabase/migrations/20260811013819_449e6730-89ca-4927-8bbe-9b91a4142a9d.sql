-- Part 1: wallets may already exist (auto-provisioned) -> upsert
CREATE OR REPLACE FUNCTION public._qa_s7_wallet(p_owner uuid, p_party party_type, p_bal bigint, p_held bigint)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.wallets(owner_user_id, party_type, balance_gnf, held_gnf)
  VALUES (p_owner, p_party, p_bal, p_held)
  ON CONFLICT (owner_user_id, party_type)
  DO UPDATE SET balance_gnf = EXCLUDED.balance_gnf, held_gnf = EXCLUDED.held_gnf
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION public._qa_s7_run1()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r jsonb := '[]'::jsonb; v_pass int; v_total int;
  v_c uuid; v_o uuid; v_wid uuid; v_ov jsonb; v_err text;
  v_n bigint; v_pay uuid; v_rec jsonb; v_master0 bigint; v_master1 bigint;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  BEGIN
    v_c := gen_random_uuid(); v_o := gen_random_uuid();
    PERFORM public._qa_s7_user(v_c,'cust'); PERFORM public._qa_s7_user(v_o,'other');
    v_wid := public._qa_s7_wallet(v_c,'client',200000,50000);
    PERFORM public._qa_s7_wallet(v_o,'client',777000,0);

    INSERT INTO public.mission_financial_holds(party_type, party_user_id, driver_user_id,
      mission_type, source_module, source_id, kind, amount_gnf, customer_gnf, state)
    VALUES ('client', v_c, NULL, 'ride','qa_s7', gen_random_uuid(), 'customer_payment',
            50000, 50000, 'held');

    INSERT INTO public.wallet_transactions(reference,type,status,amount_gnf,to_wallet_id,completed_at,description)
    VALUES ('QA-S7-TOPUP-1','topup','completed',300000,v_wid, now(),'Recharge OM QA');
    INSERT INTO public.wallet_transactions(reference,type,status,amount_gnf,from_wallet_id,completed_at,description,related_entity)
    VALUES ('QA-S7-PAY-1','payment','completed',80000,v_wid, now(),'Paiement ChopPay QA','repas')
    RETURNING id INTO v_pay;
    INSERT INTO public.wallet_transactions(reference,type,status,amount_gnf,from_wallet_id,description)
    VALUES ('QA-S7-PAY-PENDING','payment','pending',10000,v_wid,'Paiement en attente QA');
    INSERT INTO public.wallet_transactions(reference,type,status,amount_gnf,to_wallet_id,completed_at,description)
    VALUES ('QA-S7-REFUND-1','refund','completed',20000,v_wid, now(),'Remboursement QA');
    INSERT INTO public.wallet_transactions(reference,type,status,amount_gnf,from_wallet_id,completed_at,description)
    VALUES ('QA-S7-RELEASE-1','release','completed',15000,v_wid, now(),'Liberation de caution QA');
    INSERT INTO public.topup_requests(reference, client_user_id, amount_gnf, confirmation_code,
      status, provider, target_party_type)
    VALUES ('QA-S7-TR-PENDING', v_c, 60000, '000000', 'pending','orange_money','client');

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_c), true);
    v_ov := public.customer_finance_overview();

    r := r || public._qa_s5_ok('A1 balance = canonical wallets.balance_gnf (200000)',
      (v_ov->>'balance_gnf')::bigint = 200000, v_ov->>'balance_gnf');
    r := r || public._qa_s5_ok('A2 held = canonical wallets.held_gnf (50000)',
      (v_ov->>'held_gnf')::bigint = 50000, v_ov->>'held_gnf');
    r := r || public._qa_s5_ok('A3 open holds reconcile to held_gnf',
      (v_ov->>'open_hold_gnf')::bigint = 50000 AND (v_ov->>'holds_reconciled')::boolean,
      v_ov->>'open_hold_gnf');
    r := r || public._qa_s5_ok('A4 available server-computed = 150000',
      (v_ov->>'available_gnf')::bigint = 150000, v_ov->>'available_gnf');
    r := r || public._qa_s5_ok('A5 ecosystem spend = captured spend only (80000)',
      (v_ov->>'ecosystem_spend_gnf')::bigint = 80000, v_ov->>'ecosystem_spend_gnf');
    r := r || public._qa_s5_ok('A6 spend excludes topups, pending payment, refund and release',
      (v_ov->>'ecosystem_spend_gnf')::bigint NOT IN (300000, 90000, 95000));
    r := r || public._qa_s5_ok('A7 credited topup total = 300000 counted once',
      (v_ov->>'topup_credited_gnf')::bigint = 300000, v_ov->>'topup_credited_gnf');
    r := r || public._qa_s5_ok('A8 pending topup surfaced separately (60000 / 1)',
      (v_ov->>'topup_pending_gnf')::bigint = 60000 AND (v_ov->>'topup_pending_count')::int = 1);
    r := r || public._qa_s5_ok('A9 pending topup NOT counted as balance',
      (v_ov->>'balance_gnf')::bigint = 200000);
    r := r || public._qa_s5_ok('A10 refund total = 20000',
      (v_ov->>'refund_total_gnf')::bigint = 20000, v_ov->>'refund_total_gnf');

    SELECT count(*) INTO v_n FROM public.customer_finance_history(100) h WHERE h.reference='QA-S7-TOPUP-1';
    r := r || public._qa_s5_ok('A11 credited topup appears exactly once in history', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.customer_finance_history(100) h
     WHERE h.source='topup_request' AND h.counts_as_balance = false;
    r := r || public._qa_s5_ok('A12 pending topup event flagged as not counting toward balance', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.customer_finance_history(100) h WHERE h.kind='refund';
    r := r || public._qa_s5_ok('A13 exactly one refund event; release not mislabeled as refund', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.customer_finance_history(100) h WHERE h.kind='release';
    r := r || public._qa_s5_ok('A14 release event kept as its own kind', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.customer_finance_history(100) h WHERE h.direction='in' AND h.kind='payment';
    r := r || public._qa_s5_ok('A15 outbound payment not shown as inbound', v_n = 0, v_n::text);

    v_rec := public.customer_receipt(v_pay);
    r := r || public._qa_s5_ok('A16 receipt amount matches captured transaction (80000)',
      (v_rec->>'amount_gnf')::bigint = 80000 AND v_rec->>'direction' = 'out'
      AND v_rec->>'status' = 'completed', v_rec->>'amount_gnf');
    r := r || public._qa_s5_ok('A17 receipt carries stable source reference',
      v_rec->>'reference' = 'QA-S7-PAY-1', v_rec->>'reference');

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_o), true);
    v_ov := public.customer_finance_overview();
    r := r || public._qa_s5_ok('A18 cross-customer read returns only the caller''s own truth',
      (v_ov->>'balance_gnf')::bigint = 777000, v_ov->>'balance_gnf');
    BEGIN v_rec := public.customer_receipt(v_pay); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s5_ok('A19 cross-customer receipt denied', v_err LIKE '%RECEIPT_NOT_FOUND%', v_err);

    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN v_ov := public.customer_finance_overview(); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s5_ok('A20 anonymous read denied', v_err LIKE '%NOT_AUTHENTICATED%', v_err);

    RAISE EXCEPTION 'QA_S7_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_S7_ROLLBACK' THEN
      r := r || public._qa_s5_ok('HARNESS_PART1_UNEXPECTED_ABORT', false, SQLERRM);
    END IF;
  END;
  PERFORM set_config('request.jwt.claims', '', true);

  SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
  r := r || public._qa_s5_ok('Z1 master wallet unchanged by rollback',
    v_master1 = v_master0 AND v_master1 = -100435, v_master1::text);

  SELECT count(*) FILTER (WHERE (x->>'ok')::boolean), count(*) INTO v_pass, v_total
    FROM jsonb_array_elements(r) x;
  RETURN jsonb_build_object('part',1,'total',v_total,'passed',v_pass,'failed',v_total-v_pass,
    'failures',(SELECT COALESCE(jsonb_agg(x),'[]'::jsonb) FROM jsonb_array_elements(r) x
                 WHERE NOT (x->>'ok')::boolean));
END $$;

-- Part 2: promo credit needs grant_key; wallets upserted
CREATE OR REPLACE FUNCTION public._qa_s7_run2()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r jsonb := '[]'::jsonb; v_pass int; v_total int;
  v_d uuid; v_d2 uuid; v_wid uuid; v_sum jsonb; v_el jsonb; v_err text; v_n bigint;
BEGIN
  BEGIN
    v_d := gen_random_uuid(); v_d2 := gen_random_uuid();
    PERFORM public._qa_s7_user(v_d,'drv'); PERFORM public._qa_s7_user(v_d2,'drv2');
    INSERT INTO public.driver_profiles(user_id,status,vehicle_type)
    VALUES (v_d,'approved','moto'),(v_d2,'approved','moto') ON CONFLICT DO NOTHING;
    v_wid := public._qa_s7_wallet(v_d,'driver',500000,100000);
    PERFORM public._qa_s7_wallet(v_d2,'driver',10000,0);
    INSERT INTO public.driver_promo_credits(driver_user_id, grant_key, granted_gnf, consumed_gnf, reversed_gnf, state)
    VALUES (v_d, 'qa-s7-promo-'||substr(v_d::text,1,8), 25000, 0, 0, 'active');
    INSERT INTO public.mission_financial_holds(party_type, party_user_id, driver_user_id,
      mission_type, source_module, source_id, kind, amount_gnf, unrestricted_gnf, promo_gnf, state)
    VALUES ('driver', v_d, v_d, 'ride','qa_s7', gen_random_uuid(), 'collateral',
            100000, 75000, 25000, 'held');

    INSERT INTO public.topup_requests(reference, client_user_id, amount_gnf, confirmation_code,
      status, provider, target_party_type)
    VALUES ('QA-S7-DRV-TOPUP', v_d, 120000, '000000','pending','orange_money','driver'),
           ('QA-S7-DRV-CLIENT-TOPUP', v_d, 5000, '000000','pending','orange_money','client');

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_d), true);
    v_sum := public.driver_balance_summary(NULL);

    r := r || public._qa_s5_ok('B1 driver total = canonical wallet balance (500000)',
      (v_sum->>'balance_gnf')::bigint = 500000, v_sum->>'balance_gnf');
    r := r || public._qa_s5_ok('B2 held = canonical wallets.held_gnf (100000)',
      (v_sum->>'held_gnf')::bigint = 100000, v_sum->>'held_gnf');
    r := r || public._qa_s5_ok('B3 open source-bucket holds reconcile to held_gnf',
      (SELECT COALESCE(SUM(amount_gnf-captured_gnf-released_gnf),0) FROM public.mission_financial_holds
        WHERE driver_user_id=v_d AND state IN ('held','frozen','partially_captured'))
      = (v_sum->>'held_gnf')::bigint);
    r := r || public._qa_s5_ok('B4 available server-computed (400000)',
      (v_sum->>'available_gnf')::bigint = 400000, v_sum->>'available_gnf');
    r := r || public._qa_s5_ok('B5 promo remaining = 25000 from promo credits ledger',
      (v_sum->>'promo_remaining_gnf')::bigint = 25000, v_sum->>'promo_remaining_gnf');
    r := r || public._qa_s5_ok('B6 promo held = 25000 (attribution survives the hold)',
      (v_sum->>'promo_held_gnf')::bigint = 25000, v_sum->>'promo_held_gnf');
    r := r || public._qa_s5_ok('B7 promo available = 0 while fully held',
      (v_sum->>'promo_available_gnf')::bigint = 0, v_sum->>'promo_available_gnf');
    r := r || public._qa_s5_ok('B8 unrestricted available = 400000',
      (v_sum->>'unrestricted_available_gnf')::bigint = 400000);
    r := r || public._qa_s5_ok('B9 identity: unrestricted_available + promo_available = available',
      (v_sum->>'unrestricted_available_gnf')::bigint + (v_sum->>'promo_available_gnf')::bigint
      = (v_sum->>'available_gnf')::bigint);
    r := r || public._qa_s5_ok('B10 withdrawable never includes the restricted promo',
      (v_sum->>'withdrawable_gnf')::bigint = (v_sum->>'unrestricted_available_gnf')::bigint);
    r := r || public._qa_s5_ok('B11 collateral bucket exposed from holds (100000)',
      (v_sum->>'collateral_held_gnf')::bigint = 100000, v_sum->>'collateral_held_gnf');

    v_el := public.driver_financial_eligibility('ride', 100000, NULL);
    r := r || public._qa_s5_ok('B12 eligibility comes from server rule (eligible = available >= required)',
      (v_el->>'eligible')::boolean = ((v_el->>'available_gnf')::bigint >= (v_el->>'required_gnf')::bigint));
    r := r || public._qa_s5_ok('B13 eligibility available matches the balance read model',
      (v_el->>'available_gnf')::bigint = (v_sum->>'available_gnf')::bigint);

    UPDATE public.wallets SET held_gnf = 500000 WHERE id = v_wid;
    UPDATE public.mission_financial_holds SET amount_gnf = 500000, unrestricted_gnf = 475000
     WHERE driver_user_id = v_d;
    v_el := public.driver_financial_eligibility('ride', 100000, NULL);
    r := r || public._qa_s5_ok('B14 available drops to 0 when everything is held',
      (v_el->>'available_gnf')::bigint = 0, v_el->>'available_gnf');
    r := r || public._qa_s5_ok('B15 eligibility flips correctly against the server requirement',
      (v_el->>'eligible')::boolean = (0 >= (v_el->>'required_gnf')::bigint)
      AND (v_el->>'shortfall_gnf')::bigint = GREATEST((v_el->>'required_gnf')::bigint,0));

    SELECT count(*) INTO v_n FROM public.driver_topup_history(50);
    r := r || public._qa_s5_ok('B16 driver top-up history is driver-target scoped (1 row)', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.driver_topup_history(50) t WHERE t.reference='QA-S7-DRV-CLIENT-TOPUP';
    r := r || public._qa_s5_ok('B17 client top-up does not leak into driver history', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.list_my_topup_requests(50) t WHERE t.reference='QA-S7-DRV-TOPUP';
    r := r || public._qa_s5_ok('B18 driver top-up does not leak into customer history', v_n = 0, v_n::text);

    BEGIN v_sum := public.driver_balance_summary(v_d2); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s5_ok('B19 cross-driver balance read denied', v_err LIKE '%Not authorized%', v_err);

    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN v_n := (SELECT count(*) FROM public.driver_topup_history(5)); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s5_ok('B20 anonymous driver top-up history returns nothing',
      v_err = 'NO_ERROR' AND v_n = 0, v_err || '/' || COALESCE(v_n::text,'null'));

    RAISE EXCEPTION 'QA_S7_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_S7_ROLLBACK' THEN
      r := r || public._qa_s5_ok('HARNESS_PART2_UNEXPECTED_ABORT', false, SQLERRM);
    END IF;
  END;
  PERFORM set_config('request.jwt.claims', '', true);

  SELECT count(*) FILTER (WHERE (x->>'ok')::boolean), count(*) INTO v_pass, v_total
    FROM jsonb_array_elements(r) x;
  RETURN jsonb_build_object('part',2,'total',v_total,'passed',v_pass,'failed',v_total-v_pass,
    'failures',(SELECT COALESCE(jsonb_agg(x),'[]'::jsonb) FROM jsonb_array_elements(r) x
                 WHERE NOT (x->>'ok')::boolean));
END $$;

-- Part 3: audit_logs.target_id is text; wallets upserted
CREATE OR REPLACE FUNCTION public._qa_s7_run3()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r jsonb := '[]'::jsonb; v_pass int; v_total int;
  v_m uuid; v_m2 uuid; v_s uuid; v_s2 uuid; v_ov jsonb; v_res jsonb; v_err text; v_n bigint;
  v_bal bigint; v_held bigint; v_rid uuid;
BEGIN
  BEGIN
    v_m := gen_random_uuid(); v_m2 := gen_random_uuid();
    PERFORM public._qa_s7_user(v_m,'merch'); PERFORM public._qa_s7_user(v_m2,'merch2');
    INSERT INTO public.merchant_stores(owner_user_id, name, slug)
    VALUES (v_m,'QA S7 Store','qa-s7-store-'||substr(v_m::text,1,8)) RETURNING id INTO v_s;
    INSERT INTO public.merchant_stores(owner_user_id, name, slug)
    VALUES (v_m2,'QA S7 Store 2','qa-s7-store2-'||substr(v_m2::text,1,8)) RETURNING id INTO v_s2;
    PERFORM public._qa_s7_wallet(v_m,'merchant',400000,0);
    PERFORM public._qa_s7_wallet(v_m2,'merchant',1000,0);

    INSERT INTO public.merchant_payables(payable_key, source_module, source_id, merchant_store_id,
      merchant_user_id, subtotal_gnf, amount_gnf, funded_gnf, settled_gnf, state)
    VALUES ('qa-s7-p1','qa_s7',gen_random_uuid(),v_s,v_m,150000,150000,150000,0,'funded'),
           ('qa-s7-p2','qa_s7',gen_random_uuid(),v_s,v_m,90000,90000,0,0,'pending_funding'),
           ('qa-s7-p3','qa_s7',gen_random_uuid(),v_s,v_m,50000,50000,50000,50000,'settled'),
           ('qa-s7-p4','qa_s7',gen_random_uuid(),v_s,v_m,30000,30000,0,0,'reversed');

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_m), true);
    v_ov := public.merchant_finance_overview(NULL);

    r := r || public._qa_s5_ok('C1 sales balance = canonical merchant wallet balance (400000)',
      (v_ov->>'sales_balance_gnf')::bigint = 400000, v_ov->>'sales_balance_gnf');
    r := r || public._qa_s5_ok('C2 pending payable = pending_funding + funded/due unsettled (240000)',
      (v_ov->>'pending_payable_gnf')::bigint = 240000, v_ov->>'pending_payable_gnf');
    r := r || public._qa_s5_ok('C3 pending payable excludes settled and reversed items',
      (v_ov->>'pending_payable_gnf')::bigint NOT IN (290000, 270000));
    r := r || public._qa_s5_ok('C4 funded unsettled = 150000',
      (v_ov->>'funded_unsettled_gnf')::bigint = 150000, v_ov->>'funded_unsettled_gnf');
    r := r || public._qa_s5_ok('C5 settled total = 50000',
      (v_ov->>'settled_total_gnf')::bigint = 50000, v_ov->>'settled_total_gnf');
    r := r || public._qa_s5_ok('C6 reversed total = 30000 (refund/reversal visible once)',
      (v_ov->>'reversed_total_gnf')::bigint = 30000, v_ov->>'reversed_total_gnf');
    r := r || public._qa_s5_ok('C7 eligible settlement = min(available, funded unsettled) = 150000',
      (v_ov->>'eligible_settlement_gnf')::bigint = 150000, v_ov->>'eligible_settlement_gnf');
    r := r || public._qa_s5_ok('C8 settlement rail reported OFF',
      (v_ov->>'settlement_rail_enabled')::boolean = false, v_ov->>'settlement_rail_enabled');

    BEGIN v_res := public.merchant_settlement_request_create(150001,'qa-s7-over-key',v_s,NULL);
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s5_ok('C9 request above eligible amount refused',
      v_err LIKE '%AMOUNT_EXCEEDS_ELIGIBLE%', v_err);

    SELECT balance_gnf, held_gnf INTO v_bal, v_held FROM public.wallets
     WHERE owner_user_id=v_m AND party_type='merchant';
    v_res := public.merchant_settlement_request_create(100000,'qa-s7-key-001',v_s,'QA');
    v_rid := (v_res->>'request_id')::uuid;
    r := r || public._qa_s5_ok('C10 valid request recorded as requested (no settlement)',
      v_res->>'status' = 'requested' AND (v_res->>'duplicate')::boolean = false, v_res::text);

    v_res := public.merchant_settlement_request_create(100000,'qa-s7-key-001',v_s,'QA replay');
    SELECT count(*) INTO v_n FROM public.merchant_settlement_requests WHERE merchant_store_id=v_s;
    r := r || public._qa_s5_ok('C11 replayed idempotency key yields exactly one request',
      (v_res->>'duplicate')::boolean = true AND v_n = 1, v_n::text);

    r := r || public._qa_s5_ok('C12 no merchant funds moved by the request',
      (SELECT balance_gnf FROM public.wallets WHERE owner_user_id=v_m AND party_type='merchant') = v_bal
      AND (SELECT held_gnf FROM public.wallets WHERE owner_user_id=v_m AND party_type='merchant') = v_held);
    r := r || public._qa_s5_ok('C13 no ledger journal created by the request',
      NOT EXISTS (SELECT 1 FROM public.ledger_journals WHERE source_module='qa_s7'));

    v_ov := public.merchant_finance_overview(v_s);
    r := r || public._qa_s5_ok('C14 open request reduces the eligible amount to 50000',
      (v_ov->>'eligible_settlement_gnf')::bigint = 50000
      AND (v_ov->>'open_request_gnf')::bigint = 100000, v_ov->>'eligible_settlement_gnf');

    SELECT count(*) INTO v_n FROM public.merchant_settlement_requests_list(v_s, 20) l
     WHERE l.status='requested' AND l.settled_at IS NULL;
    r := r || public._qa_s5_ok('C15 history shows requested state with no settlement evidence', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.merchant_settlement_requests_list(v_s, 20) l WHERE l.status='settled';
    r := r || public._qa_s5_ok('C16 nothing marked settled while the rail is OFF', v_n = 0, v_n::text);
    r := r || public._qa_s5_ok('C17 request audit-logged',
      EXISTS (SELECT 1 FROM public.audit_logs WHERE target_id = v_rid::text
               AND action = 'merchant.settlement_request.created'));

    BEGIN
      UPDATE public.merchant_settlement_requests SET amount_gnf = 999 WHERE id = v_rid;
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s5_ok('C18 requested amount immutable',
      v_err LIKE '%MERCHANT_SETTLEMENT_REQUEST_IMMUTABLE%', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_m2), true);
    BEGIN v_ov := public.merchant_finance_overview(v_s); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s5_ok('C19 cross-merchant overview denied', v_err LIKE '%NOT_AUTHORIZED%', v_err);
    BEGIN v_res := public.merchant_settlement_request_create(1000,'qa-s7-cross-key',v_s,NULL);
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s5_ok('C20 cross-merchant settlement request denied',
      v_err LIKE '%NOT_AUTHORIZED%', v_err);
    BEGIN v_n := (SELECT count(*) FROM public.merchant_settlement_requests_list(v_s, 20)); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s5_ok('C21 cross-merchant settlement history denied',
      v_err LIKE '%NOT_AUTHORIZED%', v_err);

    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN v_ov := public.merchant_finance_overview(v_s); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s5_ok('C22 anonymous merchant read denied',
      v_err LIKE '%NOT_AUTHENTICATED%', v_err);

    RAISE EXCEPTION 'QA_S7_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_S7_ROLLBACK' THEN
      r := r || public._qa_s5_ok('HARNESS_PART3_UNEXPECTED_ABORT', false, SQLERRM);
    END IF;
  END;
  PERFORM set_config('request.jwt.claims', '', true);

  SELECT count(*) FILTER (WHERE (x->>'ok')::boolean), count(*) INTO v_pass, v_total
    FROM jsonb_array_elements(r) x;
  RETURN jsonb_build_object('part',3,'total',v_total,'passed',v_pass,'failed',v_total-v_pass,
    'failures',(SELECT COALESCE(jsonb_agg(x),'[]'::jsonb) FROM jsonb_array_elements(r) x
                 WHERE NOT (x->>'ok')::boolean));
END $$;

-- Part 4: D4 must use effective privilege checks, not the grants view
CREATE OR REPLACE FUNCTION public._qa_s7_run4()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r jsonb := '[]'::jsonb; v_pass int; v_total int; v_n bigint;
BEGIN
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public'
     AND p.proname IN ('customer_finance_overview','customer_finance_history','customer_receipt',
                       'driver_topup_history','merchant_finance_overview',
                       'merchant_settlement_requests_list','merchant_settlement_request_create',
                       'list_my_topup_requests')
     AND array_to_string(p.proacl,',') LIKE '%anon=%';
  r := r || public._qa_s5_ok('D1 no anon EXECUTE on any Slice 7 read model', v_n = 0, v_n::text);

  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public'
     AND p.proname IN ('customer_finance_overview','customer_finance_history','customer_receipt',
                       'driver_topup_history','merchant_finance_overview',
                       'merchant_settlement_requests_list','merchant_settlement_request_create')
     AND (p.prosecdef IS NOT TRUE OR p.proconfig IS NULL
          OR NOT (array_to_string(p.proconfig,',') LIKE '%search_path%'));
  r := r || public._qa_s5_ok('D2 all Slice 7 read models are SECURITY DEFINER with fixed search_path',
    v_n = 0, v_n::text);

  SELECT count(*) INTO v_n FROM pg_policies
   WHERE schemaname='public' AND tablename='merchant_settlement_requests' AND cmd <> 'SELECT';
  r := r || public._qa_s5_ok('D3 settlement requests are read-only to clients (no write policy)',
    v_n = 0, v_n::text);

  r := r || public._qa_s5_ok('D4 no client INSERT/UPDATE/DELETE privilege on settlement requests',
    NOT (has_table_privilege('authenticated','public.merchant_settlement_requests','INSERT')
      OR has_table_privilege('authenticated','public.merchant_settlement_requests','UPDATE')
      OR has_table_privilege('authenticated','public.merchant_settlement_requests','DELETE')
      OR has_table_privilege('anon','public.merchant_settlement_requests','SELECT')));
  r := r || public._qa_s5_ok('D4b authenticated retains SELECT (RLS-scoped)',
    has_table_privilege('authenticated','public.merchant_settlement_requests','SELECT'));

  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public'
     AND p.proname IN ('_ledger_post','_ledger_reverse','wallet_internal_transfer',
                       '_driver_exact_hold_place_internal','_package_authorize_internal')
     AND array_to_string(p.proacl,',') LIKE ANY (ARRAY['%anon=%','%authenticated=%']);
  r := r || public._qa_s5_ok('D5 raw finance primitives remain closed to clients', v_n = 0, v_n::text);

  SELECT count(*) INTO v_n FROM public.merchant_settlement_requests;
  r := r || public._qa_s5_ok('F1 no settlement request residue after QA rollback', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.merchant_payables WHERE source_module='qa_s7';
  r := r || public._qa_s5_ok('F2 no payable residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.mission_financial_holds WHERE source_module='qa_s7';
  r := r || public._qa_s5_ok('F3 no hold residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.wallet_transactions WHERE reference LIKE 'QA-S7-%';
  r := r || public._qa_s5_ok('F4 no wallet transaction residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.topup_requests WHERE reference LIKE 'QA-S7-%';
  r := r || public._qa_s5_ok('F5 no top-up residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.merchant_stores WHERE slug LIKE 'qa-s7-%';
  r := r || public._qa_s5_ok('F6 no merchant store residue', v_n = 0, v_n::text);
  r := r || public._qa_s5_ok('F7 master wallet still exactly -100435 with unchanged hold',
    EXISTS (SELECT 1 FROM public.wallets WHERE party_type='master' AND balance_gnf = -100435 AND held_gnf = 0));
  SELECT count(*) INTO v_n FROM public.feature_flags
   WHERE enabled AND key IN ('merchant_om_settlement_enabled','chop_pay_checkout_enabled',
                             'chop_pay_p2p_enabled','driver_cashout_enabled','envoyer_enabled');
  r := r || public._qa_s5_ok('F8 no finance rail activated by Slice 7', v_n = 0, v_n::text);
  r := r || public._qa_s5_ok('F9 om_topup_enabled remains ON (canonical)',
    EXISTS (SELECT 1 FROM public.feature_flags WHERE key='om_topup_enabled' AND enabled));

  SELECT count(*) FILTER (WHERE (x->>'ok')::boolean), count(*) INTO v_pass, v_total
    FROM jsonb_array_elements(r) x;
  RETURN jsonb_build_object('part',4,'total',v_total,'passed',v_pass,'failed',v_total-v_pass,
    'failures',(SELECT COALESCE(jsonb_agg(x),'[]'::jsonb) FROM jsonb_array_elements(r) x
                 WHERE NOT (x->>'ok')::boolean));
END $$;

TRUNCATE public._qa_s7_results;
INSERT INTO public._qa_s7_results(part, result)
VALUES (1, public._qa_s7_run1()), (2, public._qa_s7_run2()),
       (3, public._qa_s7_run3()), (4, public._qa_s7_run4());