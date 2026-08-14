CREATE OR REPLACE FUNCTION public._qa_node3_repas_r7_tracking_receipt()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_cust uuid; v_cust2 uuid; v_merch uuid; v_drv uuid;
  v_store uuid; v_resto uuid; v_item uuid; v_item2 uuid;
  v_o1 uuid; v_o2 uuid; v_res jsonb; v_err text; v_n int; v_def text;
  v_master0 bigint; v_master1 bigint; v_flags0 jsonb; v_flags1 jsonb;
  v_t jsonb; v_rc jsonb; v_rc2 jsonb; v_code text; v_mission uuid;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;

  -- ============ P0. STATIC SHAPE / SECURITY ============
  r := r || public._qa_s13_ok('P0.1 repas_order_tracking exists',
        to_regprocedure('public.repas_order_tracking(uuid)') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('P0.2 repas_order_receipt exists',
        to_regprocedure('public.repas_order_receipt(uuid)') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('P0.3 mission_earnings exists',
        to_regprocedure('public.mission_earnings(uuid[])') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('P0.4 tracking closed to anon',
        NOT has_function_privilege('anon','public.repas_order_tracking(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('P0.5 receipt closed to anon',
        NOT has_function_privilege('anon','public.repas_order_receipt(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('P0.6 mission_earnings closed to anon',
        NOT has_function_privilege('anon','public.mission_earnings(uuid[])','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('P0.7 tracking is granted to authenticated',
        has_function_privilege('authenticated','public.repas_order_tracking(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('P0.8 receipt is granted to authenticated',
        has_function_privilege('authenticated','public.repas_order_receipt(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('P0.9 this harness is closed to anon/authenticated',
        NOT has_function_privilege('anon','public._qa_node3_repas_r7_tracking_receipt()','EXECUTE')
    AND NOT has_function_privilege('authenticated','public._qa_node3_repas_r7_tracking_receipt()','EXECUTE'), NULL);

  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname IN ('repas_order_tracking','repas_order_receipt','mission_earnings')
     AND p.prosecdef AND p.proconfig @> ARRAY['search_path=public'];
  r := r || public._qa_s13_ok('P0.10 all three read models are definer + pinned search_path', v_n = 3, v_n::text);

  -- Column-level revocation (raw leakage closed)
  r := r || public._qa_s13_ok('P0.11 authenticated cannot read missions.estimated_earning_gnf',
        NOT has_column_privilege('authenticated','public.missions','estimated_earning_gnf','SELECT'), NULL);
  r := r || public._qa_s13_ok('P0.12 anon cannot read missions.estimated_earning_gnf',
        NOT has_column_privilege('anon','public.missions','estimated_earning_gnf','SELECT'), NULL);
  r := r || public._qa_s13_ok('P0.13 authenticated cannot read food_orders.courier_payout_gnf',
        NOT has_column_privilege('authenticated','public.food_orders','courier_payout_gnf','SELECT'), NULL);
  r := r || public._qa_s13_ok('P0.14 authenticated cannot read food_orders.pricing_snapshot',
        NOT has_column_privilege('authenticated','public.food_orders','pricing_snapshot','SELECT'), NULL);
  r := r || public._qa_s13_ok('P0.15 authenticated cannot read food_orders.pricing_policy_id',
        NOT has_column_privilege('authenticated','public.food_orders','pricing_policy_id','SELECT'), NULL);
  r := r || public._qa_s13_ok('P0.16 authenticated cannot read food_orders.promotion_id',
        NOT has_column_privilege('authenticated','public.food_orders','promotion_id','SELECT'), NULL);
  -- Non-vacuous counterpart: the operational columns are still readable.
  r := r || public._qa_s13_ok('P0.17 authenticated still reads food_orders.state',
        has_column_privilege('authenticated','public.food_orders','state','SELECT'), NULL);
  r := r || public._qa_s13_ok('P0.18 authenticated still reads food_orders.order_total_gnf',
        has_column_privilege('authenticated','public.food_orders','order_total_gnf','SELECT'), NULL);
  r := r || public._qa_s13_ok('P0.19 authenticated still reads missions.state',
        has_column_privilege('authenticated','public.missions','state','SELECT'), NULL);

  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='repas_order_tracking';
  r := r || public._qa_s13_ok('P0.20 tracking fails closed on anonymous callers',
        v_def LIKE '%NOT_AUTHENTICATED%' AND v_def LIKE '%NOT_AUTHORIZED%', NULL);
  r := r || public._qa_s13_ok('P0.21 tracking derives merchant actions server-side',
        v_def LIKE '%allowed_actions%', NULL);
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='repas_order_receipt';
  r := r || public._qa_s13_ok('P0.22 receipt fails closed on anonymous callers',
        v_def LIKE '%NOT_AUTHENTICATED%' AND v_def LIKE '%NOT_AUTHORIZED%', NULL);
  r := r || public._qa_s13_ok('P0.23 receipt reconciles totals server-side',
        v_def LIKE '%totals_reconcile%', NULL);
  r := r || public._qa_s13_ok('P0.24 receipt lines use the frozen name snapshot',
        v_def LIKE '%name_snapshot%', NULL);

  BEGIN
    -- ============ FIXTURES ============
    v_cust := gen_random_uuid(); v_cust2 := gen_random_uuid();
    v_merch := gen_random_uuid(); v_drv := gen_random_uuid();
    PERFORM public._qa_s13_user(v_cust,'n3r7c');
    PERFORM public._qa_s13_user(v_cust2,'n3r7x');
    PERFORM public._qa_s13_user(v_merch,'n3r7m');
    PERFORM public._qa_s13_user(v_drv,'n3r7d');
    PERFORM public._qa_s13_wallet(v_cust,'client',2000000,0);
    PERFORM public._qa_s13_wallet(v_cust2,'client',900000,0);
    PERFORM public._qa_s13_wallet(v_merch,'merchant',0,0);
    PERFORM public._qa_s13_wallet(v_drv,'driver',900000,0);

    INSERT INTO public.merchant_stores(owner_user_id, slug, name, delivery_available, status)
      VALUES (v_merch, 'qa-n3r7-store-'||substr(v_merch::text,1,8), 'QA N3R7 Store', true, 'active')
      RETURNING id INTO v_store;
    INSERT INTO public.food_restaurants(owner_user_id, merchant_store_id, slug, name, status,
        is_open, delivery_available, pickup_available, choppay_enabled, prep_time_min)
      VALUES (v_merch, v_store, 'qa-n3r7-resto-'||substr(v_merch::text,1,8), 'QA N3R7 Resto',
              'active', true, true, true, true, 20)
      RETURNING id INTO v_resto;
    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
      VALUES (v_resto,'QA R7 Plat A',100000,true) RETURNING id INTO v_item;
    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
      VALUES (v_resto,'QA R7 Plat B',50000,true) RETURNING id INTO v_item2;

    UPDATE public.feature_flags SET enabled = true WHERE key = 'chop_pay_checkout_enabled';

    -- ============ P1. UNAUTHENTICATED / STRANGER FAIL-CLOSED ============
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1),
                          jsonb_build_object('menu_item_id',v_item2,'qty',2)),
        'pickup','choppay', gen_random_uuid());
    v_o1 := (v_res->>'order_id')::uuid;
    r := r || public._qa_s13_ok('P1.0 pickup Chop Pay fixture order committed', v_o1 IS NOT NULL, v_res::text);

    PERFORM set_config('request.jwt.claims', ''::text, true);
    BEGIN PERFORM public.repas_order_tracking(v_o1); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P1.1 anonymous tracking is refused',
          v_err LIKE '%NOT_AUTHENTICATED%', v_err);
    BEGIN PERFORM public.repas_order_receipt(v_o1); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P1.2 anonymous receipt is refused',
          v_err LIKE '%NOT_AUTHENTICATED%', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust2), true);
    BEGIN PERFORM public.repas_order_tracking(v_o1); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P1.3 a stranger cannot track someone else''s order',
          v_err LIKE '%NOT_AUTHORIZED%', v_err);
    BEGIN PERFORM public.repas_order_receipt(v_o1); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P1.4 a stranger cannot read someone else''s receipt',
          v_err LIKE '%NOT_AUTHORIZED%', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    BEGIN PERFORM public.repas_order_tracking(gen_random_uuid()); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P1.5 unknown order id is refused explicitly',
          v_err LIKE '%ORDER_NOT_FOUND%', v_err);

    -- ============ P2. CUSTOMER TRACKING TRUTH + ZERO LEAKAGE ============
    v_t := public.repas_order_tracking(v_o1);
    r := r || public._qa_s13_ok('P2.1 customer role is server-assigned',
          v_t->>'viewer_role' = 'customer', v_t->>'viewer_role');
    r := r || public._qa_s13_ok('P2.2 tracking state matches the order row',
          v_t->>'state' = (SELECT state::text FROM public.food_orders WHERE id=v_o1), v_t->>'state');
    r := r || public._qa_s13_ok('P2.3 fulfillment is pickup', v_t->>'fulfillment' = 'pickup', v_t->>'fulfillment');
    r := r || public._qa_s13_ok('P2.4 a pickup order exposes no mission',
          v_t->'mission' = 'null'::jsonb OR v_t->>'mission' IS NULL, v_t->>'mission');
    r := r || public._qa_s13_ok('P2.5 order total is server truth',
          (v_t->>'order_total_gnf')::bigint
            = (SELECT order_total_gnf FROM public.food_orders WHERE id=v_o1),
          v_t->>'order_total_gnf');
    r := r || public._qa_s13_ok('P2.6 customer never receives merchant next actions',
          NOT (v_t ? 'allowed_actions'), v_t::text);
    r := r || public._qa_s13_ok('P2.7 customer never receives courier payout',
          NOT (v_t ? 'courier_payout_gnf'), NULL);
    r := r || public._qa_s13_ok('P2.8 customer never receives the pricing snapshot',
          NOT (v_t ? 'pricing_snapshot') AND NOT (v_t ? 'pricing_policy_id'), NULL);
    r := r || public._qa_s13_ok('P2.9 customer never receives another party''s contact block',
          NOT (v_t ? 'customer'), NULL);
    r := r || public._qa_s13_ok('P2.10 order is not terminal at placed',
          (v_t->>'terminal')::boolean IS FALSE, v_t->>'terminal');
    r := r || public._qa_s13_ok('P2.11 custody projection carries no code material',
          v_t::text NOT LIKE '%code_hash%' AND v_t::text NOT LIKE '%code_secret_id%', NULL);

    -- ============ P3. MERCHANT ACTION TRUTH ============
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_t := public.repas_order_tracking(v_o1);
    r := r || public._qa_s13_ok('P3.1 merchant role is server-assigned',
          v_t->>'viewer_role' = 'merchant', v_t->>'viewer_role');
    r := r || public._qa_s13_ok('P3.2 placed order offers accept + reject',
          v_t->'allowed_actions' @> '["accept","reject"]'::jsonb
          AND jsonb_array_length(v_t->'allowed_actions') = 2, v_t->>'allowed_actions');
    r := r || public._qa_s13_ok('P3.3 merchant sees no ready action before preparing',
          NOT (v_t->'allowed_actions' @> '["ready"]'::jsonb), v_t->>'allowed_actions');

    PERFORM public.repas_merchant_transition(v_o1,'accept');
    v_t := public.repas_order_tracking(v_o1);
    r := r || public._qa_s13_ok('P3.4 accepted order offers prepare',
          v_t->'allowed_actions' @> '["prepare"]'::jsonb, v_t->>'allowed_actions');
    r := r || public._qa_s13_ok('P3.5 accepted order no longer offers accept',
          NOT (v_t->'allowed_actions' @> '["accept"]'::jsonb), v_t->>'allowed_actions');

    PERFORM public.repas_merchant_transition(v_o1,'prepare');
    v_t := public.repas_order_tracking(v_o1);
    r := r || public._qa_s13_ok('P3.6 preparing order offers ready only',
          v_t->'allowed_actions' = '["ready"]'::jsonb, v_t->>'allowed_actions');

    PERFORM public.repas_merchant_transition(v_o1,'ready');
    v_t := public.repas_order_tracking(v_o1);
    r := r || public._qa_s13_ok('P3.7 ready pickup order offers the collection handover',
          v_t->'allowed_actions' = '["pickup_collection"]'::jsonb, v_t->>'allowed_actions');
    r := r || public._qa_s13_ok('P3.8 merchant sees the customer contact block',
          v_t ? 'customer', NULL);
    r := r || public._qa_s13_ok('P3.9 merchant tracking exposes no courier payout',
          NOT (v_t ? 'courier_payout_gnf'), NULL);

    -- ============ P4. RECEIPT IS FROZEN ITEMIZED TRUTH ============
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_rc := public.repas_order_receipt(v_o1);
    r := r || public._qa_s13_ok('P4.1 receipt is itemized',
          jsonb_array_length(v_rc->'items') = 2, v_rc->>'items');
    r := r || public._qa_s13_ok('P4.2 line quantities and unit prices are frozen',
          (SELECT sum((e->>'line_total_gnf')::bigint) FROM jsonb_array_elements(v_rc->'items') e) = 200000,
          v_rc->>'items_line_total_gnf');
    r := r || public._qa_s13_ok('P4.3 merchandise subtotal equals the sum of lines',
          (v_rc->>'items_line_total_gnf')::bigint = (v_rc->>'merchandise_subtotal_gnf')::bigint,
          v_rc->>'merchandise_subtotal_gnf');
    r := r || public._qa_s13_ok('P4.4 pickup receipt carries no delivery fee',
          (v_rc->>'delivery_fee_gnf')::bigint = 0, v_rc->>'delivery_fee_gnf');
    r := r || public._qa_s13_ok('P4.5 platform fee is the policy 1% of merchandise',
          (v_rc->>'platform_fee_gnf')::bigint = 2000, v_rc->>'platform_fee_gnf');
    r := r || public._qa_s13_ok('P4.6 total = merchandise + livraison + frais',
          (v_rc->>'order_total_gnf')::bigint = 202000, v_rc->>'order_total_gnf');
    r := r || public._qa_s13_ok('P4.7 the server declares the totals reconciled',
          (v_rc->>'totals_reconcile')::boolean, v_rc->>'totals_reconcile');
    r := r || public._qa_s13_ok('P4.8 receipt total matches the committed order row',
          (v_rc->>'order_total_gnf')::bigint
            = (SELECT order_total_gnf FROM public.food_orders WHERE id=v_o1), NULL);
    r := r || public._qa_s13_ok('P4.9 receipt total matches the Chop Pay runtime',
          (v_rc->>'order_total_gnf')::bigint
            = (SELECT order_total_gnf FROM public.chop_pay_order_runtime
                WHERE source_module='repas' AND source_id=v_o1), NULL);
    r := r || public._qa_s13_ok('P4.10 customer receipt hides the courier payout',
          NOT (v_rc ? 'courier_payout_gnf'), NULL);
    r := r || public._qa_s13_ok('P4.11 receipt is not marked cancelled',
          (v_rc->>'cancelled')::boolean IS FALSE, v_rc->>'cancelled');

    -- Immutability: menu changes after checkout must never rewrite the receipt.
    UPDATE public.food_menu_items SET price_gnf = 999000, name = 'QA R7 Plat A RENAMED'
     WHERE id = v_item;
    UPDATE public.food_menu_items SET is_available = false WHERE id = v_item2;
    v_rc2 := public.repas_order_receipt(v_o1);
    r := r || public._qa_s13_ok('P4.12 a later menu price change does not alter the receipt total',
          (v_rc2->>'order_total_gnf')::bigint = (v_rc->>'order_total_gnf')::bigint,
          v_rc2->>'order_total_gnf');
    r := r || public._qa_s13_ok('P4.13 receipt lines stay byte-identical after a menu change',
          v_rc2->'items' = v_rc->'items', v_rc2->>'items');
    r := r || public._qa_s13_ok('P4.14 the frozen line name is the snapshot, not the new name',
          v_rc2::text NOT LIKE '%RENAMED%', NULL);
    UPDATE public.food_menu_items SET price_gnf = 100000, name = 'QA R7 Plat A' WHERE id = v_item;
    UPDATE public.food_menu_items SET is_available = true WHERE id = v_item2;

    -- ============ P5. TERMINAL TRUTH AFTER REAL COMPLETION ============
    v_code := public.repas_custody_code_view(v_o1,'customer_pickup')->>'code';
    r := r || public._qa_s13_ok('P5.1 the customer holds a real pickup code',
          v_code IS NOT NULL AND length(v_code) >= 4, NULL);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    PERFORM public.repas_custody_confirm_pickup_collection(v_o1, v_code);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_t := public.repas_order_tracking(v_o1);
    r := r || public._qa_s13_ok('P5.2 completed order reports terminal',
          (v_t->>'terminal')::boolean, v_t->>'terminal');
    r := r || public._qa_s13_ok('P5.3 completed order state is completed',
          v_t->>'state' = 'completed', v_t->>'state');
    r := r || public._qa_s13_ok('P5.4 no custody credential remains pending after completion',
          (SELECT count(*) FROM jsonb_array_elements(v_t->'custody'->'credentials') e
            WHERE (e->>'consumed')::boolean IS FALSE AND (e->>'locked')::boolean IS FALSE) = 0,
          v_t->'custody'->>'credentials');
    v_rc2 := public.repas_order_receipt(v_o1);
    r := r || public._qa_s13_ok('P5.5 the receipt records the completion timestamp',
          (v_rc2->>'completed_at') IS NOT NULL, v_rc2->>'completed_at');
    r := r || public._qa_s13_ok('P5.6 the receipt carries the custody handover evidence',
          jsonb_array_length(v_rc2->'custody_timeline') >= 1, v_rc2->>'custody_timeline');
    r := r || public._qa_s13_ok('P5.7 completion did not change the frozen total',
          (v_rc2->>'order_total_gnf')::bigint = (v_rc->>'order_total_gnf')::bigint, NULL);
    r := r || public._qa_s13_ok('P5.8 totals still reconcile after completion',
          (v_rc2->>'totals_reconcile')::boolean, NULL);

    -- ============ P6. DELIVERY ORDER — MISSION + EARNINGS AUTHORIZATION ============
    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'delivery','choppay', gen_random_uuid(), 'QA R7 Adresse', 9.535, -13.677);
    v_o2 := (v_res->>'order_id')::uuid;
    SELECT id INTO v_mission FROM public.missions WHERE ref_food_order_id = v_o2 LIMIT 1;
    r := r || public._qa_s13_ok('P6.1 a delivery order creates a courier mission',
          v_mission IS NOT NULL, v_res::text);
    v_t := public.repas_order_tracking(v_o2);
    r := r || public._qa_s13_ok('P6.2 customer tracking projects the mission state',
          (v_t->'mission'->>'id')::uuid = v_mission, v_t->>'mission');
    r := r || public._qa_s13_ok('P6.3 no courier contact is exposed before assignment',
          (v_t->'mission'->>'courier_assigned')::boolean IS FALSE
          AND COALESCE(v_t->>'courier','null') IN ('null',''), v_t->>'courier');
    r := r || public._qa_s13_ok('P6.4 delivery receipt carries a real delivery fee',
          (public.repas_order_receipt(v_o2)->>'delivery_fee_gnf')::bigint > 0, NULL);
    r := r || public._qa_s13_ok('P6.5 delivery receipt reconciles',
          (public.repas_order_receipt(v_o2)->>'totals_reconcile')::boolean, NULL);

    v_res := public.mission_earnings(ARRAY[v_mission]);
    r := r || public._qa_s13_ok('P6.6 the customer cannot read the courier earning',
          NOT (v_res ? v_mission::text), v_res::text);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust2), true);
    v_res := public.mission_earnings(ARRAY[v_mission]);
    r := r || public._qa_s13_ok('P6.7 a stranger cannot read the courier earning',
          NOT (v_res ? v_mission::text), v_res::text);
    BEGIN PERFORM public.repas_order_tracking(v_o2); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P6.8 an unassigned stranger cannot track the delivery',
          v_err LIKE '%NOT_AUTHORIZED%', v_err);
    PERFORM set_config('request.jwt.claims', ''::text, true);
    v_res := public.mission_earnings(ARRAY[v_mission]);
    r := r || public._qa_s13_ok('P6.9 anonymous callers read no earnings at all',
          v_res = '{}'::jsonb, v_res::text);

    -- ============ P7. NO FINANCIAL SIDE EFFECT FROM READS ============
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    SELECT count(*) INTO v_n FROM (
      SELECT j.id FROM public.ledger_journals j
        JOIN public.ledger_postings p ON p.journal_id = j.id
       WHERE j.created_at >= now() - interval '5 minutes'
       GROUP BY j.id HAVING sum(p.amount_gnf) <> 0) z;
    r := r || public._qa_s13_ok('P7.1 every journal created here is zero-sum', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_module='repas' AND source_id IN (v_o1, v_o2)
       AND (captured_gnf + released_gnf) > amount_gnf;
    r := r || public._qa_s13_ok('P7.2 no hold is over-consumed', v_n = 0, v_n::text);

    PERFORM set_config('request.jwt.claims', ''::text, true);
    RAISE EXCEPTION 'QA_NODE3_R7_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_NODE3_R7_ROLLBACK' THEN
      r := r || public._qa_s13_ok('HARNESS aborted before completion', false, SQLERRM);
    END IF;
  END;

  PERFORM set_config('request.jwt.claims', ''::text, true);
  SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;
  r := r || public._qa_s13_ok('Z7.1 master wallet unchanged after fixture rollback',
        v_master0 IS NOT DISTINCT FROM v_master1, v_master1::text);
  r := r || public._qa_s13_ok('Z7.2 feature flags byte-identical after fixture rollback',
        v_flags0 = v_flags1, NULL);
  SELECT count(*) INTO v_n FROM public.food_restaurants WHERE slug LIKE 'qa-n3r7-%';
  r := r || public._qa_s13_ok('Z7.3 no restaurant fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.food_menu_items WHERE name LIKE 'QA R7 %';
  r := r || public._qa_s13_ok('Z7.4 no menu fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.chop_pay_order_runtime c
    JOIN auth.users u ON u.id = c.customer_user_id WHERE u.email LIKE 'qa-s13-n3r7%';
  r := r || public._qa_s13_ok('Z7.5 no Chop Pay runtime residue', v_n = 0, v_n::text);

  RETURN jsonb_build_object('part','node3_repas_r7_tracking_receipt',
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'results', r);
END; $function$;

REVOKE ALL ON FUNCTION public._qa_node3_repas_r7_tracking_receipt() FROM PUBLIC, anon, authenticated;