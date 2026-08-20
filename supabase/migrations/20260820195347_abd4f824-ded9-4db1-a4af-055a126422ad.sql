CREATE OR REPLACE FUNCTION public._qa_node4_marche_r14()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  r jsonb := '[]'::jsonb;
  v_buy uuid; v_buy2 uuid; v_merch uuid; v_merch2 uuid; v_ops uuid; v_fin uuid;
  v_shop uuid; v_drv uuid;
  v_store uuid; v_store2 uuid;
  l_a uuid; l_b uuid; l_c uuid;
  v_o1 uuid; v_o2 uuid;
  v_res jsonb; v_rev jsonb; v_rec jsonb; v_case jsonb; v_case_id uuid;
  v_err text; v_n int; v_n2 int; i int;
  v_com uuid; v_var uuid; v_opt uuid; v_rid uuid;
  v_obs0 int; v_obs1 int;
  v_w0 int; v_wt0 int; v_lj0 int; v_lp0 bigint; v_pi0 int; v_mp0 int; v_po0 int;
  v_pr0 int; v_au0 int; v_ml0 int; v_ord0 int; v_oi0 int; v_pm0 int; v_ob0 int;
  v_re0 int; v_cs0 int; v_ev0 int; v_ct0 int; v_st0 int; v_flags0 jsonb;
  v_w1 int; v_wt1 int; v_lj1 int; v_lp1 bigint; v_pi1 int; v_mp1 int; v_po1 int;
  v_pr1 int; v_au1 int; v_ml1 int; v_ord1 int; v_oi1 int; v_pm1 int; v_ob1 int;
  v_re1 int; v_cs1 int; v_ev1 int; v_ct1 int; v_st1 int; v_flags1 jsonb;
