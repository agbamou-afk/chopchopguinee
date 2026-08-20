CREATE OR REPLACE FUNCTION public._qa_node4_marche_r12()
RETURNS jsonb LANGUAGE plpgsql SET statement_timeout TO '60s' AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_buy uuid; v_merch uuid; v_shop uuid; v_ops uuid; v_fin uuid; v_god uuid;
  v_store uuid; l_a uuid; l_b uuid; v_o1 uuid; v_res jsonb; v_case jsonb;
  v_c_susp uuid; v_c_cat uuid; v_c_price uuid; v_c_fraud uuid; v_c_proc uuid;
  v_c_cust uuid; v_c_shop uuid; v_c_rate uuid; v_c_stock uuid; v_c_rel uuid;
  v_mission uuid; v_rep uuid; v_sig jsonb; v_sig2 jsonb; v_err text; v_n int;
  v_types text[] := ARRAY['merchant_suspension','catalog_violation','price_anomaly','fraud',
    'procurement_anomaly','customer_dispute','shopper_dispute','rating_abuse',
    'stock_accuracy','merchant_reliability'];
  t text; v_ok boolean; v_state text; v_price bigint; v_obs int; v_avg numeric;
  v_w0 bigint; v_w1 bigint; v_wt0 bigint; v_wt1 bigint; v_lj0 bigint; v_lj1 bigint;
  v_lp0 numeric; v_lp1 numeric; v_pi0 bigint; v_pi1 bigint; v_mp0 bigint; v_mp1 bigint;
  v_po0 bigint; v_po1 bigint; v_pr0 bigint; v_pr1 bigint; v_au0 bigint; v_au1 bigint;
  v_cs0 bigint; v_cs1 bigint; v_ev0 bigint; v_ev1 bigint; v_ct0 bigint; v_ct1 bigint;
  v_re0 bigint; v_re1 bigint; v_ml0 bigint; v_ml1 bigint; v_ord0 bigint; v_ord1 bigint;
  v_pm0 bigint; v_pm1 bigint; v_ob0 bigint; v_ob1 bigint; v_flags0 jsonb; v_flags1 jsonb;
