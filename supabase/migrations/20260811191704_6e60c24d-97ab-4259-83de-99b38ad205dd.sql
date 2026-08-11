DO $mig$
DECLARE
  s text; a int; b int; m1 text; m2 text;
BEGIN
  SELECT prosrc INTO s FROM pg_proc
   WHERE proname = '_qa_s13_run5' AND pronamespace = 'public'::regnamespace;
  IF s IS NULL THEN RAISE EXCEPTION 'harness missing'; END IF;

  s := replace(s,
    '  v_mbal0 bigint; v_mbal1 bigint;' || chr(10),
    '  v_mbal0 bigint; v_mbal1 bigint;' || chr(10) ||
    '  v_tr3 public.topup_requests;' || chr(10) ||
    '  v_tx_orig public.wallet_transactions; v_tx_replay public.wallet_transactions;' || chr(10) ||
    '  v_mrq uuid; v_mru uuid; v_j0 bigint; v_j1 bigint; v_w0 bigint; v_w1 bigint;' || chr(10) ||
    '  v_ntx0 bigint; v_ntx1 bigint;' || chr(10));

  m1 := $m1$    v_code := 'OM'||v_sfx||'D8';$m1$;
  m2 := $m2$'source receipt credited its own request');$m2$;
  a := strpos(s, m1);
  b := strpos(s, m2);
  IF a = 0 OR b = 0 OR b < a THEN RAISE EXCEPTION 'D8 markers not found (a=%, b=%)', a, b; END IF;

  s := substr(s, 1, a - 1) || $blk$    -- D8 series - a provider reference stays bound to one logical credit.
    -- D8.0-D8.7 cover IDEMPOTENT REPLAY of an already-credited receipt against
    -- another customer's request (no exception required, no redirect allowed).
    -- D8F/D8G cover a FRESH, uncredited receipt manually pointed at the wrong
    -- target, which credit-time revalidation must refuse outright.
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

    SELECT * INTO v_tx_orig FROM public.wallet_transactions
     WHERE type='topup' AND (metadata->>'event_id') = v_evid::text LIMIT 1;
    SELECT matched_topup_request_id, matched_user_id INTO v_mrq, v_mru
      FROM public.payment_provider_events WHERE id = v_evid;
    r := r || public._qa_s13_ok('D8.0 the D8 receipt is a genuine receipt that already credited its own request',
      v_tx_orig.id IS NOT NULL AND v_mrq = v_tr.id AND v_mru = v_cust2
      AND (SELECT processing_status FROM public.payment_provider_events WHERE id=v_evid) = 'credited',
      format('tx=%s matched_request=%s matched_user=%s', v_tx_orig.id, v_mrq, v_mru));

    SELECT balance_gnf INTO v_bal0 FROM public.wallets WHERE owner_user_id=v_cust3 AND party_type='client';
    SELECT balance_gnf INTO v_w0   FROM public.wallets WHERE owner_user_id=v_cust2 AND party_type='client';
    SELECT count(*) INTO v_j0   FROM public.ledger_journals;
    SELECT count(*) INTO v_ntx0 FROM public.wallet_transactions;
    v_tx_replay := NULL; v_err := 'NO_ERROR';
    BEGIN v_tx_replay := public.wallet_topup_om_credit(v_evid, v_tr2.id);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; v_tx_replay := NULL; END;
    SELECT balance_gnf INTO v_bal1 FROM public.wallets WHERE owner_user_id=v_cust3 AND party_type='client';
    SELECT balance_gnf INTO v_w1   FROM public.wallets WHERE owner_user_id=v_cust2 AND party_type='client';
    SELECT count(*) INTO v_j1   FROM public.ledger_journals;
    SELECT count(*) INTO v_ntx1 FROM public.wallet_transactions;
    SELECT matched_topup_request_id, matched_user_id INTO v_mrq, v_mru
      FROM public.payment_provider_events WHERE id = v_evid;

    r := r || public._qa_s13_ok('D8.1 replaying a credited receipt against another customer returns exactly the original transaction',
      v_err = 'NO_ERROR' AND v_tx_replay.id = v_tx_orig.id
      AND v_tx_replay.amount_gnf = v_tx_orig.amount_gnf
      AND v_tx_replay.to_wallet_id = v_tx_orig.to_wallet_id,
      format('err=%s replay_tx=%s original_tx=%s', v_err, v_tx_replay.id, v_tx_orig.id));
    r := r || public._qa_s13_ok('D8.2 the receipt stays bound to its original request and original payer',
      v_mrq = v_tr.id AND v_mru = v_cust2,
      format('matched_request=%s matched_user=%s', v_mrq, v_mru));
    r := r || public._qa_s13_ok('D8.3 the second customer request is still uncredited with no transaction attached',
      (SELECT status::text FROM public.topup_requests WHERE id=v_tr2.id) <> 'credited'
      AND (SELECT transaction_id FROM public.topup_requests WHERE id=v_tr2.id) IS NULL,
      (SELECT status::text FROM public.topup_requests WHERE id=v_tr2.id));
    r := r || public._qa_s13_ok('D8.4 the second customer wallet moved exactly zero GNF',
      v_bal1 = v_bal0, format('delta=%s', v_bal1-v_bal0));
    r := r || public._qa_s13_ok('D8.5 the original customer wallet moved no additional GNF on replay',
      v_w1 = v_w0, format('delta=%s', v_w1-v_w0));
    r := r || public._qa_s13_ok('D8.6 the replay created no new wallet transaction and no new ledger journal',
      v_ntx1 = v_ntx0 AND v_j1 = v_j0,
      format('tx %s->%s journals %s->%s', v_ntx0, v_ntx1, v_j0, v_j1));
    SELECT count(*) INTO v_n FROM public.wallet_transactions
     WHERE type='topup' AND (metadata->>'event_id') = v_evid::text;
    r := r || public._qa_s13_ok('D8.7 the provider reference remains associated with exactly one logical credit',
      v_n = 1, format('credits=%s', v_n));

    -- D8F: a FRESH, uncredited receipt manually pointed at another customer's request.
    v_code := 'OM'||v_sfx||'D8F';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust3), true);
    v_tr3 := public.wallet_topup_om_create(140000, v_acct);
    PERFORM public.submit_customer_om_code(v_tr3.id, v_code);
    PERFORM set_config('request.jwt.claims','',true);
    INSERT INTO public.payment_provider_events(provider, event_type, provider_transaction_id, payer_phone,
      amount_gnf, currency, status, raw_payload, processing_status, om_code_normalized,
      receiving_account_id, is_sandbox, environment)
    VALUES ('orange_money','payment', 'PTX'||v_sfx||'D8F', '+224620000502',
      140000, 'GNF', 'successful', jsonb_build_object('source','qa'), 'received',
      public.normalize_om_code(v_code), v_acct, false, 'production')
    RETURNING id INTO v_ev2;
    SELECT balance_gnf INTO v_bal0 FROM public.wallets WHERE owner_user_id=v_cust3 AND party_type='client';
    v_err := 'NO_ERROR';
    BEGIN PERFORM public.wallet_topup_om_credit(v_ev2, v_tr3.id);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT balance_gnf INTO v_bal1 FROM public.wallets WHERE owner_user_id=v_cust3 AND party_type='client';
    r := r || public._qa_s13_ok('D8F a fresh receipt whose payer is a different customer is refused at credit time',
      v_err = 'payer_phone_mismatch' AND v_bal1 = v_bal0,
      format('err=%s delta=%s', v_err, v_bal1-v_bal0));

    -- D8G: the same fresh receipt manually pointed at a driver request of a third party.
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv2), true);
    v_tr2 := public.driver_wallet_topup_om_create(140000, v_acct);
    PERFORM set_config('request.jwt.claims','',true);
    SELECT balance_gnf INTO v_bal0 FROM public.wallets WHERE owner_user_id=v_drv2 AND party_type='driver';
    v_err := 'NO_ERROR';
    BEGIN PERFORM public.wallet_topup_om_credit(v_ev2, v_tr2.id);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT balance_gnf INTO v_bal1 FROM public.wallets WHERE owner_user_id=v_drv2 AND party_type='driver';
    r := r || public._qa_s13_ok('D8G the same fresh receipt cannot be diverted into an unrelated driver request',
      v_err <> 'NO_ERROR' AND v_bal1 = v_bal0, format('err=%s delta=%s', v_err, v_bal1-v_bal0));
    r := r || public._qa_s13_ok('D8H neither diversion attempt left the fresh receipt credited',
      (SELECT processing_status FROM public.payment_provider_events WHERE id=v_ev2) <> 'credited',
      (SELECT processing_status FROM public.payment_provider_events WHERE id=v_ev2));$blk$
    || substr(s, b + length(m2));

  s := replace(s,
    $e0$    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust3), true);
    PERFORM public.submit_customer_om_code(v_tr.id, v_code);
    PERFORM set_config('request.jwt.claims','',true);$e0$,
    $e1$    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust3), true);
    BEGIN PERFORM public.submit_customer_om_code(v_tr.id, v_code);
    EXCEPTION WHEN OTHERS THEN NULL; END;
    PERFORM set_config('request.jwt.claims','',true);$e1$);

  EXECUTE format(
    'CREATE OR REPLACE FUNCTION public._qa_s13_run5() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS %L',
    s);
END
$mig$;

REVOKE ALL ON FUNCTION public._qa_s13_run5() FROM PUBLIC;
REVOKE ALL ON FUNCTION public._qa_s13_run5() FROM anon;
REVOKE ALL ON FUNCTION public._qa_s13_run5() FROM authenticated;
GRANT EXECUTE ON FUNCTION public._qa_s13_run5() TO service_role;