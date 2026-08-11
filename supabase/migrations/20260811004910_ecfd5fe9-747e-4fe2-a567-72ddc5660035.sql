CREATE OR REPLACE FUNCTION public._qa_s6_run5()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  r jsonb := '[]'::jsonb; v_pass int; v_total int; v_n bigint; v_bad text;
BEGIN
  SELECT count(*), COALESCE(string_agg(sig,', '),'') INTO v_n, v_bad FROM (
    SELECT p.oid::regprocedure::text AS sig FROM pg_proc p
     WHERE p.pronamespace='public'::regnamespace
       AND p.proname IN ('_package_economics','_package_dispatch_internal',
             '_package_choppay_hold_internal','_package_choppay_capture_internal',
             '_package_choppay_release_internal','_package_authorize_internal',
             '_package_accept_internal','_package_complete_internal',
             '_package_cancel_release_internal','_package_claim_freeze_internal',
             '_package_collateral_capture_internal','_driver_exact_hold_place_internal',
             '_driver_mission_hold_release_internal')
       AND (has_function_privilege('authenticated', p.oid, 'EXECUTE')
            OR has_function_privilege('anon', p.oid, 'EXECUTE'))) t;
  r := r || public._qa_s5_ok('M1 every internal Envoyer primitive is service_role only', v_n = 0, v_bad);

  SELECT count(*) INTO v_n FROM pg_proc p
   WHERE p.pronamespace='public'::regnamespace
     AND p.proname IN ('_package_authorize_internal','_package_accept_internal',
                       '_package_complete_internal','_package_claim_freeze_internal')
     AND NOT has_function_privilege('service_role', p.oid, 'EXECUTE');
  r := r || public._qa_s5_ok('M2 service_role retains the internal engine', v_n = 0, v_n::text);

  SELECT count(*), COALESCE(string_agg(sig,', '),'') INTO v_n, v_bad FROM (
    SELECT p.oid::regprocedure::text AS sig FROM pg_proc p
     WHERE p.pronamespace='public'::regnamespace
       AND p.proname IN ('package_delivery_create_checkout','package_evidence_register',
             'package_claim_open','package_verify_pickup','package_verify_delivery',
             'package_delivery_cancel','package_delivery_quote')
       AND (NOT has_function_privilege('authenticated', p.oid, 'EXECUTE')
            OR has_function_privilege('anon', p.oid, 'EXECUTE'))) t;
  r := r || public._qa_s5_ok('M3 participant wrappers are authenticated-only', v_n = 0, v_bad);

  SELECT count(*) INTO v_n FROM pg_proc p
   WHERE p.pronamespace='public'::regnamespace AND p.proname='admin_package_claim_resolve'
     AND (has_function_privilege('anon', p.oid, 'EXECUTE')
          OR pg_get_functiondef(p.oid) NOT LIKE '%is_god_admin%');
  r := r || public._qa_s5_ok('M4 claim adjudication is God-Admin gated and closed to anon', v_n = 0, v_n::text);

  SELECT count(*) INTO v_n FROM pg_proc p
   WHERE p.pronamespace='public'::regnamespace
     AND p.proname='package_delivery_create_checkout';
  r := r || public._qa_s5_ok('M5 exactly one checkout entry point remains (no legacy overload)',
    v_n = 1, v_n::text);

  SELECT count(*) INTO v_n FROM storage.buckets WHERE id='package-evidence' AND public = false;
  r := r || public._qa_s5_ok('L1 package-evidence bucket exists and is private', v_n = 1, v_n::text);

  SELECT count(*) INTO v_n FROM pg_policies
   WHERE schemaname='storage' AND tablename='objects'
     AND qual LIKE '%package-evidence%' AND ('anon' = ANY(roles) OR roles = '{public}');
  r := r || public._qa_s5_ok('L2 no anonymous read path to shipment photos', v_n = 0, v_n::text);

  SELECT count(*) INTO v_n FROM pg_policies
   WHERE schemaname='public' AND tablename='package_evidence_photos';
  r := r || public._qa_s5_ok('L3 evidence register carries participant/admin read policies',
    v_n = 3 AND (SELECT relrowsecurity FROM pg_class WHERE oid='public.package_evidence_photos'::regclass),
    v_n::text);

  v_bad := public._qa_s6_l4();
  r := r || public._qa_s5_ok('L4 evidence and runtime tables are read-only for client roles',
    v_bad = '', v_bad);

  SELECT count(*) INTO v_n FROM pg_policies
   WHERE schemaname='public' AND tablename='package_runtime' AND 'anon' = ANY(roles);
  r := r || public._qa_s5_ok('L5 Envoyer financial runtime is closed to anon', v_n = 0, v_n::text);

  SELECT count(*) FILTER (WHERE (x->>'ok')::boolean), count(*) INTO v_pass, v_total
    FROM jsonb_array_elements(r) x;
  RETURN jsonb_build_object('part',5,'total',v_total,'passed',v_pass,'failed',v_total-v_pass,
    'failures',(SELECT COALESCE(jsonb_agg(x),'[]'::jsonb) FROM jsonb_array_elements(r) x
                 WHERE NOT (x->>'ok')::boolean));
