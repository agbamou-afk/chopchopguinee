CREATE OR REPLACE FUNCTION public._qa_s13_run4()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_cust uuid; v_drv uuid; v_god uuid; v_sfx text;
  v_err text; v_n bigint; v_res jsonb; v_q jsonb; v_qid uuid; v_fee bigint;
  v_pkg uuid; v_mis uuid; v_rt public.package_runtime;
  v_pkg2 uuid; v_mis2 uuid; v_rt2 public.package_runtime; v_qid2 uuid;
  v_master0 bigint; v_master1 bigint; v_flags0 jsonb; v_flags1 jsonb;
  v_bal0 bigint; v_bal1 bigint; v_held bigint; v_mw0 bigint; v_mw bigint;
  v_pcode text; v_dcode text; v_claim uuid; v_auth bigint; v_state text;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;

  BEGIN
    v_cust := gen_random_uuid(); v_drv := gen_random_uuid(); v_god := gen_random_uuid();
    v_sfx := substr(replace(gen_random_uuid()::text,'-',''),1,10);
    PERFORM public._qa_s13_user(v_cust,'ec'); PERFORM public._qa_s13_user(v_drv,'ed');
    PERFORM public._qa_s13_user(v_god,'eg');
    INSERT INTO public.user_roles(user_id, role) VALUES (v_god,'god_admin') ON CONFLICT DO NOTHING;
    INSERT INTO public.driver_profiles(user_id,status,vehicle_type,id_doc_url,vehicle_photo_url)
    VALUES (v_drv,'approved','moto','x','y')
    ON CONFLICT (user_id) DO UPDATE SET status='approved';
    UPDATE public.driver_profiles
       SET capabilities = ARRAY['rides_moto','repas_delivery','marche_delivery','package_delivery']
     WHERE user_id = v_drv;
    PERFORM public._qa_s13_wallet(v_cust,'client',900000,0);
    PERFORM public._qa_s13_wallet(v_drv,'driver',900000,0);

    PERFORM public._qa_s13_flag('envoyer_enabled', true);
    PERFORM public._qa_s13_flag('envoyer_declared_value_enabled', true);
    PERFORM public._qa_s13_flag('envoyer_claims_enabled', true);
    PERFORM public._qa_s13_flag('chop_pay_enabled', true);
    PERFORM public._qa_s13_flag('chop_pay_checkout_enabled', true);
    PERFORM public._qa_s13_flag('driver_balance_gate_enabled', true);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);

    -- ---------- F1: declared-value gates ----------
    v_q := public.package_delivery_quote(9.5370, -13.6785, 9.5560, -13.6600, 'small_parcel', 'A', 'B');
    v_qid := (v_q->>'quote_id')::uuid;
    v_fee := (v_q->>'amount_gnf')::bigint;
    r := r || public._qa_s13_ok('F1.0 Envoyer quote returns a server-priced delivery fee',
      v_qid IS NOT NULL AND v_fee > 0, v_q::text);

    BEGIN v_res := public.package_delivery_create_checkout(v_qid,'Ami Diallo','622000001',
      NULL,NULL,'k1-'||v_sfx,'622000002','orange_money',false,NULL, 500000, NULL, true,
      'Je declare la valeur de mon colis'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('F1.1 shipment without an explicit tender is refused',
      v_err <> 'NO_ERROR', v_err);

    BEGIN v_res := public.package_delivery_create_checkout(v_qid,'Ami Diallo','622000001',
      NULL,NULL,'k2-'||v_sfx,'622000002','orange_money',false,NULL, NULL, 'chop_pay', true,
      'Je declare la valeur de mon colis'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('F1.2 shipment without a declared value is refused',
      v_err <> 'NO_ERROR', v_err);

    BEGIN v_res := public.package_delivery_create_checkout(v_qid,'Ami Diallo','622000001',
      NULL,NULL,'k3-'||v_sfx,'622000002','orange_money',false,NULL, 500000, 'chop_pay', false,
      NULL); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('F1.3 shipment without a value attestation is refused',
      v_err <> 'NO_ERROR', v_err);

    BEGIN v_res := public.package_delivery_create_checkout(v_qid,'Ami Diallo','622000001',
      NULL,NULL,'k4-'||v_sfx,'622000002','orange_money',false,NULL, 500000, 'chop_pay', true,
      'Je declare la valeur de mon colis'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('F1.4 shipment without evidence photos is refused',
      v_err = 'SHIPMENT_PHOTOS_REQUIRED', v_err);

    SELECT count(*) INTO v_n FROM public.package_runtime WHERE customer_user_id = v_cust;
    r := r || public._qa_s13_ok('F1.5 refusals created no shipment runtime, hold or journal',
      v_n = 0, v_n::text);

    PERFORM public.package_evidence_register(v_qid, v_cust::text||'/'||v_qid::text||'/p1.jpg',
      'item','image/jpeg',1024);

    BEGIN v_res := public.package_delivery_create_checkout(v_qid,'Ami Diallo','622000001',
      NULL,NULL,'k5-'||v_sfx,'622000002','orange_money',false,NULL, 999000000, 'chop_pay', true,
      'Je declare la valeur de mon colis'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('F1.6 declared value above the policy ceiling is refused',
      v_err <> 'NO_ERROR', v_err);
    SELECT count(*) INTO v_n FROM public.package_runtime WHERE customer_user_id = v_cust;
    r := r || public._qa_s13_ok('F1.7 ceiling refusal created no shipment', v_n = 0, v_n::text);

    -- ---------- F2: authorized Chop Pay shipment ----------
    BEGIN v_res := public.package_delivery_create_checkout(v_qid,'Ami Diallo','622000001',
      NULL,NULL,'k6-'||v_sfx,'622000002','orange_money',false,NULL, 500000, 'chop_pay', true,
      'Je declare la valeur de mon colis'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; v_res := '{}'::jsonb; END;
    v_pkg := (v_res->>'package_id')::uuid;
    r := r || public._qa_s13_ok('F2.0 fully attested shipment is authorized',
      v_err = 'NO_ERROR' AND v_pkg IS NOT NULL, format('%s %s', v_err, v_res::text));

    SELECT * INTO v_rt FROM public.package_runtime WHERE package_id = v_pkg;
    r := r || public._qa_s13_ok('F2.1 customer holds delivery fee + platform fee only',
      v_rt.customer_hold_gnf = v_rt.delivery_fee_gnf + v_rt.platform_fee_gnf,
      format('hold=%s fee=%s pf=%s', v_rt.customer_hold_gnf, v_rt.delivery_fee_gnf, v_rt.platform_fee_gnf));
    r := r || public._qa_s13_ok('F2.2 declared value is never charged to the customer',
      v_rt.customer_hold_gnf < v_rt.declared_value_gnf, v_rt.customer_hold_gnf::text);
    r := r || public._qa_s13_ok('F2.3 claims exposure never exceeds declared value minus collateral',
      v_rt.claims_exposure_gnf <= GREATEST(v_rt.declared_value_gnf - v_rt.collateral_gnf, 0),
      format('exp=%s dv=%s col=%s', v_rt.claims_exposure_gnf, v_rt.declared_value_gnf, v_rt.collateral_gnf));
    SELECT COALESCE(sum(GREATEST(amount_gnf-captured_gnf-released_gnf,0)),0) INTO v_n
      FROM public.mission_financial_holds
     WHERE source_module = 'package' AND source_id = v_pkg AND kind = 'customer_payment';
    r := r || public._qa_s13_ok('F2.4 customer hold is real and open on the shipment',
      v_n = v_rt.customer_hold_gnf, format('%s vs %s', v_n, v_rt.customer_hold_gnf));

    SELECT mission_id INTO v_mis FROM public.package_deliveries WHERE id = v_pkg;
    r := r || public._qa_s13_ok('F2.5 authorization dispatched a mission', v_mis IS NOT NULL, v_mis::text);

    -- ---------- F3: courier claim + collateral + custody ----------
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    BEGIN PERFORM public.mission_claim(v_mis); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT COALESCE(sum(amount_gnf),0) INTO v_held FROM public.mission_financial_holds
     WHERE source_module = 'package' AND source_id = v_pkg AND kind = 'collateral';
    r := r || public._qa_s13_ok('F3.1 courier collateral hold equals the frozen policy amount',
      v_err = 'NO_ERROR' AND v_held = v_rt.collateral_gnf,
      format('%s hold=%s frozen=%s', v_err, v_held, v_rt.collateral_gnf));

    SELECT pickup_code, delivery_code INTO v_pcode, v_dcode
      FROM public.package_delivery_secrets WHERE package_id = v_pkg;

    v_res := public.package_verify_pickup(v_pkg, '000000');
    r := r || public._qa_s13_ok('F3.2 wrong pickup code never establishes custody',
      COALESCE((v_res->>'ok')::boolean,false) = false, v_res::text);
    SELECT pickup_verified_at IS NULL INTO v_err FROM public.package_delivery_secrets WHERE package_id = v_pkg;
    r := r || public._qa_s13_ok('F3.3 shipment stays pre-custody after a failed code', v_err::boolean, v_err);

    v_res := public.package_verify_pickup(v_pkg, v_pcode);
    r := r || public._qa_s13_ok('F3.4 correct pickup code establishes custody',
      COALESCE((v_res->>'ok')::boolean,false), v_res::text);

    -- ---------- F4: cancellation locked once in custody ----------
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    BEGIN v_res := public.package_delivery_cancel(v_pkg, 'qa cancel test'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; v_res := '{}'::jsonb; END;
    r := r || public._qa_s13_ok('F4.1 self-service cancellation refused once the courier has custody',
      v_err <> 'NO_ERROR' OR COALESCE(v_res->>'error','') = 'CUSTODY_ESTABLISHED_CLAIM_REQUIRED',
      format('%s %s', v_err, v_res::text));
    SELECT cancelled_at IS NULL INTO v_err FROM public.package_deliveries WHERE id = v_pkg;
    r := r || public._qa_s13_ok('F4.2 shipment remains live after the refused cancellation',
      v_err::boolean, v_err);

    -- ---------- F5: delivery + settlement ----------
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    v_res := public.package_verify_delivery(v_pkg, '000000', 'Ami Diallo');
    r := r || public._qa_s13_ok('F5.1 wrong delivery code never completes a shipment',
      COALESCE((v_res->>'ok')::boolean,false) = false, v_res::text);

    SELECT balance_gnf INTO v_bal0 FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    SELECT balance_gnf INTO v_mw0 FROM public.wallets WHERE party_type='master' LIMIT 1;
    v_res := public.package_verify_delivery(v_pkg, v_dcode, 'Ami Diallo');
    SELECT balance_gnf INTO v_bal1 FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    SELECT balance_gnf INTO v_mw FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s13_ok('F5.2 correct delivery code completes the shipment',
      COALESCE((v_res->>'ok')::boolean,false), v_res::text);
    r := r || public._qa_s13_ok('F5.3 courier is paid exactly the delivery fee',
      v_bal1 - v_bal0 = v_rt.delivery_fee_gnf, format('%s -> %s (fee %s)', v_bal0, v_bal1, v_rt.delivery_fee_gnf));
    r := r || public._qa_s13_ok('F5.4 platform fee captured to the master wallet',
      v_mw - v_mw0 = v_rt.platform_fee_gnf, format('%s -> %s (pf %s)', v_mw0, v_mw, v_rt.platform_fee_gnf));
    SELECT COALESCE(sum(GREATEST(amount_gnf-captured_gnf-released_gnf,0)),0) INTO v_n
      FROM public.mission_financial_holds WHERE source_module='package' AND source_id = v_pkg;
    r := r || public._qa_s13_ok('F5.5 no hold survives a completed shipment', v_n = 0, v_n::text);

    v_res := public.package_verify_delivery(v_pkg, v_dcode, 'Ami Diallo');
    SELECT balance_gnf INTO v_n FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    r := r || public._qa_s13_ok('F5.6 duplicate delivery confirmation moves 0 additional GNF',
      v_n = v_bal1, format('%s vs %s', v_n, v_bal1));

    -- ---------- F6: claims on a second shipment still in custody ----------
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_q := public.package_delivery_quote(9.5370, -13.6785, 9.5600, -13.6500, 'small_parcel', 'A', 'C');
    v_qid2 := (v_q->>'quote_id')::uuid;
    PERFORM public.package_evidence_register(v_qid2, v_cust::text||'/'||v_qid2::text||'/p1.jpg',
      'item','image/jpeg',1024);
    v_res := public.package_delivery_create_checkout(v_qid2,'Ami Diallo','622000001',
      NULL,NULL,'k7-'||v_sfx,'622000002','orange_money',false,NULL, 400000, 'chop_pay', true,
      'Je declare la valeur de mon colis');
    v_pkg2 := (v_res->>'package_id')::uuid;
    SELECT * INTO v_rt2 FROM public.package_runtime WHERE package_id = v_pkg2;
    SELECT mission_id INTO v_mis2 FROM public.package_deliveries WHERE id = v_pkg2;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_claim(v_mis2);
    SELECT pickup_code INTO v_pcode FROM public.package_delivery_secrets WHERE package_id = v_pkg2;
    PERFORM public.package_verify_pickup(v_pkg2, v_pcode);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    BEGIN v_res := public.claims_reserve_allocate('package', v_pkg2, 50000, 'evidence/x.jpg',
      'qa reserve before freeze', v_cust, v_drv, 400000, 'envoyer', false); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('F6.1 no reserve can be authorised before the collateral is frozen',
      v_err <> 'NO_ERROR', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    BEGIN v_res := public.package_claim_open(v_pkg2, 'colis endommage'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; v_res := '{}'::jsonb; END;
    SELECT state INTO v_state FROM public.mission_financial_holds
     WHERE source_module='package' AND source_id = v_pkg2 AND kind='collateral';
    r := r || public._qa_s13_ok('F6.2 opening a claim freezes the courier collateral',
      v_err = 'NO_ERROR' AND v_state = 'frozen', format('%s state=%s', v_err, v_state));
    SELECT claim_state INTO v_state FROM public.package_runtime WHERE package_id = v_pkg2;
    r := r || public._qa_s13_ok('F6.3 shipment runtime records the open claim', v_state = 'open', v_state);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    BEGIN v_res := public.claims_reserve_allocate('package', v_pkg2, 50000, 'evidence/x.jpg',
      'qa non admin allocation', v_cust, v_drv, 400000, 'envoyer', false); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('F6.4 only a God Admin can authorise a claims reserve',
      v_err <> 'NO_ERROR', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    v_auth := LEAST(50000, v_rt2.claims_exposure_gnf);
    v_res := public.claims_reserve_allocate('package', v_pkg2, v_auth, 'evidence/x.jpg',
      'qa investigated claim', v_cust, v_drv, 400000, 'envoyer', false);
    SELECT id INTO v_claim FROM public.claims_reserves
     WHERE source_module='package' AND source_id = v_pkg2;
    r := r || public._qa_s13_ok('F6.5 an investigated claim allocates a reserve within the frozen exposure',
      v_claim IS NOT NULL AND v_auth <= v_rt2.claims_exposure_gnf,
      format('%s authorized=%s exposure=%s', v_res::text, v_auth, v_rt2.claims_exposure_gnf));

    SELECT balance_gnf INTO v_bal0 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    BEGIN v_res := public.claims_reserve_resolve(v_claim, v_auth + 5000000, 'qa adjudication test');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; v_res := '{}'::jsonb; END;
    SELECT balance_gnf INTO v_bal1 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('F6.6 a claim can never pay more than the authorized reserve',
      v_err = 'NO_ERROR' AND COALESCE((v_res->>'paid_gnf')::bigint, -1) = v_auth,
      format('%s %s authorized=%s', v_err, v_res::text, v_auth));
    r := r || public._qa_s13_ok('F6.7 the customer is credited exactly the adjudicated amount',
      v_bal1 - v_bal0 = v_auth, format('%s -> %s (auth %s)', v_bal0, v_bal1, v_auth));

    v_res := public.claims_reserve_resolve(v_claim, v_auth, 'qa duplicate adjudication');
    SELECT balance_gnf INTO v_n FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('F6.8 re-adjudicating a resolved claim pays nothing more',
      v_n = v_bal1, format('%s vs %s', v_n, v_bal1));

    -- ---------- ledger integrity ----------
    SELECT count(*) INTO v_n FROM (
      SELECT j.id FROM public.ledger_journals j
       JOIN public.ledger_postings p ON p.journal_id = j.id
       GROUP BY j.id HAVING sum(p.amount_gnf) <> 0) z;
    r := r || public._qa_s13_ok('F7.1 no imbalanced journal after Envoyer fixtures', v_n = 0, v_n::text);
    SELECT COALESCE(sum(amount_gnf),0) INTO v_n FROM public.ledger_postings;
    r := r || public._qa_s13_ok('F7.2 global ledger sum is zero', v_n = 0, v_n::text);

    RAISE EXCEPTION 'QA_S13_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_S13_ROLLBACK' THEN
      r := r || public._qa_s13_ok('HARNESS_PART4_UNEXPECTED_ABORT', false, SQLERRM);
    END IF;
  END;

  PERFORM set_config('request.jwt.claims', '', true);
  SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;
  r := r || public._qa_s13_ok('Z4.1 master wallet unchanged after rollback',
    v_master1 = v_master0, v_master1::text);
  r := r || public._qa_s13_ok('Z4.2 live feature flags byte-identical after fixture rollback',
    v_flags1 = v_flags0, NULL);

  RETURN public._qa_s13_summary(4, r);
END $function$;

REVOKE ALL ON FUNCTION public._qa_s13_run4() FROM PUBLIC, anon, authenticated;

INSERT INTO public._qa_s13_results(part, result) SELECT 4, public._qa_s13_run4();