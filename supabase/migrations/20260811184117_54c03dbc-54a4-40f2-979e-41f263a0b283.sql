CREATE OR REPLACE FUNCTION public._qa_s13_om_rolecall(p_role text, p_uid uuid, p_sql text, p_a1 text, p_a2 text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_err text := 'NO_ERROR';
BEGIN
  PERFORM set_config('request.jwt.claims',
    CASE WHEN p_uid IS NULL THEN '' ELSE public._as_user_claims(p_uid) END, true);
  EXECUTE format('SET LOCAL ROLE %I', p_role);
  BEGIN
    EXECUTE p_sql USING p_a1, p_a2;
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM;
  END;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims','',true);
  RETURN v_err;
END $fn$;

CREATE OR REPLACE FUNCTION public._qa_s13_om_case(
  p_user uuid, p_god uuid, p_party text, p_amount bigint, p_acct_req uuid,
  p_code text, p_ev_amount bigint, p_ev_phone text, p_ev_acct uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_tr public.topup_requests; v_b0 bigint; v_b1 bigint;
  v_sub jsonb; v_res jsonb; v_err text := 'NO_ERROR';
  v_st text; v_rr text; v_evid uuid; v_evst text;
BEGIN
  SELECT balance_gnf INTO v_b0 FROM public.wallets
   WHERE owner_user_id = p_user AND party_type = p_party::party_type;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(p_user), true);
  IF p_party = 'driver' THEN
    v_tr := public.driver_wallet_topup_om_create(p_amount, p_acct_req);
  ELSE
    v_tr := public.wallet_topup_om_create(p_amount, p_acct_req);
  END IF;
  v_sub := public.submit_customer_om_code(v_tr.id, p_code);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(p_god), true);
  BEGIN
    v_res := public.admin_record_om_receipt(p_code, p_ev_amount, p_ev_phone, p_ev_acct, 'qa s13 part5');
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; v_res := '{}'::jsonb;
  END;
  PERFORM set_config('request.jwt.claims','',true);
  SELECT balance_gnf INTO v_b1 FROM public.wallets
   WHERE owner_user_id = p_user AND party_type = p_party::party_type;
  SELECT status::text, review_reason INTO v_st, v_rr FROM public.topup_requests WHERE id = v_tr.id;
  v_evid := NULLIF(v_res->>'event_id','')::uuid;
  SELECT processing_status INTO v_evst FROM public.payment_provider_events WHERE id = v_evid;
  RETURN jsonb_build_object(
    'topup_id', v_tr.id, 'submit', v_sub, 'record', v_res, 'record_error', v_err,
    'delta', COALESCE(v_b1,0) - COALESCE(v_b0,0),
    'status', v_st, 'review_reason', v_rr,
    'event_id', v_evid, 'event_status', v_evst,
    'match_status', v_res->'match'->>'status', 'match_reason', v_res->'match'->>'reason');
END $fn$;

