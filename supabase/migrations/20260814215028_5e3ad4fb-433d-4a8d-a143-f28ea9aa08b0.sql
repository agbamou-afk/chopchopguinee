CREATE OR REPLACE FUNCTION public._qa_node3_repas_r11_conakry_hardening_fxcore()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_cust uuid; v_merch uuid; v_drv uuid; v_god uuid;
  v_store uuid; v_resto uuid; v_item uuid; v_item2 uuid;
  v_oDel uuid; v_oPick uuid; v_oRep uuid;
  v_res jsonb; v_res2 jsonb; v_t jsonb; v_d jsonb; v_err text; v_def text;
  v_n int; v_n2 int; v_rq uuid; v_rq2 uuid;
  v_row public.food_orders%ROWTYPE;
  v_master0 bigint; v_master1 bigint; v_flags0 jsonb; v_flags1 jsonb;
  v_upd timestamptz; v_upd2 timestamptz;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;

  -- ================= P0 · STRUCTURAL / PRIVILEGE TRUTH =================
  r := r || public._qa_s13_ok('P0.1 the destination snapshot columns exist',
        (SELECT count(*) FROM information_schema.columns
          WHERE table_schema='public' AND table_name='food_orders'
            AND column_name IN ('delivery_landmark','delivery_instructions',
                                'delivery_location_source','delivery_location_quality')) = 4, NULL);
  r := r || public._qa_s13_ok('P0.2 a trigger freezes the committed destination',
        (SELECT count(*) FROM pg_trigger WHERE tgrelid='public.food_orders'::regclass
          AND tgname='trg_repas_destination_immutable' AND NOT tgisinternal) = 1, NULL);
  r := r || public._qa_s13_ok('P0.3 the quality helper is immutable and pinned',
        (SELECT provolatile='i' AND proconfig @> ARRAY['search_path=public'] FROM pg_proc
          WHERE proname='_repas_location_quality'), NULL);
  r := r || public._qa_s13_ok('P0.4 anon cannot execute order creation',
        NOT has_function_privilege('anon',
          'public.repas_order_create(uuid,jsonb,text,text,uuid,text,double precision,double precision,text,text,text,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('P0.5 anon cannot execute the recovery resume',
        NOT has_function_privilege('anon','public.repas_order_resume(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('P0.6 anon cannot execute order tracking',
        NOT has_function_privilege('anon','public.repas_order_tracking(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('P0.7 there is exactly one order-create signature (no ambiguous overload)',
        (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
          WHERE n.nspname='public' AND p.proname='repas_order_create') = 1, NULL);
  r := r || public._qa_s13_ok('P0.8 resume stays read-only (non-volatile)',
        (SELECT provolatile FROM pg_proc WHERE proname='repas_order_resume') = 's', NULL);
  r := r || public._qa_s13_ok('P0.9 tracking stays read-only (non-volatile)',
        (SELECT provolatile FROM pg_proc WHERE proname='repas_order_tracking') = 's', NULL);
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc WHERE proname='repas_order_create';
  r := r || public._qa_s13_ok('P0.10 no street address is ever synthesised from coordinates',
        v_def NOT LIKE '%Position actuelle%' AND v_def NOT LIKE '%geocode%', NULL);
  r := r || public._qa_s13_ok('P0.11 the fail-closed distance guard is still present',
        v_def LIKE '%DELIVERY_DISTANCE_UNVERIFIABLE%' AND v_def LIKE '%OUTSIDE_DELIVERY_ZONE%', NULL);
  r := r || public._qa_s13_ok('P0.12 the destination is part of the idempotency fingerprint',
        v_def LIKE '%COALESCE(v_land%' AND v_def LIKE '%COALESCE(v_instr%', NULL);
  r := r || public._qa_s13_ok('P0.13 quality is server-derived, never taken from the client',
        v_def LIKE '%public._repas_location_quality(%', NULL);
  r := r || public._qa_s13_ok('P0.14 this harness is closed to anon and authenticated',
        NOT has_function_privilege('anon','public._qa_node3_repas_r11_conakry_hardening()','EXECUTE')
    AND NOT has_function_privilege('authenticated','public._qa_node3_repas_r11_conakry_hardening()','EXECUTE'), NULL);

  r := r || public._qa_s13_ok('P1.1 gps coordinates derive gps_verified',
        public._repas_location_quality('gps', 9.53, -13.67, 'Kipe', NULL) = 'gps_verified', NULL);
  r := r || public._qa_s13_ok('P1.2 a dragged pin derives manually_placed',
        public._repas_location_quality('manual_pin', 9.53, -13.67, NULL, NULL) = 'manually_placed', NULL);
  r := r || public._qa_s13_ok('P1.3 an unspecified source with coordinates stays approximate',
        public._repas_location_quality('unspecified', 9.53, -13.67, NULL, NULL) = 'approximate', NULL);
  r := r || public._qa_s13_ok('P1.4 a landmark without coordinates is landmark_assisted',
        public._repas_location_quality('typed', NULL, NULL, NULL, 'pres de Prima Center') = 'landmark_assisted', NULL);
  r := r || public._qa_s13_ok('P1.5 nothing at all is unverifiable, never "verified"',
        public._repas_location_quality('none', NULL, NULL, NULL, NULL) = 'unverifiable', NULL);
  r := r || public._qa_s13_ok('P1.6 a missing longitude cannot claim verification',
        public._repas_location_quality('gps', 9.53, NULL, 'Kipe', NULL) = 'landmark_assisted', NULL);

  BEGIN
    v_cust := gen_random_uuid(); v_merch := gen_random_uuid();
    v_drv := gen_random_uuid(); v_god := gen_random_uuid();
    PERFORM public._qa_s13_user(v_cust,'n3r11c');
    PERFORM public._qa_s13_user(v_merch,'n3r11m');
    PERFORM public._qa_s13_user(v_drv,'n3r11d');
    PERFORM public._qa_s13_user(v_god,'n3r11g');
    PERFORM public._qa_s13_wallet(v_cust,'client',9000000,0);
    PERFORM public._qa_s13_wallet(v_merch,'merchant',0,0);
    PERFORM public._qa_s13_wallet(v_drv,'driver',900000,0);
    PERFORM public._qa_s13_admin(v_god);
    INSERT INTO public.admin_users(user_id, admin_role, status)
      VALUES (v_god,'god_admin','active')
      ON CONFLICT (user_id) DO UPDATE SET admin_role='god_admin', status='active';
    INSERT INTO public.user_roles(user_id, role) VALUES (v_god,'god_admin') ON CONFLICT DO NOTHING;

    INSERT INTO public.merchant_stores(owner_user_id, slug, name, delivery_available, status)
      VALUES (v_merch, 'qa-n3r11-store-'||substr(v_merch::text,1,8), 'QA N3R11 Store', true, 'active')
      RETURNING id INTO v_store;
    INSERT INTO public.food_restaurants(owner_user_id, merchant_store_id, slug, name, status,
        is_open, delivery_available, pickup_available, choppay_enabled, prep_time_min,
        latitude, longitude, district)
      VALUES (v_merch, v_store, 'qa-n3r11-resto-'||substr(v_merch::text,1,8), 'QA N3R11 Resto',
              'active', true, true, true, true, 20, 9.5370, -13.6785, 'Kipe')
      RETURNING id INTO v_resto;
    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
      VALUES (v_resto,'QA R11 Plat A',100000,true) RETURNING id INTO v_item;
    INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
      VALUES (v_resto,'QA R11 Plat B',50000,true) RETURNING id INTO v_item2;
    UPDATE public.feature_flags SET enabled = true WHERE key = 'chop_pay_checkout_enabled';

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);

    -- ================= A · CONAKRY DESTINATION TRUTH =================
    v_rq := gen_random_uuid();
    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'delivery','choppay', v_rq,
        'Kipe', 9.5395, -13.6760, 'Sans piment',
        'pres de Prima Center', 'portail bleu derriere la pharmacie', 'gps');
    v_oDel := (v_res->>'order_id')::uuid;
    SELECT * INTO v_row FROM public.food_orders WHERE id = v_oDel;
    r := r || public._qa_s13_ok('A1.1 a pin + label + landmark + instructions order commits',
          v_oDel IS NOT NULL AND v_row.state::text = 'placed', v_res->>'state');
    r := r || public._qa_s13_ok('A1.2 the human place label is stored verbatim',
          v_row.delivery_address = 'Kipe', v_row.delivery_address);
    r := r || public._qa_s13_ok('A1.3 the landmark is a first-class stored field',
          v_row.delivery_landmark = 'pres de Prima Center', v_row.delivery_landmark);
    r := r || public._qa_s13_ok('A1.4 the delivery instructions are stored',
          v_row.delivery_instructions = 'portail bleu derriere la pharmacie', v_row.delivery_instructions);
    r := r || public._qa_s13_ok('A1.5 the location source is recorded as gps',
          v_row.delivery_location_source = 'gps', v_row.delivery_location_source);
    r := r || public._qa_s13_ok('A1.6 the server derives gps_verified quality',
          v_row.delivery_location_quality = 'gps_verified', v_row.delivery_location_quality);
    r := r || public._qa_s13_ok('A1.7 no formal street address was fabricated from the pin',
          v_row.delivery_address NOT LIKE '%9.53%' AND v_row.delivery_address NOT LIKE '%-13.6%',
          v_row.delivery_address);
    r := r || public._qa_s13_ok('A1.8 the courier mission inherits the destination snapshot',
          (SELECT dropoff_address = 'Kipe' AND dropoff_lat IS NOT NULL
             FROM public.missions WHERE ref_food_order_id = v_oDel), NULL);
    r := r || public._qa_s13_ok('A1.9 the server-verified distance was computed',
          v_row.delivery_distance_km IS NOT NULL, v_row.delivery_distance_km::text);

    v_res2 := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item2,'qty',1)),
        'delivery','choppay', gen_random_uuid(),
        'Lambanyi', 9.5400, -13.6700, NULL, 'face au marche', NULL, 'satellite_grade_truth');
    SELECT * INTO v_row FROM public.food_orders WHERE id = (v_res2->>'order_id')::uuid;
    r := r || public._qa_s13_ok('A2.1 an unknown client-declared source degrades to unspecified',
          v_row.delivery_location_source = 'unspecified', v_row.delivery_location_source);
    r := r || public._qa_s13_ok('A2.2 an unknown source can never be gps_verified',
          v_row.delivery_location_quality = 'approximate', v_row.delivery_location_quality);

    v_res2 := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item2,'qty',1)),
        'delivery','choppay', gen_random_uuid(),
        'Ratoma', 9.5410, -13.6750, NULL, 'derriere la mosquee', 'appeler en arrivant', 'manual_pin');
    SELECT * INTO v_row FROM public.food_orders WHERE id = (v_res2->>'order_id')::uuid;
    r := r || public._qa_s13_ok('A2.3 a manually dropped pin is labelled manually_placed',
          v_row.delivery_location_quality = 'manually_placed', v_row.delivery_location_quality);

    -- ================= B · SNAPSHOT IS FROZEN =================
    BEGIN
      UPDATE public.food_orders SET delivery_address = 'Autre quartier' WHERE id = v_oDel;
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B1.1 the committed place label cannot be rewritten',
          v_err LIKE '%REPAS_DESTINATION_IMMUTABLE%', v_err);
    BEGIN
      UPDATE public.food_orders SET delivery_landmark = 'ailleurs' WHERE id = v_oDel;
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B1.2 the committed landmark cannot be rewritten',
          v_err LIKE '%REPAS_DESTINATION_IMMUTABLE%', v_err);
    BEGIN
      UPDATE public.food_orders SET delivery_lat = 1.0, delivery_lng = 1.0 WHERE id = v_oDel;
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B1.3 the committed coordinates cannot be rewritten',
          v_err LIKE '%REPAS_DESTINATION_IMMUTABLE%', v_err);
    BEGIN
      UPDATE public.food_orders SET delivery_location_quality = 'gps_verified'
       WHERE id = (v_res2->>'order_id')::uuid;
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('B1.4 nobody can upgrade a location-quality verdict after the fact',
          v_err LIKE '%REPAS_DESTINATION_IMMUTABLE%', v_err);
    UPDATE public.food_orders SET updated_at = now() WHERE id = v_oDel;
    r := r || public._qa_s13_ok('B1.5 lifecycle updates that leave the destination alone still work',
          (SELECT delivery_address FROM public.food_orders WHERE id = v_oDel) = 'Kipe', NULL);
    r := r || public._qa_s13_ok('B1.6 a saved place is never linked, so it cannot mutate an order',
          (SELECT count(*) FROM information_schema.columns
            WHERE table_schema='public' AND table_name='food_orders'
              AND column_name LIKE '%saved_place%') = 0, NULL);

    -- ================= C · FAIL-CLOSED LOCATION POLICY (R5 PRESERVED) ==========
    BEGIN
      PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'delivery','choppay', gen_random_uuid(),
        'Quelque part', NULL, NULL, NULL, 'pres du grand fromager', NULL, 'typed');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('C1.1 distance-required + no coordinates fails closed',
          v_err LIKE '%DELIVERY_DISTANCE_UNVERIFIABLE%', v_err);
    BEGIN
      PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'delivery','choppay', gen_random_uuid(),
        'Tres loin', 10.9000, -12.2000, NULL, NULL, NULL, 'gps');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('C1.2 a destination outside the zone is refused canonically',
          v_err LIKE '%OUTSIDE_DELIVERY_ZONE%', v_err);
    BEGIN
      PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'delivery','choppay', gen_random_uuid(),
        NULL, NULL, NULL, NULL, NULL, NULL, NULL);
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('C1.3 a delivery with no destination at all is refused',
          v_err LIKE '%DELIVERY_LOCATION_REQUIRED%' OR v_err LIKE '%DELIVERY_DISTANCE_UNVERIFIABLE%', v_err);
    SELECT count(*) INTO v_n FROM public.food_orders o
     WHERE o.restaurant_id = v_resto AND o.delivery_location_quality = 'unverifiable';
    r := r || public._qa_s13_ok('C1.4 no unverifiable destination was ever committed', v_n = 0, v_n::text);

    -- ================= D · RETRAIT ISOLATION =================
    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item2,'qty',2)),
        'pickup','choppay', gen_random_uuid());
    v_oPick := (v_res->>'order_id')::uuid;
    SELECT * INTO v_row FROM public.food_orders WHERE id = v_oPick;
    r := r || public._qa_s13_ok('D1.1 pickup commits with no destination argument at all',
          v_oPick IS NOT NULL, v_res->>'state');
    r := r || public._qa_s13_ok('D1.2 pickup stores no delivery coordinates',
          v_row.delivery_lat IS NULL AND v_row.delivery_lng IS NULL, NULL);
    r := r || public._qa_s13_ok('D1.3 pickup stores no delivery address or landmark',
          v_row.delivery_address IS NULL AND v_row.delivery_landmark IS NULL, NULL);
    r := r || public._qa_s13_ok('D1.4 pickup carries no location-quality verdict',
          v_row.delivery_location_quality IS NULL AND v_row.delivery_location_source IS NULL, NULL);
    r := r || public._qa_s13_ok('D1.5 pickup creates no courier mission',
          (SELECT count(*) FROM public.missions WHERE ref_food_order_id = v_oPick) = 0, NULL);
    r := r || public._qa_s13_ok('D1.6 pickup pays no courier',
          COALESCE(v_row.courier_payout_gnf,0) = 0, v_row.courier_payout_gnf::text);
    r := r || public._qa_s13_ok('D1.7 pickup charges no delivery fee',
          COALESCE(v_row.delivery_fee_gnf,0) = 0, v_row.delivery_fee_gnf::text);
    r := r || public._qa_s13_ok('D1.8 pickup economics stay subtotal + platform fee',
          v_row.order_total_gnf = v_row.subtotal_gnf + COALESCE(v_row.platform_fee_gnf,0),
          v_row.order_total_gnf::text);
    r := r || public._qa_s13_ok('D1.9 the pickup platform fee is the unchanged 1% design',
          v_row.platform_fee_gnf = public.repas_platform_fee_gnf(v_row.subtotal_gnf, 0,
              v_row.pricing_snapshot->>'fee_basis',
              (v_row.pricing_snapshot->>'platform_fee_bps')::int),
          v_row.platform_fee_gnf::text);
    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item2,'qty',1)),
        'pickup','choppay', gen_random_uuid(),
        'Kipe', 9.5395, -13.6760, NULL, 'un repere', 'des instructions', 'gps');
    SELECT * INTO v_row FROM public.food_orders WHERE id = (v_res->>'order_id')::uuid;
    r := r || public._qa_s13_ok('D2.1 a destination sent with a pickup order is discarded',
          v_row.delivery_address IS NULL AND v_row.delivery_lat IS NULL
      AND v_row.delivery_landmark IS NULL AND v_row.delivery_instructions IS NULL, NULL);
    r := r || public._qa_s13_ok('D2.2 pickup with a stray destination still creates no mission',
          (SELECT count(*) FROM public.missions
            WHERE ref_food_order_id = (v_res->>'order_id')::uuid) = 0, NULL);
    v_t := public.repas_order_tracking(v_oPick);
    r := r || public._qa_s13_ok('D2.3 pickup tracking exposes no destination block',
          v_t->'destination' = 'null'::jsonb OR v_t->>'destination' IS NULL, v_t->>'destination');

    -- ================= E · STALE CACHE CANNOT COMMIT =================
    UPDATE public.food_menu_items SET is_available = false WHERE id = v_item2;
    BEGIN
      PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item2,'qty',1)),
        'delivery','choppay', gen_random_uuid(), 'Kipe', 9.5395, -13.6760, NULL, NULL, NULL, 'gps');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('E1.1 a dish cached as available but now unavailable is refused',
          v_err LIKE '%ITEM_UNAVAILABLE%', v_err);
    UPDATE public.food_menu_items SET is_available = true WHERE id = v_item2;

    UPDATE public.food_menu_items SET price_gnf = 175000 WHERE id = v_item;
    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'delivery','choppay', gen_random_uuid(), 'Kipe', 9.5395, -13.6760, NULL, NULL, NULL, 'gps');
    r := r || public._qa_s13_ok('E1.2 a stale cached price loses to the fresh server price',
          (v_res->>'subtotal_gnf')::bigint = 175000, v_res->>'subtotal_gnf');
    r := r || public._qa_s13_ok('E1.3 the stored line snapshot uses the fresh price',
          (SELECT unit_price_gnf FROM public.food_order_items
            WHERE order_id = (v_res->>'order_id')::uuid) = 175000, NULL);
    UPDATE public.food_menu_items SET price_gnf = 100000 WHERE id = v_item;

    UPDATE public.food_restaurants SET is_open = false WHERE id = v_resto;
    BEGIN
      PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'delivery','choppay', gen_random_uuid(), 'Kipe', 9.5395, -13.6760, NULL, NULL, NULL, 'gps');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('E1.4 a restaurant cached as open but now closed is refused',
          v_err LIKE '%RESTAURANT_CLOSED%', v_err);
    UPDATE public.food_restaurants SET is_open = true WHERE id = v_resto;

    UPDATE public.food_restaurants SET delivery_available = false WHERE id = v_resto;
    BEGIN
      PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'delivery','choppay', gen_random_uuid(), 'Kipe', 9.5395, -13.6760, NULL, NULL, NULL, 'gps');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('E1.5 stale delivery eligibility loses to the fresh server verdict',
          v_err LIKE '%DELIVERY_NOT_AVAILABLE%', v_err);
    UPDATE public.food_restaurants SET delivery_available = true WHERE id = v_resto;

    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'delivery','choppay', gen_random_uuid(), 'Kipe', 9.5395, -13.6760, NULL, NULL, NULL, 'gps');
    SELECT * INTO v_row FROM public.food_orders WHERE id = (v_res->>'order_id')::uuid;
    r := r || public._qa_s13_ok('E2.1 the committed order froze a canonical pricing snapshot',
          v_row.pricing_snapshot IS NOT NULL AND v_row.pricing_policy_id IS NOT NULL, NULL);
    r := r || public._qa_s13_ok('E2.2 the delivery fee comes from the effective policy',
          v_row.delivery_fee_gnf = (v_row.pricing_snapshot->>'customer_delivery_fee_gnf')::bigint,
          v_row.delivery_fee_gnf::text);
    r := r || public._qa_s13_ok('E2.3 the promotion recorded is the canonical effective one',
          v_row.promotion_id IS NOT DISTINCT FROM NULLIF(v_row.pricing_snapshot->>'promotion_id','')::uuid, NULL);
    r := r || public._qa_s13_ok('E2.4 the total is server-composed, not client-supplied',
          v_row.order_total_gnf = v_row.subtotal_gnf + v_row.delivery_fee_gnf + v_row.platform_fee_gnf,
          v_row.order_total_gnf::text);

    -- ================= F · UNKNOWN-OUTCOME RECOVERY (R9 REUSE) =================
    v_rq2 := gen_random_uuid();
    v_res := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'delivery','choppay', v_rq2, 'Kipe', 9.5395, -13.6760, NULL,
        'pres de Prima Center', 'portail bleu', 'gps');
    v_oRep := (v_res->>'order_id')::uuid;
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_module='repas' AND source_id = v_oRep;

    v_d := public.repas_order_resume(v_rq2);
    r := r || public._qa_s13_ok('F1.1 a lost response resolves to the same canonical order',
          (v_d->>'found')::boolean AND (v_d->>'order_id')::uuid = v_oRep, v_d->>'order_id');
    r := r || public._qa_s13_ok('F1.2 resume reports canonical state, not a local guess',
          v_d->>'state' = (SELECT state::text FROM public.food_orders WHERE id = v_oRep), v_d->>'state');

    v_res2 := public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'delivery','choppay', v_rq2, 'Kipe', 9.5395, -13.6760, NULL,
        'pres de Prima Center', 'portail bleu', 'gps');
    r := r || public._qa_s13_ok('F1.3 replaying the same request id returns a replay, not a new order',
          (v_res2->>'replay')::boolean AND (v_res2->>'order_id')::uuid = v_oRep, v_res2->>'order_id');
    SELECT count(*) INTO v_n2 FROM public.food_orders WHERE client_request_id = v_rq2;
    r := r || public._qa_s13_ok('F1.4 exactly one order exists for that request id', v_n2 = 1, v_n2::text);
    SELECT count(*) INTO v_n2 FROM public.missions WHERE ref_food_order_id = v_oRep;
    r := r || public._qa_s13_ok('F1.5 exactly one courier mission exists', v_n2 = 1, v_n2::text);
    SELECT count(*) INTO v_n2 FROM public.mission_financial_holds
     WHERE source_module='repas' AND source_id = v_oRep;
    r := r || public._qa_s13_ok('F1.6 the replay created no second hold', v_n2 = v_n, v_n2::text);
    SELECT count(*) INTO v_n2 FROM public.food_order_items WHERE order_id = v_oRep;
    r := r || public._qa_s13_ok('F1.7 the replay duplicated no order line', v_n2 = 1, v_n2::text);
    SELECT count(*) INTO v_n2 FROM public.chop_pay_order_runtime
     WHERE source_module='repas' AND source_id = v_oRep;
    r := r || public._qa_s13_ok('F1.8 exactly one payment runtime row exists', v_n2 = 1, v_n2::text);
    SELECT count(*) INTO v_n2 FROM public.merchant_payables WHERE source_id = v_oRep;
    r := r || public._qa_s13_ok('F1.9 the replay created no duplicate merchant payable', v_n2 <= 1, v_n2::text);
    r := r || public._qa_s13_ok('F1.10 the replay did not move the platform fee twice',
          (SELECT platform_fee_gnf FROM public.food_orders WHERE id = v_oRep)
            = (v_res->>'platform_fee_gnf')::bigint, NULL);

    BEGIN
      PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'delivery','choppay', v_rq2, 'Lambanyi', 9.5395, -13.6760, NULL,
        'pres de Prima Center', 'portail bleu', 'gps');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('F2.1 a changed place label on the same key is refused, not swallowed',
          v_err LIKE '%IDEMPOTENCY_CONFLICT%', v_err);
    BEGIN
      PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'delivery','choppay', v_rq2, 'Kipe', 9.5395, -13.6760, NULL,
        'un autre repere', 'portail bleu', 'gps');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('F2.2 a changed landmark on the same key is refused',
          v_err LIKE '%IDEMPOTENCY_CONFLICT%', v_err);
    BEGIN
      PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
        'delivery','choppay', v_rq2, 'Kipe', 9.5395, -13.6760, NULL,
        'pres de Prima Center', 'autres instructions', 'gps');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('F2.3 changed delivery instructions on the same key are refused',
          v_err LIKE '%IDEMPOTENCY_CONFLICT%', v_err);
    BEGIN
      PERFORM public.repas_order_create(v_resto,
        jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',3)),
        'delivery','choppay', v_rq2, 'Kipe', 9.5395, -13.6760, NULL,
        'pres de Prima Center', 'portail bleu', 'gps');
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('F2.4 a changed cart on the same key is refused',
          v_err LIKE '%IDEMPOTENCY_CONFLICT%', v_err);

    SELECT count(*) INTO v_n FROM public.food_orders;
    v_d := public.repas_order_resume(gen_random_uuid());
    SELECT count(*) INTO v_n2 FROM public.food_orders;
    r := r || public._qa_s13_ok('F3.1 resuming an unknown request id reports not-found',
          (v_d->>'found')::boolean IS NOT TRUE, v_d::text);
    r := r || public._qa_s13_ok('F3.2 a not-found resume creates nothing at all', v_n = v_n2, NULL);
    r := r || public._qa_s13_ok('F3.3 resume never leaks another customer order',
          v_d->>'order_id' IS NULL, v_d::text);

    -- ================= G · RECONNECT / REPEAT-TAP INERTNESS =================
    v_t := public.repas_order_tracking(v_oRep);
    SELECT updated_at INTO v_upd FROM public.food_orders WHERE id = v_oRep;
    PERFORM public.repas_order_tracking(v_oRep);
    PERFORM public.repas_order_tracking(v_oRep);
    SELECT updated_at INTO v_upd2 FROM public.food_orders WHERE id = v_oRep;
    r := r || public._qa_s13_ok('G1.1 repeated reconnect refetches mutate nothing',
          v_upd = v_upd2, NULL);
    r := r || public._qa_s13_ok('G1.2 the customer tracking view carries the destination truth',
          v_t->'destination'->>'landmark' = 'pres de Prima Center', v_t->>'destination');
    r := r || public._qa_s13_ok('G1.3 the customer tracking view states the location quality',
          v_t->'destination'->>'location_quality' = 'gps_verified', v_t->>'destination');
    r := r || public._qa_s13_ok('G1.4 the customer view does not expose raw coordinates',
          v_t->'destination'->'coordinates' IS NULL, v_t->>'destination');

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    -- Certified R6/Slice-5 truth: a delivery order cannot be accepted before a
    -- courier is engaged. R11 must not weaken that to make reconnect easier.
    BEGIN
      PERFORM public.repas_merchant_transition(v_oRep, 'accept', NULL);
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('G2.0 a delivery order is still not acceptable before courier engagement',
          v_err LIKE '%INVALID_STATE%', v_err);
    r := r || public._qa_s13_ok('G2.0b the refused accept left the order untouched',
          (SELECT state::text FROM public.food_orders WHERE id = v_oRep) = 'placed', NULL);

    v_res := public.repas_merchant_transition(v_oPick, 'accept', NULL);
    v_res2 := public.repas_merchant_transition(v_oPick, 'accept', NULL);
    r := r || public._qa_s13_ok('G2.1 a repeated accept under latency is idempotent',
          (v_res2->>'idempotent')::boolean IS TRUE, v_res2::text);
    r := r || public._qa_s13_ok('G2.2 the order state is confirmed exactly once',
          (SELECT state::text FROM public.food_orders WHERE id = v_oPick) = 'confirmed', NULL);
    SELECT count(*) INTO v_n FROM public.merchant_payables WHERE source_id = v_oPick;
    r := r || public._qa_s13_ok('G2.3 the repeated accept created no duplicate merchant payable',
          v_n <= 1, v_n::text);
    v_res := public.repas_merchant_transition(v_oPick, 'prepare', NULL);
    v_res2 := public.repas_merchant_transition(v_oPick, 'prepare', NULL);
    r := r || public._qa_s13_ok('G2.4 a repeated prepare under latency is idempotent',
          (v_res2->>'idempotent')::boolean IS TRUE, v_res2::text);
    r := r || public._qa_s13_ok('G2.5 no lifecycle state was skipped or invented',
          (SELECT state::text FROM public.food_orders WHERE id = v_oPick) = 'preparing', NULL);
    v_res := public.repas_merchant_transition(v_oPick, 'ready', NULL);
    v_res2 := public.repas_merchant_transition(v_oPick, 'ready', NULL);
    SELECT count(*) INTO v_n FROM public.repas_custody_credentials WHERE order_id = v_oPick;
    r := r || public._qa_s13_ok('G2.6 a repeated ready issues no duplicate custody credential',
          v_n = 1, v_n::text);
    r := r || public._qa_s13_ok('G2.7 the repeated ready is idempotent',
          (v_res2->>'idempotent')::boolean IS TRUE, v_res2::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
    v_t := public.repas_order_tracking(v_oDel);
    r := r || public._qa_s13_ok('G3.1 a non-terminal order reports terminal=false honestly',
          (v_t->>'terminal')::boolean IS FALSE, v_t->>'terminal');
    PERFORM public.repas_customer_cancel_order(v_oDel, 'QA R11 annulation client');
    v_t := public.repas_order_tracking(v_oDel);
    r := r || public._qa_s13_ok('G3.2 a reconnect after a terminal state restores terminal truth',
          (v_t->>'terminal')::boolean IS TRUE AND v_t->>'state' = 'cancelled', v_t->>'state');
    r := r || public._qa_s13_ok('G3.3 the terminal reason is server-provided, not invented',
          v_t->>'terminal_reason' IS NOT NULL, v_t->>'terminal_reason');
    r := r || public._qa_s13_ok('G3.4 the frozen destination survives cancellation',
          (SELECT delivery_landmark FROM public.food_orders WHERE id = v_oDel)
            = 'pres de Prima Center', NULL);

    -- ================= H · R10 OPS VISIBILITY =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    v_d := public.repas_ops_case_detail(v_oRep);
    r := r || public._qa_s13_ok('H1.1 ops sees the canonical landmark',
          v_d->'destination'->>'landmark' = 'pres de Prima Center', v_d->>'destination');
    r := r || public._qa_s13_ok('H1.2 ops sees the canonical delivery instructions',
          v_d->'destination'->>'instructions' = 'portail bleu', v_d->>'destination');
    r := r || public._qa_s13_ok('H1.3 ops sees the honest location-quality posture',
          v_d->'destination'->>'location_quality' = 'gps_verified', v_d->>'destination');
    r := r || public._qa_s13_ok('H1.4 ops is told the destination is frozen and not editable',
          (v_d->'destination'->>'frozen')::boolean IS TRUE
      AND (v_d->'destination'->>'editable')::boolean IS FALSE, v_d->>'destination');
    r := r || public._qa_s13_ok('H1.5 ops sees the coordinates needed to help a courier',
          v_d->'destination'->>'lat' IS NOT NULL, v_d->>'destination');
    v_d := public.repas_ops_case_detail(v_oPick);
    r := r || public._qa_s13_ok('H1.6 a pickup case exposes no destination block',
          v_d->'destination' = 'null'::jsonb, v_d->>'destination');
    SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc WHERE proname='repas_ops_case_detail';
    r := r || public._qa_s13_ok('H1.7 the ops detail remains read-only over the order',
          v_def NOT LIKE '%UPDATE public.food_orders%'
      AND v_def NOT LIKE '%INSERT INTO public.food_orders%', NULL);
    r := r || public._qa_s13_ok('H1.8 reassignment is still declared unavailable',
          (v_d->>'reassignment_available')::boolean IS FALSE, NULL);

    -- ================= Z · SYSTEMIC INVARIANTS =================
    SELECT count(*) INTO v_n FROM (
      SELECT j.id FROM public.ledger_journals j
        JOIN public.ledger_postings p ON p.journal_id = j.id
       WHERE j.created_at >= now() - interval '10 minutes'
       GROUP BY j.id HAVING sum(p.amount_gnf) <> 0) z;
    r := r || public._qa_s13_ok('Z1.1 every journal created here is zero-sum', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_module='repas' AND (captured_gnf + released_gnf) > amount_gnf;
    r := r || public._qa_s13_ok('Z1.2 no hold is over-consumed', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.payout_orders WHERE created_at >= now() - interval '10 minutes';
    r := r || public._qa_s13_ok('Z1.3 R11 created no payout order', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.food_orders o
      WHERE o.restaurant_id = v_resto AND o.fulfillment::text = 'pickup'
        AND (o.delivery_lat IS NOT NULL OR o.delivery_address IS NOT NULL
             OR o.delivery_landmark IS NOT NULL OR o.delivery_location_quality IS NOT NULL);
    r := r || public._qa_s13_ok('Z1.4 no pickup order leaked any delivery location', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.food_orders o
      WHERE o.restaurant_id = v_resto AND o.fulfillment::text = 'delivery'
        AND o.delivery_location_quality IS NULL;
    r := r || public._qa_s13_ok('Z1.5 every delivery order carries an explicit quality verdict',
          v_n = 0, v_n::text);

    PERFORM set_config('request.jwt.claims', ''::text, true);
    RAISE EXCEPTION 'QA_NODE3_R11_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_NODE3_R11_ROLLBACK' THEN
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
  SELECT count(*) INTO v_n FROM public.food_restaurants WHERE slug LIKE 'qa-n3r11-%';
  r := r || public._qa_s13_ok('Z9.3 no restaurant fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.food_menu_items WHERE name LIKE 'QA R11 %';
  r := r || public._qa_s13_ok('Z9.4 no menu fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM auth.users WHERE email LIKE 'qa-s13-n3r11%';
  r := r || public._qa_s13_ok('Z9.5 no QA user residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.food_orders WHERE delivery_landmark = 'pres de Prima Center';
  r := r || public._qa_s13_ok('Z9.6 no destination fixture residue', v_n = 0, v_n::text);

  RETURN jsonb_build_object('part','node3_repas_r11_conakry_hardening',
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'results', r);
END; $function$;

DELETE FROM public._qa_s13_results WHERE part = 1011;
INSERT INTO public._qa_s13_results(part, result)
VALUES (1011, public._qa_node3_repas_r11_conakry_hardening());
