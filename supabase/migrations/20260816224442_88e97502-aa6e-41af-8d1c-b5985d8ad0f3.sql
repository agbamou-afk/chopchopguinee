CREATE OR REPLACE FUNCTION public._qa_node4_marche_r5()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  r jsonb := '[]'::jsonb;
  v_buy uuid; v_merch uuid; v_merch2 uuid; v_other uuid; v_adm uuid; v_drv uuid; v_drv2 uuid;
  v_store uuid; v_store2 uuid;
  l_a uuid; l_b uuid;
  v_res jsonb; v_o1 uuid; v_o2 uuid; v_o3 uuid;
  v_ord public.marche_orders; v_m public.missions; v_mid uuid; v_mid2 uuid;
  v_err text; v_n int; v_src text; v_json jsonb;
  v_stock_a0 int; v_stock_a1 int; v_res_a0 int; v_res_a1 int;
  v_flags0 jsonb; v_flags1 jsonb;
  v_w0 bigint; v_w1 bigint; v_wt0 bigint; v_wt1 bigint; v_lj0 bigint; v_lj1 bigint;
  v_lp0 bigint; v_lp1 bigint; v_pi0 bigint; v_pi1 bigint; v_ms0 bigint; v_ms1 bigint;
  v_mp0 bigint; v_mp1 bigint; v_ss0 bigint; v_ss1 bigint;
  v_total0 bigint; v_total1 bigint; v_reserved0 bigint; v_reserved1 bigint;
