CREATE OR REPLACE FUNCTION public._qa_node3_repas_r1_r4()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_cust uuid; v_cust2 uuid; v_cust3 uuid; v_cust4 uuid;
  v_merch uuid; v_drv uuid; v_drv2 uuid;
  v_store uuid; v_resto uuid; v_resto2 uuid;
  v_item uuid; v_item2 uuid; v_item_off uuid; v_item_other uuid;
  v_o1 uuid; v_o2 uuid; v_o3 uuid; v_o4 uuid; v_o5 uuid;
  v_res jsonb; v_err text; v_n int; v_state text;
  v_master0 bigint; v_master1 bigint; v_flags0 jsonb; v_flags1 jsonb;
  v_mission uuid; v_mission4 uuid; v_mission5 uuid;
  v_cash public.cash_order_runtime; v_cp public.chop_pay_order_runtime;
  v_req uuid; v_bal bigint; v_held bigint; v_args text;
  v_unbalanced int; v_debt public.customer_cancellation_debts;
  v_c0 bigint; v_m0 bigint; v_d0 bigint; v_x0 bigint;
  v_c1 bigint; v_m1 bigint; v_d1 bigint; v_x1 bigint;
  v_col bigint; v_open bigint; v_pay public.merchant_payables;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;

  -- ============ STATIC SECURITY / SHAPE (B0) ============
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

  SELECT pg_get_functiondef(p.oid) INTO v_args FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='repas_order_create';
  r := r || public._qa_s13_ok('B0.12 commitment source gates the cash funding rail',
        v_args LIKE '%cash_order_funding_enabled%', NULL);
  r := r || public._qa_s13_ok('B0.13 commitment source carries the temporary pickup guard',
        v_args LIKE '%PICKUP_NOT_YET_SUPPORTED%', NULL);
  r := r || public._qa_s13_ok('B0.14 fingerprint covers coordinates and notes',
        v_args LIKE '%p_delivery_lat::numeric%' AND v_args LIKE '%p_delivery_lng::numeric%'
        AND v_args LIKE '%COALESCE(v_notes%', NULL);
  SELECT pg_get_functiondef(p.oid) INTO v_args FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='repas_customer_cancel_order';
  r := r || public._qa_s13_ok('B0.15 cancellation routes on committed tender, not runtime existence',
        v_args LIKE '%v_o.payment_method::text%'
        AND v_args NOT LIKE '%EXISTS (SELECT 1 FROM public.cash_order_runtime%', NULL);

  BEGIN
    -- ============ FIXTURES ============
    v_cust := gen_random_uuid(); v_cust2 := gen_random_uuid(); v_cust3 := gen_random_uuid();
    v_cust4 := gen_random_uuid();
    v_merch := gen_random_uuid(); v_drv := gen_random_uuid(); v_drv2 := gen_random_uuid();
    PERFORM public._qa_s13_user(v_cust,'n3c');
    PERFORM public._qa_s13_user(v_cust2,'n3x');
    PERFORM public._qa_s13_user(v_cust3,'n3y');
    PERFORM public._qa_s13_user(v_cust4,'n3z');
    PERFORM public._qa_s13_user(v_merch,'n3m');
    PERFORM public._qa_s13_user(v_drv,'n3d');
    PERFORM public._qa_s13_user(v_drv2,'n3e');
    PERFORM public._qa_s13_wallet(v_cust,'client',900000,0);
    PERFORM public._qa_s13_wallet(v_cust2,'client',900000,0);
    PERFORM public._qa_s13_wallet(v_cust3,'client',900000,0);
    PERFORM public._qa_s13_wallet(v_cust4,'client',900000,0);
    PERFORM public._qa_s13_wallet(v_merch,'merchant',0,0);
    PERFORM public._qa_s13_wallet(v_drv,'driver',900000,0);
    PERFORM public._qa_s13_wallet(v_drv2,'driver',900000,0);

    INSERT INTO public.driver_profiles(user_id,status,vehicle_type,capabilities)
      VALUES (v_drv,'approved','livraison',ARRAY['repas_delivery'])
      ON CONFLICT (user_id) DO UPDATE SET status='approved', capabilities=ARRAY['repas_delivery'];
    INSERT INTO public.driver_profiles(user_id,status,vehicle_type,capabilities)
      VALUES (v_drv2,'approved','livraison',ARRAY['repas_delivery'])
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

    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
      VALUES (v_resto,'QA Plat A',100000,true) RETURNING id INTO v_item;
    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
      VALUES (v_resto,'QA Plat B',50000,true) RETURNING id INTO v_item2;
    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
      VALUES (v_resto,'QA Plat Indispo',7000,false) RETURNING id INTO v_item_off;
    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
      VALUES (v_resto2,'QA Autre Resto',9000,true) RETURNING id INTO v_item_other;

    -- ============ M. MC2 / MC3 FAIL-CLOSED AT PRODUCTION FLAG TRUTH ============
    r := r || public._qa_s13_ok('M0.0 cash rail flag is OFF at this point (production truth)',
          NOT public._finance_flag('cash_order_funding_enabled'), NULL);

    PERFORM set_config('request.jwt.claims', ''::text, true);
    BEGIN PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'delivery','cash',gen_random_uuid(),'Kaloum',9.51,-13.70); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A0.1 unauthenticated order creation fails closed',
          v_err LIKE '%NOT_AUTHENTICATED%', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);

    BEGIN PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'pickup','cash', gen_random_uuid()); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('M1.1 cash pickup commitment fails closed (R4.5 not shipped)',
          v_err LIKE '%PICKUP_NOT_YET_SUPPORTED%', v_err);
    BEGIN PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'pickup','choppay', gen_random_uuid()); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('M1.2 Chop Pay pickup commitment fails closed too',
          v_err LIKE '%PICKUP_NOT_YET_SUPPORTED%', v_err);

    BEGIN PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'delivery','cash', gen_random_uuid(), 'Kaloum, Conakry', 9.5100, -13.7000);
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('M2.1 cash delivery commitment fails closed when the rail is OFF',
          v_err LIKE '%CASH_ORDER_FUNDING_DISABLED%', v_err);

    SELECT count(*) INTO v_n FROM public.food_orders WHERE user_id = v_cust;
    r := r || public._qa_s13_ok('M2.2 fail-closed commitments created zero orders', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.missions WHERE customer_id = v_cust;
    r := r || public._qa_s13_ok('M2.3 fail-closed commitments created zero missions', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.cash_order_runtime WHERE customer_user_id = v_cust;
    r := r || public._qa_s13_ok('M2.4 fail-closed commitments created zero cash runtime', v_n = 0, v_n::text);
    SELECT held_gnf INTO v_held FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('M2.5 fail-closed commitments moved zero value', v_held = 0, v_held::text);

    UPDATE public.feature_flags SET enabled = true WHERE key = 'cash_order_funding_enabled';

    -- ============ A. R1 AUTHORITY ============
    v_req := gen_random_uuid();
    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(
          jsonb_build_object('menu_item_id',v_item,'qty',1,'unit_price_gnf',1,'name','HACK'),
          jsonb_build_object('menu_item_id',v_item2,'qty',1,'unit_price_gnf',1)),
        'delivery','cash', v_req, 'Kaloum, Conakry', 9.5100, -13.7000);
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

    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(
          jsonb_build_object('menu_item_id',v_item,'qty',1),
          jsonb_build_object('menu_item_id',v_item2,'qty',1)),
        'delivery','cash', v_req, 'Kaloum, Conakry', 9.5100, -13.7000);
    r := r || public._qa_s13_ok('A2.1 replay of same client_request_id returns the same order',
          (v_res->>'order_id')::uuid = v_o1 AND (v_res->>'replay')::boolean, v_res::text);
    SELECT count(*) INTO v_n FROM public.food_orders WHERE client_request_id = v_req;
    r := r || public._qa_s13_ok('A2.2 replay created no second order', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.food_order_items WHERE order_id = v_o1;
    r := r || public._qa_s13_ok('A2.3 replay created no duplicate items', v_n = 2, v_n::text);
    SELECT count(*) INTO v_n FROM public.missions WHERE ref_food_order_id = v_o1;
    r := r || public._qa_s13_ok('A2.3b replay created no duplicate mission', v_n = 1, v_n::text);

    BEGIN PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',9)),
        'delivery','cash', v_req, 'Kaloum, Conakry', 9.5100, -13.7000); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A2.4 contradictory replay (items) denied',
          v_err LIKE '%IDEMPOTENCY_CONFLICT%', v_err);

    BEGIN PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(
          jsonb_build_object('menu_item_id',v_item,'qty',1),
          jsonb_build_object('menu_item_id',v_item2,'qty',1)),
        'delivery','cash', v_req, 'Kaloum, Conakry', 9.5100, -13.7000, 'sans piment');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A2.6 contradictory replay (notes) denied',
          v_err LIKE '%IDEMPOTENCY_CONFLICT%', v_err);

    BEGIN PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(
          jsonb_build_object('menu_item_id',v_item,'qty',1),
          jsonb_build_object('menu_item_id',v_item2,'qty',1)),
        'delivery','cash', v_req, 'Kaloum, Conakry', 9.6000, -13.7000); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A2.7 contradictory replay (drop-off latitude) denied',
          v_err LIKE '%IDEMPOTENCY_CONFLICT%', v_err);

    BEGIN PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(
          jsonb_build_object('menu_item_id',v_item,'qty',1),
          jsonb_build_object('menu_item_id',v_item2,'qty',1)),
        'delivery','cash', v_req, 'Kaloum, Conakry', 9.5100, -13.6500); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A2.8 contradictory replay (drop-off longitude) denied',
          v_err LIKE '%IDEMPOTENCY_CONFLICT%', v_err);

    BEGIN PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(
          jsonb_build_object('menu_item_id',v_item,'qty',1),
          jsonb_build_object('menu_item_id',v_item2,'qty',1)),
        'delivery','cash', v_req, 'Matam, Conakry', 9.5100, -13.7000); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A2.9 contradictory replay (address) denied',
          v_err LIKE '%IDEMPOTENCY_CONFLICT%', v_err);

    SELECT count(*) INTO v_n FROM public.food_orders WHERE client_request_id = v_req;
    r := r || public._qa_s13_ok('A2.5 every contradictory replay created zero extra orders',
          v_n = 1, v_n::text);

    BEGIN PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item_off,'qty',1)),
        'delivery','cash', gen_random_uuid(), 'Kaloum', 9.51, -13.70); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A3.1 unavailable item denied', v_err LIKE '%ITEM_UNAVAILABLE%', v_err);

    BEGIN PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item_other,'qty',1)),
        'delivery','cash', gen_random_uuid(), 'Kaloum', 9.51, -13.70); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A3.2 wrong-restaurant item denied', v_err LIKE '%ITEM_WRONG_RESTAURANT%', v_err);

    BEGIN PERFORM public.repas_order_create(v_resto2,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item_other,'qty',1)),
        'delivery','cash', gen_random_uuid(), 'Kaloum', 9.51, -13.70); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A3.3 closed restaurant denied', v_err LIKE '%RESTAURANT_CLOSED%', v_err);

    BEGIN PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',0)),
        'delivery','cash', gen_random_uuid(), 'Kaloum', 9.51, -13.70); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A3.4 non-positive quantity denied', v_err LIKE '%INVALID_QUANTITY%', v_err);

    BEGIN PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'delivery','wallet', gen_random_uuid(), 'Kaloum', 9.51, -13.70); v_err := 'NO_ERROR';
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

    UPDATE public.food_menu_items SET price_gnf = 999999 WHERE id = v_item;
    SELECT subtotal_gnf INTO v_bal FROM public.food_orders WHERE id = v_o1;
    r := r || public._qa_s13_ok('A4.1 committed order economics frozen against menu price change',
          v_bal = 150000, v_bal::text);
    UPDATE public.food_menu_items SET price_gnf = 100000 WHERE id = v_item;

    -- ============ MC4. PRE-DISPATCH CASH CANCELLATION -> SLICE 8 ============
    r := r || public._qa_s13_ok('MC4.0 no cash runtime exists before courier engagement',
          NOT EXISTS (SELECT 1 FROM public.cash_order_runtime
                       WHERE source_module='repas' AND source_id=v_o1), NULL);
    SELECT balance_gnf INTO v_c0 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    v_res := public.repas_customer_cancel_order(v_o1, 'change of mind');
    SELECT * INTO v_debt FROM public.customer_cancellation_debts
     WHERE source_module='repas' AND source_id=v_o1;
    r := r || public._qa_s13_ok('MC4.1 pre-dispatch cash cancellation creates a Slice 8 debt',
          v_debt.id IS NOT NULL, COALESCE(v_debt.state,'none'));
    r := r || public._qa_s13_ok('MC4.2 debt stage is before_dispatch',
          v_debt.stage = 'before_dispatch', COALESCE(v_debt.stage,'none'));
    r := r || public._qa_s13_ok('MC4.3 debt basis = merchandise 150 000 + delivery 15 000',
          v_debt.basis_gnf = 165000, v_debt.basis_gnf::text);
    r := r || public._qa_s13_ok('MC4.4 applied bps is the canonical repas policy (500)',
          v_debt.applied_bps = 500, v_debt.applied_bps::text);
    r := r || public._qa_s13_ok('MC4.5 debt amount = 5% of basis, charged exactly once',
          v_debt.amount_gnf = 8250, v_debt.amount_gnf::text);
    SELECT count(*) INTO v_n FROM public.customer_cancellation_debts
     WHERE source_module='repas' AND source_id=v_o1;
    r := r || public._qa_s13_ok('MC4.6 exactly one debt row for the order', v_n = 1, v_n::text);
    SELECT balance_gnf INTO v_c1 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    r := r || public._qa_s13_ok('MC4.7 a cash cancellation debt moves no wallet value',
          v_c1 = v_c0, v_c1::text);
    SELECT state::text INTO v_state FROM public.food_orders WHERE id=v_o1;
    r := r || public._qa_s13_ok('MC4.8 order is cancelled', v_state='cancelled', v_state);
    SELECT count(*) INTO v_n FROM public.missions
      WHERE ref_food_order_id=v_o1 AND state='assigned' AND courier_id IS NULL;
    r := r || public._qa_s13_ok('MC4.9 unclaimed delivery mission retired', v_n=0, v_n::text);
    v_res := public.repas_customer_cancel_order(v_o1, 'again');
    SELECT count(*) INTO v_n FROM public.customer_cancellation_debts
     WHERE source_module='repas' AND source_id=v_o1;
    r := r || public._qa_s13_ok('MC4.10 repeat cancellation is idempotent and never double-charges',
          (v_res->>'idempotent')::boolean AND v_n = 1, v_n::text);

    -- an unpaid cancellation fee must block new cash exposure (Slice 8 invariant)
    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item2,'qty',1)),
        'delivery','cash', gen_random_uuid(), 'Kaloum, Conakry', 9.5100, -13.7000);
    v_o5 := (v_res->>'order_id')::uuid;
    v_mission5 := (v_res->>'mission_id')::uuid;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    BEGIN PERFORM public.mission_claim(v_mission5); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('MC4.11 outstanding cancellation debt blocks new cash exposure',
          v_err LIKE '%CUSTOMER_CASH_RESTRICTED%', v_err);
    r := r || public._qa_s13_ok('MC4.12 blocked engagement created zero cash runtime',
          NOT EXISTS (SELECT 1 FROM public.cash_order_runtime
                       WHERE source_module='repas' AND source_id=v_o5), NULL);

    -- ============ B. R2 SECURITY ============
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
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust4), true);
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

    UPDATE public.feature_flags SET enabled = false WHERE key = 'cash_order_funding_enabled';
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    BEGIN PERFORM public.mission_claim(v_mission); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('C1.1 cash rail flag OFF fails closed at courier engagement',
          v_err <> 'NO_ERROR', v_err);
    r := r || public._qa_s13_ok('C1.2 flag OFF created zero cash runtime',
          NOT EXISTS (SELECT 1 FROM public.cash_order_runtime WHERE source_module='repas' AND source_id=v_o2), NULL);
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

    -- ============ E. R4 STATE MACHINE (cash) ============
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

    BEGIN PERFORM public.repas_merchant_transition(v_o2,'complete'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('E1.4 merchant may not hand-complete a funded rail',
          v_err LIKE '%COMPLETION_OWNED_BY_DELIVERY_ENGINE%', v_err);

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

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust4), true);
    BEGIN PERFORM public.repas_customer_cancel_order(v_o2,'change of mind'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('E4.1 customer cancel after preparing denied',
          v_err LIKE '%PREPARATION_LOCKED%' OR v_err LIKE '%PREPARATION%', v_err);
    SELECT state::text INTO v_state FROM public.food_orders WHERE id=v_o2;
    r := r || public._qa_s13_ok('E4.2 denied cancellation mutated nothing', v_state='preparing', v_state);
    SELECT count(*) INTO v_n FROM public.customer_cancellation_debts
     WHERE source_module='repas' AND source_id=v_o2;
    r := r || public._qa_s13_ok('E4.3 denied cancellation created no debt', v_n = 0, v_n::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    PERFORM public.repas_merchant_transition(v_o2,'ready');
    SELECT state::text INTO v_state FROM public.food_orders WHERE id=v_o2;
    r := r || public._qa_s13_ok('E3.2 ready transition legal after preparing', v_state='ready', v_state);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust4), true);
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
    SELECT count(*) INTO v_n FROM public.customer_cancellation_debts
     WHERE source_module='repas' AND source_id=v_o3;
    r := r || public._qa_s13_ok('E5.5 a merchant-caused reject charges the customer nothing',
          v_n = 0, v_n::text);

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

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust2), true);
    SELECT balance_gnf INTO v_c0 FROM public.wallets WHERE owner_user_id=v_cust2 AND party_type='client';
    v_res := public.repas_customer_cancel_order(v_o3, 'change of mind');
    SELECT held_gnf, balance_gnf INTO v_held, v_c1
      FROM public.wallets WHERE owner_user_id=v_cust2 AND party_type='client';
    r := r || public._qa_s13_ok('D4.1 Chop Pay cancellation releases the customer hold entirely',
          v_held = 0, v_held::text);
    r := r || public._qa_s13_ok('D4.2 Chop Pay cancellation charges no fee while the policy flag is OFF',
          v_c1 = v_c0, v_c1::text);
    SELECT count(*) INTO v_n FROM public.customer_cancellation_debts
     WHERE source_module='repas' AND source_id=v_o3;
    r := r || public._qa_s13_ok('D4.3 a Chop Pay cancellation never creates a cash debt row',
          v_n = 0, v_n::text);
    SELECT state::text INTO v_state FROM public.food_orders WHERE id=v_o3;
    r := r || public._qa_s13_ok('D4.4 cancelled Chop Pay order reaches cancelled state',
          v_state='cancelled', v_state);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust2), true);
    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item2,'qty',1)),
        'delivery','choppay', gen_random_uuid(), 'Matam, Conakry', 9.5300, -13.6800);
    v_o3 := (v_res->>'order_id')::uuid;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_res := public.repas_merchant_transition(v_o3,'reject','indisponible');
    SELECT state::text INTO v_state FROM public.food_orders WHERE id=v_o3;
    r := r || public._qa_s13_ok('E6.1 Chop Pay merchant reject cancels the order', v_state='cancelled', v_state);
    SELECT held_gnf INTO v_held FROM public.wallets WHERE owner_user_id=v_cust2 AND party_type='client';
    r := r || public._qa_s13_ok('E6.2 Chop Pay reject releases the customer hold (no orphan hold)',
          v_held = 0, v_held::text);

    -- ============ G. MC5 FULL POSITIVE CHOP PAY LIFECYCLE ============
    SELECT balance_gnf INTO v_c0 FROM public.wallets WHERE owner_user_id=v_cust3 AND party_type='client';
    SELECT balance_gnf INTO v_m0 FROM public.wallets WHERE owner_user_id=v_merch AND party_type='merchant';
    SELECT balance_gnf INTO v_d0 FROM public.wallets WHERE owner_user_id=v_drv2 AND party_type='driver';
    SELECT balance_gnf INTO v_x0 FROM public.wallets WHERE party_type='master' LIMIT 1;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust3), true);
    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(
          jsonb_build_object('menu_item_id',v_item,'qty',1),
          jsonb_build_object('menu_item_id',v_item2,'qty',1)),
        'delivery','choppay', gen_random_uuid(), 'Dixinn, Conakry', 9.5400, -13.6900);
    v_o4 := (v_res->>'order_id')::uuid;
    v_mission4 := (v_res->>'mission_id')::uuid;
    SELECT * INTO v_cp FROM public.chop_pay_order_runtime
      WHERE source_module='repas' AND source_id=v_o4;
    r := r || public._qa_s13_ok('G1.1 lifecycle order authorized for the full total (166 500 GNF)',
          v_cp.state='authorized' AND v_cp.order_total_gnf = 166500,
          COALESCE(v_cp.order_total_gnf,0)::text);
    r := r || public._qa_s13_ok('G1.2 platform fee is the 1% policy fee on merchandise',
          v_cp.platform_fee_gnf = 1500, v_cp.platform_fee_gnf::text);
    r := r || public._qa_s13_ok('G1.3 collateral frozen at 50% of merchandise at authorization',
          v_cp.collateral_gnf = 75000, v_cp.collateral_gnf::text);
    SELECT held_gnf INTO v_held FROM public.wallets WHERE owner_user_id=v_cust3 AND party_type='client';
    r := r || public._qa_s13_ok('G1.4 customer holds exactly the order total', v_held = 166500, v_held::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv2), true);
    PERFORM public.mission_claim(v_mission4);
    SELECT * INTO v_cp FROM public.chop_pay_order_runtime
      WHERE source_module='repas' AND source_id=v_o4;
    r := r || public._qa_s13_ok('G2.1 mission_claim drives the Slice 5 acceptance',
          v_cp.state='accepted' AND v_cp.driver_user_id = v_drv2, v_cp.state);
    SELECT COALESCE(SUM(amount_gnf),0), count(*) INTO v_col, v_n
      FROM public.mission_financial_holds
     WHERE source_module='repas' AND source_id=v_o4 AND kind='collateral';
    r := r || public._qa_s13_ok('G2.2 collateral placed exactly once at the frozen amount',
          v_col = 75000 AND v_n = 1, v_col::text||'/'||v_n::text);
    SELECT held_gnf INTO v_held FROM public.wallets WHERE owner_user_id=v_drv2 AND party_type='driver';
    r := r || public._qa_s13_ok('G2.3 driver wallet holds the collateral', v_held = 75000, v_held::text);
    SELECT * INTO v_pay FROM public.merchant_payables
     WHERE source_module='repas' AND source_id=v_o4;
    r := r || public._qa_s13_ok('G2.4 merchant payable created for the merchandise principal',
          v_pay.id IS NOT NULL AND v_pay.amount_gnf = 150000, COALESCE(v_pay.amount_gnf,0)::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    PERFORM public.repas_merchant_transition(v_o4,'accept');
    SELECT * INTO v_pay FROM public.merchant_payables
     WHERE source_module='repas' AND source_id=v_o4;
    r := r || public._qa_s13_ok('G3.1 merchant accept funds the payable in full',
          v_pay.funded_gnf = 150000, COALESCE(v_pay.funded_gnf,0)::text);
    SELECT balance_gnf INTO v_m1 FROM public.wallets WHERE owner_user_id=v_merch AND party_type='merchant';
    r := r || public._qa_s13_ok('G3.2 merchant credited exactly the merchandise subtotal',
          v_m1 - v_m0 = 150000, (v_m1 - v_m0)::text);
    SELECT held_gnf INTO v_held FROM public.wallets WHERE owner_user_id=v_cust3 AND party_type='client';
    r := r || public._qa_s13_ok('G3.3 customer hold reduced by the captured merchandise only',
          v_held = 16500, v_held::text);
    SELECT * INTO v_cp FROM public.chop_pay_order_runtime
      WHERE source_module='repas' AND source_id=v_o4;
    r := r || public._qa_s13_ok('G3.4 runtime reached merchant_accepted', v_cp.state='merchant_accepted', v_cp.state);

    PERFORM public.repas_merchant_transition(v_o4,'prepare');
    SELECT * INTO v_cp FROM public.chop_pay_order_runtime
      WHERE source_module='repas' AND source_id=v_o4;
    r := r || public._qa_s13_ok('G4.1 preparation locks the order on the Chop Pay engine',
          v_cp.state='preparing', v_cp.state);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust3), true);
    BEGIN PERFORM public.repas_customer_cancel_order(v_o4,'too late'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('G4.2 customer cannot cancel once preparation started',
          v_err LIKE '%PREPARATION%', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    PERFORM public.repas_merchant_transition(v_o4,'ready');
    PERFORM public.repas_merchant_transition(v_o4,'handoff');
    SELECT state::text INTO v_state FROM public.food_orders WHERE id=v_o4;
    r := r || public._qa_s13_ok('G4.3 order handed off to the courier', v_state='out_for_delivery', v_state);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv2), true);
    PERFORM public.mission_confirm_pickup(v_mission4);
    SELECT count(*) INTO v_n FROM public.missions
     WHERE id=v_mission4 AND pickup_confirmed_at IS NOT NULL AND state='picked_up';
    r := r || public._qa_s13_ok('G5.1 custody established through mission_confirm_pickup', v_n=1, v_n::text);

    PERFORM public.mission_confirm_dropoff(v_mission4);
    SELECT * INTO v_cp FROM public.chop_pay_order_runtime
      WHERE source_module='repas' AND source_id=v_o4;
    r := r || public._qa_s13_ok('G6.1 delivery confirmation completes the Chop Pay runtime',
          v_cp.state='completed', v_cp.state);
    r := r || public._qa_s13_ok('G6.2 settled driver earning equals the frozen delivery fee',
          v_cp.driver_earning_gnf = 15000, COALESCE(v_cp.driver_earning_gnf,0)::text);
    r := r || public._qa_s13_ok('G6.3 settled platform revenue equals the frozen fee',
          v_cp.platform_revenue_gnf = 1500, COALESCE(v_cp.platform_revenue_gnf,0)::text);
    r := r || public._qa_s13_ok('G6.4 settled merchant credit equals the merchandise subtotal',
          v_cp.merchant_credited_gnf = 150000, COALESCE(v_cp.merchant_credited_gnf,0)::text);
    SELECT state::text INTO v_state FROM public.food_orders WHERE id=v_o4;
    r := r || public._qa_s13_ok('G6.5 food order reaches completed', v_state='completed', v_state);
    SELECT state::text INTO v_state FROM public.missions WHERE id=v_mission4;
    r := r || public._qa_s13_ok('G6.6 mission reaches delivered', v_state='delivered', v_state);

    SELECT balance_gnf, held_gnf INTO v_c1, v_held
      FROM public.wallets WHERE owner_user_id=v_cust3 AND party_type='client';
    r := r || public._qa_s13_ok('G7.1 customer paid exactly the order total', v_c0 - v_c1 = 166500,
          (v_c0 - v_c1)::text);
    r := r || public._qa_s13_ok('G7.2 no customer value stays encumbered', v_held = 0, v_held::text);
    SELECT balance_gnf, held_gnf INTO v_d1, v_col
      FROM public.wallets WHERE owner_user_id=v_drv2 AND party_type='driver';
    r := r || public._qa_s13_ok('G7.3 driver earned exactly the delivery fee', v_d1 - v_d0 = 15000,
          (v_d1 - v_d0)::text);
    r := r || public._qa_s13_ok('G7.4 driver collateral fully released', v_col = 0, v_col::text);
    SELECT balance_gnf INTO v_m1 FROM public.wallets WHERE owner_user_id=v_merch AND party_type='merchant';
    r := r || public._qa_s13_ok('G7.5 merchant kept exactly the merchandise principal',
          v_m1 - v_m0 = 150000, (v_m1 - v_m0)::text);
    SELECT balance_gnf INTO v_x1 FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s13_ok('G7.6 platform captured exactly the transaction fee',
          v_x1 - v_x0 = 1500, (v_x1 - v_x0)::text);
    r := r || public._qa_s13_ok('G7.7 economics reconcile: customer out = merchant + driver + platform',
          (v_c0 - v_c1) = (v_m1 - v_m0) + (v_d1 - v_d0) + (v_x1 - v_x0),
          (v_c0 - v_c1)::text);
    SELECT COALESCE(SUM(GREATEST(amount_gnf - captured_gnf - released_gnf,0)),0) INTO v_open
      FROM public.mission_financial_holds WHERE source_module='repas' AND source_id=v_o4;
    r := r || public._qa_s13_ok('G7.8 zero residual open holds on the completed order', v_open = 0, v_open::text);

    SELECT balance_gnf INTO v_bal FROM public.wallets WHERE owner_user_id=v_drv2 AND party_type='driver';
    BEGIN PERFORM public.mission_confirm_dropoff(v_mission4); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    SELECT balance_gnf INTO v_d1 FROM public.wallets WHERE owner_user_id=v_drv2 AND party_type='driver';
    r := r || public._qa_s13_ok('G8.1 repeated delivery confirmation settles nothing extra',
          v_d1 = v_bal, v_d1::text||' err='||v_err);
    SELECT count(*) INTO v_n FROM public.ledger_journals
      WHERE source_module='repas' AND source_id=v_o4 AND journal_key LIKE 'cph-capture:%delivery';
    r := r || public._qa_s13_ok('G8.2 exactly one delivery capture journal', v_n = 1, v_n::text);

    -- ============ F. INVARIANTS ============
    SELECT count(*) INTO v_unbalanced FROM (
      SELECT j.id FROM public.ledger_journals j
        JOIN public.ledger_postings p ON p.journal_id = j.id
       WHERE j.created_at >= now() - interval '5 minutes'
       GROUP BY j.id HAVING sum(p.amount_gnf) <> 0
    ) z;
    r := r || public._qa_s13_ok('F1.1 every journal created by fixtures is zero-sum',
          v_unbalanced = 0, v_unbalanced::text);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_module='repas' AND (captured_gnf + released_gnf) > amount_gnf;
    r := r || public._qa_s13_ok('F1.2 no hold is over-consumed', v_n = 0, v_n::text);

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
  SELECT count(*) INTO v_n FROM public.customer_cancellation_debts d
    JOIN auth.users u ON u.id = d.customer_user_id WHERE u.email LIKE 'qa-s13-n3%';
  r := r || public._qa_s13_ok('Z3.7 no cancellation debt residue', v_n = 0, v_n::text);

  RETURN jsonb_build_object(
    'part','node3_repas_r1_r4',
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'results', r);
END; $function$;

REVOKE ALL ON FUNCTION public._qa_node3_repas_r1_r4() FROM PUBLIC, anon, authenticated;
