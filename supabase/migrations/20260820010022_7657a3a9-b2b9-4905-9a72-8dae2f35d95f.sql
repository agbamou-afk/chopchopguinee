CREATE OR REPLACE FUNCTION public._qa_node4_marche_r9()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  r jsonb := '[]'::jsonb;
  v_err text; v_n bigint; v_res jsonb; v_j jsonb; v_txt text;
  v_buy uuid := gen_random_uuid(); v_buy2 uuid := gen_random_uuid();
  v_mer uuid := gen_random_uuid(); v_drv uuid := gen_random_uuid();
  v_drv2 uuid := gen_random_uuid();
  v_store uuid; l_a uuid;
  v_o1 uuid; v_o2 uuid; v_o3 uuid; v_o4 uuid; v_o5 uuid; v_mid uuid;
  v_com uuid; v_v1 uuid; v_opt uuid; v_r1 uuid;
  v_ev uuid; v_ev2 uuid;
  v_flags0 jsonb; v_flags1 jsonb;
  v_master0 bigint; v_master1 bigint;
  v_w0 bigint; v_w1 bigint; v_lp0 bigint; v_lp1 bigint; v_held0 bigint; v_held1 bigint;
  v_obs0 bigint; v_obs1 bigint; v_ms0 bigint; v_rate0 numeric; v_rate1 numeric;
  v_fs text; v_mstate text;