BEGIN
  PERFORM set_config('request.jwt.claims','', true);

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

  -- ==================== A. STATIC SECURITY POSTURE ====================
  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname LIKE 'marche\_%' AND p.prosecdef
     AND COALESCE(array_to_string(p.proconfig,','),'') NOT LIKE '%search_path%';
  r := r || public._qa_s13_ok('N4R14.A1 every Marche SECURITY DEFINER function pins its search_path', v_n=0, v_n::text);

  SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname LIKE 'marche\_%' AND p.prosecdef
     AND pg_get_userbyid(p.proowner) <> 'postgres';
  r := r || public._qa_s13_ok('N4R14.A2 no Marche definer function is owned by a non-superuser role', v_n=0, v_n::text);

  SELECT count(*) INTO v_n FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relkind='r'
     AND (c.relname LIKE 'marche\_%' OR c.relname IN ('marketplace_listings','marketplace_offers','listing_images','merchant_stores','merchant_payables'))
     AND NOT c.relrowsecurity;
  r := r || public._qa_s13_ok('N4R14.A3 RLS is enabled on every Marche-bearing table', v_n=0, v_n::text);

  SELECT count(*) INTO v_n FROM information_schema.role_table_grants g
   WHERE g.table_schema='public' AND g.grantee IN ('anon','authenticated')
     AND g.privilege_type IN ('INSERT','UPDATE','DELETE','TRUNCATE')
     AND (g.table_name LIKE 'marche\_%' OR g.table_name IN ('marketplace_listings','marketplace_offers','merchant_payables'));
  r := r || public._qa_s13_ok('N4R14.A4 no client role holds direct write privilege on Marche tables', v_n=0, v_n::text);

  SELECT count(*) INTO v_n FROM information_schema.role_table_grants g
   WHERE g.table_schema='public' AND g.grantee='anon' AND g.privilege_type='SELECT'
     AND g.table_name LIKE 'marche\_%';
  r := r || public._qa_s13_ok('N4R14.A5 signed-out callers hold no direct SELECT on Marche tables', v_n=0, v_n::text);

  r := r || public._qa_s13_ok('N4R14.A6 anon still cannot execute has_role (Repas R8 P15.5 preserved)',
        NOT has_function_privilege('anon','public.has_role(uuid,app_role)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R14.A7 anon cannot execute the ops command rail',
        NOT has_function_privilege('anon','public.marche_ops_command(uuid,text,uuid,text,text,jsonb)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R14.A8 anon cannot execute order commitment',
        NOT has_function_privilege('anon','public.marche_order_commit(jsonb)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R14.A9 anon cannot read the finance order audit',
        NOT has_function_privilege('anon','public.marche_finance_order_audit(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R14.A10 anon cannot read the merchant cockpit',
        NOT has_function_privilege('anon','public.marche_merchant_orders_cockpit(uuid,text,integer,integer)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R14.A11 commitment refuses any client-declared price',
        (SELECT prosrc FROM pg_proc WHERE proname='marche_order_commit') LIKE '%CLIENT_PRICE_NOT_ALLOWED%', NULL);
  r := r || public._qa_s13_ok('N4R14.A12 the ops rail never touches wallets or the ledger directly',
        (SELECT prosrc NOT LIKE '%wallet_transactions%' AND prosrc NOT LIKE '%_ledger_post%'
           FROM pg_proc WHERE proname='marche_ops_command'), NULL);
  r := r || public._qa_s13_ok('N4R14.A13 ops events are protected by an append-only trigger',
        EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
                 WHERE c.relname='marche_ops_events' AND NOT t.tgisinternal), NULL);
  r := r || public._qa_s13_ok('N4R14.A14 price observations are protected by an append-only trigger',
        EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
                 WHERE c.relname='marche_procurement_price_observations' AND NOT t.tgisinternal), NULL);

  BEGIN
    -- ==================== FIXTURES ====================
    v_buy := gen_random_uuid(); v_buy2 := gen_random_uuid();
    v_merch := gen_random_uuid(); v_merch2 := gen_random_uuid();
    v_ops := gen_random_uuid(); v_fin := gen_random_uuid();
    v_shop := gen_random_uuid(); v_drv := gen_random_uuid();
    PERFORM public._qa_s13_user(v_buy,'n414b');
    PERFORM public._qa_s13_user(v_buy2,'n414c');
    PERFORM public._qa_s13_user(v_merch,'n414m');
    PERFORM public._qa_s13_user(v_merch2,'n414n');
    PERFORM public._qa_s13_user(v_ops,'n414o');
    PERFORM public._qa_s13_user(v_fin,'n414f');
    PERFORM public._qa_s13_driver(v_shop,'n414s',0);
    PERFORM public._qa_s13_driver(v_drv,'n414d',0);
    UPDATE public.driver_profiles SET capabilities = capabilities || ARRAY['marche_shopper']
     WHERE user_id = v_shop;
    INSERT INTO public.admin_users(user_id, admin_role, status) VALUES (v_ops,'operations_admin','active');
    INSERT INTO public.admin_users(user_id, admin_role, status) VALUES (v_fin,'finance_admin','active');

    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status,
      latitude, longitude, address_label, phone)
      VALUES (v_merch,'qa-n414-'||substr(v_merch::text,1,8),'QA N414 Store A','active','approved',
              9.5370,-13.6785,'QA Madina','+224620000114') RETURNING id INTO v_store;
    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status,
      latitude, longitude, address_label, phone)
      VALUES (v_merch2,'qa-n414-'||substr(v_merch2::text,1,8),'QA N414 Store B','active','approved',
              9.5380,-13.6795,'QA Kaloum','+224620000115') RETURNING id INTO v_store2;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    l_a := public.marche_listing_create(jsonb_build_object('store_id',v_store,'title','QA N414 Riz',
      'category','Alimentation','price_gnf',11000,'quantity_in_stock',5,'publish',true));
    l_b := public.marche_listing_create(jsonb_build_object('store_id',v_store,'title','QA N414 Huile',
      'category','Alimentation','price_gnf',25000,'quantity_in_stock',1,'publish',true));
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch2), true);
    l_c := public.marche_listing_create(jsonb_build_object('store_id',v_store2,'title','QA N414 Sucre',
      'category','Alimentation','price_gnf',9000,'quantity_in_stock',5,'publish',true));

    -- ==================== B. SIGNED-OUT ACTOR ====================
    PERFORM set_config('request.jwt.claims','', true);

    v_err := NULL;
    BEGIN PERFORM public.marche_order_commit(jsonb_build_object('client_request_id','qa-n414-anon-000001',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_a, 'qty', 1))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.B1 a signed-out caller cannot commit an order', v_err IS NOT NULL, v_err);

    v_err := NULL;
    BEGIN PERFORM public.marche_listing_create(jsonb_build_object('store_id',v_store,'title','QA N414 Pirate',
      'category','Alimentation','price_gnf',1,'quantity_in_stock',1));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.B2 a signed-out caller cannot create supply', v_err IS NOT NULL, v_err);

    v_err := NULL;
    BEGIN PERFORM public.marche_ops_queue(NULL,NULL,NULL,10);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.B3 a signed-out caller cannot open the ops queue', v_err IS NOT NULL, v_err);

    v_err := NULL;
    BEGIN PERFORM public.marche_merchant_orders_cockpit(v_store,NULL,10,0);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.B4 a signed-out caller cannot read a merchant cockpit', v_err IS NOT NULL, v_err);

    v_err := NULL;
    BEGIN PERFORM public.marche_listings_discover(NULL,NULL,NULL,NULL,10,0);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.B5 public discovery still works signed-out', v_err IS NULL, v_err);

    -- ==================== C. CUSTOMER BOUNDARY ====================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_res := public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n414-order-000001',
      'destination_landmark','pres du marche Madina','location_source','typed',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_a, 'qty', 2))));
    v_o1 := (v_res->>'id')::uuid;
    r := r || public._qa_s13_ok('N4R14.C1 a legitimate customer order commits',
          v_o1 IS NOT NULL AND (v_res->>'merchandise_subtotal_gnf')::bigint = 22000,
          v_res->>'merchandise_subtotal_gnf');
    r := r || public._qa_s13_ok('N4R14.C2 the buyer never sees merchant economics',
          v_res->>'merchant_payable_gnf' IS NULL AND v_res->>'merchant_platform_fee_gnf' IS NULL, NULL);
    r := r || public._qa_s13_ok('N4R14.C3 commitment reserves exactly the ordered quantity',
          (SELECT quantity_reserved FROM public.marketplace_listings WHERE id=l_a)=2, NULL);

    v_err := NULL;
    BEGIN PERFORM public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n414-price-000001','merchandise_subtotal_gnf', 1,
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_a, 'qty', 1, 'unit_price_gnf', 1))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.C4 a customer cannot dictate the price of its own basket',
          v_err IS NOT NULL, v_err);

    v_err := NULL;
    BEGIN PERFORM public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n414-oversell-0001',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_b, 'qty', 9999))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.C5 a customer cannot oversell a merchant', v_err IS NOT NULL, v_err);

    BEGIN PERFORM public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n414-buyerid-0001','buyer_user_id', v_buy2::text,
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_a, 'qty', 1))));
    EXCEPTION WHEN OTHERS THEN NULL; END;
    SELECT count(*) INTO v_n FROM public.marche_orders
      WHERE client_request_id='qa-n414-buyerid-0001' AND buyer_user_id <> v_buy;
    r := r || public._qa_s13_ok('N4R14.C6 a supplied buyer identity can never take effect', v_n=0, v_n::text);

    FOR i IN 1..10 LOOP
      v_res := public.marche_order_commit(jsonb_build_object('client_request_id','qa-n414-taps-000001',
        'items', jsonb_build_array(jsonb_build_object('listing_id', l_a, 'qty', 1))));
    END LOOP;
    SELECT count(*) INTO v_n FROM public.marche_orders WHERE client_request_id='qa-n414-taps-000001';
    r := r || public._qa_s13_ok('N4R14.C7 ten taps create exactly one order', v_n=1, v_n::text);
    r := r || public._qa_s13_ok('N4R14.C8 ten taps reserve stock exactly once',
          (SELECT quantity_reserved FROM public.marketplace_listings WHERE id=l_a) IN (3,4),
          (SELECT quantity_reserved::text FROM public.marketplace_listings WHERE id=l_a));
    v_err := NULL;
    BEGIN PERFORM public.marche_order_commit(jsonb_build_object('client_request_id','qa-n414-taps-000001',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_a, 'qty', 2))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.C9 a mutated basket cannot reuse a spent intent identity',
          v_err='IDEMPOTENCY_CONFLICT', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy2), true);
    v_res := NULL; v_err := NULL;
    BEGIN v_res := public.marche_order_get(v_o1);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.C10 knowing an order UUID does not reveal another customer order',
          v_err IS NOT NULL OR v_res IS NULL OR v_res='null'::jsonb, COALESCE(v_err, v_res::text));
    v_rec := public.marche_order_recover('qa-n414-order-000001');
    r := r || public._qa_s13_ok('N4R14.C11 recovery keys are buyer-scoped',
          (v_rec->>'found')::boolean = false, NULL);
    v_res := public.marche_orders_for_buyer(50,0);
    r := r || public._qa_s13_ok('N4R14.C12 a customer order list contains only its own orders',
          NOT (v_res::text LIKE '%'||v_o1::text||'%'), NULL);
    v_err := NULL;
    BEGIN PERFORM public.marche_order_cancel(v_o1,'qa-n414 hostile cancel');
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.C13 a stranger cannot cancel another customer order', v_err IS NOT NULL, v_err);
    r := r || public._qa_s13_ok('N4R14.C14 the attacked order is untouched',
          (SELECT status::text FROM public.marche_orders WHERE id=v_o1) <> 'cancelled', NULL);

    v_err := NULL;
    BEGIN PERFORM public.marche_merchant_transition(v_o1,'accept','qa-n414');
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.C15 a customer cannot drive merchant fulfillment', v_err IS NOT NULL, v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_finance_order_audit(v_o1);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.C16 a customer cannot read the finance audit', v_err IS NOT NULL, v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_ops_queue(NULL,NULL,NULL,10);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.C17 a customer cannot open the ops queue', v_err IS NOT NULL, v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_listing_set_stock(l_a, 999);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.C18 a customer cannot rewrite merchant stock', v_err IS NOT NULL, v_err);
    r := r || public._qa_s13_ok('N4R14.C19 merchant stock is unchanged after the attempt',
          (SELECT quantity_in_stock FROM public.marketplace_listings WHERE id=l_a)=5, NULL);

    -- ==================== D. MERCHANT BOUNDARY ====================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch2), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_listing_update(l_a, jsonb_build_object('price_gnf', 1));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.D1 a merchant cannot edit a rival listing', v_err IS NOT NULL, v_err);
    r := r || public._qa_s13_ok('N4R14.D2 the rival listing price is unchanged',
          (SELECT price_gnf FROM public.marketplace_listings WHERE id=l_a)=11000, NULL);
    v_err := NULL;
    BEGIN PERFORM public.marche_listing_set_stock(l_a, 0);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.D3 a merchant cannot starve a rival stock', v_err IS NOT NULL, v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_listing_archive(l_a);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.D4 a merchant cannot archive a rival listing', v_err IS NOT NULL, v_err);
    r := r || public._qa_s13_ok('N4R14.D5 the rival listing survives',
          (SELECT status::text FROM public.marketplace_listings WHERE id=l_a)='active', NULL);

    v_res := NULL; v_err := NULL;
    BEGIN v_res := public.marche_merchant_orders_cockpit(v_store, NULL, 50, 0);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.D6 a merchant cannot read a rival cockpit',
          v_err IS NOT NULL OR NOT (v_res::text LIKE '%'||v_o1::text||'%'), COALESCE(v_err,'leak'));
    v_res := NULL; v_err := NULL;
    BEGIN v_res := public.marche_orders_for_merchant(v_store, 50, 0);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.D7 a merchant cannot list rival orders',
          v_err IS NOT NULL OR NOT (v_res::text LIKE '%'||v_o1::text||'%'), COALESCE(v_err,'leak'));
    v_err := NULL;
    BEGIN PERFORM public.marche_merchant_transition(v_o1,'accept','qa-n414 hostile');
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.D8 a merchant cannot advance a rival fulfillment', v_err IS NOT NULL, v_err);
    r := r || public._qa_s13_ok('N4R14.D9 the rival order fulfillment state is untouched',
          (SELECT fulfillment_state::text FROM public.marche_orders WHERE id=v_o1)='committed',
          (SELECT fulfillment_state::text FROM public.marche_orders WHERE id=v_o1));
    v_err := NULL;
    BEGIN PERFORM public.marche_merchant_order_ops(v_o1);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.D10 a merchant cannot open a rival order ops view', v_err IS NOT NULL, v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_merchant_transition(v_o1,'accept','qa-n414 legitimate');
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.D11 the owning merchant can accept its own order', v_err IS NULL, v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_finance_order_audit(v_o1);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.D12 a merchant cannot read the finance audit rail', v_err IS NOT NULL, v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_ops_command(gen_random_uuid(),'suspend_merchant',gen_random_uuid(),'qa','x','{}'::jsonb);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.D13 a merchant cannot issue ops commands', v_err='NOT_AUTHORIZED', v_err);
    v_rev := public.marche_basket_revalidate(jsonb_build_object('items',
      jsonb_build_array(jsonb_build_object('listing_id',l_a,'qty',1))));
    r := r || public._qa_s13_ok('N4R14.D14 a merchant cannot buy its own supply',
          NOT (v_rev->>'ok')::boolean AND v_rev->'lines'->0->>'reason'='SELF_PURCHASE_NOT_ALLOWED',
          v_rev->'lines'->0->>'reason');

    -- ==================== E. SHOPPER / DRIVER BOUNDARY ====================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    r := r || public._qa_s13_ok('N4R14.E1 a plain driver is not a Marche shopper',
          NOT public._marche_shopper_eligible(v_drv), NULL);
    v_err := NULL;
    BEGIN PERFORM public.marche_shopper_claim(gen_random_uuid());
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.E2 a plain driver cannot claim a procurement basket',
          v_err='PROCUREMENT_SHOPPER_NOT_ELIGIBLE', v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_shopper_available_baskets(10);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.E3 a plain driver cannot browse procurement supply', v_err IS NOT NULL, v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_shopper_submit_purchase(jsonb_build_object('request_id', gen_random_uuid()));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.E4 a plain driver cannot submit purchase evidence', v_err IS NOT NULL, v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_shop), true);
    r := r || public._qa_s13_ok('N4R14.E5 a capability-bearing shopper is eligible',
          public._marche_shopper_eligible(v_shop), NULL);
    v_err := NULL;
    BEGIN PERFORM public.marche_shopper_claim(gen_random_uuid());
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.E6 an eligible shopper cannot claim a basket that does not exist',
          v_err='PROCUREMENT_NOT_FOUND', v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_merchant_transition(v_o1,'ready','qa-n414');
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.E7 a shopper cannot act as the merchant', v_err IS NOT NULL, v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_ops_command(gen_random_uuid(),'resolve',gen_random_uuid(),'qa','x','{}'::jsonb);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.E8 a shopper cannot resolve ops cases', v_err='NOT_AUTHORIZED', v_err);
    v_res := NULL; v_err := NULL;
    BEGIN v_res := public.marche_shopper_performance(v_drv);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.E9 a shopper cannot read another shopper performance',
          v_err IS NOT NULL OR v_res IS NULL OR v_res='null'::jsonb, COALESCE(v_err,'leak'));

    -- ==================== F. OPERATIONS AUTHORITY + NON-RETROACTIVITY ====================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_ops), true);
    v_case := public.marche_ops_case_open(jsonb_build_object('case_type','catalog_violation',
      'store_id', v_store, 'listing_id', l_a, 'reason_code','qa_n414'));
    v_case_id := (v_case->>'case_id')::uuid;
    r := r || public._qa_s13_ok('N4R14.F1 operations can open an exception case', v_case_id IS NOT NULL, NULL);

    v_rid := gen_random_uuid();
    PERFORM public.marche_ops_command(v_case_id,'quarantine_listing', v_rid,'qa_n414','QA','{}'::jsonb);
    r := r || public._qa_s13_ok('N4R14.F2 quarantine removes the listing from canonical truth',
          NOT (SELECT is_orderable FROM public.v_marche_listing_truth WHERE id=l_a), NULL);
    r := r || public._qa_s13_ok('N4R14.F3 the already-committed order survives the sanction',
          (SELECT count(*) FROM public.marche_orders WHERE id=v_o1)=1, NULL);
    r := r || public._qa_s13_ok('N4R14.F4 the frozen order total is not rewritten by the sanction',
          (SELECT merchandise_subtotal_gnf FROM public.marche_orders WHERE id=v_o1)=22000, NULL);

    SELECT count(*) INTO v_n FROM public.marche_ops_events WHERE case_id=v_case_id;
    SELECT count(*) INTO v_n2 FROM public.marche_ops_controls WHERE case_id=v_case_id;
    PERFORM public.marche_ops_command(v_case_id,'quarantine_listing', v_rid,'qa_n414','QA','{}'::jsonb);
    r := r || public._qa_s13_ok('N4R14.F5 replaying an ops command writes no second event',
          (SELECT count(*) FROM public.marche_ops_events WHERE case_id=v_case_id)=v_n, NULL);
    r := r || public._qa_s13_ok('N4R14.F6 replaying an ops command applies no second control',
          (SELECT count(*) FROM public.marche_ops_controls WHERE case_id=v_case_id)=v_n2, NULL);

    v_err := NULL;
    BEGIN UPDATE public.marche_ops_events SET note='tampered' WHERE case_id=v_case_id;
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.F7 the ops history cannot be rewritten', v_err IS NOT NULL, v_err);
    v_err := NULL;
    BEGIN DELETE FROM public.marche_ops_events WHERE case_id=v_case_id;
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.F8 the ops history cannot be deleted', v_err IS NOT NULL, v_err);

    PERFORM public.marche_ops_command(v_case_id,'restore_listing',gen_random_uuid(),'qa_n414','QA','{}'::jsonb);
    r := r || public._qa_s13_ok('N4R14.F9 a lifted sanction restores canonical orderability',
          (SELECT is_orderable FROM public.v_marche_listing_truth WHERE id=l_a), NULL);

    v_err := NULL;
    BEGIN PERFORM public.marche_ops_command(v_case_id,'record_finance_resolution',gen_random_uuid(),
      'qa_n414','QA', jsonb_build_object('amount_gnf', 100000));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.F10 operations cannot record a financial resolution',
          v_err IS NOT NULL, v_err);
    r := r || public._qa_s13_ok('N4R14.F11 no wallet movement was produced by operations',
          (SELECT count(*) FROM public.wallet_transactions)=v_wt0, NULL);
    r := r || public._qa_s13_ok('N4R14.F12 no ledger journal was produced by operations',
          (SELECT count(*) FROM public.ledger_journals)=v_lj0, NULL);
    r := r || public._qa_s13_ok('N4R14.F13 no payable was produced by operations',
          (SELECT count(*) FROM public.merchant_payables)=v_mp0, NULL);

    v_err := NULL;
    BEGIN UPDATE public.marche_orders SET merchandise_subtotal_gnf = 1 WHERE id=v_o1;
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.F14 committed order economics are immutable',
          v_err IS NOT NULL OR (SELECT merchandise_subtotal_gnf FROM public.marche_orders WHERE id=v_o1)=22000,
          v_err);

    -- ==================== G. FINANCE SEPARATION ====================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_fin), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_finance_order_audit(v_o1);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.G1 finance can read the canonical order audit', v_err IS NULL, v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_listing_set_stock(l_a, 42);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.G2 finance cannot edit merchant supply', v_err IS NOT NULL, v_err);
    v_err := NULL;
    BEGIN PERFORM public.marche_merchant_transition(v_o1,'ready','qa-n414');
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.G3 finance cannot drive merchant fulfillment', v_err IS NOT NULL, v_err);

    -- ==================== H. HISTORICAL PRICE TRUTH ====================
    PERFORM set_config('request.jwt.claims','', true);
    INSERT INTO public.marche_staple_categories(code, name_fr) VALUES ('qa_n414_cat','QA N414')
      ON CONFLICT (code) DO NOTHING;
    INSERT INTO public.marche_staple_commodities(code, category_code, name_fr, unit_family)
    VALUES ('qa_n414_riz','qa_n414_cat','QA N414 Riz',
            (SELECT unit_family FROM public.marche_staple_commodities LIMIT 1))
    RETURNING id INTO v_com;
    INSERT INTO public.marche_staple_variants(commodity_id, code, name_fr)
      VALUES (v_com,'v1','QA N414 V1') RETURNING id INTO v_var;
    INSERT INTO public.marche_staple_purchase_options(variant_id, code, sale_unit, label_fr,
      normalization_kind, canonical_base_unit, canonical_quantity, min_qty, max_qty, step_qty)
      VALUES (v_var,'o1','kg','Sac 1kg','exact','kg',1,1,20,1) RETURNING id INTO v_opt;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    PERFORM public.marche_listing_set_staple_mapping(l_a, v_opt);
    SELECT count(*) INTO v_obs0 FROM public.marche_procurement_price_observations WHERE variant_id=v_var;
    PERFORM public.marche_listing_update(l_a, jsonb_build_object('price_gnf', 13000));
    PERFORM public.marche_listing_update(l_a, jsonb_build_object('price_gnf', 11000));
    SELECT count(*) INTO v_obs1 FROM public.marche_procurement_price_observations WHERE variant_id=v_var;
    r := r || public._qa_s13_ok('N4R14.H1 every merchant ask movement is recorded as evidence',
          v_obs1 > v_obs0, format('%s -> %s', v_obs0, v_obs1));
    SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations
     WHERE variant_id=v_var AND observed_unit_price_gnf=13000;
    r := r || public._qa_s13_ok('N4R14.H2 a reverted price does not erase the 13 000 GNF episode', v_n>=1, v_n::text);
    v_err := NULL;
    BEGIN UPDATE public.marche_procurement_price_observations SET observed_unit_price_gnf=1
     WHERE variant_id=v_var;
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.H3 raw price evidence cannot be rewritten', v_err IS NOT NULL, v_err);
    v_err := NULL;
    BEGIN DELETE FROM public.marche_procurement_price_observations WHERE variant_id=v_var;
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R14.H4 raw price evidence cannot be deleted', v_err IS NOT NULL, v_err);

    -- ==================== I. RECONNECT / LOST RESPONSE ====================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_rec := public.marche_order_recover('qa-n414-order-000001');
    r := r || public._qa_s13_ok('N4R14.I1 the buyer recovers its canonical order after a lost response',
          (v_rec->>'found')::boolean AND (v_rec->'order'->>'id')::uuid = v_o1, NULL);
    r := r || public._qa_s13_ok('N4R14.I2 recovery restates the frozen server total',
          (v_rec->'order'->>'merchandise_subtotal_gnf')::bigint = 22000, NULL);
    r := r || public._qa_s13_ok('N4R14.I3 recovery creates no second order',
          (SELECT count(*) FROM public.marche_orders WHERE client_request_id='qa-n414-order-000001')=1, NULL);
    r := r || public._qa_s13_ok('N4R14.I4 the landmark destination survives recovery',
          v_rec->'order'->>'destination_landmark'='pres du marche Madina', NULL);
    r := r || public._qa_s13_ok('N4R14.I5 landmark prose never invents coordinates',
          v_rec->'order'->>'dropoff_lat' IS NULL, NULL);

    -- ==================== J. BOUNDED READS ====================
    v_res := public.marche_listings_discover(NULL,NULL,NULL,NULL,5000,0);
    r := r || public._qa_s13_ok('N4R14.J1 discovery clamps a hostile page size',
          jsonb_array_length(COALESCE(v_res->'items', v_res)) <= 200,
          jsonb_array_length(COALESCE(v_res->'items', v_res))::text);
    v_res := public.marche_orders_for_buyer(100000,0);
    r := r || public._qa_s13_ok('N4R14.J2 a buyer order list stays bounded',
          jsonb_array_length(COALESCE(v_res->'items', v_res)) <= 500, NULL);

    RAISE EXCEPTION 'QA_N4R14_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_N4R14_ROLLBACK' THEN
      r := r || public._qa_s13_ok('N4R14.X fixture run raised', false, SQLERRM);
    END IF;
  END;

  PERFORM set_config('request.jwt.claims','', true);

  -- ==================== K. ZERO RESIDUE / ZERO DRIFT ====================
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

  r := r || public._qa_s13_ok('N4R14.K1 zero wallet / ledger drift',
        v_w1=v_w0 AND v_wt1=v_wt0 AND v_lj1=v_lj0 AND v_lp1=v_lp0,
        format('%s/%s/%s/%s', v_w1-v_w0, v_wt1-v_wt0, v_lj1-v_lj0, v_lp1-v_lp0));
  r := r || public._qa_s13_ok('N4R14.K2 zero payment / payable / payout drift',
        v_pi1=v_pi0 AND v_mp1=v_mp0 AND v_po1=v_po0,
        format('%s/%s/%s', v_pi1-v_pi0, v_mp1-v_mp0, v_po1-v_po0));
  r := r || public._qa_s13_ok('N4R14.K3 zero identity drift',
        v_pr1=v_pr0 AND v_au1=v_au0, format('%s/%s', v_pr1-v_pr0, v_au1-v_au0));
  r := r || public._qa_s13_ok('N4R14.K4 zero Marche order / line residue',
        v_ord1=v_ord0 AND v_oi1=v_oi0, format('%s/%s', v_ord1-v_ord0, v_oi1-v_oi0));
  r := r || public._qa_s13_ok('N4R14.K5 zero listing residue', v_ml1=v_ml0, (v_ml1-v_ml0)::text);
  r := r || public._qa_s13_ok('N4R14.K6 zero store residue', v_st1=v_st0, (v_st1-v_st0)::text);
  r := r || public._qa_s13_ok('N4R14.K7 zero procurement residue', v_pm1=v_pm0, (v_pm1-v_pm0)::text);
  r := r || public._qa_s13_ok('N4R14.K8 zero price observation residue', v_ob1=v_ob0, (v_ob1-v_ob0)::text);
  r := r || public._qa_s13_ok('N4R14.K9 zero reputation residue', v_re1=v_re0, (v_re1-v_re0)::text);
  r := r || public._qa_s13_ok('N4R14.K10 zero ops case / event / control residue',
        v_cs1=v_cs0 AND v_ev1=v_ev0 AND v_ct1=v_ct0,
        format('%s/%s/%s', v_cs1-v_cs0, v_ev1-v_ev0, v_ct1-v_ct0));
  r := r || public._qa_s13_ok('N4R14.K11 feature flags byte-identical', v_flags1=v_flags0, NULL);
  SELECT count(*) INTO v_n FROM public.merchant_stores WHERE slug LIKE 'qa-n414-%';
  r := r || public._qa_s13_ok('N4R14.K12 zero store fixture residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marketplace_listings WHERE title LIKE 'QA N414%';
  r := r || public._qa_s13_ok('N4R14.K13 zero listing fixture residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_orders WHERE client_request_id LIKE 'qa-n414-%';
  r := r || public._qa_s13_ok('N4R14.K14 zero order fixture residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_ops_cases WHERE reason_code LIKE 'qa_n414%';
  r := r || public._qa_s13_ok('N4R14.K15 zero ops case fixture residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_staple_commodities WHERE code LIKE 'qa_n414%';
  r := r || public._qa_s13_ok('N4R14.K16 zero staple catalog fixture residue', v_n=0, v_n::text);
  v_n := public._qa_n4r12_orphan_admins()::int;
  r := r || public._qa_s13_ok('N4R14.K17 zero orphan admin fixture residue', v_n=0, v_n::text);

  RETURN r;
END
$fn$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r14() FROM PUBLIC;
REVOKE ALL ON FUNCTION public._qa_node4_marche_r14() FROM anon;
REVOKE ALL ON FUNCTION public._qa_node4_marche_r14() FROM authenticated;