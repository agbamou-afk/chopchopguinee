CREATE OR REPLACE FUNCTION public._qa_s9b_run()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r text[] := ARRAY[]::text[];
  ok_ct int; fail_ct int; v_row text;
  v_master_before bigint; v_master_after bigint;
BEGIN
  SELECT balance_gnf INTO v_master_before FROM public.wallets WHERE party_type='master' LIMIT 1;
  BEGIN
    DECLARE
      v_c uuid; v_w_c uuid; b_c bigint;
      v_d uuid; v_w_d uuid; b_d bigint; v_w_dc uuid; b_dc bigint;
      v_acct uuid; v_acct2 uuid; v_dphone text; v_cphone text;
      v_t uuid; v_e uuid; v_res jsonb; v_n int;
      v_pfx text := 'PPB' || to_char(now(),'YYMMDDHH24MISS') || '.';
    BEGIN
      SELECT w.owner_user_id, w.id, w.balance_gnf INTO v_c, v_w_c, b_c
        FROM public.wallets w WHERE w.party_type='client' AND w.status='active' ORDER BY w.created_at LIMIT 1;
      SELECT w.owner_user_id, w.id, w.balance_gnf INTO v_d, v_w_d, b_d
        FROM public.wallets w WHERE w.party_type='driver' AND w.status='active' AND w.owner_user_id <> v_c
        ORDER BY w.created_at LIMIT 1;
      INSERT INTO public.wallets (owner_user_id, party_type) VALUES (v_d,'client')
        ON CONFLICT (owner_user_id, party_type) DO NOTHING;
      SELECT id, balance_gnf INTO v_w_dc, b_dc FROM public.wallets WHERE owner_user_id=v_d AND party_type='client';

      SELECT id INTO v_acct FROM public.payment_receiving_accounts
        WHERE provider='orange_money' AND is_active = true ORDER BY updated_at DESC LIMIT 1;
      INSERT INTO public.payment_receiving_accounts (provider,label,phone_e164,is_active)
        VALUES ('orange_money','QA S9B ALT','+224600000029', false) RETURNING id INTO v_acct2;

      UPDATE public.profiles SET phone = COALESCE(phone,'+224633333329') WHERE user_id = v_d;
      SELECT public._normalize_guinea_phone(phone) INTO v_dphone FROM public.profiles WHERE user_id=v_d;
      UPDATE public.profiles SET phone = COALESCE(phone,'+224644444429') WHERE user_id = v_c;
      SELECT public._normalize_guinea_phone(phone) INTO v_cphone FROM public.profiles WHERE user_id=v_c;

      -- B. DRIVER QUEUE with complete exact evidence
      INSERT INTO public.topup_requests
        (reference, client_user_id, amount_gnf, confirmation_code, provider, user_phone, status, expires_at,
         receiving_account_id, target_party_type, environment,
         customer_om_code_normalized, customer_om_code_raw, customer_om_code_submitted_at)
      VALUES ('QA9B-'||substr(md5(random()::text),1,8), v_d, 300000,'------','orange_money', v_dphone,
              'matched'::topup_status, now()+interval '2 hours', v_acct,'driver','production',
              public.normalize_om_code(v_pfx||'B1'), v_pfx||'B1', now())
      RETURNING id INTO v_t;
      INSERT INTO public.payment_provider_events
        (provider, provider_transaction_id, payer_phone, amount_gnf, status, processing_status,
         receiving_account_id, environment, is_sandbox)
      VALUES ('orange_money', v_pfx||'B1', v_dphone, 300000,'successful','received', v_acct,'production',false)
      RETURNING id INTO v_e;
      v_res := public.om_auto_match(v_e);
      r := r || format('%s|B1 driver request credited (complete evidence)|status=%s', CASE WHEN v_res->>'status'='credited' THEN 'PASS' ELSE 'FAIL' END, v_res->>'status');
      r := r || format('%s|B2 driver wallet +300000|%s', CASE WHEN (SELECT balance_gnf FROM public.wallets WHERE id=v_w_d)=b_d+300000 THEN 'PASS' ELSE 'FAIL' END, (SELECT balance_gnf FROM public.wallets WHERE id=v_w_d)-b_d);
      r := r || format('%s|B3 driver client wallet +0|%s', CASE WHEN (SELECT balance_gnf FROM public.wallets WHERE id=v_w_dc)=b_dc THEN 'PASS' ELSE 'FAIL' END, (SELECT balance_gnf FROM public.wallets WHERE id=v_w_dc)-b_dc);
      r := r || format('%s|B4 credit routed to driver liability account|', CASE WHEN EXISTS(SELECT 1 FROM public.ledger_postings p JOIN public.ledger_journals j ON j.id=p.journal_id WHERE j.journal_key='om_topup:'||v_e::text AND p.account_code='L_DRIVER_UNRESTRICTED' AND p.amount_gnf=-300000) THEN 'PASS' ELSE 'FAIL' END);
      SELECT count(*) INTO v_n FROM public.topup_requests WHERE client_user_id=v_d AND target_party_type='client' AND id=v_t;
      r := r || format('%s|B5 driver top-up never appears in client queue|', CASE WHEN v_n=0 THEN 'PASS' ELSE 'FAIL' END);
      r := r || format('%s|B6 driver eligibility reflects real driver wallet|', CASE WHEN ((public.driver_financial_eligibility('ride',0,v_d))->>'available_gnf')::bigint >= b_d+300000 - COALESCE((SELECT held_gnf FROM public.wallets WHERE id=v_w_d),0) THEN 'PASS' ELSE 'FAIL' END);

      -- C7/C8 receiving account mismatch with complete phone evidence
      INSERT INTO public.topup_requests
        (reference, client_user_id, amount_gnf, confirmation_code, provider, user_phone, status, expires_at,
         receiving_account_id, target_party_type, environment,
         customer_om_code_normalized, customer_om_code_raw, customer_om_code_submitted_at)
      VALUES ('QA9B-'||substr(md5(random()::text),1,8), v_c, 130000,'------','orange_money', v_cphone,
              'matched'::topup_status, now()+interval '2 hours', v_acct,'client','production',
              public.normalize_om_code(v_pfx||'C7'), v_pfx||'C7', now())
      RETURNING id INTO v_t;
      INSERT INTO public.payment_provider_events
        (provider, provider_transaction_id, payer_phone, amount_gnf, status, processing_status,
         receiving_account_id, environment, is_sandbox)
      VALUES ('orange_money', v_pfx||'C7', v_cphone, 130000,'successful','received', v_acct2,'production',false)
      RETURNING id INTO v_e;
      v_res := public.om_auto_match(v_e);
      r := r || format('%s|C7 receiving account mismatch => needs_review|%s', CASE WHEN v_res->>'reason'='receiving_account_mismatch' THEN 'PASS' ELSE 'FAIL' END, v_res->>'reason');
      r := r || format('%s|C7b zero credit on account mismatch|%s', CASE WHEN (SELECT balance_gnf FROM public.wallets WHERE id=v_w_c)=b_c THEN 'PASS' ELSE 'FAIL' END, (SELECT balance_gnf FROM public.wallets WHERE id=v_w_c)-b_c);
      BEGIN
        PERFORM public.wallet_topup_om_credit(v_e, v_t);
        r := r || 'FAIL|C8 forced credit on account mismatch denied|credited'::text;
      EXCEPTION WHEN OTHERS THEN
        r := r || format('%s|C8 forced credit on account mismatch denied|%s', CASE WHEN SQLERRM LIKE '%receiving_account_mismatch%' THEN 'PASS' ELSE 'FAIL' END, SQLERRM);
      END;

      RAISE EXCEPTION 'QA_S9B_ROLLBACK';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM <> 'QA_S9B_ROLLBACK' THEN
        r := r || format('FAIL|X0 harness aborted|%s', SQLERRM);
      END IF;
    END;
  END;

  SELECT balance_gnf INTO v_master_after FROM public.wallets WHERE party_type='master' LIMIT 1;
  r := r || format('%s|B7 master wallet unchanged|before=%s after=%s', CASE WHEN v_master_before=v_master_after THEN 'PASS' ELSE 'FAIL' END, v_master_before, v_master_after);
  SELECT count(*) INTO ok_ct FROM public.topup_requests WHERE reference LIKE 'QA9B-%';
  r := r || format('%s|B8 no QA rows remain|%s', CASE WHEN ok_ct=0 THEN 'PASS' ELSE 'FAIL' END, ok_ct);
  SELECT count(*) INTO ok_ct FROM public.payment_provider_events WHERE provider_transaction_id LIKE 'PPB%';
  r := r || format('%s|B9 no QA provider events remain|%s', CASE WHEN ok_ct=0 THEN 'PASS' ELSE 'FAIL' END, ok_ct);

  DELETE FROM public._qa_s9_results WHERE name IN
    ('B1 driver request credited','B2 driver wallet +300000','B4 credit routed to driver liability account',
     'B6 driver eligibility reflects real driver wallet','C7 receiving account mismatch => needs_review',
     'B3 driver client wallet +0','B5 driver top-up never appears in client queue',
     'C8 forced credit on account mismatch denied');
  FOREACH v_row IN ARRAY r LOOP
    INSERT INTO public._qa_s9_results (name, ok, detail)
    VALUES (split_part(v_row,'|',2), split_part(v_row,'|',1)='PASS', split_part(v_row,'|',3));
  END LOOP;
  SELECT count(*) FILTER (WHERE ok), count(*) FILTER (WHERE NOT ok) INTO ok_ct, fail_ct FROM public._qa_s9_results;
  RETURN jsonb_build_object('total', ok_ct+fail_ct, 'pass', ok_ct, 'fail', fail_ct);
END;
$function$;

REVOKE ALL ON FUNCTION public._qa_s9b_run() FROM PUBLIC, anon, authenticated;

DO $$ DECLARE a jsonb; BEGIN a := public._qa_s9b_run(); RAISE NOTICE '%', a; END $$;