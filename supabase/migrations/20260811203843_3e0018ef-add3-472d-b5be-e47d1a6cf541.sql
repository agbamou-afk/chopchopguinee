CREATE OR REPLACE FUNCTION public._qa_s13_run6()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_master0 bigint; v_master1 bigint; v_flags0 jsonb; v_flags1 jsonb;
  v_t0 timestamptz; v_sfx text;
  v_m1 uuid; v_m2 uuid; v_fa uuid; v_plain uuid; v_drv uuid;
  v_s1 uuid; v_s2 uuid; v_phone1 text := '+224620000601'; v_phone2 text := '+224620000602';
  v_err text; v_n bigint; v_b bigint; v_res jsonb; v_ov jsonb;
  v_req uuid; v_ord uuid; v_reqC uuid; v_ordC uuid;
  v_reqE uuid; v_ordE uuid; v_reqR uuid; v_ordR uuid;
  v_o public.payout_orders; v_e public.payout_provider_evidence;
  v_refB text; v_evid uuid;
  v_pay0 bigint; v_pay1 bigint; v_w0 bigint; v_w1 bigint;
  v_jid uuid; v_period text;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;

  BEGIN
    v_t0 := now() - interval '1 second';
    v_sfx := upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
    v_m1 := gen_random_uuid(); v_m2 := gen_random_uuid();
    v_fa := gen_random_uuid(); v_plain := gen_random_uuid(); v_drv := gen_random_uuid();
    PERFORM public._qa_s13_user(v_m1,'p6m1');
    PERFORM public._qa_s13_user(v_m2,'p6m2');
    PERFORM public._qa_s13_user(v_fa,'p6fa');
    PERFORM public._qa_s13_user(v_plain,'p6pl');
    PERFORM public._qa_s13_driver(v_drv,'p6dr', 500000);
    PERFORM public._qa_s13_admin(v_fa);
    INSERT INTO public.user_roles(user_id, role) VALUES (v_fa, 'god_admin') ON CONFLICT DO NOTHING;

    INSERT INTO public.merchant_stores (owner_user_id, slug, name, phone)
    VALUES (v_m1, 'qa-s13-p6-'||lower(v_sfx)||'-a', 'QA S13 P6 Store A', v_phone1)
    RETURNING id INTO v_s1;
    INSERT INTO public.merchant_stores (owner_user_id, slug, name, phone)
    VALUES (v_m2, 'qa-s13-p6-'||lower(v_sfx)||'-b', 'QA S13 P6 Store B', v_phone2)
    RETURNING id INTO v_s2;

    PERFORM public._qa_s13_wallet(v_m1,'merchant', 1000000, 0);
    PERFORM public._qa_s13_wallet(v_m2,'merchant', 200000, 0);
    PERFORM public._qa_s13_wallet(v_plain,'client', 200000, 0);

    INSERT INTO public.merchant_payables
      (payable_key, source_module, source_id, merchant_store_id, merchant_user_id,
       subtotal_gnf, amount_gnf, funded_gnf, state, funding_source)
    VALUES ('qa-s13-p6:'||v_sfx||':1','qa_s13', gen_random_uuid(), v_s1, v_m1,
            1000000, 1000000, 1000000, 'funded','platform');

    INSERT INTO public.provider_fee_schedules
      (provider, fee_bps, fee_fixed_gnf, passthrough_to_recipient, effective_from, note)
    VALUES ('orange_money', 0, 5000, true, v_t0, 'QA S13 P6 recipient-borne');

    ---------------------------------------------------------------- A. request / reservation
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_m1), true);
    v_ov := public.merchant_finance_overview(v_s1);
    r := r || public._qa_s13_ok('A0 fixture: one million GNF of funded merchant liability is eligible',
      (v_ov->>'eligible_settlement_gnf')::bigint = 1000000, v_ov->>'eligible_settlement_gnf');

    v_res := public.merchant_settlement_request_create(100000, 'qa-p6-key-a1-'||v_sfx, v_s1, 'A1');
    v_req := (v_res->>'request_id')::uuid; v_ord := (v_res->>'payout_order_id')::uuid;
    SELECT count(*) INTO v_n FROM public.payout_orders WHERE source_request_id = v_req;
    r := r || public._qa_s13_ok('A1 a funded settlement request creates exactly one payout reservation',
      v_req IS NOT NULL AND v_ord IS NOT NULL AND v_n = 1, v_n::text);
    SELECT * INTO v_o FROM public.payout_orders WHERE id = v_ord;
    r := r || public._qa_s13_ok('A1b the reservation freezes principal, fee and the exact expected transfer',
      v_o.requested_principal_gnf = 100000 AND v_o.provider_fee_gnf = 5000
      AND v_o.fee_borne_by = 'recipient' AND v_o.merchant_liability_debit_gnf = 100000
      AND v_o.expected_provider_transfer_gnf = 95000 AND v_o.reservation_gnf = 100000
      AND v_o.destination_msisdn = v_phone1 AND v_o.provider = 'orange_money',
      format('principal=%s fee=%s expected=%s borne=%s', v_o.requested_principal_gnf, v_o.provider_fee_gnf, v_o.expected_provider_transfer_gnf, v_o.fee_borne_by));

    BEGIN
      PERFORM public.merchant_settlement_request_create(99000000, 'qa-p6-key-a2-'||v_sfx, v_s1, 'A2');
      v_err := 'no_error';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT count(*) INTO v_n FROM public.merchant_settlement_requests WHERE merchant_store_id = v_s1;
    r := r || public._qa_s13_ok('A2 a settlement above eligible liability is refused before any mutation',
      v_err LIKE 'AMOUNT_EXCEEDS_ELIGIBLE%' AND v_n = 1, v_err);

    v_res := public.merchant_settlement_request_create(100000, 'qa-p6-key-a1-'||v_sfx, v_s1, 'A1 replay');
    SELECT count(*) INTO v_n FROM public.payout_orders WHERE merchant_store_id = v_s1;
    r := r || public._qa_s13_ok('A3 replaying the same request key returns the same request and reserves nothing extra',
      (v_res->>'request_id')::uuid = v_req AND (v_res->>'duplicate')::boolean AND v_n = 1, v_n::text);

    v_ov := public.merchant_finance_overview(v_s1);
    r := r || public._qa_s13_ok('A4 an open reservation reduces the eligible amount so requests cannot over-reserve',
      (v_ov->>'eligible_settlement_gnf')::bigint = 900000, v_ov->>'eligible_settlement_gnf');
    BEGIN
      PERFORM public.merchant_settlement_request_create(950000, 'qa-p6-key-a4-'||v_sfx, v_s1, 'A4');
      v_err := 'no_error';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT COALESCE(sum(reservation_gnf),0) INTO v_n FROM public.payout_orders WHERE merchant_store_id = v_s1;
    r := r || public._qa_s13_ok('A4b overlapping requests cannot over-reserve the same merchant liability',
      v_err LIKE 'AMOUNT_EXCEEDS_ELIGIBLE%' AND v_n = 100000, v_err);

    SELECT COALESCE(sum(amount_gnf - settled_gnf),0) INTO v_pay1 FROM public.merchant_payables WHERE merchant_store_id = v_s1;
    SELECT balance_gnf INTO v_w1 FROM public.wallets WHERE owner_user_id = v_m1 AND party_type='merchant';
    SELECT count(*) INTO v_n FROM public.ledger_journals WHERE source_module='payout_settlement' AND created_at >= v_t0;
    r := r || public._qa_s13_ok('A5 reserving money moves no payable, no wallet balance and posts no ledger entry',
      v_pay1 = 1000000 AND v_w1 = 1000000 AND v_n = 0,
      format('payable=%s wallet=%s journals=%s', v_pay1, v_w1, v_n));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_m2), true);
    BEGIN
      PERFORM public.merchant_settlement_request_create(50000, 'qa-p6-key-a6-'||v_sfx, v_s1, 'A6');
      v_err := 'no_error';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A6 a merchant cannot request a settlement for another merchant store',
      v_err = 'NOT_AUTHORIZED', v_err);

    ---------------------------------------------------------------- B. manual Orange Money finance operation
    v_refB := 'OM-P6-'||v_sfx||'-MAIN';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_fa), true);
    BEGIN
      PERFORM public.finance_confirm_manual_om_payout(v_ord, v_refB, true, NULL);
      v_err := 'no_error';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT count(*) INTO v_n FROM public.payout_provider_evidence WHERE payout_order_id = v_ord;
    r := r || public._qa_s13_ok('B1 with Stage 5 OFF the manual confirmation is refused and records no evidence',
      v_err = 'STAGE_DISABLED:merchant_om_settlement_enabled' AND v_n = 0, v_err);

    PERFORM public._qa_s13_flag('merchant_om_settlement_enabled', true);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_plain), true);
    BEGIN
      PERFORM public.finance_confirm_manual_om_payout(v_ord, v_refB, true, NULL);
      v_err := 'no_error';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B2 an ordinary signed-in user cannot confirm a manual payout',
      v_err = 'NOT_AUTHORIZED', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_m1), true);
    BEGIN
      PERFORM public.finance_confirm_manual_om_payout(v_ord, v_refB, true, NULL);
      v_err := 'no_error';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B2b a merchant cannot mark their own payout as paid',
      v_err = 'NOT_AUTHORIZED', v_err);

    PERFORM set_config('request.jwt.claims','',true);
    BEGIN
      PERFORM public.finance_confirm_manual_om_payout(v_ord, v_refB, true, NULL);
      v_err := 'no_error';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B3 an unauthenticated caller is not treated as privileged',
      v_err = 'NOT_AUTHENTICATED', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_fa), true);
    BEGIN
      PERFORM public.finance_confirm_manual_om_payout(v_ord, ' OM ', true, NULL);
      v_err := 'no_error';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT count(*) INTO v_n FROM public.payout_provider_evidence WHERE payout_order_id = v_ord;
    r := r || public._qa_s13_ok('B4 a blank or too short Orange Money reference is refused with zero movement',
      v_err = 'PROVIDER_REFERENCE_REQUIRED' AND v_n = 0, v_err);
    BEGIN
      PERFORM public.finance_confirm_manual_om_payout(v_ord, v_refB, false, NULL);
      v_err := 'no_error';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B4b confirmation without an explicit operator attestation is refused',
      v_err = 'ATTESTATION_REQUIRED', v_err);
    BEGIN
      PERFORM public.finance_confirm_manual_om_payout(v_ord, v_refB, true, now() + interval '3 days');
      v_err := 'no_error';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT count(*) INTO v_n FROM public.payout_provider_evidence WHERE payout_order_id = v_ord;
    r := r || public._qa_s13_ok('B4c an impossible future transfer timestamp is refused with zero movement',
      v_err = 'INVALID_TRANSFER_TIMESTAMP' AND v_n = 0, v_err);

    SELECT COALESCE(sum(amount_gnf - settled_gnf),0) INTO v_pay0 FROM public.merchant_payables WHERE merchant_store_id = v_s1;
    SELECT balance_gnf INTO v_w0 FROM public.wallets WHERE owner_user_id = v_m1 AND party_type='merchant';

    v_res := public.finance_confirm_manual_om_payout(v_ord, v_refB, true, NULL);
    r := r || public._qa_s13_ok('B5 the exact manual confirmation settles the payout through the canonical engine',
      v_res->>'status' = 'settled' AND (v_res->>'moved_gnf')::bigint = 100000, v_res::text);

    SELECT * INTO v_e FROM public.payout_provider_evidence WHERE payout_order_id = v_ord;
    r := r || public._qa_s13_ok('B6 the evidence facts are server-derived from the frozen order, not typed by the operator',
      v_e.amount_gnf = 95000 AND v_e.fee_gnf = 5000 AND v_e.recipient_msisdn = v_phone1
      AND v_e.provider = 'orange_money' AND v_e.environment = public._payout_env()
      AND v_e.provider_status = 'completed' AND v_e.reconciliation_state = 'reconciled',
      format('amount=%s fee=%s msisdn=%s', v_e.amount_gnf, v_e.fee_gnf, v_e.recipient_msisdn));
    r := r || public._qa_s13_ok('B6b the evidence is stored as operator-attested manual proof with a traceable actor',
      v_e.raw->>'source' = 'finance_manual_om'
      AND v_e.raw->>'evidence_kind' = 'manual_operator_attested'
      AND (v_e.raw->>'provider_verified')::boolean = false
      AND (v_e.raw->>'attested_by')::uuid = v_fa AND v_e.recorded_by = v_fa, v_e.raw::text);
    r := r || public._qa_s13_ok('B6c the recorded net amount is what the recipient receives, never the fee twice',
      v_e.net_gnf = v_e.amount_gnf AND v_e.net_gnf = 95000, v_e.net_gnf::text);

    SELECT COALESCE(sum(amount_gnf - settled_gnf),0) INTO v_pay1 FROM public.merchant_payables WHERE merchant_store_id = v_s1;
    SELECT balance_gnf INTO v_w1 FROM public.wallets WHERE owner_user_id = v_m1 AND party_type='merchant';
    r := r || public._qa_s13_ok('B7 the merchant payable decreases by exactly the settled principal, once',
      v_pay0 - v_pay1 = 100000, format('%s -> %s', v_pay0, v_pay1));
    r := r || public._qa_s13_ok('B7b the merchant wallet decreases by exactly the frozen liability debit, once',
      v_w0 - v_w1 = 100000, format('%s -> %s', v_w0, v_w1));
    SELECT COALESCE(sum(amount_gnf),0) INTO v_n FROM public.payout_settlement_allocations WHERE payout_order_id = v_ord;
    r := r || public._qa_s13_ok('B7c the settlement is allocated against real payables for the exact amount',
      v_n = 100000, v_n::text);

    SELECT id INTO v_jid FROM public.ledger_journals WHERE journal_key = 'payout-settle:'||v_ord::text;
    SELECT COALESCE(sum(amount_gnf),0) INTO v_n FROM public.ledger_postings WHERE journal_id = v_jid;
    r := r || public._qa_s13_ok('B8 the settlement journal balances to zero', v_jid IS NOT NULL AND v_n = 0, v_n::text);
    SELECT COALESCE(sum(amount_gnf),0) INTO v_n FROM public.ledger_postings
     WHERE journal_id = v_jid AND account_code = 'A_PROVIDER_CLEARING';
    r := r || public._qa_s13_ok('B8b the outbound transfer is booked against provider clearing',
      v_n = -100000, v_n::text);

    SELECT status INTO v_err FROM public.merchant_settlement_requests WHERE id = v_req;
    r := r || public._qa_s13_ok('B9 the settlement request becomes settled only after evidence reconciliation',
      v_err = 'settled', v_err);
    v_res := public.merchant_settlement_receipt(v_req);
    r := r || public._qa_s13_ok('B10 the receipt exists after settlement and states the manual operator evidence truthfully',
      (v_res->>'receipt_available')::boolean = true
      AND v_res->>'evidence_kind' = 'manual_operator_attested'
      AND (v_res->>'provider_verified')::boolean = false
      AND v_res->>'provider_reference' = v_refB
      AND (v_res->>'expected_provider_transfer_gnf')::bigint = 95000, v_res->>'evidence_kind');

    ---------------------------------------------------------------- C. mismatch / replay / uniqueness
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_m1), true);
    v_res := public.merchant_settlement_request_create(50000, 'qa-p6-key-c-'||v_sfx, v_s1, 'C');
    v_reqC := (v_res->>'request_id')::uuid; v_ordC := (v_res->>'payout_order_id')::uuid;
    SELECT * INTO v_o FROM public.payout_orders WHERE id = v_ordC;
    v_res := public.merchant_settlement_receipt(v_reqC);
    r := r || public._qa_s13_ok('C0 a reserved but unsettled request exposes no settlement receipt',
      (v_res->>'receipt_available')::boolean = false AND (v_res->>'settled')::boolean = false, v_res->>'kind');
    SELECT COALESCE(sum(amount_gnf - settled_gnf),0) INTO v_pay0 FROM public.merchant_payables WHERE merchant_store_id = v_s1;
    SELECT balance_gnf INTO v_w0 FROM public.wallets WHERE owner_user_id = v_m1 AND party_type='merchant';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_fa), true);

    v_res := public.payout_record_provider_evidence(v_ordC,'orange_money','OM-P6-'||v_sfx||'-C1',NULL,
      v_o.expected_provider_transfer_gnf,'completed', v_o.environment, now(), v_o.provider_fee_gnf, '{}'::jsonb);
    r := r || public._qa_s13_ok('C1 incomplete evidence is quarantined and moves zero',
      v_res->>'status' = 'evidence_incomplete' AND (v_res->>'moved_gnf')::bigint = 0, v_res::text);
    v_res := public.payout_record_provider_evidence(v_ordC,'orange_money','OM-P6-'||v_sfx||'-C2',v_o.destination_msisdn,
      v_o.expected_provider_transfer_gnf + 1,'completed', v_o.environment, now(), v_o.provider_fee_gnf, '{}'::jsonb);
    v_evid := (v_res->>'evidence_id')::uuid;
    r := r || public._qa_s13_ok('C2 a wrong transferred amount is a mismatch and moves zero',
      v_res->>'status' = 'mismatch' AND v_res->>'reason' = 'amount_mismatch' AND (v_res->>'moved_gnf')::bigint = 0, v_res::text);
    v_res := public.payout_record_provider_evidence(v_ordC,'orange_money','OM-P6-'||v_sfx||'-C3','+224620999999',
      v_o.expected_provider_transfer_gnf,'completed', v_o.environment, now(), v_o.provider_fee_gnf, '{}'::jsonb);
    r := r || public._qa_s13_ok('C3 a wrong recipient number is a mismatch and moves zero',
      v_res->>'reason' = 'recipient_mismatch' AND (v_res->>'moved_gnf')::bigint = 0, v_res::text);
    v_res := public.payout_record_provider_evidence(v_ordC,'orange_money','OM-P6-'||v_sfx||'-C4',v_o.destination_msisdn,
      v_o.expected_provider_transfer_gnf,'completed',
      CASE WHEN v_o.environment='sandbox' THEN 'production' ELSE 'sandbox' END, now(), v_o.provider_fee_gnf, '{}'::jsonb);
    r := r || public._qa_s13_ok('C4 evidence from the wrong environment is a mismatch and moves zero',
      v_res->>'reason' = 'environment_mismatch' AND (v_res->>'moved_gnf')::bigint = 0, v_res::text);
    v_res := public.payout_record_provider_evidence(v_ordC,'mtn_money','OM-P6-'||v_sfx||'-C5',v_o.destination_msisdn,
      v_o.expected_provider_transfer_gnf,'completed', v_o.environment, now(), v_o.provider_fee_gnf, '{}'::jsonb);
    r := r || public._qa_s13_ok('C5 evidence from the wrong provider is a mismatch and moves zero',
      v_res->>'reason' = 'provider_mismatch' AND (v_res->>'moved_gnf')::bigint = 0, v_res::text);
    v_res := public.payout_record_provider_evidence(v_ordC,'orange_money','OM-P6-'||v_sfx||'-C6',v_o.destination_msisdn,
      v_o.expected_provider_transfer_gnf,'failed', v_o.environment, now(), v_o.provider_fee_gnf, '{}'::jsonb);
    r := r || public._qa_s13_ok('C6 an unsuccessful provider status never settles',
      v_res->>'reason' = 'provider_status_not_successful' AND (v_res->>'moved_gnf')::bigint = 0, v_res::text);

    SELECT COALESCE(sum(amount_gnf - settled_gnf),0) INTO v_pay1 FROM public.merchant_payables WHERE merchant_store_id = v_s1;
    SELECT balance_gnf INTO v_w1 FROM public.wallets WHERE owner_user_id = v_m1 AND party_type='merchant';
    r := r || public._qa_s13_ok('C6b none of the rejected evidence attempts moved any money',
      v_pay1 = v_pay0 AND v_w1 = v_w0, format('payable=%s wallet=%s', v_pay1, v_w1));

    BEGIN
      PERFORM public.payout_record_provider_evidence(v_ordC,'orange_money', v_refB, v_o.destination_msisdn,
        v_o.expected_provider_transfer_gnf,'completed', v_o.environment, now(), v_o.provider_fee_gnf, '{}'::jsonb);
      v_err := 'no_error';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('C7 a provider reference already used by another payout is globally denied',
      v_err = 'PROVIDER_REFERENCE_ALREADY_CONSUMED', v_err);

    v_res := public.finance_confirm_manual_om_payout(v_ord, v_refB, true, NULL);
    SELECT COALESCE(sum(amount_gnf - settled_gnf),0) INTO v_pay1 FROM public.merchant_payables WHERE merchant_store_id = v_s1;
    SELECT balance_gnf INTO v_w1 FROM public.wallets WHERE owner_user_id = v_m1 AND party_type='merchant';
    r := r || public._qa_s13_ok('C8 replaying the same manual confirmation is idempotent and moves zero extra',
      (v_res->>'moved_gnf')::bigint = 0 AND v_res->>'status' = 'already_settled'
      AND v_pay1 = v_pay0 AND v_w1 = v_w0, v_res::text);
    SELECT count(*) INTO v_n FROM public.payout_provider_evidence WHERE payout_order_id = v_ord;
    r := r || public._qa_s13_ok('C8b the replay creates no second evidence record', v_n = 1, v_n::text);

    BEGIN
      PERFORM public._payout_settle_internal(v_ordC, v_evid, v_fa);
      v_err := 'no_error';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT COALESCE(sum(amount_gnf - settled_gnf),0) INTO v_pay1 FROM public.merchant_payables WHERE merchant_store_id = v_s1;
    r := r || public._qa_s13_ok('C9 the debit primitive itself refuses bad evidence before touching any money',
      v_err LIKE 'EVIDENCE_VALIDATION_FAILED%' AND v_pay1 = v_pay0, v_err);

    ---------------------------------------------------------------- D. rejection / release / scheduler
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_m1), true);
    v_res := public.merchant_settlement_request_create(50000, 'qa-p6-key-d-'||v_sfx, v_s1, 'D');
    v_reqR := (v_res->>'request_id')::uuid; v_ordR := (v_res->>'payout_order_id')::uuid;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_fa), true);
    SELECT COALESCE(sum(amount_gnf - settled_gnf),0) INTO v_pay0 FROM public.merchant_payables WHERE merchant_store_id = v_s1;
    v_res := public.payout_reject_release(v_ordR, 'QA rejection for Part 6');
    SELECT reservation_gnf, status INTO v_b, v_err FROM public.payout_orders WHERE id = v_ordR;
    SELECT COALESCE(sum(amount_gnf - settled_gnf),0) INTO v_pay1 FROM public.merchant_payables WHERE merchant_store_id = v_s1;
    r := r || public._qa_s13_ok('D1 a finance rejection releases the reservation and leaves the payable untouched',
      (v_res->>'released_gnf')::bigint = 50000 AND v_b = 0 AND v_err = 'rejected' AND v_pay1 = v_pay0,
      format('released=%s payable=%s', v_res->>'released_gnf', v_pay1));
    v_res := public.payout_reject_release(v_ordR, 'QA rejection repeated');
    SELECT COALESCE(sum(amount_gnf - settled_gnf),0) INTO v_pay1 FROM public.merchant_payables WHERE merchant_store_id = v_s1;
    r := r || public._qa_s13_ok('D2 repeating the rejection releases nothing extra',
      (v_res->>'released_gnf')::bigint = 0 AND (v_res->>'duplicate')::boolean AND v_pay1 = v_pay0, v_res::text);

    INSERT INTO public.merchant_settlement_policies
      (configured, min_settlement_gnf, max_settlement_gnf, cadence, fee_passthrough, effective_from, note)
    VALUES (true, 10000, 300000, 'daily', false, v_t0, 'QA S13 P6 platform-borne daily');

    SELECT COALESCE(sum(amount_gnf - settled_gnf),0) INTO v_pay0 FROM public.merchant_payables WHERE merchant_store_id = v_s1;
    v_res := public.merchant_settlement_schedule_generate(now());
    v_period := v_res->>'period_key';
    SELECT count(*) INTO v_n FROM public.merchant_settlement_schedule_runs
     WHERE merchant_store_id = v_s1 AND period_key = v_period;
    r := r || public._qa_s13_ok('D3 the configured scheduler queues exactly one settlement for the period',
      v_res->>'status' = 'ok' AND v_n = 1, v_res::text);
    v_res := public.merchant_settlement_schedule_generate(now());
    SELECT count(*) INTO v_n FROM public.merchant_settlement_schedule_runs
     WHERE merchant_store_id = v_s1 AND period_key = v_period;
    r := r || public._qa_s13_ok('D4 running the scheduler again for the same period queues nothing',
      (v_res->>'created')::int = 0 AND v_n = 1, v_res::text);
    v_res := public.merchant_settlement_schedule_generate(now() + interval '1 day');
    SELECT count(*) INTO v_n FROM public.merchant_settlement_schedule_runs WHERE merchant_store_id = v_s1;
    r := r || public._qa_s13_ok('D5 the next eligible period queues a new settlement', v_n = 2, v_n::text);
    SELECT COALESCE(sum(amount_gnf - settled_gnf),0) INTO v_pay1 FROM public.merchant_payables WHERE merchant_store_id = v_s1;
    r := r || public._qa_s13_ok('D6 scheduling alone never debits a payable', v_pay1 = v_pay0,
      format('%s -> %s', v_pay0, v_pay1));

    ---------------------------------------------------------------- E. fees
    SELECT * INTO v_o FROM public.payout_orders WHERE id = v_ord;
    r := r || public._qa_s13_ok('E1 recipient-borne fee: 100000 principal, 5000 fee, 95000 transferred, 100000 debited',
      v_o.requested_principal_gnf = 100000 AND v_o.provider_fee_gnf = 5000
      AND v_o.fee_borne_by = 'recipient' AND v_o.expected_provider_transfer_gnf = 95000
      AND v_o.merchant_liability_debit_gnf = 100000 AND v_o.settled_gnf = 100000, NULL);
    SELECT COALESCE(sum(amount_gnf),0) INTO v_n FROM public.ledger_postings
     WHERE journal_id = (SELECT id FROM public.ledger_journals WHERE journal_key='payout-settle:'||v_ord::text)
       AND account_code = 'E_PROVIDER_FEE';
    r := r || public._qa_s13_ok('E1b a recipient-borne fee creates no platform fee expense', v_n = 0, v_n::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_m1), true);
    v_res := public.merchant_settlement_request_create(100000, 'qa-p6-key-e2-'||v_sfx, v_s1, 'E2');
    v_reqE := (v_res->>'request_id')::uuid; v_ordE := (v_res->>'payout_order_id')::uuid;
    SELECT * INTO v_o FROM public.payout_orders WHERE id = v_ordE;
    r := r || public._qa_s13_ok('E2 platform-borne fee: 100000 principal, 5000 fee, 100000 transferred, 100000 debited',
      v_o.fee_borne_by = 'platform' AND v_o.provider_fee_gnf = 5000
      AND v_o.expected_provider_transfer_gnf = 100000 AND v_o.merchant_liability_debit_gnf = 100000,
      format('borne=%s fee=%s expected=%s', v_o.fee_borne_by, v_o.provider_fee_gnf, v_o.expected_provider_transfer_gnf));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_fa), true);
    SELECT COALESCE(sum(amount_gnf - settled_gnf),0) INTO v_pay0 FROM public.merchant_payables WHERE merchant_store_id = v_s1;
    SELECT balance_gnf INTO v_w0 FROM public.wallets WHERE owner_user_id = v_m1 AND party_type='merchant';
    v_res := public.finance_confirm_manual_om_payout(v_ordE, 'OM-P6-'||v_sfx||'-E2', true, NULL);
    SELECT * INTO v_e FROM public.payout_provider_evidence WHERE payout_order_id = v_ordE;
    r := r || public._qa_s13_ok('E3 the manual wrapper derives the correct expected transfer in the platform-borne branch',
      v_res->>'status' = 'settled' AND v_e.amount_gnf = 100000 AND v_e.net_gnf = 100000 AND v_e.fee_gnf = 5000,
      format('amount=%s net=%s', v_e.amount_gnf, v_e.net_gnf));
    SELECT id INTO v_jid FROM public.ledger_journals WHERE journal_key='payout-settle:'||v_ordE::text;
    SELECT COALESCE(sum(amount_gnf),0) INTO v_n FROM public.ledger_postings WHERE journal_id = v_jid;
    SELECT COALESCE(sum(amount_gnf),0) INTO v_b FROM public.ledger_postings
     WHERE journal_id = v_jid AND account_code='E_PROVIDER_FEE';
    r := r || public._qa_s13_ok('E4 the platform-borne journal balances and books the 5000 provider fee exactly once',
      v_n = 0 AND v_b = 5000, format('sum=%s fee=%s', v_n, v_b));
    SELECT COALESCE(sum(amount_gnf - settled_gnf),0) INTO v_pay1 FROM public.merchant_payables WHERE merchant_store_id = v_s1;
    SELECT balance_gnf INTO v_w1 FROM public.wallets WHERE owner_user_id = v_m1 AND party_type='merchant';
    r := r || public._qa_s13_ok('E5 the platform-borne settlement debits payable and wallet by exactly the principal',
      v_pay0 - v_pay1 = 100000 AND v_w0 - v_w1 = 100000, format('payable %s->%s wallet %s->%s', v_pay0, v_pay1, v_w0, v_w1));

    ---------------------------------------------------------------- F. stage 6 / stage 7 isolation
    r := r || public._qa_s13_ok('F1 enabling Stage 5 for this test did not enable Stage 6 or Stage 7',
      public._finance_flag('merchant_om_settlement_enabled')
      AND NOT public._finance_flag('driver_cashout_enabled')
      AND NOT public._finance_flag('chop_pay_p2p_enabled'), NULL);
    SELECT balance_gnf INTO v_w0 FROM public.wallets WHERE owner_user_id = v_drv AND party_type='driver';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    BEGIN
      PERFORM public.driver_payout_request_create(50000, '+224620000700', 'qa-p6-driver-'||v_sfx);
      v_err := 'no_error';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('F2 driver payout requests stay blocked by the Stage 6 gate',
      v_err = 'STAGE_DISABLED:driver_cashout_enabled', v_err);
    PERFORM set_config('request.jwt.claims','',true);
    BEGIN
      PERFORM public.driver_payout_hold_place(gen_random_uuid(), v_drv, 10000);
      v_err := 'no_error';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('F3 the legacy driver payout hold path stays hard-blocked',
      v_err LIKE 'STAGE_DISABLED:driver_cashout_enabled%', v_err);
    BEGIN
      PERFORM public.driver_cashout_mark_paid(gen_random_uuid(), 'OM-QA-REF-1', 'qa');
      v_err := 'no_error';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('F4 the legacy driver cashout payment path stays hard-blocked',
      v_err LIKE 'STAGE_DISABLED%', v_err);
    SELECT balance_gnf INTO v_w1 FROM public.wallets WHERE owner_user_id = v_drv AND party_type='driver';
    r := r || public._qa_s13_ok('F5 no driver money moved while Stage 6 is off', v_w1 = v_w0, format('%s -> %s', v_w0, v_w1));
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_plain), true);
    BEGIN
      PERFORM public.wallet_p2p_transfer(v_m1, 5000, 'qa', 'qa-p6-p2p-'||v_sfx);
      v_err := 'no_error';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('F6 peer-to-peer transfers stay blocked by the Stage 7 gate',
      v_err = 'STAGE_DISABLED:chop_pay_p2p_enabled', v_err);
    SELECT count(*) INTO v_n FROM public.feature_flags
     WHERE key IN ('chop_pay_enabled','chop_pay_checkout_enabled','chop_pay_ecosystem_spend_enabled') AND enabled;
    r := r || public._qa_s13_ok('F7 no umbrella Chop Pay flag is opened by the Stage 5 test enablement', v_n = 0, v_n::text);

    ---------------------------------------------------------------- G. security matrix
    PERFORM set_config('request.jwt.claims','',true);
    SELECT count(*) INTO v_n FROM pg_proc p WHERE p.pronamespace='public'::regnamespace
      AND p.proname IN ('finance_confirm_manual_om_payout','payout_record_provider_evidence',
                        'payout_reconcile_evidence','payout_reject_release','finance_payout_queue',
                        'merchant_settlement_request_create','merchant_settlement_schedule_generate',
                        'merchant_settlement_receipt','driver_payout_request_create')
      AND has_function_privilege('anon', p.oid, 'EXECUTE');
    r := r || public._qa_s13_ok('G1 anonymous callers cannot execute any payout or settlement function', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM pg_proc p WHERE p.pronamespace='public'::regnamespace
      AND p.proname IN ('_payout_settle_internal','_payout_order_create_internal',
                        '_merchant_settlement_request_queue_internal','_finance_evidence_claim')
      AND (has_function_privilege('anon', p.oid,'EXECUTE') OR has_function_privilege('authenticated', p.oid,'EXECUTE'));
    r := r || public._qa_s13_ok('G2 the internal settlement primitives stay service-role only', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM pg_proc p WHERE p.pronamespace='public'::regnamespace
      AND p.proname = 'finance_confirm_manual_om_payout'
      AND has_function_privilege('authenticated', p.oid,'EXECUTE');
    r := r || public._qa_s13_ok('G3 the manual confirmation is reachable by signed-in staff only, gated in the body', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM pg_proc p WHERE p.pronamespace='public'::regnamespace
      AND p.proname IN ('finance_confirm_manual_om_payout','payout_record_provider_evidence',
                        'payout_reconcile_evidence','_payout_settle_internal','_payout_evidence_mismatch_reason',
                        'payout_reject_release','merchant_settlement_receipt','finance_payout_queue')
      AND (p.proconfig IS NULL OR NOT EXISTS (
        SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%'));
    r := r || public._qa_s13_ok('G4 every payout function pins a fixed search path', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM (
      SELECT 1 WHERE has_table_privilege('authenticated','public.payout_orders','INSERT')
        OR has_table_privilege('authenticated','public.payout_orders','UPDATE')
        OR has_table_privilege('authenticated','public.payout_provider_evidence','INSERT')
        OR has_table_privilege('authenticated','public.payout_provider_evidence','UPDATE')
        OR has_table_privilege('authenticated','public.payout_settlement_allocations','INSERT')
        OR has_table_privilege('authenticated','public.merchant_payables','UPDATE')) z;
    r := r || public._qa_s13_ok('G5 participants cannot write payout orders, evidence, allocations or payables directly', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM pg_proc p WHERE p.pronamespace='public'::regnamespace
      AND p.proname = 'finance_confirm_manual_om_payout'
      AND p.prosrc LIKE '%NOT_AUTHENTICATED%' AND p.prosrc LIKE '%is_god_admin%';
    r := r || public._qa_s13_ok('G6 the manual confirmation has no null-caller privilege shortcut', v_n = 1, v_n::text);

    ---------------------------------------------------------------- H. accounting truth inside the fixture
    SELECT count(*) INTO v_n FROM (
      SELECT j.id FROM public.ledger_journals j
       JOIN public.ledger_postings p ON p.journal_id = j.id
       GROUP BY j.id HAVING sum(p.amount_gnf) <> 0) z;
    r := r || public._qa_s13_ok('H1 no imbalanced journal exists anywhere inside the fixture', v_n = 0, v_n::text);
    SELECT COALESCE(sum(amount_gnf),0) INTO v_n FROM public.ledger_postings;
    r := r || public._qa_s13_ok('H2 the global ledger posting sum is still zero inside the fixture', v_n = 0, v_n::text);
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s13_ok('H3 merchant settlements never touch the master wallet', v_b = v_master0, v_b::text);
    SELECT count(*) INTO v_n FROM public.payout_orders WHERE status='settled' AND merchant_store_id = v_s1;
    r := r || public._qa_s13_ok('H4 exactly two payouts settled in this run, each exactly once', v_n = 2, v_n::text);

    RAISE EXCEPTION 'QA_S13_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_S13_ROLLBACK' THEN
      r := r || public._qa_s13_ok('HARNESS_PART6_UNEXPECTED_ABORT', false, SQLERRM);
    END IF;
  END;

  PERFORM set_config('request.jwt.claims','',true);
  SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;
  r := r || public._qa_s13_ok('Z6.1 the master wallet is exactly back to its live balance after rollback',
    v_master1 = v_master0 AND v_master1 = -100435, v_master1::text);
  SELECT held_gnf INTO v_n FROM public.wallets WHERE party_type='master';
  r := r || public._qa_s13_ok('Z6.2 the master wallet holds nothing after rollback', v_n = 0, v_n::text);
  SELECT COALESCE(sum(amount_gnf),0) INTO v_n FROM public.ledger_postings;
  r := r || public._qa_s13_ok('Z6.3 the global ledger posting sum is zero after rollback', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM (
    SELECT j.id FROM public.ledger_journals j
     JOIN public.ledger_postings p ON p.journal_id = j.id
     GROUP BY j.id HAVING sum(p.amount_gnf) <> 0) z;
  r := r || public._qa_s13_ok('Z6.4 no imbalanced journal survives the rollback', v_n = 0, v_n::text);
  r := r || public._qa_s13_ok('Z6.5 live feature flags are byte-identical after the fixture', v_flags1 = v_flags0, NULL);
  r := r || public._qa_s13_ok('Z6.6 Stage 5, Stage 6 and Stage 7 are OFF in production after the run',
    NOT public._finance_flag('merchant_om_settlement_enabled')
    AND NOT public._finance_flag('driver_cashout_enabled')
    AND NOT public._finance_flag('chop_pay_p2p_enabled'), NULL);
  r := r || public._qa_s13_ok('Z6.7 the Orange Money top-up rail is still ON',
    public._finance_flag('om_topup_enabled'), NULL);
  SELECT count(*) INTO v_n FROM public.payout_orders;
  r := r || public._qa_s13_ok('Z6.8 no payout order survives the rollback', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.payout_provider_evidence;
  r := r || public._qa_s13_ok('Z6.9 no payout evidence survives the rollback', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.payout_settlement_allocations;
  r := r || public._qa_s13_ok('Z6.10 no settlement allocation survives the rollback', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.merchant_settlement_requests;
  r := r || public._qa_s13_ok('Z6.11 no settlement request survives the rollback', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.merchant_settlement_schedule_runs;
  r := r || public._qa_s13_ok('Z6.12 no scheduler run survives the rollback', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM auth.users WHERE email LIKE 'qa-s13-p6%@qa.invalid';
  r := r || public._qa_s13_ok('Z6.13 no QA user survives the rollback', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.merchant_stores WHERE slug LIKE 'qa-s13-p6-%';
  r := r || public._qa_s13_ok('Z6.14 no QA merchant store survives the rollback', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.merchant_payables WHERE source_module = 'qa_s13';
  r := r || public._qa_s13_ok('Z6.15 no QA merchant payable survives the rollback', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.provider_fee_schedules WHERE note LIKE 'QA S13 P6%';
  r := r || public._qa_s13_ok('Z6.16 no QA provider fee schedule survives the rollback', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.merchant_settlement_policies WHERE note LIKE 'QA S13 P6%';
  r := r || public._qa_s13_ok('Z6.17 no QA settlement policy survives the rollback', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM pg_proc p
   WHERE p.pronamespace='public'::regnamespace AND p.proname LIKE '\_qa\_s13%'
     AND (has_function_privilege('anon', p.oid,'EXECUTE') OR has_function_privilege('authenticated', p.oid,'EXECUTE'));
  r := r || public._qa_s13_ok('Z6.18 no QA harness function is executable by anon or authenticated', v_n = 0, v_n::text);

  RETURN public._qa_s13_summary(6, r);
END $function$;

REVOKE ALL ON FUNCTION public._qa_s13_run6() FROM PUBLIC, anon, authenticated;

SELECT public._qa_s13_run6();