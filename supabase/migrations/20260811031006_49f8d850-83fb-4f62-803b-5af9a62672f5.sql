CREATE OR REPLACE FUNCTION public._qa_s9_run()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  r text[] := ARRAY[]::text[];
  ok_ct int := 0; fail_ct int := 0;
  v_master_before bigint; v_master_after bigint;
  v_res jsonb;
BEGIN
  SELECT balance_gnf INTO v_master_before FROM public.wallets WHERE party_type='master' LIMIT 1;

  BEGIN
    DECLARE
      v_c1 uuid; v_c2 uuid; v_d uuid;
      v_w_c1 uuid; v_w_c2 uuid; v_w_d uuid; v_w_dc uuid;
      b_c1 bigint; b_c2 bigint; b_d bigint; b_dc bigint;
      v_acct uuid; v_acct2 uuid;
      v_t1 uuid; v_t2 uuid; v_t3 uuid; v_te uuid; v_tm uuid;
      v_e1 uuid; v_e2 uuid; v_e3 uuid; v_esbx uuid;
      v_ref1 text := 'PP260811.0300.A99001';
      v_refd text := 'PP260811.0301.B77002';
      v_n int; v_j uuid; v_sum bigint;
      v_status text; v_tx uuid; v_tx2 uuid;
      v_phone text;
    BEGIN
      SELECT w.owner_user_id, w.id, w.balance_gnf INTO v_c1, v_w_c1, b_c1
        FROM public.wallets w WHERE w.party_type='client' AND w.status='active'
        ORDER BY w.created_at LIMIT 1;
      SELECT w.owner_user_id, w.id, w.balance_gnf INTO v_c2, v_w_c2, b_c2
        FROM public.wallets w WHERE w.party_type='client' AND w.status='active' AND w.owner_user_id <> v_c1
        ORDER BY w.created_at LIMIT 1;
      SELECT w.owner_user_id, w.id, w.balance_gnf INTO v_d, v_w_d, b_d
        FROM public.wallets w WHERE w.party_type='driver' AND w.status='active'
        ORDER BY w.created_at LIMIT 1;

      INSERT INTO public.wallets (owner_user_id, party_type) VALUES (v_d,'client')
        ON CONFLICT (owner_user_id, party_type) DO NOTHING;
      SELECT id, balance_gnf INTO v_w_dc, b_dc FROM public.wallets
        WHERE owner_user_id = v_d AND party_type='client';

      SELECT id INTO v_acct FROM public.payment_receiving_accounts
        WHERE provider='orange_money' AND is_active = true ORDER BY updated_at DESC LIMIT 1;
      INSERT INTO public.payment_receiving_accounts (provider, label, phone_e164, is_active)
        VALUES ('orange_money','QA S9 ALT','+224600000009', false) RETURNING id INTO v_acct2;

      SELECT public._normalize_guinea_phone(phone) INTO v_phone FROM public.profiles WHERE user_id = v_c1;

      -- ============ A. CUSTOMER QUEUE ============
      INSERT INTO public.topup_requests
        (reference, client_user_id, amount_gnf, confirmation_code, provider, user_phone,
         status, expires_at, receiving_account_id, target_party_type, environment,
         customer_om_code_normalized, customer_om_code_raw, customer_om_code_submitted_at)
      VALUES ('QA9-'||substr(md5(random()::text),1,8), v_c1, 250000, '------','orange_money', v_phone,
              'matched'::topup_status, now()+interval '2 hours', v_acct, 'client','production',
              public.normalize_om_code(v_ref1), v_ref1, now())
      RETURNING id INTO v_t1;

      r := r || format('%s|A1 pending request does not move wallet balance|',
             CASE WHEN (SELECT balance_gnf FROM public.wallets WHERE id=v_w_c1) = b_c1 THEN 'PASS' ELSE 'FAIL' END);

      INSERT INTO public.payment_provider_events
        (provider, provider_transaction_id, payer_phone, amount_gnf, status, processing_status,
         receiving_account_id, environment, is_sandbox, raw_payload)
      VALUES ('orange_money', v_ref1, v_phone, 250000, 'successful','received', v_acct,'production',false,'{}'::jsonb)
      RETURNING id INTO v_e1;

      v_res := public.om_auto_match(v_e1);
      r := r || format('%s|A2 exact production event credits once|status=%s', CASE WHEN v_res->>'status'='credited' THEN 'PASS' ELSE 'FAIL' END, v_res->>'status');
      r := r || format('%s|A3 client wallet +250000|%s', CASE WHEN (SELECT balance_gnf FROM public.wallets WHERE id=v_w_c1) = b_c1+250000 THEN 'PASS' ELSE 'FAIL' END, (SELECT balance_gnf FROM public.wallets WHERE id=v_w_c1)-b_c1);
      r := r || format('%s|A4 driver wallet +0|%s', CASE WHEN (SELECT balance_gnf FROM public.wallets WHERE id=v_w_d) = b_d THEN 'PASS' ELSE 'FAIL' END, (SELECT balance_gnf FROM public.wallets WHERE id=v_w_d)-b_d);

      SELECT status::text, transaction_id INTO v_status, v_tx FROM public.topup_requests WHERE id=v_t1;
      r := r || format('%s|A5 request marked credited|%s', CASE WHEN v_status='credited' THEN 'PASS' ELSE 'FAIL' END, v_status);
      r := r || format('%s|A6 stage=credited|', CASE WHEN (SELECT public._topup_stage(t.status::text,t.expires_at,t.customer_om_code_submitted_at,t.transaction_id) FROM public.topup_requests t WHERE t.id=v_t1)='credited' THEN 'PASS' ELSE 'FAIL' END);
      r := r || format('%s|A7 matched_event_id linked|', CASE WHEN (SELECT matched_event_id FROM public.topup_requests WHERE id=v_t1)=v_e1 THEN 'PASS' ELSE 'FAIL' END);

      v_res := public.om_auto_match(v_e1);
      SELECT count(*) INTO v_n FROM public.wallet_transactions WHERE type='topup' AND metadata->>'event_id'=v_e1::text;
      r := r || format('%s|A8 replay auto-match inert|status=%s', CASE WHEN (v_res->>'status')='credited' AND (v_res->>'inert')='true' THEN 'PASS' ELSE 'FAIL' END, v_res->>'status');
      r := r || format('%s|A9 exactly one topup transaction for event|n=%s', CASE WHEN v_n=1 THEN 'PASS' ELSE 'FAIL' END, v_n);
      r := r || format('%s|A10 replay moved zero value|', CASE WHEN (SELECT balance_gnf FROM public.wallets WHERE id=v_w_c1) = b_c1+250000 THEN 'PASS' ELSE 'FAIL' END);

      SELECT id INTO v_tx2 FROM public.wallet_topup_om_credit(v_e1, v_t1);
      r := r || format('%s|A11 direct re-credit returns same transaction|', CASE WHEN v_tx2 = v_tx THEN 'PASS' ELSE 'FAIL' END);
      SELECT count(*) INTO v_n FROM public.wallet_transactions WHERE type='topup' AND metadata->>'event_id'=v_e1::text;
      r := r || format('%s|A12 still one transaction after direct re-credit|n=%s', CASE WHEN v_n=1 THEN 'PASS' ELSE 'FAIL' END, v_n);

      SELECT id INTO v_j FROM public.ledger_journals WHERE journal_key='om_topup:'||v_e1::text;
      r := r || format('%s|A13 ledger journal posted|', CASE WHEN v_j IS NOT NULL THEN 'PASS' ELSE 'FAIL' END);
      SELECT COALESCE(sum(amount_gnf),999) INTO v_sum FROM public.ledger_postings WHERE journal_id=v_j;
      r := r || format('%s|A14 journal zero-sum|sum=%s', CASE WHEN v_sum=0 THEN 'PASS' ELSE 'FAIL' END, v_sum);
      SELECT count(*) INTO v_n FROM public.ledger_postings WHERE journal_id=v_j AND account_code='L_CUSTOMER_CHOPPAY' AND amount_gnf=-250000;
      r := r || format('%s|A15 customer liability increased|', CASE WHEN v_n=1 THEN 'PASS' ELSE 'FAIL' END);
      SELECT count(*) INTO v_n FROM public.ledger_postings p JOIN public.ledger_accounts a ON a.code=p.account_code
        WHERE p.journal_id=v_j AND a.kind='revenue';
      r := r || format('%s|A16 top-up is not platform revenue|', CASE WHEN v_n=0 THEN 'PASS' ELSE 'FAIL' END);

      -- ============ D. GLOBAL REFERENCE UNIQUENESS ============
      BEGIN
        INSERT INTO public.payment_provider_events
          (provider, provider_transaction_id, amount_gnf, status, processing_status, environment)
        VALUES ('orange_money', v_ref1, 250000,'successful','received','production');
        r := r || 'FAIL|D1 duplicate provider reference rejected|inserted'::text;
      EXCEPTION WHEN unique_violation THEN
        r := r || 'PASS|D1 duplicate provider reference rejected|unique_violation'::text;
      END;

      INSERT INTO public.topup_requests
        (reference, client_user_id, amount_gnf, confirmation_code, provider,
         status, expires_at, receiving_account_id, target_party_type, environment,
         customer_om_code_normalized, customer_om_code_raw, customer_om_code_submitted_at)
      VALUES ('QA9-'||substr(md5(random()::text),1,8), v_c2, 250000, '------','orange_money',
              'matched'::topup_status, now()+interval '2 hours', v_acct, 'client','production',
              public.normalize_om_code(v_ref1), v_ref1, now())
      RETURNING id INTO v_t2;

      v_res := public.om_auto_match(v_e1);
      r := r || format('%s|D2 credited event cannot serve a second customer|status=%s', CASE WHEN (v_res->>'inert')='true' THEN 'PASS' ELSE 'FAIL' END, v_res->>'status');
      r := r || format('%s|D3 second customer wallet +0|%s', CASE WHEN (SELECT balance_gnf FROM public.wallets WHERE id=v_w_c2)=b_c2 THEN 'PASS' ELSE 'FAIL' END, (SELECT balance_gnf FROM public.wallets WHERE id=v_w_c2)-b_c2);

      BEGIN
        PERFORM public.wallet_topup_om_credit(v_e1, v_t2);
        r := r || 'FAIL|D4 direct credit of consumed event to 2nd customer denied|credited'::text;
      EXCEPTION WHEN OTHERS THEN
        r := r || format('PASS|D4 direct credit of consumed event to 2nd customer denied|%s', SQLERRM);
      END;
      DELETE FROM public.topup_requests WHERE id = v_t2;

      -- ============ B. DRIVER QUEUE ============
      INSERT INTO public.topup_requests
        (reference, client_user_id, amount_gnf, confirmation_code, provider,
         status, expires_at, receiving_account_id, target_party_type, environment,
         customer_om_code_normalized, customer_om_code_raw, customer_om_code_submitted_at)
      VALUES ('QA9-'||substr(md5(random()::text),1,8), v_d, 300000, '------','orange_money',
              'matched'::topup_status, now()+interval '2 hours', v_acct, 'driver','production',
              public.normalize_om_code(v_refd), v_refd, now())
      RETURNING id INTO v_t3;

      INSERT INTO public.payment_provider_events
        (provider, provider_transaction_id, amount_gnf, status, processing_status,
         receiving_account_id, environment, is_sandbox)
      VALUES ('orange_money', v_refd, 300000,'successful','received', v_acct,'production',false)
      RETURNING id INTO v_e2;

      v_res := public.om_auto_match(v_e2);
      r := r || format('%s|B1 driver request credited|status=%s', CASE WHEN v_res->>'status'='credited' THEN 'PASS' ELSE 'FAIL' END, v_res->>'status');
      r := r || format('%s|B2 driver wallet +300000|%s', CASE WHEN (SELECT balance_gnf FROM public.wallets WHERE id=v_w_d)=b_d+300000 THEN 'PASS' ELSE 'FAIL' END, (SELECT balance_gnf FROM public.wallets WHERE id=v_w_d)-b_d);
      r := r || format('%s|B3 driver client wallet +0|%s', CASE WHEN (SELECT balance_gnf FROM public.wallets WHERE id=v_w_dc)=b_dc THEN 'PASS' ELSE 'FAIL' END, (SELECT balance_gnf FROM public.wallets WHERE id=v_w_dc)-b_dc);
      r := r || format('%s|B4 credit routed to driver liability account|', CASE WHEN EXISTS(SELECT 1 FROM public.ledger_postings p JOIN public.ledger_journals j ON j.id=p.journal_id WHERE j.journal_key='om_topup:'||v_e2::text AND p.account_code='L_DRIVER_UNRESTRICTED' AND p.amount_gnf=-300000) THEN 'PASS' ELSE 'FAIL' END);
      SELECT count(*) INTO v_n FROM public.topup_requests WHERE client_user_id=v_d AND target_party_type='client' AND id=v_t3;
      r := r || format('%s|B5 driver top-up never appears in client queue|', CASE WHEN v_n=0 THEN 'PASS' ELSE 'FAIL' END);
      r := r || format('%s|B6 driver eligibility reflects real driver wallet|', CASE WHEN ((public.driver_financial_eligibility('ride',0,v_d))->>'available_gnf')::bigint >= b_d+300000 - COALESCE((SELECT held_gnf FROM public.wallets WHERE id=v_w_d),0) THEN 'PASS' ELSE 'FAIL' END);

      -- ============ C. MISMATCHES ============
      INSERT INTO public.topup_requests
        (reference, client_user_id, amount_gnf, confirmation_code, provider, status, expires_at,
         receiving_account_id, target_party_type, environment, customer_om_code_normalized, customer_om_code_submitted_at)
      VALUES ('QA9-'||substr(md5(random()::text),1,8), v_c1, 111000,'------','orange_money','matched'::topup_status, now()+interval '2 hours',
              v_acct,'client','production', public.normalize_om_code('PP260811.0302.C1'), now())
      RETURNING id INTO v_tm;
      INSERT INTO public.payment_provider_events
        (provider, provider_transaction_id, amount_gnf, status, processing_status, receiving_account_id, environment)
      VALUES ('orange_money','PP260811.0302.C1', 999000,'successful','received', v_acct,'production') RETURNING id INTO v_e3;
      v_res := public.om_auto_match(v_e3);
      r := r || format('%s|C1 amount mismatch => needs_review|%s', CASE WHEN v_res->>'reason'='amount_mismatch' THEN 'PASS' ELSE 'FAIL' END, v_res->>'reason');
      r := r || format('%s|C2 amount mismatch credits nothing|', CASE WHEN (SELECT balance_gnf FROM public.wallets WHERE id=v_w_c1)=b_c1+250000 THEN 'PASS' ELSE 'FAIL' END);
      r := r || format('%s|C3 machine reason stored|%s', CASE WHEN (SELECT review_reason FROM public.topup_requests WHERE id=v_tm)='amount_mismatch' THEN 'PASS' ELSE 'FAIL' END, (SELECT review_reason FROM public.topup_requests WHERE id=v_tm));
      DELETE FROM public.payment_provider_events WHERE id=v_e3; DELETE FROM public.topup_requests WHERE id=v_tm;

      INSERT INTO public.topup_requests
        (reference, client_user_id, amount_gnf, confirmation_code, provider, user_phone, status, expires_at,
         receiving_account_id, target_party_type, environment, customer_om_code_normalized, customer_om_code_submitted_at)
      VALUES ('QA9-'||substr(md5(random()::text),1,8), v_c1, 120000,'------','orange_money','+224610000001','matched'::topup_status, now()+interval '2 hours',
              v_acct,'client','production', public.normalize_om_code('PP260811.0303.C2'), now())
      RETURNING id INTO v_tm;
      INSERT INTO public.payment_provider_events
        (provider, provider_transaction_id, payer_phone, amount_gnf, status, processing_status, receiving_account_id, environment)
      VALUES ('orange_money','PP260811.0303.C2','+224620000002', 120000,'successful','received', v_acct,'production') RETURNING id INTO v_e3;
      v_res := public.om_auto_match(v_e3);
      r := r || format('%s|C4 payer phone mismatch => needs_review|%s', CASE WHEN v_res->>'reason'='payer_phone_mismatch' THEN 'PASS' ELSE 'FAIL' END, v_res->>'reason');
      r := r || format('%s|C5 phone mismatch credits nothing|', CASE WHEN (SELECT balance_gnf FROM public.wallets WHERE id=v_w_c1)=b_c1+250000 THEN 'PASS' ELSE 'FAIL' END);
      BEGIN
        PERFORM public.wallet_topup_om_credit(v_e3, v_tm);
        r := r || 'FAIL|C6 forced credit on phone mismatch denied|credited'::text;
      EXCEPTION WHEN OTHERS THEN
        r := r || format('PASS|C6 forced credit on phone mismatch denied|%s', SQLERRM);
      END;
      DELETE FROM public.payment_provider_events WHERE id=v_e3; DELETE FROM public.topup_requests WHERE id=v_tm;

      INSERT INTO public.topup_requests
        (reference, client_user_id, amount_gnf, confirmation_code, provider, status, expires_at,
         receiving_account_id, target_party_type, environment, customer_om_code_normalized, customer_om_code_submitted_at)
      VALUES ('QA9-'||substr(md5(random()::text),1,8), v_c1, 130000,'------','orange_money','matched'::topup_status, now()+interval '2 hours',
              v_acct,'client','production', public.normalize_om_code('PP260811.0304.C3'), now())
      RETURNING id INTO v_tm;
      INSERT INTO public.payment_provider_events
        (provider, provider_transaction_id, amount_gnf, status, processing_status, receiving_account_id, environment)
      VALUES ('orange_money','PP260811.0304.C3', 130000,'successful','received', v_acct2,'production') RETURNING id INTO v_e3;
      v_res := public.om_auto_match(v_e3);
      r := r || format('%s|C7 receiving account mismatch => needs_review|%s', CASE WHEN v_res->>'reason'='receiving_account_mismatch' THEN 'PASS' ELSE 'FAIL' END, v_res->>'reason');
      BEGIN
        PERFORM public.wallet_topup_om_credit(v_e3, v_tm);
        r := r || 'FAIL|C8 forced credit on account mismatch denied|credited'::text;
      EXCEPTION WHEN OTHERS THEN
        r := r || format('PASS|C8 forced credit on account mismatch denied|%s', SQLERRM);
      END;
      DELETE FROM public.payment_provider_events WHERE id=v_e3; DELETE FROM public.topup_requests WHERE id=v_tm;

      INSERT INTO public.topup_requests
        (reference, client_user_id, amount_gnf, confirmation_code, provider, status, expires_at,
         receiving_account_id, target_party_type, environment, customer_om_code_normalized, customer_om_code_submitted_at)
      VALUES ('QA9-'||substr(md5(random()::text),1,8), v_c1, 140000,'------','orange_money','matched'::topup_status, now()+interval '2 hours',
              v_acct,'client','production', public.normalize_om_code('PP260811.0305.C4'), now()) RETURNING id INTO v_tm;
      INSERT INTO public.topup_requests
        (reference, client_user_id, amount_gnf, confirmation_code, provider, status, expires_at,
         receiving_account_id, target_party_type, environment, customer_om_code_normalized, customer_om_code_submitted_at)
      VALUES ('QA9-'||substr(md5(random()::text),1,8), v_c2, 140000,'------','orange_money','matched'::topup_status, now()+interval '2 hours',
              v_acct,'client','production', public.normalize_om_code('PP260811.0305.C4'), now()) RETURNING id INTO v_t2;
      INSERT INTO public.payment_provider_events
        (provider, provider_transaction_id, amount_gnf, status, processing_status, receiving_account_id, environment)
      VALUES ('orange_money','PP260811.0305.C4', 140000,'successful','received', v_acct,'production') RETURNING id INTO v_e3;
      v_res := public.om_auto_match(v_e3);
      r := r || format('%s|C9 multiple candidates => no credit|%s', CASE WHEN v_res->>'reason'='multiple_candidates' THEN 'PASS' ELSE 'FAIL' END, v_res->>'reason');
      r := r || format('%s|C10 multiple candidates move zero value|', CASE WHEN (SELECT balance_gnf FROM public.wallets WHERE id=v_w_c2)=b_c2 THEN 'PASS' ELSE 'FAIL' END);
      DELETE FROM public.payment_provider_events WHERE id=v_e3;
      DELETE FROM public.topup_requests WHERE id IN (v_tm, v_t2);

      INSERT INTO public.topup_requests
        (reference, client_user_id, amount_gnf, confirmation_code, provider, status, expires_at,
         receiving_account_id, target_party_type, environment, customer_om_code_normalized, customer_om_code_submitted_at)
      VALUES ('QA9-'||substr(md5(random()::text),1,8), v_c1, 150000,'------','orange_money','matched'::topup_status, now()-interval '1 hour',
              v_acct,'client','production', public.normalize_om_code('PP260811.0306.C5'), now()) RETURNING id INTO v_te;
      INSERT INTO public.payment_provider_events
        (provider, provider_transaction_id, amount_gnf, status, processing_status, receiving_account_id, environment)
      VALUES ('orange_money','PP260811.0306.C5', 150000,'successful','received', v_acct,'production') RETURNING id INTO v_e3;
      v_res := public.om_auto_match(v_e3);
      r := r || format('%s|C11 expired request not matched|%s', CASE WHEN v_res->>'status'='awaiting_customer_code' THEN 'PASS' ELSE 'FAIL' END, v_res->>'status');
      BEGIN
        PERFORM public.wallet_topup_om_credit(v_e3, v_te);
        r := r || 'FAIL|C12 forced credit on expired request denied|credited'::text;
      EXCEPTION WHEN OTHERS THEN
        r := r || format('PASS|C12 forced credit on expired request denied|%s', SQLERRM);
      END;
      r := r || format('%s|C13 expired stage honest|%s', CASE WHEN (SELECT public._topup_stage(t.status::text,t.expires_at,t.customer_om_code_submitted_at,t.transaction_id) FROM public.topup_requests t WHERE t.id=v_te)='expired' THEN 'PASS' ELSE 'FAIL' END, 'expired');
      DELETE FROM public.payment_provider_events WHERE id=v_e3; DELETE FROM public.topup_requests WHERE id=v_te;

      INSERT INTO public.payment_provider_events
        (provider, provider_transaction_id, amount_gnf, status, processing_status, receiving_account_id, environment)
      VALUES ('orange_money','PP260811.0307.C6', 160000,'successful','received', v_acct,'production') RETURNING id INTO v_e3;
      v_res := public.om_auto_match(v_e3);
      r := r || format('%s|C14 unmatched receipt parks as awaiting_customer_code|%s', CASE WHEN v_res->>'status'='awaiting_customer_code' THEN 'PASS' ELSE 'FAIL' END, v_res->>'status');
      r := r || format('%s|C15 unmatched receipt never rejected outright|%s', CASE WHEN (SELECT processing_status FROM public.payment_provider_events WHERE id=v_e3)='received' THEN 'PASS' ELSE 'FAIL' END, (SELECT processing_status FROM public.payment_provider_events WHERE id=v_e3));
      DELETE FROM public.payment_provider_events WHERE id=v_e3;

      INSERT INTO public.payment_provider_events
        (provider, provider_transaction_id, amount_gnf, status, processing_status, receiving_account_id, environment)
      VALUES ('orange_money','PP260811.0308.C7', 170000,'failed','received', v_acct,'production') RETURNING id INTO v_e3;
      v_res := public.om_auto_match(v_e3);
      r := r || format('%s|C16 unsuccessful provider status rejected|%s', CASE WHEN v_res->>'status'='rejected' THEN 'PASS' ELSE 'FAIL' END, v_res->>'status');
      DELETE FROM public.payment_provider_events WHERE id=v_e3;

      -- ============ E. SANDBOX ISOLATION ============
      INSERT INTO public.topup_requests
        (reference, client_user_id, amount_gnf, confirmation_code, provider, status, expires_at,
         receiving_account_id, target_party_type, environment, customer_om_code_normalized, customer_om_code_submitted_at)
      VALUES ('QA9-'||substr(md5(random()::text),1,8), v_c1, 180000,'------','orange_money','matched'::topup_status, now()+interval '2 hours',
              v_acct,'client','production', public.normalize_om_code('OM-SBX-QA9001'), now()) RETURNING id INTO v_tm;
      INSERT INTO public.payment_provider_events
        (provider, provider_transaction_id, amount_gnf, status, processing_status, receiving_account_id,
         environment, is_sandbox)
      VALUES ('orange_money','OM-SBX-QA9001', 180000,'successful','received', v_acct,'sandbox', true) RETURNING id INTO v_esbx;
      v_res := public.om_auto_match(v_esbx);
      r := r || format('%s|E1 sandbox event cannot match production request|%s', CASE WHEN v_res->>'status'='awaiting_customer_code' THEN 'PASS' ELSE 'FAIL' END, v_res->>'status');
      r := r || format('%s|E2 sandbox event credits nothing|', CASE WHEN (SELECT balance_gnf FROM public.wallets WHERE id=v_w_c1)=b_c1+250000 THEN 'PASS' ELSE 'FAIL' END);
      BEGIN
        PERFORM public.wallet_topup_om_credit(v_esbx, v_tm);
        r := r || 'FAIL|E3 forced sandbox->production credit denied|credited'::text;
      EXCEPTION WHEN OTHERS THEN
        r := r || format('PASS|E3 forced sandbox->production credit denied|%s', SQLERRM);
      END;

      UPDATE public.topup_requests SET environment='sandbox',
             customer_om_code_normalized = public.normalize_om_code('PP260811.0309.E4') WHERE id=v_tm;
      INSERT INTO public.payment_provider_events
        (provider, provider_transaction_id, amount_gnf, status, processing_status, receiving_account_id, environment, is_sandbox)
      VALUES ('orange_money','PP260811.0309.E4', 180000,'successful','received', v_acct,'production', false) RETURNING id INTO v_e3;
      v_res := public.om_auto_match(v_e3);
      r := r || format('%s|E4 production event cannot consume sandbox request|%s', CASE WHEN v_res->>'status'='awaiting_customer_code' THEN 'PASS' ELSE 'FAIL' END, v_res->>'status');
      BEGIN
        PERFORM public.wallet_topup_om_credit(v_e3, v_tm);
        r := r || 'FAIL|E5 forced production->sandbox credit denied|credited'::text;
      EXCEPTION WHEN OTHERS THEN
        r := r || format('PASS|E5 forced production->sandbox credit denied|%s', SQLERRM);
      END;
      r := r || format('%s|E6 provider reference uniqueness is global|', CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='payment_provider_events_provider_tx_uidx') THEN 'PASS' ELSE 'FAIL' END);
      DELETE FROM public.payment_provider_events WHERE id IN (v_e3, v_esbx);
      DELETE FROM public.topup_requests WHERE id=v_tm;

      -- ============ F. PRIVILEGES ============
      r := r || format('%s|F1 anon cannot execute om_auto_match|', CASE WHEN NOT has_function_privilege('anon','public.om_auto_match(uuid)','EXECUTE') THEN 'PASS' ELSE 'FAIL' END);
      r := r || format('%s|F2 authenticated cannot execute om_auto_match|', CASE WHEN NOT has_function_privilege('authenticated','public.om_auto_match(uuid)','EXECUTE') THEN 'PASS' ELSE 'FAIL' END);
      r := r || format('%s|F3 authenticated cannot execute wallet_topup_om_credit|', CASE WHEN NOT has_function_privilege('authenticated','public.wallet_topup_om_credit(uuid,uuid)','EXECUTE') THEN 'PASS' ELSE 'FAIL' END);
      r := r || format('%s|F4 anon cannot execute wallet_topup_om_credit|', CASE WHEN NOT has_function_privilege('anon','public.wallet_topup_om_credit(uuid,uuid)','EXECUTE') THEN 'PASS' ELSE 'FAIL' END);
      r := r || format('%s|F5 anon cannot list own topups|', CASE WHEN NOT has_function_privilege('anon','public.list_my_topup_requests(integer)','EXECUTE') THEN 'PASS' ELSE 'FAIL' END);
      r := r || format('%s|F6 anon cannot read driver topup history|', CASE WHEN NOT has_function_privilege('anon','public.driver_topup_history(integer)','EXECUTE') THEN 'PASS' ELSE 'FAIL' END);
      r := r || format('%s|F7 anon cannot submit OM code|', CASE WHEN NOT has_function_privilege('anon','public.submit_customer_om_code(uuid,text)','EXECUTE') THEN 'PASS' ELSE 'FAIL' END);
      r := r || format('%s|F8 anon cannot read finance candidate queue|', CASE WHEN NOT has_function_privilege('anon','public.om_pending_topups_for_event(uuid)','EXECUTE') THEN 'PASS' ELSE 'FAIL' END);
      r := r || format('%s|F9 anon cannot record OM receipts|', CASE WHEN NOT has_function_privilege('anon','public.admin_record_om_receipt(text,bigint,text,uuid,text)','EXECUTE') THEN 'PASS' ELSE 'FAIL' END);
      r := r || format('%s|F10 anon cannot retry OM credit|', CASE WHEN NOT has_function_privilege('anon','public.admin_retry_om_credit(uuid)','EXECUTE') THEN 'PASS' ELSE 'FAIL' END);
      r := r || format('%s|F11 anon cannot create OM top-up|', CASE WHEN NOT has_function_privilege('anon','public.wallet_topup_om_create(bigint,uuid)','EXECUTE') THEN 'PASS' ELSE 'FAIL' END);
      r := r || format('%s|F12 topup_requests has no anon RLS policy|', CASE WHEN NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename='topup_requests' AND 'anon' = ANY(roles)) THEN 'PASS' ELSE 'FAIL' END);

      -- ============ G. INVARIANTS ============
      r := r || format('%s|G1 one-credit-per-event index present|', CASE WHEN EXISTS(SELECT 1 FROM pg_indexes WHERE indexname='wallet_transactions_om_event_uidx') THEN 'PASS' ELSE 'FAIL' END);
      r := r || format('%s|G2 one-credited-topup-per-event index present|', CASE WHEN EXISTS(SELECT 1 FROM pg_indexes WHERE indexname='ppe_credited_topup_uidx') THEN 'PASS' ELSE 'FAIL' END);
      r := r || format('%s|G3 one-credit-per-provider-reference index present|', CASE WHEN EXISTS(SELECT 1 FROM pg_indexes WHERE indexname='topup_requests_credited_provider_tx_uidx') THEN 'PASS' ELSE 'FAIL' END);
      SELECT count(*) INTO v_n FROM public.ledger_journals j
        WHERE j.journal_key IN ('om_topup:'||v_e1::text,'om_topup:'||v_e2::text)
          AND (SELECT COALESCE(sum(p.amount_gnf),1) FROM public.ledger_postings p WHERE p.journal_id=j.id) <> 0;
      r := r || format('%s|G4 all top-up journals zero-sum|%s', CASE WHEN v_n=0 THEN 'PASS' ELSE 'FAIL' END, v_n);
      r := r || format('%s|G5 no fuzzy payload matching left in matcher|', CASE WHEN position('ILIKE' in pg_get_functiondef('public.om_auto_match(uuid)'::regprocedure)) = 0 THEN 'PASS' ELSE 'FAIL' END);
      r := r || format('%s|G6 matcher requires provider reference|', CASE WHEN position('missing_provider_reference' in pg_get_functiondef('public.om_auto_match(uuid)'::regprocedure)) > 0 THEN 'PASS' ELSE 'FAIL' END);
      r := r || format('%s|G7 om_topup_enabled still ON|', CASE WHEN (SELECT enabled FROM public.feature_flags WHERE key='om_topup_enabled') THEN 'PASS' ELSE 'FAIL' END);
      r := r || format('%s|G8 gated rails still OFF|', CASE WHEN NOT EXISTS (SELECT 1 FROM public.feature_flags WHERE enabled AND key IN ('chop_pay_checkout_enabled','merchant_om_settlement_enabled','driver_cashout_enabled','chop_pay_p2p_enabled','om_direct_checkout_enabled')) THEN 'PASS' ELSE 'FAIL' END);

      RAISE EXCEPTION 'QA_S9_ROLLBACK';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM <> 'QA_S9_ROLLBACK' THEN
        r := r || format('FAIL|X0 harness aborted|%s', SQLERRM);
      END IF;
    END;
  END;

  SELECT balance_gnf INTO v_master_after FROM public.wallets WHERE party_type='master' LIMIT 1;
  r := r || format('%s|G9 master wallet returned to baseline naturally|before=%s after=%s',
        CASE WHEN v_master_before = v_master_after THEN 'PASS' ELSE 'FAIL' END, v_master_before, v_master_after);
  SELECT count(*) INTO ok_ct FROM public.topup_requests WHERE reference LIKE 'QA9-%';
  r := r || format('%s|G10 no QA top-up rows remain|%s', CASE WHEN ok_ct=0 THEN 'PASS' ELSE 'FAIL' END, ok_ct);
  SELECT count(*) INTO ok_ct FROM public.payment_provider_events WHERE provider_transaction_id LIKE 'PP260811.%' OR provider_transaction_id='OM-SBX-QA9001';
  r := r || format('%s|G11 no QA provider events remain|%s', CASE WHEN ok_ct=0 THEN 'PASS' ELSE 'FAIL' END, ok_ct);
  SELECT count(*) INTO ok_ct FROM public.ledger_journals WHERE source_module='om_topup';
  r := r || format('%s|G12 no QA ledger journals remain|%s', CASE WHEN ok_ct=0 THEN 'PASS' ELSE 'FAIL' END, ok_ct);

  DELETE FROM public._qa_s9_results;
  FOR v_res IN SELECT to_jsonb(x) FROM unnest(r) AS x LOOP
    INSERT INTO public._qa_s9_results (name, ok, detail)
    VALUES (split_part(trim(both '"' from v_res::text),'|',2),
            split_part(trim(both '"' from v_res::text),'|',1) = 'PASS',
            split_part(trim(both '"' from v_res::text),'|',3));
  END LOOP;
  SELECT count(*) FILTER (WHERE ok), count(*) FILTER (WHERE NOT ok) INTO ok_ct, fail_ct FROM public._qa_s9_results;

  RETURN jsonb_build_object('total', ok_ct+fail_ct, 'pass', ok_ct, 'fail', fail_ct,
    'failures', (SELECT COALESCE(jsonb_agg(jsonb_build_object('name',name,'detail',detail)),'[]'::jsonb)
                   FROM public._qa_s9_results WHERE NOT ok));
END;
$fn$;