DO $mig$
DECLARE
  src text; nsrc text; p1 int; p2 int;
  m_start text; m_end text; new_a11 text;
  old_decl text; new_decl text; old_c7 text; new_c7 text;
  anchor_om text; add_om text; anchor_r text; add_r text; old_b13 text; new_b13 text;
BEGIN
  SELECT prosrc INTO src FROM pg_proc WHERE proname = '_qa_s13_run7' AND pronamespace = 'public'::regnamespace;
  IF src IS NULL THEN RAISE EXCEPTION 'harness _qa_s13_run7 not found'; END IF;
  nsrc := src;

  ---------------------------------------------------------------- declarations
  old_decl := '  v_ptx public.wallet_transactions;';
  new_decl := '  v_ptx public.wallet_transactions;
  v_tr public.topup_requests;
  v_ovd0 jsonb; v_ovd1 jsonb; v_dstate text; v_dbasis bigint; v_dbps int;
  v_rest uuid; v_fo uuid; v_fmis uuid; v_lst uuid; v_mo1 uuid; v_mo2 uuid; v_mmis uuid;
  v_e jsonb; v_pay bigint; v_pay0 bigint; v_held bigint; v_obj text; v_probe jsonb;';
  IF position(old_decl in nsrc) = 0 THEN RAISE EXCEPTION 'decl anchor missing'; END IF;
  nsrc := replace(nsrc, old_decl, new_decl);

  ---------------------------------------------------------------- A11 rebuild
  m_start := '    PERFORM public._qa_s13_flag(''cancellation_policy_enabled'', true);';
  m_end := '    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_c2), true);
    SELECT balance_gnf INTO v_b0 FROM public.wallets WHERE owner_user_id=v_c2 AND party_type=''client'';';
  p1 := position(m_start in nsrc);
  p2 := position(m_end in nsrc);
  IF p1 = 0 OR p2 = 0 OR p2 <= p1 THEN RAISE EXCEPTION 'A11 boundaries missing (%,%)', p1, p2; END IF;
  new_a11 := '    PERFORM public._qa_s13_flag(''cancellation_policy_enabled'', true);
    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_god), true);
    v_ovd0 := public.finance_treasury_overview();
    PERFORM set_config(''request.jwt.claims'','''',true);
    v_res := public.customer_cancellation_debt_create(''qa_s13_p7'', gen_random_uuid(), v_c2,
             ''ride'', ''after_dispatch'', 100000, 0, 0, false, ''customer'', false, NULL);
    v_debt := (v_res->>''debt_id'')::uuid;
    SELECT amount_gnf, basis_gnf, applied_bps, state
      INTO v_debt_amt, v_dbasis, v_dbps, v_dstate
      FROM public.customer_cancellation_debts WHERE id = v_debt;
    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_god), true);
    v_ovd1 := public.finance_treasury_overview();
    PERFORM set_config(''request.jwt.claims'','''',true);
    r := r || public._qa_s13_ok(''A11.1 the created cancellation debt persists the canonical basis, rate and charge'',
      v_debt IS NOT NULL AND v_dbasis = 100000 AND v_dbps = 1000 AND v_debt_amt = 10000,
      format(''basis=%s bps=%s amount=%s state=%s'', v_dbasis, v_dbps, v_debt_amt, v_dstate));
    r := r || public._qa_s13_ok(''A11.2 the new debt is persisted as an open charged receivable, never pre-settled'',
      v_dstate IN (''open'',''charged''), COALESCE(v_dstate,''null''));
    r := r || public._qa_s13_ok(''A11.3 the cancellation receivable rises by exactly the charged debt against the immediately preceding snapshot'',
      (v_ovd1->>''cancellation_debt_receivable_gnf'')::bigint
        - (v_ovd0->>''cancellation_debt_receivable_gnf'')::bigint = 10000,
      format(''%s -> %s'', v_ovd0->>''cancellation_debt_receivable_gnf'', v_ovd1->>''cancellation_debt_receivable_gnf''));
    r := r || public._qa_s13_ok(''A11.4 creating the debt creates no cash, no provider asset and no captured revenue'',
      (v_ovd1->>''captured_revenue_gnf'')::bigint = (v_ovd0->>''captured_revenue_gnf'')::bigint
      AND (v_ovd1->>''verified_assets_gnf'')::bigint = (v_ovd0->>''verified_assets_gnf'')::bigint
      AND (v_ovd1->>''om_inbound_credited_gnf'')::bigint = (v_ovd0->>''om_inbound_credited_gnf'')::bigint,
      format(''rev %s->%s assets %s->%s'',
        v_ovd0->>''captured_revenue_gnf'', v_ovd1->>''captured_revenue_gnf'',
        v_ovd0->>''verified_assets_gnf'', v_ovd1->>''verified_assets_gnf''));

';
  nsrc := left(nsrc, p1 - 1) || new_a11 || substr(nsrc, p2);

  ---------------------------------------------------------------- C7 provenance
  old_c7 := '    SELECT count(*) INTO v_n FROM public.payout_provider_evidence
     WHERE payout_order_id = v_ord AND evidence_source = ''finance_manual_om'' AND provider_verified = false;
    r := r || public._qa_s13_ok(''C7 manual evidence is stored as operator-attested and never as provider-verified'',
      v_n = 1, v_n::text);';
  new_c7 := '    SELECT count(*) INTO v_n FROM public.payout_provider_evidence
     WHERE payout_order_id = v_ord
       AND raw->>''source'' = ''finance_manual_om''
       AND raw->>''evidence_kind'' = ''manual_operator_attested''
       AND (raw->>''provider_verified'')::boolean = false
       AND NULLIF(raw->>''attested_by'','''') IS NOT NULL
       AND recorded_by IS NOT NULL;
    r := r || public._qa_s13_ok(''C7 manual evidence is stored as operator-attested, traceable, and never as provider-verified'',
      v_n = 1, (SELECT COALESCE(raw::text,''none'') FROM public.payout_provider_evidence
                 WHERE payout_order_id = v_ord LIMIT 1));';
  IF position(old_c7 in nsrc) = 0 THEN RAISE EXCEPTION 'C7 anchor missing'; END IF;
  nsrc := replace(nsrc, old_c7, new_c7);

  ---------------------------------------------------------------- OM admin-first ordering
  anchor_om := '    r := r || public._qa_s13_ok(''C16 at most one wallet transaction exists for the credited top-up'',
      v_n <= 1, v_n::text);
';
  IF position(anchor_om in nsrc) = 0 THEN RAISE EXCEPTION 'C16 anchor missing'; END IF;
  add_om := anchor_om || '
    r := r || public._qa_s13_ok(''C14b the ordering exercised above is user-first: the request and code precede the provider receipt'',
      (v_case->>''topup_id'') IS NOT NULL AND COALESCE(v_case->>''status'','''') = ''credited'', v_case->>''status'');

    -- admin-first ordering: Finance records the provider receipt BEFORE the user pastes the code
    v_code := ''P7AF''||v_sfx;
    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_god), true);
    v_res := public.admin_record_om_receipt(v_code, 60000, v_phone2, v_acct, ''qa s13 p7 admin-first'');
    SELECT balance_gnf INTO v_b0 FROM public.wallets WHERE owner_user_id=v_c2 AND party_type=''client'';
    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_c2), true);
    v_tr := public.wallet_topup_om_create(60000, v_acct);
    v_res := public.submit_customer_om_code(v_tr.id, v_code);
    SELECT balance_gnf INTO v_b1 FROM public.wallets WHERE owner_user_id=v_c2 AND party_type=''client'';
    SELECT status::text INTO v_err FROM public.topup_requests WHERE id = v_tr.id;
    r := r || public._qa_s13_ok(''C14c the admin-first ordering credits the customer exactly once when the code arrives second'',
      v_b1 - v_b0 = 60000 AND v_err = ''credited'', format(''%s -> %s status=%s %s'', v_b0, v_b1, v_err, v_res::text));
    BEGIN v_res := public.submit_customer_om_code(v_tr.id, v_code); v_err := ''NO_ERROR'';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT balance_gnf INTO v_b0 FROM public.wallets WHERE owner_user_id=v_c2 AND party_type=''client'';
    r := r || public._qa_s13_ok(''C14d replaying the admin-first code submission moves zero additional GNF'',
      v_b0 = v_b1, format(''%s (%s)'', v_b0, v_err));
    SELECT count(*) INTO v_n FROM public.wallet_transactions
     WHERE metadata->>''topup_request_id'' = v_tr.id::text;
    r := r || public._qa_s13_ok(''C14e the admin-first top-up produced exactly one wallet transaction'',
      v_n = 1, v_n::text);
    PERFORM set_config(''request.jwt.claims'','''',true);
';
  nsrc := replace(nsrc, anchor_om, add_om);

  ---------------------------------------------------------------- Repas / Marche retry seams
  anchor_r := '    ---------------------------------------------------------------- Orange Money inbound replay + sandbox isolation';
  IF position(anchor_r in nsrc) = 0 THEN RAISE EXCEPTION 'OM section anchor missing'; END IF;
  add_r := '    ---------------------------------------------------------------- R. Repas / Marche order retry + lifecycle seams
    PERFORM public._qa_s13_flag(''cash_order_funding_enabled'', true);
    PERFORM public._qa_s13_flag(''chop_pay_enabled'', true);
    PERFORM public._qa_s13_flag(''chop_pay_checkout_enabled'', true);
    UPDATE public.merchant_stores SET status=''active'', merchant_status=''active'', onboarding_status=''approved''
     WHERE id = v_s1;
    UPDATE public.driver_profiles
       SET capabilities = ARRAY[''rides_moto'',''repas_delivery'',''marche_delivery'',''package_delivery'']
     WHERE user_id IN (v_d1, v_d2);
    INSERT INTO public.food_restaurants(slug, name, merchant_store_id, owner_user_id, status)
    VALUES (''qa-s13-p7-resto-''||lower(v_sfx),''QA S13 P7 Resto'', v_s1, v_m1, ''active'')
    RETURNING id INTO v_rest;

    INSERT INTO public.food_orders(user_id, restaurant_id, subtotal_gnf, payment_method, state, fulfillment)
    VALUES (v_c1, v_rest, 50000, ''cash'', ''placed'', ''delivery'') RETURNING id INTO v_fo;
    INSERT INTO public.missions(type, customer_id, ref_food_order_id, estimated_earning_gnf, state, courier_id)
    VALUES (''food_delivery'', v_c1, v_fo, 10000, ''assigned'', v_d2) RETURNING id INTO v_fmis;

    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_d2), true);
    BEGIN v_res := public.cash_order_accept(''repas'', v_fo); v_err := ''NO_ERROR'';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT COALESCE(sum(amount_gnf),0) INTO v_held FROM public.mission_financial_holds
     WHERE source_id = v_fo AND kind = ''cash_funding'';
    r := r || public._qa_s13_ok(''R1.1 a Repas cash acceptance places exactly one merchandise funding hold'',
      v_err = ''NO_ERROR'' AND v_held = 50000, format(''%s hold=%s'', v_err, v_held));
    BEGIN v_res := public.cash_order_accept(''repas'', v_fo); EXCEPTION WHEN OTHERS THEN NULL; END;
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_id = v_fo AND kind = ''cash_funding'';
    SELECT count(*) INTO v_b FROM public.cash_order_runtime WHERE source_id = v_fo;
    r := r || public._qa_s13_ok(''R1.2 retrying the same Repas acceptance creates no second hold and no second runtime'',
      v_n = 1 AND v_b = 1, format(''holds=%s runtime=%s'', v_n, v_b));

    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_m1), true);
    BEGIN v_res := public.cash_order_merchant_accept(''repas'', v_fo); v_err := ''NO_ERROR'';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT COALESCE(funded_gnf,0) INTO v_pay FROM public.merchant_payables
     WHERE source_module=''repas'' AND source_id = v_fo;
    r := r || public._qa_s13_ok(''R1.3 merchant acceptance funds the Repas payable exactly once'',
      v_err = ''NO_ERROR'' AND v_pay = 50000, format(''%s funded=%s'', v_err, v_pay));
    BEGIN v_res := public.cash_order_merchant_accept(''repas'', v_fo); EXCEPTION WHEN OTHERS THEN NULL; END;
    SELECT COALESCE(sum(funded_gnf),0), count(*) INTO v_pay0, v_n FROM public.merchant_payables
     WHERE source_module=''repas'' AND source_id = v_fo;
    r := r || public._qa_s13_ok(''R1.4 replaying merchant acceptance funds nothing more and creates no second payable'',
      v_pay0 = v_pay AND v_n = 1, format(''%s vs %s rows=%s'', v_pay0, v_pay, v_n));

    BEGIN v_res := public.cash_order_merchant_prepare(''repas'', v_fo); v_err := ''NO_ERROR'';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok(''R2.1 preparation is allowed only once the merchandise funding is secured'',
      v_err = ''NO_ERROR'', v_err);
    SELECT balance_gnf INTO v_mw0 FROM public.wallets WHERE party_type=''master'' LIMIT 1;
    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_c1), true);
    BEGIN PERFORM public.cash_order_customer_cancel(''repas'', v_fo, ''qa p7''); v_err := ''NO_ERROR'';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok(''R2.2 the kitchen preparation state forbids a Repas customer cancellation'',
      v_err <> ''NO_ERROR'', v_err);
    BEGIN PERFORM public.cash_order_customer_cancel(''repas'', v_fo, ''qa p7 retry''); v_err := ''NO_ERROR'';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT balance_gnf INTO v_mw1 FROM public.wallets WHERE party_type=''master'' LIMIT 1;
    SELECT count(*) INTO v_n FROM public.customer_cancellation_debts
     WHERE source_module=''repas'' AND source_id = v_fo;
    r := r || public._qa_s13_ok(''R2.3 retrying the refused Repas cancellation moves zero GNF and creates no fee or debt'',
      v_err <> ''NO_ERROR'' AND v_mw1 = v_mw0 AND v_n = 0,
      format(''%s master=%s debts=%s'', v_err, v_mw1, v_n));

    UPDATE public.missions SET pickup_confirmed_at = now(), state=''picked_up'' WHERE id = v_fmis;
    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_d2), true);
    SELECT balance_gnf INTO v_mw0 FROM public.wallets WHERE party_type=''master'' LIMIT 1;
    BEGIN v_res := public.cash_order_complete_cash(''repas'', v_fo); v_err := ''NO_ERROR'';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT balance_gnf INTO v_mw1 FROM public.wallets WHERE party_type=''master'' LIMIT 1;
    r := r || public._qa_s13_ok(''R2.4 Repas cash completion captures exactly the one percent platform fee once'',
      v_err = ''NO_ERROR'' AND v_mw1 - v_mw0 = 500, format(''%s %s -> %s'', v_err, v_mw0, v_mw1));
    BEGIN v_res := public.cash_order_complete_cash(''repas'', v_fo); EXCEPTION WHEN OTHERS THEN NULL; END;
    SELECT balance_gnf INTO v_b0 FROM public.wallets WHERE party_type=''master'' LIMIT 1;
    r := r || public._qa_s13_ok(''R2.5 replaying the Repas cash completion captures zero additional GNF'',
      v_b0 = v_mw1, format(''%s vs %s'', v_b0, v_mw1));

    INSERT INTO public.marketplace_listings(seller_id, category, title)
    VALUES (v_m1, ''divers'', ''QA S13 P7 Article'') RETURNING id INTO v_lst;
    INSERT INTO public.marketplace_offers(listing_id, merchant_store_id, buyer_user_id, merchant_user_id,
      offer_amount_gnf, status, metadata)
    VALUES (v_lst, v_s1, v_c1, v_m1, 60000, ''accepted'', ''{"payment_method":"cash"}''::jsonb)
    RETURNING id INTO v_mo1;
    INSERT INTO public.missions(type, customer_id, ref_market_order_id, estimated_earning_gnf, state, courier_id)
    VALUES (''marketplace_delivery'', v_c1, v_mo1, 12000, ''assigned'', v_d2) RETURNING id INTO v_mmis;
    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_d2), true);
    BEGIN v_res := public.cash_order_accept(''marche'', v_mo1); v_err := ''NO_ERROR'';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT COALESCE(sum(amount_gnf),0) INTO v_held FROM public.mission_financial_holds
     WHERE source_id = v_mo1 AND kind=''cash_funding'';
    r := r || public._qa_s13_ok(''R3.1 a Marche cash acceptance funds exactly the merchandise amount'',
      v_err = ''NO_ERROR'' AND v_held = 60000, format(''%s hold=%s'', v_err, v_held));
    SELECT balance_gnf INTO v_b0 FROM public.wallets WHERE owner_user_id=v_d2 AND party_type=''driver'';
    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_m1), true);
    BEGIN v_res := public.cash_order_merchant_reject(''marche'', v_mo1, ''qa p7''); v_err := ''NO_ERROR'';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT COALESCE(sum(GREATEST(amount_gnf - captured_gnf - released_gnf,0)),0) INTO v_held
      FROM public.mission_financial_holds WHERE source_id = v_mo1 AND kind=''cash_funding'';
    SELECT balance_gnf INTO v_b1 FROM public.wallets WHERE owner_user_id=v_d2 AND party_type=''driver'';
    r := r || public._qa_s13_ok(''R3.2 the canonical merchant rejection releases the courier funding exactly once'',
      v_err = ''NO_ERROR'' AND v_held = 0 AND v_b1 = v_b0, format(''%s open=%s bal=%s'', v_err, v_held, v_b1));
    BEGIN v_res := public.cash_order_merchant_reject(''marche'', v_mo1, ''qa p7 replay''); v_err := ''NO_ERROR'';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; v_res := ''{}''::jsonb; END;
    SELECT balance_gnf INTO v_b0 FROM public.wallets WHERE owner_user_id=v_d2 AND party_type=''driver'';
    r := r || public._qa_s13_ok(''R3.3 replaying the rejection is inert and moves zero GNF'',
      COALESCE(v_res->>''status'','''') = ''already_rejected'' AND v_b0 = v_b1,
      format(''%s bal=%s %s'', v_err, v_b0, v_res::text));

    INSERT INTO public.marketplace_offers(listing_id, merchant_store_id, buyer_user_id, merchant_user_id,
      offer_amount_gnf, status, metadata)
    VALUES (v_lst, v_s1, v_c1, v_m1, 60000, ''accepted'', ''{"payment_method":"choppay"}''::jsonb)
    RETURNING id INTO v_mo2;
    INSERT INTO public.missions(type, customer_id, ref_market_order_id, estimated_earning_gnf, state)
    VALUES (''marketplace_delivery'', v_c1, v_mo2, 12000, ''assigned'') RETURNING id INTO v_mmis;
    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_c1), true);
    SELECT balance_gnf, held_gnf INTO v_b0, v_held FROM public.wallets
     WHERE owner_user_id=v_c1 AND party_type=''client'';
    BEGIN v_res := public.chop_pay_authorize_order(''marche'', v_mo2); v_err := ''NO_ERROR'';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT balance_gnf, held_gnf INTO v_b1, v_n FROM public.wallets
     WHERE owner_user_id=v_c1 AND party_type=''client'';
    r := r || public._qa_s13_ok(''R4.1 a Chop Pay authorization holds customer funds without spending them'',
      v_err = ''NO_ERROR'' AND v_b1 = v_b0 AND v_n > v_held,
      format(''%s bal=%s held %s->%s'', v_err, v_b1, v_held, v_n));
    BEGIN v_res := public.chop_pay_authorize_order(''marche'', v_mo2); EXCEPTION WHEN OTHERS THEN NULL; END;
    SELECT balance_gnf, held_gnf INTO v_b0, v_b FROM public.wallets
     WHERE owner_user_id=v_c1 AND party_type=''client'';
    SELECT count(*) INTO v_pay0 FROM public.chop_pay_order_runtime WHERE source_id = v_mo2;
    r := r || public._qa_s13_ok(''R4.2 duplicate Chop Pay authorization double-holds nothing and creates no second runtime'',
      v_b = v_n AND v_b0 = v_b1 AND v_pay0 = 1, format(''held=%s bal=%s runtime=%s'', v_b, v_b0, v_pay0));

    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_m1), true);
    SELECT COALESCE(sum(funded_gnf),0) INTO v_pay0 FROM public.merchant_payables
     WHERE source_module=''marche'' AND source_id = v_mo2;
    BEGIN v_res := public.chop_pay_merchant_accept(''marche'', v_mo2); v_err := ''NO_ERROR'';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT COALESCE(sum(funded_gnf),0) INTO v_pay FROM public.merchant_payables
     WHERE source_module=''marche'' AND source_id = v_mo2;
    r := r || public._qa_s13_ok(''R4.3 the Chop Pay merchant capture funds exactly the merchandise amount'',
      v_err = ''NO_ERROR'' AND v_pay - v_pay0 = 60000, format(''%s %s -> %s'', v_err, v_pay0, v_pay));
    SELECT count(*) INTO v_n FROM public.ledger_journals WHERE source_id = v_mo2;
    BEGIN v_res := public.chop_pay_merchant_accept(''marche'', v_mo2); EXCEPTION WHEN OTHERS THEN NULL; END;
    SELECT COALESCE(sum(funded_gnf),0) INTO v_pay0 FROM public.merchant_payables
     WHERE source_module=''marche'' AND source_id = v_mo2;
    SELECT count(*) INTO v_b FROM public.ledger_journals WHERE source_id = v_mo2;
    r := r || public._qa_s13_ok(''R4.4 replaying the Chop Pay capture moves zero GNF and posts no duplicate journal'',
      v_pay0 = v_pay AND v_b = v_n, format(''funded=%s journals %s -> %s'', v_pay0, v_n, v_b));

    PERFORM set_config(''request.jwt.claims'', public._as_user_claims(v_c1), true);
    BEGIN v_res := public.chop_pay_customer_cancel(''marche'', v_mo2, ''qa p7''); v_err := ''NO_ERROR'';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; v_res := ''{}''::jsonb; END;
    SELECT COALESCE(sum(funded_gnf),0) INTO v_pay0 FROM public.merchant_payables
     WHERE source_module=''marche'' AND source_id = v_mo2 AND state <> ''reversed'';
    r := r || public._qa_s13_ok(''R4.5 the canonical cancellation reverses the merchant capture exactly once'',
      v_err = ''NO_ERROR'' AND v_pay0 = 0, format(''%s remaining=%s %s'', v_err, v_pay0, v_res::text));
    SELECT balance_gnf INTO v_b0 FROM public.wallets WHERE owner_user_id=v_c1 AND party_type=''client'';
    BEGIN v_res := public.chop_pay_customer_cancel(''marche'', v_mo2, ''qa p7 replay''); v_err := ''NO_ERROR'';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; v_res := ''{}''::jsonb; END;
    SELECT balance_gnf INTO v_b1 FROM public.wallets WHERE owner_user_id=v_c1 AND party_type=''client'';
    SELECT count(*) INTO v_n FROM public.customer_cancellation_debts
     WHERE source_module=''marche'' AND source_id = v_mo2;
    r := r || public._qa_s13_ok(''R4.6 retrying the cancellation is inert with no duplicate fee, debt or capture'',
      COALESCE(v_res->>''status'','''') = ''already_cancelled'' AND v_b1 = v_b0 AND v_n <= 1,
      format(''%s bal=%s debts=%s'', v_res->>''status'', v_b1, v_n));
    PERFORM set_config(''request.jwt.claims'','''',true);

' || anchor_r;
  nsrc := replace(nsrc, anchor_r, add_r);

  ---------------------------------------------------------------- Envoyer storage isolation
  old_b13 := '    SELECT count(*) INTO v_n FROM storage.buckets WHERE id=''package-evidence'' AND public = false;
    r := r || public._qa_s13_ok(''B13 the Envoyer evidence bucket is private'', v_n = 1, v_n::text);';
  IF position(old_b13 in nsrc) = 0 THEN RAISE EXCEPTION 'B13 anchor missing'; END IF;
  new_b13 := old_b13 || '

    v_obj := v_c1::text||''/''||v_qid::text||''/p1.jpg'';
    INSERT INTO storage.objects(bucket_id, name, owner, owner_id, metadata)
    VALUES (''package-evidence'', v_obj, v_c1, v_c1::text, ''{"size":1024}''::jsonb)
    ON CONFLICT DO NOTHING;
    v_probe := public._qa_s13_rls_probe(''authenticated'', v_c1, ''select'', ''package-evidence'', v_obj);
    r := r || public._qa_s13_ok(''B14 the owning sender can still read their own package evidence object'',
      (v_probe->>''count'')::bigint = 1 AND v_probe->>''error'' = ''NO_ERROR'', v_probe::text);
    v_probe := public._qa_s13_rls_probe(''authenticated'', v_c2, ''select'', ''package-evidence'', v_obj);
    r := r || public._qa_s13_ok(''B15 another signed-in customer cannot read the sender package evidence object'',
      COALESCE((v_probe->>''count'')::bigint,0) = 0, v_probe::text);
    v_probe := public._qa_s13_rls_probe(''anon'', NULL, ''select'', ''package-evidence'', v_obj);
    r := r || public._qa_s13_ok(''B16 an anonymous caller cannot read the package evidence object'',
      COALESCE((v_probe->>''count'')::bigint,0) = 0, v_probe::text);
    v_probe := public._qa_s13_rls_probe(''authenticated'', v_c2, ''photos'', ''package-evidence'', v_obj);
    r := r || public._qa_s13_ok(''B17 another signed-in customer cannot read the evidence metadata row'',
      COALESCE((v_probe->>''count'')::bigint,0) = 0, v_probe::text);';
  nsrc := replace(nsrc, old_b13, new_b13);

  IF nsrc = src THEN RAISE EXCEPTION 'no harness change produced'; END IF;

  EXECUTE format(
    'CREATE OR REPLACE FUNCTION public._qa_s13_run7() RETURNS jsonb LANGUAGE plpgsql SET search_path TO ''public'' AS $f$%s$f$',
    nsrc);
END
$mig$;

REVOKE ALL ON FUNCTION public._qa_s13_run7() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_s13_run7() TO service_role;