BEGIN
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;
  SELECT count(*) INTO v_w0 FROM public.wallets;
  SELECT count(*) INTO v_wt0 FROM public.wallet_transactions;
  SELECT count(*) INTO v_lj0 FROM public.ledger_journals;
  SELECT count(*) INTO v_lp0 FROM public.ledger_postings;
  SELECT count(*) INTO v_pi0 FROM public.payment_intents;
  SELECT count(*) INTO v_ms0 FROM public.missions;
  SELECT count(*) INTO v_mp0 FROM public.merchant_payables;
  SELECT count(*) INTO v_ss0 FROM public.merchant_settlement_requests;
  SELECT count(*) INTO v_total0 FROM public.marketplace_listings;
  SELECT COALESCE(sum(quantity_reserved),0) INTO v_reserved0 FROM public.marketplace_listings;

  -- ================= A. STRUCTURAL LAW =================
  r := r || public._qa_s13_ok('N4R5.A1 orders carry a server fulfillment state',
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                 AND table_name='marche_orders' AND column_name='fulfillment_state'
                 AND is_nullable='NO'), NULL);
  r := r || public._qa_s13_ok('N4R5.A2 fulfillment vocabulary is constrained',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conname='marche_orders_fulfillment_state_legal'), NULL);
  r := r || public._qa_s13_ok('N4R5.A3 append-only transition log exists',
        to_regclass('public.marche_fulfillment_transitions') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N4R5.A4 transition log is append-only guarded',
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_marche_fulfillment_transition_guard'), NULL);
  r := r || public._qa_s13_ok('N4R5.A5 transition log has RLS enabled and zero policies',
        (SELECT relrowsecurity FROM pg_class WHERE oid='public.marche_fulfillment_transitions'::regclass)
        AND (SELECT count(*) FROM pg_policies WHERE tablename='marche_fulfillment_transitions') = 0, NULL);
  r := r || public._qa_s13_ok('N4R5.A6 transition log unreachable by anon/authenticated',
        NOT has_table_privilege('anon','public.marche_fulfillment_transitions','SELECT')
    AND NOT has_table_privilege('authenticated','public.marche_fulfillment_transitions','SELECT'), NULL);
  r := r || public._qa_s13_ok('N4R5.A7 order->mission linkage is unique',
        EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='marche_orders_mission_unique'), NULL);
  r := r || public._qa_s13_ok('N4R5.A8 reservation settlement kind is constrained',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conname='marche_orders_reservation_settlement_chk'), NULL);
  r := r || public._qa_s13_ok('N4R5.A9 merchant transition RPC exists and is definer',
        EXISTS (SELECT 1 FROM pg_proc WHERE proname='marche_merchant_transition' AND prosecdef), NULL);
  r := r || public._qa_s13_ok('N4R5.A10 dispatch RPC exists and is definer',
        EXISTS (SELECT 1 FROM pg_proc WHERE proname='marche_dispatch_request' AND prosecdef), NULL);
  r := r || public._qa_s13_ok('N4R5.A11 courier transition RPC exists and is definer',
        EXISTS (SELECT 1 FROM pg_proc WHERE proname='marche_courier_transition' AND prosecdef), NULL);
  r := r || public._qa_s13_ok('N4R5.A12 history RPC exists and is definer',
        EXISTS (SELECT 1 FROM pg_proc WHERE proname='marche_order_fulfillment_history' AND prosecdef), NULL);
  r := r || public._qa_s13_ok('N4R5.A13 all R5 definers pin search_path',
        NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname IN
          ('marche_merchant_transition','marche_dispatch_request','marche_courier_transition',
           'marche_order_fulfillment_history','_marche_fulfillment_apply','_marche_reservation_settle',
           '_marche_courier_engaged_internal','_marche_fulfillment_note')
          AND NOT (COALESCE(array_to_string(proconfig,','),'') LIKE '%search_path=public%')), NULL);
  r := r || public._qa_s13_ok('N4R5.A14 anon cannot execute any R5 lifecycle RPC',
        NOT has_function_privilege('anon','public.marche_merchant_transition(uuid,text,text)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_dispatch_request(uuid)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_courier_transition(uuid,text)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_order_fulfillment_history(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R5.A15 authenticated CAN execute the lifecycle RPCs',
        has_function_privilege('authenticated','public.marche_merchant_transition(uuid,text,text)','EXECUTE')
    AND has_function_privilege('authenticated','public.marche_dispatch_request(uuid)','EXECUTE')
    AND has_function_privilege('authenticated','public.marche_courier_transition(uuid,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R5.A16 internal primitives are not client-callable',
        NOT has_function_privilege('authenticated','public._marche_fulfillment_apply(uuid,text,uuid,text,text)','EXECUTE')
    AND NOT has_function_privilege('authenticated','public._marche_reservation_settle(uuid,text)','EXECUTE')
    AND NOT has_function_privilege('authenticated','public._marche_courier_engaged_internal(uuid,uuid,uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R5.A17 anon still cannot execute has_role (P15.5 preserved)',
        NOT has_function_privilege('anon','public.has_role(uuid,app_role)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R5.A18 marche_orders remains RPC-only for clients',
        NOT has_table_privilege('anon','public.marche_orders','SELECT')
    AND NOT has_table_privilege('authenticated','public.marche_orders','SELECT')
    AND NOT has_table_privilege('authenticated','public.marche_orders','UPDATE'), NULL);

  v_src := (SELECT prosrc FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='marche_order_guard');
  r := r || public._qa_s13_ok('N4R5.A19 guard refuses client-authored fulfillment writes',
        v_src LIKE '%FULFILLMENT_SERVER_ONLY%', NULL);
  r := r || public._qa_s13_ok('N4R5.A20 guard refuses terminal rewind',
        v_src LIKE '%FULFILLMENT_TERMINAL%', NULL);
  r := r || public._qa_s13_ok('N4R5.A21 guard refuses relinking an existing mission',
        v_src LIKE '%MISSION_LINK_IMMUTABLE%', NULL);
  r := r || public._qa_s13_ok('N4R5.A22 guard still freezes R4 economics',
        v_src LIKE '%ECONOMICS_IMMUTABLE%', NULL);
  r := r || public._qa_s13_ok('N4R5.A23 guard refuses double reservation settlement',
        v_src LIKE '%RESERVATION_ALREADY_SETTLED%', NULL);

  v_src := (SELECT prosrc FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='marche_courier_transition');
  r := r || public._qa_s13_ok('N4R5.A24 courier RPC never fabricates SHOPPING_* telemetry',
        v_src NOT LIKE '%SHOPPING_%', NULL);
  r := r || public._qa_s13_ok('N4R5.A25 courier RPC binds authority to the assigned courier',
        v_src LIKE '%NOT_THE_ASSIGNED_COURIER%', NULL);
  v_src := (SELECT prosrc FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='marche_merchant_transition');
  r := r || public._qa_s13_ok('N4R5.A26 merchant RPC never fabricates SHOPPING_* telemetry',
        v_src NOT LIKE '%SHOPPING_%', NULL);
  r := r || public._qa_s13_ok('N4R5.A27 R5 creates no parallel finance architecture',
        v_src NOT LIKE '%wallet%' AND v_src NOT LIKE '%ledger%' AND v_src NOT LIKE '%payment_intent%'
    AND v_src NOT LIKE '%merchant_payable%' AND v_src NOT LIKE '%settlement%', NULL);
  v_src := (SELECT prosrc FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='marche_dispatch_request');
  r := r || public._qa_s13_ok('N4R5.A28 dispatch reuses canonical missions, no new courier table',
        v_src LIKE '%public.missions%' AND v_src LIKE '%marketplace_delivery%', NULL);
  r := r || public._qa_s13_ok('N4R5.A29 dispatch freezes fulfillment mode with provenance',
        v_src LIKE '%marche_fulfillment_set_mode%' AND v_src LIKE '%marche_dispatch_request%', NULL);
  r := r || public._qa_s13_ok('N4R5.A30 no parallel marché mission/tracking/custody tables',
        (SELECT count(*) FROM information_schema.tables WHERE table_schema='public'
          AND (table_name LIKE 'marche_mission%' OR table_name LIKE 'marche_courier%'
               OR table_name LIKE 'marche_custody%' OR table_name LIKE 'marche_tracking%')) = 0, NULL);

  BEGIN
    -- ================= FIXTURES =================
    v_buy := gen_random_uuid(); v_merch := gen_random_uuid(); v_merch2 := gen_random_uuid();
    v_other := gen_random_uuid(); v_adm := gen_random_uuid();
    v_drv := gen_random_uuid(); v_drv2 := gen_random_uuid();
    PERFORM public._qa_s13_user(v_buy,'n45b');
    PERFORM public._qa_s13_user(v_merch,'n45m');
    PERFORM public._qa_s13_user(v_merch2,'n45m2');
    PERFORM public._qa_s13_user(v_other,'n45o');
    PERFORM public._qa_s13_user(v_adm,'n45a');
    PERFORM public._qa_s13_admin(v_adm);
    PERFORM public._qa_s13_driver(v_drv,'n45d',0);
    PERFORM public._qa_s13_driver(v_drv2,'n45d2',0);

    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status, latitude, longitude, address_label)
      VALUES (v_merch,'qa-n45-a-'||substr(v_merch::text,1,8),'QA N45 Store A','active','approved',9.5370,-13.6785,'QA Madina')
      RETURNING id INTO v_store;
    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status, latitude, longitude)
      VALUES (v_merch2,'qa-n45-b-'||substr(v_merch2::text,1,8),'QA N45 Store B','active','approved',9.5380,-13.6700)
      RETURNING id INTO v_store2;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    l_a := public.marche_listing_create(jsonb_build_object('store_id',v_store,'title','QA N45 Riz',
      'category','Alimentation','price_gnf',10000,'quantity_in_stock',10,'publish',true));
    l_b := public.marche_listing_create(jsonb_build_object('store_id',v_store,'title','QA N45 Huile',
      'category','Alimentation','price_gnf',20000,'quantity_in_stock',5,'publish',true));

    SELECT quantity_in_stock, quantity_reserved INTO v_stock_a0, v_res_a0
      FROM public.marketplace_listings WHERE id = l_a;

    -- ================= B. COMMIT BASELINE =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_res := public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n45-main-0001',
      'delivery_address','QA Kaloum, Conakry',
      'dropoff_lat', 9.5550, 'dropoff_lng', -13.6785,
      'items', jsonb_build_array(
        jsonb_build_object('listing_id', l_a, 'qty', 2),
        jsonb_build_object('listing_id', l_b, 'qty', 1))));
    v_o1 := (v_res->>'id')::uuid;

    r := r || public._qa_s13_ok('N4R5.B1 fresh order starts at committed',
          (v_res->>'fulfillment_state') = 'committed', v_res->>'fulfillment_state');
    r := r || public._qa_s13_ok('N4R5.B2 fresh order has no courier assigned',
          (v_res->>'courier_assigned')::boolean = false, NULL);
    r := r || public._qa_s13_ok('N4R5.B3 buyer read leaks no mission id',
          NOT (v_res ? 'mission_id'), NULL);
    r := r || public._qa_s13_ok('N4R5.B4 buyer read leaks no merchant economics',
          NOT (v_res ? 'merchant_payable_gnf') AND NOT (v_res ? 'economics_snapshot'), NULL);
    r := r || public._qa_s13_ok('N4R5.B5 commit reserved stock (R3 intact)',
          (SELECT quantity_reserved FROM public.marketplace_listings WHERE id=l_a) = v_res_a0 + 2, NULL);
    r := r || public._qa_s13_ok('N4R5.B6 commit did not touch physical stock',
          (SELECT quantity_in_stock FROM public.marketplace_listings WHERE id=l_a) = v_stock_a0, NULL);
    r := r || public._qa_s13_ok('N4R5.B7 commit emitted only ORDER_COMMITTED',
          (SELECT count(*) FROM public.marche_fulfillment_events WHERE order_id=v_o1) = 1, NULL);
    r := r || public._qa_s13_ok('N4R5.B8 fulfillment mode still unspecified before dispatch',
          (SELECT fulfillment_mode FROM public.marche_fulfillment_profiles WHERE order_id=v_o1) = 'unspecified', NULL);

    -- ================= C. MERCHANT AUTHORITY =================
    v_err := NULL;
    BEGIN PERFORM public.marche_merchant_transition(v_o1,'accept',NULL);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R5.C1 buyer cannot act as merchant', v_err = 'NOT_AUTHORIZED', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch2), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_merchant_transition(v_o1,'accept',NULL);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R5.C2 a different store owner cannot accept', v_err = 'NOT_AUTHORIZED', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_adm), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_merchant_transition(v_o1,'accept',NULL);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R5.C3 admin cannot impersonate merchant authority', v_err = 'NOT_AUTHORIZED', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_other), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_merchant_transition(v_o1,'accept',NULL);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R5.C4 a stranger cannot accept', v_err = 'NOT_AUTHORIZED', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_merchant_transition(v_o1,'ready',NULL);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R5.C5 ready before accept is refused', v_err = 'ILLEGAL_TRANSITION', v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_merchant_transition(v_o1,'prepare',NULL);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R5.C6 prepare before accept is refused', v_err = 'ILLEGAL_TRANSITION', v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_merchant_transition(v_o1,'teleport',NULL);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R5.C7 unknown action refused', v_err = 'UNSUPPORTED_ACTION', v_err);

    v_res := public.marche_merchant_transition(v_o1,'accept',NULL);
    r := r || public._qa_s13_ok('N4R5.C8 rightful merchant accepts', (v_res->>'fulfillment_state')='accepted', v_res->>'fulfillment_state');
    r := r || public._qa_s13_ok('N4R5.C9 accepted_at stamped server-side', (v_res->>'accepted_at') IS NOT NULL, NULL);
    r := r || public._qa_s13_ok('N4R5.C10 merchant read exposes mission linkage key', v_res ? 'mission_id', NULL);
    r := r || public._qa_s13_ok('N4R5.C11 MERCHANT_ACCEPTED emitted exactly once',
          (SELECT count(*) FROM public.marche_fulfillment_events WHERE order_id=v_o1 AND event_type='MERCHANT_ACCEPTED')=1, NULL);

    v_res := public.marche_merchant_transition(v_o1,'accept',NULL);
    r := r || public._qa_s13_ok('N4R5.C12 accept replay is idempotent', (v_res->>'fulfillment_state')='accepted', NULL);
    r := r || public._qa_s13_ok('N4R5.C13 accept replay emits no second event',
          (SELECT count(*) FROM public.marche_fulfillment_events WHERE order_id=v_o1 AND event_type='MERCHANT_ACCEPTED')=1, NULL);
    r := r || public._qa_s13_ok('N4R5.C14 accept replay writes no second history row',
          (SELECT count(*) FROM public.marche_fulfillment_transitions WHERE order_id=v_o1 AND to_state='accepted')=1, NULL);

    v_res := public.marche_merchant_transition(v_o1,'prepare',NULL);
    r := r || public._qa_s13_ok('N4R5.C15 accepted -> preparing', (v_res->>'fulfillment_state')='preparing', NULL);
    r := r || public._qa_s13_ok('N4R5.C16 preparing emits no fabricated telemetry',
          (SELECT count(*) FROM public.marche_fulfillment_events WHERE order_id=v_o1)=2, NULL);

    v_res := public.marche_merchant_transition(v_o1,'ready',NULL);
    r := r || public._qa_s13_ok('N4R5.C17 preparing -> ready', (v_res->>'fulfillment_state')='ready', NULL);
    r := r || public._qa_s13_ok('N4R5.C18 ready_at stamped', (v_res->>'ready_at') IS NOT NULL, NULL);
    r := r || public._qa_s13_ok('N4R5.C19 MERCHANT_READY emitted exactly once',
          (SELECT count(*) FROM public.marche_fulfillment_events WHERE order_id=v_o1 AND event_type='MERCHANT_READY')=1, NULL);
    v_res := public.marche_merchant_transition(v_o1,'ready',NULL);
    r := r || public._qa_s13_ok('N4R5.C20 ready replay idempotent, still one event',
          (SELECT count(*) FROM public.marche_fulfillment_events WHERE order_id=v_o1 AND event_type='MERCHANT_READY')=1, NULL);
    r := r || public._qa_s13_ok('N4R5.C21 history is ordered and complete so far',
          (SELECT string_agg(to_state, '>' ORDER BY created_at, id)
             FROM public.marche_fulfillment_transitions WHERE order_id=v_o1) = 'accepted>preparing>ready', NULL);

    -- ================= D. DISPATCH / MISSION LINKAGE =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_other), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_dispatch_request(v_o1);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R5.D1 stranger cannot dispatch', v_err = 'NOT_AUTHORIZED', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_res := public.marche_dispatch_request(v_o1);
    v_mid := (v_res->>'mission_id')::uuid;
    SELECT * INTO v_m FROM public.missions WHERE id = v_mid;
    r := r || public._qa_s13_ok('N4R5.D2 dispatch created exactly one canonical mission',
          v_mid IS NOT NULL AND (SELECT count(*) FROM public.missions WHERE ref_market_order_id=v_o1)=1, NULL);
    r := r || public._qa_s13_ok('N4R5.D3 mission is a marketplace_delivery mission',
          v_m.type::text = 'marketplace_delivery', v_m.type::text);
    r := r || public._qa_s13_ok('N4R5.D4 mission references the marché order',
          v_m.ref_market_order_id = v_o1, NULL);
    r := r || public._qa_s13_ok('N4R5.D5 mission starts unassigned in assigned state',
          v_m.courier_id IS NULL AND v_m.state::text = 'assigned', v_m.state::text);
    r := r || public._qa_s13_ok('N4R5.D6 mission carries no courier economics at R5',
          COALESCE(v_m.estimated_earning_gnf,0) = 0, v_m.estimated_earning_gnf::text);
    r := r || public._qa_s13_ok('N4R5.D7 mission pickup is the store, dropoff the buyer address',
          v_m.dropoff_address = 'QA Kaloum, Conakry' AND v_m.pickup_address = 'QA Madina', NULL);
    r := r || public._qa_s13_ok('N4R5.D8 fulfillment mode becomes truthful delivery',
          (SELECT fulfillment_mode FROM public.marche_fulfillment_profiles WHERE order_id=v_o1)='delivery', NULL);
    r := r || public._qa_s13_ok('N4R5.D9 fulfillment mode carries dispatch provenance',
          (SELECT fulfillment_mode_source FROM public.marche_fulfillment_profiles WHERE order_id=v_o1)='marche_dispatch_request', NULL);
    r := r || public._qa_s13_ok('N4R5.D10 dispatch emitted no courier telemetry yet',
          (SELECT count(*) FROM public.marche_fulfillment_events WHERE order_id=v_o1 AND event_type='COURIER_ENGAGED')=0, NULL);
    r := r || public._qa_s13_ok('N4R5.D11 dispatch logged mission linkage in history',
          EXISTS (SELECT 1 FROM public.marche_fulfillment_transitions
                   WHERE order_id=v_o1 AND reason LIKE 'mission_linked:%'), NULL);

    v_res := public.marche_dispatch_request(v_o1);
    r := r || public._qa_s13_ok('N4R5.D12 dispatch replay creates no second mission',
          (SELECT count(*) FROM public.missions WHERE ref_market_order_id=v_o1)=1, NULL);
    r := r || public._qa_s13_ok('N4R5.D13 dispatch replay returns the same mission',
          (v_res->>'mission_id')::uuid = v_mid, NULL);

    -- ================= E. COURIER AUTHORITY =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv2), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_courier_transition(v_o1,'collect');
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R5.E1 unassigned mission has no courier authority',
          v_err = 'COURIER_NOT_ASSIGNED', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_claim(v_mid);
    SELECT * INTO v_ord FROM public.marche_orders WHERE id=v_o1;
    r := r || public._qa_s13_ok('N4R5.E2 claim engaged the courier on the order',
          v_ord.fulfillment_state = 'courier_engaged', v_ord.fulfillment_state);
    r := r || public._qa_s13_ok('N4R5.E3 COURIER_ENGAGED emitted exactly once',
          (SELECT count(*) FROM public.marche_fulfillment_events WHERE order_id=v_o1 AND event_type='COURIER_ENGAGED')=1, NULL);
    r := r || public._qa_s13_ok('N4R5.E4 canonical mission assignment holds the courier identity',
          (SELECT courier_id FROM public.missions WHERE id=v_mid) = v_drv, NULL);
    r := r || public._qa_s13_ok('N4R5.E5 no second driver identity table was created',
          (SELECT count(*) FROM public.driver_profiles WHERE user_id=v_drv)=1, NULL);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv2), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_courier_transition(v_o1,'collect');
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R5.E6 a different courier cannot collect', v_err='NOT_THE_ASSIGNED_COURIER', v_err);
    v_err := NULL;
    BEGIN PERFORM public.mission_claim(v_mid);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R5.E7 a claimed mission cannot be re-claimed', v_err='mission_already_claimed', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_courier_transition(v_o1,'deliver');
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R5.E8 buyer cannot self-deliver', v_err='NOT_THE_ASSIGNED_COURIER', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_courier_transition(v_o1,'collect');
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R5.E9 merchant cannot act as courier', v_err='NOT_THE_ASSIGNED_COURIER', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_courier_transition(v_o1,'deliver');
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R5.E10 delivering before collection is refused', v_err='ILLEGAL_TRANSITION', v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_courier_transition(v_o1,'start_delivery');
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R5.E11 start_delivery before collection is refused', v_err='ILLEGAL_TRANSITION', v_err);

    PERFORM public.marche_courier_transition(v_o1,'arrive_store');
    r := r || public._qa_s13_ok('N4R5.E12 COURIER_AT_STORE emitted exactly once',
          (SELECT count(*) FROM public.marche_fulfillment_events WHERE order_id=v_o1 AND event_type='COURIER_AT_STORE')=1, NULL);
    r := r || public._qa_s13_ok('N4R5.E13 arrival moved the canonical mission, not a parallel one',
          (SELECT state::text FROM public.missions WHERE id=v_mid)='arrived_pickup', NULL);
    PERFORM public.marche_courier_transition(v_o1,'arrive_store');
    r := r || public._qa_s13_ok('N4R5.E14 arrival replay stays exactly-once',
          (SELECT count(*) FROM public.marche_fulfillment_events WHERE order_id=v_o1 AND event_type='COURIER_AT_STORE')=1, NULL);

    v_res := public.marche_courier_transition(v_o1,'collect');
    r := r || public._qa_s13_ok('N4R5.E15 collection is server-authoritative', (v_res->>'fulfillment_state')='collected', v_res->>'fulfillment_state');
    r := r || public._qa_s13_ok('N4R5.E16 PICKED_UP emitted exactly once',
          (SELECT count(*) FROM public.marche_fulfillment_events WHERE order_id=v_o1 AND event_type='PICKED_UP')=1, NULL);
    SELECT * INTO v_m FROM public.missions WHERE id=v_mid;
    r := r || public._qa_s13_ok('N4R5.E17 custody attributed to the real courier',
          v_m.state::text='picked_up' AND v_m.pickup_confirmed_by = v_drv AND v_m.pickup_confirmed_at IS NOT NULL, NULL);
    PERFORM public.marche_courier_transition(v_o1,'collect');
    r := r || public._qa_s13_ok('N4R5.E18 collection replay is idempotent',
          (SELECT count(*) FROM public.marche_fulfillment_events WHERE order_id=v_o1 AND event_type='PICKED_UP')=1
      AND (SELECT count(*) FROM public.marche_fulfillment_transitions WHERE order_id=v_o1 AND to_state='collected')=1, NULL);
    r := r || public._qa_s13_ok('N4R5.E19 collection did not settle stock early',
          (SELECT reservation_settled_at FROM public.marche_orders WHERE id=v_o1) IS NULL, NULL);

    v_res := public.marche_courier_transition(v_o1,'start_delivery');
    r := r || public._qa_s13_ok('N4R5.E20 collected -> delivering', (v_res->>'fulfillment_state')='delivering', NULL);
    r := r || public._qa_s13_ok('N4R5.E21 mission is heading to dropoff',
          (SELECT state::text FROM public.missions WHERE id=v_mid)='heading_to_dropoff', NULL);
    r := r || public._qa_s13_ok('N4R5.E22 delivering emits no fabricated telemetry',
          (SELECT count(*) FROM public.marche_fulfillment_events WHERE order_id=v_o1 AND event_type='DELIVERED')=0, NULL);

    SELECT quantity_in_stock, quantity_reserved INTO v_stock_a1, v_res_a1
      FROM public.marketplace_listings WHERE id=l_a;
    v_res := public.marche_courier_transition(v_o1,'deliver');
    r := r || public._qa_s13_ok('N4R5.E23 delivery is terminal truth', (v_res->>'fulfillment_state')='delivered', v_res->>'fulfillment_state');
    r := r || public._qa_s13_ok('N4R5.E24 delivered_at stamped', (v_res->>'delivered_at') IS NOT NULL, NULL);
    SELECT * INTO v_m FROM public.missions WHERE id=v_mid;
    r := r || public._qa_s13_ok('N4R5.E25 mission delivered and attributed to the courier',
          v_m.state::text='delivered' AND v_m.dropoff_confirmed_by = v_drv, NULL);
    r := r || public._qa_s13_ok('N4R5.E26 DELIVERED emitted exactly once',
          (SELECT count(*) FROM public.marche_fulfillment_events WHERE order_id=v_o1 AND event_type='DELIVERED')=1, NULL);

    -- ================= F. STOCK TRUTH =================
    r := r || public._qa_s13_ok('N4R5.F1 delivery consumed the reservation',
          (SELECT quantity_reserved FROM public.marketplace_listings WHERE id=l_a) = v_res_a1 - 2, NULL);
    r := r || public._qa_s13_ok('N4R5.F2 delivery decremented physical stock exactly once',
          (SELECT quantity_in_stock FROM public.marketplace_listings WHERE id=l_a) = v_stock_a1 - 2, NULL);
    r := r || public._qa_s13_ok('N4R5.F3 second line stock consumed too',
          (SELECT quantity_in_stock FROM public.marketplace_listings WHERE id=l_b) = 4, NULL);
    r := r || public._qa_s13_ok('N4R5.F4 reservation settlement recorded as consumed',
          (SELECT reservation_settlement_kind FROM public.marche_orders WHERE id=v_o1)='consumed', NULL);
    PERFORM public.marche_courier_transition(v_o1,'deliver');
    r := r || public._qa_s13_ok('N4R5.F5 delivery replay does not double-consume stock',
          (SELECT quantity_in_stock FROM public.marketplace_listings WHERE id=l_a) = v_stock_a1 - 2
      AND (SELECT count(*) FROM public.marche_fulfillment_events WHERE order_id=v_o1 AND event_type='DELIVERED')=1, NULL);

    -- ================= G. TERMINAL IRREVERSIBILITY =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_merchant_transition(v_o1,'reject','changed my mind');
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R5.G1 delivered order cannot be rejected', v_err='FULFILLMENT_IN_PROGRESS', v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_order_cancel(v_o1,'nope');
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R5.G2 delivered order cannot be cancelled', v_err='FULFILLMENT_IN_PROGRESS', v_err);
    v_err := NULL;
    BEGIN
      PERFORM set_config('marche.rpc','1', true);
      UPDATE public.marche_orders SET fulfillment_state='preparing' WHERE id=v_o1;
      PERFORM set_config('marche.rpc','', true);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; PERFORM set_config('marche.rpc','', true); END;
    r := r || public._qa_s13_ok('N4R5.G3 terminal state cannot rewind even server-side', v_err='FULFILLMENT_TERMINAL', v_err);
    v_err := NULL;
    BEGIN
      UPDATE public.marche_orders SET fulfillment_state='committed' WHERE id=v_o1;
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R5.G4 fulfillment writes outside the RPC path are refused',
          v_err='FULFILLMENT_SERVER_ONLY', v_err);
    r := r || public._qa_s13_ok('N4R5.G5 order still delivered after all refusals',
          (SELECT fulfillment_state FROM public.marche_orders WHERE id=v_o1)='delivered', NULL);

    -- ================= H. TELEMETRY / OBSERVATIONS =================
    r := r || public._qa_s13_ok('N4R5.H1 exactly six canonical milestones on the happy path',
          (SELECT count(*) FROM public.marche_fulfillment_events WHERE order_id=v_o1)=6, 
          (SELECT string_agg(event_type,',' ORDER BY occurred_at) FROM public.marche_fulfillment_events WHERE order_id=v_o1));
    r := r || public._qa_s13_ok('N4R5.H2 zero fabricated SHOPPING_* events',
          (SELECT count(*) FROM public.marche_fulfillment_events
            WHERE order_id=v_o1 AND event_type LIKE 'SHOPPING%')=0, NULL);
    r := r || public._qa_s13_ok('N4R5.H3 COMMIT_TO_MERCHANT_ACCEPTED observation derived',
          EXISTS (SELECT 1 FROM public.marche_fulfillment_observations
                   WHERE order_id=v_o1 AND metric_name='COMMIT_TO_MERCHANT_ACCEPTED'), NULL);
    r := r || public._qa_s13_ok('N4R5.H4 MERCHANT_ACCEPTED_TO_READY observation derived',
          EXISTS (SELECT 1 FROM public.marche_fulfillment_observations
                   WHERE order_id=v_o1 AND metric_name='MERCHANT_ACCEPTED_TO_READY'), NULL);
    r := r || public._qa_s13_ok('N4R5.H5 COURIER_ENGAGED_TO_STORE_ARRIVAL observation derived',
          EXISTS (SELECT 1 FROM public.marche_fulfillment_observations
                   WHERE order_id=v_o1 AND metric_name='COURIER_ENGAGED_TO_STORE_ARRIVAL'), NULL);
    r := r || public._qa_s13_ok('N4R5.H6 PICKUP_TO_DELIVERED observation derived',
          EXISTS (SELECT 1 FROM public.marche_fulfillment_observations
                   WHERE order_id=v_o1 AND metric_name='PICKUP_TO_DELIVERED'), NULL);
    r := r || public._qa_s13_ok('N4R5.H7 COMMIT_TO_DELIVERED observation derived',
          EXISTS (SELECT 1 FROM public.marche_fulfillment_observations
                   WHERE order_id=v_o1 AND metric_name='COMMIT_TO_DELIVERED'), NULL);
    r := r || public._qa_s13_ok('N4R5.H8 no shopping observation fabricated',
          NOT EXISTS (SELECT 1 FROM public.marche_fulfillment_observations
                       WHERE order_id=v_o1 AND metric_name='SHOPPING_START_TO_COMPLETE'), NULL);
    r := r || public._qa_s13_ok('N4R5.H9 every observation has a non-negative duration',
          NOT EXISTS (SELECT 1 FROM public.marche_fulfillment_observations
                       WHERE order_id=v_o1 AND duration_seconds < 0), NULL);
    r := r || public._qa_s13_ok('N4R5.H10 one observation per metric (no duplicates on replay)',
          (SELECT count(*) FROM (SELECT metric_name FROM public.marche_fulfillment_observations
              WHERE order_id=v_o1 GROUP BY metric_name HAVING count(*)>1) d)=0, NULL);

    -- ================= I. SANITIZED READS =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_json := public.marche_order_get(v_o1);
    r := r || public._qa_s13_ok('N4R5.I1 buyer sees the fulfillment state',
          (v_json->>'fulfillment_state')='delivered', NULL);
    r := r || public._qa_s13_ok('N4R5.I2 buyer sees only that a courier exists, not who',
          (v_json->>'courier_assigned')::boolean = true AND NOT (v_json ? 'mission_id')
      AND NOT (v_json::text LIKE '%'||v_drv::text||'%'), NULL);
    r := r || public._qa_s13_ok('N4R5.I3 buyer still sees no merchant economics',
          NOT (v_json ? 'merchant_fee_gnf') AND NOT (v_json ? 'merchant_payable_gnf'), NULL);
    r := r || public._qa_s13_ok('N4R5.I4 buyer sees no reservation settlement internals',
          NOT (v_json ? 'reservation_settlement_kind'), NULL);
    v_json := public.marche_order_fulfillment_history(v_o1);
    r := r || public._qa_s13_ok('N4R5.I5 buyer can read sanitized history',
          jsonb_array_length(v_json) >= 6, jsonb_array_length(v_json)::text);
    r := r || public._qa_s13_ok('N4R5.I6 buyer history hides actor ids and mission ids',
          NOT (v_json::text LIKE '%actor_id%') AND NOT (v_json::text LIKE '%"mission_id"%'), NULL);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_other), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_order_fulfillment_history(v_o1);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R5.I7 stranger cannot read fulfillment history', v_err='NOT_AUTHORIZED', v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_order_get(v_o1);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R5.I8 stranger order read stays refused/empty',
          v_err IS NOT NULL OR public.marche_order_get(v_o1) IS NULL, COALESCE(v_err,'null'));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_json := public.marche_order_get(v_o1);
    r := r || public._qa_s13_ok('N4R5.I9 merchant sees mission linkage and economics',
          (v_json->>'mission_id')::uuid = v_mid AND (v_json ? 'merchant_payable_gnf'), NULL);
    r := r || public._qa_s13_ok('N4R5.I10 merchant fee snapshot unchanged by fulfillment (1%)',
          (v_json->>'merchant_platform_fee_bps')::int = 100
      AND (v_json->>'merchant_fee_gnf')::bigint = 400
      AND (v_json->>'merchant_payable_gnf')::bigint = 39600, v_json->>'merchant_fee_gnf');
    r := r || public._qa_s13_ok('N4R5.I11 delivery pricing remains honestly unresolved',
          (v_json->>'delivery_pricing_state')='unresolved' AND (v_json->>'delivery_charge_gnf') IS NULL, NULL);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_adm), true);
    v_json := public.marche_order_fulfillment_history(v_o1);
    r := r || public._qa_s13_ok('N4R5.I12 admin history carries full provenance',
          v_json::text LIKE '%actor_id%' AND v_json::text LIKE '%"mission_id"%', NULL);

    -- ================= J. REJECTION PATH =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_res := public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n45-reject-0002',
      'delivery_address','QA Ratoma',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_a, 'qty', 3))));
    v_o2 := (v_res->>'id')::uuid;
    SELECT quantity_in_stock, quantity_reserved INTO v_stock_a1, v_res_a1
      FROM public.marketplace_listings WHERE id=l_a;
    r := r || public._qa_s13_ok('N4R5.J1 second order reserved its stock', v_res_a1 = 3, v_res_a1::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_res := public.marche_merchant_transition(v_o2,'accept',NULL);
    v_res := public.marche_merchant_transition(v_o2,'reject','rupture de stock');
    r := r || public._qa_s13_ok('N4R5.J2 merchant rejection is terminal fulfillment',
          (v_res->>'fulfillment_state')='rejected', v_res->>'fulfillment_state');
    r := r || public._qa_s13_ok('N4R5.J3 rejection cancels the commercial order',
          (v_res->>'status')='cancelled', v_res->>'status');
    r := r || public._qa_s13_ok('N4R5.J4 rejection released the reservation exactly once',
          (SELECT quantity_reserved FROM public.marketplace_listings WHERE id=l_a) = v_res_a1 - 3, NULL);
    r := r || public._qa_s13_ok('N4R5.J5 rejection never touched physical stock',
          (SELECT quantity_in_stock FROM public.marketplace_listings WHERE id=l_a) = v_stock_a1, NULL);
    r := r || public._qa_s13_ok('N4R5.J6 rejection settlement recorded as released',
          (SELECT reservation_settlement_kind FROM public.marche_orders WHERE id=v_o2)='released', NULL);
    v_res := public.marche_merchant_transition(v_o2,'reject','encore');
    r := r || public._qa_s13_ok('N4R5.J7 rejection replay releases nothing twice',
          (SELECT quantity_reserved FROM public.marketplace_listings WHERE id=l_a) = v_res_a1 - 3
      AND (SELECT count(*) FROM public.marche_fulfillment_transitions WHERE order_id=v_o2 AND to_state='rejected')=1, NULL);
    v_err := NULL;
    BEGIN PERFORM public.marche_merchant_transition(v_o2,'accept',NULL);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R5.J8 rejected order cannot be resurrected', v_err='ORDER_NOT_ACTIVE', v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_dispatch_request(v_o2);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R5.J9 rejected order cannot be dispatched', v_err='ORDER_NOT_ACTIVE', v_err);
    r := r || public._qa_s13_ok('N4R5.J10 rejection emitted no delivery telemetry',
          (SELECT count(*) FROM public.marche_fulfillment_events
            WHERE order_id=v_o2 AND event_type IN ('COURIER_ENGAGED','PICKED_UP','DELIVERED'))=0, NULL);
    r := r || public._qa_s13_ok('N4R5.J11 rejected order created no mission',
          (SELECT count(*) FROM public.missions WHERE ref_market_order_id=v_o2)=0, NULL);

    -- ================= K. CANCEL BOUNDARY =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_res := public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n45-cancel-0003',
      'delivery_address','QA Matoto',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_b, 'qty', 1))));
    v_o3 := (v_res->>'id')::uuid;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    PERFORM public.marche_merchant_transition(v_o3,'accept',NULL);
    PERFORM public.marche_merchant_transition(v_o3,'prepare',NULL);
    PERFORM public.marche_merchant_transition(v_o3,'ready',NULL);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_res := public.marche_order_cancel(v_o3,'plus besoin');
    r := r || public._qa_s13_ok('N4R5.K1 buyer can still cancel before dispatch',
          (v_res->>'status')='cancelled' AND (v_res->>'fulfillment_state')='cancelled', v_res->>'fulfillment_state');
    r := r || public._qa_s13_ok('N4R5.K2 cancel released the reservation exactly once',
          (SELECT quantity_reserved FROM public.marketplace_listings WHERE id=l_b) = 0, NULL);
    v_res := public.marche_order_cancel(v_o3,'encore');
    r := r || public._qa_s13_ok('N4R5.K3 cancel replay releases nothing twice',
          (SELECT quantity_reserved FROM public.marketplace_listings WHERE id=l_b) = 0
      AND (SELECT count(*) FROM public.marche_fulfillment_transitions WHERE order_id=v_o3 AND to_state='cancelled')=1, NULL);
    v_err := NULL;
    BEGIN PERFORM public.marche_dispatch_request(v_o3);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R5.K4 cancelled order cannot be dispatched', v_err='ORDER_NOT_ACTIVE', v_err);

    -- ================= L. FINANCE NON-DRIFT (in-flight) =================
    r := r || public._qa_s13_ok('N4R5.L1 no marché wallet transaction was created by fulfillment',
          (SELECT count(*) FROM public.wallet_transactions) = v_wt0, NULL);
    r := r || public._qa_s13_ok('N4R5.L2 no ledger journal created by fulfillment',
          (SELECT count(*) FROM public.ledger_journals) = v_lj0, NULL);
    r := r || public._qa_s13_ok('N4R5.L3 no payment intent created by fulfillment',
          (SELECT count(*) FROM public.payment_intents) = v_pi0, NULL);
    r := r || public._qa_s13_ok('N4R5.L4 no merchant payable created by fulfillment',
          (SELECT count(*) FROM public.merchant_payables) = v_mp0, NULL);
    r := r || public._qa_s13_ok('N4R5.L5 no settlement request created by fulfillment',
          (SELECT count(*) FROM public.merchant_settlement_requests) = v_ss0, NULL);
    r := r || public._qa_s13_ok('N4R5.L6 active marché merchant fee still 100 bps',
          (SELECT merchant_platform_fee_bps FROM public.finance_policy_at('marche', now())) = 100, NULL);
    r := r || public._qa_s13_ok('N4R5.L7 delivery charge never invented anywhere',
          (SELECT count(*) FROM public.marche_orders WHERE delivery_charge_gnf IS NOT NULL) = 0, NULL);

  EXCEPTION WHEN OTHERS THEN
    r := r || public._qa_s13_ok('N4R5.FIXTURE runtime block completed without unhandled error', false, SQLERRM);
  END;

  -- ================= CLEANUP =================
  PERFORM set_config('request.jwt.claims','', true);
  PERFORM set_config('marche.rpc','1', true);
  DELETE FROM public.marche_order_items WHERE order_id IN
    (SELECT id FROM public.marche_orders WHERE buyer_user_id IN (v_buy, v_merch, v_other, v_adm));
  DELETE FROM public.marche_orders WHERE buyer_user_id IN (v_buy, v_merch, v_other, v_adm);
  PERFORM set_config('marche.rpc','', true);
  DELETE FROM public.mission_events WHERE mission_id IN
    (SELECT id FROM public.missions WHERE customer_id IN (v_buy, v_merch, v_other));
  DELETE FROM public.missions WHERE customer_id IN (v_buy, v_merch, v_other) OR courier_id IN (v_drv, v_drv2);
  DELETE FROM public.listing_images WHERE listing_id IN (l_a,l_b);
  DELETE FROM public.listing_metrics WHERE listing_id IN (l_a,l_b);
  DELETE FROM public.marketplace_listings WHERE seller_id IN (v_buy,v_merch,v_merch2,v_other,v_adm);
  DELETE FROM public.account_bans WHERE user_id IN (v_buy,v_merch,v_merch2,v_other,v_adm,v_drv,v_drv2);
  DELETE FROM public.merchant_stores WHERE owner_user_id IN (v_merch, v_merch2);
  DELETE FROM public.admin_users WHERE user_id = v_adm;
  DELETE FROM public.driver_profiles WHERE user_id IN (v_drv, v_drv2);
  DELETE FROM public.wallet_transactions WHERE from_wallet_id IN
      (SELECT id FROM public.wallets WHERE owner_user_id IN (v_buy,v_merch,v_merch2,v_other,v_adm,v_drv,v_drv2))
     OR to_wallet_id IN
      (SELECT id FROM public.wallets WHERE owner_user_id IN (v_buy,v_merch,v_merch2,v_other,v_adm,v_drv,v_drv2));
  DELETE FROM public.wallets WHERE owner_user_id IN (v_buy,v_merch,v_merch2,v_other,v_adm,v_drv,v_drv2);
  DELETE FROM auth.users WHERE id IN (v_buy,v_merch,v_merch2,v_other,v_adm,v_drv,v_drv2);

  -- ================= S. SYSTEMIC =================
  SELECT count(*) INTO v_w1 FROM public.wallets;
  SELECT count(*) INTO v_wt1 FROM public.wallet_transactions;
  SELECT count(*) INTO v_lj1 FROM public.ledger_journals;
  SELECT count(*) INTO v_lp1 FROM public.ledger_postings;
  SELECT count(*) INTO v_pi1 FROM public.payment_intents;
  SELECT count(*) INTO v_ms1 FROM public.missions;
  SELECT count(*) INTO v_mp1 FROM public.merchant_payables;
  SELECT count(*) INTO v_ss1 FROM public.merchant_settlement_requests;
  SELECT count(*) INTO v_total1 FROM public.marketplace_listings;
  SELECT COALESCE(sum(quantity_reserved),0) INTO v_reserved1 FROM public.marketplace_listings;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;

  r := r || public._qa_s13_ok('N4R5.S1 zero wallet / ledger / payment drift',
        v_w1=v_w0 AND v_wt1=v_wt0 AND v_lj1=v_lj0 AND v_lp1=v_lp0 AND v_pi1=v_pi0,
        format('%s/%s/%s/%s/%s', v_w1-v_w0, v_wt1-v_wt0, v_lj1-v_lj0, v_lp1-v_lp0, v_pi1-v_pi0));
  r := r || public._qa_s13_ok('N4R5.S2 zero merchant payable / settlement drift',
        v_mp1=v_mp0 AND v_ss1=v_ss0, format('%s/%s', v_mp1-v_mp0, v_ss1-v_ss0));
  r := r || public._qa_s13_ok('N4R5.S3 zero mission residue', v_ms1=v_ms0, format('%s->%s', v_ms0, v_ms1));
  r := r || public._qa_s13_ok('N4R5.S4 production listing population unchanged',
        v_total1=v_total0, format('%s->%s', v_total0, v_total1));
  r := r || public._qa_s13_ok('N4R5.S5 reserved stock returns to baseline',
        v_reserved1=v_reserved0, format('%s->%s', v_reserved0, v_reserved1));
  r := r || public._qa_s13_ok('N4R5.S6 feature flags byte-identical', v_flags1=v_flags0, NULL);
  SELECT count(*) INTO v_n FROM public.marche_orders WHERE client_request_id LIKE 'qa-n45-%';
  r := r || public._qa_s13_ok('N4R5.S7 zero order fixture residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_fulfillment_transitions t
    LEFT JOIN public.marche_orders o ON o.id=t.order_id WHERE o.id IS NULL;
  r := r || public._qa_s13_ok('N4R5.S8 zero orphan transition rows', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_fulfillment_events e
    LEFT JOIN public.marche_orders o ON o.id=e.order_id WHERE o.id IS NULL;
  r := r || public._qa_s13_ok('N4R5.S9 zero orphan telemetry rows', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_fulfillment_observations ob
    LEFT JOIN public.marche_orders o ON o.id=ob.order_id WHERE o.id IS NULL;
  r := r || public._qa_s13_ok('N4R5.S10 zero orphan observation rows', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marketplace_listings WHERE title LIKE 'QA N45%';
  r := r || public._qa_s13_ok('N4R5.S11 zero listing fixture residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.merchant_stores WHERE slug LIKE 'qa-n45-%';
  r := r || public._qa_s13_ok('N4R5.S12 zero store fixture residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM auth.users WHERE id IN (v_buy,v_merch,v_merch2,v_other,v_adm,v_drv,v_drv2);
  r := r || public._qa_s13_ok('N4R5.S13 zero auth fixture residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_orders
    WHERE fulfillment_state NOT IN ('committed','accepted','preparing','ready','courier_engaged',
                                    'collected','delivering','delivered','rejected','cancelled');
  r := r || public._qa_s13_ok('N4R5.S14 no illegal fulfillment state anywhere', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_fulfillment_events WHERE event_type LIKE 'SHOPPING%';
  r := r || public._qa_s13_ok('N4R5.S15 zero SHOPPING_* events exist in production', v_n=0, v_n::text);

  RETURN r;
END $fn$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r5() FROM PUBLIC, anon, authenticated;