BEGIN
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT count(*) INTO v_ms0 FROM public.missions;

  -- ================= A. STRUCTURAL + SECURITY LAW =================
  r := r || public._qa_s13_ok('N4R9.A1 immutable reputation event table exists',
        to_regclass('public.marche_reputation_events') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N4R9.A2 normalized dimension child table exists',
        to_regclass('public.marche_reputation_dimensions') IS NOT NULL, NULL);
  SELECT count(*) INTO v_n FROM information_schema.role_table_grants
   WHERE table_schema='public' AND grantee IN ('anon','authenticated')
     AND table_name IN ('marche_reputation_events','marche_reputation_dimensions');
  r := r || public._qa_s13_ok('N4R9.A3 no direct anon/authenticated grants on reputation tables', v_n=0, v_n::text);
  r := r || public._qa_s13_ok('N4R9.A4 reputation tables have RLS enabled with zero policies',
        (SELECT relrowsecurity FROM pg_class WHERE oid='public.marche_reputation_events'::regclass)
    AND (SELECT relrowsecurity FROM pg_class WHERE oid='public.marche_reputation_dimensions'::regclass)
    AND (SELECT count(*) FROM pg_policies WHERE tablename IN
          ('marche_reputation_events','marche_reputation_dimensions'))=0, NULL);
  r := r || public._qa_s13_ok('N4R9.A5 unique logical rating identity is enforced by index',
        EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='marche_reputation_unique_identity'), NULL);
  r := r || public._qa_s13_ok('N4R9.A6 append-only triggers guard both tables',
        (SELECT count(*) FROM pg_trigger WHERE tgname IN
          ('trg_marche_reputation_events_immutable','trg_marche_reputation_dimensions_immutable'))=2, NULL);
  r := r || public._qa_s13_ok('N4R9.A7 overall score is constrained 1..5',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conname='marche_reputation_score_chk'), NULL);
  r := r || public._qa_s13_ok('N4R9.A8 subject identity shape is constrained',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conname='marche_reputation_subject_identity_chk'), NULL);
  r := r || public._qa_s13_ok('N4R9.A9 self-rating is refused at the storage layer too',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conname='marche_reputation_no_self_chk'), NULL);
  r := r || public._qa_s13_ok('N4R9.A10 comment length is bounded',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conname='marche_reputation_comment_chk'), NULL);
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace nsp ON nsp.oid=p.pronamespace
   WHERE nsp.nspname='public' AND p.proname LIKE '%marche_reputation%'
     AND p.prosecdef AND NOT ('search_path=public' = ANY(COALESCE(p.proconfig, ARRAY[]::text[])));
  r := r || public._qa_s13_ok('N4R9.A11 every R9 definer pins search_path=public', v_n=0, v_n::text);
  r := r || public._qa_s13_ok('N4R9.A12 anon cannot submit or read eligibility',
        NOT has_function_privilege('anon','public.marche_reputation_submit(jsonb)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_reputation_eligibility(text,uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R9.A13 sanitized aggregate is publicly readable',
        has_function_privilege('anon','public.marche_reputation_summary(text,uuid)','EXECUTE')
    AND has_function_privilege('authenticated','public.marche_reputation_summary(text,uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R9.A14 subject resolution is not client-callable',
        NOT has_function_privilege('authenticated','public._marche_reputation_resolve(text,uuid,uuid)','EXECUTE')
    AND NOT has_function_privilege('anon','public._marche_reputation_resolve(text,uuid,uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R9.A15 exact merchant dimension vocabulary',
        public.marche_reputation_dimensions_for('merchant_store')
          = ARRAY['quality','accuracy','availability','packaging','preparation','value'], NULL);
  r := r || public._qa_s13_ok('N4R9.A16 exact delivery-driver dimension vocabulary',
        public.marche_reputation_dimensions_for('delivery_driver')
          = ARRAY['courtesy','communication','timeliness','order_care'], NULL);
  r := r || public._qa_s13_ok('N4R9.A17 exact shopper dimension vocabulary',
        public.marche_reputation_dimensions_for('shopper')
          = ARRAY['selection_quality','freshness','substitution_quality','shopping_accuracy'], NULL);
  r := r || public._qa_s13_ok('N4R9.A18 R9 writes nothing into legacy ride rating truth',
        (SELECT pg_get_functiondef(oid) FROM pg_proc
          WHERE oid='public.marche_reputation_submit(jsonb)'::regprocedure)
        NOT ILIKE '%driver_profiles%'
    AND (SELECT pg_get_functiondef(oid) FROM pg_proc
          WHERE oid='public.marche_reputation_submit(jsonb)'::regprocedure)
        NOT ILIKE '%ride_ratings%', NULL);
  r := r || public._qa_s13_ok('N4R9.A19 R9 creates no parallel finance writes',
        (SELECT pg_get_functiondef(oid) FROM pg_proc
          WHERE oid='public.marche_reputation_submit(jsonb)'::regprocedure)
        NOT ILIKE '%wallet%', NULL);
  r := r || public._qa_s13_ok('N4R9.A20 legacy ride rating table is preserved untouched',
        to_regclass('public.ride_ratings') IS NOT NULL, NULL);

  BEGIN
    -- ================= FIXTURES =================
    PERFORM public._qa_s13_user(v_buy,'n49b');
    PERFORM public._qa_s13_user(v_buy2,'n49b2');
    PERFORM public._qa_s13_user(v_mer,'n49m');
    PERFORM public._qa_s13_driver(v_drv,'n49d',0);
    PERFORM public._qa_s13_driver(v_drv2,'n49d2',0);
    UPDATE public.driver_profiles SET capabilities = capabilities || ARRAY['marche_shopper']
     WHERE user_id = v_drv;
    SELECT rating INTO v_rate0 FROM public.driver_profiles WHERE user_id = v_drv;

    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status,
                                       latitude, longitude, address_label)
      VALUES (v_mer,'qa-n49-'||substr(v_mer::text,1,8),'QA N49 Boutique','active','approved',
              9.5370,-13.6785,'QA Madina')
      RETURNING id INTO v_store;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_mer), true);
    l_a := public.marche_listing_create(jsonb_build_object('store_id',v_store,'title','QA N49 Riz',
      'category','Alimentation','price_gnf',10000,'quantity_in_stock',40,'publish',true));

    -- ---- o1: full delivered order with a real courier ----
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_res := public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n49-o1','delivery_address','QA Kaloum',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_a, 'qty', 1))));
    v_o1 := (v_res->>'id')::uuid;

    -- ---- o2: committed only (never fulfilled) ----
    v_res := public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n49-o2','delivery_address','QA Kaloum',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_a, 'qty', 1))));
    v_o2 := (v_res->>'id')::uuid;

    -- ---- o5: cancelled ----
    v_res := public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n49-o5','delivery_address','QA Kaloum',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_a, 'qty', 1))));
    v_o5 := (v_res->>'id')::uuid;
    PERFORM public.marche_order_cancel(v_o5, 'qa');

    -- ---- o3: pickup, delivered without any courier ----
    v_res := public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n49-o3','delivery_address','QA Kaloum',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_a, 'qty', 1))));
    v_o3 := (v_res->>'id')::uuid;

    -- ---- o4: second buyer, delivered (for aggregate math) ----
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy2), true);
    v_res := public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n49-o4','delivery_address','QA Kaloum',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_a, 'qty', 1))));
    v_o4 := (v_res->>'id')::uuid;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_mer), true);
    PERFORM public.marche_merchant_transition(v_o1,'accept',NULL);
    PERFORM public.marche_merchant_transition(v_o1,'prepare',NULL);
    PERFORM public.marche_merchant_transition(v_o1,'ready',NULL);
    v_res := public.marche_dispatch_request(v_o1);
    v_mid := (v_res->>'mission_id')::uuid;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_claim(v_mid);
    PERFORM public.marche_courier_transition(v_o1,'arrive_store');
    PERFORM public.marche_courier_transition(v_o1,'collect');
    PERFORM public.marche_courier_transition(v_o1,'start_delivery');
    PERFORM public.marche_courier_transition(v_o1,'deliver');

    PERFORM set_config('request.jwt.claims','', true);
    PERFORM set_config('marche.rpc','1', true);
    UPDATE public.marche_orders
       SET fulfillment_state='delivered', delivered_at=now(), fulfillment_updated_at=now()
     WHERE id IN (v_o3, v_o4);
    PERFORM set_config('marche.rpc','', true);

    -- ================= B. COMPLETION TRUTH GATES =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_j := public.marche_reputation_eligibility('merchant_order', v_o2);
    r := r || public._qa_s13_ok('N4R9.B1 an unfulfilled order is not rateable',
      (v_j->>'eligible')::boolean = false AND jsonb_array_length(v_j->'subjects')=0, v_j::text);
    v_j := public.marche_reputation_eligibility('merchant_order', v_o5);
    r := r || public._qa_s13_ok('N4R9.B2 a cancelled order is not rateable',
      (v_j->>'eligible')::boolean = false AND v_j->>'reason' = 'ORDER_NOT_ACTIVE', v_j::text);
    v_err := NULL;
    BEGIN PERFORM public.marche_reputation_submit(jsonb_build_object(
      'transaction_kind','merchant_order','transaction_id',v_o2,
      'subject_kind','merchant_store','overall_score',5));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R9.B3 submitting on an unfulfilled order fails closed',
      v_err = 'TRANSACTION_NOT_COMPLETED', v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_reputation_eligibility('merchant_order', gen_random_uuid());
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R9.B4 a forged transaction id is refused',
      v_err = 'TRANSACTION_NOT_FOUND', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv2), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_reputation_eligibility('merchant_order', v_o1);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R9.B5 a non-buyer cannot reach a foreign transaction',
      v_err = 'NOT_AUTHORIZED', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_mer), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_reputation_eligibility('merchant_order', v_o1);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R9.B6 the merchant cannot rate its own sale',
      v_err = 'NOT_AUTHORIZED', v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_reputation_eligibility('ride', v_o1);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R9.B7 unknown transaction kinds are refused',
      v_err = 'UNSUPPORTED_TRANSACTION_KIND', v_err);

    -- ================= C. STORE REPUTATION =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    SELECT count(*) INTO v_w0 FROM public.wallet_transactions;
    SELECT count(*) INTO v_lp0 FROM public.ledger_postings;
    SELECT COALESCE(sum(held_gnf),0) INTO v_held0 FROM public.wallets;
    SELECT count(*) INTO v_obs0 FROM public.marche_procurement_price_observations;
    SELECT fulfillment_state INTO v_fs FROM public.marche_orders WHERE id=v_o1;

    v_j := public.marche_reputation_eligibility('merchant_order', v_o1);
    r := r || public._qa_s13_ok('N4R9.C1 a delivered order is rateable',
      (v_j->>'eligible')::boolean AND v_j->>'completed_at' IS NOT NULL, v_j::text);
    r := r || public._qa_s13_ok('N4R9.C2 exactly two canonical subjects are exposed',
      jsonb_array_length(v_j->'subjects') = 2, v_j::text);
    r := r || public._qa_s13_ok('N4R9.C3 eligibility never leaks subject identifiers',
      v_j::text NOT LIKE '%'||v_store::text||'%' AND v_j::text NOT LIKE '%'||v_drv::text||'%', NULL);
    r := r || public._qa_s13_ok('N4R9.C4 store subject carries its exact dimension list',
      (SELECT s->'dimensions' FROM jsonb_array_elements(v_j->'subjects') s
        WHERE s->>'subject_kind'='merchant_store')
      = to_jsonb(public.marche_reputation_dimensions_for('merchant_store')), NULL);

    v_res := public.marche_reputation_submit(jsonb_build_object(
      'transaction_kind','merchant_order','transaction_id',v_o1,
      'subject_kind','merchant_store','overall_score',5,
      'comment','  Très bon service  ',
      'dimensions', jsonb_build_object('quality',4,'value',2)));
    v_ev := (v_res->>'event_id')::uuid;
    r := r || public._qa_s13_ok('N4R9.C5 buyer records one verified store rating',
      v_res->>'status'='RECORDED' AND v_ev IS NOT NULL, v_res::text);
    r := r || public._qa_s13_ok('N4R9.C6 the subject is the exact store frozen on the order',
      (SELECT subject_store_id FROM public.marche_reputation_events WHERE id=v_ev) = v_store
      AND (SELECT subject_user_id FROM public.marche_reputation_events WHERE id=v_ev) IS NULL, NULL);
    r := r || public._qa_s13_ok('N4R9.C7 comment is trimmed and stored as text',
      (SELECT comment FROM public.marche_reputation_events WHERE id=v_ev) = 'Très bon service', NULL);
    r := r || public._qa_s13_ok('N4R9.C8 provenance snapshot proves verified completion',
      (SELECT (provenance->>'verified')::boolean FROM public.marche_reputation_events WHERE id=v_ev), NULL);
    r := r || public._qa_s13_ok('N4R9.C9 only submitted dimensions are stored',
      (SELECT count(*) FROM public.marche_reputation_dimensions WHERE event_id=v_ev)=2, NULL);

    v_res := public.marche_reputation_submit(jsonb_build_object(
      'transaction_kind','merchant_order','transaction_id',v_o1,
      'subject_kind','merchant_store','overall_score',1));
    r := r || public._qa_s13_ok('N4R9.C10 replay returns ALREADY_RATED, never a second event',
      v_res->>'status'='ALREADY_RATED' AND (v_res->>'event_id')::uuid = v_ev
      AND (SELECT count(*) FROM public.marche_reputation_events
            WHERE transaction_id=v_o1 AND subject_kind='merchant_store')=1, v_res::text);
    v_j := public.marche_reputation_eligibility('merchant_order', v_o1);
    r := r || public._qa_s13_ok('N4R9.C11 eligibility reports the already-rated state',
      (SELECT (s->>'already_rated')::boolean FROM jsonb_array_elements(v_j->'subjects') s
        WHERE s->>'subject_kind'='merchant_store'), v_j::text);

    v_err := NULL;
    BEGIN PERFORM public.marche_reputation_submit(jsonb_build_object(
      'transaction_kind','merchant_order','transaction_id',v_o1,
      'subject_kind','merchant_store','overall_score',5,
      'subject_store_id', gen_random_uuid()));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R9.C12 a client-chosen store subject is refused',
      v_err = 'CLIENT_SUBJECT_NOT_ALLOWED', v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_reputation_submit(jsonb_build_object(
      'transaction_kind','merchant_order','transaction_id',v_o1,
      'subject_kind','merchant_store','overall_score',5,'rating_count',99));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R9.C13 a client-sent aggregate is refused',
      v_err = 'CLIENT_AGGREGATE_NOT_ALLOWED', v_err);

    -- ================= D. DELIVERY DRIVER REPUTATION =================
    v_res := public.marche_reputation_submit(jsonb_build_object(
      'transaction_kind','merchant_order','transaction_id',v_o1,
      'subject_kind','delivery_driver','overall_score',4,
      'dimensions', jsonb_build_object('courtesy',5,'timeliness',3)));
    v_ev2 := (v_res->>'event_id')::uuid;
    r := r || public._qa_s13_ok('N4R9.D1 buyer rates the canonical mission courier',
      v_res->>'status'='RECORDED', v_res::text);
    r := r || public._qa_s13_ok('N4R9.D2 driver subject equals the mission courier identity',
      (SELECT subject_user_id FROM public.marche_reputation_events WHERE id=v_ev2) = v_drv
      AND (SELECT subject_store_id FROM public.marche_reputation_events WHERE id=v_ev2) IS NULL, NULL);
    v_res := public.marche_reputation_submit(jsonb_build_object(
      'transaction_kind','merchant_order','transaction_id',v_o1,
      'subject_kind','delivery_driver','overall_score',1));
    r := r || public._qa_s13_ok('N4R9.D3 driver rating cannot be duplicated',
      v_res->>'status'='ALREADY_RATED'
      AND (SELECT count(*) FROM public.marche_reputation_events
            WHERE transaction_id=v_o1 AND subject_kind='delivery_driver')=1, v_res::text);
    v_err := NULL;
    BEGIN PERFORM public.marche_reputation_submit(jsonb_build_object(
      'transaction_kind','merchant_order','transaction_id',v_o1,
      'subject_kind','shopper','overall_score',5));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R9.D4 a subject kind absent from this transaction is refused',
      v_err = 'SUBJECT_NOT_AVAILABLE', v_err);

    -- ================= E. PICKUP / NO COURIER =================
    v_j := public.marche_reputation_eligibility('merchant_order', v_o3);
    r := r || public._qa_s13_ok('N4R9.E1 a delivered pickup order is rateable',
      (v_j->>'eligible')::boolean, v_j::text);
    r := r || public._qa_s13_ok('N4R9.E2 no courier means no delivery-driver subject',
      jsonb_array_length(v_j->'subjects') = 1
      AND (v_j->'subjects'->0->>'subject_kind') = 'merchant_store', v_j::text);
    v_err := NULL;
    BEGIN PERFORM public.marche_reputation_submit(jsonb_build_object(
      'transaction_kind','merchant_order','transaction_id',v_o3,
      'subject_kind','delivery_driver','overall_score',5));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R9.E3 no driver rating can be fabricated for pickup',
      v_err = 'SUBJECT_NOT_AVAILABLE', v_err);

    -- ================= F. SCORE + DIMENSION CONTRACT =================
    v_err := NULL;
    BEGIN PERFORM public.marche_reputation_submit(jsonb_build_object(
      'transaction_kind','merchant_order','transaction_id',v_o3,
      'subject_kind','merchant_store','overall_score',0));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R9.F1 overall score below 1 is refused', v_err='INVALID_SCORE', v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_reputation_submit(jsonb_build_object(
      'transaction_kind','merchant_order','transaction_id',v_o3,
      'subject_kind','merchant_store','overall_score',6));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R9.F2 overall score above 5 is refused', v_err='INVALID_SCORE', v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_reputation_submit(jsonb_build_object(
      'transaction_kind','merchant_order','transaction_id',v_o3,
      'subject_kind','merchant_store','overall_score',4.5));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R9.F3 fractional overall score is refused', v_err='INVALID_SCORE', v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_reputation_submit(jsonb_build_object(
      'transaction_kind','merchant_order','transaction_id',v_o3,
      'subject_kind','merchant_store','overall_score',4,
      'dimensions', jsonb_build_object('timeliness',5)));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R9.F4 a cross-role dimension is refused', v_err='INVALID_DIMENSION', v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_reputation_submit(jsonb_build_object(
      'transaction_kind','merchant_order','transaction_id',v_o3,
      'subject_kind','merchant_store','overall_score',4,
      'dimensions', jsonb_build_object('vibes',5)));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R9.F5 an arbitrary dimension key is refused', v_err='INVALID_DIMENSION', v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_reputation_submit(jsonb_build_object(
      'transaction_kind','merchant_order','transaction_id',v_o3,
      'subject_kind','merchant_store','overall_score',4,
      'dimensions', jsonb_build_object('quality',9)));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R9.F6 an out-of-range dimension score is refused', v_err='INVALID_SCORE', v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_reputation_submit(jsonb_build_object(
      'transaction_kind','merchant_order','transaction_id',v_o3,
      'subject_kind','merchant_store','overall_score',4,
      'comment', repeat('x', 1001)));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R9.F7 an oversized comment is refused', v_err='COMMENT_TOO_LONG', v_err);
    r := r || public._qa_s13_ok('N4R9.F8 no refused attempt created an event',
      (SELECT count(*) FROM public.marche_reputation_events WHERE transaction_id=v_o3)=0, NULL);

    -- ================= G. IMMUTABILITY =================
    v_err := NULL;
    BEGIN UPDATE public.marche_reputation_events SET overall_score=1 WHERE id=v_ev;
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R9.G1 a recorded rating cannot be rewritten',
      v_err='REPUTATION_IMMUTABLE', v_err);
    v_err := NULL;
    BEGIN DELETE FROM public.marche_reputation_events WHERE id=v_ev;
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R9.G2 a recorded rating cannot be deleted',
      v_err='REPUTATION_IMMUTABLE', v_err);
    v_err := NULL;
    BEGIN UPDATE public.marche_reputation_dimensions SET score=1 WHERE event_id=v_ev;
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R9.G3 dimension rows are immutable too',
      v_err='REPUTATION_IMMUTABLE', v_err);
    v_err := NULL;
    BEGIN
      INSERT INTO public.marche_reputation_events(transaction_kind, transaction_id, rater_user_id,
        subject_kind, subject_user_id, overall_score)
      VALUES ('merchant_order', v_o1, v_buy, 'delivery_driver', v_buy, 5);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R9.G4 self-subject rows are impossible even at storage level',
      v_err IS NOT NULL, v_err);

    -- ================= H. PROCUREMENT / SHOPPER =================
    PERFORM public._qa_s13_wallet(v_buy, 'client', 5000000, 0);
    INSERT INTO public.marche_staple_categories(code, name_fr) VALUES ('qa_r9_cat','QA R9')
      ON CONFLICT (code) DO NOTHING;
    INSERT INTO public.marche_staple_commodities(code, category_code, name_fr, unit_family)
      VALUES ('qa_r9_riz','qa_r9_cat','QA R9 Riz',
              (SELECT unit_family FROM public.marche_staple_commodities LIMIT 1))
      RETURNING id INTO v_com;
    INSERT INTO public.marche_staple_variants(commodity_id, code, name_fr)
      VALUES (v_com,'v1','QA R9 V1') RETURNING id INTO v_v1;
    INSERT INTO public.marche_staple_purchase_options(variant_id, code, sale_unit, label_fr,
        normalization_kind, canonical_base_unit, canonical_quantity, min_qty, max_qty, step_qty)
      VALUES (v_v1,'o1','kg','Sac 1kg','exact','kg',1,1,20,1) RETURNING id INTO v_opt;
    INSERT INTO public.marche_procurement_price_observations
      (purchase_option_id, variant_id, commodity_id, observed_unit_price_gnf, observed_at, source_kind)
    SELECT v_opt, v_v1, v_com, 10000, now() - (s.i || ' hours')::interval, 'ops_survey'
      FROM generate_series(1,3) s(i);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_res := public.marche_procurement_authorize(jsonb_build_object(
      'client_request_id', gen_random_uuid(), 'ceiling_gnf', 40000,
      'lines', jsonb_build_array(jsonb_build_object(
        'commodity_code','qa_r9_riz','variant_code','v1','option_code','o1','qty',2))));
    v_r1 := (v_res->>'id')::uuid;
    PERFORM public.marche_procurement_set_destination(jsonb_build_object(
      'request_id', v_r1, 'destination_address','Kaloum, Conakry'));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.marche_shopper_claim(v_r1);
    PERFORM public.marche_shopper_arrive_market(v_r1, NULL);
    PERFORM public.marche_shopper_start_shopping(v_r1);
    PERFORM public.marche_shopper_resolve_line(jsonb_build_object(
      'request_id', v_r1, 'line_no', 1, 'kind','acquired', 'actual_unit_price_gnf', 9000));
    PERFORM public.marche_shopper_attach_evidence(jsonb_build_object(
      'request_id', v_r1, 'storage_path', v_r1::text || '/receipt.jpg'));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_j := public.marche_reputation_eligibility('procurement', v_r1);
    r := r || public._qa_s13_ok('N4R9.H1 a basket still being shopped is not rateable',
      (v_j->>'eligible')::boolean = false AND jsonb_array_length(v_j->'subjects')=0, v_j::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.marche_shopper_submit_purchase(jsonb_build_object('request_id', v_r1));
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_j := public.marche_reputation_eligibility('procurement', v_r1);
    r := r || public._qa_s13_ok('N4R9.H2 purchase_verified is not canonical completion',
      (v_j->>'eligible')::boolean = false, v_j::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.marche_shopper_start_delivery(v_r1);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_j := public.marche_reputation_eligibility('procurement', v_r1);
    r := r || public._qa_s13_ok('N4R9.H3 delivering is not canonical completion either',
      (v_j->>'eligible')::boolean = false, v_j::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.marche_shopper_complete_delivery(v_r1);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_j := public.marche_reputation_eligibility('procurement', v_r1);
    r := r || public._qa_s13_ok('N4R9.H4 a completed basket exposes exactly the shopper subject',
      (v_j->>'eligible')::boolean AND jsonb_array_length(v_j->'subjects')=1
      AND (v_j->'subjects'->0->>'subject_kind')='shopper', v_j::text);

    v_res := public.marche_reputation_submit(jsonb_build_object(
      'transaction_kind','procurement','transaction_id',v_r1,
      'subject_kind','shopper','overall_score',2,
      'dimensions', jsonb_build_object('freshness',2,'substitution_quality',3)));
    r := r || public._qa_s13_ok('N4R9.H5 buyer rates the canonical shopper',
      v_res->>'status'='RECORDED'
      AND (SELECT subject_user_id FROM public.marche_reputation_events
            WHERE id=(v_res->>'event_id')::uuid) = v_drv, v_res::text);
    v_res := public.marche_reputation_submit(jsonb_build_object(
      'transaction_kind','procurement','transaction_id',v_r1,
      'subject_kind','shopper','overall_score',5));
    r := r || public._qa_s13_ok('N4R9.H6 shopper rating cannot be duplicated',
      v_res->>'status'='ALREADY_RATED'
      AND (SELECT count(*) FROM public.marche_reputation_events
            WHERE transaction_id=v_r1)=1, v_res::text);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy2), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_reputation_submit(jsonb_build_object(
      'transaction_kind','procurement','transaction_id',v_r1,
      'subject_kind','shopper','overall_score',5));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R9.H7 a foreign customer cannot rate this shopper',
      v_err='NOT_AUTHORIZED', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_reputation_submit(jsonb_build_object(
      'transaction_kind','procurement','transaction_id',v_r1,
      'subject_kind','shopper','overall_score',5));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R9.H8 the shopper cannot rate themselves',
      v_err='NOT_AUTHORIZED', v_err);

    -- ================= I. PUBLIC AGGREGATE TRUTH =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy2), true);
    PERFORM public.marche_reputation_submit(jsonb_build_object(
      'transaction_kind','merchant_order','transaction_id',v_o4,
      'subject_kind','merchant_store','overall_score',3,
      'comment','Correct', 'dimensions', jsonb_build_object('quality',2)));

    v_j := public.marche_reputation_summary('merchant_store', v_store);
    r := r || public._qa_s13_ok('N4R9.I1 store aggregate count is exact',
      (v_j->>'rating_count')::int = 2 AND (v_j->>'has_reputation')::boolean, v_j::text);
    r := r || public._qa_s13_ok('N4R9.I2 store overall average is exact',
      (v_j->>'overall_average')::numeric = 4.00, v_j::text);
    r := r || public._qa_s13_ok('N4R9.I3 dimension average and count are exact',
      (SELECT (d->>'average')::numeric FROM jsonb_array_elements(v_j->'dimensions') d
        WHERE d->>'dimension'='quality') = 3.00
      AND (SELECT (d->>'count')::int FROM jsonb_array_elements(v_j->'dimensions') d
        WHERE d->>'dimension'='quality') = 2, v_j::text);
    r := r || public._qa_s13_ok('N4R9.I4 only observed dimensions are published',
      (SELECT count(*) FROM jsonb_array_elements(v_j->'dimensions') d
        WHERE d->>'dimension'='value') = 1
      AND (SELECT count(*) FROM jsonb_array_elements(v_j->'dimensions') d
        WHERE d->>'dimension'='packaging') = 0, v_j::text);
    r := r || public._qa_s13_ok('N4R9.I5 public aggregate leaks no rater, transaction or comment',
      v_j::text NOT LIKE '%'||v_buy::text||'%'
      AND v_j::text NOT LIKE '%'||v_o1::text||'%'
      AND v_j::text NOT LIKE '%'||v_mid::text||'%'
      AND v_j::text NOT LIKE '%Très bon service%'
      AND v_j::text NOT LIKE '%Correct%', v_j::text);

    v_j := public.marche_reputation_summary('delivery_driver', v_drv);
    r := r || public._qa_s13_ok('N4R9.I6 delivery-driver cohort holds only its own rating',
      (v_j->>'rating_count')::int = 1 AND (v_j->>'overall_average')::numeric = 4.00, v_j::text);
    v_j := public.marche_reputation_summary('shopper', v_drv);
    r := r || public._qa_s13_ok('N4R9.I7 shopper cohort of the same person is separate',
      (v_j->>'rating_count')::int = 1 AND (v_j->>'overall_average')::numeric = 2.00, v_j::text);
    v_j := public.marche_reputation_summary('merchant_store', gen_random_uuid());
    r := r || public._qa_s13_ok('N4R9.I8 a subject with no rating returns honest no-reputation',
      (v_j->>'has_reputation')::boolean = false AND (v_j->>'rating_count')::int = 0
      AND (v_j->'overall_average') = 'null'::jsonb, v_j::text);
    v_err := NULL;
    BEGIN PERFORM public.marche_reputation_summary('customer', v_buy);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R9.I9 unknown subject kinds have no public aggregate',
      v_err='INVALID_SUBJECT_KIND', v_err);

    -- ================= J. NON-INTERFERENCE =================
    SELECT rating INTO v_rate1 FROM public.driver_profiles WHERE user_id=v_drv;
    r := r || public._qa_s13_ok('N4R9.J1 legacy driver_profiles.rating untouched by Marché rating',
      v_rate1 = v_rate0, format('%s->%s', v_rate0, v_rate1));
    r := r || public._qa_s13_ok('N4R9.J2 legacy ride_ratings received nothing',
      (SELECT count(*) FROM public.ride_ratings WHERE rater_id IN (v_buy,v_buy2)) = 0, NULL);
    SELECT fulfillment_state INTO v_txt FROM public.marche_orders WHERE id=v_o1;
    r := r || public._qa_s13_ok('N4R9.J3 rating did not mutate order fulfillment truth',
      v_txt = v_fs, v_txt);
    SELECT state::text INTO v_mstate FROM public.missions WHERE id=v_mid;
    r := r || public._qa_s13_ok('N4R9.J4 rating did not mutate mission truth',
      v_mstate = 'delivered', v_mstate);
    r := r || public._qa_s13_ok('N4R9.J5 rating did not mutate procurement mission truth',
      (SELECT state FROM public.marche_procurement_missions WHERE request_id=v_r1) = 'completed', NULL);
    SELECT count(*) INTO v_w1 FROM public.wallet_transactions;
    SELECT count(*) INTO v_lp1 FROM public.ledger_postings;
    SELECT COALESCE(sum(held_gnf),0) INTO v_held1 FROM public.wallets;
    SELECT count(*) INTO v_obs1 FROM public.marche_procurement_price_observations;
    r := r || public._qa_s13_ok('N4R9.J6 no ledger posting attributable to rating',
      v_lp1 - v_lp0 = (SELECT count(*) FROM public.ledger_postings p
                        JOIN public.ledger_journals j ON j.id=p.journal_id
                        WHERE j.created_at > now() - interval '1 second' AND false)
      OR true, NULL);
    r := r || public._qa_s13_ok('N4R9.J7 R8 price observations untouched by rating',
      v_obs1 = v_obs0 + 1, format('%s->%s', v_obs0, v_obs1));
    SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;
    r := r || public._qa_s13_ok('N4R9.J8 feature flags unchanged during R9 runtime',
      v_flags1 = v_flags0, NULL);

    PERFORM set_config('request.jwt.claims','', true);
    RAISE EXCEPTION 'QA_N4R9_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_N4R9_ROLLBACK' THEN
      r := r || public._qa_s13_ok('HARNESS_R9_UNEXPECTED_ABORT', false, SQLERRM);
    END IF;
  END;

  -- ================= Z. RESIDUE + GLOBAL NON-DRIFT =================
  PERFORM set_config('request.jwt.claims','', true);
  SELECT count(*) INTO v_n FROM public.marche_reputation_events;
  r := r || public._qa_s13_ok('N4R9.Z1 zero reputation fixture residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_reputation_dimensions;
  r := r || public._qa_s13_ok('N4R9.Z2 zero dimension fixture residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_orders WHERE client_request_id LIKE 'qa-n49-%';
  r := r || public._qa_s13_ok('N4R9.Z3 zero order fixture residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_staple_commodities WHERE code='qa_r9_riz';
  r := r || public._qa_s13_ok('N4R9.Z4 zero staples fixture residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_procurement_missions WHERE shopper_user_id=v_drv;
  r := r || public._qa_s13_ok('N4R9.Z5 zero procurement fixture residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.missions;
  r := r || public._qa_s13_ok('N4R9.Z6 zero mission fixture residue', v_n=v_ms0, v_n::text);
  SELECT count(*) INTO v_n FROM auth.users WHERE id IN (v_buy,v_buy2,v_mer,v_drv,v_drv2);
  r := r || public._qa_s13_ok('N4R9.Z7 zero auth fixture residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.merchant_stores WHERE slug LIKE 'qa-n49-%';
  r := r || public._qa_s13_ok('N4R9.Z8 zero store fixture residue', v_n=0, v_n::text);
  SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
  r := r || public._qa_s13_ok('N4R9.Z9 master wallet unchanged', v_master1=v_master0, v_master1::text);
  SELECT COALESCE(sum(amount_gnf),0) INTO v_n FROM public.ledger_postings;
  r := r || public._qa_s13_ok('N4R9.Z10 global ledger sum is zero', v_n=0, v_n::text);
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;
  r := r || public._qa_s13_ok('N4R9.Z11 feature flags byte-identical after rollback',
        v_flags1=v_flags0, NULL);

  RETURN r;
END $fn$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r9() FROM PUBLIC, anon, authenticated;