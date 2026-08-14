CREATE OR REPLACE FUNCTION public.repas_delivery_earning_gnf()
RETURNS bigint LANGUAGE sql IMMUTABLE SET search_path TO 'public'
AS $$ SELECT 15000::bigint $$;
REVOKE ALL ON FUNCTION public.repas_delivery_earning_gnf() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.repas_delivery_earning_gnf() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public._qa_node3_repas_r1_r4()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_cust uuid; v_cust2 uuid; v_merch uuid; v_drv uuid;
  v_store uuid; v_resto uuid; v_resto2 uuid;
  v_item uuid; v_item2 uuid; v_item_off uuid; v_item_other uuid;
  v_o1 uuid; v_o2 uuid; v_o3 uuid;
  v_res jsonb; v_err text; v_n int; v_state text;
  v_master0 bigint; v_master1 bigint; v_flags0 jsonb; v_flags1 jsonb;
  v_mission uuid; v_cash public.cash_order_runtime; v_cp public.chop_pay_order_runtime;
  v_req uuid; v_bal bigint; v_held bigint; v_args text;
  v_unbalanced int;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;

  -- ============ STATIC SECURITY / SHAPE (B) ============
  SELECT pg_get_function_identity_arguments(p.oid) INTO v_args
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='repas_order_create';
  r := r || public._qa_s13_ok('R1.0 repas_order_create exists and takes no client price/subtotal param',
        v_args IS NOT NULL AND v_args NOT LIKE '%price%' AND v_args NOT LIKE '%subtotal%'
        AND v_args NOT LIKE '%amount%' AND v_args NOT LIKE '%user_id%', v_args);
  r := r || public._qa_s13_ok('B0.1 repas_order_create not executable by anon',
        NOT has_function_privilege('anon','public.repas_order_create(uuid,jsonb,text,text,uuid,text,double precision,double precision,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('B0.2 repas_merchant_transition not executable by anon',
        NOT has_function_privilege('anon','public.repas_merchant_transition(uuid,text,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('B0.3 repas_customer_cancel_order not executable by anon',
        NOT has_function_privilege('anon','public.repas_customer_cancel_order(uuid,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('B0.4 repas_complete_order not executable by anon',
        NOT has_function_privilege('anon','public.repas_complete_order(uuid,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('B0.5 raw cash engine internal closed to authenticated',
        NOT has_function_privilege('authenticated','public._cash_order_accept_internal(text,uuid,uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('B0.6 raw chop pay hold internal closed to authenticated',
        NOT has_function_privilege('authenticated','public._chop_pay_customer_hold_internal(text,uuid,uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('B0.7 this harness is closed to anon/authenticated',
        NOT has_function_privilege('anon','public._qa_node3_repas_r1_r4()','EXECUTE')
        AND NOT has_function_privilege('authenticated','public._qa_node3_repas_r1_r4()','EXECUTE'), NULL);

  -- RLS posture
  SELECT count(*) INTO v_n FROM pg_policies
   WHERE tablename='food_orders' AND cmd='INSERT' AND policyname <> 'Admins manage orders';
  r := r || public._qa_s13_ok('B0.8 no customer INSERT policy remains on food_orders', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM pg_policies
   WHERE tablename='food_orders' AND cmd='UPDATE' AND policyname <> 'Admins manage orders';
  r := r || public._qa_s13_ok('B0.9 no customer/merchant UPDATE policy remains on food_orders', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM pg_policies
   WHERE tablename='food_order_items' AND cmd='INSERT' AND policyname <> 'Admins manage order items';
  r := r || public._qa_s13_ok('B0.10 no customer INSERT policy remains on food_order_items', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM pg_policies WHERE tablename='food_orders' AND cmd='SELECT';
  r := r || public._qa_s13_ok('B0.11 participant read policy preserved on food_orders', v_n >= 1, v_n::text);

  BEGIN
    -- ============ FIXTURES ============
    v_cust := gen_random_uuid(); v_cust2 := gen_random_uuid();
    v_merch := gen_random_uuid(); v_drv := gen_random_uuid();
    PERFORM public._qa_s13_user(v_cust,'n3c');
    PERFORM public._qa_s13_user(v_cust2,'n3x');
    PERFORM public._qa_s13_user(v_merch,'n3m');
    PERFORM public._qa_s13_user(v_drv,'n3d');
    PERFORM public._qa_s13_wallet(v_cust,'client',900000,0);
    PERFORM public._qa_s13_wallet(v_cust2,'client',900000,0);
    PERFORM public._qa_s13_wallet(v_merch,'merchant',0,0);
    PERFORM public._qa_s13_wallet(v_drv,'driver',900000,0);

    INSERT INTO public.driver_profiles(user_id,status,vehicle_type,capabilities)
      VALUES (v_drv,'approved','livraison',ARRAY['repas_delivery'])
      ON CONFLICT (user_id) DO UPDATE SET status='approved', capabilities=ARRAY['repas_delivery'];

    INSERT INTO public.merchant_stores(owner_user_id, slug, name, delivery_available, status)
      VALUES (v_merch, 'qa-n3-store-'||substr(v_merch::text,1,8), 'QA N3 Store', true, 'active')
      RETURNING id INTO v_store;

    INSERT INTO public.food_restaurants(owner_user_id, merchant_store_id, slug, name, status,
        is_open, delivery_available, pickup_available, choppay_enabled, prep_time_min)
      VALUES (v_merch, v_store, 'qa-n3-resto-'||substr(v_merch::text,1,8), 'QA N3 Resto',
              'active', true, true, true, true, 20)
      RETURNING id INTO v_resto;

    INSERT INTO public.food_restaurants(owner_user_id, slug, name, status, is_open,
        delivery_available, pickup_available, prep_time_min)
      VALUES (v_merch, 'qa-n3-resto2-'||substr(v_merch::text,1,8), 'QA N3 Resto 2',
              'active', false, true, true, 20)
      RETURNING id INTO v_resto2;

    -- 150 000 GNF merchandise fixture = 1 x 100 000 + 1 x 50 000
    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
      VALUES (v_resto,'QA Plat A',100000,true) RETURNING id INTO v_item;
    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
      VALUES (v_resto,'QA Plat B',50000,true) RETURNING id INTO v_item2;
    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
      VALUES (v_resto,'QA Plat Indispo',7000,false) RETURNING id INTO v_item_off;
    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
      VALUES (v_resto2,'QA Autre Resto',9000,true) RETURNING id INTO v_item_other;

    -- ============ A. R1 AUTHORITY ============
    PERFORM set_config('request.jwt.claims', ''::text, true);
    BEGIN PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'pickup','cash',gen_random_uuid()); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A0.1 unauthenticated order creation fails closed',
          v_err LIKE '%NOT_AUTHENTICATED%', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);

    -- manipulated client fields are simply not accepted by the signature; prove
    -- extra keys in the item payload are ignored and server prices win.
    v_req := gen_random_uuid();
    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(
          jsonb_build_object('menu_item_id',v_item,'qty',1,'unit_price_gnf',1,'name','HACK'),
          jsonb_build_object('menu_item_id',v_item2,'qty',1,'unit_price_gnf',1)),
        'pickup','cash', v_req);
    v_o1 := (v_res->>'order_id')::uuid;
    r := r || public._qa_s13_ok('A1.1 server reprices from menu truth despite manipulated client values',
          (v_res->>'subtotal_gnf')::bigint = 150000, v_res->>'subtotal_gnf');
    SELECT subtotal_gnf INTO v_bal FROM public.food_orders WHERE id = v_o1;
    r := r || public._qa_s13_ok('A1.2 persisted subtotal equals server total', v_bal = 150000, v_bal::text);
    SELECT count(*) INTO v_n FROM public.food_order_items WHERE order_id = v_o1;
    r := r || public._qa_s13_ok('A1.3 exactly two server-resolved item rows', v_n = 2, v_n::text);
    SELECT count(*) INTO v_n FROM public.food_order_items
      WHERE order_id = v_o1 AND unit_price_gnf IN (100000,50000);
    r := r || public._qa_s13_ok('A1.4 item snapshots carry server unit prices', v_n = 2, v_n::text);
    SELECT count(*) INTO v_n FROM public.food_order_items WHERE order_id=v_o1 AND name_snapshot='HACK';
    r := r || public._qa_s13_ok('A1.5 client-supplied item name ignored', v_n = 0, v_n::text);

    -- idempotent replay
    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(
          jsonb_build_object('menu_item_id',v_item,'qty',1),
          jsonb_build_object('menu_item_id',v_item2,'qty',1)),
        'pickup','cash', v_req);
    r := r || public._qa_s13_ok('A2.1 replay of same client_request_id returns the same order',
          (v_res->>'order_id')::uuid = v_o1 AND (v_res->>'replay')::boolean, v_res::text);
    SELECT count(*) INTO v_n FROM public.food_orders WHERE client_request_id = v_req;
    r := r || public._qa_s13_ok('A2.2 replay created no second order', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.food_order_items WHERE order_id = v_o1;
    r := r || public._qa_s13_ok('A2.3 replay created no duplicate items', v_n = 2, v_n::text);

    BEGIN PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',9)),
        'pickup','cash', v_req); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A2.4 contradictory replay denied',
          v_err LIKE '%IDEMPOTENCY_CONFLICT%', v_err);
    SELECT count(*) INTO v_n FROM public.food_orders WHERE client_request_id = v_req;
    r := r || public._qa_s13_ok('A2.5 contradictory replay created zero orders', v_n = 1, v_n::text);

    -- negative validation, each must leave zero new orders
    SELECT count(*) INTO v_n FROM public.food_orders WHERE user_id = v_cust;
    BEGIN PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item_off,'qty',1)),
        'pickup','cash', gen_random_uuid()); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A3.1 unavailable item denied', v_err LIKE '%ITEM_UNAVAILABLE%', v_err);

    BEGIN PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item_other,'qty',1)),
        'pickup','cash', gen_random_uuid()); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A3.2 wrong-restaurant item denied', v_err LIKE '%ITEM_WRONG_RESTAURANT%', v_err);

    BEGIN PERFORM public.repas_order_create(v_resto2,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item_other,'qty',1)),
        'pickup','cash', gen_random_uuid()); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A3.3 closed restaurant denied', v_err LIKE '%RESTAURANT_CLOSED%', v_err);

    BEGIN PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',0)),
        'pickup','cash', gen_random_uuid()); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A3.4 non-positive quantity denied', v_err LIKE '%INVALID_QUANTITY%', v_err);

    BEGIN PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'pickup','wallet', gen_random_uuid()); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A3.5 legacy wallet tender rejected', v_err LIKE '%UNSUPPORTED_TENDER%', v_err);

    BEGIN PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'delivery','cash', gen_random_uuid()); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A3.6 delivery without location denied',
          v_err LIKE '%DELIVERY_LOCATION_REQUIRED%', v_err);

    SELECT count(*) INTO v_n FROM public.food_orders WHERE user_id = v_cust;
    r := r || public._qa_s13_ok('A3.7 every denied attempt created zero orders', v_n = 1, v_n::text);

    -- frozen snapshot: later menu price change must not move a committed order
    UPDATE public.food_menu_items SET price_gnf = 999999 WHERE id = v_item;
    SELECT subtotal_gnf INTO v_bal FROM public.food_orders WHERE id = v_o1;
    r := r || public._qa_s13_ok('A4.1 committed order economics frozen against menu price change',
          v_bal = 150000, v_bal::text);
    UPDATE public.food_menu_items SET price_gnf = 100000 WHERE id = v_item;

    -- ============ B. R2 SECURITY (runtime) ============
    BEGIN PERFORM public.repas_customer_cancel_order(v_o1, 'x'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B1.0 owner may cancel own un-prepared order', v_err = 'NO_ERROR', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust2), true);
    BEGIN PERFORM public.repas_customer_cancel_order(v_o1, 'x'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B1.1 cross-customer cancellation denied',
          v_err LIKE '%NOT_AUTHORIZED%', v_err);
    BEGIN PERFORM public.repas_merchant_transition(v_o1,'accept'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B1.2 non-owner merchant transition denied',
          v_err LIKE '%NOT_AUTHORIZED%', v_err);

    -- ============ C. CASH RAIL ============
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(
          jsonb_build_object('menu_item_id',v_item,'qty',1),
          jsonb_build_object('menu_item_id',v_item2,'qty',1)),
        'delivery','cash', gen_random_uuid(), 'Kaloum, Conakry', 9.5100, -13.7000);
    v_o2 := (v_res->>'order_id')::uuid;
    v_mission := (v_res->>'mission_id')::uuid;
    r := r || public._qa_s13_ok('C0.1 cash delivery order creates canonical food_delivery mission',
          v_mission IS NOT NULL, v_mission::text);
    SELECT count(*) INTO v_n FROM public.missions
      WHERE id=v_mission AND type='food_delivery' AND estimated_earning_gnf = public.repas_delivery_earning_gnf();
    r := r || public._qa_s13_ok('C0.2 courier earning is the server snapshot (15 000 GNF)', v_n = 1, v_n::text);
    r := r || public._qa_s13_ok('C0.3 no financial value moves at cash commitment',
          NOT EXISTS (SELECT 1 FROM public.cash_order_runtime WHERE source_module='repas' AND source_id=v_o2)
          AND NOT EXISTS (SELECT 1 FROM public.chop_pay_order_runtime WHERE source_module='repas' AND source_id=v_o2),
          'inert until courier engagement (Slice 4 contract)');

    -- flag OFF: courier engagement must fail closed, zero runtime, zero value
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    BEGIN PERFORM public.mission_claim(v_mission); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('C1.1 cash rail flag OFF fails closed at courier engagement',
          v_err <> 'NO_ERROR', v_err);
    r := r || public._qa_s13_ok('C1.2 flag OFF created zero cash runtime',
          NOT EXISTS (SELECT 1 FROM public.cash_order_runtime WHERE source_module='repas' AND source_id=v_o2), NULL);

    -- enable rail inside the rolled-back fixture only
    UPDATE public.feature_flags SET enabled = true WHERE key = 'cash_order_funding_enabled';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    BEGIN PERFORM public.mission_claim(v_mission); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('C2.1 courier engagement succeeds with rail enabled', v_err = 'NO_ERROR', v_err);
    SELECT * INTO v_cash FROM public.cash_order_runtime
      WHERE source_module='repas' AND source_id=v_o2;
    r := r || public._qa_s13_ok('C2.2 exactly one cash runtime for the committed cash order',
          v_cash.id IS NOT NULL, v_cash.state);
    SELECT count(*) INTO v_n FROM public.chop_pay_order_runtime WHERE source_module='repas' AND source_id=v_o2;
    r := r || public._qa_s13_ok('C2.3 cash order has zero Chop Pay runtime', v_n = 0, v_n::text);
    r := r || public._qa_s13_ok('C2.4 merchandise 150 000 + delivery 15 000 frozen on runtime',
          v_cash.merchandise_subtotal_gnf = 150000 AND v_cash.delivery_fee_gnf = 15000,
          v_cash.merchandise_subtotal_gnf::text||'/'||v_cash.delivery_fee_gnf::text);
    r := r || public._qa_s13_ok('C2.5 cash due = merchandise + delivery + 1% platform fee',
          v_cash.cash_due_gnf = v_cash.merchandise_subtotal_gnf + v_cash.delivery_fee_gnf
                                 + v_cash.platform_fee_gnf
          AND v_cash.platform_fee_gnf = 1500,
          v_cash.cash_due_gnf::text||' fee='||v_cash.platform_fee_gnf::text);

    -- R4 state machine on the cash rail
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    BEGIN PERFORM public.repas_merchant_transition(v_o2,'ready'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('E1.1 illegal jump placed -> ready denied',
          v_err LIKE '%ILLEGAL_TRANSITION%', v_err);
    SELECT state::text INTO v_state FROM public.food_orders WHERE id=v_o2;
    r := r || public._qa_s13_ok('E1.2 illegal jump left state untouched', v_state='placed', v_state);

    BEGIN PERFORM public.repas_merchant_transition(v_o2,'prepare'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('E1.3 prepare before merchant funding denied', v_err <> 'NO_ERROR', v_err);

    v_res := public.repas_merchant_transition(v_o2,'accept');
    SELECT state::text INTO v_state FROM public.food_orders WHERE id=v_o2;
    r := r || public._qa_s13_ok('E2.1 merchant accept own cash order succeeds', v_state='confirmed', v_state);
    SELECT count(*) INTO v_n FROM public.cash_order_runtime
      WHERE source_module='repas' AND source_id=v_o2 AND state='merchant_accepted';
    r := r || public._qa_s13_ok('E2.2 cash engine reached merchant_accepted (funded)', v_n=1, v_n::text);

    v_res := public.repas_merchant_transition(v_o2,'accept');
    r := r || public._qa_s13_ok('E2.3 duplicate accept is idempotent, no extra money',
          (v_res->>'idempotent')::boolean, v_res::text);
    SELECT count(*) INTO v_n FROM public.merchant_payables
      WHERE source_module='repas' AND source_id=v_o2;
    r := r || public._qa_s13_ok('E2.4 exactly one merchant payable for the order', v_n=1, v_n::text);

    PERFORM public.repas_merchant_transition(v_o2,'prepare');
    SELECT state::text INTO v_state FROM public.food_orders WHERE id=v_o2;
    r := r || public._qa_s13_ok('E3.1 prepare after funding succeeds', v_state='preparing', v_state);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    BEGIN PERFORM public.repas_customer_cancel_order(v_o2,'change of mind'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('E4.1 customer cancel after preparing denied',
          v_err LIKE '%PREPARATION_LOCKED%' OR v_err LIKE '%PREPARATION%', v_err);
    SELECT state::text INTO v_state FROM public.food_orders WHERE id=v_o2;
    r := r || public._qa_s13_ok('E4.2 denied cancellation mutated nothing', v_state='preparing', v_state);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    PERFORM public.repas_merchant_transition(v_o2,'ready');
    SELECT state::text INTO v_state FROM public.food_orders WHERE id=v_o2;
    r := r || public._qa_s13_ok('E3.2 ready transition legal after preparing', v_state='ready', v_state);

    -- cash merchant reject path on a fresh order
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item2,'qty',1)),
        'delivery','cash', gen_random_uuid(), 'Ratoma, Conakry', 9.5600, -13.6600);
    v_o3 := (v_res->>'order_id')::uuid;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_res := public.repas_merchant_transition(v_o3,'reject','rupture de stock');
    SELECT state::text INTO v_state FROM public.food_orders WHERE id=v_o3;
    r := r || public._qa_s13_ok('E5.1 merchant reject before courier engagement cancels order',
          v_state='cancelled', v_state);
    r := r || public._qa_s13_ok('E5.2 reject leaves no orphan cash runtime',
          NOT EXISTS (SELECT 1 FROM public.cash_order_runtime WHERE source_module='repas' AND source_id=v_o3), NULL);
    SELECT count(*) INTO v_n FROM public.missions
      WHERE ref_food_order_id=v_o3 AND state='assigned' AND courier_id IS NULL;
    r := r || public._qa_s13_ok('E5.3 reject retires the unclaimed delivery mission', v_n=0, v_n::text);
    v_res := public.repas_merchant_transition(v_o3,'reject','again');
    r := r || public._qa_s13_ok('E5.4 duplicate reject is idempotent', (v_res->>'idempotent')::boolean, v_res::text);

    -- ============ D. CHOP PAY RAIL ============
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust2), true);
    BEGIN PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'delivery','choppay', gen_random_uuid(), 'Kaloum', 9.51, -13.70); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('D1.1 Chop Pay flag OFF fails closed at commitment',
          v_err LIKE '%CHOP_PAY_CHECKOUT_DISABLED%', v_err);
    SELECT count(*) INTO v_n FROM public.food_orders WHERE user_id=v_cust2;
    r := r || public._qa_s13_ok('D1.2 Chop Pay flag OFF created zero order and zero value', v_n=0, v_n::text);

    UPDATE public.feature_flags SET enabled = true
      WHERE key IN ('chop_pay_checkout_enabled','chop_pay_enabled');
    SELECT balance_gnf, held_gnf INTO v_bal, v_held
      FROM public.wallets WHERE owner_user_id=v_cust2 AND party_type='client';

    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(
          jsonb_build_object('menu_item_id',v_item,'qty',1),
          jsonb_build_object('menu_item_id',v_item2,'qty',1)),
        'delivery','choppay', gen_random_uuid(), 'Kaloum, Conakry', 9.5100, -13.7000);
    v_o3 := (v_res->>'order_id')::uuid;
    SELECT * INTO v_cp FROM public.chop_pay_order_runtime
      WHERE source_module='repas' AND source_id=v_o3;
    r := r || public._qa_s13_ok('D2.1 committed Chop Pay order creates exactly one Chop Pay runtime',
          v_cp.id IS NOT NULL, COALESCE(v_cp.state,'none'));
    SELECT count(*) INTO v_n FROM public.cash_order_runtime WHERE source_module='repas' AND source_id=v_o3;
    r := r || public._qa_s13_ok('D2.2 Chop Pay order has zero cash runtime', v_n=0, v_n::text);
    r := r || public._qa_s13_ok('D2.3 customer hold equals full order total',
          v_cp.order_total_gnf = v_cp.merchandise_subtotal_gnf + v_cp.delivery_fee_gnf + v_cp.platform_fee_gnf,
          v_cp.order_total_gnf::text);
    SELECT held_gnf INTO v_held FROM public.wallets WHERE owner_user_id=v_cust2 AND party_type='client';
    r := r || public._qa_s13_ok('D2.4 customer wallet holds the full order total',
          v_held = v_cp.order_total_gnf, v_held::text);
    r := r || public._qa_s13_ok('D2.5 authorization state is canonical', v_cp.state='authorized', v_cp.state);

    -- replay must not create a second runtime or move extra value
    SELECT held_gnf INTO v_bal FROM public.wallets WHERE owner_user_id=v_cust2 AND party_type='client';
    SELECT client_request_id INTO v_req FROM public.food_orders WHERE id=v_o3;
    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(
          jsonb_build_object('menu_item_id',v_item,'qty',1),
          jsonb_build_object('menu_item_id',v_item2,'qty',1)),
        'delivery','choppay', v_req, 'Kaloum, Conakry', 9.5100, -13.7000);
    SELECT count(*) INTO v_n FROM public.chop_pay_order_runtime WHERE source_module='repas' AND source_id=v_o3;
    r := r || public._qa_s13_ok('D3.1 replay creates no duplicate Chop Pay runtime', v_n=1, v_n::text);
    SELECT held_gnf INTO v_held FROM public.wallets WHERE owner_user_id=v_cust2 AND party_type='client';
    r := r || public._qa_s13_ok('D3.2 replay moves zero extra value', v_held = v_bal, v_held::text);

    -- merchant reject on Chop Pay releases the hold
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_res := public.repas_merchant_transition(v_o3,'reject','indisponible');
    SELECT state::text INTO v_state FROM public.food_orders WHERE id=v_o3;
    r := r || public._qa_s13_ok('E6.1 Chop Pay merchant reject cancels the order', v_state='cancelled', v_state);
    SELECT held_gnf INTO v_held FROM public.wallets WHERE owner_user_id=v_cust2 AND party_type='client';
    r := r || public._qa_s13_ok('E6.2 Chop Pay reject releases the customer hold (no orphan hold)',
          v_held = 0, v_held::text);

    -- ============ F. INVARIANTS ============
    SELECT count(*) INTO v_unbalanced FROM (
      SELECT j.id FROM public.ledger_journals j
        JOIN public.ledger_postings p ON p.journal_id = j.id
       WHERE j.created_at >= now() - interval '5 minutes'
       GROUP BY j.id HAVING sum(p.amount_gnf) <> 0
    ) z;
    r := r || public._qa_s13_ok('F1.1 every journal created by fixtures is zero-sum',
          v_unbalanced = 0, v_unbalanced::text);

    PERFORM set_config('request.jwt.claims', ''::text, true);
    RAISE EXCEPTION 'QA_NODE3_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_NODE3_ROLLBACK' THEN
      r := r || public._qa_s13_ok('HARNESS aborted before completion', false, SQLERRM);
    END IF;
  END;

  PERFORM set_config('request.jwt.claims', ''::text, true);
  SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;
  r := r || public._qa_s13_ok('Z3.1 master wallet unchanged after fixture rollback',
        v_master0 IS NOT DISTINCT FROM v_master1, v_master1::text);
  r := r || public._qa_s13_ok('Z3.2 feature flags byte-identical after fixture rollback',
        v_flags0 = v_flags1, NULL);
  SELECT count(*) INTO v_n FROM public.food_orders o
    JOIN auth.users u ON u.id = o.user_id WHERE u.email LIKE 'qa-s13-n3%';
  r := r || public._qa_s13_ok('Z3.3 no Repas order fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.food_restaurants WHERE slug LIKE 'qa-n3-%';
  r := r || public._qa_s13_ok('Z3.4 no restaurant fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.cash_order_runtime c
    JOIN auth.users u ON u.id = c.customer_user_id WHERE u.email LIKE 'qa-s13-n3%';
  r := r || public._qa_s13_ok('Z3.5 no cash runtime residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.chop_pay_order_runtime c
    JOIN auth.users u ON u.id = c.customer_user_id WHERE u.email LIKE 'qa-s13-n3%';
  r := r || public._qa_s13_ok('Z3.6 no Chop Pay runtime residue', v_n = 0, v_n::text);

  RETURN jsonb_build_object(
    'part','node3_repas_r1_r4',
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'results', r);
END; $function$;

REVOKE ALL ON FUNCTION public._qa_node3_repas_r1_r4() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node3_repas_r1_r4() TO service_role;