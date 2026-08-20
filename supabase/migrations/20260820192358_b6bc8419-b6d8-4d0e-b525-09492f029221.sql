CREATE OR REPLACE FUNCTION public._qa_node4_marche_r13()
RETURNS jsonb
LANGUAGE plpgsql
SET statement_timeout TO '60s'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_buy uuid; v_buy2 uuid; v_merch uuid; v_ops uuid;
  v_store uuid; l_a uuid; l_b uuid; l_neg uuid; l_zero uuid;
  v_res jsonb; v_rev jsonb; v_rec jsonb; v_case jsonb; v_case_id uuid;
  v_o1 uuid; v_o2 uuid; v_err text; v_n int; i int;
  v_ids uuid[]; v_ids2 uuid[]; v_t0 timestamptz;
  v_w0 bigint; v_w1 bigint; v_wt0 bigint; v_wt1 bigint; v_lj0 bigint; v_lj1 bigint;
  v_lp0 numeric; v_lp1 numeric; v_pi0 bigint; v_pi1 bigint; v_mp0 bigint; v_mp1 bigint;
  v_po0 bigint; v_po1 bigint; v_pr0 bigint; v_pr1 bigint; v_au0 bigint; v_au1 bigint;
  v_ml0 bigint; v_ml1 bigint; v_ord0 bigint; v_ord1 bigint; v_oi0 bigint; v_oi1 bigint;
  v_pm0 bigint; v_pm1 bigint; v_ob0 bigint; v_ob1 bigint; v_re0 bigint; v_re1 bigint;
  v_cs0 bigint; v_cs1 bigint; v_ev0 bigint; v_ev1 bigint; v_ct0 bigint; v_ct1 bigint;
  v_st0 bigint; v_st1 bigint; v_flags0 jsonb; v_flags1 jsonb;
