CREATE OR REPLACE FUNCTION public._qa_s9f_run()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r text[] := ARRAY[]::text[];
  ok_ct int; fail_ct int;
  v_master_before bigint; v_master_after bigint;
  v_row text;
BEGIN
  SELECT balance_gnf INTO v_master_before FROM public.wallets WHERE party_type='master' LIMIT 1;

  BEGIN
    DECLARE
      v_c uuid; v_w uuid; b0 bigint;
      v_acct uuid; v_acct2 uuid;
      v_phone text; v_other_phone text := '+224611111199';
      v_t uuid; v_e uuid; v_res jsonb; v_n int; v_err text;
      v_pfx text := 'PPF' || to_char(now(),'YYMMDDHH24MISS') || '.';
      v_i int := 0;
      FUNCTION_NOOP boolean;
    BEGIN
      SELECT w.owner_user_id, w.id, w.balance_gnf INTO v_c, v_w, b0
        FROM public.wallets w WHERE w.party_type='client' AND w.status='active'
        ORDER BY w.created_at LIMIT 1;
      SELECT id INTO v_acct FROM public.payment_receiving_accounts
        WHERE provider='orange_money' AND is_active = true ORDER BY updated_at DESC LIMIT 1;
      INSERT INTO public.payment_receiving_accounts (provider, label, phone_e164, is_active)
        VALUES ('orange_money','QA S9F ALT','+224600000019', false) RETURNING id INTO v_acct2;
      SELECT public._normalize_guinea_phone(phone) INTO v_phone FROM public.profiles WHERE user_id = v_c;
      IF v_phone IS NULL THEN
        v_phone := '+224622222299';
        UPDATE public.profiles SET phone = v_phone WHERE user_id = v_c;
      END IF;

      -- H1/H2 complete exact evidence credits exactly once
      v_i := v_i + 1;
      INSERT INTO public.topup_requests
        (reference, client_user_id, amount_gnf, confirmation_code, provider, user_phone,
         status, expires_at, receiving_account_id, target_party_type, environment,
         customer_om_code_normalized, customer_om_code_raw, customer_om_code_submitted_at)
      VALUES ('QA9F-'||substr(md5(random()::text),1,8), v_c, 120000, '------','orange_money', v_phone,
              'matched'::topup_status, now()+interval '2 hours', v_acct, 'client','production',
              public.normalize_om_code(v_pfx||'H1'), v_pfx||'H1', now())
      RETURNING id INTO v_t;
      INSERT INTO public.payment_provider_events
        (provider, provider_transaction_id, payer_phone, amount_gnf, status, processing_status,
         receiving_account_id, environment, is_sandbox, raw_payload)
      VALUES ('orange_money', v_pfx||'H1', v_phone, 120000,'successful','received', v_acct,'production',false,'{}'::jsonb)
      RETURNING id INTO v_e;
      v_res := public.om_auto_match(v_e);
      r := r || format('%s|H1 complete exact evidence credits|status=%s', CASE WHEN v_res->>'status'='credited' THEN 'PASS' ELSE 'FAIL' END, v_res->>'status');
      r := r || format('%s|H2 wallet credited exactly once (+120000)|%s', CASE WHEN (SELECT balance_gnf FROM public.wallets WHERE id=v_w)=b0+120000 THEN 'PASS' ELSE 'FAIL' END, (SELECT balance_gnf FROM public.wallets WHERE id=v_w)-b0);

      -- H3 event payer phone missing
      INSERT INTO public.topup_requests
        (reference, client_user_id, amount_gnf, confirmation_code, provider, user_phone,
         status, expires_at, receiving_account_id, target_party_type, environment,
         customer_om_code_normalized, customer_om_code_raw, customer_om_code_submitted_at)
      VALUES ('QA9F-'||substr(md5(random()::text),1,8), v_c, 130000, '------','orange_money', v_phone,
              'matched'::topup_status, now()+interval '2 hours', v_acct, 'client','production',
              public.normalize_om_code(v_pfx||'H3'), v_pfx||'H3', now())
      RETURNING id INTO v_t;
      INSERT INTO public.payment_provider_events
        (provider, provider_transaction_id, payer_phone, amount_gnf, status, processing_status,
         receiving_account_id, environment, is_sandbox, raw_payload)
      VALUES ('orange_money', v_pfx||'H3', NULL, 130000,'successful','received', v_acct,'production',false,'{}'::jsonb)
      RETURNING id INTO v_e;
      v_res := public.om_auto_match(v_e);
      r := r || format('%s|H3 missing event payer phone parks needs_review|reason=%s', CASE WHEN v_res->>'status'='needs_review' AND v_res->>'reason'='payer_phone_missing' THEN 'PASS' ELSE 'FAIL' END, v_res->>'reason');
      r := r || format('%s|H3b zero credit on missing event phone|%s', CASE WHEN (SELECT balance_gnf FROM public.wallets WHERE id=v_w)=b0+120000 THEN 'PASS' ELSE 'FAIL' END, (SELECT balance_gnf FROM public.wallets WHERE id=v_w)-b0);
      BEGIN
        PERFORM public.wallet_topup_om_credit(v_e, v_t);
        r := r || 'FAIL|H3c forced credit refuses missing event phone|credited'::text;
      EXCEPTION WHEN OTHERS THEN
        v_err := SQLERRM;
        r := r || format('%s|H3c forced credit refuses missing event phone|%s', CASE WHEN v_err LIKE '%payer_phone_missing%' THEN 'PASS' ELSE 'FAIL' END, v_err);
      END;

      -- H4 request-side payer phone missing
      UPDATE public.profiles SET phone = NULL WHERE user_id = v_c;
      INSERT INTO public.topup_requests
        (reference, client_user_id, amount_gnf, confirmation_code, provider, user_phone,
         status, expires_at, receiving_account_id, target_party_type, environment,
         customer_om_code_normalized, customer_om_code_raw, customer_om_code_submitted_at)
      VALUES ('QA9F-'||substr(md5(random()::text),1,8), v_c, 140000, '------','orange_money', NULL,
              'matched'::topup_status, now()+interval '2 hours', v_acct, 'client','production',
              public.normalize_om_code(v_pfx||'H4'), v_pfx||'H4', now())
      RETURNING id INTO v_t;
      INSERT INTO public.payment_provider_events
        (provider, provider_transaction_id, payer_phone, amount_gnf, status, processing_status,
         receiving_account_id, environment, is_sandbox, raw_payload)
      VALUES ('orange_money', v_pfx||'H4', v_phone, 140000,'successful','received', v_acct,'production',false,'{}'::jsonb)
      RETURNING id INTO v_e;
      v_res := public.om_auto_match(v_e);
      r := r || format('%s|H4 missing request payer phone parks needs_review|reason=%s', CASE WHEN v_res->>'status'='needs_review' AND v_res->>'reason'='payer_phone_missing' THEN 'PASS' ELSE 'FAIL' END, v_res->>'reason');
      BEGIN
        PERFORM public.wallet_topup_om_credit(v_e, v_t);
        r := r || 'FAIL|H4b forced credit refuses missing request phone|credited'::text;
      EXCEPTION WHEN OTHERS THEN
        v_err := SQLERRM;
        r := r || format('%s|H4b forced credit refuses missing request phone|%s', CASE WHEN v_err LIKE '%payer_phone_missing%' THEN 'PASS' ELSE 'FAIL' END, v_err);
      END;
      UPDATE public.profiles SET phone = v_phone WHERE user_id = v_c;

      -- H5 phone mismatch
      INSERT INTO public.topup_requests
        (reference, client_user_id, amount_gnf, confirmation_code, provider, user_phone,
         status, expires_at, receiving_account_id, target_party_type, environment,
         customer_om_code_normalized, customer_om_code_raw, customer_om_code_submitted_at)
      VALUES ('QA9F-'||substr(md5(random()::text),1,8), v_c, 150000, '------','orange_money', v_phone,
              'matched'::topup_status, now()+interval '2 hours', v_acct, 'client','production',
              public.normalize_om_code(v_pfx||'H5'), v_pfx||'H5', now())
      RETURNING id INTO v_t;
      INSERT INTO public.payment_provider_events
        (provider, provider_transaction_id, payer_phone, amount_gnf, status, processing_status,
         receiving_account_id, environment, is_sandbox, raw_payload)
      VALUES ('orange_money', v_pfx||'H5', v_other_phone, 150000,'successful','received', v_acct,'production',false,'{}'::jsonb)
      RETURNING id INTO v_e;
      v_res := public.om_auto_match(v_e);
      r := r || format('%s|H5 payer phone mismatch parks needs_review|reason=%s', CASE WHEN v_res->>'reason'='payer_phone_mismatch' THEN 'PASS' ELSE 'FAIL' END, v_res->>'reason');
      BEGIN
        PERFORM public.wallet_topup_om_credit(v_e, v_t);
        r := r || 'FAIL|H5b forced credit refuses phone mismatch|credited'::text;
      EXCEPTION WHEN OTHERS THEN
        v_err := SQLERRM;
        r := r || format('%s|H5b forced credit refuses phone mismatch|%s', CASE WHEN v_err LIKE '%payer_phone_mismatch%' THEN 'PASS' ELSE 'FAIL' END, v_err);
      END;

      -- H6 event receiving account missing
      INSERT INTO public.topup_requests
        (reference, client_user_id, amount_gnf, confirmation_code, provider, user_phone,
         status, expires_at, receiving_account_id, target_party_type, environment,
         customer_om_code_normalized, customer_om_code_raw, customer_om_code_submitted_at)
      VALUES ('QA9F-'||substr(md5(random()::text),1,8), v_c, 160000, '------','orange_money', v_phone,
              'matched'::topup_status, now()+interval '2 hours', v_acct, 'client','production',
              public.normalize_om_code(v_pfx||'H6'), v_pfx||'H6', now())
      RETURNING id INTO v_t;
      INSERT INTO public.payment_provider_events
        (provider, provider_transaction_id, payer_phone, amount_gnf, status, processing_status,
         receiving_account_id, environment, is_sandbox, raw_payload)
      VALUES ('orange_money', v_pfx||'H6', v_phone, 160000,'successful','received', NULL,'production',false,'{}'::jsonb)
      RETURNING id INTO v_e;
      v_res := public.om_auto_match(v_e);
      r := r || format('%s|H6 missing event receiving account parks needs_review|reason=%s', CASE WHEN v_res->>'reason'='receiving_account_missing' THEN 'PASS' ELSE 'FAIL' END, v_res->>'reason');
      BEGIN
        PERFORM public.wallet_topup_om_credit(v_e, v_t);
        r := r || 'FAIL|H6b forced credit refuses missing event account|credited'::text;
      EXCEPTION WHEN OTHERS THEN
        v_err := SQLERRM;
        r := r || format('%s|H6b forced credit refuses missing event account|%s', CASE WHEN v_err LIKE '%receiving_account_missing%' THEN 'PASS' ELSE 'FAIL' END, v_err);
      END;

      -- H7 request receiving account missing
      INSERT INTO public.topup_requests
        (reference, client_user_id, amount_gnf, confirmation_code, provider, user_phone,
         status, expires_at, receiving_account_id, target_party_type, environment,
         customer_om_code_normalized, customer_om_code_raw, customer_om_code_submitted_at)
      VALUES ('QA9F-'||substr(md5(random()::text),1,8), v_c, 170000, '------','orange_money', v_phone,
              'matched'::topup_status, now()+interval '2 hours', NULL, 'client','production',
              public.normalize_om_code(v_pfx||'H7'), v_pfx||'H7', now())
      RETURNING id INTO v_t;
      INSERT INTO public.payment_provider_events
        (provider, provider_transaction_id, payer_phone, amount_gnf, status, processing_status,
         receiving_account_id, environment, is_sandbox, raw_payload)
      VALUES ('orange_money', v_pfx||'H7', v_phone, 170000,'successful','received', v_acct,'production',false,'{}'::jsonb)
      RETURNING id INTO v_e;
      v_res := public.om_auto_match(v_e);
      r := r || format('%s|H7 missing request receiving account parks needs_review|reason=%s', CASE WHEN v_res->>'reason'='receiving_account_missing' THEN 'PASS' ELSE 'FAIL' END, v_res->>'reason');
      BEGIN
        PERFORM public.wallet_topup_om_credit(v_e, v_t);
        r := r || 'FAIL|H7b forced credit refuses missing request account|credited'::text;
      EXCEPTION WHEN OTHERS THEN
        v_err := SQLERRM;
        r := r || format('%s|H7b forced credit refuses missing request account|%s', CASE WHEN v_err LIKE '%receiving_account_missing%' THEN 'PASS' ELSE 'FAIL' END, v_err);
      END;

      -- H8 receiving account mismatch
      INSERT INTO public.topup_requests
        (reference, client_user_id, amount_gnf, confirmation_code, provider, user_phone,
         status, expires_at, receiving_account_id, target_party_type, environment,
         customer_om_code_normalized, customer_om_code_raw, customer_om_code_submitted_at)
      VALUES ('QA9F-'||substr(md5(random()::text),1,8), v_c, 180000, '------','orange_money', v_phone,
              'matched'::topup_status, now()+interval '2 hours', v_acct, 'client','production',
              public.normalize_om_code(v_pfx||'H8'), v_pfx||'H8', now())
      RETURNING id INTO v_t;
      INSERT INTO public.payment_provider_events
        (provider, provider_transaction_id, payer_phone, amount_gnf, status, processing_status,
         receiving_account_id, environment, is_sandbox, raw_payload)
      VALUES ('orange_money', v_pfx||'H8', v_phone, 180000,'successful','received', v_acct2,'production',false,'{}'::jsonb)
      RETURNING id INTO v_e;
      v_res := public.om_auto_match(v_e);
      r := r || format('%s|H8 receiving account mismatch parks needs_review|reason=%s', CASE WHEN v_res->>'reason'='receiving_account_mismatch' THEN 'PASS' ELSE 'FAIL' END, v_res->>'reason');
      BEGIN
        PERFORM public.wallet_topup_om_credit(v_e, v_t);
        r := r || 'FAIL|H8b forced credit refuses account mismatch|credited'::text;
      EXCEPTION WHEN OTHERS THEN
        v_err := SQLERRM;
        r := r || format('%s|H8b forced credit refuses account mismatch|%s', CASE WHEN v_err LIKE '%receiving_account_mismatch%' THEN 'PASS' ELSE 'FAIL' END, v_err);
      END;

      -- H9 no drift beyond the single legitimate credit
      r := r || format('%s|H9 only the complete-evidence credit moved value|%s', CASE WHEN (SELECT balance_gnf FROM public.wallets WHERE id=v_w)=b0+120000 THEN 'PASS' ELSE 'FAIL' END, (SELECT balance_gnf FROM public.wallets WHERE id=v_w)-b0);
      SELECT count(*) INTO v_n FROM public.wallet_transactions WHERE type='topup'
        AND (metadata->>'provider_transaction_id') LIKE v_pfx||'%';
      r := r || format('%s|H10 exactly one QA top-up transaction|n=%s', CASE WHEN v_n=1 THEN 'PASS' ELSE 'FAIL' END, v_n);

      -- H11..H14 static contract assertions
      r := r || format('%s|H11 matcher enforces payer_phone_missing|', CASE WHEN position('payer_phone_missing' in pg_get_functiondef('public.om_auto_match(uuid)'::regprocedure))>0 THEN 'PASS' ELSE 'FAIL' END);
      r := r || format('%s|H12 matcher enforces receiving_account_missing|', CASE WHEN position('receiving_account_missing' in pg_get_functiondef('public.om_auto_match(uuid)'::regprocedure))>0 THEN 'PASS' ELSE 'FAIL' END);
      r := r || format('%s|H13 credit primitive enforces both presence rules|', CASE WHEN position('payer_phone_missing' in pg_get_functiondef('public.wallet_topup_om_credit(uuid,uuid)'::regprocedure))>0 AND position('receiving_account_missing' in pg_get_functiondef('public.wallet_topup_om_credit(uuid,uuid)'::regprocedure))>0 THEN 'PASS' ELSE 'FAIL' END);
      r := r || format('%s|H14 admin manual receipt routes through om_auto_match (records, never bypasses)|', CASE WHEN position('om_auto_match' in pg_get_functiondef('public.admin_record_om_receipt(text,bigint,text,uuid,text)'::regprocedure))>0 THEN 'PASS' ELSE 'FAIL' END);

      -- H15..H18 privilege matrix (truthful shape)
      r := r || format('%s|H15 raw primitives: anon+authenticated denied|', CASE WHEN NOT has_function_privilege('anon','public.om_auto_match(uuid)','EXECUTE')
            AND NOT has_function_privilege('authenticated','public.om_auto_match(uuid)','EXECUTE')
            AND NOT has_function_privilege('anon','public.wallet_topup_om_credit(uuid,uuid)','EXECUTE')
            AND NOT has_function_privilege('authenticated','public.wallet_topup_om_credit(uuid,uuid)','EXECUTE') THEN 'PASS' ELSE 'FAIL' END);
      r := r || format('%s|H16 participant wrappers: authenticated EXECUTE granted|', CASE WHEN has_function_privilege('authenticated','public.list_my_topup_requests(integer)','EXECUTE')
            AND has_function_privilege('authenticated','public.submit_customer_om_code(uuid,text)','EXECUTE')
            AND has_function_privilege('authenticated','public.driver_topup_history(integer)','EXECUTE') THEN 'PASS' ELSE 'FAIL' END);
      r := r || format('%s|H17 admin wrappers: authenticated EXECUTE + role guard in body|', CASE WHEN has_function_privilege('authenticated','public.admin_record_om_receipt(text,bigint,text,uuid,text)','EXECUTE')
            AND position('can_manage_wallet' in pg_get_functiondef('public.admin_record_om_receipt(text,bigint,text,uuid,text)'::regprocedure))>0
            AND position('can_manage_wallet' in pg_get_functiondef('public.om_pending_topups_for_event(uuid)'::regprocedure))>0 THEN 'PASS' ELSE 'FAIL' END);
      r := r || format('%s|H18 anon denied on every OM surface|', CASE WHEN NOT has_function_privilege('anon','public.list_my_topup_requests(integer)','EXECUTE')
            AND NOT has_function_privilege('anon','public.submit_customer_om_code(uuid,text)','EXECUTE')
            AND NOT has_function_privilege('anon','public.driver_topup_history(integer)','EXECUTE')
            AND NOT has_function_privilege('anon','public.admin_record_om_receipt(text,bigint,text,uuid,text)','EXECUTE')
            AND NOT has_function_privilege('anon','public.om_pending_topups_for_event(uuid)','EXECUTE') THEN 'PASS' ELSE 'FAIL' END);

      RAISE EXCEPTION 'QA_S9F_ROLLBACK';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM <> 'QA_S9F_ROLLBACK' THEN
        r := r || format('FAIL|X0 harness aborted|%s', SQLERRM);
      END IF;
    END;
  END;

  SELECT balance_gnf INTO v_master_after FROM public.wallets WHERE party_type='master' LIMIT 1;
  r := r || format('%s|H19 master wallet unchanged|before=%s after=%s', CASE WHEN v_master_before=v_master_after THEN 'PASS' ELSE 'FAIL' END, v_master_before, v_master_after);
  SELECT count(*) INTO ok_ct FROM public.topup_requests WHERE reference LIKE 'QA9F-%';
  r := r || format('%s|H20 no QA top-up rows remain|%s', CASE WHEN ok_ct=0 THEN 'PASS' ELSE 'FAIL' END, ok_ct);
  SELECT count(*) INTO ok_ct FROM public.payment_provider_events WHERE provider_transaction_id LIKE 'PPF%';
  r := r || format('%s|H21 no QA provider events remain|%s', CASE WHEN ok_ct=0 THEN 'PASS' ELSE 'FAIL' END, ok_ct);
  SELECT count(*) INTO ok_ct FROM public.ledger_journals WHERE source_module='om_topup';
  r := r || format('%s|H22 no QA ledger journals remain|%s', CASE WHEN ok_ct=0 THEN 'PASS' ELSE 'FAIL' END, ok_ct);

  FOREACH v_row IN ARRAY r LOOP
    INSERT INTO public._qa_s9_results (name, ok, detail)
    VALUES (split_part(v_row,'|',2), split_part(v_row,'|',1)='PASS', split_part(v_row,'|',3));
  END LOOP;

  SELECT count(*) FILTER (WHERE ok), count(*) FILTER (WHERE NOT ok) INTO ok_ct, fail_ct
    FROM public._qa_s9_results WHERE name LIKE 'H%';
  RETURN jsonb_build_object('total', ok_ct+fail_ct, 'pass', ok_ct, 'fail', fail_ct);
END;
$function$;

REVOKE ALL ON FUNCTION public._qa_s9f_run() FROM PUBLIC, anon, authenticated;

DO $$
DECLARE a jsonb; b jsonb;
BEGIN
  a := public._qa_s9_run();
  b := public._qa_s9f_run();
  RAISE NOTICE 'S9=% S9F=%', a, b;
END $$;