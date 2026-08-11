CREATE OR REPLACE FUNCTION public._qa_s11_run()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_owner uuid := gen_random_uuid();
  v_owner2 uuid := gen_random_uuid();
  v_owner3 uuid := gen_random_uuid();
  v_admin uuid := gen_random_uuid();
  v_store uuid; v_store2 uuid; v_store3 uuid;
  v_pay uuid; v_pay2 uuid; v_pay3 uuid;
  v_req jsonb; v_req2 jsonb; v_o uuid; v_o2 uuid; v_o3 uuid; v_o4 uuid; v_ev uuid;
  v_ord public.payout_orders;
  v_ov jsonb; v_res jsonb; v_bal bigint; v_settled bigint; v_status text;
  v_sum bigint; v_master bigint; v_n int; v_cnt int; v_cnt2 int;
  v_ref text := 'QA-S11-' || substr(gen_random_uuid()::text,1,8);
  v_refr text := 'QA-S11R-' || substr(gen_random_uuid()::text,1,8);
  v_refp text := 'QA-S11P-' || substr(gen_random_uuid()::text,1,8);
  v_journal bigint; v_pass int; v_total int; v_sched1 jsonb; v_sched2 jsonb; v_sched3 jsonb;
  v_allon boolean; vf1 uuid; vf2 uuid; vp1 uuid; v_fee bigint;
