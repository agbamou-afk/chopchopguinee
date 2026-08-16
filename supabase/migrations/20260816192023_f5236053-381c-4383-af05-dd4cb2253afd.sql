
CREATE OR REPLACE FUNCTION public._qa_node4_marche_r2()
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public'
AS $fn$
DECLARE
  r jsonb := '[]'::jsonb;
  v_merch uuid; v_merch2 uuid; v_buyer uuid; v_other uuid; v_adm uuid; v_pend uuid; v_demo uuid; v_ban uuid;
  v_store uuid; v_store2 uuid; v_pstore uuid; v_dstore uuid; v_bstore uuid;
  l_ok uuid; l_s2 uuid; l_paused uuid; l_oos uuid; l_pend uuid; l_demo uuid; l_ban uuid;
  l_fixed uuid; l_legacy uuid;
  o1 uuid; o2 uuid; o3 uuid; o4 uuid; o5 uuid;
  v_err text; v_n int; v_o public.marketplace_offers; v_j jsonb; v_src text;
  v_flags0 jsonb; v_flags1 jsonb;
  v_w0 bigint; v_w1 bigint; v_wt0 bigint; v_wt1 bigint; v_lj0 bigint; v_lj1 bigint;
  v_ms0 bigint; v_ms1 bigint; v_pi0 bigint; v_pi1 bigint;
  v_total0 bigint; v_total1 bigint; v_demo0 bigint; v_demo1 bigint;
  v_less0 bigint; v_less1 bigint;
