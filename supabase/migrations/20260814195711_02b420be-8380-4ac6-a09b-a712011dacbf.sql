CREATE OR REPLACE FUNCTION public._qa_node3_repas_r9_recovery_flows_fxcore()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_cust uuid; v_cust2 uuid; v_merch uuid; v_drv uuid;
  v_store uuid; v_resto uuid; v_item uuid; v_item2 uuid;
  v_req uuid; v_req2 uuid; v_req3 uuid;
  v_o1 uuid; v_o2 uuid; v_o3 uuid;
  v_res jsonb; v_res2 jsonb; v_rs jsonb; v_t jsonb; v_err text;
  v_n int; v_n2 int; v_def text; v_code text; v_mission uuid;
  v_master0 bigint; v_master1 bigint; v_flags0 jsonb; v_flags1 jsonb;
  v_state text; v_jr int; v_jr2 int;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;

  -- ============ P0. STATIC SHAPE / SECURITY ============
  r := r || public._qa_s13_ok('P0.1 repas_order_resume exists',
        to_regprocedure('public.repas_order_resume(uuid)') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('P0.2 resume is closed to anon',
        NOT has_function_privilege('anon','public.repas_order_resume(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('P0.3 resume is granted to authenticated',
        has_function_privilege('authenticated','public.repas_order_resume(uuid)','EXECUTE'), NULL);
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='repas_order_resume'
     AND p.prosecdef AND p.proconfig @> ARRAY['search_path=public'];
  r := r || public._qa_s13_ok('P0.4 resume is definer + pinned search_path', v_n = 1, v_n::text);
  SELECT provolatile INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='repas_order_resume';
  r := r || public._qa_s13_ok('P0.5 resume is read-only (non-volatile)', v_def = 's', v_def);
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='repas_order_resume';
  r := r || public._qa_s13_ok('P0.6 resume fails closed on anonymous callers',
        v_def LIKE '%NOT_AUTHENTICATED%', NULL);
  r := r || public._qa_s13_ok('P0.7 resume is scoped to the calling customer',
        v_def LIKE '%user_id = v_uid%', NULL);
  r := r || public._qa_s13_ok('P0.8 resume never writes durable state',
        v_def NOT LIKE '%INSERT INTO%' AND v_def NOT LIKE '%UPDATE public.%', NULL);
  r := r || public._qa_s13_ok('P0.9 this harness is closed to anon/authenticated',
        NOT has_function_privilege('anon','public._qa_node3_repas_r9_recovery_flows()','EXECUTE')
    AND NOT has_function_privilege('authenticated','public._qa_node3_repas_r9_recovery_flows()','EXECUTE'), NULL);
  SELECT count(*) INTO v_n FROM pg_indexes
   WHERE schemaname='public' AND tablename='food_orders'
     AND indexdef LIKE '%client_request_id%';
  r := r || public._qa_s13_ok('P0.10 client_request_id is indexed for replay resolution', v_n >= 1, v_n::text);
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='repas_order_create';
  r := r || public._qa_s13_ok('P0.11 create still guards replays with a request fingerprint',
        v_def LIKE '%request_fingerprint%', NULL);
  r := r || public._qa_s13_ok('P0.12 create still locks the replay row',
        v_def LIKE '%FOR UPDATE%', NULL);

  BEGIN
    -- ============ FIXTURES ============
    v_cust := gen_random_uuid(); v_cust2 := gen_random_uuid();
    v_merch := gen_random_uuid(); v_drv := gen_random_uuid();
    PERFORM public._qa_s13_user(v_cust,'n3r9c');
    PERFORM public._qa_s13_user(v_cust2,'n3r9x');
    PERFORM public._qa_s13_user(v_merch,'n3r9m');
    PERFORM public._qa_s13_user(v_drv,'n3r9d');
    PERFORM public._qa_s13_wallet(v_cust,'client',3000000,0);
    PERFORM public._qa_s13_wallet(v_cust2,'client',900000,0);
    PERFORM public._qa_s13_wallet(v_merch,'merchant',0,0);
    PERFORM public._qa_s13_wallet(v_drv,'driver',900000,0);

    INSERT INTO public.merchant_stores(owner_user_id, slug, name, delivery_available, status)
      VALUES (v_merch, 'qa-n3r9-store-'||substr(v_merch::text,1,8), 'QA N3R9 Store', true, 'active')
      RETURNING id INTO v_store;
    INSERT INTO public.food_restaurants(owner_user_id, merchant_store_id, slug, name, status,
        is_open, delivery_available, pickup_available, choppay_enabled, prep_time_min,
        latitude, longitude)
      VALUES (v_merch, v_store, 'qa-n3r9-resto-'||substr(v_merch::text,1,8), 'QA N3R9 Resto',
              'active', true, true, true, true, 20, 9.5370, -13.6785)
      RETURNING id INTO v_resto;
    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
      VALUES (v_resto,'QA R9 Plat A',100000,true) RETURNING id INTO v_item;
    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
      VALUES (v_resto,'QA R9 Plat B',50000,true) RETURNING id INTO v_item2;

    UPDATE public.feature_flags SET enabled = true WHERE key = 'chop_pay_checkout_enabled';

    -- ============ P1. RESUME AUTHORIZATION ============
    v_req := gen_random_uuid();
    PERFORM set_config('request.jwt.claims', ''::text, true);
    BEGIN PERFORM public.repas_order_resume(v_req); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P1.1 anonymous resume is refused',
          v_err LIKE '%NOT_AUTHENTICATED%', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    BEGIN PERFORM public.repas_order_resume(NULL); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P1.2 a missing request id is refused explicitly',
          v_err LIKE '%CLIENT_REQUEST_ID_REQUIRED%', v_err);

    v_rs := public.repas_order_resume(v_req);
    r := r || public._qa_s13_ok('P1.3 an unknown request id resolves to not-found, not an error',
          (v_rs->>'ok')::boolean AND (v_rs->>'found')::boolean IS FALSE, v_rs::text);

    -- ============ P2. COMMIT + REPLAY IS ONE CANONICAL ORDER ============
    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1),
                          jsonb_build_object('menu_item_id',v_item2,'qty',2)),
        'pickup','choppay', v_req);
    v_o1 := (v_res->>'order_id')::uuid;
    r := r || public._qa_s13_ok('P2.1 the first commit creates a real order', v_o1 IS NOT NULL, v_res::text);

    v_rs := public.repas_order_resume(v_req);
    r := r || public._qa_s13_ok('P2.2 resume after an unknown outcome finds the canonical order',
          (v_rs->>'found')::boolean AND (v_rs->>'order_id')::uuid = v_o1, v_rs::text);
    r := r || public._qa_s13_ok('P2.3 resume reports server-truth state',
          v_rs->>'state' = (SELECT state::text FROM public.food_orders WHERE id=v_o1), v_rs->>'state');
    r := r || public._qa_s13_ok('P2.4 resume reports the frozen order total',
          (v_rs->>'order_total_gnf')::bigint
            = (SELECT order_total_gnf FROM public.food_orders WHERE id=v_o1), v_rs->>'order_total_gnf');
    r := r || public._qa_s13_ok('P2.5 a pickup resume exposes no mission',
          v_rs->>'mission_id' IS NULL, v_rs->>'mission_id');
    r := r || public._qa_s13_ok('P2.6 resume leaks no internal pricing snapshot',
          NOT (v_rs ? 'pricing_snapshot') AND NOT (v_rs ? 'pricing_policy_id')
          AND NOT (v_rs ? 'courier_payout_gnf'), v_rs::text);

    SELECT count(*) INTO v_n FROM public.ledger_journals WHERE created_at >= now() - interval '5 minutes';
    v_res2 := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1),
                          jsonb_build_object('menu_item_id',v_item2,'qty',2)),
        'pickup','choppay', v_req);
    SELECT count(*) INTO v_n2 FROM public.ledger_journals WHERE created_at >= now() - interval '5 minutes';
    r := r || public._qa_s13_ok('P2.7 a retry with the same request id returns the same order',
          (v_res2->>'order_id')::uuid = v_o1, v_res2::text);
    r := r || public._qa_s13_ok('P2.8 the retry is declared a replay',
          (v_res2->>'replay')::boolean IS TRUE, v_res2::text);
    r := r || public._qa_s13_ok('P2.9 the retry posts no additional ledger journal', v_n = v_n2,
          v_n::text||'/'||v_n2::text);
    SELECT count(*) INTO v_n FROM public.food_orders WHERE client_request_id = v_req;
    r := r || public._qa_s13_ok('P2.10 exactly one order exists for the request id', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.chop_pay_order_runtime
     WHERE source_module='repas' AND source_id = v_o1;
    r := r || public._qa_s13_ok('P2.11 exactly one Chop Pay runtime exists for the order', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_module='repas' AND source_id = v_o1;
    r := r || public._qa_s13_ok('P2.12 the replay placed no second customer hold', v_n <= 1, v_n::text);

    -- a mutated cart on the same request id must never silently reuse the order
    BEGIN
      PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',5)),
        'pickup','choppay', v_req);
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P2.13 a different cart on the same request id is refused',
          v_err <> 'NO_ERROR', v_err);
    SELECT count(*) INTO v_n FROM public.food_orders WHERE client_request_id = v_req;
    r := r || public._qa_s13_ok('P2.14 the refusal created no extra order', v_n = 1, v_n::text);

    -- ============ P3. RESUME IS OWNER-SCOPED ============
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust2), true);
    v_rs := public.repas_order_resume(v_req);
    r := r || public._qa_s13_ok('P3.1 a stranger resolving the same request id finds nothing',
          (v_rs->>'found')::boolean IS FALSE, v_rs::text);
    r := r || public._qa_s13_ok('P3.2 the stranger response leaks no order id',
          v_rs::text NOT LIKE '%'||v_o1::text||'%', v_rs::text);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_rs := public.repas_order_resume(v_req);
    r := r || public._qa_s13_ok('P3.3 the merchant cannot resume a customer request id',
          (v_rs->>'found')::boolean IS FALSE, v_rs::text);

    -- ============ P4. MERCHANT DOUBLE-SUBMIT IS IDEMPOTENT ============
    v_t := public.repas_order_tracking(v_o1);
    r := r || public._qa_s13_ok('P4.1 merchant sees accept before any transition',
          v_t->'allowed_actions' @> '["accept"]'::jsonb, v_t->>'allowed_actions');
    SELECT count(*) INTO v_jr FROM public.ledger_journals WHERE created_at >= now() - interval '5 minutes';
    v_res := public.repas_merchant_transition(v_o1,'accept');
    v_res2 := public.repas_merchant_transition(v_o1,'accept');
    SELECT count(*) INTO v_jr2 FROM public.ledger_journals WHERE created_at >= now() - interval '5 minutes';
    r := r || public._qa_s13_ok('P4.2 the first accept advances the order',
          (v_res->>'idempotent')::boolean IS FALSE AND v_res->>'state' = 'confirmed', v_res::text);
    r := r || public._qa_s13_ok('P4.3 the replayed accept is declared idempotent',
          (v_res2->>'idempotent')::boolean IS TRUE, v_res2::text);
    r := r || public._qa_s13_ok('P4.4 the replayed accept leaves the state unchanged',
          (SELECT state::text FROM public.food_orders WHERE id=v_o1) = 'confirmed', NULL);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_module='repas' AND source_id = v_o1;
    r := r || public._qa_s13_ok('P4.5 the replayed accept placed no second hold', v_n <= 2, v_n::text);

    PERFORM public.repas_merchant_transition(v_o1,'prepare');
    v_res2 := public.repas_merchant_transition(v_o1,'prepare');
    r := r || public._qa_s13_ok('P4.6 the replayed prepare is idempotent',
          (v_res2->>'idempotent')::boolean IS TRUE
          AND (SELECT state::text FROM public.food_orders WHERE id=v_o1) = 'preparing', v_res2::text);
    PERFORM public.repas_merchant_transition(v_o1,'ready');
    v_res2 := public.repas_merchant_transition(v_o1,'ready');
    r := r || public._qa_s13_ok('P4.7 the replayed ready is idempotent',
          (v_res2->>'idempotent')::boolean IS TRUE
          AND (SELECT state::text FROM public.food_orders WHERE id=v_o1) = 'ready', v_res2::text);

    -- an out-of-order action after a stale UI must be refused, not applied
    BEGIN PERFORM public.repas_merchant_transition(v_o1,'accept'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P4.8 a stale accept on a ready order is harmless',
          (SELECT state::text FROM public.food_orders WHERE id=v_o1) = 'ready', v_err);

    -- ============ P5. CUSTODY REFUSAL LEAVES TRUTH UNCHANGED ============
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_code := public.repas_custody_code_view(v_o1,'customer_pickup')->>'code';
    r := r || public._qa_s13_ok('P5.1 the customer holds a real pickup code',
          v_code IS NOT NULL AND length(v_code) >= 4, NULL);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    BEGIN
      v_res := public.repas_custody_confirm_pickup_collection(v_o1, '000000');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_res := NULL; v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P5.2 a wrong code never completes the order',
          (SELECT state::text FROM public.food_orders WHERE id=v_o1) = 'ready',
          COALESCE(v_res::text, v_err));
    v_res := public.repas_custody_confirm_pickup_collection(v_o1, v_code);
    r := r || public._qa_s13_ok('P5.3 the correct code completes the order',
          (SELECT state::text FROM public.food_orders WHERE id=v_o1) = 'completed', v_res::text);
    BEGIN
      v_res2 := public.repas_custody_confirm_pickup_collection(v_o1, v_code);
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_res2 := NULL; v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P5.4 replaying a consumed code moves nothing',
          (SELECT state::text FROM public.food_orders WHERE id=v_o1) = 'completed',
          COALESCE(v_res2::text, v_err));
    SELECT count(*) INTO v_n FROM public.repas_custody_events
     WHERE order_id = v_o1 AND boundary = 'customer_pickup';
    r := r || public._qa_s13_ok('P5.5 exactly one pickup custody event was recorded', v_n = 1, v_n::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_rs := public.repas_order_resume(v_req);
    r := r || public._qa_s13_ok('P5.6 resume rehydrates the terminal state after reload',
          v_rs->>'state' = 'completed', v_rs->>'state');
    r := r || public._qa_s13_ok('P5.7 resume total is unchanged by the whole lifecycle',
          (v_rs->>'order_total_gnf')::bigint
            = (public.repas_order_receipt(v_o1)->>'order_total_gnf')::bigint, v_rs->>'order_total_gnf');

    -- ============ P6. CANCELLATION REPLAY ============
    v_req2 := gen_random_uuid();
    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item2,'qty',1)),
        'pickup','choppay', v_req2);
    v_o2 := (v_res->>'order_id')::uuid;
    v_res := public.repas_customer_cancel_order(v_o2,'QA R9 double tap');
    v_res2 := public.repas_customer_cancel_order(v_o2,'QA R9 double tap');
    r := r || public._qa_s13_ok('P6.1 the first cancel is applied',
          (v_res->>'idempotent')::boolean IS FALSE AND v_res->>'state' = 'cancelled', v_res::text);
    r := r || public._qa_s13_ok('P6.2 the replayed cancel is declared idempotent',
          (v_res2->>'idempotent')::boolean IS TRUE, v_res2::text);
    SELECT count(*) INTO v_n FROM public.customer_cancellation_debts
     WHERE source_module='repas' AND source_id = v_o2;
    r := r || public._qa_s13_ok('P6.3 cancellation never produced a duplicate debt row', v_n <= 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_module='repas' AND source_id = v_o2 AND (captured_gnf + released_gnf) > amount_gnf;
    r := r || public._qa_s13_ok('P6.4 no hold was over-consumed by the cancel replay', v_n = 0, v_n::text);
    v_rs := public.repas_order_resume(v_req2);
    r := r || public._qa_s13_ok('P6.5 resume reports the cancelled order, not a lost one',
          (v_rs->>'found')::boolean AND v_rs->>'state' = 'cancelled', v_rs::text);
    -- a retry of the original commit after cancellation must NOT resurrect a new order
    v_res2 := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item2,'qty',1)),
        'pickup','choppay', v_req2);
    r := r || public._qa_s13_ok('P6.6 a late retry after cancellation returns the cancelled order',
          (v_res2->>'order_id')::uuid = v_o2, v_res2::text);
    SELECT count(*) INTO v_n FROM public.food_orders WHERE client_request_id = v_req2;
    r := r || public._qa_s13_ok('P6.7 the late retry created no second order', v_n = 1, v_n::text);

    -- ============ P7. DELIVERY RECOVERY ============
    v_req3 := gen_random_uuid();
    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'delivery','choppay', v_req3, 'QA R9 Adresse', 9.5395, -13.6760);
    v_o3 := (v_res->>'order_id')::uuid;
    SELECT id INTO v_mission FROM public.missions WHERE ref_food_order_id = v_o3 LIMIT 1;
    r := r || public._qa_s13_ok('P7.1 the delivery commit created exactly one mission',
          v_mission IS NOT NULL, v_res::text);
    v_res2 := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'delivery','choppay', v_req3, 'QA R9 Adresse', 9.5395, -13.6760);
    SELECT count(*) INTO v_n FROM public.missions WHERE ref_food_order_id = v_o3;
    r := r || public._qa_s13_ok('P7.2 the delivery retry created no second mission', v_n = 1, v_n::text);
    r := r || public._qa_s13_ok('P7.3 the delivery retry returns the same order',
          (v_res2->>'order_id')::uuid = v_o3, v_res2::text);
    v_rs := public.repas_order_resume(v_req3);
    r := r || public._qa_s13_ok('P7.4 resume exposes the mission for a delivery order',
          (v_rs->>'mission_id')::uuid = v_mission, v_rs::text);
    v_t := public.repas_order_tracking(v_o3);
    r := r || public._qa_s13_ok('P7.5 resume and tracking agree on state',
          v_rs->>'state' = v_t->>'state', v_rs->>'state'||'/'||(v_t->>'state'));

    -- ============ P8. NO FINANCIAL DAMAGE FROM RECOVERY ============
    SELECT count(*) INTO v_n FROM (
      SELECT j.id FROM public.ledger_journals j
        JOIN public.ledger_postings p ON p.journal_id = j.id
       WHERE j.created_at >= now() - interval '5 minutes'
       GROUP BY j.id HAVING sum(p.amount_gnf) <> 0) z;
    r := r || public._qa_s13_ok('P8.1 every journal created here is zero-sum', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_module='repas' AND source_id IN (v_o1, v_o2, v_o3)
       AND (captured_gnf + released_gnf) > amount_gnf;
    r := r || public._qa_s13_ok('P8.2 no hold is over-consumed', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.food_orders
     WHERE client_request_id IN (v_req, v_req2, v_req3);
    r := r || public._qa_s13_ok('P8.3 three request ids produced exactly three orders', v_n = 3, v_n::text);

    PERFORM set_config('request.jwt.claims', ''::text, true);
    RAISE EXCEPTION 'QA_NODE3_R9_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_NODE3_R9_ROLLBACK' THEN
      r := r || public._qa_s13_ok('HARNESS aborted before completion', false, SQLERRM);
    END IF;
  END;

  PERFORM set_config('request.jwt.claims', ''::text, true);
  SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;
  r := r || public._qa_s13_ok('Z9.1 master wallet unchanged after fixture rollback',
        v_master0 IS NOT DISTINCT FROM v_master1, v_master1::text);
  r := r || public._qa_s13_ok('Z9.2 feature flags byte-identical after fixture rollback',
        v_flags0 = v_flags1, NULL);
  SELECT count(*) INTO v_n FROM public.food_restaurants WHERE slug LIKE 'qa-n3r9-%';
  r := r || public._qa_s13_ok('Z9.3 no restaurant fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.food_menu_items WHERE name LIKE 'QA R9 %';
  r := r || public._qa_s13_ok('Z9.4 no menu fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM auth.users WHERE email LIKE 'qa-s13-n3r9%';
  r := r || public._qa_s13_ok('Z9.5 no QA user residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.missions WHERE dropoff_address LIKE 'QA R9 %';
  r := r || public._qa_s13_ok('Z9.6 no mission residue', v_n = 0, v_n::text);

  RETURN jsonb_build_object('part','node3_repas_r9_recovery_flows',
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'results', r);
END; $function$;

CREATE OR REPLACE FUNCTION public._qa_node3_repas_r9_recovery_flows()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_out jsonb; BEGIN
  PERFORM set_config('app.repas_fixture_verified','1', true);
  v_out := public._qa_node3_repas_r9_recovery_flows_fxcore();
  PERFORM set_config('app.repas_fixture_verified','', true);
  RETURN v_out; END; $function$;

REVOKE ALL ON FUNCTION public._qa_node3_repas_r9_recovery_flows() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._qa_node3_repas_r9_recovery_flows_fxcore() FROM PUBLIC, anon, authenticated;