BEGIN
  BEGIN
    v_store := public._qa_s11_fixture_store(v_owner);
    INSERT INTO public.wallets (owner_user_id, party_type, balance_gnf, held_gnf)
    VALUES (v_owner, 'merchant', 500000, 0);
    INSERT INTO public.merchant_payables
      (payable_key, source_module, source_id, merchant_store_id, merchant_user_id,
       subtotal_gnf, amount_gnf, funded_gnf, state, funding_source)
    VALUES ('qa-s11-' || v_store::text, 'qa_s11', gen_random_uuid(), v_store, v_owner,
            500000, 500000, 500000, 'funded', 'customer_choppay')
    RETURNING id INTO v_pay;
    INSERT INTO public.admin_users (user_id, admin_role, status)
    VALUES (v_admin, 'finance_admin', 'active');

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_owner), true);
    v_req := public.merchant_settlement_request_create(300000, 'qa-s11-idem-0001', v_store, 'QA');
    v_o := (v_req->>'payout_order_id')::uuid;

    SELECT settled_gnf INTO v_settled FROM public.merchant_payables WHERE id = v_pay;
    SELECT balance_gnf INTO v_bal FROM public.wallets WHERE owner_user_id = v_owner AND party_type='merchant';
    r := r || jsonb_build_object('name','A1 reservation moves no money',
      'ok', (v_settled = 0 AND v_bal = 500000),
      'detail', format('payable_settled=%s wallet=%s', v_settled, v_bal));

    v_ov := public.merchant_finance_overview(v_store);
    r := r || jsonb_build_object('name','A2 reservation reduces eligibility',
      'ok', (v_ov->>'eligible_settlement_gnf')::bigint = 200000
            AND (v_ov->>'reserved_for_settlement_gnf')::bigint = 300000,
      'detail', v_ov::text);

    BEGIN
      PERFORM public.merchant_settlement_request_create(300000, 'qa-s11-idem-0002', v_store, 'QA over');
      r := r || jsonb_build_object('name','A3 over-reservation blocked','ok',false,'detail','no error');
    EXCEPTION WHEN OTHERS THEN
      r := r || jsonb_build_object('name','A3 over-reservation blocked',
        'ok', SQLERRM LIKE 'AMOUNT_EXCEEDS_ELIGIBLE%','detail',SQLERRM);
    END;

    v_req2 := public.merchant_settlement_request_create(300000, 'qa-s11-idem-0001', v_store, 'QA');
    r := r || jsonb_build_object('name','A4 request idempotent',
      'ok', (v_req2->>'duplicate')::boolean AND (v_req2->>'request_id') = (v_req->>'request_id'),
      'detail', v_req2::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_admin), true);
    UPDATE public.feature_flags SET enabled = false WHERE key = 'merchant_om_settlement_enabled';
    BEGIN
      PERFORM public.payout_record_provider_evidence(
        v_o,'orange_money','QA-GATE-'||substr(gen_random_uuid()::text,1,8),
        '+224620000111',300000,'success','sandbox', now(), 0, '{}'::jsonb);
      r := r || jsonb_build_object('name','A5 Stage 5 gate blocks settlement','ok',false,'detail','settled while OFF');
    EXCEPTION WHEN OTHERS THEN
      r := r || jsonb_build_object('name','A5 Stage 5 gate blocks settlement',
        'ok', SQLERRM LIKE 'STAGE_DISABLED:merchant_om_settlement_enabled%','detail',SQLERRM);
    END;
    SELECT settled_gnf INTO v_settled FROM public.merchant_payables WHERE id = v_pay;
    r := r || jsonb_build_object('name','A6 gated attempt moved no money','ok', v_settled = 0,
      'detail', format('payable_settled=%s', v_settled));

    UPDATE public.feature_flags SET enabled = true WHERE key = 'merchant_om_settlement_enabled';

    v_res := public.payout_record_provider_evidence(
      v_o,'orange_money','QA-INC-'||substr(gen_random_uuid()::text,1,8),
      NULL, 300000,'success','sandbox', now(), 0, '{}'::jsonb);
    SELECT settled_gnf INTO v_settled FROM public.merchant_payables WHERE id = v_pay;
    SELECT status INTO v_status FROM public.payout_orders WHERE id = v_o;
    r := r || jsonb_build_object('name','A7 incomplete evidence parks for review',
      'ok', v_res->>'status' = 'evidence_incomplete' AND (v_res->>'moved_gnf')::bigint = 0
            AND v_settled = 0 AND v_status = 'needs_review',
      'detail', v_res::text || ' order=' || v_status);

    v_res := public.payout_record_provider_evidence(
      v_o,'orange_money','QA-MIS-'||substr(gen_random_uuid()::text,1,8),
      '+224620000111', 250000,'success','sandbox', now(), 0, '{}'::jsonb);
    SELECT settled_gnf INTO v_settled FROM public.merchant_payables WHERE id = v_pay;
    r := r || jsonb_build_object('name','A8 amount mismatch parks, moves nothing',
      'ok', v_res->>'status' = 'mismatch' AND v_res->>'reason' = 'amount_mismatch'
            AND (v_res->>'moved_gnf')::bigint = 0 AND v_settled = 0,
      'detail', v_res::text);

    v_res := public.payout_record_provider_evidence(
      v_o,'orange_money','QA-REC-'||substr(gen_random_uuid()::text,1,8),
      '+224610009999', 300000,'success','sandbox', now(), 0, '{}'::jsonb);
    r := r || jsonb_build_object('name','A9 recipient mismatch parks',
      'ok', v_res->>'reason' = 'recipient_mismatch' AND (v_res->>'moved_gnf')::bigint = 0,
      'detail', v_res::text);

    v_res := public.payout_record_provider_evidence(
      v_o,'orange_money','QA-ENV-'||substr(gen_random_uuid()::text,1,8),
      '+224620000111', 300000,'success','production', now(), 0, '{}'::jsonb);
    r := r || jsonb_build_object('name','A10 environment mismatch parks',
      'ok', v_res->>'reason' = 'environment_mismatch' AND (v_res->>'moved_gnf')::bigint = 0,
      'detail', v_res::text);

    v_res := public.payout_record_provider_evidence(
      v_o,'orange_money','QA-STA-'||substr(gen_random_uuid()::text,1,8),
      '+224620000111', 300000,'pending','sandbox', now(), 0, '{}'::jsonb);
    r := r || jsonb_build_object('name','A11 non-success provider status parks',
      'ok', v_res->>'reason' = 'provider_status_not_successful' AND (v_res->>'moved_gnf')::bigint = 0,
      'detail', v_res::text);

    v_res := public.payout_record_provider_evidence(
      v_o,'orange_money', v_ref, '+224620000111', 300000,'success','sandbox', now(), 0, '{}'::jsonb);
    SELECT settled_gnf INTO v_settled FROM public.merchant_payables WHERE id = v_pay;
    SELECT balance_gnf INTO v_bal FROM public.wallets WHERE owner_user_id = v_owner AND party_type='merchant';
    SELECT status INTO v_status FROM public.payout_orders WHERE id = v_o;
    r := r || jsonb_build_object('name','A12 exact evidence settles exactly',
      'ok', v_res->>'status' = 'settled' AND (v_res->>'moved_gnf')::bigint = 300000
            AND v_settled = 300000 AND v_bal = 200000 AND v_status = 'settled',
      'detail', format('moved=%s payable_settled=%s wallet=%s order=%s',
                       v_res->>'moved_gnf', v_settled, v_bal, v_status));

    SELECT status INTO v_status FROM public.merchant_settlement_requests WHERE id = (v_req->>'request_id')::uuid;
    r := r || jsonb_build_object('name','A13 request marked settled','ok', v_status = 'settled','detail',v_status);

    SELECT COALESCE(SUM(p.amount_gnf),0), count(*) INTO v_journal, v_n
      FROM public.ledger_postings p JOIN public.ledger_journals j ON j.id = p.journal_id
     WHERE j.journal_key = 'payout-settle:' || v_o::text;
    r := r || jsonb_build_object('name','A14 settlement journal balanced',
      'ok', v_n >= 2 AND v_journal = 0, 'detail', format('lines=%s sum=%s', v_n, v_journal));

    SELECT COALESCE(SUM(amount_gnf),0) INTO v_sum FROM public.payout_settlement_allocations
     WHERE payout_order_id = v_o;
    r := r || jsonb_build_object('name','A15 payable allocation is exact','ok', v_sum = 300000,
      'detail', format('allocated=%s', v_sum));

    v_res := public.payout_record_provider_evidence(
      v_o,'orange_money', v_ref, '+224620000111', 300000,'success','sandbox', now(), 0, '{}'::jsonb);
    SELECT settled_gnf INTO v_settled FROM public.merchant_payables WHERE id = v_pay;
    r := r || jsonb_build_object('name','A16 replay is idempotent',
      'ok', (v_res->>'moved_gnf')::bigint = 0 AND v_settled = 300000, 'detail', v_res::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_owner), true);
    v_req2 := public.merchant_settlement_request_create(200000, 'qa-s11-idem-0003', v_store, 'QA2');
    v_o2 := (v_req2->>'payout_order_id')::uuid;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_admin), true);
    BEGIN
      PERFORM public.payout_record_provider_evidence(
        v_o2,'orange_money', v_ref, '+224620000111', 200000,'success','sandbox', now(), 0, '{}'::jsonb);
      r := r || jsonb_build_object('name','A17 reference reuse blocked','ok',false,'detail','reused');
    EXCEPTION WHEN OTHERS THEN
      r := r || jsonb_build_object('name','A17 reference reuse blocked',
        'ok', SQLERRM LIKE 'PROVIDER_REFERENCE_ALREADY_CONSUMED%','detail',SQLERRM);
    END;

    v_res := public.payout_reject_release(v_o2, 'QA rejection: no provider transfer');
    v_ov := public.merchant_finance_overview(v_store);
    SELECT settled_gnf INTO v_settled FROM public.merchant_payables WHERE id = v_pay;
    r := r || jsonb_build_object('name','A18 reject releases reservation once, no money moves',
      'ok', v_res->>'status' = 'rejected' AND (v_res->>'released_gnf')::bigint = 200000
            AND v_settled = 300000
            AND (v_ov->>'reserved_for_settlement_gnf')::bigint = 0,
      'detail', v_res::text || ' ' || v_ov::text);
    v_res := public.payout_reject_release(v_o2, 'QA rejection repeat');
    r := r || jsonb_build_object('name','A19 reject is idempotent',
      'ok', (v_res->>'released_gnf')::bigint = 0 AND (v_res->>'duplicate')::boolean,
      'detail', v_res::text);

    v_res := public.merchant_settlement_receipt((v_req->>'request_id')::uuid);
    r := r || jsonb_build_object('name','A20 receipt only from reconciled evidence',
      'ok', (v_res->>'receipt_available')::boolean AND v_res->>'provider_reference' = v_ref
            AND (v_res->'ledger'->>'journal_key') = 'payout-settle:' || v_o::text,
      'detail', v_res::text);
    v_res := public.merchant_settlement_receipt((v_req2->>'request_id')::uuid);
    r := r || jsonb_build_object('name','A21 unsettled request has no receipt',
      'ok', NOT (v_res->>'receipt_available')::boolean AND v_res->>'kind' = 'request_confirmation',
      'detail', v_res::text);

    v_sched1 := public.merchant_settlement_schedule_generate(now());
    v_sched2 := public.merchant_settlement_schedule_generate(now());
    r := r || jsonb_build_object('name','A22 scheduler never double-queues a period',
      'ok', COALESCE((v_sched2->>'created')::int, 0) = 0,
      'detail', v_sched1::text || ' / ' || v_sched2::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_owner), true);
    BEGIN
      PERFORM public.finance_payout_queue('requested', 10);
      r := r || jsonb_build_object('name','A23 merchant cannot read payout queue','ok',false,'detail','allowed');
    EXCEPTION WHEN OTHERS THEN
      r := r || jsonb_build_object('name','A23 merchant cannot read payout queue',
        'ok', SQLERRM LIKE 'NOT_AUTHORIZED%','detail',SQLERRM);
    END;
    BEGIN
      PERFORM public.payout_record_provider_evidence(
        v_o2,'orange_money','QA-SELF-'||substr(gen_random_uuid()::text,1,8),
        '+224620000111',200000,'success','sandbox', now(), 0, '{}'::jsonb);
      r := r || jsonb_build_object('name','A24 merchant cannot record own payout evidence','ok',false,'detail','allowed');
    EXCEPTION WHEN OTHERS THEN
      r := r || jsonb_build_object('name','A24 merchant cannot record own payout evidence',
        'ok', SQLERRM LIKE 'NOT_AUTHORIZED%','detail',SQLERRM);
    END;

    BEGIN
      PERFORM public.driver_payout_request_create(50000, '+224620000111', 'qa-s11-driver-01');
      r := r || jsonb_build_object('name','A25 Stage 6 driver payout still gated','ok',false,'detail','allowed');
    EXCEPTION WHEN OTHERS THEN
      r := r || jsonb_build_object('name','A25 Stage 6 driver payout still gated',
        'ok', SQLERRM LIKE 'STAGE_DISABLED:driver_cashout_enabled%','detail',SQLERRM);
    END;

    -- ================= FINDING 1: legacy merchant settlement escape path =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_admin), true);
    BEGIN
      PERFORM public.merchant_settlement_complete(v_pay, 'QA-LEGACY-REF-0001');
      r := r || jsonb_build_object('name','A34 legacy merchant_settlement_complete disabled','ok',false,'detail','executed');
    EXCEPTION WHEN OTHERS THEN
      r := r || jsonb_build_object('name','A34 legacy merchant_settlement_complete disabled',
        'ok', SQLERRM LIKE 'LEGACY_PATH_DISABLED:merchant_settlement_complete%','detail',SQLERRM);
    END;
    BEGIN
      PERFORM public.merchant_settlement_hold(v_pay);
      r := r || jsonb_build_object('name','A35 legacy merchant_settlement_hold disabled','ok',false,'detail','executed');
    EXCEPTION WHEN OTHERS THEN
      r := r || jsonb_build_object('name','A35 legacy merchant_settlement_hold disabled',
        'ok', SQLERRM LIKE 'LEGACY_PATH_DISABLED:merchant_settlement_hold%','detail',SQLERRM);
    END;
    BEGIN
      PERFORM public.merchant_settlement_fail(v_pay, 'QA legacy fail attempt');
      r := r || jsonb_build_object('name','A36 legacy merchant_settlement_fail disabled','ok',false,'detail','executed');
    EXCEPTION WHEN OTHERS THEN
      r := r || jsonb_build_object('name','A36 legacy merchant_settlement_fail disabled',
        'ok', SQLERRM LIKE 'LEGACY_PATH_DISABLED:merchant_settlement_fail%','detail',SQLERRM);
    END;
    SELECT settled_gnf INTO v_settled FROM public.merchant_payables WHERE id = v_pay;
    SELECT balance_gnf INTO v_bal FROM public.wallets WHERE owner_user_id = v_owner AND party_type='merchant';
    r := r || jsonb_build_object('name','A37 legacy attempts moved zero',
      'ok', v_settled = 300000 AND v_bal = 200000,
      'detail', format('payable_settled=%s wallet=%s', v_settled, v_bal));

    -- ================= FINDING 2: legacy driver payout bypass =================
    BEGIN
      PERFORM public.driver_payout_hold_place(gen_random_uuid(), gen_random_uuid(), 50000);
      r := r || jsonb_build_object('name','A38 legacy driver_payout_hold_place stage-gated','ok',false,'detail','executed');
    EXCEPTION WHEN OTHERS THEN
      r := r || jsonb_build_object('name','A38 legacy driver_payout_hold_place stage-gated',
        'ok', SQLERRM LIKE 'STAGE_DISABLED:driver_cashout_enabled%','detail',SQLERRM);
    END;
    BEGIN
      PERFORM public.driver_payout_confirm(gen_random_uuid(), 'QA-DRIVER-REF-0001');
      r := r || jsonb_build_object('name','A39 legacy driver_payout_confirm stage-gated','ok',false,'detail','executed');
    EXCEPTION WHEN OTHERS THEN
      r := r || jsonb_build_object('name','A39 legacy driver_payout_confirm stage-gated',
        'ok', SQLERRM LIKE 'STAGE_DISABLED:driver_cashout_enabled%','detail',SQLERRM);
    END;
    BEGIN
      PERFORM public.driver_cashout_mark_paid(gen_random_uuid(), 'QA-DRIVER-REF-0002', NULL);
      r := r || jsonb_build_object('name','A40 driver_cashout_mark_paid stage-gated','ok',false,'detail','executed');
    EXCEPTION WHEN OTHERS THEN
      r := r || jsonb_build_object('name','A40 driver_cashout_mark_paid stage-gated',
        'ok', SQLERRM LIKE 'STAGE_DISABLED:driver_cashout_enabled%' OR SQLERRM LIKE 'not_authorized%',
        'detail',SQLERRM);
    END;

    -- ============ FINDING 3: debit point revalidates evidence (direct calls) ============
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_owner), true);
    v_req2 := public.merchant_settlement_request_create(100000, 'qa-s11-idem-0005', v_store, 'QA3');
    v_o3 := (v_req2->>'payout_order_id')::uuid;
    v_req2 := public.merchant_settlement_request_create(50000, 'qa-s11-idem-0006', v_store, 'QA4');
    v_o4 := (v_req2->>'payout_order_id')::uuid;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_admin), true);
    v_res := public.payout_record_provider_evidence(
      v_o3,'orange_money','QA-DIR-'||substr(gen_random_uuid()::text,1,8),
      '+224620000111', 50000,'success','sandbox', now(), 0, '{}'::jsonb);
    v_ev := (v_res->>'evidence_id')::uuid;
    BEGIN
      PERFORM public._payout_settle_internal(v_o3, v_ev, v_admin);
      r := r || jsonb_build_object('name','A41 direct settle with mismatched evidence rejected','ok',false,'detail','executed');
    EXCEPTION WHEN OTHERS THEN
      r := r || jsonb_build_object('name','A41 direct settle with mismatched evidence rejected',
        'ok', SQLERRM LIKE 'EVIDENCE_VALIDATION_FAILED:amount_mismatch%','detail',SQLERRM);
    END;
    BEGIN
      PERFORM public._payout_settle_internal(v_o4, v_ev, v_admin);
      r := r || jsonb_build_object('name','A42 direct settle with unlinked evidence rejected','ok',false,'detail','executed');
    EXCEPTION WHEN OTHERS THEN
      r := r || jsonb_build_object('name','A42 direct settle with unlinked evidence rejected',
        'ok', SQLERRM LIKE 'EVIDENCE_VALIDATION_FAILED:evidence_not_linked%','detail',SQLERRM);
    END;
    SELECT settled_gnf INTO v_settled FROM public.merchant_payables WHERE id = v_pay;
    SELECT balance_gnf INTO v_bal FROM public.wallets WHERE owner_user_id = v_owner AND party_type='merchant';
    r := r || jsonb_build_object('name','A43 direct-call abuse moved zero',
      'ok', v_settled = 300000 AND v_bal = 200000,
      'detail', format('payable_settled=%s wallet=%s', v_settled, v_bal));
    PERFORM public.payout_reject_release(v_o3, 'QA cleanup: direct-call fixture');
    PERFORM public.payout_reject_release(v_o4, 'QA cleanup: direct-call fixture');

    -- ================= FINDING 4a: non-zero fee, recipient-borne =================
    v_store2 := public._qa_s11_fixture_store(v_owner2);
    INSERT INTO public.wallets (owner_user_id, party_type, balance_gnf, held_gnf)
    VALUES (v_owner2, 'merchant', 1000000, 0);
    INSERT INTO public.merchant_payables
      (payable_key, source_module, source_id, merchant_store_id, merchant_user_id,
       subtotal_gnf, amount_gnf, funded_gnf, state, funding_source)
    VALUES ('qa-s11-fee-' || v_store2::text, 'qa_s11', gen_random_uuid(), v_store2, v_owner2,
            1000000, 1000000, 1000000, 'funded', 'customer_choppay')
    RETURNING id INTO v_pay2;

    INSERT INTO public.provider_fee_schedules
      (provider, fee_bps, fee_fixed_gnf, min_fee_gnf, passthrough_to_recipient, effective_from, enabled, note)
    VALUES ('orange_money', 0, 5000, 0, true, now() - interval '3 seconds', true, 'QA S11 recipient-borne');

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_owner2), true);
    v_req2 := public.merchant_settlement_request_create(100000, 'qa-s11-fee-r-01', v_store2, 'QA fee R');
    vf1 := (v_req2->>'payout_order_id')::uuid;
    SELECT * INTO v_ord FROM public.payout_orders WHERE id = vf1;
    r := r || jsonb_build_object('name','A44 recipient-borne fee frozen on reservation',
      'ok', v_ord.provider_fee_gnf = 5000 AND v_ord.fee_borne_by = 'recipient'
            AND v_ord.merchant_liability_debit_gnf = 100000
            AND v_ord.recipient_net_gnf = 95000
            AND v_ord.expected_provider_transfer_gnf = 95000,
      'detail', format('fee=%s borne=%s debit=%s net=%s expected=%s',
        v_ord.provider_fee_gnf, v_ord.fee_borne_by, v_ord.merchant_liability_debit_gnf,
        v_ord.recipient_net_gnf, v_ord.expected_provider_transfer_gnf));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_admin), true);
    v_res := public.payout_record_provider_evidence(
      vf1,'orange_money','QA-FEEP-'||substr(gen_random_uuid()::text,1,8),
      '+224620000111', 100000,'success','sandbox', now(), 5000, '{}'::jsonb);
    r := r || jsonb_build_object('name','A45 principal-amount evidence no longer accepted with non-zero fee',
      'ok', v_res->>'reason' = 'amount_mismatch' AND (v_res->>'moved_gnf')::bigint = 0,
      'detail', v_res::text);

    v_res := public.payout_record_provider_evidence(
      vf1,'orange_money','QA-FEEF-'||substr(gen_random_uuid()::text,1,8),
      '+224620000111', 95000,'success','sandbox', now(), 9999, '{}'::jsonb);
    r := r || jsonb_build_object('name','A46 provider fee mismatch parks',
      'ok', v_res->>'reason' = 'provider_fee_mismatch' AND (v_res->>'moved_gnf')::bigint = 0,
      'detail', v_res::text);

    v_res := public.payout_record_provider_evidence(
      vf1,'orange_money', v_refr, '+224620000111', 95000,'success','sandbox', now(), 5000, '{}'::jsonb);
    SELECT settled_gnf INTO v_settled FROM public.merchant_payables WHERE id = v_pay2;
    SELECT balance_gnf INTO v_bal FROM public.wallets WHERE owner_user_id = v_owner2 AND party_type='merchant';
    r := r || jsonb_build_object('name','A47 recipient-borne exact evidence settles exact liability',
      'ok', (v_res->>'moved_gnf')::bigint = 100000 AND v_settled = 100000 AND v_bal = 900000,
      'detail', format('moved=%s payable_settled=%s wallet=%s', v_res->>'moved_gnf', v_settled, v_bal));

    SELECT COALESCE(SUM(p.amount_gnf),0), count(*) INTO v_journal, v_n
      FROM public.ledger_postings p JOIN public.ledger_journals j ON j.id = p.journal_id
     WHERE j.journal_key = 'payout-settle:' || vf1::text;
    SELECT count(*) INTO v_cnt FROM public.ledger_postings p
      JOIN public.ledger_journals j ON j.id = p.journal_id
      JOIN public.ledger_accounts a ON a.id = p.account_id
     WHERE j.journal_key = 'payout-settle:' || vf1::text AND a.code = 'E_PROVIDER_FEE';
    r := r || jsonb_build_object('name','A48 recipient-borne journal balanced with no platform fee expense',
      'ok', v_journal = 0 AND v_n = 2 AND v_cnt = 0,
      'detail', format('sum=%s lines=%s fee_lines=%s', v_journal, v_n, v_cnt));

    v_res := public.merchant_settlement_receipt((v_req2->>'request_id')::uuid);
    r := r || jsonb_build_object('name','A49 receipt exposes canonical fee economics',
      'ok', (v_res->>'provider_fee_gnf')::bigint = 5000
            AND v_res->>'fee_borne_by' = 'recipient'
            AND (v_res->>'expected_provider_transfer_gnf')::bigint = 95000
            AND (v_res->>'merchant_liability_debit_gnf')::bigint = 100000,
      'detail', v_res::text);

    v_res := public.payout_record_provider_evidence(
      vf1,'orange_money', v_refr, '+224620000111', 95000,'success','sandbox', now(), 5000, '{}'::jsonb);
    SELECT settled_gnf INTO v_settled FROM public.merchant_payables WHERE id = v_pay2;
    r := r || jsonb_build_object('name','A50 non-zero fee replay moves zero',
      'ok', (v_res->>'moved_gnf')::bigint = 0 AND v_settled = 100000, 'detail', v_res::text);

    -- ============ FINDING 4b: snapshot immutability against later policy change ============
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_owner2), true);
    v_req2 := public.merchant_settlement_request_create(100000, 'qa-s11-fee-r-02', v_store2, 'QA snapshot');
    vf2 := (v_req2->>'payout_order_id')::uuid;
    INSERT INTO public.provider_fee_schedules
      (provider, fee_bps, fee_fixed_gnf, min_fee_gnf, passthrough_to_recipient, effective_from, enabled, note)
    VALUES ('orange_money', 0, 20000, 0, true, now() - interval '2 seconds', true, 'QA S11 later policy');
    SELECT * INTO v_ord FROM public.payout_orders WHERE id = vf2;
    r := r || jsonb_build_object('name','A51 later fee policy does not alter a reserved order',
      'ok', v_ord.provider_fee_gnf = 5000 AND v_ord.expected_provider_transfer_gnf = 95000,
      'detail', format('fee=%s expected=%s', v_ord.provider_fee_gnf, v_ord.expected_provider_transfer_gnf));
    BEGIN
      UPDATE public.payout_orders SET provider_fee_gnf = 1 WHERE id = vf2;
      r := r || jsonb_build_object('name','A52 payout order economics are immutable','ok',false,'detail','mutated');
    EXCEPTION WHEN OTHERS THEN
      r := r || jsonb_build_object('name','A52 payout order economics are immutable',
        'ok', SQLERRM LIKE 'PAYOUT_ORDER_IMMUTABLE%','detail',SQLERRM);
    END;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_admin), true);
    PERFORM public.payout_reject_release(vf2, 'QA cleanup: snapshot fixture');

    -- ================= FINDING 4c: non-zero fee, platform-borne =================
    INSERT INTO public.provider_fee_schedules
      (provider, fee_bps, fee_fixed_gnf, min_fee_gnf, passthrough_to_recipient, effective_from, enabled, note)
    VALUES ('orange_money', 0, 5000, 0, false, now() - interval '1 second', true, 'QA S11 platform-borne');

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_owner2), true);
    v_req2 := public.merchant_settlement_request_create(100000, 'qa-s11-fee-p-01', v_store2, 'QA fee P');
    vp1 := (v_req2->>'payout_order_id')::uuid;
    SELECT * INTO v_ord FROM public.payout_orders WHERE id = vp1;
    r := r || jsonb_build_object('name','A53 platform-borne fee frozen on reservation',
      'ok', v_ord.provider_fee_gnf = 5000 AND v_ord.fee_borne_by = 'platform'
            AND v_ord.merchant_liability_debit_gnf = 100000
            AND v_ord.recipient_net_gnf = 100000
            AND v_ord.expected_provider_transfer_gnf = 100000,
      'detail', format('fee=%s borne=%s debit=%s expected=%s', v_ord.provider_fee_gnf,
        v_ord.fee_borne_by, v_ord.merchant_liability_debit_gnf, v_ord.expected_provider_transfer_gnf));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_admin), true);
    v_res := public.payout_record_provider_evidence(
      vp1,'orange_money', v_refp, '+224620000111', 100000,'success','sandbox', now(), 5000, '{}'::jsonb);
    SELECT settled_gnf INTO v_settled FROM public.merchant_payables WHERE id = v_pay2;
    SELECT balance_gnf INTO v_bal FROM public.wallets WHERE owner_user_id = v_owner2 AND party_type='merchant';
    r := r || jsonb_build_object('name','A54 platform-borne settlement debits exact merchant principal',
      'ok', (v_res->>'moved_gnf')::bigint = 100000 AND v_settled = 200000 AND v_bal = 800000,
      'detail', format('moved=%s payable_settled=%s wallet=%s', v_res->>'moved_gnf', v_settled, v_bal));

    SELECT COALESCE(SUM(p.amount_gnf),0), count(*) INTO v_journal, v_n
      FROM public.ledger_postings p JOIN public.ledger_journals j ON j.id = p.journal_id
     WHERE j.journal_key = 'payout-settle:' || vp1::text;
    SELECT count(*), COALESCE(SUM(p.amount_gnf),0) INTO v_cnt, v_sum
      FROM public.ledger_postings p
      JOIN public.ledger_journals j ON j.id = p.journal_id
      JOIN public.ledger_accounts a ON a.id = p.account_id
     WHERE j.journal_key = 'payout-settle:' || vp1::text AND a.code = 'E_PROVIDER_FEE';
    r := r || jsonb_build_object('name','A55 provider fee posts to expense exactly once and journal balances',
      'ok', v_journal = 0 AND v_n = 3 AND v_cnt = 1 AND v_sum = 5000,
      'detail', format('sum=%s lines=%s fee_lines=%s fee_amount=%s', v_journal, v_n, v_cnt, v_sum));

    v_res := public.payout_record_provider_evidence(
      vp1,'orange_money', v_refp, '+224620000111', 100000,'success','sandbox', now(), 5000, '{}'::jsonb);
    SELECT settled_gnf INTO v_settled FROM public.merchant_payables WHERE id = v_pay2;
    r := r || jsonb_build_object('name','A56 platform-borne replay moves zero',
      'ok', (v_res->>'moved_gnf')::bigint = 0 AND v_settled = 200000, 'detail', v_res::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_owner2), true);
    v_req2 := public.merchant_settlement_request_create(50000, 'qa-s11-xref-01', v_store2, 'QA xref');
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_admin), true);
    BEGIN
      PERFORM public.payout_record_provider_evidence(
        (v_req2->>'payout_order_id')::uuid,'orange_money', v_refr,
        '+224620000111', 45000,'success','sandbox', now(), 5000, '{}'::jsonb);
      r := r || jsonb_build_object('name','A57 one-reference-one-settlement across orders','ok',false,'detail','reused');
    EXCEPTION WHEN OTHERS THEN
      r := r || jsonb_build_object('name','A57 one-reference-one-settlement across orders',
        'ok', SQLERRM LIKE 'PROVIDER_REFERENCE_ALREADY_CONSUMED%','detail',SQLERRM);
    END;
    PERFORM public.payout_reject_release((v_req2->>'payout_order_id')::uuid, 'QA cleanup: xref fixture');

    -- ================= FINDING 4d: configured scheduler, non-vacuous =================
    v_store3 := public._qa_s11_fixture_store(v_owner3);
    INSERT INTO public.wallets (owner_user_id, party_type, balance_gnf, held_gnf)
    VALUES (v_owner3, 'merchant', 300000, 0);
    INSERT INTO public.merchant_payables
      (payable_key, source_module, source_id, merchant_store_id, merchant_user_id,
       subtotal_gnf, amount_gnf, funded_gnf, state, funding_source)
    VALUES ('qa-s11-sched-' || v_store3::text, 'qa_s11', gen_random_uuid(), v_store3, v_owner3,
            300000, 300000, 300000, 'funded', 'customer_choppay')
    RETURNING id INTO v_pay3;

    INSERT INTO public.merchant_settlement_policies
      (configured, min_settlement_gnf, max_settlement_gnf, cadence, fee_passthrough,
       requires_evidence_reconciliation, effective_from, enabled, note)
    VALUES (true, 1000, 150000, 'daily', NULL, true, now() - interval '1 second', true, 'QA S11 scheduler');

    v_sched1 := public.merchant_settlement_schedule_generate(now());
    SELECT count(*) INTO v_cnt FROM public.merchant_settlement_schedule_runs WHERE merchant_store_id = v_store3;
    SELECT count(*) INTO v_cnt2 FROM public.merchant_settlement_requests WHERE merchant_store_id = v_store3;
    r := r || jsonb_build_object('name','A58 configured scheduler queues exactly one request per store/period',
      'ok', v_cnt = 1 AND v_cnt2 = 1 AND COALESCE((v_sched1->>'created')::int,0) >= 1,
      'detail', format('runs=%s requests=%s %s', v_cnt, v_cnt2, v_sched1::text));

    v_sched2 := public.merchant_settlement_schedule_generate(now());
    SELECT count(*) INTO v_cnt FROM public.merchant_settlement_schedule_runs WHERE merchant_store_id = v_store3;
    SELECT count(*) INTO v_cnt2 FROM public.merchant_settlement_requests WHERE merchant_store_id = v_store3;
    r := r || jsonb_build_object('name','A59 second run in same period creates zero additional',
      'ok', v_cnt = 1 AND v_cnt2 = 1,
      'detail', format('runs=%s requests=%s %s', v_cnt, v_cnt2, v_sched2::text));

    v_sched3 := public.merchant_settlement_schedule_generate(now() + interval '1 day');
    SELECT count(*) INTO v_cnt FROM public.merchant_settlement_schedule_runs WHERE merchant_store_id = v_store3;
    SELECT count(*) INTO v_cnt2 FROM public.merchant_settlement_requests WHERE merchant_store_id = v_store3;
    r := r || jsonb_build_object('name','A60 next valid period queues the next request',
      'ok', v_cnt = 2 AND v_cnt2 = 2,
      'detail', format('runs=%s requests=%s %s', v_cnt, v_cnt2, v_sched3::text));

    SELECT settled_gnf INTO v_settled FROM public.merchant_payables WHERE id = v_pay3;
    SELECT balance_gnf INTO v_bal FROM public.wallets WHERE owner_user_id = v_owner3 AND party_type='merchant';
    SELECT count(*) INTO v_cnt FROM public.ledger_journals j
      JOIN public.payout_orders o ON j.journal_key = 'payout-settle:' || o.id::text
     WHERE o.merchant_store_id = v_store3;
    r := r || jsonb_build_object('name','A61 scheduler never pays or debits anything',
      'ok', v_settled = 0 AND v_bal = 300000 AND v_cnt = 0,
      'detail', format('payable_settled=%s wallet=%s settle_journals=%s', v_settled, v_bal, v_cnt));

    SELECT COALESCE(SUM(amount_gnf),0) INTO v_sum FROM public.ledger_postings;
    r := r || jsonb_build_object('name','A62 ledger stays zero-sum inside the run','ok', v_sum = 0,
      'detail', format('sum=%s', v_sum));

    RAISE EXCEPTION 'QA_S11_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_S11_ROLLBACK' THEN
      r := r || jsonb_build_object('name','HARNESS ERROR','ok',false,'detail',SQLERRM);
    END IF;
  END;

  SELECT count(*) INTO v_n FROM pg_proc p
   WHERE p.pronamespace = 'public'::regnamespace
     AND p.proname IN ('payout_record_provider_evidence','payout_reject_release',
                       'payout_reconcile_evidence','merchant_settlement_schedule_generate',
                       'finance_payout_queue','driver_payout_request_create')
     AND has_function_privilege('anon', p.oid, 'EXECUTE');
  r := r || jsonb_build_object('name','A26 anon has no payout execute','ok', v_n = 0,
    'detail', format('anon_executable=%s', v_n));

  SELECT count(*) INTO v_n FROM pg_proc p
   WHERE p.pronamespace = 'public'::regnamespace
     AND p.proname IN ('_payout_settle_internal','_payout_order_create_internal',
                       '_merchant_settlement_request_queue_internal','_payout_evidence_mismatch_reason')
     AND (has_function_privilege('anon', p.oid, 'EXECUTE')
          OR has_function_privilege('authenticated', p.oid, 'EXECUTE'));
  r := r || jsonb_build_object('name','A27 settlement primitives are internal-only','ok', v_n = 0,
    'detail', format('exposed=%s', v_n));

  SELECT count(*) INTO v_n FROM pg_tables t
   WHERE t.schemaname='public'
     AND t.tablename IN ('payout_orders','payout_provider_evidence',
                         'payout_settlement_allocations','merchant_settlement_schedule_runs')
     AND (has_table_privilege('anon', 'public.'||t.tablename, 'SELECT')
          OR has_table_privilege('authenticated','public.'||t.tablename,'INSERT')
          OR has_table_privilege('authenticated','public.'||t.tablename,'UPDATE')
          OR has_table_privilege('authenticated','public.'||t.tablename,'DELETE'));
  r := r || jsonb_build_object('name','A28 payout tables are read-only / anon-denied','ok', v_n = 0,
    'detail', format('violations=%s', v_n));

  r := r || jsonb_build_object('name','A29 provider evidence never readable by clients directly',
    'ok', NOT has_table_privilege('authenticated','public.payout_provider_evidence','SELECT'),
    'detail','authenticated SELECT on payout_provider_evidence');

  SELECT COALESCE(SUM(amount_gnf),0) INTO v_sum FROM public.ledger_postings;
  r := r || jsonb_build_object('name','A30 global ledger zero-sum','ok', v_sum = 0,
    'detail', format('sum=%s', v_sum));

  SELECT COALESCE(balance_gnf,0) INTO v_master FROM public.wallets WHERE party_type='master' LIMIT 1;
  r := r || jsonb_build_object('name','A31 master wallet baseline unchanged','ok', v_master = -100435,
    'detail', format('master=%s', v_master));

  SELECT COALESCE(bool_and(NOT enabled), true) INTO v_allon FROM public.feature_flags
   WHERE key IN ('merchant_om_settlement_enabled','driver_cashout_enabled','chop_pay_p2p_enabled');
  r := r || jsonb_build_object('name','A32 stage flags remain OFF after run','ok', v_allon,
    'detail', format('all_off=%s', v_allon));

  SELECT count(*) INTO v_n FROM public.payout_orders;
  SELECT count(*) INTO v_cnt FROM public.payout_provider_evidence;
  SELECT count(*) INTO v_cnt2 FROM public.merchant_settlement_schedule_runs;
  r := r || jsonb_build_object('name','A33 no QA rows persisted',
    'ok', v_n = 0 AND v_cnt = 0 AND v_cnt2 = 0,
    'detail', format('payout_orders=%s evidence=%s schedule_runs=%s', v_n, v_cnt, v_cnt2));

  -- Source-level exit proof for finding 1.
  SELECT count(*) INTO v_n FROM pg_proc p
   WHERE p.pronamespace = 'public'::regnamespace
     AND p.prosrc ~ 'settled_gnf\s*=\s*settled_gnf'
     AND p.proname <> '_payout_settle_internal';
  r := r || jsonb_build_object('name','A63 only _payout_settle_internal debits merchant payables',
    'ok', v_n = 0, 'detail', format('other_writers=%s', v_n));

  SELECT count(*) INTO v_n FROM pg_proc p
   WHERE p.pronamespace = 'public'::regnamespace
     AND p.proname IN ('merchant_settlement_complete','merchant_settlement_hold','merchant_settlement_fail')
     AND (has_function_privilege('anon', p.oid, 'EXECUTE')
          OR has_function_privilege('authenticated', p.oid, 'EXECUTE')
          OR has_function_privilege('service_role', p.oid, 'EXECUTE'));
  r := r || jsonb_build_object('name','A64 legacy merchant settlement functions have no callable grants',
    'ok', v_n = 0, 'detail', format('exposed=%s', v_n));

  SELECT count(*) INTO v_n FROM pg_proc p
   WHERE p.pronamespace = 'public'::regnamespace
     AND p.proname IN ('driver_payout_confirm','driver_payout_cancel','driver_payout_hold_place')
     AND (has_function_privilege('anon', p.oid, 'EXECUTE')
          OR has_function_privilege('authenticated', p.oid, 'EXECUTE'));
  r := r || jsonb_build_object('name','A65 legacy driver payout functions not client-callable',
    'ok', v_n = 0, 'detail', format('exposed=%s', v_n));

  DELETE FROM public._qa_s11_results;
  INSERT INTO public._qa_s11_results (name, ok, detail)
  SELECT x->>'name', (x->>'ok')::boolean, x->>'detail' FROM jsonb_array_elements(r) x;

  SELECT count(*) FILTER (WHERE (x->>'ok')::boolean), count(*) INTO v_pass, v_total
    FROM jsonb_array_elements(r) x;
  RETURN jsonb_build_object('pass', v_pass, 'total', v_total, 'results', r);
END $function$;