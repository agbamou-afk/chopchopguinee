CREATE OR REPLACE FUNCTION public._qa_node3_repas_r5_runtime()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_god uuid; v_cust uuid; v_cust2 uuid; v_merch uuid; v_drv uuid;
  v_store uuid; v_resto uuid; v_resto2 uuid; v_resto3 uuid;
  v_item uuid; v_item2 uuid; v_item_off uuid;
  v_pol0 public.finance_policies; v_polB public.finance_policies;
  v_q jsonb; v_res jsonb; v_err text; v_n int; v_promo uuid;
  v_o1 uuid; v_o2 uuid; v_o3 uuid; v_o4 uuid; v_m4 uuid; v_req uuid;
  v_snap1 jsonb; v_snap4 jsonb; v_rt4 jsonb;
  v_cp public.chop_pay_order_runtime; v_fo public.food_orders;
  v_master0 bigint; v_master1 bigint; v_flags0 jsonb; v_flags1 jsonb;
  v_c0 bigint; v_c1 bigint; v_m0 bigint; v_m1 bigint; v_d0 bigint; v_d1 bigint;
  v_x0 bigint; v_x1 bigint; v_held bigint; v_dist numeric; v_unbalanced int;
  v_orders_before int; v_open bigint;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;

  r := r || public._qa_s13_ok('R0.1 runtime harness is closed to anon and authenticated',
        NOT has_function_privilege('anon','public._qa_node3_repas_r5_runtime()','EXECUTE')
        AND NOT has_function_privilege('authenticated','public._qa_node3_repas_r5_runtime()','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('R0.2 quote preview closed to anon',
        NOT has_function_privilege('anon','public.repas_quote_preview(uuid,jsonb,text,double precision,double precision)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('R0.3 promotion admin RPC closed to anon',
        NOT has_function_privilege('anon','public.admin_set_repas_promotion(text,text,timestamptz,timestamptz,text,bigint,bigint)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('R0.4 courier subsidy primitive closed to authenticated',
        NOT has_function_privilege('authenticated',
          (SELECT oid FROM pg_proc WHERE proname='_chop_pay_courier_adjust_internal'), 'EXECUTE'), NULL);

  BEGIN
    -- ================= FIXTURES =================
    v_god := gen_random_uuid(); v_cust := gen_random_uuid(); v_cust2 := gen_random_uuid();
    v_merch := gen_random_uuid(); v_drv := gen_random_uuid();
    PERFORM public._qa_s13_user(v_god,'n3r5g');
    PERFORM public._qa_s13_user(v_cust,'n3r5c');
    PERFORM public._qa_s13_user(v_cust2,'n3r5x');
    PERFORM public._qa_s13_user(v_merch,'n3r5m');
    PERFORM public._qa_s13_user(v_drv,'n3r5d');
    PERFORM public._qa_s13_wallet(v_cust,'client',5000000,0);
    PERFORM public._qa_s13_wallet(v_cust2,'client',5000000,0);
    PERFORM public._qa_s13_wallet(v_merch,'merchant',0,0);
    PERFORM public._qa_s13_wallet(v_drv,'driver',900000,0);
    INSERT INTO public.user_roles(user_id, role) VALUES (v_god,'god_admin')
      ON CONFLICT DO NOTHING;
    INSERT INTO public.driver_profiles(user_id,status,vehicle_type,capabilities)
      VALUES (v_drv,'approved','livraison',ARRAY['repas_delivery'])
      ON CONFLICT (user_id) DO UPDATE SET status='approved', capabilities=ARRAY['repas_delivery'];

    INSERT INTO public.merchant_stores(owner_user_id, slug, name, delivery_available, status)
      VALUES (v_merch, 'qa-n3r5-store-'||substr(v_merch::text,1,8), 'QA R5 Store', true, 'active')
      RETURNING id INTO v_store;
    INSERT INTO public.food_restaurants(owner_user_id, merchant_store_id, slug, name, status,
        is_open, delivery_available, pickup_available, choppay_enabled, prep_time_min,
        latitude, longitude)
      VALUES (v_merch, v_store, 'qa-n3r5-resto-'||substr(v_merch::text,1,8), 'QA R5 Resto',
              'active', true, true, true, true, 20, 9.5350, -13.6800)
      RETURNING id INTO v_resto;
    -- unmapped restaurant: distance can never be verified
    INSERT INTO public.food_restaurants(owner_user_id, slug, name, status, is_open,
        delivery_available, pickup_available, choppay_enabled, prep_time_min)
      VALUES (v_merch, 'qa-n3r5-resto2-'||substr(v_merch::text,1,8), 'QA R5 Unmapped',
              'active', true, true, true, true, 20)
      RETURNING id INTO v_resto2;
    -- closed restaurant
    INSERT INTO public.food_restaurants(owner_user_id, slug, name, status, is_open,
        delivery_available, pickup_available, choppay_enabled, prep_time_min,
        latitude, longitude)
      VALUES (v_merch, 'qa-n3r5-resto3-'||substr(v_merch::text,1,8), 'QA R5 Closed',
              'active', false, true, true, true, 20, 9.5350, -13.6800)
      RETURNING id INTO v_resto3;

    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
      VALUES (v_resto,'QA R5 Plat A',100000,true) RETURNING id INTO v_item;
    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
      VALUES (v_resto,'QA R5 Plat B',50000,true) RETURNING id INTO v_item2;
    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
      VALUES (v_resto,'QA R5 Plat Indispo',7000,false) RETURNING id INTO v_item_off;

    UPDATE public.feature_flags SET enabled = true
      WHERE key IN ('chop_pay_checkout_enabled','chop_pay_enabled');

    SELECT * INTO v_pol0 FROM public.finance_policy_at('repas', now());

    -- ================= A. BASE POLICY DRIVES A REAL QUOTE + ORDER =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_q := public.repas_quote_preview(v_resto,
      jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1),
                        jsonb_build_object('menu_item_id',v_item2,'qty',1)),
      'delivery', 9.5100, -13.7000);
    r := r || public._qa_s13_ok('A1.1 quote merchandise is repriced from the catalogue',
          (v_q->>'merchandise_subtotal_gnf')::bigint = 150000, v_q->>'merchandise_subtotal_gnf');
    r := r || public._qa_s13_ok('A1.2 quote delivery price is the configured policy price',
          (v_q->>'base_delivery_fee_gnf')::bigint = v_pol0.delivery_flat_fee_gnf
          AND (v_q->>'delivery_fee_gnf')::bigint = v_pol0.delivery_flat_fee_gnf,
          v_q->>'delivery_fee_gnf');
    r := r || public._qa_s13_ok('A1.3 quote courier payout is the configured policy payout',
          (v_q->>'courier_payout_gnf')::bigint = v_pol0.courier_payout_gnf, v_q->>'courier_payout_gnf');
    r := r || public._qa_s13_ok('A1.4 quote is eligible with a server-verified geodesic distance',
          (v_q->>'delivery_eligible')::boolean AND (v_q->>'distance_verified')::boolean
          AND (v_q->>'delivery_distance_km')::numeric > 0
          AND v_q->>'distance_method' = 'geodesic_straight_line',
          v_q->>'delivery_distance_km');

    v_res := public.repas_order_create(v_resto,
      jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1),
                        jsonb_build_object('menu_item_id',v_item2,'qty',1)),
      'delivery','choppay', gen_random_uuid(), 'Kaloum, Conakry', 9.5100, -13.7000);
    v_o1 := (v_res->>'order_id')::uuid;
    SELECT * INTO v_fo FROM public.food_orders WHERE id = v_o1;
    r := r || public._qa_s13_ok('A2.1 committed order freezes the base policy delivery price',
          v_fo.base_delivery_fee_gnf = v_pol0.delivery_flat_fee_gnf
          AND v_fo.delivery_fee_gnf = v_pol0.delivery_flat_fee_gnf, v_fo.delivery_fee_gnf::text);
    r := r || public._qa_s13_ok('A2.2 committed order freezes the policy courier payout',
          v_fo.courier_payout_gnf = v_pol0.courier_payout_gnf, v_fo.courier_payout_gnf::text);
    r := r || public._qa_s13_ok('A2.3 committed order records the pricing policy version',
          v_fo.pricing_policy_id = v_pol0.id, COALESCE(v_fo.pricing_policy_id::text,'null'));
    r := r || public._qa_s13_ok('A2.4 committed order freezes the measured distance',
          v_fo.delivery_distance_km IS NOT NULL AND v_fo.delivery_distance_km > 0,
          COALESCE(v_fo.delivery_distance_km::text,'null'));
    SELECT estimated_earning_gnf INTO v_c1 FROM public.missions WHERE ref_food_order_id = v_o1;
    r := r || public._qa_s13_ok('A2.5 courier mission earning equals the policy payout (not a literal)',
          v_c1 = v_pol0.courier_payout_gnf, v_c1::text);
    v_snap1 := jsonb_build_object('base', v_fo.base_delivery_fee_gnf, 'cust', v_fo.delivery_fee_gnf,
      'payout', v_fo.courier_payout_gnf, 'fee', v_fo.platform_fee_gnf, 'total', v_fo.order_total_gnf,
      'policy', v_fo.pricing_policy_id);

    -- ================= B. A LATER POLICY CHANGES NEW PRICING ONLY =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    PERFORM public.admin_set_finance_policy(
      p_mission_type := 'repas', p_effective_from := now(),
      p_note := 'qa-r5 runtime policy B',
      p_delivery_flat_fee_gnf := 25000, p_courier_payout_gnf := 18000,
      p_transaction_fee_bps := 200, p_pickup_platform_fee_bps := 300,
      p_delivery_max_distance_km := 10);
    SELECT * INTO v_polB FROM public.finance_policy_at('repas', now());
    r := r || public._qa_s13_ok('B1.1 the new policy is the effective policy',
          v_polB.id <> v_pol0.id AND v_polB.delivery_flat_fee_gnf = 25000
          AND v_polB.courier_payout_gnf = 18000, v_polB.id::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_q := public.repas_quote_preview(v_resto,
      jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1),
                        jsonb_build_object('menu_item_id',v_item2,'qty',1)),
      'delivery', 9.5100, -13.7000);
    r := r || public._qa_s13_ok('B1.2 a NEW quote follows the new policy price',
          (v_q->>'delivery_fee_gnf')::bigint = 25000
          AND (v_q->>'courier_payout_gnf')::bigint = 18000, v_q->>'delivery_fee_gnf');
    r := r || public._qa_s13_ok('B1.3 a NEW quote applies the new 2% platform fee',
          (v_q->>'platform_fee_gnf')::bigint = 3000, v_q->>'platform_fee_gnf');

    SELECT * INTO v_fo FROM public.food_orders WHERE id = v_o1;
    r := r || public._qa_s13_ok('B2.1 the already committed order is NOT repriced',
          jsonb_build_object('base', v_fo.base_delivery_fee_gnf, 'cust', v_fo.delivery_fee_gnf,
            'payout', v_fo.courier_payout_gnf, 'fee', v_fo.platform_fee_gnf,
            'total', v_fo.order_total_gnf, 'policy', v_fo.pricing_policy_id) = v_snap1,
          v_fo.order_total_gnf::text);
    SELECT * INTO v_cp FROM public.chop_pay_order_runtime
      WHERE source_module='repas' AND source_id=v_o1;
    r := r || public._qa_s13_ok('B2.2 the committed Chop Pay runtime keeps the frozen delivery fee',
          v_cp.delivery_fee_gnf = (v_snap1->>'cust')::bigint, v_cp.delivery_fee_gnf::text);
    SELECT estimated_earning_gnf INTO v_c1 FROM public.missions WHERE ref_food_order_id = v_o1;
    r := r || public._qa_s13_ok('B2.3 the committed mission keeps the frozen courier payout',
          v_c1 = (v_snap1->>'payout')::bigint, v_c1::text);

    v_res := public.repas_order_create(v_resto,
      jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1),
                        jsonb_build_object('menu_item_id',v_item2,'qty',1)),
      'delivery','choppay', gen_random_uuid(), 'Kaloum, Conakry', 9.5100, -13.7000);
    v_o2 := (v_res->>'order_id')::uuid;
    SELECT * INTO v_fo FROM public.food_orders WHERE id = v_o2;
    r := r || public._qa_s13_ok('B3.1 a NEW order is committed at the new policy price',
          v_fo.delivery_fee_gnf = 25000 AND v_fo.courier_payout_gnf = 18000
          AND v_fo.pricing_policy_id = v_polB.id, v_fo.delivery_fee_gnf::text);
    r := r || public._qa_s13_ok('B3.2 delivery platform fee is policy-driven on a real order (2%)',
          v_fo.platform_fee_gnf = 3000 AND v_fo.order_total_gnf = 178000,
          v_fo.platform_fee_gnf::text);
    SELECT estimated_earning_gnf INTO v_c1 FROM public.missions WHERE ref_food_order_id = v_o2;
    r := r || public._qa_s13_ok('B3.3 the new mission carries the new policy courier payout',
          v_c1 = 18000, v_c1::text);

    -- ================= C. DISTANCE FAILS CLOSED, WITH ZERO VALUE =================
    SELECT count(*) INTO v_orders_before FROM public.food_orders WHERE user_id = v_cust2;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust2), true);
    v_q := public.repas_quote_preview(v_resto,
      jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
      'delivery', 10.2000, -13.7000);
    r := r || public._qa_s13_ok('C1.1 quote refuses an out-of-zone destination',
          (v_q->>'delivery_eligible')::boolean IS FALSE
          AND v_q->>'ineligible_reason' = 'OUTSIDE_DELIVERY_ZONE'
          AND (v_q->>'delivery_distance_km')::numeric > 10, v_q->>'delivery_distance_km');
    BEGIN PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'delivery','choppay', gen_random_uuid(), 'Loin', 10.2000, -13.7000); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('C1.2 commitment refuses an out-of-zone destination',
          v_err LIKE '%OUTSIDE_DELIVERY_ZONE%', v_err);

    v_q := public.repas_quote_preview(v_resto2,
      jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
      'delivery', 9.5100, -13.7000);
    r := r || public._qa_s13_ok('C2.1 quote refuses an unmapped restaurant under a configured zone',
          (v_q->>'delivery_eligible')::boolean IS FALSE
          AND (v_q->>'distance_verified')::boolean IS FALSE
          AND v_q->>'ineligible_reason' = 'DELIVERY_DISTANCE_UNVERIFIABLE', v_q::text);
    BEGIN PERFORM public.repas_order_create(v_resto2,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'delivery','choppay', gen_random_uuid(), 'Kaloum', 9.5100, -13.7000); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('C2.2 commitment refuses an unverifiable distance',
          v_err LIKE '%DELIVERY_DISTANCE_UNVERIFIABLE%' OR v_err LIKE '%ITEM_WRONG_RESTAURANT%', v_err);

    v_q := public.repas_quote_preview(v_resto,
      jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
      'delivery', NULL, NULL);
    r := r || public._qa_s13_ok('C3.1 quote refuses a destination-less delivery under a zone',
          (v_q->>'delivery_eligible')::boolean IS FALSE
          AND v_q->>'ineligible_reason' = 'DESTINATION_REQUIRED', v_q->>'ineligible_reason');
    BEGIN PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'delivery','choppay', gen_random_uuid(), 'Kaloum sans GPS', NULL, NULL); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('C3.2 commitment refuses a destination-less delivery under a zone',
          v_err LIKE '%DELIVERY_DISTANCE_UNVERIFIABLE%', v_err);

    SELECT count(*) INTO v_n FROM public.food_orders WHERE user_id = v_cust2;
    r := r || public._qa_s13_ok('C4.1 every distance refusal created zero orders',
          v_n = v_orders_before, v_n::text);
    SELECT count(*) INTO v_n FROM public.missions WHERE customer_id = v_cust2;
    r := r || public._qa_s13_ok('C4.2 every distance refusal created zero missions', v_n = 0, v_n::text);
    SELECT held_gnf, balance_gnf INTO v_held, v_c1
      FROM public.wallets WHERE owner_user_id=v_cust2 AND party_type='client';
    r := r || public._qa_s13_ok('C4.3 every distance refusal moved zero value',
          v_held = 0 AND v_c1 = 5000000, v_held::text||'/'||v_c1::text);

    -- ================= D. MENU + ORDERABILITY TRUTH =================
    BEGIN
      v_q := public.repas_quote_preview(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item_off,'qty',1)),
        'delivery', 9.5100, -13.7000);
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('D1.1 quote refuses an unavailable dish (canonical code)',
          v_err LIKE '%ITEM_UNAVAILABLE%', v_err);
    BEGIN PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item_off,'qty',1)),
        'delivery','choppay', gen_random_uuid(), 'Kaloum', 9.5100, -13.7000); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('D1.2 commitment refuses the same unavailable dish',
          v_err LIKE '%ITEM_UNAVAILABLE%', v_err);
    v_q := public.repas_quote_preview(v_resto3,
      jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
      'delivery', 9.5100, -13.7000);
    r := r || public._qa_s13_ok('D2.1 quote does not advertise a closed restaurant',
          (v_q->>'orderable')::boolean IS FALSE
          AND (v_q->>'restaurant_open')::boolean IS FALSE, v_q->>'ineligible_reason');
    UPDATE public.food_restaurants SET status='suspended' WHERE id = v_resto3;
    BEGIN
      v_q := public.repas_quote_preview(v_resto3,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)), 'delivery', 9.51, -13.70);
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('D2.2 quote refuses a non-active restaurant outright',
          v_err LIKE '%RESTAURANT_NOT_ORDERABLE%', v_err);

    -- ================= E. PICKUP KEEPS ITS OWN POLICY FEE (R4.5 INVARIANT) =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_res := public.repas_order_create(v_resto,
      jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1),
                        jsonb_build_object('menu_item_id',v_item2,'qty',1)),
      'pickup','choppay', gen_random_uuid());
    v_o3 := (v_res->>'order_id')::uuid;
    SELECT * INTO v_fo FROM public.food_orders WHERE id = v_o3;
    r := r || public._qa_s13_ok('E1.1 pickup platform fee is the policy pickup rate (3%)',
          v_fo.platform_fee_gnf = 4500, v_fo.platform_fee_gnf::text);
    r := r || public._qa_s13_ok('E1.2 pickup carries zero delivery price and zero courier payout',
          v_fo.delivery_fee_gnf = 0 AND v_fo.base_delivery_fee_gnf = 0
          AND v_fo.courier_payout_gnf = 0, v_fo.delivery_fee_gnf::text);
    SELECT count(*) INTO v_n FROM public.missions WHERE ref_food_order_id = v_o3;
    r := r || public._qa_s13_ok('E1.3 pickup creates no delivery mission', v_n = 0, v_n::text);
    r := r || public._qa_s13_ok('E1.4 pickup total = merchandise + pickup fee only',
          v_fo.order_total_gnf = 154500, v_fo.order_total_gnf::text);
    BEGIN PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'pickup','cash', gen_random_uuid()); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('E2.1 cash pickup still fails closed', v_err LIKE '%PICKUP_CASH_NOT_SUPPORTED%', v_err);

    -- ================= F. PROMOTION: CUSTOMER PRICE DOWN, COURIER PAY UNCHANGED =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    v_res := public.admin_set_repas_promotion('QA R5 Campagne','qa runtime campaign proof',
      now() - interval '1 minute', now() + interval '2 hours', 'delivery', NULL, 8000);
    v_promo := (v_res->>'promotion_id')::uuid;
    r := r || public._qa_s13_ok('F0.1 promotion created through the audited admin RPC',
          v_promo IS NOT NULL, COALESCE(v_promo::text,'null'));
    r := r || public._qa_s13_ok('F0.2 promotion creation is audited',
          EXISTS (SELECT 1 FROM public.audit_logs WHERE target_id = v_promo::text
                    AND action='repas_promotion.create'), NULL);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_q := public.repas_quote_preview(v_resto,
      jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1),
                        jsonb_build_object('menu_item_id',v_item2,'qty',1)),
      'delivery', 9.5100, -13.7000);
    r := r || public._qa_s13_ok('F1.1 promotion lowers only the customer delivery price',
          (v_q->>'base_delivery_fee_gnf')::bigint = 25000
          AND (v_q->>'delivery_fee_gnf')::bigint = 17000
          AND (v_q->>'promo_discount_gnf')::bigint = 8000, v_q->>'delivery_fee_gnf');
    r := r || public._qa_s13_ok('F1.2 promotion never reduces the courier payout',
          (v_q->>'courier_payout_gnf')::bigint = 18000, v_q->>'courier_payout_gnf');

    SELECT balance_gnf INTO v_c0 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    SELECT balance_gnf INTO v_m0 FROM public.wallets WHERE owner_user_id=v_merch AND party_type='merchant';
    SELECT balance_gnf INTO v_d0 FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    SELECT balance_gnf INTO v_x0 FROM public.wallets WHERE party_type='master' LIMIT 1;
    v_req := gen_random_uuid();
    v_res := public.repas_order_create(v_resto,
      jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1),
                        jsonb_build_object('menu_item_id',v_item2,'qty',1)),
      'delivery','choppay', v_req, 'Dixinn, Conakry', 9.5400, -13.6900);
    v_o4 := (v_res->>'order_id')::uuid;
    v_m4 := (v_res->>'mission_id')::uuid;
    SELECT * INTO v_fo FROM public.food_orders WHERE id = v_o4;
    r := r || public._qa_s13_ok('F2.1 promo order freezes base, customer price and discount distinctly',
          v_fo.base_delivery_fee_gnf = 25000 AND v_fo.delivery_fee_gnf = 17000
          AND v_fo.promo_discount_gnf = 8000, v_fo.delivery_fee_gnf::text);
    r := r || public._qa_s13_ok('F2.2 promo order freezes the promotion identity',
          v_fo.promotion_id = v_promo, COALESCE(v_fo.promotion_id::text,'null'));
    r := r || public._qa_s13_ok('F2.3 promo order freezes the full courier payout separately',
          v_fo.courier_payout_gnf = 18000, v_fo.courier_payout_gnf::text);
    r := r || public._qa_s13_ok('F2.4 customer total reflects the discounted price',
          v_fo.order_total_gnf = 170000, v_fo.order_total_gnf::text);
    v_snap4 := to_jsonb(v_fo) - 'updated_at' - 'state';
    SELECT * INTO v_cp FROM public.chop_pay_order_runtime WHERE source_module='repas' AND source_id=v_o4;
    v_rt4 := jsonb_build_object('total', v_cp.order_total_gnf, 'delivery', v_cp.delivery_fee_gnf,
                                'fee', v_cp.platform_fee_gnf);
    SELECT estimated_earning_gnf INTO v_c1 FROM public.missions WHERE id = v_m4;
    r := r || public._qa_s13_ok('F2.5 courier mission is funded at the full payout, not the customer price',
          v_c1 = 18000, v_c1::text);

    -- replay is inert
    v_res := public.repas_order_create(v_resto,
      jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1),
                        jsonb_build_object('menu_item_id',v_item2,'qty',1)),
      'delivery','choppay', v_req, 'Dixinn, Conakry', 9.5400, -13.6900);
    r := r || public._qa_s13_ok('F3.1 replay returns the same order',
          (v_res->>'order_id')::uuid = v_o4 AND (v_res->>'replay')::boolean, v_res->>'order_id');
    SELECT count(*) INTO v_n FROM public.missions WHERE ref_food_order_id = v_o4;
    r := r || public._qa_s13_ok('F3.2 replay created zero extra mission', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.chop_pay_order_runtime
      WHERE source_module='repas' AND source_id=v_o4;
    r := r || public._qa_s13_ok('F3.3 replay created zero extra Chop Pay runtime', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
      WHERE source_module='repas' AND source_id=v_o4;
    r := r || public._qa_s13_ok('F3.4 replay created zero extra hold', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.ledger_journals
      WHERE source_module='repas' AND source_id=v_o4;
    r := r || public._qa_s13_ok('F3.5 replay created zero extra journal', v_n = 1, v_n::text);

    -- cash cannot fund a subsidised delivery
    UPDATE public.feature_flags SET enabled = true WHERE key = 'cash_order_funding_enabled';
    BEGIN PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'delivery','cash', gen_random_uuid(), 'Kaloum', 9.5100, -13.7000); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('F4.1 cash refuses a delivery whose price differs from courier pay',
          v_err LIKE '%CASH_DELIVERY_PRICING_UNSUPPORTED%', v_err);
    UPDATE public.feature_flags SET enabled = false WHERE key = 'cash_order_funding_enabled';

    -- ================= G. FULL LIFECYCLE: SUBSIDY SETTLES AGAINST THE PLATFORM =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_claim(v_m4);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    PERFORM public.repas_merchant_transition(v_o4,'accept');
    PERFORM public.repas_merchant_transition(v_o4,'prepare');
    PERFORM public.repas_merchant_transition(v_o4,'ready');
    PERFORM public.repas_merchant_transition(v_o4,'handoff');
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    PERFORM public.mission_confirm_pickup(v_m4);
    PERFORM public.mission_confirm_dropoff(v_m4);

    SELECT * INTO v_cp FROM public.chop_pay_order_runtime WHERE source_module='repas' AND source_id=v_o4;
    r := r || public._qa_s13_ok('G1.1 promo order completes on the Chop Pay engine',
          v_cp.state='completed', v_cp.state);
    r := r || public._qa_s13_ok('G1.2 courier is settled the full frozen payout, not the discounted price',
          v_cp.driver_earning_gnf = 18000, COALESCE(v_cp.driver_earning_gnf,0)::text);
    SELECT balance_gnf INTO v_c1 FROM public.wallets WHERE owner_user_id=v_cust AND party_type='client';
    SELECT balance_gnf INTO v_m1 FROM public.wallets WHERE owner_user_id=v_merch AND party_type='merchant';
    SELECT balance_gnf, held_gnf INTO v_d1, v_held FROM public.wallets WHERE owner_user_id=v_drv AND party_type='driver';
    SELECT balance_gnf INTO v_x1 FROM public.wallets WHERE party_type='master' LIMIT 1;
    r := r || public._qa_s13_ok('G2.1 customer paid exactly the discounted total',
          v_c0 - v_c1 = 170000, (v_c0 - v_c1)::text);
    r := r || public._qa_s13_ok('G2.2 merchant kept exactly the merchandise principal',
          v_m1 - v_m0 = 150000, (v_m1 - v_m0)::text);
    r := r || public._qa_s13_ok('G2.3 driver earned the full policy courier payout',
          v_d1 - v_d0 = 18000, (v_d1 - v_d0)::text);
    r := r || public._qa_s13_ok('G2.4 platform absorbed the promotion subsidy out of its own fee',
          v_x1 - v_x0 = 2000, (v_x1 - v_x0)::text);
    r := r || public._qa_s13_ok('G2.5 economics reconcile: customer out = merchant + driver + platform',
          (v_c0 - v_c1) = (v_m1 - v_m0) + (v_d1 - v_d0) + (v_x1 - v_x0), (v_c0-v_c1)::text);
    r := r || public._qa_s13_ok('G2.6 driver collateral fully released', v_held = 0, v_held::text);
    SELECT COALESCE(SUM(GREATEST(amount_gnf - captured_gnf - released_gnf,0)),0) INTO v_open
      FROM public.mission_financial_holds WHERE source_module='repas' AND source_id=v_o4;
    r := r || public._qa_s13_ok('G2.7 zero residual open holds on the completed promo order',
          v_open = 0, v_open::text);

    -- ================= H. POST-COMMITMENT POLICY CHANGE IS INERT =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    PERFORM public.admin_set_finance_policy(
      p_mission_type := 'repas', p_effective_from := now() + interval '1 second',
      p_note := 'qa-r5 runtime policy C', p_delivery_flat_fee_gnf := 40000,
      p_courier_payout_gnf := 30000, p_transaction_fee_bps := 500);
    SELECT * INTO v_fo FROM public.food_orders WHERE id = v_o4;
    r := r || public._qa_s13_ok('H1.1 a later policy cannot mutate the frozen order economics',
          (to_jsonb(v_fo) - 'updated_at' - 'state') = v_snap4, v_fo.order_total_gnf::text);
    SELECT * INTO v_cp FROM public.chop_pay_order_runtime WHERE source_module='repas' AND source_id=v_o4;
    r := r || public._qa_s13_ok('H1.2 a later policy cannot mutate the settled receipt economics',
          jsonb_build_object('total', v_cp.order_total_gnf, 'delivery', v_cp.delivery_fee_gnf,
                             'fee', v_cp.platform_fee_gnf) = v_rt4, v_cp.order_total_gnf::text);
    r := r || public._qa_s13_ok('H1.3 the settled courier earning stays at the frozen payout',
          v_cp.driver_earning_gnf = 18000, COALESCE(v_cp.driver_earning_gnf,0)::text);

    -- ================= I. ADMIN AUTHORITY + FAIL-CLOSED VALUES =================
    BEGIN PERFORM public.admin_set_finance_policy('repas', p_effective_from := now() + interval '2 minutes',
      p_note := 'qa negative fee', p_delivery_flat_fee_gnf := -1); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('I1.1 negative delivery price refused', v_err LIKE '%INVALID_DELIVERY_FLAT_FEE%', v_err);
    BEGIN PERFORM public.admin_set_finance_policy('repas', p_effective_from := now() + interval '2 minutes',
      p_note := 'qa negative payout', p_courier_payout_gnf := -1); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('I1.2 negative courier payout refused', v_err LIKE '%INVALID_COURIER_PAYOUT%', v_err);
    BEGIN PERFORM public.admin_set_finance_policy('repas', p_effective_from := now() + interval '2 minutes',
      p_note := 'qa zero distance', p_delivery_max_distance_km := 0); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('I1.3 non-positive max distance refused', v_err LIKE '%INVALID_DELIVERY_MAX_DISTANCE%', v_err);
    BEGIN PERFORM public.admin_set_finance_policy('repas', p_effective_from := now() + interval '2 minutes',
      p_note := 'qa bad pickup bps', p_pickup_platform_fee_bps := 20000); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('I1.4 out-of-range pickup fee refused', v_err LIKE '%INVALID_PICKUP_FEE_BPS%', v_err);
    BEGIN PERFORM public.admin_set_finance_policy('repas', p_effective_from := now() + interval '2 minutes',
      p_note := 'x', p_delivery_flat_fee_gnf := 1000); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('I1.5 a price change without a reason is refused', v_err LIKE '%REASON_REQUIRED%', v_err);
    BEGIN PERFORM public.admin_set_finance_policy('repas', p_effective_from := now() - interval '1 day',
      p_note := 'qa backdate attempt', p_delivery_flat_fee_gnf := 1000); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('I1.6 backdated pricing refused', v_err LIKE '%BACKDATING_REJECTED%', v_err);

    BEGIN PERFORM public.admin_set_repas_promotion('QA pickup promo','qa scope proof',
      now(), now() + interval '1 hour', 'pickup', NULL, 1000); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('I2.1 a pickup-scope promotion is refused instead of doing nothing',
          v_err LIKE '%INVALID_FULFILLMENT_SCOPE%', v_err);
    BEGIN PERFORM public.admin_set_repas_promotion('QA both promo','qa scope proof',
      now(), now() + interval '1 hour', 'both', NULL, 1000); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('I2.2 a both-scope promotion is refused', v_err LIKE '%INVALID_FULFILLMENT_SCOPE%', v_err);
    BEGIN INSERT INTO public.repas_pricing_promotions(name,reason,fulfillment_scope,
        delivery_discount_gnf,starts_at,ends_at)
      VALUES ('QA raw pickup','qa constraint proof','pickup',1000,now(),now()+interval '1 hour');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('I2.3 the table itself refuses a non-delivery scope', v_err <> 'NO_ERROR', v_err);
    BEGIN PERFORM public.admin_set_repas_promotion('QA overlap','qa overlap proof',
      now(), now() + interval '1 hour', 'delivery', NULL, 1000); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('I2.4 overlapping campaigns refused', v_err LIKE '%PROMO_WINDOW_OVERLAP%', v_err);
    BEGIN PERFORM public.admin_set_repas_promotion('QA expired','qa expiry proof',
      now() - interval '2 hours', now() - interval '1 hour', 'delivery', NULL, 1000); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('I2.5 an already expired campaign is refused', v_err LIKE '%PROMO_ALREADY_EXPIRED%', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    BEGIN PERFORM public.admin_set_finance_policy('repas', p_effective_from := now() + interval '5 minutes',
      p_note := 'qa unauthorized attempt', p_delivery_flat_fee_gnf := 1); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('I3.1 a normal customer cannot change Repas pricing',
          v_err LIKE '%God Admin%', v_err);
    BEGIN PERFORM public.admin_set_repas_promotion('QA hack','qa unauthorized promo',
      now(), now() + interval '1 hour', 'delivery', NULL, 1000); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('I3.2 a normal customer cannot create a campaign',
          v_err LIKE '%God Admin%', v_err);
    BEGIN PERFORM public.admin_disable_repas_promotion(v_promo, 'qa unauthorized disable'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('I3.3 a normal customer cannot stop a campaign',
          v_err LIKE '%God Admin%', v_err);

    -- ================= J. PROMOTION EXPIRY / SCHEDULING ON REAL PRICING =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    PERFORM public.admin_disable_repas_promotion(v_promo, 'qa runtime closeout of the campaign');
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_q := public.repas_quote_preview(v_resto,
      jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)), 'delivery', 9.5100, -13.7000);
    r := r || public._qa_s13_ok('J1.1 stopping a campaign restores the base price with no admin repricing',
          (v_q->>'delivery_fee_gnf')::bigint = 25000 AND v_q->>'promotion_id' IS NULL,
          v_q->>'delivery_fee_gnf');
    r := r || public._qa_s13_ok('J1.2 a campaign expires on its own clock',
          ((public.repas_pricing_effective('delivery', now() + interval '3 hours'))->>'promotion_id') IS NULL,
          'auto-expiry');

    -- ================= K. INVARIANTS =================
    SELECT count(*) INTO v_unbalanced FROM (
      SELECT j.id FROM public.ledger_journals j
        JOIN public.ledger_postings p ON p.journal_id = j.id
       WHERE j.source_module='repas' AND j.source_id IN (v_o1,v_o2,v_o3,v_o4)
       GROUP BY j.id HAVING SUM(p.amount_gnf) <> 0) z;
    r := r || public._qa_s13_ok('K1.1 every journal created here is zero-sum', v_unbalanced = 0, v_unbalanced::text);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_module='repas' AND source_id IN (v_o1,v_o2,v_o3,v_o4)
       AND (captured_gnf + released_gnf) > amount_gnf;
    r := r || public._qa_s13_ok('K1.2 no hold is over-consumed', v_n = 0, v_n::text);

    PERFORM set_config('request.jwt.claims', ''::text, true);
    RAISE EXCEPTION 'QA_NODE3_R5_RUNTIME_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_NODE3_R5_RUNTIME_ROLLBACK' THEN
      r := r || public._qa_s13_ok('HARNESS aborted before completion', false, SQLERRM);
    END IF;
  END;

  PERFORM set_config('request.jwt.claims', ''::text, true);
  SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;
  r := r || public._qa_s13_ok('Z5.1 master wallet unchanged after fixture rollback',
        v_master0 IS NOT DISTINCT FROM v_master1, v_master1::text);
  r := r || public._qa_s13_ok('Z5.2 feature flags byte-identical after fixture rollback',
        v_flags0 = v_flags1, NULL);
  SELECT count(*) INTO v_n FROM public.food_restaurants WHERE slug LIKE 'qa-n3r5-%';
  r := r || public._qa_s13_ok('Z5.3 no restaurant fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.finance_policies WHERE note LIKE 'qa-r5%';
  r := r || public._qa_s13_ok('Z5.4 no policy fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.repas_pricing_promotions WHERE name LIKE 'QA R5%';
  r := r || public._qa_s13_ok('Z5.5 no promotion fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.food_orders WHERE restaurant_id NOT IN
    (SELECT id FROM public.food_restaurants);
  r := r || public._qa_s13_ok('Z5.6 no orphan order residue', v_n = 0, v_n::text);

  RETURN jsonb_build_object('part','node3_repas_r5_runtime',
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'results', r);
END; $function$;

REVOKE ALL ON FUNCTION public._qa_node3_repas_r5_runtime() FROM PUBLIC, anon, authenticated;