CREATE OR REPLACE FUNCTION public._qa_s13_om_forced(
  p_user uuid, p_amount bigint, p_acct_ok uuid, p_acct_other uuid,
  p_code text, p_mutate text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_tr public.topup_requests; v_evid uuid; v_b0 bigint; v_b1 bigint; v_err text;
  v_amt bigint; v_phone text; v_acct uuid; v_sand boolean := false;
  v_env text := 'production'; v_norm text;
BEGIN
  PERFORM set_config('request.jwt.claims', public._as_user_claims(p_user), true);
  v_tr := public.wallet_topup_om_create(p_amount, p_acct_ok);
  PERFORM public.submit_customer_om_code(v_tr.id, p_code);
  PERFORM set_config('request.jwt.claims','',true);
  SELECT * INTO v_tr FROM public.topup_requests WHERE id = v_tr.id;

  v_amt := p_amount; v_phone := v_tr.user_phone; v_acct := p_acct_ok;
  v_norm := public.normalize_om_code(p_code);
  IF p_mutate = 'amount'          THEN v_amt := p_amount + 1000; END IF;
  IF p_mutate = 'phone'           THEN v_phone := '+224620999999'; END IF;
  IF p_mutate = 'phone_missing'   THEN v_phone := NULL; END IF;
  IF p_mutate = 'account'         THEN v_acct := p_acct_other; END IF;
  IF p_mutate = 'account_missing' THEN v_acct := NULL; END IF;
  IF p_mutate = 'reference'       THEN v_norm := public.normalize_om_code(p_code || 'X9'); END IF;
  IF p_mutate = 'environment'     THEN v_sand := true; v_env := 'sandbox'; END IF;
  IF p_mutate = 'target' THEN
    UPDATE public.topup_requests SET target_party_type = 'driver' WHERE id = v_tr.id;
  END IF;

  INSERT INTO public.payment_provider_events(
    provider, event_type, provider_transaction_id, payer_phone, amount_gnf,
    status, processing_status, raw_payload, receiving_account_id,
    om_code_normalized, is_sandbox, environment, matched_topup_request_id, matched_user_id)
  VALUES ('orange_money','payment.received',
    upper(p_code) || '-' || upper(p_mutate), v_phone, v_amt,
    'successful','matched','{"source":"qa_s13_forced"}'::jsonb, v_acct,
    v_norm, v_sand, v_env, v_tr.id, p_user)
  RETURNING id INTO v_evid;

  UPDATE public.topup_requests
     SET status = 'matched'::topup_status, matched_event_id = v_evid WHERE id = v_tr.id;

  SELECT COALESCE(sum(balance_gnf),0) INTO v_b0 FROM public.wallets WHERE owner_user_id = p_user;
  BEGIN
    PERFORM public.wallet_topup_om_credit(v_evid, v_tr.id); v_err := 'NO_ERROR';
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM;
  END;
  SELECT COALESCE(sum(balance_gnf),0) INTO v_b1 FROM public.wallets WHERE owner_user_id = p_user;

  RETURN jsonb_build_object('error', v_err, 'delta', v_b1 - v_b0,
    'topup_id', v_tr.id, 'event_id', v_evid,
    'topup_status', (SELECT status::text FROM public.topup_requests WHERE id = v_tr.id));
END $fn$;

REVOKE ALL ON FUNCTION public._qa_s13_om_rolecall(text,uuid,text,text,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._qa_s13_om_case(uuid,uuid,text,bigint,uuid,text,bigint,text,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._qa_s13_om_forced(uuid,bigint,uuid,uuid,text,text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._qa_s13_run5()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  r jsonb := '[]'::jsonb;
  v_master0 bigint; v_master1 bigint; v_flags0 jsonb; v_flags1 jsonb;
  v_t0 timestamptz;
  v_cust uuid; v_cust2 uuid; v_cust3 uuid; v_drv uuid; v_drv2 uuid; v_god uuid; v_plain uuid;
  v_sfx text; v_acct uuid; v_acct2 uuid;
  v_err text; v_n bigint; v_res jsonb; v_c jsonb; v_f jsonb;
  v_tr public.topup_requests; v_tr2 public.topup_requests;
  v_topA uuid; v_topB uuid; v_topAdmFirst uuid;
  v_amtA bigint := 250000; v_amtB bigint := 300000;
  v_codeA text; v_codeB text; v_code text;
  v_bal0 bigint; v_bal1 bigint; v_evid uuid; v_ev2 uuid;
  v_lock bigint; v_txid uuid; v_credited bigint := 0;
  v_mbal0 bigint; v_mbal1 bigint;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;

  BEGIN
    v_t0 := clock_timestamp();
    v_sfx := upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
    v_cust  := gen_random_uuid(); v_cust2 := gen_random_uuid(); v_cust3 := gen_random_uuid();
    v_drv   := gen_random_uuid(); v_drv2  := gen_random_uuid();
    v_god   := gen_random_uuid(); v_plain := gen_random_uuid();

    PERFORM public._qa_s13_user(v_cust ,'omc1'); PERFORM public._qa_s13_user(v_cust2,'omc2');
    PERFORM public._qa_s13_user(v_cust3,'omc3'); PERFORM public._qa_s13_user(v_god  ,'omg');
    PERFORM public._qa_s13_user(v_plain,'omp');
    PERFORM public._qa_s13_driver(v_drv ,'omd1', 0);
    PERFORM public._qa_s13_driver(v_drv2,'omd2', 0);

    INSERT INTO public.profiles(user_id, phone, full_name) VALUES
      (v_cust ,'+224620000501','QA OM Client 1'),
      (v_cust2,'+224620000502','QA OM Client 2'),
      (v_cust3,'+224620000503','QA OM Client 3'),
      (v_drv  ,'+224620000504','QA OM Driver 1'),
      (v_drv2 ,'+224620000505','QA OM Driver 2'),
      (v_plain,'+224620000506','QA OM Plain'),
      (v_god  ,'+224620000507','QA OM God')
    ON CONFLICT (user_id) DO UPDATE SET phone = EXCLUDED.phone;

    PERFORM public._qa_s13_wallet(v_cust ,'client',0,0);
    PERFORM public._qa_s13_wallet(v_cust2,'client',0,0);
    PERFORM public._qa_s13_wallet(v_cust3,'client',0,0);
    PERFORM public._qa_s13_wallet(v_plain,'client',0,0);
    PERFORM public._qa_s13_admin(v_god);

    SELECT id INTO v_acct FROM public.payment_receiving_accounts
     WHERE provider='orange_money' AND is_active = true ORDER BY updated_at DESC LIMIT 1;
    INSERT INTO public.payment_receiving_accounts(provider,label,phone_e164,is_active)
    VALUES ('orange_money','QA S13 alt account','+224622999'||substr(v_sfx,1,3), true)
    RETURNING id INTO v_acct2;

    r := r || public._qa_s13_ok('P5.0.1 an active Orange Money receiving account exists for the fixture',
      v_acct IS NOT NULL AND v_acct2 IS NOT NULL, format('primary=%s alt=%s', v_acct, v_acct2));
    r := r || public._qa_s13_ok('P5.0.2 the live Orange Money top-up rail is ON and sandbox mode is OFF before the fixture',
      COALESCE((v_flags0->>'om_topup_enabled')::boolean,false) = true
      AND COALESCE((v_flags0->>'om_sandbox_enabled')::boolean,false) = false,
      format('om_topup_enabled=%s om_sandbox_enabled=%s',
        v_flags0->>'om_topup_enabled', v_flags0->>'om_sandbox_enabled'));
    r := r || public._qa_s13_ok('P5.0.3 the fixture admin really holds wallet management rights',
      public.can_manage_wallet(v_god), 'god_admin');
    r := r || public._qa_s13_ok('P5.0.4 the ordinary fixture user holds no wallet management rights',
      NOT COALESCE(public.can_manage_wallet(v_plain),false), 'plain user');

    v_codeA := 'OM' || v_sfx || 'A1';
    SELECT balance_gnf INTO v_bal0 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_tr := public.wallet_topup_om_create(v_amtA, v_acct);
    v_topA := v_tr.id;
    r := r || public._qa_s13_ok('A1 a customer creates a real Orange Money top-up request through the self-scoped RPC',
      v_tr.id IS NOT NULL AND v_tr.status::text='pending' AND v_tr.amount_gnf=v_amtA
      AND v_tr.provider='orange_money' AND v_tr.environment='production'
      AND v_tr.target_party_type='client' AND v_tr.receiving_account_id = v_acct
      AND v_tr.client_user_id = v_cust,
      format('ref=%s status=%s amount=%s', v_tr.reference, v_tr.status, v_tr.amount_gnf));
    r := r || public._qa_s13_ok('A2 the customer wallet is empty before the top-up', v_bal0 = 0, v_bal0::text);

    v_res := public.submit_customer_om_code(v_topA, v_codeA);
    r := r || public._qa_s13_ok('A3 the customer submits the provider reference and no receipt exists yet',
      v_res->>'status' = 'awaiting_admin_receipt', v_res::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    v_res := public.admin_record_om_receipt(v_codeA, v_amtA, '+224620000501', v_acct, 'qa s13 part5 A');
    PERFORM set_config('request.jwt.claims','',true);
    r := r || public._qa_s13_ok('A4 the operator records the exact provider receipt and the matcher credits it',
      v_res->'match'->>'status' = 'credited' AND v_res->'match'->>'reason' = 'exact_reference_match',
      v_res::text);
    v_evid := (v_res->>'event_id')::uuid;

    SELECT balance_gnf INTO v_bal1 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('A5 the customer wallet is credited by exactly the requested amount',
      v_bal1 - v_bal0 = v_amtA, format('%s -> %s', v_bal0, v_bal1));
    SELECT count(*) INTO v_n FROM public.wallet_transactions
     WHERE type='topup' AND (metadata->>'topup_request_id') = v_topA::text;
    r := r || public._qa_s13_ok('A6 exactly one top-up transaction exists for the request', v_n = 1, v_n::text);

    SELECT count(*) INTO v_n FROM public.ledger_postings p
      JOIN public.ledger_journals j ON j.id = p.journal_id
     WHERE j.source_module='om_topup' AND j.source_id = v_topA
       AND p.account_code = 'L_CUSTOMER_CHOPPAY' AND p.amount_gnf = -v_amtA;
    r := r || public._qa_s13_ok('A7 the offsetting entry is a customer Chop Pay liability of the exact amount',
      v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.ledger_postings p
      JOIN public.ledger_journals j ON j.id = p.journal_id
     WHERE j.source_module='om_topup' AND j.source_id = v_topA
       AND p.account_code = 'A_PROVIDER_CLEARING' AND p.amount_gnf = v_amtA;
    r := r || public._qa_s13_ok('A8 the funds arrive as a provider clearing asset, not as platform income',
      v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.ledger_postings p
      JOIN public.ledger_journals j ON j.id = p.journal_id
     WHERE j.source_module='om_topup' AND j.source_id = v_topA
       AND (p.account_code LIKE 'R!_%' ESCAPE '!' OR p.account_code LIKE 'E!_%' ESCAPE '!');
    r := r || public._qa_s13_ok('A9 the top-up generates no revenue, commission or fee entry at all',
      v_n = 0, v_n::text);
    SELECT COALESCE(sum(amount_gnf),0) INTO v_n FROM public.ledger_postings p
      JOIN public.ledger_journals j ON j.id = p.journal_id
     WHERE j.source_module='om_topup' AND j.source_id = v_topA;
    r := r || public._qa_s13_ok('A10 the top-up journal balances to zero', v_n = 0, v_n::text);

    SELECT status::text INTO v_err FROM public.topup_requests WHERE id = v_topA;
    r := r || public._qa_s13_ok('A11 the top-up request reaches the credited terminal state', v_err = 'credited', v_err);
    SELECT processing_status INTO v_err FROM public.payment_provider_events WHERE id = v_evid;
    r := r || public._qa_s13_ok('A12 the provider receipt reaches the credited terminal state', v_err = 'credited', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    SELECT count(*) INTO v_n FROM public.list_my_topup_requests(50) l
     WHERE (to_jsonb(l)->>'id')::uuid = v_topA AND to_jsonb(l)->>'status' = 'credited';
    r := r || public._qa_s13_ok('A13 the requester history truthfully shows the credited top-up', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.get_my_topup_om_status(v_topA) s
     WHERE to_jsonb(s)->>'status' = 'credited';
    r := r || public._qa_s13_ok('A14 the requester status surface reports the credit', v_n = 1, v_n::text);
    PERFORM set_config('request.jwt.claims','',true);
    v_credited := v_credited + v_amtA;

    v_code := 'OM' || v_sfx || 'AF';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust3), true);
    v_tr := public.wallet_topup_om_create(120000, v_acct);
    v_topAdmFirst := v_tr.id;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    v_res := public.admin_record_om_receipt(v_code, 120000, '+224620000503', v_acct, 'qa s13 admin-first');
    r := r || public._qa_s13_ok('A15 an operator receipt with no customer reference yet waits instead of crediting',
      v_res->'match'->>'status' = 'awaiting_customer_code', v_res::text);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust3), true);
    v_res := public.submit_customer_om_code(v_topAdmFirst, v_code);
    PERFORM set_config('request.jwt.claims','',true);
    SELECT balance_gnf INTO v_bal1 FROM public.wallets WHERE owner_user_id=v_cust3 AND party_type='client';
    r := r || public._qa_s13_ok('A16 the later customer reference completes the admin-first match exactly once',
      v_res->>'status' = 'attempted_match' AND v_bal1 = 120000
      AND (SELECT status::text FROM public.topup_requests WHERE id=v_topAdmFirst) = 'credited',
      format('%s balance=%s', v_res::text, v_bal1));
    v_credited := v_credited + 120000;

    v_codeB := 'OM' || v_sfx || 'B1';
    SELECT balance_gnf INTO v_bal0 FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    r := r || public._qa_s13_ok('B1 the driver operating balance starts at zero, i.e. finance-blocked',
      v_bal0 = 0, v_bal0::text);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    v_tr := public.driver_wallet_topup_om_create(v_amtB, v_acct);
    v_topB := v_tr.id;
    r := r || public._qa_s13_ok('B2 a driver creates a top-up request through the driver self-scoped wrapper',
      v_tr.target_party_type = 'driver' AND v_tr.client_user_id = v_drv
      AND v_tr.receiving_account_id = v_acct AND v_tr.status::text='pending',
      format('ref=%s target=%s', v_tr.reference, v_tr.target_party_type));
    v_res := public.submit_customer_om_code(v_topB, v_codeB);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    v_res := public.admin_record_om_receipt(v_codeB, v_amtB, '+224620000504', v_acct, 'qa s13 part5 B');
    PERFORM set_config('request.jwt.claims','',true);
    r := r || public._qa_s13_ok('B3 the exact driver receipt is matched and credited',
      v_res->'match'->>'status' = 'credited', v_res::text);
    SELECT balance_gnf INTO v_bal1 FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    r := r || public._qa_s13_ok('B4 the driver wallet is credited exactly once by the requested amount',
      v_bal1 - v_bal0 = v_amtB, format('%s -> %s', v_bal0, v_bal1));
    SELECT count(*) INTO v_n FROM public.ledger_postings p
      JOIN public.ledger_journals j ON j.id = p.journal_id
     WHERE j.source_module='om_topup' AND j.source_id = v_topB
       AND p.account_code='L_DRIVER_UNRESTRICTED' AND p.amount_gnf = -v_amtB;
    r := r || public._qa_s13_ok('B5 the driver credit lands in the unrestricted operating balance',
      v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.ledger_postings p
      JOIN public.ledger_journals j ON j.id = p.journal_id
     WHERE j.source_module='om_topup' AND j.source_id = v_topB
       AND p.account_code='L_DRIVER_PROMO';
    r := r || public._qa_s13_ok('B6 no part of the driver top-up becomes restricted starter credit',
      v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.driver_promo_credits WHERE driver_user_id = v_drv;
    r := r || public._qa_s13_ok('B7 no promotional credit record is created by a driver top-up', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.ledger_postings p
      JOIN public.ledger_journals j ON j.id = p.journal_id
     WHERE j.source_module='om_topup' AND j.source_id = v_topB
       AND (p.account_code LIKE 'R!_%' ESCAPE '!' OR p.account_code LIKE 'E!_%' ESCAPE '!');
    r := r || public._qa_s13_ok('B8 the driver top-up produces no platform revenue', v_n = 0, v_n::text);
    SELECT COALESCE(sum(amount_gnf),0) INTO v_n FROM public.ledger_postings p
      JOIN public.ledger_journals j ON j.id = p.journal_id
     WHERE j.source_module='om_topup' AND j.source_id = v_topB;
    r := r || public._qa_s13_ok('B9 the driver top-up journal balances to zero', v_n = 0, v_n::text);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    SELECT count(*) INTO v_n FROM public.driver_topup_history(50) h
     WHERE (to_jsonb(h)->>'id')::uuid = v_topB AND to_jsonb(h)->>'status' = 'credited';
    r := r || public._qa_s13_ok('B10 the driver top-up history reflects the credited event', v_n = 1, v_n::text);
    PERFORM set_config('request.jwt.claims','',true);
    v_credited := v_credited + v_amtB;

    v_c := public._qa_s13_om_case(v_cust2, v_god,'client',150000,v_acct,'OM'||v_sfx||'C1',150000,NULL,v_acct);
    r := r || public._qa_s13_ok('C1 a receipt with no payer phone is held for review and moves no money',
      v_c->>'match_reason' = 'payer_phone_missing' AND (v_c->>'delta')::bigint = 0
      AND v_c->>'review_reason' = 'payer_phone_missing', v_c::text);

    v_c := public._qa_s13_om_case(v_cust2, v_god,'client',150000,v_acct,'OM'||v_sfx||'C2',150000,'+224620000502',NULL);
    r := r || public._qa_s13_ok('C2 a receipt with no receiving account is held for review and moves no money',
      v_c->>'match_reason' = 'receiving_account_missing' AND (v_c->>'delta')::bigint = 0, v_c::text);

    v_c := public._qa_s13_om_case(v_cust2, v_god,'client',150000,v_acct,'OM'||v_sfx||'C3',150000,'+224620777777',v_acct);
    r := r || public._qa_s13_ok('C3 a payer phone that does not match the requester moves no money',
      v_c->>'match_reason' = 'payer_phone_mismatch' AND (v_c->>'delta')::bigint = 0, v_c::text);

    v_c := public._qa_s13_om_case(v_cust2, v_god,'client',150000,v_acct,'OM'||v_sfx||'C4',150000,'+224620000502',v_acct2);
    r := r || public._qa_s13_ok('C4 a receipt paid into a different receiving account moves no money',
      v_c->>'match_reason' = 'receiving_account_mismatch' AND (v_c->>'delta')::bigint = 0, v_c::text);

    v_c := public._qa_s13_om_case(v_cust2, v_god,'client',150000,v_acct,'OM'||v_sfx||'C5',149000,'+224620000502',v_acct);
    r := r || public._qa_s13_ok('C5 an amount that differs from the request moves no money',
      v_c->>'match_reason' = 'amount_mismatch' AND (v_c->>'delta')::bigint = 0, v_c::text);

    SELECT COALESCE(sum(balance_gnf),0) INTO v_bal0 FROM public.wallets
     WHERE owner_user_id IN (v_cust,v_cust2,v_cust3,v_drv,v_drv2,v_plain);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    v_res := public.admin_record_om_receipt('OM'||v_sfx||'C6NOREQ', 150000, '+224620000502', v_acct, 'qa c6');
    PERFORM set_config('request.jwt.claims','',true);
    SELECT COALESCE(sum(balance_gnf),0) INTO v_bal1 FROM public.wallets
     WHERE owner_user_id IN (v_cust,v_cust2,v_cust3,v_drv,v_drv2,v_plain);
    r := r || public._qa_s13_ok('C6 a provider reference with no matching request credits nobody',
      v_res->'match'->>'status' = 'awaiting_customer_code' AND v_bal1 = v_bal0, v_res::text);

    v_code := 'OM'||v_sfx||'C7';
    INSERT INTO public.topup_requests(reference, client_user_id, amount_gnf, confirmation_code,
      provider, user_phone, status, expires_at, receiving_account_id, target_party_type,
      environment, customer_om_code_normalized, customer_om_code_raw, customer_om_code_submitted_at)
    VALUES (public.gen_topup_reference(), v_cust2, 150000, '------','orange_money','+224620000502',
      'matched'::topup_status, now() + interval '2 hours', v_acct, 'client','sandbox',
      public.normalize_om_code(v_code), v_code, now())
    RETURNING id INTO v_topAdmFirst;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    v_res := public.admin_record_om_receipt(v_code, 150000, '+224620000502', v_acct, 'qa c7');
    PERFORM set_config('request.jwt.claims','',true);
    SELECT COALESCE(sum(balance_gnf),0) INTO v_bal1 FROM public.wallets
     WHERE owner_user_id IN (v_cust,v_cust2,v_cust3,v_drv,v_drv2,v_plain);
    r := r || public._qa_s13_ok('C7 a production receipt cannot satisfy a sandbox request',
      v_res->'match'->>'status' = 'awaiting_customer_code' AND v_bal1 = v_bal0
      AND (SELECT status::text FROM public.topup_requests WHERE id=v_topAdmFirst) = 'matched',
      v_res::text);

    v_f := public._qa_s13_om_forced(v_cust2, 150000, v_acct, v_acct2, 'OM'||v_sfx||'C8','target');
    r := r || public._qa_s13_ok('C8 a request pointing at a wallet the requester does not own credits nothing',
      v_f->>'error' LIKE '%target_wallet_not_found%' AND (v_f->>'delta')::bigint = 0, v_f::text);

    v_code := 'OM'||v_sfx||'C9';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust2), true);
    v_tr := public.wallet_topup_om_create(150000, v_acct);
    PERFORM public.submit_customer_om_code(v_tr.id, v_code);
    PERFORM set_config('request.jwt.claims','',true);
    UPDATE public.topup_requests SET expires_at = now() - interval '1 hour' WHERE id = v_tr.id;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    v_res := public.admin_record_om_receipt(v_code, 150000, '+224620000502', v_acct, 'qa c9');
    PERFORM set_config('request.jwt.claims','',true);
    v_evid := (v_res->>'event_id')::uuid;
    BEGIN PERFORM public.wallet_topup_om_credit(v_evid, v_tr.id); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT COALESCE(sum(balance_gnf),0) INTO v_bal1 FROM public.wallets
     WHERE owner_user_id IN (v_cust,v_cust2,v_cust3,v_drv,v_drv2,v_plain);
    r := r || public._qa_s13_ok('C10 an expired request is never matched and never credited even by force',
      v_res->'match'->>'status' = 'awaiting_customer_code' AND v_err LIKE '%expired%' AND v_bal1 = v_bal0,
      format('match=%s force=%s', v_res::text, v_err));

    INSERT INTO public.payment_provider_events(provider,event_type,provider_transaction_id,payer_phone,
      amount_gnf,status,processing_status,raw_payload,receiving_account_id)
    VALUES ('orange_money','payment.received','OM'||v_sfx||'C11','+224620000502',150000,
      'failed','received','{"source":"qa"}'::jsonb, v_acct) RETURNING id INTO v_evid;
    v_res := public.om_auto_match(v_evid);
    SELECT COALESCE(sum(balance_gnf),0) INTO v_bal1 FROM public.wallets
     WHERE owner_user_id IN (v_cust,v_cust2,v_cust3,v_drv,v_drv2,v_plain);
    r := r || public._qa_s13_ok('C11 an unsuccessful provider receipt is rejected and credits nothing',
      v_res->>'status' = 'rejected' AND v_bal1 = v_bal0, v_res::text);

    v_code := 'OM'||v_sfx||'C12';
    INSERT INTO public.topup_requests(reference, client_user_id, amount_gnf, confirmation_code,
      provider, user_phone, status, expires_at, receiving_account_id, target_party_type,
      environment, customer_om_code_normalized, customer_om_code_raw, customer_om_code_submitted_at)
    VALUES
      (public.gen_topup_reference(), v_cust2, 150000,'------','orange_money','+224620000502',
       'matched'::topup_status, now()+interval '2 hours', v_acct,'client','production',
       public.normalize_om_code(v_code), v_code, now()),
      (public.gen_topup_reference(), v_cust3, 150000,'------','orange_money','+224620000503',
       'matched'::topup_status, now()+interval '2 hours', v_acct,'client','production',
       public.normalize_om_code(v_code), v_code, now());
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    v_res := public.admin_record_om_receipt(v_code, 150000, '+224620000502', v_acct, 'qa c12');
    PERFORM set_config('request.jwt.claims','',true);
    SELECT COALESCE(sum(balance_gnf),0) INTO v_bal1 FROM public.wallets
     WHERE owner_user_id IN (v_cust,v_cust2,v_cust3,v_drv,v_drv2,v_plain);
    r := r || public._qa_s13_ok('C12 two requests claiming the same reference are held for review, not credited',
      v_res->'match'->>'reason' = 'multiple_candidates' AND v_bal1 = v_bal0, v_res::text);

    r := r || public._qa_s13_ok('C13 the whole missing-evidence matrix moved exactly zero GNF',
      v_bal1 = v_bal0, format('before=%s after=%s', v_bal0, v_bal1));

    v_f := public._qa_s13_om_forced(v_cust2, 150000, v_acct, v_acct2, 'OM'||v_sfx||'D1','amount');
    r := r || public._qa_s13_ok('D1 a forced credit with a wrong amount is refused at credit time',
      v_f->>'error' = 'amount_mismatch' AND (v_f->>'delta')::bigint = 0, v_f::text);
    v_f := public._qa_s13_om_forced(v_cust2, 150000, v_acct, v_acct2, 'OM'||v_sfx||'D2','phone');
    r := r || public._qa_s13_ok('D2 a forced credit with a wrong payer phone is refused at credit time',
      v_f->>'error' = 'payer_phone_mismatch' AND (v_f->>'delta')::bigint = 0, v_f::text);
    v_f := public._qa_s13_om_forced(v_cust2, 150000, v_acct, v_acct2, 'OM'||v_sfx||'D3','phone_missing');
    r := r || public._qa_s13_ok('D3 a forced credit with a missing payer phone is refused at credit time',
      v_f->>'error' = 'payer_phone_missing' AND (v_f->>'delta')::bigint = 0, v_f::text);
    v_f := public._qa_s13_om_forced(v_cust2, 150000, v_acct, v_acct2, 'OM'||v_sfx||'D4','account');
    r := r || public._qa_s13_ok('D4 a forced credit paid into another receiving account is refused',
      v_f->>'error' = 'receiving_account_mismatch' AND (v_f->>'delta')::bigint = 0, v_f::text);
    v_f := public._qa_s13_om_forced(v_cust2, 150000, v_acct, v_acct2, 'OM'||v_sfx||'D5','account_missing');
    r := r || public._qa_s13_ok('D5 a forced credit with no receiving account evidence is refused',
      v_f->>'error' = 'receiving_account_missing' AND (v_f->>'delta')::bigint = 0, v_f::text);
    v_f := public._qa_s13_om_forced(v_cust2, 150000, v_acct, v_acct2, 'OM'||v_sfx||'D6','reference');
    r := r || public._qa_s13_ok('D6 a forced credit whose provider reference differs is refused',
      v_f->>'error' = 'provider_reference_mismatch' AND (v_f->>'delta')::bigint = 0, v_f::text);
    v_f := public._qa_s13_om_forced(v_cust2, 150000, v_acct, v_acct2, 'OM'||v_sfx||'D7','environment');
    r := r || public._qa_s13_ok('D7 a forced credit from the wrong environment is refused',
      v_f->>'error' LIKE 'environment_mismatch%' AND (v_f->>'delta')::bigint = 0, v_f::text);

    v_code := 'OM'||v_sfx||'D8';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust2), true);
    v_tr := public.wallet_topup_om_create(150000, v_acct);
    PERFORM public.submit_customer_om_code(v_tr.id, v_code);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust3), true);
    v_tr2 := public.wallet_topup_om_create(150000, v_acct);
    PERFORM public.submit_customer_om_code(v_tr2.id, 'OM'||v_sfx||'D8B');
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    v_res := public.admin_record_om_receipt(v_code, 150000, '+224620000502', v_acct, 'qa d8');
    PERFORM set_config('request.jwt.claims','',true);
    v_evid := (v_res->>'event_id')::uuid;
    SELECT COALESCE(sum(balance_gnf),0) INTO v_bal0 FROM public.wallets WHERE owner_user_id = v_cust3;
    BEGIN PERFORM public.wallet_topup_om_credit(v_evid, v_tr2.id); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT COALESCE(sum(balance_gnf),0) INTO v_bal1 FROM public.wallets WHERE owner_user_id = v_cust3;
    r := r || public._qa_s13_ok('D8 one customer receipt cannot be redirected into another customer request',
      v_err <> 'NO_ERROR' AND v_bal1 = v_bal0, format('%s delta=%s', v_err, v_bal1-v_bal0));
    r := r || public._qa_s13_ok('D9 the redirected receipt itself was a genuine credited-eligible receipt',
      (SELECT processing_status FROM public.payment_provider_events WHERE id=v_evid) = 'credited',
      'source receipt credited its own request');

    SELECT balance_gnf INTO v_bal0 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    v_res := public.admin_record_om_receipt(v_codeA, v_amtA, '+224620000501', v_acct, 'qa replay');
    PERFORM set_config('request.jwt.claims','',true);
    SELECT balance_gnf INTO v_bal1 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    SELECT count(*) INTO v_n FROM public.payment_provider_events
     WHERE provider='orange_money' AND om_code_normalized = public.normalize_om_code(v_codeA);
    r := r || public._qa_s13_ok('E1 re-ingesting the same provider reference creates no second receipt and no second credit',
      (v_res->>'duplicate')::boolean = true AND v_n = 1 AND v_bal1 = v_bal0,
      format('events=%s delta=%s', v_n, v_bal1-v_bal0));

    SELECT id INTO v_evid FROM public.payment_provider_events
     WHERE om_code_normalized = public.normalize_om_code(v_codeA);
    v_res := public.om_auto_match(v_evid);
    SELECT balance_gnf INTO v_bal1 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('E2 re-running the matcher on a credited receipt is inert',
      (v_res->>'inert')::boolean = true AND v_bal1 = v_bal0, v_res::text);

    BEGIN v_tr := public.wallet_topup_om_credit(v_evid, v_topA); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT balance_gnf INTO v_bal1 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    SELECT count(*) INTO v_n FROM public.wallet_transactions
     WHERE type='topup' AND (metadata->>'topup_request_id') = v_topA::text;
    r := r || public._qa_s13_ok('E3 replaying the raw credit returns the original receipt and moves no extra money',
      v_bal1 = v_bal0 AND v_n = 1, format('err=%s delta=%s txs=%s', v_err, v_bal1-v_bal0, v_n));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    BEGIN v_res := public.admin_manual_om_credit(v_evid, v_topA); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    PERFORM set_config('request.jwt.claims','',true);
    SELECT balance_gnf INTO v_bal1 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    SELECT count(*) INTO v_n FROM public.wallet_transactions
     WHERE type='topup' AND (metadata->>'topup_request_id') = v_topA::text;
    r := r || public._qa_s13_ok('E4 an operator manual credit on an already credited top-up adds nothing',
      v_bal1 = v_bal0 AND v_n = 1, format('err=%s delta=%s txs=%s', v_err, v_bal1-v_bal0, v_n));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust2), true);
    v_tr := public.wallet_topup_om_create(150000, v_acct);
    BEGIN v_res := public.submit_customer_om_code(v_tr.id, v_codeA); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; v_res := '{}'::jsonb; END;
    PERFORM set_config('request.jwt.claims','',true);
    SELECT COALESCE(sum(balance_gnf),0) INTO v_bal1 FROM public.wallets WHERE owner_user_id = v_cust2;
    r := r || public._qa_s13_ok('E5 a provider reference already credited cannot be reused by another customer',
      (v_res->>'reason' = 'duplicate_customer_code' OR v_err <> 'NO_ERROR')
      AND (SELECT status::text FROM public.topup_requests WHERE id=v_tr.id) <> 'credited',
      format('res=%s err=%s', v_res::text, v_err));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv2), true);
    v_tr := public.driver_wallet_topup_om_create(150000, v_acct);
    BEGIN v_res := public.submit_customer_om_code(v_tr.id, v_codeA); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; v_res := '{}'::jsonb; END;
    PERFORM set_config('request.jwt.claims','',true);
    SELECT balance_gnf INTO v_bal1 FROM public.wallets WHERE owner_user_id=v_drv2 AND party_type='driver';
    r := r || public._qa_s13_ok('E6 a credited customer reference cannot be reused on a driver request either',
      v_bal1 = 0 AND (SELECT status::text FROM public.topup_requests WHERE id=v_tr.id) <> 'credited',
      format('res=%s err=%s balance=%s', v_res::text, v_err, v_bal1));

    v_code := 'OM'||v_sfx||'E7';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust3), true);
    v_tr := public.wallet_topup_om_create(90000, v_acct);
    PERFORM public.submit_customer_om_code(v_tr.id, v_code);
    PERFORM public.submit_customer_om_code(v_tr.id, v_code);
    PERFORM public.submit_customer_om_code(v_tr.id, v_code);
    SELECT balance_gnf INTO v_bal0 FROM public.wallets WHERE owner_user_id=v_cust3 AND party_type='client';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    v_res := public.admin_record_om_receipt(v_code, 90000, '+224620000503', v_acct, 'qa e7');
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust3), true);
    PERFORM public.submit_customer_om_code(v_tr.id, v_code);
    PERFORM set_config('request.jwt.claims','',true);
    SELECT balance_gnf INTO v_bal1 FROM public.wallets WHERE owner_user_id=v_cust3 AND party_type='client';
    SELECT count(*) INTO v_n FROM public.wallet_transactions
     WHERE type='topup' AND (metadata->>'topup_request_id') = v_tr.id::text;
    r := r || public._qa_s13_ok('E7 repeated offline retries of the same submission produce exactly one credit',
      v_bal1 - v_bal0 = 90000 AND v_n = 1, format('delta=%s txs=%s', v_bal1-v_bal0, v_n));

    v_evid := (v_res->>'event_id')::uuid;
    v_lock := hashtextextended('om_credit:'||v_evid::text, 0);
    SELECT count(*) INTO v_n FROM pg_locks
     WHERE locktype='advisory' AND pid = pg_backend_pid()
       AND classid = ((v_lock >> 32) & 4294967295)::bigint::oid
       AND objid  = (v_lock & 4294967295)::bigint::oid;
    r := r || public._qa_s13_ok('E8 the credit primitive holds a per-receipt exclusive lock, so a concurrent credit must wait',
      v_n = 1, format('advisory locks held for this receipt = %s', v_n));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust3), true);
    v_tr  := public.wallet_topup_om_create(70000, v_acct);
    v_tr2 := public.wallet_topup_om_create(70000, v_acct);
    PERFORM set_config('request.jwt.claims','',true);
    SELECT balance_gnf INTO v_bal0 FROM public.wallets WHERE owner_user_id=v_cust3 AND party_type='client';
    r := r || public._qa_s13_ok('E9 a retried create call produces separate pending requests and no financial exposure',
      v_tr.id <> v_tr2.id AND v_bal0 = v_bal1
      AND v_tr.status::text='pending' AND v_tr2.status::text='pending',
      format('a=%s b=%s balance=%s', v_tr.id, v_tr2.id, v_bal0));

    SELECT count(*) INTO v_n FROM pg_proc p
     WHERE p.pronamespace='public'::regnamespace AND p.proname IN ('om_auto_match','wallet_topup_om_credit')
       AND (has_function_privilege('anon', p.oid,'EXECUTE') OR has_function_privilege('authenticated', p.oid,'EXECUTE'));
    r := r || public._qa_s13_ok('F1 the raw matcher and credit primitives are not executable by app users',
      v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM pg_proc p
     WHERE p.pronamespace='public'::regnamespace AND p.proname IN ('om_auto_match','wallet_topup_om_credit')
       AND has_function_privilege('service_role', p.oid,'EXECUTE');
    r := r || public._qa_s13_ok('F2 the raw matcher and credit primitives remain available to the backend service role',
      v_n = 2, v_n::text);

    v_err := public._qa_s13_om_rolecall('anon', NULL, 'SELECT public.om_auto_match($1::uuid)', v_evid::text, NULL);
    r := r || public._qa_s13_ok('F3 an anonymous caller cannot run the matcher', v_err <> 'NO_ERROR', v_err);
    v_err := public._qa_s13_om_rolecall('authenticated', v_cust,
      'SELECT public.wallet_topup_om_credit($1::uuid, $2::uuid)', v_evid::text, v_topA::text);
    r := r || public._qa_s13_ok('F4 a signed-in app user cannot run the raw credit primitive', v_err <> 'NO_ERROR', v_err);
    v_err := public._qa_s13_om_rolecall('authenticated', v_plain,
      'SELECT public.admin_record_om_receipt($1, 1000, ''+224620000506'', NULL, ''qa'')', 'OM'||v_sfx||'F5', NULL);
    r := r || public._qa_s13_ok('F5 an ordinary signed-in user cannot record an operator receipt',
      v_err LIKE '%forbidden%', v_err);
    v_err := public._qa_s13_om_rolecall('authenticated', v_plain,
      'SELECT public.admin_manual_om_credit($1::uuid, $2::uuid)', v_evid::text, v_topA::text);
    r := r || public._qa_s13_ok('F6 an ordinary signed-in user cannot force a manual credit',
      v_err LIKE '%forbidden%', v_err);
    v_err := public._qa_s13_om_rolecall('authenticated', NULL,
      'SELECT public.admin_record_om_receipt($1, 1000, ''+224620000506'', NULL, ''qa'')', 'OM'||v_sfx||'F7', NULL);
    r := r || public._qa_s13_ok('F7 an unauthenticated caller is never treated as privileged',
      v_err <> 'NO_ERROR', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust2), true);
    SELECT count(*) INTO v_n FROM public.get_my_topup_om_status(v_topA) s;
    r := r || public._qa_s13_ok('F8 a customer cannot inspect another customer top-up request', v_n = 0, v_n::text);
    BEGIN PERFORM public.submit_customer_om_code(v_topA, 'OM'||v_sfx||'F9'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('F9 a customer cannot attach a reference to another customer request',
      v_err <> 'NO_ERROR', v_err);
    SELECT count(*) INTO v_n FROM public.list_my_topup_requests(100) l
     WHERE (to_jsonb(l)->>'id')::uuid = v_topA;
    r := r || public._qa_s13_ok('F10 the participant history returns only the caller own requests', v_n = 0, v_n::text);
    PERFORM set_config('request.jwt.claims','',true);

    v_err := public._qa_s13_om_rolecall('authenticated', NULL, 'SELECT public.wallet_topup_om_create(5000, NULL)', NULL, NULL);
    r := r || public._qa_s13_ok('F11 the customer top-up wrapper requires authentication', v_err <> 'NO_ERROR', v_err);
    v_err := public._qa_s13_om_rolecall('authenticated', NULL, 'SELECT public.driver_wallet_topup_om_create(5000, NULL)', NULL, NULL);
    r := r || public._qa_s13_ok('F12 the driver top-up wrapper requires authentication', v_err <> 'NO_ERROR', v_err);
    v_err := public._qa_s13_om_rolecall('authenticated', v_cust2, 'SELECT public.driver_wallet_topup_om_create(5000, NULL)', NULL, NULL);
    r := r || public._qa_s13_ok('F13 a customer cannot open a driver top-up and reach a driver wallet',
      v_err <> 'NO_ERROR', v_err);
    SELECT count(*) INTO v_n FROM pg_proc p
     WHERE p.pronamespace='public'::regnamespace
       AND p.proname IN ('wallet_topup_om_create','driver_wallet_topup_om_create','submit_customer_om_code',
                         'om_auto_match','wallet_topup_om_credit','admin_record_om_receipt',
                         'admin_manual_om_credit','admin_retry_om_credit','get_my_topup_om_status',
                         'list_my_topup_requests','driver_topup_history')
       AND p.prosecdef AND (p.proconfig IS NULL OR NOT (p.proconfig::text LIKE '%search_path%'));
    r := r || public._qa_s13_ok('F14 every privileged function on the Orange Money path has a fixed search path',
      v_n = 0, v_n::text);

    SELECT COALESCE(sum(balance_gnf),0) INTO v_bal0 FROM public.wallets;
    PERFORM public._qa_s13_flag('om_sandbox_enabled', true);
    v_code := 'OM'||v_sfx||'G1';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust2), true);
    v_tr := public.wallet_topup_om_create(80000, v_acct);
    PERFORM public.submit_customer_om_code(v_tr.id, v_code);
    PERFORM set_config('request.jwt.claims','',true);
    INSERT INTO public.payment_provider_events(provider,event_type,provider_transaction_id,payer_phone,
      amount_gnf,status,processing_status,raw_payload,receiving_account_id,is_sandbox,environment)
    VALUES ('orange_money','payment.received', v_code||'-SBX','+224620000502',80000,'successful','received',
      '{"source":"qa_sandbox"}'::jsonb, v_acct, true, 'sandbox')
    RETURNING id INTO v_evid;
    UPDATE public.payment_provider_events SET om_code_normalized = public.normalize_om_code(v_code) WHERE id = v_evid;
    v_res := public.om_auto_match(v_evid);
    SELECT balance_gnf INTO v_bal1 FROM public.wallets WHERE owner_user_id=v_cust2 AND party_type='client';
    r := r || public._qa_s13_ok('G1 a sandbox receipt cannot match or credit a production top-up request',
      v_res->>'status' <> 'credited' AND v_bal1 = 0, format('%s balance=%s', v_res::text, v_bal1));
    r := r || public._qa_s13_ok('G2 the sandbox receipt carries the sandbox environment discriminator',
      (SELECT is_sandbox AND environment='sandbox' FROM public.payment_provider_events WHERE id=v_evid),
      'is_sandbox/environment');

    v_code := 'OM'||v_sfx||'G3';
    INSERT INTO public.topup_requests(reference, client_user_id, amount_gnf, confirmation_code,
      provider, user_phone, status, expires_at, receiving_account_id, target_party_type,
      environment, customer_om_code_normalized, customer_om_code_raw, customer_om_code_submitted_at)
    VALUES (public.gen_topup_reference(), v_cust2, 80000,'------','orange_money','+224620000502',
      'matched'::topup_status, now()+interval '2 hours', v_acct,'client','sandbox',
      public.normalize_om_code(v_code), v_code, now())
    RETURNING id INTO v_topAdmFirst;
    INSERT INTO public.payment_provider_events(provider,event_type,provider_transaction_id,payer_phone,
      amount_gnf,status,processing_status,raw_payload,receiving_account_id,is_sandbox,environment,
      om_code_normalized)
    VALUES ('orange_money','payment.received', v_code||'-SBX2','+224620000502',80000,'successful','received',
      '{"source":"qa_sandbox"}'::jsonb, v_acct, true, 'sandbox', public.normalize_om_code(v_code))
    RETURNING id INTO v_ev2;
    SELECT COALESCE(sum(balance_gnf),0) INTO v_bal1 FROM public.wallets;
    BEGIN v_res := public.om_auto_match(v_ev2); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; v_res := '{}'::jsonb; END;
    SELECT COALESCE(sum(balance_gnf),0) INTO v_n FROM public.wallets;
    r := r || public._qa_s13_ok('G3 a sandbox top-up lifecycle never moves production wallet money',
      v_n = v_bal1, format('match=%s err=%s before=%s after=%s', v_res::text, v_err, v_bal1, v_n));

    PERFORM public._qa_s13_flag('om_sandbox_enabled',
      COALESCE((v_flags0->>'om_sandbox_enabled')::boolean, false));
    r := r || public._qa_s13_ok('G4 the sandbox switch is restored inside the fixture',
      (SELECT enabled FROM public.feature_flags WHERE key='om_sandbox_enabled')
        = COALESCE((v_flags0->>'om_sandbox_enabled')::boolean,false), 'restored');

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust2), true);
    BEGIN PERFORM public.wallet_topup_om_create(0, v_acct); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('H1 a zero amount top-up is refused before anything is created', v_err <> 'NO_ERROR', v_err);
    BEGIN PERFORM public.wallet_topup_om_create(-50000, v_acct); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('H2 a negative amount top-up is refused', v_err <> 'NO_ERROR', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    BEGIN PERFORM public.admin_record_om_receipt('OM'||v_sfx||'H3', 0, '+224620000502', v_acct, 'qa h3'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('H3 an operator receipt with a zero amount is refused',
      v_err LIKE '%invalid_amount%', v_err);
    BEGIN PERFORM public.admin_record_om_receipt('OM'||v_sfx||'H3B', -1000, '+224620000502', v_acct, 'qa h3b'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('H4 an operator receipt with a negative amount is refused',
      v_err LIKE '%invalid_amount%', v_err);
    PERFORM set_config('request.jwt.claims','',true);

    v_code := 'OM'||v_sfx||'H5';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_plain), true);
    v_tr := public.wallet_topup_om_create(60000, v_acct);
    PERFORM public.submit_customer_om_code(v_tr.id, v_code);
    PERFORM set_config('request.jwt.claims','',true);
    UPDATE public.wallets SET status='frozen'::wallet_status
     WHERE owner_user_id = v_plain AND party_type='client';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    v_res := public.admin_record_om_receipt(v_code, 60000, '+224620000506', v_acct, 'qa h5');
    PERFORM set_config('request.jwt.claims','',true);
    SELECT balance_gnf INTO v_bal1 FROM public.wallets WHERE owner_user_id=v_plain AND party_type='client';
    r := r || public._qa_s13_ok('H5 a frozen wallet cannot be credited and stays at zero',
      v_bal1 = 0 AND (SELECT status::text FROM public.topup_requests WHERE id=v_tr.id) <> 'credited',
      format('match=%s balance=%s', v_res::text, v_bal1));
    UPDATE public.wallets SET status='active'::wallet_status
     WHERE owner_user_id = v_plain AND party_type='client';

    v_code := 'OM'||v_sfx||'H6';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust2), true);
    v_tr := public.wallet_topup_om_create(55000, v_acct);
    PERFORM public.submit_customer_om_code(v_tr.id, v_code);
    PERFORM public.wallet_topup_cancel(v_tr.id, 'qa cancel');
    PERFORM set_config('request.jwt.claims','',true);
    INSERT INTO public.payment_provider_events(provider,event_type,provider_transaction_id,payer_phone,
      amount_gnf,status,processing_status,raw_payload,receiving_account_id,om_code_normalized)
    VALUES ('orange_money','payment.received', v_code||'-EV','+224620000502',55000,'successful','received',
      '{"source":"qa"}'::jsonb, v_acct, public.normalize_om_code(v_code))
    RETURNING id INTO v_evid;
    SELECT COALESCE(sum(balance_gnf),0) INTO v_bal0 FROM public.wallets WHERE owner_user_id=v_cust2;
    BEGIN PERFORM public.wallet_topup_om_credit(v_evid, v_tr.id); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT COALESCE(sum(balance_gnf),0) INTO v_bal1 FROM public.wallets WHERE owner_user_id=v_cust2;
    r := r || public._qa_s13_ok('H6 a cancelled top-up request can never be credited afterwards',
      v_err <> 'NO_ERROR' AND v_bal1 = v_bal0, format('%s delta=%s', v_err, v_bal1-v_bal0));

    UPDATE public.driver_profiles SET status='suspended'::driver_status WHERE user_id = v_drv2;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv2), true);
    BEGIN PERFORM public.driver_wallet_topup_om_create(60000, v_acct); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    PERFORM set_config('request.jwt.claims','',true);
    r := r || public._qa_s13_ok('H7 a suspended driver cannot open a top-up request',
      v_err LIKE '%driver_%', v_err);
    UPDATE public.driver_profiles SET status='approved'::driver_status WHERE user_id = v_drv2;
    r := r || public._qa_s13_ok('H8 the canonical driver recovery exception holds: a zero-balance driver still tops up',
      (SELECT balance_gnf FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver') = v_amtB,
      'driver credited from a finance-blocked zero balance');

    SELECT count(*) INTO v_n FROM (
      SELECT j.id FROM public.ledger_journals j
       JOIN public.ledger_postings p ON p.journal_id = j.id
       WHERE j.source_module='om_topup' AND j.created_at >= v_t0
       GROUP BY j.id HAVING sum(p.amount_gnf) <> 0) z;
    r := r || public._qa_s13_ok('I1 every top-up journal created in this run balances to zero', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.ledger_postings p
      JOIN public.ledger_journals j ON j.id = p.journal_id
     WHERE j.source_module='om_topup' AND j.created_at >= v_t0
       AND (p.account_code LIKE 'R!_%' ESCAPE '!' OR p.account_code LIKE 'E!_%' ESCAPE '!');
    r := r || public._qa_s13_ok('I2 no inbound top-up produced revenue, commission or provider fee', v_n = 0, v_n::text);
    SELECT COALESCE(-sum(p.amount_gnf),0) INTO v_bal0 FROM public.ledger_postings p
      JOIN public.ledger_journals j ON j.id = p.journal_id
     WHERE j.source_module='om_topup' AND j.created_at >= v_t0
       AND p.account_code IN ('L_CUSTOMER_CHOPPAY','L_DRIVER_UNRESTRICTED');
    SELECT COALESCE(sum(amount_gnf),0) INTO v_bal1 FROM public.wallet_transactions
     WHERE type='topup' AND created_at >= v_t0
       AND related_user_id IN (v_cust,v_cust2,v_cust3,v_drv,v_drv2,v_plain);
    r := r || public._qa_s13_ok('I3 customer and driver top-up liabilities reconcile exactly to the wallet credits',
      v_bal0 = v_bal1 AND v_bal0 > 0, format('liabilities=%s credits=%s', v_bal0, v_bal1));
    SELECT balance_gnf INTO v_mbal1 FROM public.wallets WHERE party_type='master';
    r := r || public._qa_s13_ok('I4 the platform master wallet only passes the cash through and gains no revenue',
      v_master0 - v_mbal1 = v_bal1, format('master %s -> %s, credited %s', v_master0, v_mbal1, v_bal1));
    SELECT count(*) INTO v_n FROM (
      SELECT j.id FROM public.ledger_journals j
       JOIN public.ledger_postings p ON p.journal_id = j.id
       GROUP BY j.id HAVING sum(p.amount_gnf) <> 0) z;
    r := r || public._qa_s13_ok('I5 no imbalanced journal exists anywhere after the fixture', v_n = 0, v_n::text);
    SELECT COALESCE(sum(amount_gnf),0) INTO v_n FROM public.ledger_postings;
    r := r || public._qa_s13_ok('I6 the global ledger posting sum is still zero', v_n = 0, v_n::text);

    RAISE EXCEPTION 'QA_S13_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_S13_ROLLBACK' THEN
      r := r || public._qa_s13_ok('HARNESS_PART5_UNEXPECTED_ABORT', false, SQLERRM);
    END IF;
  END;

  PERFORM set_config('request.jwt.claims','',true);
  SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;
  r := r || public._qa_s13_ok('Z5.1 the master wallet is exactly back to its live balance after rollback',
    v_master1 = v_master0 AND v_master1 = -100435, v_master1::text);
  SELECT held_gnf INTO v_n FROM public.wallets WHERE party_type='master';
  r := r || public._qa_s13_ok('Z5.2 the master wallet holds nothing after rollback', v_n = 0, v_n::text);
  SELECT COALESCE(sum(amount_gnf),0) INTO v_n FROM public.ledger_postings;
  r := r || public._qa_s13_ok('Z5.3 the global ledger posting sum is zero after rollback', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM (
    SELECT j.id FROM public.ledger_journals j
     JOIN public.ledger_postings p ON p.journal_id = j.id
     GROUP BY j.id HAVING sum(p.amount_gnf) <> 0) z;
  r := r || public._qa_s13_ok('Z5.4 no imbalanced journal survives the rollback', v_n = 0, v_n::text);
  r := r || public._qa_s13_ok('Z5.5 live feature flags are byte-identical after the fixture', v_flags1 = v_flags0, NULL);
  r := r || public._qa_s13_ok('Z5.6 the Orange Money top-up rail is still ON and sandbox mode still OFF',
    (SELECT enabled FROM public.feature_flags WHERE key='om_topup_enabled') = true
    AND (SELECT enabled FROM public.feature_flags WHERE key='om_sandbox_enabled') = false, NULL);
  SELECT count(*) INTO v_n FROM auth.users WHERE email LIKE 'qa-s13-om%@qa.invalid';
  r := r || public._qa_s13_ok('Z5.7 no QA user survives the rollback', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.topup_requests
   WHERE client_user_id IN (SELECT id FROM auth.users WHERE email LIKE 'qa-s13-%@qa.invalid');
  r := r || public._qa_s13_ok('Z5.8 no QA top-up request survives the rollback', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.payment_provider_events
   WHERE raw_payload->>'source' IN ('qa','qa_sandbox','qa_s13_forced');
  r := r || public._qa_s13_ok('Z5.9 no QA provider receipt survives the rollback', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.payment_receiving_accounts WHERE label = 'QA S13 alt account';
  r := r || public._qa_s13_ok('Z5.10 no QA receiving account survives the rollback', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.ledger_journals WHERE source_module='om_topup' AND created_at >= v_t0;
  r := r || public._qa_s13_ok('Z5.11 no QA top-up journal survives the rollback', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM pg_proc p
   WHERE p.pronamespace='public'::regnamespace AND p.proname LIKE '\_qa\_s13%'
     AND (has_function_privilege('anon', p.oid,'EXECUTE') OR has_function_privilege('authenticated', p.oid,'EXECUTE'));
  r := r || public._qa_s13_ok('Z5.12 no QA harness function is executable by anon or authenticated', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM pg_proc p
   WHERE p.pronamespace='public'::regnamespace AND p.proname IN ('om_auto_match','wallet_topup_om_credit')
     AND has_function_privilege('service_role', p.oid,'EXECUTE')
     AND NOT has_function_privilege('anon', p.oid,'EXECUTE')
     AND NOT has_function_privilege('authenticated', p.oid,'EXECUTE');
  r := r || public._qa_s13_ok('Z5.13 the raw Orange Money privilege matrix is unchanged after the run', v_n = 2, v_n::text);

  RETURN public._qa_s13_summary(5, r);
END $fn$;

REVOKE ALL ON FUNCTION public._qa_s13_run5() FROM PUBLIC, anon, authenticated;