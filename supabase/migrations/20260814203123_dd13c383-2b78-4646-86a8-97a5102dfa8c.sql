CREATE OR REPLACE FUNCTION public._qa_node3_repas_r10_operations_fxcore()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_cust uuid; v_cust2 uuid; v_merch uuid; v_drv uuid; v_ops uuid; v_god uuid;
  v_store uuid; v_resto uuid; v_item uuid; v_item2 uuid;
  v_oA uuid; v_oB uuid; v_oC uuid; v_oD uuid; v_oE uuid;
  v_res jsonb; v_res2 jsonb; v_q jsonb; v_d jsonb; v_err text; v_def text;
  v_n int; v_row jsonb; v_case uuid;
  v_rq uuid; v_rq2 uuid; v_rq3 uuid;
  v_code text; v_code2 text; v_bal0 bigint; v_bal1 bigint; v_jr int; v_jr2 int;
  v_master0 bigint; v_master1 bigint; v_flags0 jsonb; v_flags1 jsonb;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;

  -- ================= P0. STATIC SHAPE / SECURITY =================
  r := r || public._qa_s13_ok('P0.1 ops queue RPC exists',
        to_regprocedure('public.repas_ops_queue(text,text,int)') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('P0.2 ops case detail RPC exists',
        to_regprocedure('public.repas_ops_case_detail(uuid)') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('P0.3 ops command RPC exists',
        to_regprocedure('public.repas_ops_command(uuid,text,uuid,text,text,jsonb)') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('P0.4 anon cannot execute the ops queue',
        NOT has_function_privilege('anon','public.repas_ops_queue(text,text,int)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('P0.5 anon cannot execute the ops detail',
        NOT has_function_privilege('anon','public.repas_ops_case_detail(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('P0.6 anon cannot execute the ops command',
        NOT has_function_privilege('anon','public.repas_ops_command(uuid,text,uuid,text,text,jsonb)','EXECUTE'), NULL);
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname IN ('repas_ops_queue','repas_ops_case_detail','repas_ops_command')
     AND p.prosecdef AND p.proconfig @> ARRAY['search_path=public'];
  r := r || public._qa_s13_ok('P0.7 all three ops RPCs are definer with a pinned search_path',
        v_n = 3, v_n::text);
  r := r || public._qa_s13_ok('P0.8 the queue is read-only (non-volatile)',
        (SELECT provolatile FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
          WHERE n.nspname='public' AND p.proname='repas_ops_queue') = 's', NULL);
  r := r || public._qa_s13_ok('P0.9 the case detail is read-only (non-volatile)',
        (SELECT provolatile FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
          WHERE n.nspname='public' AND p.proname='repas_ops_case_detail') = 's', NULL);
  r := r || public._qa_s13_ok('P0.10 authenticated has no read on ops cases',
        NOT has_table_privilege('authenticated','public.repas_ops_cases','SELECT'), NULL);
  r := r || public._qa_s13_ok('P0.11 authenticated has no write on ops cases',
        NOT has_table_privilege('authenticated','public.repas_ops_cases','INSERT')
    AND NOT has_table_privilege('authenticated','public.repas_ops_cases','UPDATE')
    AND NOT has_table_privilege('authenticated','public.repas_ops_cases','DELETE'), NULL);
  r := r || public._qa_s13_ok('P0.12 authenticated has no read on the ops timeline',
        NOT has_table_privilege('authenticated','public.repas_ops_events','SELECT'), NULL);
  r := r || public._qa_s13_ok('P0.13 authenticated has no write on the ops timeline',
        NOT has_table_privilege('authenticated','public.repas_ops_events','INSERT')
    AND NOT has_table_privilege('authenticated','public.repas_ops_events','UPDATE')
    AND NOT has_table_privilege('authenticated','public.repas_ops_events','DELETE'), NULL);
  r := r || public._qa_s13_ok('P0.14 anon has no access to ops tables at all',
        NOT has_table_privilege('anon','public.repas_ops_cases','SELECT')
    AND NOT has_table_privilege('anon','public.repas_ops_events','SELECT'), NULL);
  r := r || public._qa_s13_ok('P0.15 RLS is enabled on both ops tables',
        (SELECT bool_and(relrowsecurity) FROM pg_class
          WHERE relname IN ('repas_ops_cases','repas_ops_events')
            AND relnamespace = 'public'::regnamespace), NULL);
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='repas_ops_command';
  r := r || public._qa_s13_ok('P0.16 the command plane never deletes canonical order rows',
        v_def NOT LIKE '%DELETE FROM public.food_orders%'
    AND v_def NOT LIKE '%DELETE FROM public.missions%', NULL);
  r := r || public._qa_s13_ok('P0.17 authenticated has no write on the ledger',
        NOT has_table_privilege('authenticated','public.ledger_journals','INSERT')
    AND NOT has_table_privilege('authenticated','public.ledger_postings','INSERT'), NULL);
  r := r || public._qa_s13_ok('P0.18 authenticated cannot edit custody credentials',
        NOT has_table_privilege('authenticated','public.repas_custody_credentials','UPDATE'), NULL);
  SELECT count(*) INTO v_n FROM pg_trigger
   WHERE tgrelid = 'public.repas_ops_events'::regclass AND NOT tgisinternal;
  r := r || public._qa_s13_ok('P0.19 an append-only trigger guards the ops timeline', v_n >= 1, v_n::text);
  r := r || public._qa_s13_ok('P0.20 this harness is closed to anon/authenticated',
        NOT has_function_privilege('anon','public._qa_node3_repas_r10_operations()','EXECUTE')
    AND NOT has_function_privilege('authenticated','public._qa_node3_repas_r10_operations()','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('P0.21 the command plane has no mark-delivered escape hatch',
        v_def NOT LIKE '%customer_confirmed_at%' AND v_def NOT LIKE '%repas_custody_events%', NULL);
  r := r || public._qa_s13_ok('P0.22 the command plane never touches wallets or the ledger directly',
        v_def NOT LIKE '%public.wallets%' AND v_def NOT LIKE '%ledger_postings%'
        AND v_def NOT LIKE '%_ledger_post%', NULL);
  r := r || public._qa_s13_ok('P0.23 reassignment is declared unavailable in source',
        v_def LIKE '%NO_CERTIFIED_REASSIGNMENT_PRIMITIVE%', NULL);
  r := r || public._qa_s13_ok('P0.24 economic cancellation routes through the certified admin engine',
        v_def LIKE '%admin_chop_pay_cancel%', NULL);
  r := r || public._qa_s13_ok('P0.25 dispute resolution routes through certified admin engines',
        v_def LIKE '%admin_chop_pay_dispute_resolve%'
        AND v_def LIKE '%admin_cash_order_dispute_resolve%', NULL);

  BEGIN
    -- ================= FIXTURES =================
    v_cust := gen_random_uuid(); v_cust2 := gen_random_uuid();
    v_merch := gen_random_uuid(); v_drv := gen_random_uuid();
    v_ops := gen_random_uuid(); v_god := gen_random_uuid();
    PERFORM public._qa_s13_user(v_cust,'n3r10c');
    PERFORM public._qa_s13_user(v_cust2,'n3r10x');
    PERFORM public._qa_s13_user(v_merch,'n3r10m');
    PERFORM public._qa_s13_user(v_drv,'n3r10d');
    PERFORM public._qa_s13_user(v_ops,'n3r10o');
    PERFORM public._qa_s13_user(v_god,'n3r10g');
    PERFORM public._qa_s13_wallet(v_cust,'client',5000000,0);
    PERFORM public._qa_s13_wallet(v_cust2,'client',900000,0);
    PERFORM public._qa_s13_wallet(v_merch,'merchant',0,0);
    PERFORM public._qa_s13_wallet(v_drv,'driver',900000,0);
    INSERT INTO public.admin_users(user_id, admin_role, status)
      VALUES (v_ops,'operations_admin','active')
      ON CONFLICT (user_id) DO UPDATE SET admin_role='operations_admin', status='active';
    PERFORM public._qa_s13_admin(v_god);

    INSERT INTO public.merchant_stores(owner_user_id, slug, name, delivery_available, status)
      VALUES (v_merch, 'qa-n3r10-store-'||substr(v_merch::text,1,8), 'QA N3R10 Store', true, 'active')
      RETURNING id INTO v_store;
    INSERT INTO public.food_restaurants(owner_user_id, merchant_store_id, slug, name, status,
        is_open, delivery_available, pickup_available, choppay_enabled, prep_time_min,
        latitude, longitude)
      VALUES (v_merch, v_store, 'qa-n3r10-resto-'||substr(v_merch::text,1,8), 'QA N3R10 Resto',
              'active', true, true, true, true, 20, 9.5370, -13.6785)
      RETURNING id INTO v_resto;
    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
      VALUES (v_resto,'QA R10 Plat A',100000,true) RETURNING id INTO v_item;
    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
      VALUES (v_resto,'QA R10 Plat B',50000,true) RETURNING id INTO v_item2;
    UPDATE public.feature_flags SET enabled = true WHERE key = 'chop_pay_checkout_enabled';

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'delivery','choppay', gen_random_uuid(), 'QA R10 Adresse', 9.5395, -13.6760);
    v_oA := (v_res->>'order_id')::uuid;
    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item2,'qty',1)),
        'pickup','choppay', gen_random_uuid());
    v_oB := (v_res->>'order_id')::uuid;
    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',2)),
        'pickup','choppay', gen_random_uuid());
    v_oC := (v_res->>'order_id')::uuid;
    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item2,'qty',2)),
        'pickup','choppay', gen_random_uuid());
    v_oD := (v_res->>'order_id')::uuid;
    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item2,'qty',1)),
        'pickup','choppay', gen_random_uuid());
    v_oE := (v_res->>'order_id')::uuid;

    -- Age order A so a real never-accepted condition exists.
    PERFORM set_config('chopchop.cash_engine','1',true);
    UPDATE public.food_orders SET created_at = now() - interval '95 minutes' WHERE id = v_oA;
    PERFORM set_config('chopchop.cash_engine','0',true);

    -- ================= P1. NON-OPS CALLERS ARE REFUSED =================
    PERFORM set_config('request.jwt.claims', ''::text, true);
    BEGIN PERFORM public.repas_ops_queue(); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P1.1 an anonymous caller cannot open the ops queue',
          v_err LIKE '%NOT_AUTHENTICATED%', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    BEGIN PERFORM public.repas_ops_queue(); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P1.2 a customer cannot list the ops queue',
          v_err LIKE '%NOT_AUTHORIZED%', v_err);
    BEGIN PERFORM public.repas_ops_case_detail(v_oA); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P1.3 a customer cannot read an ops case detail',
          v_err LIKE '%NOT_AUTHORIZED%', v_err);
    BEGIN PERFORM public.repas_ops_command(v_oA,'open_case',gen_random_uuid(),'order_stuck','QA note');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P1.4 a customer cannot execute an ops command',
          v_err LIKE '%NOT_AUTHORIZED%', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    BEGIN PERFORM public.repas_ops_queue(); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P1.5 a restaurant owner cannot list the ops queue',
          v_err LIKE '%NOT_AUTHORIZED%', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    BEGIN PERFORM public.repas_ops_command(v_oA,'add_note',gen_random_uuid(),NULL,'QA note');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P1.6 a courier cannot execute an ops command',
          v_err LIKE '%NOT_AUTHORIZED%', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust2), true);
    BEGIN PERFORM public.repas_ops_case_detail(v_oB); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P1.7 an unrelated customer cannot read another order case',
          v_err LIKE '%NOT_AUTHORIZED%', v_err);

    -- ================= P2. OPS READ ACCESS WORKS =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_ops), true);
    v_q := public.repas_ops_queue('attention', v_oA::text, 50);
    r := r || public._qa_s13_ok('P2.1 an operations admin can open the queue',
          (v_q->>'ok')::boolean, v_q->>'ok');
    r := r || public._qa_s13_ok('P2.2 the queue reports the caller tier',
          v_q->>'actor_role' = 'operations_admin', v_q->>'actor_role');
    r := r || public._qa_s13_ok('P2.3 the queue declares reassignment unavailable',
          (v_q->>'reassignment_available')::boolean IS FALSE, v_q->>'reassignment_available');
    v_row := v_q->'rows'->0;
    r := r || public._qa_s13_ok('P2.4 the aged order surfaces in the attention queue',
          (v_row->>'order_id')::uuid = v_oA, v_q::text);
    r := r || public._qa_s13_ok('P2.5 the aged order is flagged for attention',
          (v_row->>'attention')::boolean IS TRUE, v_row->>'attention_flags');
    r := r || public._qa_s13_ok('P2.6 the flag names the real stuck condition',
          v_row->'attention_flags' @> '["awaiting_merchant_accept"]'::jsonb,
          v_row->>'attention_flags');
    r := r || public._qa_s13_ok('P2.7 the queue exposes a server-derived age',
          (v_row->>'age_minutes')::int >= 90, v_row->>'age_minutes');
    r := r || public._qa_s13_ok('P2.8 the queue carries canonical order state',
          v_row->>'state' = (SELECT state::text FROM public.food_orders WHERE id=v_oA),
          v_row->>'state');
    r := r || public._qa_s13_ok('P2.9 the queue leaks no custody secret',
          NOT (v_row ? 'code') AND v_row::text NOT LIKE '%code_hash%', NULL);

    v_q := public.repas_ops_queue('attention', v_oB::text, 50);
    r := r || public._qa_s13_ok('P2.10 a healthy fresh order is not fabricated into the queue',
          jsonb_array_length(v_q->'rows') = 0, v_q->>'count');
    v_q := public.repas_ops_queue('active', v_oB::text, 50);
    r := r || public._qa_s13_ok('P2.11 the healthy order is still visible under the active filter',
          jsonb_array_length(v_q->'rows') = 1, v_q->>'count');
    r := r || public._qa_s13_ok('P2.12 the healthy order carries no attention flag',
          (v_q->'rows'->0->>'attention')::boolean IS FALSE, v_q->'rows'->0->>'attention_flags');
    BEGIN PERFORM public.repas_ops_queue('whatever'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P2.13 an unknown filter is refused', v_err LIKE '%INVALID_FILTER%', v_err);

    v_d := public.repas_ops_case_detail(v_oA);
    r := r || public._qa_s13_ok('P2.14 the case detail resolves for ops', (v_d->>'ok')::boolean, NULL);
    r := r || public._qa_s13_ok('P2.15 the detail exposes payment engine truth',
          v_d->'payment'->>'engine_state' IS NOT NULL, v_d->'payment'->>'engine_state');
    r := r || public._qa_s13_ok('P2.16 the detail exposes mission truth for a delivery order',
          v_d->'mission'->>'mission_id' IS NOT NULL, v_d->>'mission');
    r := r || public._qa_s13_ok('P2.17 the detail has no case before one is opened',
          v_d->'case' = 'null'::jsonb OR v_d->>'case' IS NULL, v_d->>'case');
    r := r || public._qa_s13_ok('P2.18 the detail offers open_case as the entry action',
          v_d->'allowed_actions' @> '["open_case"]'::jsonb, v_d->>'allowed_actions');
    r := r || public._qa_s13_ok('P2.19 the detail never exposes a custody code',
          v_d::text NOT LIKE '%"code"%', NULL);
    r := r || public._qa_s13_ok('P2.20 the detail declares reassignment unavailable with a reason',
          (v_d->>'reassignment_available')::boolean IS FALSE
          AND v_d->>'reassignment_reason' = 'NO_CERTIFIED_REASSIGNMENT_PRIMITIVE', NULL);

    -- ================= P3. CASE LIFECYCLE + IMMUTABLE TIMELINE =================
    v_rq := gen_random_uuid();
    v_res := public.repas_ops_command(v_oA,'open_case',v_rq,'order_stuck','QA R10 commande bloquee');
    v_case := (v_res->>'case_id')::uuid;
    r := r || public._qa_s13_ok('P3.1 ops can open a case', v_case IS NOT NULL, v_res::text);
    r := r || public._qa_s13_ok('P3.2 the first command is not a replay',
          (v_res->>'replay')::boolean IS FALSE, v_res::text);
    SELECT count(*) INTO v_n FROM public.repas_ops_events WHERE food_order_id = v_oA;
    r := r || public._qa_s13_ok('P3.3 exactly one timeline event was appended', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.repas_ops_events
     WHERE food_order_id = v_oA AND actor_user_id = v_ops AND actor_role = 'operations_admin'
       AND reason_code = 'order_stuck' AND request_id = v_rq
       AND before_state IS NOT NULL AND after_state IS NOT NULL AND created_at IS NOT NULL;
    r := r || public._qa_s13_ok('P3.4 the event records actor, tier, reason, request id and snapshots',
          v_n = 1, v_n::text);

    v_res2 := public.repas_ops_command(v_oA,'open_case',v_rq,'order_stuck','QA R10 commande bloquee');
    r := r || public._qa_s13_ok('P3.5 an identical replay is declared a replay',
          (v_res2->>'replay')::boolean IS TRUE, v_res2::text);
    r := r || public._qa_s13_ok('P3.6 the replay returns the same canonical case',
          (v_res2->>'case_id')::uuid = v_case, v_res2::text);
    SELECT count(*) INTO v_n FROM public.repas_ops_events WHERE food_order_id = v_oA;
    r := r || public._qa_s13_ok('P3.7 the replay appended no second event', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.repas_ops_cases WHERE food_order_id = v_oA;
    r := r || public._qa_s13_ok('P3.8 the replay created no second case', v_n = 1, v_n::text);

    BEGIN PERFORM public.repas_ops_command(v_oB,'open_case',v_rq,'order_stuck','QA R10 conflit');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P3.9 reusing a request id on another order fails closed',
          v_err LIKE '%OPS_REQUEST_ID_CONFLICT%', v_err);
    SELECT count(*) INTO v_n FROM public.repas_ops_cases WHERE food_order_id = v_oB;
    r := r || public._qa_s13_ok('P3.10 the conflicting reuse created nothing', v_n = 0, v_n::text);

    BEGIN PERFORM public.repas_ops_command(v_oA,'add_note',gen_random_uuid(),NULL,'x');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P3.11 a note shorter than the minimum is refused',
          v_err LIKE '%NOTE_REQUIRED%', v_err);
    BEGIN PERFORM public.repas_ops_command(v_oA,'add_note',NULL,NULL,'QA note valable');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P3.12 a command without an idempotency key is refused',
          v_err LIKE '%REQUEST_ID_REQUIRED%', v_err);

    PERFORM public.repas_ops_command(v_oA,'add_note',gen_random_uuid(),NULL,'QA R10 note operateur');
    PERFORM public.repas_ops_command(v_oA,'contact_customer',gen_random_uuid(),NULL,'QA R10 client appele');
    PERFORM public.repas_ops_command(v_oA,'contact_merchant',gen_random_uuid(),NULL,'QA R10 resto appele');
    PERFORM public.repas_ops_command(v_oA,'contact_courier',gen_random_uuid(),NULL,'QA R10 livreur appele');
    SELECT count(*) INTO v_n FROM public.repas_ops_events WHERE food_order_id = v_oA;
    r := r || public._qa_s13_ok('P3.13 note and contact commands each append one event', v_n = 5, v_n::text);

    v_res := public.repas_ops_command(v_oA,'escalate',gen_random_uuid(),NULL,'QA R10 escalade');
    r := r || public._qa_s13_ok('P3.14 escalation moves the case status',
          (SELECT status FROM public.repas_ops_cases WHERE id=v_case) = 'escalated', v_res::text);

    BEGIN UPDATE public.repas_ops_events SET note = 'tampered' WHERE food_order_id = v_oA;
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P3.15 a direct update of a prior ops event is refused',
          v_err LIKE '%OPS_EVENTS_APPEND_ONLY%', v_err);
    BEGIN DELETE FROM public.repas_ops_events WHERE food_order_id = v_oA;
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P3.16 a direct delete of a prior ops event is refused',
          v_err LIKE '%OPS_EVENTS_APPEND_ONLY%', v_err);
    SELECT count(*) INTO v_n FROM public.repas_ops_events WHERE food_order_id = v_oA;
    r := r || public._qa_s13_ok('P3.17 the timeline survived the tamper attempts intact', v_n = 6, v_n::text);
    SELECT count(*) INTO v_n FROM (
      SELECT created_at, lag(created_at) OVER (ORDER BY created_at) prev
        FROM public.repas_ops_events WHERE food_order_id = v_oA) z
     WHERE prev IS NOT NULL AND created_at < prev;
    r := r || public._qa_s13_ok('P3.18 the timeline order is stable and monotonic', v_n = 0, v_n::text);

    v_d := public.repas_ops_case_detail(v_oA);
    r := r || public._qa_s13_ok('P3.19 the merged timeline includes ops interventions',
          (SELECT count(*) FROM jsonb_array_elements(v_d->'timeline') e
            WHERE e->>'source' = 'ops') = 6, v_d->>'timeline');
    r := r || public._qa_s13_ok('P3.20 the merged timeline includes the canonical order milestone',
          (SELECT count(*) FROM jsonb_array_elements(v_d->'timeline') e
            WHERE e->>'source' = 'order') >= 1, NULL);
    r := r || public._qa_s13_ok('P3.21 the timeline distinguishes the operator actor',
          (SELECT bool_and(e->>'actor' = 'operator') FROM jsonb_array_elements(v_d->'timeline') e
            WHERE e->>'source' = 'ops'), NULL);

    -- ================= P4. FINANCE + BYPASS BOUNDARIES =================
    v_d := public.repas_ops_case_detail(v_oA);
    r := r || public._qa_s13_ok('P4.1 an operations admin is offered no cancellation action',
          NOT (v_d->'allowed_actions' @> '["cancel_order"]'::jsonb), v_d->>'allowed_actions');
    BEGIN PERFORM public.repas_ops_command(v_oA,'cancel_order',gen_random_uuid(),
            'order_stuck','QA R10 tentative ops', jsonb_build_object('responsible_party','platform'));
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P4.2 an operations admin cannot execute a cancellation',
          v_err LIKE '%ACTION_NOT_ALLOWED%', v_err);
    r := r || public._qa_s13_ok('P4.3 the refused cancellation left the order untouched',
          (SELECT state::text FROM public.food_orders WHERE id=v_oA) <> 'cancelled', NULL);
    BEGIN PERFORM public.repas_ops_command(v_oA,'reassign_courier',gen_random_uuid(),
            'courier_unresponsive','QA R10 reassignation');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P4.4 courier reassignment is deliberately unavailable',
          v_err LIKE '%ACTION_NOT_AVAILABLE%', v_err);
    BEGIN PERFORM public.repas_ops_command(v_oA,'mark_delivered',gen_random_uuid(),NULL,'QA R10 bypass');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P4.5 there is no ops action that marks an order delivered',
          v_err LIKE '%ACTION_NOT_REVERSIBLE%' OR v_err LIKE '%UNKNOWN_ACTION%', v_err);
    SELECT count(*) INTO v_n FROM public.repas_custody_events WHERE order_id = v_oA;
    r := r || public._qa_s13_ok('P4.6 no custody event was ever produced by an ops command',
          v_n = 0, v_n::text);
    BEGIN
      UPDATE public.food_orders SET state = 'completed' WHERE id = v_oA;
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P4.7 a direct state write outside the certified engine is refused',
          v_err <> 'NO_ERROR'
          AND (SELECT state::text FROM public.food_orders WHERE id=v_oA) <> 'completed', v_err);

    -- ================= P5. CUSTODY REISSUE (NO BYPASS) =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    PERFORM public.repas_merchant_transition(v_oC,'accept');
    PERFORM public.repas_merchant_transition(v_oC,'prepare');
    PERFORM public.repas_merchant_transition(v_oC,'ready');
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_code := public.repas_custody_code_view(v_oC,'customer_pickup')->>'code';
    r := r || public._qa_s13_ok('P5.1 the holder holds a real pickup code before reissue',
          v_code IS NOT NULL AND length(v_code) = 6, NULL);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_ops), true);
    v_rq2 := gen_random_uuid();
    BEGIN PERFORM public.repas_ops_command(v_oC,'custody_reissue',v_rq2,'custody_issue','QA R10 code perdu');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P5.2 a reissue requires an open case first',
          v_err LIKE '%ACTION_NOT_ALLOWED%', v_err);
    PERFORM public.repas_ops_command(v_oC,'open_case',gen_random_uuid(),'custody_issue','QA R10 dossier garde');
    v_res := public.repas_ops_command(v_oC,'custody_reissue',v_rq2,'custody_issue','QA R10 code perdu');
    r := r || public._qa_s13_ok('P5.3 the reissue succeeds in the pre-handoff phase',
          (v_res->'result'->>'reissued')::boolean IS TRUE, v_res::text);
    r := r || public._qa_s13_ok('P5.4 the operator never receives the new code',
          v_res::text NOT LIKE '%"code"%', v_res::text);
    r := r || public._qa_s13_ok('P5.5 the reissue changed no order state',
          (SELECT state::text FROM public.food_orders WHERE id=v_oC) = 'ready', NULL);
    SELECT count(*) INTO v_n FROM public.repas_custody_events WHERE order_id = v_oC;
    r := r || public._qa_s13_ok('P5.6 the reissue produced no custody event', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.repas_custody_credentials
     WHERE order_id = v_oC AND kind = 'customer_pickup';
    r := r || public._qa_s13_ok('P5.7 exactly one live credential remains', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.repas_custody_credentials
     WHERE order_id = v_oC AND kind = 'customer_pickup' AND holder_user_id = v_cust;
    r := r || public._qa_s13_ok('P5.8 the credential holder is unchanged', v_n = 1, v_n::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_code2 := public.repas_custody_code_view(v_oC,'customer_pickup')->>'code';
    r := r || public._qa_s13_ok('P5.9 the holder can retrieve a genuinely new code',
          v_code2 IS NOT NULL AND v_code2 <> v_code, NULL);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    BEGIN PERFORM public.repas_custody_confirm_pickup_collection(v_oC, v_code); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P5.10 the old code no longer completes anything',
          (SELECT state::text FROM public.food_orders WHERE id=v_oC) = 'ready', v_err);
    PERFORM public.repas_custody_confirm_pickup_collection(v_oC, v_code2);
    r := r || public._qa_s13_ok('P5.11 the new code still requires the normal R6 proof and works',
          (SELECT state::text FROM public.food_orders WHERE id=v_oC) = 'completed', NULL);
    SELECT count(*) INTO v_n FROM public.repas_custody_events
     WHERE order_id = v_oC AND boundary = 'merchant_to_customer_pickup';
    r := r || public._qa_s13_ok('P5.12 exactly one custody event closed the boundary', v_n = 1, v_n::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_ops), true);
    v_res2 := public.repas_ops_command(v_oC,'custody_reissue',v_rq2,'custody_issue','QA R10 code perdu');
    r := r || public._qa_s13_ok('P5.13 replaying the reissue key is safe and idempotent',
          (v_res2->>'replay')::boolean IS TRUE, v_res2::text);
    SELECT count(*) INTO v_n FROM public.repas_ops_events
     WHERE food_order_id = v_oC AND action = 'custody_reissue';
    r := r || public._qa_s13_ok('P5.14 only one reissue event exists', v_n = 1, v_n::text);
    BEGIN PERFORM public.repas_ops_command(v_oC,'custody_reissue',gen_random_uuid(),
            'custody_issue','QA R10 apres livraison'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P5.15 a reissue on a completed order is refused',
          v_err LIKE '%ACTION_NOT_ALLOWED%', v_err);

    -- ================= P6. TERMINAL ORDER BOUNDARIES =================
    v_d := public.repas_ops_case_detail(v_oC);
    r := r || public._qa_s13_ok('P6.1 a terminal order still allows support notes',
          v_d->'allowed_actions' @> '["add_note"]'::jsonb, v_d->>'allowed_actions');
    r := r || public._qa_s13_ok('P6.2 a terminal order offers no cancellation',
          NOT (v_d->'allowed_actions' @> '["cancel_order"]'::jsonb), v_d->>'allowed_actions');
    r := r || public._qa_s13_ok('P6.3 a terminal order offers no custody reissue',
          NOT (v_d->'allowed_actions' @> '["custody_reissue"]'::jsonb), v_d->>'allowed_actions');
    v_res := public.repas_ops_command(v_oC,'resolve',gen_random_uuid(),
              'resolved_delivered','QA R10 cloture apres retrait');
    r := r || public._qa_s13_ok('P6.4 a case on a terminal order can still be resolved',
          (SELECT status FROM public.repas_ops_cases WHERE food_order_id=v_oC
            ORDER BY created_at DESC LIMIT 1) = 'resolved', v_res::text);
    PERFORM public.repas_ops_command(v_oC,'reopen',gen_random_uuid(),
              'quality_issue','QA R10 reouverture');
    SELECT count(*) INTO v_n FROM public.repas_ops_cases WHERE food_order_id = v_oC;
    r := r || public._qa_s13_ok('P6.5 a reopen creates a new case instead of erasing the old one',
          v_n = 2, v_n::text);
    SELECT count(*) INTO v_n FROM public.repas_ops_cases
     WHERE food_order_id = v_oC AND status = 'resolved' AND resolution_code = 'resolved_delivered';
    r := r || public._qa_s13_ok('P6.6 the prior resolution is preserved verbatim', v_n = 1, v_n::text);

    -- ================= P7. MERCHANT REJECT IS NOT REVERSIBLE =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    PERFORM public.repas_merchant_transition(v_oD,'reject','QA R10 rejet accidentel');
    r := r || public._qa_s13_ok('P7.1 the merchant rejection is terminal',
          (SELECT state::text FROM public.food_orders WHERE id=v_oD) = 'cancelled', NULL);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_ops), true);
    BEGIN PERFORM public.repas_ops_command(v_oD,'undo_reject',gen_random_uuid(),
            'wrong_order','QA R10 annuler le rejet'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P7.2 ops cannot rewind an accidental rejection',
          v_err LIKE '%ACTION_NOT_REVERSIBLE%', v_err);
    r := r || public._qa_s13_ok('P7.3 the rejected order stayed cancelled',
          (SELECT state::text FROM public.food_orders WHERE id=v_oD) = 'cancelled', NULL);
    v_res := public.repas_ops_command(v_oD,'open_case',gen_random_uuid(),
              'wrong_order','QA R10 rejet accidentel a traiter');
    r := r || public._qa_s13_ok('P7.4 a support case is still possible on the rejected order',
          (v_res->>'case_id') IS NOT NULL, v_res::text);
    v_res := public.repas_ops_command(v_oD,'resolve',gen_random_uuid(),
              'resolved_duplicate','QA R10 nouvelle commande a creer');
    r := r || public._qa_s13_ok('P7.5 the rejected order case can be closed with guidance',
          (v_res->'result'->>'case_status') = 'resolved', v_res::text);

    -- ================= P8. CANONICAL CANCELLATION MOVES VALUE ONCE =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    v_d := public.repas_ops_case_detail(v_oE);
    r := r || public._qa_s13_ok('P8.1 a god admin sees the full ops surface',
          v_d->>'actor_role' = 'god_admin', v_d->>'actor_role');
    PERFORM public.repas_ops_command(v_oE,'open_case',gen_random_uuid(),
            'payment_issue','QA R10 annulation operateur');
    v_d := public.repas_ops_case_detail(v_oE);
    r := r || public._qa_s13_ok('P8.2 a finance-privileged caller is offered the cancellation',
          v_d->'allowed_actions' @> '["cancel_order"]'::jsonb, v_d->>'allowed_actions');

    SELECT count(*) INTO v_jr FROM public.ledger_journals WHERE created_at >= now() - interval '5 minutes';
    v_rq3 := gen_random_uuid();
    v_res := public.repas_ops_command(v_oE,'cancel_order',v_rq3,'payment_issue',
              'QA R10 annulation justifiee', jsonb_build_object('responsible_party','platform'));
    r := r || public._qa_s13_ok('P8.3 the cancellation reports success',
          (v_res->>'ok')::boolean AND (v_res->>'replay')::boolean IS FALSE, v_res::text);
    r := r || public._qa_s13_ok('P8.4 the order is cancelled in canonical truth',
          (SELECT state::text FROM public.food_orders WHERE id=v_oE) = 'cancelled', NULL);
    r := r || public._qa_s13_ok('P8.5 the ops event carries the canonical finance result',
          (SELECT finance_result IS NOT NULL FROM public.repas_ops_events
            WHERE food_order_id = v_oE AND action = 'cancel_order'), NULL);
    r := r || public._qa_s13_ok('P8.6 the payment engine reached a terminal state exactly once',
          (SELECT count(*) FROM public.chop_pay_order_runtime
            WHERE source_module='repas' AND source_id=v_oE
              AND state IN ('cancelled','refunded','reversed','closed')) = 1,
          (SELECT state FROM public.chop_pay_order_runtime
            WHERE source_module='repas' AND source_id=v_oE));
    SELECT balance_gnf INTO v_bal1 FROM public.wallets
     WHERE owner_user_id = v_cust AND party_type = 'client';
    SELECT count(*) INTO v_jr2 FROM public.ledger_journals WHERE created_at >= now() - interval '5 minutes';

    v_res2 := public.repas_ops_command(v_oE,'cancel_order',v_rq3,'payment_issue',
              'QA R10 annulation justifiee', jsonb_build_object('responsible_party','platform'));
    r := r || public._qa_s13_ok('P8.7 an exact cancellation replay is a replay',
          (v_res2->>'replay')::boolean IS TRUE, v_res2::text);
    SELECT count(*) INTO v_n FROM public.ledger_journals WHERE created_at >= now() - interval '5 minutes';
    r := r || public._qa_s13_ok('P8.8 the cancellation replay posted no additional journal',
          v_n = v_jr2, v_n::text||'/'||v_jr2::text);
    SELECT balance_gnf INTO v_bal0 FROM public.wallets
     WHERE owner_user_id = v_cust AND party_type = 'client';
    r := r || public._qa_s13_ok('P8.9 the cancellation replay moved zero additional value',
          v_bal0 = v_bal1, v_bal0::text||'/'||v_bal1::text);
    SELECT count(*) INTO v_n FROM public.repas_ops_events
     WHERE food_order_id = v_oE AND action = 'cancel_order';
    r := r || public._qa_s13_ok('P8.10 only one cancellation event exists', v_n = 1, v_n::text);
    r := r || public._qa_s13_ok('P8.11 the frozen R5 pricing snapshot is untouched by ops',
          (SELECT pricing_snapshot IS NOT NULL AND order_total_gnf IS NOT NULL
             FROM public.food_orders WHERE id = v_oE), NULL);
    BEGIN PERFORM public.repas_ops_command(v_oE,'cancel_order',gen_random_uuid(),'payment_issue',
            'QA R10 deuxieme annulation', jsonb_build_object('responsible_party','platform'));
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('P8.12 a second cancellation on a cancelled order is refused',
          v_err LIKE '%ACTION_NOT_ALLOWED%', v_err);

    -- ================= P9. READ MODELS SURVIVE REFETCH =================
    v_d := public.repas_ops_case_detail(v_oE);
    r := r || public._qa_s13_ok('P9.1 a refetch reflects the cancelled canonical state',
          v_d->'order'->>'state' = 'cancelled', v_d->'order'->>'state');
    r := r || public._qa_s13_ok('P9.2 a refetch keeps the full ops timeline',
          (SELECT count(*) FROM jsonb_array_elements(v_d->'timeline') e
            WHERE e->>'source' = 'ops') = 2, v_d->>'timeline');
    v_q := public.repas_ops_queue('all', v_oE::text, 50);
    r := r || public._qa_s13_ok('P9.3 the queue and the detail agree on state',
          v_q->'rows'->0->>'state' = v_d->'order'->>'state', v_q->'rows'->0->>'state');
    r := r || public._qa_s13_ok('P9.4 a cancelled order raises no fabricated delay flag',
          NOT (v_q->'rows'->0->'attention_flags' @> '["delivery_overdue"]'::jsonb)
          AND NOT (v_q->'rows'->0->'attention_flags' @> '["preparation_overdue"]'::jsonb),
          v_q->'rows'->0->>'attention_flags');

    -- ================= Z. FINANCIAL INTEGRITY =================
    SELECT count(*) INTO v_n FROM (
      SELECT j.id FROM public.ledger_journals j
        JOIN public.ledger_postings p ON p.journal_id = j.id
       WHERE j.created_at >= now() - interval '10 minutes'
       GROUP BY j.id HAVING sum(p.amount_gnf) <> 0) z;
    r := r || public._qa_s13_ok('Z1.1 every journal created here is zero-sum', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_module='repas' AND source_id IN (v_oA,v_oB,v_oC,v_oD,v_oE)
       AND (captured_gnf + released_gnf) > amount_gnf;
    r := r || public._qa_s13_ok('Z1.2 no hold is over-consumed', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.payout_orders
     WHERE created_at >= now() - interval '10 minutes';
    r := r || public._qa_s13_ok('Z1.3 ops created no payout order', v_n = 0, v_n::text);

    PERFORM set_config('request.jwt.claims', ''::text, true);
    RAISE EXCEPTION 'QA_NODE3_R10_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_NODE3_R10_ROLLBACK' THEN
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
  SELECT count(*) INTO v_n FROM public.food_restaurants WHERE slug LIKE 'qa-n3r10-%';
  r := r || public._qa_s13_ok('Z9.3 no restaurant fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.food_menu_items WHERE name LIKE 'QA R10 %';
  r := r || public._qa_s13_ok('Z9.4 no menu fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM auth.users WHERE email LIKE 'qa-s13-n3r10%';
  r := r || public._qa_s13_ok('Z9.5 no QA user residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.repas_ops_cases;
  r := r || public._qa_s13_ok('Z9.6 no ops case residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.repas_ops_events;
  r := r || public._qa_s13_ok('Z9.7 no ops timeline residue', v_n = 0, v_n::text);

  RETURN jsonb_build_object('part','node3_repas_r10_operations',
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'results', r);
END; $function$;

DELETE FROM public._qa_s13_results WHERE part = 1010;
INSERT INTO public._qa_s13_results(part, result)
VALUES (1010, public._qa_node3_repas_r10_operations());