END; $$;
REVOKE ALL ON FUNCTION public._qa_s6_run5() FROM PUBLIC, anon, authenticated;

-- Part 3: correct the capture-journal assertion column.
CREATE OR REPLACE FUNCTION public._qa_s6_run3()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  r jsonb := '[]'::jsonb; v_pass int; v_total int;
  v_send uuid; v_poor uuid; v_drv uuid; v_god uuid;
  v_pkg uuid; v_mis uuid; v_rt public.package_runtime; v_q uuid;
  v_j jsonb; v_err text; v_n bigint; v_b bigint; v_h bigint;
  v_master0 bigint; v_master1 bigint; v_master2 bigint; v_pick text; v_del text;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  BEGIN
    v_send := gen_random_uuid(); v_drv := gen_random_uuid();
    v_god := gen_random_uuid(); v_poor := gen_random_uuid();
    PERFORM public._qa_s6_setup(v_send, v_drv, v_god);
    INSERT INTO public.wallets(owner_user_id, party_type, balance_gnf) VALUES (v_poor,'client',50000);

    v_pkg := public._qa_s6_ship(v_send, 400000, 'chop_pay', 'qa-s6-p1');
    SELECT * INTO v_rt FROM public.package_runtime WHERE package_id = v_pkg;
    SELECT mission_id INTO v_mis FROM public.package_deliveries WHERE id = v_pkg;
    SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;

    r := r || public._qa_s5_ok('P1 chop pay customer hold = delivery fee + 1% fee (101000)',
      v_rt.customer_hold_gnf = 101000 AND v_rt.cash_due_gnf = 0,
      format('hold=%s cash_due=%s', v_rt.customer_hold_gnf, v_rt.cash_due_gnf));
    r := r || public._qa_s5_ok('P2 platform fee is 1% of the delivery fee only (1000)',
      v_rt.platform_fee_gnf = 1000, v_rt.platform_fee_gnf::text);
    r := r || public._qa_s5_ok('P3 declared 400000 => collateral 300000, exposure 100000',
      v_rt.collateral_gnf = 300000 AND v_rt.claims_exposure_gnf = 100000,
      format('col=%s exp=%s', v_rt.collateral_gnf, v_rt.claims_exposure_gnf));
    SELECT balance_gnf, held_gnf INTO v_b, v_h FROM public.wallets
     WHERE owner_user_id=v_send AND party_type='client';
    r := r || public._qa_s5_ok('P4 customer funds reserved at authorisation, balance untouched',
      v_b = 5000000 AND v_h = 101000, format('bal=%s held=%s', v_b, v_h));
    r := r || public._qa_s5_ok('P5 digital authorisation recorded on the shipment',
      (SELECT payment_status FROM public.package_deliveries WHERE id=v_pkg) = 'authorized');
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_module='package' AND source_id=v_pkg;
    r := r || public._qa_s5_ok('P6 only the customer hold exists before a courier accepts', v_n = 1, v_n::text);
    r := r || public._qa_s5_ok('P7 explicit rail recorded (tender = chop_pay, never implicit)',
      v_rt.tender = 'chop_pay', v_rt.tender);

    v_q := public._qa_s6_quote(v_poor, 100000);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_poor), true);
    PERFORM public.package_evidence_register(v_q, format('%s/%s/front.jpg', v_poor, v_q), 'item');
    BEGIN
      v_j := public.package_delivery_create_checkout(
        v_q,'QA Destinataire','+224620000001',NULL,NULL,'qa-s6-q1',NULL,'orange_money',false,NULL,
        200000,'chop_pay',true,'Je certifie que la valeur declaree est exacte.');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s5_ok('Q1 insufficient Chop Pay balance refuses the shipment',
      v_err LIKE '%INSUFFICIENT_CHOP_PAY_BALANCE%', v_err);
    SELECT count(*) INTO v_n FROM public.package_runtime;
    r := r || public._qa_s5_ok('Q2 refused Chop Pay shipment leaves no runtime residue', v_n = 1, v_n::text);
    SELECT held_gnf INTO v_h FROM public.wallets WHERE owner_user_id=v_poor AND party_type='client';
    r := r || public._qa_s5_ok('Q3 refused Chop Pay shipment reserves nothing', v_h = 0, v_h::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_claim(v_mis);
    SELECT amount_gnf INTO v_b FROM public.mission_financial_holds
     WHERE source_module='package' AND source_id=v_pkg AND kind='collateral';
    r := r || public._qa_s5_ok('R1 courier collateral is exactly the frozen 300000', v_b = 300000, v_b::text);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_module='package' AND source_id=v_pkg AND kind='platform_fee';
    r := r || public._qa_s5_ok('R2 no courier fee reserve on a Chop Pay shipment (customer pays it)',
      v_n = 0, v_n::text);
    SELECT balance_gnf, held_gnf INTO v_b, v_h FROM public.wallets
     WHERE owner_user_id=v_drv AND party_type='driver';
    r := r || public._qa_s5_ok('R3 courier balance untouched, held = 300000',
      v_b = 5000000 AND v_h = 300000, format('bal=%s held=%s', v_b, v_h));

    SELECT pickup_code, delivery_code INTO v_pick, v_del
      FROM public.package_delivery_secrets WHERE package_id=v_pkg;
    PERFORM public.package_verify_pickup(v_pkg, v_pick);
    v_j := public.package_verify_delivery(v_pkg, v_del, 'QA Destinataire');
    r := r || public._qa_s5_ok('S1 delivery verified on the Chop Pay rail', (v_j->>'ok')::boolean, v_j::text);
    SELECT balance_gnf, held_gnf INTO v_b, v_h FROM public.wallets
     WHERE owner_user_id=v_send AND party_type='client';
    r := r || public._qa_s5_ok('S2 customer charged exactly 101000, nothing left reserved',
      v_b = 4899000 AND v_h = 0, format('bal=%s held=%s', v_b, v_h));
    SELECT balance_gnf, held_gnf INTO v_b, v_h FROM public.wallets
     WHERE owner_user_id=v_drv AND party_type='driver';
    r := r || public._qa_s5_ok('S3 courier receives the full delivery fee digitally (+100000), nothing held',
      v_b = 5100000 AND v_h = 0, format('bal=%s held=%s', v_b, v_h));
    SELECT balance_gnf INTO v_master2 FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s5_ok('S4 platform keeps exactly the 1000 transaction fee',
      v_master2 = v_master1 + 1000, format('before=%s after=%s', v_master1, v_master2));
    SELECT released_gnf, captured_gnf INTO v_b, v_h FROM public.mission_financial_holds
     WHERE source_module='package' AND source_id=v_pkg AND kind='collateral';
    r := r || public._qa_s5_ok('S5 collateral released in full, never captured on a clean delivery',
      v_b = 300000 AND v_h = 0, format('released=%s captured=%s', v_b, v_h));
    SELECT captured_gnf, released_gnf INTO v_b, v_h FROM public.mission_financial_holds
     WHERE source_module='package' AND source_id=v_pkg AND kind='customer_payment';
    r := r || public._qa_s5_ok('S6 customer reservation fully consumed, no residual release',
      v_b = 101000 AND v_h = 0, format('captured=%s released=%s', v_b, v_h));
    SELECT * INTO v_rt FROM public.package_runtime WHERE package_id = v_pkg;
    r := r || public._qa_s5_ok('S7 runtime completed with a digital courier earning of 100000',
      v_rt.state='completed' AND v_rt.driver_earning_gnf = 100000
      AND v_rt.platform_revenue_gnf = 1000, v_rt.state);

    v_j := public.package_verify_delivery(v_pkg, v_del, 'QA Destinataire');
    SELECT balance_gnf INTO v_b FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s5_ok('T1 replayed Chop Pay delivery is inert', v_b = v_master2, v_b::text);
    v_n := public._qa_s6_t2(v_pkg);
    r := r || public._qa_s5_ok('T2 the delivery capture is journalled exactly once', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM (
      SELECT j.id FROM public.ledger_journals j JOIN public.ledger_postings p ON p.journal_id=j.id
       WHERE j.source_module='package' GROUP BY j.id HAVING sum(p.amount_gnf) <> 0 OR count(*) < 2) t;
    r := r || public._qa_s5_ok('T3 every Chop Pay Envoyer journal is balanced', v_n=0, v_n::text);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_module='package' AND captured_gnf + released_gnf > amount_gnf;
    r := r || public._qa_s5_ok('T4 no hold over-captured or over-released', v_n=0, v_n::text);

    RAISE EXCEPTION 'QA_S6_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_S6_ROLLBACK' THEN
      r := r || public._qa_s5_ok('HARNESS_PART3_UNEXPECTED_ABORT', false, SQLERRM);
    END IF;
  END;

  SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
  r := r || public._qa_s5_ok('Z1 master wallet naturally restored by rollback',
    v_master1 = v_master0, v_master1::text);
  SELECT count(*) INTO v_n FROM public.package_runtime;
  r := r || public._qa_s5_ok('Z2 no runtime residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.feature_flags
   WHERE enabled AND key IN ('envoyer_enabled','envoyer_declared_value_enabled',
                             'envoyer_claims_enabled','chop_pay_checkout_enabled');
  r := r || public._qa_s5_ok('Z3 Slice 6 flags restored to OFF', v_n = 0, v_n::text);

  SELECT count(*) FILTER (WHERE (x->>'ok')::boolean), count(*) INTO v_pass, v_total
    FROM jsonb_array_elements(r) x;
  RETURN jsonb_build_object('part',3,'total',v_total,'passed',v_pass,'failed',v_total-v_pass,
    'failures',(SELECT COALESCE(jsonb_agg(x),'[]'::jsonb) FROM jsonb_array_elements(r) x
                 WHERE NOT (x->>'ok')::boolean));
END; $$;
REVOKE ALL ON FUNCTION public._qa_s6_run3() FROM PUBLIC, anon, authenticated;