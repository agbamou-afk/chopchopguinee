CREATE OR REPLACE FUNCTION public._qa_s11_run()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  r jsonb := '[]'::jsonb;
  v_owner uuid := gen_random_uuid();
  v_admin uuid := gen_random_uuid();
  v_store uuid; v_pay uuid; v_req jsonb; v_req2 jsonb; v_o uuid; v_o2 uuid;
  v_ov jsonb; v_res jsonb; v_bal bigint; v_settled bigint; v_status text;
  v_sum bigint; v_master bigint; v_n int; v_ref text := 'QA-S11-' || substr(gen_random_uuid()::text,1,8);
  v_journal bigint; v_pass int; v_total int; v_sched1 jsonb; v_sched2 jsonb; v_allon boolean;
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
                       '_merchant_settlement_request_queue_internal')
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
  r := r || jsonb_build_object('name','A33 no QA rows persisted','ok', v_n = 0,
    'detail', format('payout_orders=%s', v_n));

  DELETE FROM public._qa_s11_results;
  INSERT INTO public._qa_s11_results (name, ok, detail)
  SELECT x->>'name', (x->>'ok')::boolean, x->>'detail' FROM jsonb_array_elements(r) x;

  SELECT count(*) FILTER (WHERE (x->>'ok')::boolean), count(*) INTO v_pass, v_total
    FROM jsonb_array_elements(r) x;
  RETURN jsonb_build_object('pass', v_pass, 'total', v_total, 'results', r);
END $fn$;
REVOKE ALL ON FUNCTION public._qa_s11_run() FROM PUBLIC, anon, authenticated;