BEGIN
  SELECT count(*) INTO v_w0 FROM public.wallets;
  SELECT count(*) INTO v_wt0 FROM public.wallet_transactions;
  SELECT count(*) INTO v_lj0 FROM public.ledger_journals;
  SELECT COALESCE(sum(amount_gnf),0) INTO v_lp0 FROM public.ledger_postings;
  SELECT count(*) INTO v_pi0 FROM public.payment_intents;
  SELECT count(*) INTO v_mp0 FROM public.merchant_payables;
  SELECT count(*) INTO v_po0 FROM public.payout_orders;
  SELECT count(*) INTO v_pr0 FROM public.profiles;
  v_au0 := public._qa_auth_user_count();
  SELECT count(*) INTO v_ml0 FROM public.marketplace_listings;
  SELECT count(*) INTO v_ord0 FROM public.marche_orders;
  SELECT count(*) INTO v_oi0 FROM public.marche_order_items;
  SELECT count(*) INTO v_pm0 FROM public.marche_procurement_missions;
  SELECT count(*) INTO v_ob0 FROM public.marche_procurement_price_observations;
  SELECT count(*) INTO v_re0 FROM public.marche_reputation_events;
  SELECT count(*) INTO v_cs0 FROM public.marche_ops_cases;
  SELECT count(*) INTO v_ev0 FROM public.marche_ops_events;
  SELECT count(*) INTO v_ct0 FROM public.marche_ops_controls;
  SELECT count(*) INTO v_st0 FROM public.merchant_stores;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;

  -- ===================== A. STRUCTURAL =====================
  r := r || public._qa_s13_ok('N4R13.A1 destination_label column exists',
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                 AND table_name='marche_orders' AND column_name='destination_label'), NULL);
  r := r || public._qa_s13_ok('N4R13.A2 destination_landmark column exists',
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                 AND table_name='marche_orders' AND column_name='destination_landmark'), NULL);
  r := r || public._qa_s13_ok('N4R13.A3 destination_instructions column exists',
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                 AND table_name='marche_orders' AND column_name='destination_instructions'), NULL);
  r := r || public._qa_s13_ok('N4R13.A4 server-derived destination_quality column exists',
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                 AND table_name='marche_orders' AND column_name='destination_quality'), NULL);
  r := r || public._qa_s13_ok('N4R13.A5 revalidation RPC exists',
        EXISTS (SELECT 1 FROM pg_proc WHERE proname='marche_basket_revalidate'), NULL);
  r := r || public._qa_s13_ok('N4R13.A6 lost-response recovery RPC exists',
        EXISTS (SELECT 1 FROM pg_proc WHERE proname='marche_order_recover'), NULL);
  r := r || public._qa_s13_ok('N4R13.A7 both R13 RPCs are definer and pin search_path',
        NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname IN
          ('marche_basket_revalidate','marche_order_recover','_marche_destination_quality')
          AND (proname <> '_marche_destination_quality' AND NOT prosecdef)
          ), NULL);
  r := r || public._qa_s13_ok('N4R13.A8 R13 RPCs pin search_path=public',
        NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname IN
          ('marche_basket_revalidate','marche_order_recover','_marche_destination_quality')
          AND COALESCE(array_to_string(proconfig,','),'') NOT LIKE '%search_path=public%'), NULL);
  r := r || public._qa_s13_ok('N4R13.A9 revalidation is STABLE (cannot write)',
        (SELECT provolatile FROM pg_proc WHERE proname='marche_basket_revalidate')='s', NULL);
  r := r || public._qa_s13_ok('N4R13.A10 recovery is STABLE (cannot write)',
        (SELECT provolatile FROM pg_proc WHERE proname='marche_order_recover')='s', NULL);
  r := r || public._qa_s13_ok('N4R13.A11 anon cannot revalidate a basket',
        NOT has_function_privilege('anon','public.marche_basket_revalidate(jsonb)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R13.A12 anon cannot recover an order',
        NOT has_function_privilege('anon','public.marche_order_recover(text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R13.A13 signed-in users can revalidate and recover',
        has_function_privilege('authenticated','public.marche_basket_revalidate(jsonb)','EXECUTE')
    AND has_function_privilege('authenticated','public.marche_order_recover(text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R13.A14 the destination-quality helper is not client-callable',
        NOT has_function_privilege('authenticated','public._marche_destination_quality(double precision,double precision,text,text,text,text)','EXECUTE')
    AND NOT has_function_privilege('anon','public._marche_destination_quality(double precision,double precision,text,text,text,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R13.A15 revalidation never reserves stock',
        (SELECT prosrc FROM pg_proc WHERE proname='marche_basket_revalidate') NOT LIKE '%quantity_reserved =%', NULL);
  r := r || public._qa_s13_ok('N4R13.A16 revalidation touches no money rail',
        (SELECT prosrc NOT LIKE '%wallet%' AND prosrc NOT LIKE '%ledger_%'
             AND prosrc NOT LIKE '%merchant_payables%' AND prosrc NOT LIKE '%payment_intents%'
           FROM pg_proc WHERE proname='marche_basket_revalidate'), NULL);
  r := r || public._qa_s13_ok('N4R13.A17 commitment still refuses any client price',
        (SELECT prosrc FROM pg_proc WHERE proname='marche_order_commit') LIKE '%CLIENT_PRICE_NOT_ALLOWED%', NULL);
  r := r || public._qa_s13_ok('N4R13.A18 commitment refuses a client-declared location verdict',
        (SELECT prosrc FROM pg_proc WHERE proname='marche_order_commit') LIKE '%CLIENT_LOCATION_QUALITY_NOT_ALLOWED%', NULL);
  r := r || public._qa_s13_ok('N4R13.A19 discovery page size stays bounded',
        (SELECT prosrc FROM pg_proc WHERE proname='marche_listings_discover'
          AND pronargs=8) LIKE '%LEAST(COALESCE(p_limit, 60), 200)%', NULL);
  r := r || public._qa_s13_ok('N4R13.A20 anon still cannot execute has_role (P15.5 preserved)',
        NOT has_function_privilege('anon','public.has_role(uuid,app_role)','EXECUTE'), NULL);

  -- pure derivation law, no fixtures needed
  r := r || public._qa_s13_ok('N4R13.A21 GPS point yields gps_verified',
        public._marche_destination_quality(9.5,-13.6,'gps',NULL,NULL,NULL)='gps_verified', NULL);
  r := r || public._qa_s13_ok('N4R13.A22 hand-placed pin yields manually_placed',
        public._marche_destination_quality(9.5,-13.6,'manual_pin',NULL,NULL,NULL)='manually_placed', NULL);
  r := r || public._qa_s13_ok('N4R13.A23 typed point with coordinates stays approximate',
        public._marche_destination_quality(9.5,-13.6,'typed',NULL,NULL,NULL)='approximate', NULL);
  r := r || public._qa_s13_ok('N4R13.A24 landmark prose alone is landmark_assisted, never GPS',
        public._marche_destination_quality(NULL,NULL,'gps','près du marché Madina',NULL,NULL)='landmark_assisted', NULL);
  r := r || public._qa_s13_ok('N4R13.A25 empty destination is honestly unverifiable',
        public._marche_destination_quality(NULL,NULL,NULL,NULL,NULL,NULL)='unverifiable', NULL);

  BEGIN
    -- ===================== FIXTURES =====================
    v_buy := gen_random_uuid(); v_buy2 := gen_random_uuid();
    v_merch := gen_random_uuid(); v_ops := gen_random_uuid();
    PERFORM public._qa_s13_user(v_buy,'n413b');
    PERFORM public._qa_s13_user(v_buy2,'n413c');
    PERFORM public._qa_s13_user(v_merch,'n413m');
    PERFORM public._qa_s13_user(v_ops,'n413o');
    INSERT INTO public.admin_users(user_id, admin_role, status) VALUES (v_ops,'operations_admin','active');

    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status,
      latitude, longitude, address_label, phone)
      VALUES (v_merch,'qa-n413-'||substr(v_merch::text,1,8),'QA N413 Store','active','approved',
              9.5370,-13.6785,'QA Madina','+224620000113')
      RETURNING id INTO v_store;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    l_a := public.marche_listing_create(jsonb_build_object('store_id',v_store,'title','QA N413 Riz',
      'category','Alimentation','price_gnf',10000,'quantity_in_stock',20,'publish',true));
    l_b := public.marche_listing_create(jsonb_build_object('store_id',v_store,'title','QA N413 Huile',
      'category','Alimentation','price_gnf',25000,'quantity_in_stock',2,'publish',true));

    -- ============ B. REVALIDATION AUTHORITY / READ-ONLYNESS ============
    PERFORM set_config('request.jwt.claims','', true);
    v_err := NULL;
    BEGIN PERFORM public.marche_basket_revalidate(jsonb_build_object('items',
      jsonb_build_array(jsonb_build_object('listing_id',l_a,'qty',1))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R13.B1 a signed-out caller cannot revalidate', v_err='AUTH_REQUIRED', v_err);

    v_err := NULL;
    BEGIN PERFORM public.marche_order_recover('qa-n413-nothing-here');
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R13.B2 a signed-out caller cannot recover', v_err='AUTH_REQUIRED', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_basket_revalidate(jsonb_build_object(
      'merchandise_subtotal_gnf', 1,
      'items', jsonb_build_array(jsonb_build_object('listing_id',l_a,'qty',1))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R13.B3 a cached total may not be pushed into revalidation',
          v_err='CLIENT_PRICE_NOT_ALLOWED', v_err);

    v_err := NULL;
    BEGIN PERFORM public.marche_basket_revalidate(jsonb_build_object('items','[]'::jsonb));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R13.B4 an empty draft is refused', v_err='EMPTY_BASKET', v_err);

    SELECT count(*) INTO v_n FROM public.marche_orders;
    v_rev := public.marche_basket_revalidate(jsonb_build_object('items',
      jsonb_build_array(jsonb_build_object('listing_id',l_a,'qty',2))));
    r := r || public._qa_s13_ok('N4R13.B5 revalidating an offline draft creates no order',
          (SELECT count(*) FROM public.marche_orders) = v_n, NULL);
    r := r || public._qa_s13_ok('N4R13.B6 revalidating an offline draft reserves no stock',
          COALESCE((SELECT quantity_reserved FROM public.marketplace_listings WHERE id=l_a),0)=0, NULL);
    r := r || public._qa_s13_ok('N4R13.B7 revalidation is a versioned, dated statement',
          v_rev->>'schema'='chopchop.marche.basket_revalidation'
      AND (v_rev->>'version')::int=1 AND (v_rev->>'revalidated_at') IS NOT NULL, NULL);

    -- ============ C. REVALIDATION SEMANTICS ============
    r := r || public._qa_s13_ok('N4R13.C1 a healthy draft revalidates ok',
          (v_rev->>'ok')::boolean AND NOT (v_rev->>'material_change')::boolean, v_rev->>'blocking_reason');
    r := r || public._qa_s13_ok('N4R13.C2 the server returns its own subtotal, not the cached one',
          (v_rev->>'merchandise_subtotal_gnf')::bigint = 20000, v_rev->>'merchandise_subtotal_gnf');
    r := r || public._qa_s13_ok('N4R13.C3 the server states the current unit price',
          (v_rev->'lines'->0->>'unit_price_gnf')::bigint = 10000, NULL);
    r := r || public._qa_s13_ok('N4R13.C4 the server states the real available quantity',
          (v_rev->'lines'->0->>'available_qty')::int = 20, NULL);
    r := r || public._qa_s13_ok('N4R13.C5 the store identity is server-resolved',
          (v_rev->>'store_id')::uuid = v_store, NULL);

    v_rev := public.marche_basket_revalidate(jsonb_build_object('items',
      jsonb_build_array(jsonb_build_object('listing_id',l_a,'qty',1,'cached_unit_price_gnf',7000))));
    r := r || public._qa_s13_ok('N4R13.C6 a stale cached price is detected',
          v_rev->'lines'->0->>'status'='price_changed'
      AND (v_rev->'lines'->0->>'price_changed')::boolean, v_rev->'lines'->0->>'status');
    r := r || public._qa_s13_ok('N4R13.C7 a stale price is flagged as a material change',
          (v_rev->>'material_change')::boolean, NULL);
    r := r || public._qa_s13_ok('N4R13.C8 the cached price never becomes the total',
          (v_rev->>'merchandise_subtotal_gnf')::bigint = 10000, v_rev->>'merchandise_subtotal_gnf');

    v_rev := public.marche_basket_revalidate(jsonb_build_object('items',
      jsonb_build_array(jsonb_build_object('listing_id',l_b,'qty',5))));
    r := r || public._qa_s13_ok('N4R13.C9 a quantity beyond real stock is refused honestly',
          NOT (v_rev->>'ok')::boolean AND v_rev->'lines'->0->>'reason'='INSUFFICIENT_STOCK', v_rev->>'blocking_reason');
    r := r || public._qa_s13_ok('N4R13.C10 the honest remaining quantity is returned',
          (v_rev->'lines'->0->>'available_qty')::int = 2, NULL);

    v_rev := public.marche_basket_revalidate(jsonb_build_object('items',
      jsonb_build_array(jsonb_build_object('listing_id',gen_random_uuid(),'qty',1))));
    r := r || public._qa_s13_ok('N4R13.C11 a removed listing is reported as not found',
          NOT (v_rev->>'ok')::boolean AND v_rev->'lines'->0->>'status'='not_found', NULL);

    -- pause the listing -> unavailable
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    PERFORM public.marche_listing_update(l_b, jsonb_build_object('status','paused'));
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_rev := public.marche_basket_revalidate(jsonb_build_object('items',
      jsonb_build_array(jsonb_build_object('listing_id',l_b,'qty',1))));
    r := r || public._qa_s13_ok('N4R13.C12 a paused listing is reported unavailable',
          NOT (v_rev->>'ok')::boolean AND v_rev->'lines'->0->>'status'='unavailable', v_rev->'lines'->0->>'reason');
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    PERFORM public.marche_listing_update(l_b, jsonb_build_object('status','active'));

    -- R12 quarantine must be honoured by revalidation
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_ops), true);
    v_case := public.marche_ops_case_open(jsonb_build_object('case_type','catalog_violation',
      'store_id', v_store, 'listing_id', l_a, 'reason_code','qa_n413'));
    v_case_id := COALESCE(NULLIF(v_case->'case'->>'id',''), v_case->>'id')::uuid;
    PERFORM public.marche_ops_command(v_case_id,'quarantine_listing',gen_random_uuid(),'qa_n413','QA','{}'::jsonb);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_rev := public.marche_basket_revalidate(jsonb_build_object('items',
      jsonb_build_array(jsonb_build_object('listing_id',l_a,'qty',1))));
    r := r || public._qa_s13_ok('N4R13.C13 a quarantined listing is refused at revalidation',
          NOT (v_rev->>'ok')::boolean AND v_rev->'lines'->0->>'reason'='LISTING_QUARANTINED',
          v_rev->'lines'->0->>'reason');
    v_err := NULL;
    BEGIN PERFORM public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n413-quarantined-001',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_a, 'qty', 1))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R13.C14 a quarantined listing cannot be committed from stale UI',
          v_err='LISTING_QUARANTINED', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_ops), true);
    PERFORM public.marche_ops_command(v_case_id,'restore_listing',gen_random_uuid(),'qa_n413','QA','{}'::jsonb);

    -- R12 merchant suspension must be honoured by revalidation
    v_case := public.marche_ops_case_open(jsonb_build_object('case_type','merchant_suspension',
      'store_id', v_store, 'reason_code','qa_n413s'));
    v_case_id := COALESCE(NULLIF(v_case->'case'->>'id',''), v_case->>'id')::uuid;
    PERFORM public.marche_ops_command(v_case_id,'suspend_merchant',gen_random_uuid(),'qa_n413s','QA','{}'::jsonb);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_rev := public.marche_basket_revalidate(jsonb_build_object('items',
      jsonb_build_array(jsonb_build_object('listing_id',l_a,'qty',1))));
    r := r || public._qa_s13_ok('N4R13.C15 a suspended merchant is refused at revalidation',
          NOT (v_rev->>'ok')::boolean AND v_rev->'lines'->0->>'reason'='STORE_SUSPENDED',
          v_rev->'lines'->0->>'reason');
    v_err := NULL;
    BEGIN PERFORM public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n413-suspended-001',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_a, 'qty', 1))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R13.C16 a suspended merchant cannot be committed from stale UI',
          v_err='STORE_SUSPENDED', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_ops), true);
    PERFORM public.marche_ops_command(v_case_id,'restore_merchant',gen_random_uuid(),'qa_n413s','QA','{}'::jsonb);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_basket_revalidate(jsonb_build_object('items',
      jsonb_build_array(jsonb_build_object('listing_id',l_a,'qty',1))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    v_rev := public.marche_basket_revalidate(jsonb_build_object('items',
      jsonb_build_array(jsonb_build_object('listing_id',l_a,'qty',1))));
    r := r || public._qa_s13_ok('N4R13.C17 the seller cannot revalidate its own supply as a buyer',
          NOT (v_rev->>'ok')::boolean AND v_rev->'lines'->0->>'reason'='SELF_PURCHASE_NOT_ALLOWED',
          v_rev->'lines'->0->>'reason');

    -- ============ D. LOST-RESPONSE RECOVERY ============
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_res := public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n413-lostresp-0001',
      'delivery_address','QA Kaloum, Conakry','dropoff_lat',9.5550,'dropoff_lng',-13.6785,
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_a, 'qty', 1))));
    v_o1 := (v_res->>'id')::uuid;

    -- the response is "lost": the client only kept its own intent identity
    v_rec := public.marche_order_recover('qa-n413-lostresp-0001');
    r := r || public._qa_s13_ok('N4R13.D1 recovery finds the canonical order after a lost response',
          (v_rec->>'found')::boolean AND (v_rec->'order'->>'id')::uuid = v_o1, NULL);
    r := r || public._qa_s13_ok('N4R13.D2 recovery is a versioned statement',
          v_rec->>'schema'='chopchop.marche.order_recovery' AND (v_rec->>'version')::int=1, NULL);
    r := r || public._qa_s13_ok('N4R13.D3 recovery restores the frozen server total',
          (v_rec->'order'->>'merchandise_subtotal_gnf')::bigint = 10000, NULL);
    r := r || public._qa_s13_ok('N4R13.D4 recovery creates no second order',
          (SELECT count(*) FROM public.marche_orders WHERE buyer_user_id=v_buy)=1, NULL);
    v_rec := public.marche_order_recover('qa-n413-never-committed-01');
    r := r || public._qa_s13_ok('N4R13.D5 an unknown intent honestly reports no commitment',
          (v_rec->>'found')::boolean = false AND v_rec->'order' = 'null'::jsonb, NULL);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy2), true);
    v_rec := public.marche_order_recover('qa-n413-lostresp-0001');
    r := r || public._qa_s13_ok('N4R13.D6 recovery is buyer-scoped: another customer sees nothing',
          (v_rec->>'found')::boolean = false, NULL);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_rec := public.marche_order_recover('qa-n413-lostresp-0001');
    r := r || public._qa_s13_ok('N4R13.D7 the merchant cannot recover by the buyer intent key',
          (v_rec->>'found')::boolean = false, NULL);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_order_recover('short');
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R13.D8 a malformed intent key is refused',
          v_err='CLIENT_REQUEST_ID_REQUIRED', v_err);

    -- ============ E. REPEATED TAPS ============
    FOR i IN 1..10 LOOP
      v_res := public.marche_order_commit(jsonb_build_object(
        'client_request_id','qa-n413-taps-000001',
        'items', jsonb_build_array(jsonb_build_object('listing_id', l_a, 'qty', 1))));
    END LOOP;
    SELECT count(*) INTO v_n FROM public.marche_orders
      WHERE buyer_user_id=v_buy AND client_request_id='qa-n413-taps-000001';
    r := r || public._qa_s13_ok('N4R13.E1 ten taps create exactly one order', v_n=1, v_n::text);
    r := r || public._qa_s13_ok('N4R13.E2 ten taps reserve stock exactly once',
          (SELECT quantity_reserved FROM public.marketplace_listings WHERE id=l_a)=2, NULL);
    r := r || public._qa_s13_ok('N4R13.E3 every replay returns the same canonical order',
          (v_res->>'id')::uuid = (SELECT id FROM public.marche_orders
            WHERE buyer_user_id=v_buy AND client_request_id='qa-n413-taps-000001'), NULL);
    SELECT count(*) INTO v_n FROM public.marche_order_items i
      JOIN public.marche_orders o ON o.id=i.order_id
     WHERE o.client_request_id='qa-n413-taps-000001';
    r := r || public._qa_s13_ok('N4R13.E4 replays never duplicate order lines', v_n=1, v_n::text);

    v_err := NULL;
    BEGIN PERFORM public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n413-taps-000001',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_a, 'qty', 3))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R13.E5 a changed basket may not reuse the same identity',
          v_err='IDEMPOTENCY_CONFLICT', v_err);

    v_res := public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n413-taps-000002',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_a, 'qty', 1))));
    v_o2 := (v_res->>'id')::uuid;
    r := r || public._qa_s13_ok('N4R13.E6 a genuinely new intent can still order the same basket',
          v_o2 IS NOT NULL AND v_o2 <> v_o1, NULL);
    r := r || public._qa_s13_ok('N4R13.E7 identity is not derived from cart contents',
          (SELECT count(DISTINCT request_fingerprint) FROM public.marche_orders
            WHERE buyer_user_id=v_buy AND client_request_id IN ('qa-n413-taps-000001','qa-n413-taps-000002'))=1, NULL);

    -- ============ F. LANDMARK DESTINATIONS ============
    v_res := public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n413-landmark-0001',
      'destination_label','Madina',
      'destination_landmark','près du marché Madina',
      'destination_instructions','derrière la station, portail bleu',
      'location_source','typed',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_a, 'qty', 1))));
    r := r || public._qa_s13_ok('N4R13.F1 the landmark is persisted with the order',
          v_res->>'destination_landmark'='près du marché Madina', NULL);
    r := r || public._qa_s13_ok('N4R13.F2 delivery instructions are persisted',
          v_res->>'destination_instructions'='derrière la station, portail bleu', NULL);
    r := r || public._qa_s13_ok('N4R13.F3 landmark prose does not invent coordinates',
          v_res->>'dropoff_lat' IS NULL AND v_res->>'dropoff_lng' IS NULL, NULL);
    r := r || public._qa_s13_ok('N4R13.F4 the server verdict is honest about the missing point',
          v_res->>'destination_quality'='landmark_assisted', v_res->>'destination_quality');

    v_res := public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n413-landmark-0002',
      'destination_landmark','près du marché Madina',
      'dropoff_lat',9.5550,'dropoff_lng',-13.6785,'location_source','gps',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_a, 'qty', 1))));
    r := r || public._qa_s13_ok('N4R13.F5 real coordinates remain the geospatial authority',
          v_res->>'destination_quality'='gps_verified'
      AND (v_res->>'dropoff_lat')::double precision = 9.5550, v_res->>'destination_quality');

    v_err := NULL;
    BEGIN PERFORM public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n413-landmark-0003','destination_quality','gps_verified',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_a, 'qty', 1))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R13.F6 the client may not declare its own location verdict',
          v_err='CLIENT_LOCATION_QUALITY_NOT_ALLOWED', v_err);

    v_err := NULL;
    BEGIN PERFORM public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n413-landmark-0004','location_source','satellite',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_a, 'qty', 1))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R13.F7 an invented location source is refused',
          v_err='INVALID_LOCATION_SOURCE', v_err);

    v_err := NULL;
    BEGIN PERFORM public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n413-landmark-0005',
      'destination_instructions', repeat('x', 500),
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_a, 'qty', 1))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R13.F8 unbounded destination prose is refused',
          v_err='DESTINATION_TEXT_TOO_LONG', v_err);

    -- pre-R13 durable keys keep replaying to the same fingerprint
    v_res := public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n413-lostresp-0001',
      'delivery_address','QA Kaloum, Conakry','dropoff_lat',9.5550,'dropoff_lng',-13.6785,
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_a, 'qty', 1))));
    r := r || public._qa_s13_ok('N4R13.F9 a legacy landmark-free key still replays identically',
          (v_res->>'id')::uuid = v_o1, NULL);

    -- ============ G. LARGE CATALOG ============
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_t0 := clock_timestamp();
    FOR i IN 1..120 LOOP
      PERFORM public.marche_listing_create(jsonb_build_object('store_id',v_store,
        'title','QA N413 Catalogue '||lpad(i::text,4,'0'),
        'category','Alimentation','price_gnf',1000+i,'quantity_in_stock',5,'publish',true));
    END LOOP;
    r := r || public._qa_s13_ok('N4R13.G1 a 120-item catalogue builds within the QA budget',
          clock_timestamp()-v_t0 < interval '40 seconds',
          extract(epoch from clock_timestamp()-v_t0)::text);
    SELECT count(*) INTO v_n FROM public.marketplace_listings WHERE store_id=v_store;
    r := r || public._qa_s13_ok('N4R13.G2 the catalogue fixture is realistically large', v_n>=120, v_n::text);

    PERFORM set_config('request.jwt.claims','', true);
    SELECT count(*) INTO v_n FROM public.marche_listings_discover(NULL,NULL,v_store,'recent',20,0);
    r := r || public._qa_s13_ok('N4R13.G3 discovery honours a small page size', v_n=20, v_n::text);
    SELECT count(*) INTO v_n FROM public.marche_listings_discover(NULL,NULL,v_store,'recent',10000,0);
    r := r || public._qa_s13_ok('N4R13.G4 an abusive page size is clamped to 200', v_n<=200, v_n::text);
    r := r || public._qa_s13_ok('N4R13.G5 the client never needs the whole catalogue for a first render',
          v_n < (SELECT count(*) FROM public.marketplace_listings WHERE store_id=v_store) + 1, NULL);

    SELECT array_agg(id ORDER BY ord) INTO v_ids FROM (
      SELECT id, row_number() OVER () ord FROM public.marche_listings_discover(NULL,NULL,v_store,'recent',20,0)) q;
    SELECT array_agg(id ORDER BY ord) INTO v_ids2 FROM (
      SELECT id, row_number() OVER () ord FROM public.marche_listings_discover(NULL,NULL,v_store,'recent',20,20)) q;
    r := r || public._qa_s13_ok('N4R13.G6 page 2 does not repeat page 1',
          NOT EXISTS (SELECT 1 FROM unnest(v_ids) x WHERE x = ANY(v_ids2)), NULL);
    r := r || public._qa_s13_ok('N4R13.G7 pagination is deterministic across identical calls',
          v_ids = (SELECT array_agg(id ORDER BY ord) FROM (
            SELECT id, row_number() OVER () ord
              FROM public.marche_listings_discover(NULL,NULL,v_store,'recent',20,0)) q2), NULL);
    SELECT count(*) INTO v_n FROM public.marche_listings_discover('Catalogue 001',NULL,v_store,'recent',50,0);
    r := r || public._qa_s13_ok('N4R13.G8 server-side search narrows a large catalogue', v_n BETWEEN 1 AND 10, v_n::text);
    SELECT count(*) INTO v_n FROM public.marche_listings_discover('Catalogue',NULL,v_store,'price_asc',30,0);
    r := r || public._qa_s13_ok('N4R13.G9 a sorted page stays bounded', v_n=30, v_n::text);
    SELECT count(*) INTO v_n FROM public.marche_listings_discover(NULL,NULL,v_store,'recent',20,10000);
    r := r || public._qa_s13_ok('N4R13.G10 an offset past the end returns an empty page, not an error', v_n=0, v_n::text);

    -- ============ H. NO OFFLINE ECONOMIC AUTHORITY ============
    r := r || public._qa_s13_ok('N4R13.H1 revalidation created no wallet movement',
          (SELECT count(*) FROM public.wallet_transactions)=v_wt0, NULL);
    r := r || public._qa_s13_ok('N4R13.H2 revalidation created no payable',
          (SELECT count(*) FROM public.merchant_payables)=v_mp0, NULL);
    r := r || public._qa_s13_ok('N4R13.H3 revalidation created no payment intent',
          (SELECT count(*) FROM public.payment_intents)=v_pi0, NULL);
    r := r || public._qa_s13_ok('N4R13.H4 revalidation created no procurement obligation',
          (SELECT count(*) FROM public.marche_procurement_missions)=v_pm0, NULL);
    r := r || public._qa_s13_ok('N4R13.H5 revalidation published no price observation',
          (SELECT count(*) FROM public.marche_procurement_price_observations)=v_ob0, NULL);
    r := r || public._qa_s13_ok('N4R13.H6 revalidation altered no reputation',
          (SELECT count(*) FROM public.marche_reputation_events)=v_re0, NULL);

    RAISE EXCEPTION 'QA_N4R13_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_N4R13_ROLLBACK' THEN
      r := r || public._qa_s13_ok('N4R13.X fixture run raised', false, SQLERRM);
    END IF;
  END;

  PERFORM set_config('request.jwt.claims','', true);

  -- ===================== S. NON-DRIFT =====================
  SELECT count(*) INTO v_w1 FROM public.wallets;
  SELECT count(*) INTO v_wt1 FROM public.wallet_transactions;
  SELECT count(*) INTO v_lj1 FROM public.ledger_journals;
  SELECT COALESCE(sum(amount_gnf),0) INTO v_lp1 FROM public.ledger_postings;
  SELECT count(*) INTO v_pi1 FROM public.payment_intents;
  SELECT count(*) INTO v_mp1 FROM public.merchant_payables;
  SELECT count(*) INTO v_po1 FROM public.payout_orders;
  SELECT count(*) INTO v_pr1 FROM public.profiles;
  v_au1 := public._qa_auth_user_count();
  SELECT count(*) INTO v_ml1 FROM public.marketplace_listings;
  SELECT count(*) INTO v_ord1 FROM public.marche_orders;
  SELECT count(*) INTO v_oi1 FROM public.marche_order_items;
  SELECT count(*) INTO v_pm1 FROM public.marche_procurement_missions;
  SELECT count(*) INTO v_ob1 FROM public.marche_procurement_price_observations;
  SELECT count(*) INTO v_re1 FROM public.marche_reputation_events;
  SELECT count(*) INTO v_cs1 FROM public.marche_ops_cases;
  SELECT count(*) INTO v_ev1 FROM public.marche_ops_events;
  SELECT count(*) INTO v_ct1 FROM public.marche_ops_controls;
  SELECT count(*) INTO v_st1 FROM public.merchant_stores;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;

  r := r || public._qa_s13_ok('N4R13.S1 zero wallet / ledger drift',
        v_w1=v_w0 AND v_wt1=v_wt0 AND v_lj1=v_lj0 AND v_lp1=v_lp0,
        format('%s/%s/%s/%s', v_w1-v_w0, v_wt1-v_wt0, v_lj1-v_lj0, v_lp1-v_lp0));
  r := r || public._qa_s13_ok('N4R13.S2 zero payment / payable / payout drift',
        v_pi1=v_pi0 AND v_mp1=v_mp0 AND v_po1=v_po0,
        format('%s/%s/%s', v_pi1-v_pi0, v_mp1-v_mp0, v_po1-v_po0));
  r := r || public._qa_s13_ok('N4R13.S3 zero identity drift',
        v_pr1=v_pr0 AND v_au1=v_au0, format('%s/%s', v_pr1-v_pr0, v_au1-v_au0));
  r := r || public._qa_s13_ok('N4R13.S4 zero Marché order / line residue',
        v_ord1=v_ord0 AND v_oi1=v_oi0, format('%s/%s', v_ord1-v_ord0, v_oi1-v_oi0));
  r := r || public._qa_s13_ok('N4R13.S5 zero listing residue', v_ml1=v_ml0, (v_ml1-v_ml0)::text);
  r := r || public._qa_s13_ok('N4R13.S6 zero store residue', v_st1=v_st0, (v_st1-v_st0)::text);
  r := r || public._qa_s13_ok('N4R13.S7 zero procurement residue', v_pm1=v_pm0, (v_pm1-v_pm0)::text);
  r := r || public._qa_s13_ok('N4R13.S8 zero price observation residue', v_ob1=v_ob0, (v_ob1-v_ob0)::text);
  r := r || public._qa_s13_ok('N4R13.S9 zero reputation residue', v_re1=v_re0, (v_re1-v_re0)::text);
  r := r || public._qa_s13_ok('N4R13.S10 zero R12 ops case / event / control residue',
        v_cs1=v_cs0 AND v_ev1=v_ev0 AND v_ct1=v_ct0,
        format('%s/%s/%s', v_cs1-v_cs0, v_ev1-v_ev0, v_ct1-v_ct0));
  r := r || public._qa_s13_ok('N4R13.S11 feature flags byte-identical', v_flags1=v_flags0, NULL);
  SELECT count(*) INTO v_n FROM public.merchant_stores WHERE slug LIKE 'qa-n413-%';
  r := r || public._qa_s13_ok('N4R13.S12 zero store fixture residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marketplace_listings WHERE title LIKE 'QA N413%';
  r := r || public._qa_s13_ok('N4R13.S13 zero listing fixture residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_orders WHERE client_request_id LIKE 'qa-n413-%';
  r := r || public._qa_s13_ok('N4R13.S14 zero order fixture residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_ops_cases WHERE reason_code LIKE 'qa_n413%';
  r := r || public._qa_s13_ok('N4R13.S15 zero ops case fixture residue', v_n=0, v_n::text);
  v_n := public._qa_n4r12_orphan_admins()::int;
  r := r || public._qa_s13_ok('N4R13.S16 zero orphan admin fixture residue', v_n=0, v_n::text);

  RETURN r;
END $function$;