BEGIN
  SELECT count(*) INTO v_w0 FROM public.wallets;
  SELECT count(*) INTO v_wt0 FROM public.wallet_transactions;
  SELECT count(*) INTO v_lj0 FROM public.ledger_journals;
  SELECT COALESCE(sum(amount_gnf),0) INTO v_lp0 FROM public.ledger_postings;
  SELECT count(*) INTO v_pi0 FROM public.payment_intents;
  SELECT count(*) INTO v_mp0 FROM public.merchant_payables;
  SELECT count(*) INTO v_po0 FROM public.payout_orders;
  SELECT count(*) INTO v_pr0 FROM public.profiles;
  SELECT count(*) INTO v_au0 FROM auth.users;
  SELECT count(*) INTO v_cs0 FROM public.marche_ops_cases;
  SELECT count(*) INTO v_ev0 FROM public.marche_ops_events;
  SELECT count(*) INTO v_ct0 FROM public.marche_ops_controls;
  SELECT count(*) INTO v_re0 FROM public.marche_reputation_events;
  SELECT count(*) INTO v_ml0 FROM public.marketplace_listings;
  SELECT count(*) INTO v_ord0 FROM public.marche_orders;
  SELECT count(*) INTO v_pm0 FROM public.marche_procurement_missions;
  SELECT count(*) INTO v_ob0 FROM public.marche_procurement_price_observations;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;

  -- ===== A. STRUCTURAL =====
  r := r || public._qa_s13_ok('N4R12.A1 case table exists',
        EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='marche_ops_cases'), NULL);
  r := r || public._qa_s13_ok('N4R12.A2 event table exists',
        EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='marche_ops_events'), NULL);
  r := r || public._qa_s13_ok('N4R12.A3 control table exists',
        EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='marche_ops_controls'), NULL);
  r := r || public._qa_s13_ok('N4R12.A4 reputation moderation layer exists',
        EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='marche_ops_reputation_moderations'), NULL);
  r := r || public._qa_s13_ok('N4R12.A5 ops events carry an append-only trigger',
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.marche_ops_events'::regclass
                 AND tgname='marche_ops_events_immutable' AND NOT tgisinternal), NULL);
  r := r || public._qa_s13_ok('N4R12.A6 RLS is enabled on every ops table',
        (SELECT bool_and(relrowsecurity) FROM pg_class
          WHERE relname IN ('marche_ops_cases','marche_ops_events','marche_ops_controls','marche_ops_reputation_moderations')
            AND relnamespace='public'::regnamespace), NULL);
  r := r || public._qa_s13_ok('N4R12.A7 no client role holds direct table CRUD',
        NOT (has_table_privilege('anon','public.marche_ops_cases','SELECT')
          OR has_table_privilege('authenticated','public.marche_ops_cases','SELECT')
          OR has_table_privilege('authenticated','public.marche_ops_cases','INSERT')
          OR has_table_privilege('authenticated','public.marche_ops_events','INSERT')
          OR has_table_privilege('authenticated','public.marche_ops_controls','UPDATE')
          OR has_table_privilege('authenticated','public.marche_ops_reputation_moderations','SELECT')), NULL);
  r := r || public._qa_s13_ok('N4R12.A8 every R12 function is definer and pins search_path',
        NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname IN
          ('marche_ops_case_detail','marche_ops_queue','marche_ops_case_open','marche_ops_command',
           'marche_ops_signal','_marche_ops_allowed_actions','_marche_ops_actor_role',
           'marche_ops_store_suspended','marche_ops_listing_quarantined','marche_ops_user_restricted')
          AND (NOT prosecdef OR COALESCE(array_to_string(proconfig,','),'') NOT LIKE '%search_path=public%')), NULL);
  r := r || public._qa_s13_ok('N4R12.A9 anon can execute no R12 RPC',
        NOT has_function_privilege('anon','public.marche_ops_case_detail(uuid)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_ops_queue(text,text,text,integer)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_ops_case_open(jsonb)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_ops_signal(jsonb)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_ops_command(uuid,text,uuid,text,text,jsonb)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R12.A10 ops internals are not client-callable',
        NOT has_function_privilege('authenticated','public._marche_ops_actor_role(uuid)','EXECUTE')
    AND NOT has_function_privilege('authenticated','public._marche_ops_allowed_actions(public.marche_ops_cases,text)','EXECUTE')
    AND NOT has_function_privilege('authenticated','public.marche_ops_store_suspended(uuid)','EXECUTE')
    AND NOT has_function_privilege('authenticated','public.marche_ops_listing_quarantined(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R12.A11 operations never touch wallets or the ledger',
        (SELECT bool_and(prosrc NOT LIKE '%public.wallets%' AND prosrc NOT LIKE '%wallet_transactions%'
                     AND prosrc NOT LIKE '%ledger_postings%' AND prosrc NOT LIKE '%ledger_journals%'
                     AND prosrc NOT LIKE '%payment_intents%')
           FROM pg_proc WHERE proname IN ('marche_ops_command','marche_ops_case_open','marche_ops_signal')), NULL);
  r := r || public._qa_s13_ok('N4R12.A12 operations never rewrite canonical history tables',
        (SELECT bool_and(prosrc NOT LIKE '%UPDATE public.marche_orders%'
                     AND prosrc NOT LIKE '%UPDATE public.marche_procurement_missions%'
                     AND prosrc NOT LIKE '%UPDATE public.marche_reputation_events%'
                     AND prosrc NOT LIKE '%DELETE FROM public.marketplace_listings%'
                     AND prosrc NOT LIKE '%UPDATE public.merchant_payables%'
                     AND prosrc NOT LIKE '%marche_procurement_price_observations%')
           FROM pg_proc WHERE proname IN ('marche_ops_command','marche_ops_case_open','marche_ops_signal')), NULL);
  r := r || public._qa_s13_ok('N4R12.A13 canonical truth carries the two prospective refusals',
        pg_get_viewdef('public.v_marche_listing_truth'::regclass, true) LIKE '%LISTING_QUARANTINED%'
    AND pg_get_viewdef('public.v_marche_listing_truth'::regclass, true) LIKE '%STORE_SUSPENDED%', NULL);
  r := r || public._qa_s13_ok('N4R12.A14 derived reputation excludes moderated evidence',
        (SELECT prosrc FROM pg_proc WHERE proname='marche_reputation_summary')
          LIKE '%marche_ops_reputation_moderations%', NULL);
  r := r || public._qa_s13_ok('N4R12.A15 the detector key is unique only while a case is active',
        EXISTS (SELECT 1 FROM pg_indexes WHERE tablename='marche_ops_cases'
                 AND indexname='marche_ops_cases_detector_active'
                 AND indexdef LIKE '%open%in_review%'), NULL);
  r := r || public._qa_s13_ok('N4R12.A16 ops commands are idempotent by construction',
        EXISTS (SELECT 1 FROM pg_indexes WHERE tablename='marche_ops_events'
                 AND indexname='marche_ops_events_request_key'), NULL);
  r := r || public._qa_s13_ok('N4R12.A17 anon still cannot execute has_role (P15.5 preserved)',
        NOT has_function_privilege('anon','public.has_role(uuid,app_role)','EXECUTE'), NULL);

  BEGIN
    -- ===== FIXTURES =====
    v_buy := gen_random_uuid(); v_merch := gen_random_uuid(); v_shop := gen_random_uuid();
    v_ops := gen_random_uuid(); v_fin := gen_random_uuid(); v_god := gen_random_uuid();
    PERFORM public._qa_s13_user(v_buy,'n412b');
    PERFORM public._qa_s13_user(v_merch,'n412m');
    PERFORM public._qa_s13_user(v_shop,'n412s');
    PERFORM public._qa_s13_user(v_ops,'n412o');
    PERFORM public._qa_s13_user(v_fin,'n412f');
    PERFORM public._qa_s13_user(v_god,'n412g');
    INSERT INTO public.admin_users(user_id, admin_role, status) VALUES
      (v_ops,'operations_admin','active'), (v_fin,'finance_admin','active'), (v_god,'god_admin','active');

    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status, latitude, longitude, address_label, phone)
      VALUES (v_merch,'qa-n412-'||substr(v_merch::text,1,8),'QA N412 Store','active','approved',9.5370,-13.6785,'QA Madina','+224620000112')
      RETURNING id INTO v_store;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    l_a := public.marche_listing_create(jsonb_build_object('store_id',v_store,'title','QA N412 Riz',
      'category','Alimentation','price_gnf',10000,'quantity_in_stock',20,'publish',true));
    l_b := public.marche_listing_create(jsonb_build_object('store_id',v_store,'title','QA N412 Huile',
      'category','Alimentation','price_gnf',25000,'quantity_in_stock',20,'publish',true));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_res := public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n412-main-0001', 'delivery_address','QA Kaloum, Conakry',
      'dropoff_lat', 9.5550, 'dropoff_lng', -13.6785,
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_a, 'qty', 1))));
    v_o1 := (v_res->>'id')::uuid;

    INSERT INTO public.marche_procurement_missions(request_id, buyer_user_id, shopper_user_id, state)
      VALUES (gen_random_uuid(), v_buy, v_shop, 'shopping') RETURNING id INTO v_mission;
    INSERT INTO public.marche_reputation_events(transaction_kind, transaction_id, rater_user_id,
      subject_kind, subject_store_id, overall_score, comment, provenance)
      VALUES ('merchant_order', v_o1, v_buy, 'merchant_store', v_store, 1, 'QA N412 abusive', '{}'::jsonb)
      RETURNING id INTO v_rep;
    INSERT INTO public.marche_reputation_dimensions(event_id, dimension, score) VALUES (v_rep,'quality',1);

    -- ===== B. PERMISSIONS =====
    PERFORM set_config('request.jwt.claims','', true);
    v_err := NULL;
    BEGIN PERFORM public.marche_ops_queue(NULL,NULL,NULL,10); EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R12.B1 a signed-out caller is refused', v_err='NOT_AUTHORIZED', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_ops_queue(NULL,NULL,NULL,10); EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R12.B2 an ordinary customer cannot read the ops queue', v_err='NOT_AUTHORIZED', v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_ops_case_open(jsonb_build_object('case_type','fraud','store_id',v_store,'reason_code','abc'));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R12.B3 a customer cannot open an ops case', v_err='NOT_AUTHORIZED', v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_ops_signal(jsonb_build_object('case_type','fraud','store_id',v_store,'detector_key','qa-n412-x'));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R12.B4 a customer cannot raise a detector signal', v_err='NOT_AUTHORIZED', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_ops_case_open(jsonb_build_object('case_type','fraud','store_id',v_store,'reason_code','abc'));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R12.B5 a merchant cannot open an ops case on itself', v_err='NOT_AUTHORIZED', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_shop), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_ops_queue(NULL,NULL,NULL,10); EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R12.B6 a shopper cannot read the ops queue', v_err='NOT_AUTHORIZED', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_ops), true);
    v_case := public.marche_ops_case_open(jsonb_build_object('case_type','merchant_suspension',
      'store_id',v_store,'reason_code','repeated_no_show','note','QA N412','severity','high'));
    v_c_susp := (v_case->>'case_id')::uuid;
    r := r || public._qa_s13_ok('N4R12.B7 operations admin can open a case', v_c_susp IS NOT NULL, NULL);
    r := r || public._qa_s13_ok('N4R12.B8 opening a case writes its first ops event',
          (SELECT count(*) FROM public.marche_ops_events WHERE case_id=v_c_susp AND action='open_case')=1, NULL);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_fin), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_ops_case_open(jsonb_build_object('case_type','fraud','store_id',v_store,'reason_code','abc'));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R12.B9 finance admin owns no case-opening authority', v_err='NOT_AUTHORIZED', v_err);
    v_case := public.marche_ops_case_detail(v_c_susp);
    r := r || public._qa_s13_ok('N4R12.B10 finance admin may inspect but not apply ops controls',
          NOT ((v_case->'allowed_actions') @> '["suspend_merchant"]'::jsonb)
      AND (v_case->'allowed_actions') @> '["record_finance_resolution"]'::jsonb,
          v_case->>'allowed_actions');
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_ops), true);
    v_case := public.marche_ops_case_detail(v_c_susp);
    r := r || public._qa_s13_ok('N4R12.B11 operations admin never gains finance authority',
          NOT ((v_case->'allowed_actions') @> '["record_finance_resolution"]'::jsonb),
          v_case->>'allowed_actions');
    v_err := NULL;
    BEGIN PERFORM public.marche_ops_command(v_c_susp,'record_finance_resolution',gen_random_uuid(),'refund_issued','x','{}'::jsonb);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R12.B12 a hidden button is not authorization', v_err='ACTION_NOT_ALLOWED', v_err);

    -- ===== C. CASE TYPE + LIFECYCLE COVERAGE =====
    FOREACH t IN ARRAY v_types LOOP
      v_case := public.marche_ops_case_open(jsonb_build_object('case_type',t,
        'store_id',v_store,'listing_id',l_b,'order_id',v_o1,'mission_id',v_mission,
        'customer_user_id',v_buy,'shopper_user_id',v_shop,'reputation_event_id',v_rep,
        'reason_code','qa_'||t));
      r := r || public._qa_s13_ok('N4R12.C-'||t||' canonical case type is supported',
            v_case->>'case_type' = t AND v_case->>'status' = 'open', v_case->>'case_type');
      IF t='catalog_violation' THEN v_c_cat := (v_case->>'case_id')::uuid;
      ELSIF t='price_anomaly' THEN v_c_price := (v_case->>'case_id')::uuid;
      ELSIF t='fraud' THEN v_c_fraud := (v_case->>'case_id')::uuid;
      ELSIF t='procurement_anomaly' THEN v_c_proc := (v_case->>'case_id')::uuid;
      ELSIF t='customer_dispute' THEN v_c_cust := (v_case->>'case_id')::uuid;
      ELSIF t='shopper_dispute' THEN v_c_shop := (v_case->>'case_id')::uuid;
      ELSIF t='rating_abuse' THEN v_c_rate := (v_case->>'case_id')::uuid;
      ELSIF t='stock_accuracy' THEN v_c_stock := (v_case->>'case_id')::uuid;
      ELSIF t='merchant_reliability' THEN v_c_rel := (v_case->>'case_id')::uuid;
      END IF;
    END LOOP;

    v_err := NULL;
    BEGIN PERFORM public.marche_ops_case_open(jsonb_build_object('case_type','not_a_type','store_id',v_store,'reason_code','abc'));
    EXCEPTION WHEN OTHERS THEN v_err := 'REFUSED'; END;
    r := r || public._qa_s13_ok('N4R12.C11 an unknown case type is refused', v_err='REFUSED', v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_ops_case_open(jsonb_build_object('case_type','fraud','reason_code','abc'));
    EXCEPTION WHEN OTHERS THEN v_err := 'REFUSED'; END;
    r := r || public._qa_s13_ok('N4R12.C12 a subjectless case is refused', v_err='REFUSED', v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_ops_case_open(jsonb_build_object('case_type','fraud','store_id',v_store,'reason_code',' '));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R12.C13 a reasonless case is refused', v_err='REASON_REQUIRED', v_err);

    v_case := public.marche_ops_command(v_c_cust,'start_review',gen_random_uuid(),'triage','QA','{}'::jsonb);
    r := r || public._qa_s13_ok('N4R12.C14 open moves to in_review', v_case->>'status'='in_review', v_case->>'status');
    v_case := public.marche_ops_command(v_c_cust,'dismiss',gen_random_uuid(),'resolved_no_action','QA','{}'::jsonb);
    r := r || public._qa_s13_ok('N4R12.C15 in_review may be dismissed with a resolution code',
          v_case->>'status'='dismissed' AND v_case->>'resolution_code'='resolved_no_action', v_case->>'status');
    v_err := NULL;
    BEGIN PERFORM public.marche_ops_command(v_c_cust,'start_review',gen_random_uuid(),'triage','QA','{}'::jsonb);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R12.C16 a closed case refuses an invalid transition', v_err='ACTION_NOT_ALLOWED', v_err);
    v_case := public.marche_ops_command(v_c_cust,'reopen',gen_random_uuid(),'new_evidence','QA','{}'::jsonb);
    r := r || public._qa_s13_ok('N4R12.C17 reopening clears the resolution and is audited',
          v_case->>'status'='open' AND v_case->'resolution_code'='null'::jsonb
      AND (SELECT count(*) FROM public.marche_ops_events WHERE case_id=v_c_cust AND action='reopen')=1, v_case->>'status');
    v_err := NULL;
    BEGIN UPDATE public.marche_ops_events SET note='tampered' WHERE case_id=v_c_cust;
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R12.C18 ops history refuses UPDATE', v_err='MARCHE_OPS_EVENTS_APPEND_ONLY', v_err);
    v_err := NULL;
    BEGIN DELETE FROM public.marche_ops_events WHERE case_id=v_c_cust;
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R12.C19 ops history refuses DELETE', v_err='MARCHE_OPS_EVENTS_APPEND_ONLY', v_err);

    -- ===== D. MERCHANT SUSPENSION =====
    SELECT count(*) INTO v_n FROM public.marche_orders WHERE merchant_store_id=v_store;
    v_case := public.marche_ops_command(v_c_susp,'suspend_merchant',gen_random_uuid(),'fraud_suspicion','QA suspension','{}'::jsonb);
    r := r || public._qa_s13_ok('N4R12.D1 suspension is recorded as an active control',
          public.marche_ops_store_suspended(v_store), NULL);
    r := r || public._qa_s13_ok('N4R12.D2 suspension makes store supply non-orderable',
          (SELECT refusal_reason FROM public.v_marche_listing_truth WHERE listing_id=l_a)='STORE_SUSPENDED',
          (SELECT refusal_reason FROM public.v_marche_listing_truth WHERE listing_id=l_a));
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n412-blocked-0002','delivery_address','QA Kaloum',
      'dropoff_lat',9.5550,'dropoff_lng',-13.6785,
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_a, 'qty', 1))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R12.D3 a new commitment on a suspended merchant is refused',
          v_err='STORE_SUSPENDED', v_err);
    r := r || public._qa_s13_ok('N4R12.D4 no new order was created by the refusal',
          (SELECT count(*) FROM public.marche_orders WHERE merchant_store_id=v_store)=v_n, NULL);
    r := r || public._qa_s13_ok('N4R12.D5 the historical order is untouched',
          (SELECT status FROM public.marche_orders WHERE id=v_o1)='committed'
      AND (SELECT fulfillment_state FROM public.marche_orders WHERE id=v_o1)='committed', NULL);
    r := r || public._qa_s13_ok('N4R12.D6 suspension deletes neither store nor listings',
          EXISTS (SELECT 1 FROM public.merchant_stores WHERE id=v_store)
      AND (SELECT count(*) FROM public.marketplace_listings WHERE store_id=v_store)=2, NULL);
    r := r || public._qa_s13_ok('N4R12.D7 suspension writes no payable or settlement row',
          (SELECT count(*) FROM public.merchant_payables WHERE source_id=v_o1)=0, NULL);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_ops), true);
    v_case := public.marche_ops_command(v_c_susp,'restore_merchant',gen_random_uuid(),'cleared_after_review','QA restore','{}'::jsonb);
    r := r || public._qa_s13_ok('N4R12.D8 restoration is prospective and immediate',
          NOT public.marche_ops_store_suspended(v_store)
      AND (SELECT is_orderable FROM public.v_marche_listing_truth WHERE listing_id=l_a), NULL);
    r := r || public._qa_s13_ok('N4R12.D9 both interventions are durable ops history',
          (SELECT count(*) FROM public.marche_ops_events
            WHERE case_id=v_c_susp AND action IN ('suspend_merchant','restore_merchant'))=2, NULL);
    r := r || public._qa_s13_ok('N4R12.D10 the lifted control keeps its own audit trail',
          (SELECT count(*) FROM public.marche_ops_controls
            WHERE case_id=v_c_susp AND control_kind='store_suspension'
              AND lifted_at IS NOT NULL AND lifted_by=v_ops AND lift_reason='cleared_after_review')=1, NULL);

    -- ===== E. CATALOG VIOLATION =====
    SELECT count(*) INTO v_obs FROM public.marche_procurement_price_observations WHERE listing_id=l_b;
    SELECT price_gnf INTO v_price FROM public.marketplace_listings WHERE id=l_b;
    v_case := public.marche_ops_command(v_c_cat,'quarantine_listing',gen_random_uuid(),'prohibited_item','QA quarantine','{}'::jsonb);
    r := r || public._qa_s13_ok('N4R12.E1 quarantine blocks future orderability',
          (SELECT refusal_reason FROM public.v_marche_listing_truth WHERE listing_id=l_b)='LISTING_QUARANTINED',
          (SELECT refusal_reason FROM public.v_marche_listing_truth WHERE listing_id=l_b));
    r := r || public._qa_s13_ok('N4R12.E2 quarantine is listing-scoped, the merchant stays open',
          (SELECT is_orderable FROM public.v_marche_listing_truth WHERE listing_id=l_a)
      AND NOT public.marche_ops_store_suspended(v_store), NULL);
    r := r || public._qa_s13_ok('N4R12.E3 quarantine deletes no listing identity or history',
          EXISTS (SELECT 1 FROM public.marketplace_listings WHERE id=l_b)
      AND (SELECT price_gnf FROM public.marketplace_listings WHERE id=l_b)=v_price, NULL);
    r := r || public._qa_s13_ok('N4R12.E4 quarantine preserves price observations',
          (SELECT count(*) FROM public.marche_procurement_price_observations WHERE listing_id=l_b)=v_obs, NULL);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n412-blocked-0003','delivery_address','QA Kaloum',
      'dropoff_lat',9.5550,'dropoff_lng',-13.6785,
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_b, 'qty', 1))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R12.E5 a quarantined article cannot be ordered', v_err='LISTING_QUARANTINED', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_ops), true);
    v_case := public.marche_ops_command(v_c_cat,'restore_listing',gen_random_uuid(),'compliant_after_review','QA','{}'::jsonb);
    r := r || public._qa_s13_ok('N4R12.E6 restoration is audited and effective',
          (SELECT is_orderable FROM public.v_marche_listing_truth WHERE listing_id=l_b)
      AND (SELECT count(*) FROM public.marche_ops_events WHERE case_id=v_c_cat AND action='restore_listing')=1, NULL);

    -- ===== F. PRICE ANOMALY =====
    SELECT count(*) INTO v_obs FROM public.marche_procurement_price_observations;
    SELECT price_gnf INTO v_price FROM public.marketplace_listings WHERE id=l_b;
    v_case := public.marche_ops_command(v_c_price,'quarantine_listing',gen_random_uuid(),'price_out_of_band','QA','{}'::jsonb);
    r := r || public._qa_s13_ok('N4R12.F1 an anomaly never rewrites the listing price',
          (SELECT price_gnf FROM public.marketplace_listings WHERE id=l_b)=v_price, NULL);
    r := r || public._qa_s13_ok('N4R12.F2 an anomaly writes no price observation',
          (SELECT count(*) FROM public.marche_procurement_price_observations)=v_obs, NULL);
    r := r || public._qa_s13_ok('N4R12.F3 an anomaly deletes no historical observation',
          (SELECT prosrc FROM pg_proc WHERE proname='marche_ops_command')
            NOT LIKE '%marche_procurement_price_observations%', NULL);
    r := r || public._qa_s13_ok('N4R12.F4 detection is separable from sanction',
          (SELECT count(*) FROM public.marche_ops_cases WHERE id=v_c_price AND status='open')=1, NULL);
    v_case := public.marche_ops_command(v_c_price,'restore_listing',gen_random_uuid(),'merchant_confirmed_price','QA','{}'::jsonb);
    r := r || public._qa_s13_ok('N4R12.F5 review can restore the article prospectively',
          (SELECT is_orderable FROM public.v_marche_listing_truth WHERE listing_id=l_b), NULL);

    -- ===== G. FRAUD / FINANCE SEPARATION =====
    SELECT count(*) INTO v_n FROM public.wallet_transactions;
    v_case := public.marche_ops_command(v_c_fraud,'restrict_user',gen_random_uuid(),'fraud_ring','QA','{}'::jsonb);
    r := r || public._qa_s13_ok('N4R12.G1 fraud can restrict a subject prospectively',
          public.marche_ops_user_restricted(v_shop), NULL);
    r := r || public._qa_s13_ok('N4R12.G2 fraud handling moves no money',
          (SELECT count(*) FROM public.wallet_transactions)=v_n, NULL);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_fin), true);
    v_case := public.marche_ops_command(v_c_fraud,'record_finance_resolution',gen_random_uuid(),
      'refund_via_canonical_rail','QA', jsonb_build_object('finance_kind','refund','finance_reference','QA-N412-REF-1'));
    r := r || public._qa_s13_ok('N4R12.G3 finance records only a canonical reference',
          (SELECT finance_ref->>'finance_reference' FROM public.marche_ops_events
            WHERE case_id=v_c_fraud AND action='record_finance_resolution')='QA-N412-REF-1', NULL);
    r := r || public._qa_s13_ok('N4R12.G4 recording a finance reference creates no ledger movement',
          (SELECT count(*) FROM public.wallet_transactions)=v_n, NULL);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_ops), true);
    v_case := public.marche_ops_command(v_c_fraud,'unrestrict_user',gen_random_uuid(),'cleared','QA','{}'::jsonb);
    r := r || public._qa_s13_ok('N4R12.G5 a restriction can be lifted and stays audited',
          NOT public.marche_ops_user_restricted(v_shop)
      AND (SELECT count(*) FROM public.marche_ops_events WHERE case_id=v_c_fraud
            AND action IN ('restrict_user','unrestrict_user'))=2, NULL);

    -- ===== H. PROCUREMENT ANOMALY =====
    SELECT state INTO v_state FROM public.marche_procurement_missions WHERE id=v_mission;
    v_case := public.marche_ops_command(v_c_proc,'request_evidence',gen_random_uuid(),'evidence_missing','QA','{}'::jsonb);
    r := r || public._qa_s13_ok('N4R12.H1 an ops intervention never moves the mission state',
          (SELECT state FROM public.marche_procurement_missions WHERE id=v_mission)=v_state, NULL);
    r := r || public._qa_s13_ok('N4R12.H2 ops exposes no mission lifecycle action',
          NOT ((v_case->'allowed_actions') @> '["force_mission_state"]'::jsonb), v_case->>'allowed_actions');
    r := r || public._qa_s13_ok('N4R12.H3 the case detail carries canonical mission truth',
          v_case->'subjects'->'mission'->>'state' = v_state, NULL);
    v_case := public.marche_ops_command(v_c_proc,'escalate',gen_random_uuid(),'shopper_conflict','QA','{}'::jsonb);
    r := r || public._qa_s13_ok('N4R12.H4 escalation raises severity and is audited',
          v_case->>'severity'='critical'
      AND (SELECT count(*) FROM public.marche_ops_events WHERE case_id=v_c_proc AND action='escalate')=1, v_case->>'severity');

    -- ===== I. DISPUTES =====
    v_case := public.marche_ops_command(v_c_cust,'start_review',gen_random_uuid(),'triage','QA','{}'::jsonb);
    r := r || public._qa_s13_ok('N4R12.I1 a customer dispute can be investigated',
          v_case->>'status'='in_review', v_case->>'status');
    r := r || public._qa_s13_ok('N4R12.I2 a customer dispute keeps its linked order truth',
          v_case->'subjects'->'order'->>'id' = v_o1::text
      AND v_case->'subjects'->'order'->>'fulfillment_state' = 'committed', NULL);
    r := r || public._qa_s13_ok('N4R12.I3 operations never sees merchant payout money',
          (v_case->'subjects'->'order'->'merchant_payable_gnf') = 'null'::jsonb, NULL);
    v_case := public.marche_ops_command(v_c_cust,'resolve',gen_random_uuid(),'resolved_contacted','QA','{}'::jsonb);
    r := r || public._qa_s13_ok('N4R12.I4 a customer dispute resolves with an explicit code',
          v_case->>'status'='resolved' AND v_case->>'resolution_code'='resolved_contacted', NULL);
    v_case := public.marche_ops_command(v_c_shop,'start_review',gen_random_uuid(),'triage','QA','{}'::jsonb);
    r := r || public._qa_s13_ok('N4R12.I5 a shopper dispute follows the same lifecycle',
          v_case->>'status'='in_review', NULL);
    r := r || public._qa_s13_ok('N4R12.I6 a shopper dispute falsifies no shopper history',
          (SELECT shopper_user_id FROM public.marche_procurement_missions WHERE id=v_mission)=v_shop
      AND (SELECT state FROM public.marche_procurement_missions WHERE id=v_mission)=v_state, NULL);
    v_case := public.marche_ops_command(v_c_shop,'resolve',gen_random_uuid(),'resolved_no_action','QA','{}'::jsonb);
    r := r || public._qa_s13_ok('N4R12.I7 a shopper dispute resolution is audited',
          (SELECT count(*) FROM public.marche_ops_events WHERE case_id=v_c_shop AND action='resolve')=1, NULL);

    -- ===== J. RATING ABUSE =====
    SELECT (public.marche_reputation_summary('merchant_store', v_store)->>'overall_average')::numeric INTO v_avg;
    r := r || public._qa_s13_ok('N4R12.J1 the abusive rating counts before moderation', v_avg = 1.00, v_avg::text);
    v_case := public.marche_ops_command(v_c_rate,'moderate_rating',gen_random_uuid(),'coordinated_abuse','QA','{}'::jsonb);
    r := r || public._qa_s13_ok('N4R12.J2 raw reputation evidence survives moderation',
          EXISTS (SELECT 1 FROM public.marche_reputation_events WHERE id=v_rep AND overall_score=1), NULL);
    r := r || public._qa_s13_ok('N4R12.J3 raw dimension evidence survives moderation',
          EXISTS (SELECT 1 FROM public.marche_reputation_dimensions WHERE event_id=v_rep AND score=1), NULL);
    r := r || public._qa_s13_ok('N4R12.J4 derived reputation excludes the moderated event',
          (public.marche_reputation_summary('merchant_store', v_store)->>'has_reputation')::boolean = false, NULL);
    r := r || public._qa_s13_ok('N4R12.J5 moderation records who and why',
          (SELECT count(*) FROM public.marche_ops_reputation_moderations
            WHERE event_id=v_rep AND moderated_by=v_ops AND reason_code='coordinated_abuse'
              AND restored_at IS NULL)=1, NULL);
    v_err := NULL;
    BEGIN UPDATE public.marche_reputation_events SET overall_score=5 WHERE id=v_rep;
    EXCEPTION WHEN OTHERS THEN v_err := 'REFUSED'; END;
    r := r || public._qa_s13_ok('N4R12.J6 a rating score can never be rewritten', v_err='REFUSED', v_err);
    v_case := public.marche_ops_command(v_c_rate,'restore_rating',gen_random_uuid(),'appeal_upheld','QA','{}'::jsonb);
    r := r || public._qa_s13_ok('N4R12.J7 restoring moderation recomputes canonical reputation',
          (public.marche_reputation_summary('merchant_store', v_store)->>'overall_average')::numeric = 1.00, NULL);
    r := r || public._qa_s13_ok('N4R12.J8 both moderation decisions are durable history',
          (SELECT count(*) FROM public.marche_ops_events WHERE case_id=v_c_rate
            AND action IN ('moderate_rating','restore_rating'))=2, NULL);

    -- ===== K. STOCK ACCURACY =====
    SELECT quantity_in_stock INTO v_n FROM public.marketplace_listings WHERE id=l_a;
    v_case := public.marche_ops_command(v_c_stock,'quarantine_listing',gen_random_uuid(),'repeated_stock_mismatch','QA','{}'::jsonb);
    r := r || public._qa_s13_ok('N4R12.K1 a stock case never rewrites recorded stock',
          (SELECT quantity_in_stock FROM public.marketplace_listings WHERE id=l_a)=v_n, NULL);
    r := r || public._qa_s13_ok('N4R12.K2 repeated inaccuracy can block future ordering only',
          (SELECT refusal_reason FROM public.v_marche_listing_truth WHERE listing_id=l_b)='LISTING_QUARANTINED', NULL);
    r := r || public._qa_s13_ok('N4R12.K3 the stock case leaves reservations untouched',
          (SELECT COALESCE(quantity_reserved,0) FROM public.marketplace_listings WHERE id=l_a)=1, NULL);
    v_case := public.marche_ops_command(v_c_stock,'restore_listing',gen_random_uuid(),'stock_recount_ok','QA','{}'::jsonb);
    r := r || public._qa_s13_ok('N4R12.K4 stock restoration is append-only evidence',
          (SELECT count(*) FROM public.marche_ops_events WHERE case_id=v_c_stock)=3, NULL);

    -- ===== L. MERCHANT RELIABILITY =====
    v_case := public.marche_ops_case_detail(v_c_rel);
    r := r || public._qa_s13_ok('N4R12.L1 reliability exposes no arbitrary score control',
          NOT ((v_case->'allowed_actions') @> '["set_reliability_score"]'::jsonb), v_case->>'allowed_actions');
    r := r || public._qa_s13_ok('N4R12.L2 no ops function writes reputation evidence',
          (SELECT bool_and(prosrc NOT LIKE '%INSERT INTO public.marche_reputation_events%')
             FROM pg_proc WHERE proname IN ('marche_ops_command','marche_ops_case_open','marche_ops_signal')), NULL);
    SELECT (public.marche_reputation_summary('merchant_store', v_store)->>'overall_average')::numeric INTO v_avg;
    v_case := public.marche_ops_command(v_c_rel,'resolve',gen_random_uuid(),'reliability_warning_issued','QA','{}'::jsonb);
    r := r || public._qa_s13_ok('N4R12.L3 an ops resolution never moves derived reliability',
          (public.marche_reputation_summary('merchant_store', v_store)->>'overall_average')::numeric = v_avg, NULL);
    r := r || public._qa_s13_ok('N4R12.L4 the reliability decision keeps its provenance',
          (SELECT resolution_code FROM public.marche_ops_cases WHERE id=v_c_rel)='reliability_warning_issued'
      AND (SELECT resolved_by FROM public.marche_ops_cases WHERE id=v_c_rel)=v_ops, NULL);

    -- ===== M. ALLOWED ACTIONS =====
    v_case := public.marche_ops_case_detail(v_c_susp);
    r := r || public._qa_s13_ok('N4R12.M1 allowed actions are case-type aware',
          (v_case->'allowed_actions') @> '["suspend_merchant"]'::jsonb
      AND NOT ((v_case->'allowed_actions') @> '["moderate_rating"]'::jsonb), v_case->>'allowed_actions');
    v_case := public.marche_ops_case_detail(v_c_rate);
    r := r || public._qa_s13_ok('N4R12.M2 rating abuse exposes rating moderation only',
          (v_case->'allowed_actions') @> '["moderate_rating"]'::jsonb
      AND NOT ((v_case->'allowed_actions') @> '["suspend_merchant"]'::jsonb), v_case->>'allowed_actions');
    v_case := public.marche_ops_case_detail(v_c_rel);
    r := r || public._qa_s13_ok('N4R12.M3 a closed case only offers reopen',
          v_case->'allowed_actions' = '["reopen"]'::jsonb, v_case->>'allowed_actions');
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    v_case := public.marche_ops_case_detail(v_c_susp);
    r := r || public._qa_s13_ok('N4R12.M4 the super tier keeps both ops and finance authority',
          (v_case->'allowed_actions') @> '["suspend_merchant","record_finance_resolution"]'::jsonb, NULL);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_ops), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_ops_command(v_c_susp,'restore_merchant',gen_random_uuid(),'x','QA','{}'::jsonb);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R12.M5 a stale action is refused server-side', v_err='ACTION_NOT_ALLOWED', v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_ops_command(v_c_susp,'suspend_merchant',gen_random_uuid(),'  ','QA','{}'::jsonb);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R12.M6 a consequential action requires a reason', v_err='REASON_REQUIRED', v_err);

    -- ===== N. IDEMPOTENCY + DETECTION =====
    v_case := public.marche_ops_case_detail(v_c_susp);
    SELECT count(*) INTO v_n FROM public.marche_ops_events WHERE case_id=v_c_susp;
    DECLARE v_req uuid := gen_random_uuid(); BEGIN
      PERFORM public.marche_ops_command(v_c_susp,'add_note',v_req,'note','QA once','{}'::jsonb);
      PERFORM public.marche_ops_command(v_c_susp,'add_note',v_req,'note','QA once','{}'::jsonb);
    END;
    r := r || public._qa_s13_ok('N4R12.N1 a retried command writes exactly one event',
          (SELECT count(*) FROM public.marche_ops_events WHERE case_id=v_c_susp)=v_n+1, NULL);
    v_err := NULL;
    BEGIN PERFORM public.marche_ops_command(v_c_susp,'add_note',NULL,'note','QA','{}'::jsonb);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R12.N2 a command without request identity is refused',
          v_err='REQUEST_ID_REQUIRED', v_err);

    v_sig := public.marche_ops_signal(jsonb_build_object('case_type','price_anomaly',
      'listing_id', l_a, 'store_id', v_store, 'detector_key','qa-n412-price-'||substr(l_a::text,1,8),
      'reason_code','price_jump_detected'));
    v_sig2 := public.marche_ops_signal(jsonb_build_object('case_type','price_anomaly',
      'listing_id', l_a, 'store_id', v_store, 'detector_key','qa-n412-price-'||substr(l_a::text,1,8),
      'reason_code','price_jump_detected'));
    r := r || public._qa_s13_ok('N4R12.N3 a detector signal opens a case',
          (v_sig->>'created')::boolean = true, NULL);
    r := r || public._qa_s13_ok('N4R12.N4 the same signal never spams a duplicate case',
          (v_sig2->>'created')::boolean = false AND v_sig2->>'case_id' = v_sig->>'case_id', NULL);
    r := r || public._qa_s13_ok('N4R12.N5 detection sanctions nothing by itself',
          NOT public.marche_ops_listing_quarantined(l_a)
      AND (SELECT is_orderable FROM public.v_marche_listing_truth WHERE listing_id=l_a), NULL);
    r := r || public._qa_s13_ok('N4R12.N6 a detector case is marked as machine-sourced',
          (SELECT source FROM public.marche_ops_cases WHERE id=(v_sig->>'case_id')::uuid)='detector', NULL);
    PERFORM public.marche_ops_command((v_sig->>'case_id')::uuid,'dismiss',gen_random_uuid(),'false_positive','QA','{}'::jsonb);
    v_sig2 := public.marche_ops_signal(jsonb_build_object('case_type','price_anomaly',
      'listing_id', l_a, 'store_id', v_store, 'detector_key','qa-n412-price-'||substr(l_a::text,1,8),
      'reason_code','price_jump_detected'));
    r := r || public._qa_s13_ok('N4R12.N7 a genuine recurrence opens a new case',
          (v_sig2->>'created')::boolean = true AND v_sig2->>'case_id' <> v_sig->>'case_id', NULL);
    v_err := NULL;
    BEGIN PERFORM public.marche_ops_signal(jsonb_build_object('case_type','fraud','store_id',v_store));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R12.N8 a keyless detector signal is refused',
          v_err='DETECTOR_KEY_REQUIRED', v_err);

    RAISE EXCEPTION 'QA_N4R12_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_N4R12_ROLLBACK' THEN
      r := r || public._qa_s13_ok('N4R12.X fixture run raised', false, SQLERRM);
    END IF;
  END;

  PERFORM set_config('request.jwt.claims','', true);

  -- ===== S. NON-DRIFT =====
  SELECT count(*) INTO v_w1 FROM public.wallets;
  SELECT count(*) INTO v_wt1 FROM public.wallet_transactions;
  SELECT count(*) INTO v_lj1 FROM public.ledger_journals;
  SELECT COALESCE(sum(amount_gnf),0) INTO v_lp1 FROM public.ledger_postings;
  SELECT count(*) INTO v_pi1 FROM public.payment_intents;
  SELECT count(*) INTO v_mp1 FROM public.merchant_payables;
  SELECT count(*) INTO v_po1 FROM public.payout_orders;
  SELECT count(*) INTO v_pr1 FROM public.profiles;
  SELECT count(*) INTO v_au1 FROM auth.users;
  SELECT count(*) INTO v_cs1 FROM public.marche_ops_cases;
  SELECT count(*) INTO v_ev1 FROM public.marche_ops_events;
  SELECT count(*) INTO v_ct1 FROM public.marche_ops_controls;
  SELECT count(*) INTO v_re1 FROM public.marche_reputation_events;
  SELECT count(*) INTO v_ml1 FROM public.marketplace_listings;
  SELECT count(*) INTO v_ord1 FROM public.marche_orders;
  SELECT count(*) INTO v_pm1 FROM public.marche_procurement_missions;
  SELECT count(*) INTO v_ob1 FROM public.marche_procurement_price_observations;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;

  r := r || public._qa_s13_ok('N4R12.S1 zero wallet / ledger drift',
        v_w1=v_w0 AND v_wt1=v_wt0 AND v_lj1=v_lj0 AND v_lp1=v_lp0,
        format('%s/%s/%s/%s', v_w1-v_w0, v_wt1-v_wt0, v_lj1-v_lj0, v_lp1-v_lp0));
  r := r || public._qa_s13_ok('N4R12.S2 zero payment / payable / payout drift',
        v_pi1=v_pi0 AND v_mp1=v_mp0 AND v_po1=v_po0,
        format('%s/%s/%s', v_pi1-v_pi0, v_mp1-v_mp0, v_po1-v_po0));
  r := r || public._qa_s13_ok('N4R12.S3 zero identity drift',
        v_pr1=v_pr0 AND v_au1=v_au0, format('%s/%s', v_pr1-v_pr0, v_au1-v_au0));
  r := r || public._qa_s13_ok('N4R12.S4 zero ops case / event / control residue',
        v_cs1=v_cs0 AND v_ev1=v_ev0 AND v_ct1=v_ct0,
        format('%s/%s/%s', v_cs1-v_cs0, v_ev1-v_ev0, v_ct1-v_ct0));
  r := r || public._qa_s13_ok('N4R12.S5 zero reputation residue', v_re1=v_re0, (v_re1-v_re0)::text);
  r := r || public._qa_s13_ok('N4R12.S6 zero marketplace listing residue', v_ml1=v_ml0, (v_ml1-v_ml0)::text);
  r := r || public._qa_s13_ok('N4R12.S7 zero Marché order residue', v_ord1=v_ord0, (v_ord1-v_ord0)::text);
  r := r || public._qa_s13_ok('N4R12.S8 zero procurement mission residue', v_pm1=v_pm0, (v_pm1-v_pm0)::text);
  r := r || public._qa_s13_ok('N4R12.S9 zero price observation residue', v_ob1=v_ob0, (v_ob1-v_ob0)::text);
  r := r || public._qa_s13_ok('N4R12.S10 feature flags byte-identical', v_flags1=v_flags0, NULL);
  SELECT count(*) INTO v_n FROM public.merchant_stores WHERE slug LIKE 'qa-n412-%';
  r := r || public._qa_s13_ok('N4R12.S11 zero store fixture residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marketplace_listings WHERE title LIKE 'QA N412%';
  r := r || public._qa_s13_ok('N4R12.S12 zero listing fixture residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_ops_cases WHERE detector_key LIKE 'qa-n412-%';
  r := r || public._qa_s13_ok('N4R12.S13 zero detector case residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.admin_users a
    WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = a.user_id);
  r := r || public._qa_s13_ok('N4R12.S14 zero orphan admin fixture residue', v_n=0, v_n::text);

  RETURN r;
END $function$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r12() FROM PUBLIC, anon, authenticated;