BEGIN
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;
  SELECT count(*) INTO v_w0  FROM public.wallets;
  SELECT count(*) INTO v_wt0 FROM public.wallet_transactions;
  SELECT count(*) INTO v_lj0 FROM public.ledger_journals;
  SELECT count(*) INTO v_ms0 FROM public.missions;
  SELECT count(*) INTO v_pi0 FROM public.payment_intents;
  SELECT count(*) INTO v_total0 FROM public.marketplace_listings;
  SELECT count(*) INTO v_demo0 FROM public.v_marche_listing_truth WHERE is_demo;
  SELECT count(*) INTO v_less0 FROM public.marketplace_listings WHERE store_id IS NULL;

  -- ================= A. STATIC CONSTITUTION =================
  r := r || public._qa_s13_ok('N4R2.A1 offer status is constrained at table level',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conname='marketplace_offers_status_chk'), NULL);
  r := r || public._qa_s13_ok('N4R2.A2 transition guard trigger installed',
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_marche_offer_transition_guard'
                AND tgrelid='public.marketplace_offers'::regclass AND NOT tgisinternal), NULL);
  SELECT prosrc INTO v_src FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='create_marketplace_offer';
  r := r || public._qa_s13_ok('N4R2.A3 creation delegates to canonical listing truth',
        v_src LIKE '%marche_listing_truth%', NULL);
  SELECT prosrc INTO v_src FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='merchant_respond_marketplace_offer';
  r := r || public._qa_s13_ok('N4R2.A4 merchant path encodes COUNTER_AWAITS_BUYER',
        v_src LIKE '%COUNTER_AWAITS_BUYER%', NULL);
  r := r || public._qa_s13_ok('N4R2.A5 buyer response primitive exists',
        EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace
                AND proname='buyer_respond_marketplace_offer'), NULL);
  SELECT prosrc INTO v_src FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='marche_create_offer_payment_intent';
  r := r || public._qa_s13_ok('N4R2.A6 payment intent binds to agreed_amount_gnf',
        v_src LIKE '%v_amount := v_offer.agreed_amount_gnf%'
        AND v_src NOT LIKE '%COALESCE(v_offer.counter_amount_gnf%', NULL);
  SELECT prosrc INTO v_src FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='marche_complete_offer';
  r := r || public._qa_s13_ok('N4R2.A7 settlement binds to agreed_amount_gnf',
        v_src LIKE '%v_amount := v_offer.agreed_amount_gnf%'
        AND v_src NOT LIKE '%COALESCE(v_offer.counter_amount_gnf%', NULL);
  r := r || public._qa_s13_ok('N4R2.A8 direct offer writes denied to anon/authenticated',
        NOT has_table_privilege('authenticated','public.marketplace_offers','INSERT')
    AND NOT has_table_privilege('authenticated','public.marketplace_offers','UPDATE')
    AND NOT has_table_privilege('authenticated','public.marketplace_offers','DELETE')
    AND NOT has_table_privilege('anon','public.marketplace_offers','INSERT')
    AND NOT has_table_privilege('anon','public.marketplace_offers','UPDATE')
    AND NOT has_table_privilege('anon','public.marketplace_offers','DELETE'), NULL);
  r := r || public._qa_s13_ok('N4R2.A8b anon cannot read the offer table at all',
        NOT has_table_privilege('anon','public.marketplace_offers','SELECT'), NULL);
  r := r || public._qa_s13_ok('N4R2.A9 anon cannot execute offer authority',
        NOT has_function_privilege('anon','public.create_marketplace_offer(uuid,bigint,text,text)','EXECUTE')
    AND NOT has_function_privilege('anon','public.merchant_respond_marketplace_offer(uuid,text,bigint,text)','EXECUTE')
    AND NOT has_function_privilege('anon','public.buyer_respond_marketplace_offer(uuid,text,text)','EXECUTE')
    AND NOT has_function_privilege('anon','public.withdraw_marketplace_offer(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R2.A9b anon cannot execute sanitized offer reads',
        NOT has_function_privilege('anon','public.marche_offers_for_buyer(uuid,integer)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_offers_for_merchant(integer)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_offer_get(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R2.A10 has_role remains not executable by anon',
        NOT has_function_privilege('anon','public.has_role(uuid,app_role)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R2.A11 expiry sweep is service/admin only',
        NOT has_function_privilege('anon','public.marche_offer_expire_due(integer)','EXECUTE')
    AND NOT has_function_privilege('authenticated','public.marche_offer_expire_due(integer)','EXECUTE'), NULL);
  SELECT count(*) INTO v_n FROM pg_proc p
   WHERE p.pronamespace='public'::regnamespace
     AND p.proname IN ('create_marketplace_offer','merchant_respond_marketplace_offer',
                       'buyer_respond_marketplace_offer','withdraw_marketplace_offer',
                       'marche_offer_expire_due','marche_offer_get','marche_offers_for_buyer',
                       'marche_offers_for_merchant','marche_offers_admin',
                       'marche_offer_transition_guard','marche_offer_is_expired')
     AND NOT (COALESCE(array_to_string(p.proconfig,','),'') LIKE '%search_path%');
  r := r || public._qa_s13_ok('N4R2.A12 every R2 primitive pins search_path', v_n = 0, v_n::text);

  -- ================= RUNTIME =================
  BEGIN
    v_merch := gen_random_uuid(); v_merch2 := gen_random_uuid(); v_buyer := gen_random_uuid();
    v_other := gen_random_uuid(); v_adm := gen_random_uuid(); v_pend := gen_random_uuid();
    v_demo := gen_random_uuid(); v_ban := gen_random_uuid();
    PERFORM public._qa_s13_user(v_merch,'n4r2m');
    PERFORM public._qa_s13_user(v_merch2,'n4r2n');
    PERFORM public._qa_s13_user(v_buyer,'n4r2b');
    PERFORM public._qa_s13_user(v_other,'n4r2o');
    PERFORM public._qa_s13_user(v_adm,'n4r2a');
    PERFORM public._qa_s13_user(v_pend,'n4r2p');
    PERFORM public._qa_s13_user(v_ban,'n4r2x');
    PERFORM public._qa_s13_admin(v_adm);
    INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                            created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
    VALUES ('00000000-0000-0000-0000-000000000000', v_demo, 'authenticated','authenticated',
            'demo.qa-n4r2-'||substr(v_demo::text,1,8)||'@chopchop.gn','x', now(), now(),
            '{"provider":"email"}'::jsonb, '{}'::jsonb);

    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status)
      VALUES (v_merch,'qa-n4r2-a-'||substr(v_merch::text,1,8),'QA R2 Store','active','approved') RETURNING id INTO v_store;
    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status)
      VALUES (v_merch2,'qa-n4r2-b-'||substr(v_merch2::text,1,8),'QA R2 Store 2','active','approved') RETURNING id INTO v_store2;
    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status)
      VALUES (v_pend,'qa-n4r2-p-'||substr(v_pend::text,1,8),'QA R2 Pending','active','submitted') RETURNING id INTO v_pstore;
    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status)
      VALUES (v_demo,'qa-n4r2-d-'||substr(v_demo::text,1,8),'QA R2 Demo','active','approved') RETURNING id INTO v_dstore;
    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status)
      VALUES (v_ban,'qa-n4r2-x-'||substr(v_ban::text,1,8),'QA R2 Banned','active','approved') RETURNING id INTO v_bstore;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    l_ok := public.marche_listing_create(jsonb_build_object('store_id',v_store,'title','QA R2 Negotiable',
      'category','Autre','price_gnf',100000,'quantity_in_stock',5,'pricing_mode','negotiable',
      'allow_offers',true,'minimum_price_gnf',60000,'publish',true));
    l_paused := public.marche_listing_create(jsonb_build_object('store_id',v_store,'title','QA R2 Paused',
      'category','Autre','price_gnf',30000,'quantity_in_stock',2,'pricing_mode','negotiable',
      'allow_offers',true,'publish',false));
    l_oos := public.marche_listing_create(jsonb_build_object('store_id',v_store,'title','QA R2 OOS',
      'category','Autre','price_gnf',30000,'quantity_in_stock',1,'pricing_mode','negotiable',
      'allow_offers',true,'publish',true));
    PERFORM public.marche_listing_set_stock(l_oos, 0);
    l_fixed := public.marche_listing_create(jsonb_build_object('store_id',v_store,'title','QA R2 Fixed',
      'category','Autre','price_gnf',30000,'quantity_in_stock',3,'pricing_mode','fixed','publish',true));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch2), true);
    l_s2 := public.marche_listing_create(jsonb_build_object('store_id',v_store2,'title','QA R2 Store2 Item',
      'category','Autre','price_gnf',50000,'quantity_in_stock',2,'pricing_mode','negotiable',
      'allow_offers',true,'publish',true));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_pend), true);
    l_pend := public.marche_listing_create(jsonb_build_object('store_id',v_pstore,'title','QA R2 Pending Item',
      'category','Autre','price_gnf',20000,'quantity_in_stock',2,'pricing_mode','negotiable',
      'allow_offers',true,'publish',true));
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_demo), true);
    l_demo := public.marche_listing_create(jsonb_build_object('store_id',v_dstore,'title','QA R2 Demo Item',
      'category','Autre','price_gnf',20000,'quantity_in_stock',2,'pricing_mode','negotiable',
      'allow_offers',true,'publish',true));
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_ban), true);
    l_ban := public.marche_listing_create(jsonb_build_object('store_id',v_bstore,'title','QA R2 Banned Item',
      'category','Autre','price_gnf',20000,'quantity_in_stock',2,'pricing_mode','negotiable',
      'allow_offers',true,'publish',true));
    INSERT INTO public.account_bans(user_id, reason, banned_by, status)
      VALUES (v_ban, 'QA R2 fixture', v_adm, 'active');

    PERFORM set_config('marche.rpc','1', true);
    INSERT INTO public.marketplace_listings(seller_id, store_id, kind, category, title, price_gnf,
      pricing_mode, allow_offers, quantity_in_stock, status, visibility, availability)
      VALUES (v_other, NULL, 'community','Autre','QA R2 Legacy', 15000,'negotiable', true, 2,
              'active','public','available') RETURNING id INTO l_legacy;
    PERFORM set_config('marche.rpc','', true);

    -- ---------- B. CREATION UNDER CANONICAL TRUTH ----------
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buyer), true);
    o1 := public.create_marketplace_offer(l_ok, 80000, 'QA offer', 'cash');
    SELECT * INTO v_o FROM public.marketplace_offers WHERE id = o1;
    r := r || public._qa_s13_ok('N4R2.B1 offer on orderable approved-store supply is created',
          v_o.status='pending' AND v_o.current_proposer_role='buyer'
          AND v_o.offer_amount_gnf=80000 AND v_o.agreed_amount_gnf IS NULL,
          COALESCE(v_o.status,'none'));

    v_err := NULL; BEGIN PERFORM public.create_marketplace_offer(l_legacy, 10000, NULL, 'cash');
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R2.B2 storeless supply refuses with MERCHANT_STORE_REQUIRED',
          v_err = 'MERCHANT_STORE_REQUIRED', v_err);

    v_err := NULL; BEGIN PERFORM public.create_marketplace_offer(l_pend, 10000, NULL, 'cash');
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R2.B3 unapproved-store supply refuses',
          v_err IN ('LISTING_PAUSED','LISTING_PRIVATE','STORE_NOT_APPROVED'), v_err);

    UPDATE public.merchant_stores SET onboarding_status='submitted' WHERE id = v_store2;
    v_err := NULL; BEGIN PERFORM public.create_marketplace_offer(l_s2, 10000, NULL, 'cash');
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R2.B3b de-approved store refuses with STORE_NOT_APPROVED',
          v_err = 'STORE_NOT_APPROVED', v_err);
    UPDATE public.merchant_stores SET onboarding_status='approved' WHERE id = v_store2;

    v_err := NULL; BEGIN PERFORM public.create_marketplace_offer(l_paused, 10000, NULL, 'cash');
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R2.B4 paused supply refuses',
          v_err IN ('LISTING_PAUSED','LISTING_PRIVATE'), v_err);

    v_err := NULL; BEGIN PERFORM public.create_marketplace_offer(l_oos, 10000, NULL, 'cash');
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R2.B5 out-of-stock supply refuses with OUT_OF_STOCK',
          v_err = 'OUT_OF_STOCK', v_err);

    v_err := NULL; BEGIN PERFORM public.create_marketplace_offer(l_demo, 10000, NULL, 'cash');
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R2.B6 demo supply refuses with DEMO_SUPPLY',
          v_err = 'DEMO_SUPPLY', v_err);

    v_err := NULL; BEGIN PERFORM public.create_marketplace_offer(l_ban, 10000, NULL, 'cash');
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R2.B7 banned seller supply refuses with SELLER_NOT_ELIGIBLE',
          v_err = 'SELLER_NOT_ELIGIBLE', v_err);

    v_err := NULL; BEGIN PERFORM public.create_marketplace_offer(l_fixed, 10000, NULL, 'cash');
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R2.B8 fixed-price supply refuses offers', v_err = 'offers not allowed', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_err := NULL; BEGIN PERFORM public.create_marketplace_offer(l_ok, 10000, NULL, 'cash');
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R2.B9 seller cannot offer on own supply',
          v_err = 'cannot offer on own listing', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buyer), true);
    v_err := NULL; BEGIN PERFORM public.create_marketplace_offer(l_ok, 0, NULL, 'cash');
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R2.B10 zero amount refused', v_err = 'invalid amount', v_err);
    v_err := NULL; BEGIN PERFORM public.create_marketplace_offer(l_ok, -500, NULL, 'cash');
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R2.B10b negative amount refused', v_err = 'invalid amount', v_err);
    v_err := NULL; BEGIN PERFORM public.create_marketplace_offer(l_ok, 1000, NULL, 'bitcoin');
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R2.B11 invalid tender refused', v_err = 'INVALID_TENDER', v_err);
    v_err := NULL; BEGIN PERFORM public.create_marketplace_offer(l_ok, 70000, NULL, 'cash');
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R2.B12 duplicate open offer refused',
          v_err = 'pending offer already exists', v_err);

    -- ---------- C. CONSENT LAW ----------
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    PERFORM public.merchant_respond_marketplace_offer(o1, 'accept', NULL, 'ok');
    SELECT * INTO v_o FROM public.marketplace_offers WHERE id = o1;
    r := r || public._qa_s13_ok('N4R2.C1 merchant acceptance freezes the buyer amount',
          v_o.status='accepted' AND v_o.agreed_amount_gnf=80000
          AND v_o.agreed_by_user_id=v_merch AND v_o.agreed_at IS NOT NULL,
          COALESCE(v_o.agreed_amount_gnf::text,'null'));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buyer), true);
    o2 := public.create_marketplace_offer(l_s2, 30000, NULL, 'choppay');
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch2), true);
    PERFORM public.merchant_respond_marketplace_offer(o2, 'counter', 45000, 'mon dernier prix');
    SELECT * INTO v_o FROM public.marketplace_offers WHERE id = o2;
    r := r || public._qa_s13_ok('N4R2.C2 merchant counter moves proposal authority to merchant',
          v_o.status='countered' AND v_o.current_proposer_role='merchant'
          AND v_o.counter_amount_gnf=45000 AND v_o.agreed_amount_gnf IS NULL, v_o.current_proposer_role);

    v_err := NULL; BEGIN PERFORM public.merchant_respond_marketplace_offer(o2, 'accept', NULL, NULL);
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R2.C3 merchant cannot accept its own counter',
          v_err = 'COUNTER_AWAITS_BUYER', v_err);
    v_err := NULL; BEGIN PERFORM public.merchant_respond_marketplace_offer(o2, 'counter', 40000, NULL);
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R2.C4 merchant cannot rewrite a counter awaiting the buyer',
          v_err = 'COUNTER_AWAITS_BUYER', v_err);
    SELECT * INTO v_o FROM public.marketplace_offers WHERE id = o2;
    r := r || public._qa_s13_ok('N4R2.C4b counter amount unchanged after refused rewrite',
          v_o.counter_amount_gnf = 45000, v_o.counter_amount_gnf::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_other), true);
    v_err := NULL; BEGIN PERFORM public.buyer_respond_marketplace_offer(o2, 'accept', NULL);
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R2.C5 third party cannot accept a counter', v_err = 'forbidden', v_err);
    v_err := NULL; BEGIN PERFORM public.merchant_respond_marketplace_offer(o2, 'reject', NULL, NULL);
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R2.C5b third party cannot respond as merchant', v_err = 'forbidden', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buyer), true);
    PERFORM public.buyer_respond_marketplace_offer(o2, 'accept', NULL);
    SELECT * INTO v_o FROM public.marketplace_offers WHERE id = o2;
    r := r || public._qa_s13_ok('N4R2.C6 buyer acceptance freezes the merchant counter',
          v_o.status='accepted' AND v_o.agreed_amount_gnf=45000
          AND v_o.agreed_by_user_id=v_buyer AND v_o.agreed_at IS NOT NULL,
          COALESCE(v_o.agreed_amount_gnf::text,'null'));

    o3 := public.create_marketplace_offer(l_ok, 70000, NULL, 'cash');
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    PERFORM public.merchant_respond_marketplace_offer(o3, 'counter', 90000, NULL);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buyer), true);
    PERFORM public.buyer_respond_marketplace_offer(o3, 'reject', 'trop cher');
    SELECT * INTO v_o FROM public.marketplace_offers WHERE id = o3;
    r := r || public._qa_s13_ok('N4R2.C7 buyer rejection of a counter is terminal',
          v_o.status='rejected' AND v_o.agreed_amount_gnf IS NULL, v_o.status);

    o4 := public.create_marketplace_offer(l_ok, 65000, NULL, 'cash');
    v_err := NULL; BEGIN PERFORM public.buyer_respond_marketplace_offer(o4, 'accept', NULL);
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R2.C8 buyer cannot accept its own pending proposal',
          v_err = 'NO_MERCHANT_PROPOSAL', v_err);

    PERFORM public.withdraw_marketplace_offer(o4);
    SELECT * INTO v_o FROM public.marketplace_offers WHERE id = o4;
    r := r || public._qa_s13_ok('N4R2.C9 buyer withdrawal works while open', v_o.status='withdrawn', v_o.status);
    v_err := NULL; BEGIN PERFORM public.withdraw_marketplace_offer(o4);
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R2.C9b withdrawal of a terminal offer refused', v_err = 'offer closed', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_err := NULL; BEGIN PERFORM public.merchant_respond_marketplace_offer(o1, 'reject', NULL, NULL);
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R2.C10 accepted offers cannot be re-responded', v_err = 'offer closed', v_err);

    PERFORM set_config('request.jwt.claims', '', true);
    v_err := NULL; BEGIN UPDATE public.marketplace_offers SET status='pending' WHERE id = o1;
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R2.C11 terminal state cannot be reopened even server-side',
          v_err = 'OFFER_TERMINAL', v_err);
    v_err := NULL; BEGIN UPDATE public.marketplace_offers SET agreed_amount_gnf = 1 WHERE id = o1;
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R2.C12 frozen agreement amount is immutable',
          v_err = 'AGREEMENT_IMMUTABLE', v_err);
    v_err := NULL; BEGIN UPDATE public.marketplace_offers SET agreed_by_user_id = v_other WHERE id = o1;
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R2.C12b frozen agreement author is immutable',
          v_err = 'AGREEMENT_IMMUTABLE', v_err);
    v_err := NULL; BEGIN UPDATE public.marketplace_offers SET offer_amount_gnf = 5 WHERE id = o1;
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R2.C12c original proposal amount is immutable',
          v_err = 'OFFER_CORE_IMMUTABLE', v_err);
    v_err := NULL; BEGIN UPDATE public.marketplace_offers SET status='accepted' WHERE id = o3;
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R2.C13 rejected offer cannot become accepted', v_err = 'OFFER_TERMINAL', v_err);

    -- ---------- D. EXPIRY ----------
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buyer), true);
    o5 := public.create_marketplace_offer(l_ok, 61000, NULL, 'cash');
    UPDATE public.marketplace_offers SET expires_at = now() - interval '1 day' WHERE id = o5;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_err := NULL; BEGIN PERFORM public.merchant_respond_marketplace_offer(o5, 'accept', NULL, NULL);
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R2.D1 a due offer cannot be accepted before the sweep runs',
          v_err = 'OFFER_EXPIRED', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buyer), true);
    v_err := NULL; BEGIN PERFORM public.marche_create_offer_payment_intent(o5);
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R2.D2 a due offer cannot be paid', v_err = 'offer_expired', v_err);

    PERFORM set_config('request.jwt.claims','',true);
    UPDATE public.marketplace_offers SET expires_at = now() - interval '2 days' WHERE id = o1;
    v_j := public.marche_offer_expire_due(100);
    SELECT * INTO v_o FROM public.marketplace_offers WHERE id = o5;
    r := r || public._qa_s13_ok('N4R2.D3 sweep expires due open offers',
          v_o.status='expired' AND v_o.expired_at IS NOT NULL, v_o.status);
    SELECT * INTO v_o FROM public.marketplace_offers WHERE id = o1;
    r := r || public._qa_s13_ok('N4R2.D4 accepted offers never expire', v_o.status='accepted', v_o.status);
    v_j := public.marche_offer_expire_due(100);
    r := r || public._qa_s13_ok('N4R2.D5 sweep is idempotent', (v_j->>'expired')::int = 0, v_j::text);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_err := NULL; BEGIN PERFORM public.merchant_respond_marketplace_offer(o5, 'accept', NULL, NULL);
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R2.D6 an expired offer cannot be accepted', v_err = 'offer closed', v_err);
    v_n := public._qa_node4_probe('authenticated', v_buyer,
      'SELECT count(*)::int FROM public.marche_offer_expire_due(10)');
    r := r || public._qa_s13_ok('N4R2.D7 ordinary users cannot run the expiry sweep', v_n = -1, v_n::text);

    -- ---------- E. AUTHORITY AND SANITIZED READS ----------
    v_n := public._qa_node4_probe('authenticated', v_buyer,
      format('UPDATE public.marketplace_offers SET status=''accepted'' WHERE id=%L RETURNING 1', o5));
    r := r || public._qa_s13_ok('N4R2.E1 direct offer UPDATE denied to signed-in users', v_n = -1, v_n::text);
    v_n := public._qa_node4_probe('authenticated', v_buyer,
      format('DELETE FROM public.marketplace_offers WHERE id=%L RETURNING 1', o5));
    r := r || public._qa_s13_ok('N4R2.E2 direct offer DELETE denied to signed-in users', v_n = -1, v_n::text);
    v_n := public._qa_node4_probe('authenticated', v_buyer,
      format('INSERT INTO public.marketplace_offers(listing_id,buyer_user_id,merchant_user_id,offer_amount_gnf) VALUES (%L,%L,%L,1) RETURNING 1',
             l_ok, v_buyer, v_merch));
    r := r || public._qa_s13_ok('N4R2.E3 direct offer INSERT denied to signed-in users', v_n = -1, v_n::text);
    v_n := public._qa_node4_probe('anon', NULL, 'SELECT count(*)::int FROM public.marketplace_offers');
    r := r || public._qa_s13_ok('N4R2.E4 anon cannot enumerate offers', v_n = -1, v_n::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buyer), true);
    SELECT count(*) INTO v_n FROM public.marche_offers_for_buyer(NULL, 100);
    r := r || public._qa_s13_ok('N4R2.E5 buyer sees own offers through the sanitized read', v_n >= 5, v_n::text);
    SELECT count(*) INTO v_n FROM public.marche_offers_for_buyer(NULL, 100) x
     WHERE (x->>'buyer_user_id')::uuid <> v_buyer;
    r := r || public._qa_s13_ok('N4R2.E5b buyer read leaks no other buyer', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.marche_offers_for_merchant(100);
    r := r || public._qa_s13_ok('N4R2.E5c buyer sees no merchant queue', v_n = 0, v_n::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    SELECT count(*) INTO v_n FROM public.marche_offers_for_merchant(100) x
     WHERE (x->>'merchant_user_id')::uuid = v_merch;
    r := r || public._qa_s13_ok('N4R2.E6 merchant sees own store offers', v_n >= 4, v_n::text);
    SELECT count(*) INTO v_n FROM public.marche_offers_for_merchant(100) x
     WHERE (x->>'merchant_user_id')::uuid <> v_merch;
    r := r || public._qa_s13_ok('N4R2.E6b merchant read leaks no other merchant', v_n = 0, v_n::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_other), true);
    r := r || public._qa_s13_ok('N4R2.E7 third party cannot read a single offer',
          public.marche_offer_get(o1) IS NULL, NULL);
    SELECT count(*) INTO v_n FROM public.marche_offers_admin(200);
    r := r || public._qa_s13_ok('N4R2.E7b non-admin gets no admin offer feed', v_n = 0, v_n::text);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_adm), true);
    SELECT count(*) INTO v_n FROM public.marche_offers_admin(200);
    r := r || public._qa_s13_ok('N4R2.E8 admin reads the full offer feed', v_n >= 5, v_n::text);
    v_j := public.marche_offer_get(o1);
    r := r || public._qa_s13_ok('N4R2.E9 sanitized payload exposes the agreement',
          (v_j->>'agreed_amount_gnf')::bigint = 80000, v_j->>'agreed_amount_gnf');
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buyer), true);
    v_j := public.marche_offer_get(o1);
    r := r || public._qa_s13_ok('N4R2.E10 sanitized payload never carries the secret floor price',
          NOT (v_j ? 'minimum_price_gnf'), NULL);

    -- ---------- F. MONEY LINKAGE (no money side effects) ----------
    v_err := NULL; BEGIN PERFORM public.marche_create_offer_payment_intent(o3);
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R2.F1 payment refused on a rejected offer', v_err = 'offer_not_accepted', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_other), true);
    v_err := NULL; BEGIN PERFORM public.marche_create_offer_payment_intent(o2);
      EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R2.F2 payment refused to a non-buyer', v_err = 'forbidden_not_buyer', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buyer), true);
    v_j := public.marche_complete_offer(o3, 'QA');
    r := r || public._qa_s13_ok('N4R2.F3 completion refused on a non-accepted offer',
          (v_j->>'ok')::boolean = false AND v_j->>'reason' = 'offer_not_accepted', v_j::text);
    v_j := public.marche_complete_offer(o2, 'QA');
    r := r || public._qa_s13_ok('N4R2.F4 completion without an authorized intent creates no money',
          (v_j->>'ok')::boolean = false AND v_j->>'reason' = 'no_payment_intent', v_j::text);
    SELECT count(*) INTO v_n FROM public.payment_intents WHERE source_module='marketplace'
      AND source_id IN (o1,o2,o3,o4,o5);
    r := r || public._qa_s13_ok('N4R2.F5 no payment intent was created by QA', v_n = 0, v_n::text);

  EXCEPTION WHEN OTHERS THEN
    r := r || public._qa_s13_ok('N4R2.FIXTURE runtime block completed without unhandled error', false, SQLERRM);
  END;

  -- ================= CLEANUP =================
  PERFORM set_config('request.jwt.claims', '', true);
  DELETE FROM public.marketplace_offers
   WHERE buyer_user_id IN (v_buyer, v_other, v_merch, v_merch2, v_adm)
      OR merchant_user_id IN (v_merch, v_merch2, v_pend, v_demo, v_ban, v_other);
  DELETE FROM public.listing_images WHERE listing_id IN
    (SELECT id FROM public.marketplace_listings WHERE seller_id IN (v_merch,v_merch2,v_pend,v_demo,v_ban,v_other,v_buyer,v_adm));
  DELETE FROM public.listing_metrics WHERE listing_id IN
    (SELECT id FROM public.marketplace_listings WHERE seller_id IN (v_merch,v_merch2,v_pend,v_demo,v_ban,v_other,v_buyer,v_adm));
  DELETE FROM public.marketplace_listings WHERE seller_id IN (v_merch,v_merch2,v_pend,v_demo,v_ban,v_other,v_buyer,v_adm);
  DELETE FROM public.account_bans WHERE user_id IN (v_merch,v_merch2,v_pend,v_demo,v_ban,v_other,v_buyer,v_adm);
  DELETE FROM public.merchant_stores WHERE owner_user_id IN (v_merch,v_merch2,v_pend,v_demo,v_ban);
  DELETE FROM public.admin_users WHERE user_id = v_adm;
  DELETE FROM public.wallet_transactions
   WHERE from_wallet_id IN (SELECT id FROM public.wallets WHERE owner_user_id IN (v_merch,v_merch2,v_pend,v_demo,v_ban,v_other,v_buyer,v_adm))
      OR to_wallet_id   IN (SELECT id FROM public.wallets WHERE owner_user_id IN (v_merch,v_merch2,v_pend,v_demo,v_ban,v_other,v_buyer,v_adm));
  DELETE FROM public.wallets WHERE owner_user_id IN (v_merch,v_merch2,v_pend,v_demo,v_ban,v_other,v_buyer,v_adm);
  DELETE FROM auth.users WHERE id IN (v_merch,v_merch2,v_pend,v_demo,v_ban,v_other,v_buyer,v_adm);

  -- ================= SYSTEMIC =================
  SELECT count(*) INTO v_w1  FROM public.wallets;
  SELECT count(*) INTO v_wt1 FROM public.wallet_transactions;
  SELECT count(*) INTO v_lj1 FROM public.ledger_journals;
  SELECT count(*) INTO v_ms1 FROM public.missions;
  SELECT count(*) INTO v_pi1 FROM public.payment_intents;
  SELECT count(*) INTO v_total1 FROM public.marketplace_listings;
  SELECT count(*) INTO v_demo1 FROM public.v_marche_listing_truth WHERE is_demo;
  SELECT count(*) INTO v_less1 FROM public.marketplace_listings WHERE store_id IS NULL;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;

  r := r || public._qa_s13_ok('N4R2.S1 no wallet / ledger / mission / payment drift',
        v_w1=v_w0 AND v_wt1=v_wt0 AND v_lj1=v_lj0 AND v_ms1=v_ms0 AND v_pi1=v_pi0,
        format('%s/%s/%s/%s/%s', v_w1-v_w0, v_wt1-v_wt0, v_lj1-v_lj0, v_ms1-v_ms0, v_pi1-v_pi0));
  r := r || public._qa_s13_ok('N4R2.S2 feature flags byte-identical', v_flags1 = v_flags0, NULL);
  r := r || public._qa_s13_ok('N4R2.S3 listing population unchanged', v_total1 = v_total0,
        format('%s->%s', v_total0, v_total1));
  r := r || public._qa_s13_ok('N4R2.S4 demo quarantine unchanged', v_demo1 = v_demo0 AND v_demo1 > 0, v_demo1::text);
  r := r || public._qa_s13_ok('N4R2.S4b storeless quarantine unchanged', v_less1 = v_less0, v_less1::text);
  SELECT count(*) INTO v_n FROM public.marketplace_offers o
   WHERE NOT EXISTS (SELECT 1 FROM public.marketplace_listings l WHERE l.id = o.listing_id);
  r := r || public._qa_s13_ok('N4R2.S5 zero orphan offer residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marketplace_listings WHERE title LIKE 'QA R2%';
  r := r || public._qa_s13_ok('N4R2.S5b zero listing fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.merchant_stores WHERE slug LIKE 'qa-n4r2-%';
  r := r || public._qa_s13_ok('N4R2.S5c zero store fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM auth.users WHERE id IN (v_merch,v_merch2,v_pend,v_demo,v_ban,v_other,v_buyer,v_adm);
  r := r || public._qa_s13_ok('N4R2.S5d zero auth fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.v_marche_listing_truth WHERE is_orderable AND store_id IS NULL;
  r := r || public._qa_s13_ok('N4R2.S6 R1.5 doctrine intact after R2', v_n = 0, v_n::text);

  RETURN public._qa_s13_summary(40, r);
END $fn$;

GRANT EXECUTE ON FUNCTION public._qa_node4_marche_r2() TO service_role;
