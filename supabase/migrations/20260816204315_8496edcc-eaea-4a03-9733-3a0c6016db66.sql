DROP FUNCTION IF EXISTS public._qa_n435_fixture_store_nc(uuid,text);

CREATE OR REPLACE FUNCTION public._qa_node4_marche_r35()
RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'public' AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_buy uuid; v_merch uuid; v_adm uuid; v_store uuid; v_store_nc uuid;
  l_a uuid; l_b uuid; l_bulk uuid; l_nc uuid;
  v_o uuid; v_o2 uuid; v_onc uuid; v_oneg uuid; v_ord public.marche_orders;
  p public.marche_fulfillment_profiles; v_res jsonb; v_res2 jsonb;
  v_err text; v_n int; v_i int; v_ids uuid[] := '{}'; v_tmp uuid; v_stats jsonb; v_row jsonb;
  v_keys text; v_now timestamptz := now();
  v_flags0 jsonb; v_flags1 jsonb;
  v_w0 bigint; v_w1 bigint; v_wt0 bigint; v_wt1 bigint; v_lj0 bigint; v_lj1 bigint;
  v_ms0 bigint; v_ms1 bigint; v_pi0 bigint; v_pi1 bigint; v_lp0 bigint; v_lp1 bigint;
  v_fp0 bigint; v_fp1 bigint; v_ev0 bigint; v_ev1 bigint; v_ob0 bigint; v_ob1 bigint;
  v_total0 bigint; v_total1 bigint; v_none0 bigint; v_none1 bigint; v_reserved0 bigint; v_reserved1 bigint;
  v_src text;
BEGIN
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;
  SELECT count(*) INTO v_w0 FROM public.wallets;
  SELECT count(*) INTO v_wt0 FROM public.wallet_transactions;
  SELECT count(*) INTO v_lj0 FROM public.ledger_journals;
  SELECT count(*) INTO v_ms0 FROM public.missions;
  SELECT count(*) INTO v_pi0 FROM public.payment_intents;
  SELECT count(*) INTO v_lp0 FROM public.ledger_postings;
  SELECT count(*) INTO v_total0 FROM public.marketplace_listings;
  SELECT count(*) INTO v_none0 FROM public.marketplace_listings WHERE store_id IS NULL;
  SELECT COALESCE(sum(quantity_reserved),0) INTO v_reserved0 FROM public.marketplace_listings;
  SELECT count(*) INTO v_fp0 FROM public.marche_fulfillment_profiles;
  SELECT count(*) INTO v_ev0 FROM public.marche_fulfillment_events;
  SELECT count(*) INTO v_ob0 FROM public.marche_fulfillment_observations;

  -- ================= A. STRUCTURAL LAW =================
  r := r || public._qa_s13_ok('N4R35.A1 basket profile table exists',
        to_regclass('public.marche_fulfillment_profiles') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N4R35.A2 raw event table exists',
        to_regclass('public.marche_fulfillment_events') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N4R35.A3 derived observation table exists',
        to_regclass('public.marche_fulfillment_observations') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N4R35.A4 order lines carry immutable category snapshot',
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                 AND table_name='marche_order_items' AND column_name='category_snapshot'), NULL);
  r := r || public._qa_s13_ok('N4R35.A5 profile is one row per order (PK on order_id)',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.marche_fulfillment_profiles'::regclass
                 AND contype='p'), NULL);
  r := r || public._qa_s13_ok('N4R35.A6 event idempotency key is unique',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conname='marche_event_unique_source'), NULL);
  r := r || public._qa_s13_ok('N4R35.A7 observation unique per (order, metric)',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conname='marche_obs_unique'), NULL);
  r := r || public._qa_s13_ok('N4R35.A8 distance honesty constraint present',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conname='marche_profile_distance_honest'), NULL);
  r := r || public._qa_s13_ok('N4R35.A9 negative durations structurally impossible',
        (SELECT count(*) FROM pg_constraint WHERE conrelid='public.marche_fulfillment_observations'::regclass
          AND contype='c' AND pg_get_constraintdef(oid) LIKE '%duration_seconds >= 0%') = 1, NULL);
  r := r || public._qa_s13_ok('N4R35.A10 canonical event vocabulary reserved',
        (SELECT bool_and(pg_get_constraintdef(oid) LIKE '%ORDER_COMMITTED%'
            AND pg_get_constraintdef(oid) LIKE '%MERCHANT_ACCEPTED%'
            AND pg_get_constraintdef(oid) LIKE '%MERCHANT_READY%'
            AND pg_get_constraintdef(oid) LIKE '%COURIER_ENGAGED%'
            AND pg_get_constraintdef(oid) LIKE '%COURIER_AT_STORE%'
            AND pg_get_constraintdef(oid) LIKE '%SHOPPING_STARTED%'
            AND pg_get_constraintdef(oid) LIKE '%SHOPPING_COMPLETED%'
            AND pg_get_constraintdef(oid) LIKE '%PICKED_UP%'
            AND pg_get_constraintdef(oid) LIKE '%DELIVERED%')
         FROM pg_constraint WHERE conrelid='public.marche_fulfillment_events'::regclass
          AND contype='c' AND pg_get_constraintdef(oid) LIKE '%event_type%'), NULL);
  r := r || public._qa_s13_ok('N4R35.A11 canonical interval vocabulary reserved',
        (SELECT bool_and(pg_get_constraintdef(oid) LIKE '%COMMIT_TO_MERCHANT_ACCEPTED%'
            AND pg_get_constraintdef(oid) LIKE '%MERCHANT_ACCEPTED_TO_READY%'
            AND pg_get_constraintdef(oid) LIKE '%COURIER_ENGAGED_TO_STORE_ARRIVAL%'
            AND pg_get_constraintdef(oid) LIKE '%SHOPPING_START_TO_COMPLETE%'
            AND pg_get_constraintdef(oid) LIKE '%PICKUP_TO_DELIVERED%'
            AND pg_get_constraintdef(oid) LIKE '%COMMIT_TO_DELIVERED%')
         FROM pg_constraint WHERE conrelid='public.marche_fulfillment_observations'::regclass
          AND contype='c' AND pg_get_constraintdef(oid) LIKE '%metric_name%'), NULL);
  r := r || public._qa_s13_ok('N4R35.A12 fulfillment_mode vocabulary constrained',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.marche_fulfillment_profiles'::regclass
                 AND contype='c' AND pg_get_constraintdef(oid) LIKE '%unspecified%'), NULL);
  r := r || public._qa_s13_ok('N4R35.A13 cohort index exists on observations',
        EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='idx_mfo_cohort'), NULL);
  r := r || public._qa_s13_ok('N4R35.A14 event lookup index exists',
        EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='idx_mfe_order'), NULL);
  r := r || public._qa_s13_ok('N4R35.A15 RLS enabled on all three R3.5 tables',
        (SELECT bool_and(relrowsecurity) FROM pg_class WHERE oid IN (
          'public.marche_fulfillment_profiles'::regclass,
          'public.marche_fulfillment_events'::regclass,
          'public.marche_fulfillment_observations'::regclass)), NULL);
  r := r || public._qa_s13_ok('N4R35.A16 raw distance retained alongside bucketing',
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                 AND table_name='marche_fulfillment_observations' AND column_name='distance_m')
    AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                 AND table_name='marche_fulfillment_observations' AND column_name='distance_bucket'), NULL);
  r := r || public._qa_s13_ok('N4R35.A17 raw basket dimensions retained alongside bucketing',
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                 AND table_name='marche_fulfillment_observations' AND column_name='basket_units')
    AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                 AND table_name='marche_fulfillment_observations' AND column_name='basket_bucket'), NULL);
  r := r || public._qa_s13_ok('N4R35.A18 weight/bulk readiness columns exist and are nullable',
        (SELECT count(*) FROM information_schema.columns WHERE table_schema='public'
          AND table_name='marche_fulfillment_profiles'
          AND column_name IN ('weight_grams','bulk_complexity') AND is_nullable='YES') = 2, NULL);
  r := r || public._qa_s13_ok('N4R35.A19 occurred_at (truth) and created_at (ingestion) both recorded',
        (SELECT count(*) FROM information_schema.columns WHERE table_schema='public'
          AND table_name='marche_fulfillment_events'
          AND column_name IN ('occurred_at','created_at')) = 2, NULL);
  r := r || public._qa_s13_ok('N4R35.A20 event provenance columns exist',
        (SELECT count(*) FROM information_schema.columns WHERE table_schema='public'
          AND table_name='marche_fulfillment_events'
          AND column_name IN ('source_type','source_id','source_key','actor_role')) = 4, NULL);

  r := r || public._qa_s13_ok('N4R35.B1 profile table not readable/writable by anon',
        NOT has_table_privilege('anon','public.marche_fulfillment_profiles','SELECT')
    AND NOT has_table_privilege('anon','public.marche_fulfillment_profiles','INSERT')
    AND NOT has_table_privilege('anon','public.marche_fulfillment_profiles','UPDATE')
    AND NOT has_table_privilege('anon','public.marche_fulfillment_profiles','DELETE'), NULL);
  r := r || public._qa_s13_ok('N4R35.B2 profile table not readable/writable by authenticated',
        NOT has_table_privilege('authenticated','public.marche_fulfillment_profiles','SELECT')
    AND NOT has_table_privilege('authenticated','public.marche_fulfillment_profiles','INSERT')
    AND NOT has_table_privilege('authenticated','public.marche_fulfillment_profiles','UPDATE')
    AND NOT has_table_privilege('authenticated','public.marche_fulfillment_profiles','DELETE'), NULL);
  r := r || public._qa_s13_ok('N4R35.B3 event table denied to anon',
        NOT has_table_privilege('anon','public.marche_fulfillment_events','SELECT')
    AND NOT has_table_privilege('anon','public.marche_fulfillment_events','INSERT')
    AND NOT has_table_privilege('anon','public.marche_fulfillment_events','UPDATE')
    AND NOT has_table_privilege('anon','public.marche_fulfillment_events','DELETE'), NULL);
  r := r || public._qa_s13_ok('N4R35.B4 event table denied to authenticated',
        NOT has_table_privilege('authenticated','public.marche_fulfillment_events','SELECT')
    AND NOT has_table_privilege('authenticated','public.marche_fulfillment_events','INSERT')
    AND NOT has_table_privilege('authenticated','public.marche_fulfillment_events','UPDATE')
    AND NOT has_table_privilege('authenticated','public.marche_fulfillment_events','DELETE'), NULL);
  r := r || public._qa_s13_ok('N4R35.B5 observation table denied to anon',
        NOT has_table_privilege('anon','public.marche_fulfillment_observations','SELECT')
    AND NOT has_table_privilege('anon','public.marche_fulfillment_observations','INSERT'), NULL);
  r := r || public._qa_s13_ok('N4R35.B6 observation table denied to authenticated',
        NOT has_table_privilege('authenticated','public.marche_fulfillment_observations','SELECT')
    AND NOT has_table_privilege('authenticated','public.marche_fulfillment_observations','INSERT')
    AND NOT has_table_privilege('authenticated','public.marche_fulfillment_observations','UPDATE')
    AND NOT has_table_privilege('authenticated','public.marche_fulfillment_observations','DELETE'), NULL);
  r := r || public._qa_s13_ok('N4R35.B7 ordinary clients cannot append fulfillment events',
        NOT has_function_privilege('authenticated','public.marche_fulfillment_event_append(uuid,text,timestamptz,text,text,text,text)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_fulfillment_event_append(uuid,text,timestamptz,text,text,text,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R35.B8 ordinary clients cannot manufacture profiles',
        NOT has_function_privilege('authenticated','public.marche_fulfillment_profile_create(uuid)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_fulfillment_profile_create(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R35.B9 ordinary clients cannot force observation recomputation',
        NOT has_function_privilege('authenticated','public.marche_fulfillment_recompute_observations(uuid)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_fulfillment_recompute_observations(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R35.B10 ordinary clients cannot declare fulfillment mode',
        NOT has_function_privilege('authenticated','public.marche_fulfillment_set_mode(uuid,text,text)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_fulfillment_set_mode(uuid,text,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R35.B11 anon cannot reach any R3.5 admin read',
        NOT has_function_privilege('anon','public.marche_fulfillment_profile_admin(uuid)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_fulfillment_events_admin(uuid)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_fulfillment_observations_admin(text,integer)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_fulfillment_cohorts_admin(text,text,text,text,boolean)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R35.B12 anon cannot reach raw cohort statistics',
        NOT has_function_privilege('anon','public.marche_fulfillment_cohort_stats(text,text,text,text,boolean)','EXECUTE')
    AND NOT has_function_privilege('authenticated','public.marche_fulfillment_cohort_stats(text,text,text,text,boolean)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R35.B13 has_role still not executable by anon',
        NOT has_function_privilege('anon','public.has_role(uuid,app_role)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R35.B14 every R3.5 definer function pins search_path',
        (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace
          AND proname LIKE 'marche_fulfillment%' AND prosecdef
          AND proconfig::text LIKE '%search_path=public%')
        = (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace
            AND proname LIKE 'marche_fulfillment%' AND prosecdef), NULL);
  r := r || public._qa_s13_ok('N4R35.B15 R3.5 definer surface is non-empty',
        (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace
          AND proname LIKE 'marche_fulfillment%' AND prosecdef) >= 6, NULL);
  r := r || public._qa_s13_ok('N4R35.B16 no buyer identity column on profiles',
        NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
          AND table_name='marche_fulfillment_profiles'
          AND (column_name LIKE '%buyer%' OR column_name LIKE '%user_id%'
            OR column_name LIKE '%email%' OR column_name LIKE '%phone%')), NULL);
  r := r || public._qa_s13_ok('N4R35.B17 no buyer identity column on events',
        NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
          AND table_name='marche_fulfillment_events'
          AND (column_name LIKE '%buyer%' OR column_name LIKE '%email%' OR column_name LIKE '%phone%')), NULL);
  r := r || public._qa_s13_ok('N4R35.B18 no buyer identity column on observations',
        NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
          AND table_name='marche_fulfillment_observations'
          AND (column_name LIKE '%buyer%' OR column_name LIKE '%user_id%'
            OR column_name LIKE '%email%' OR column_name LIKE '%phone%')), NULL);
  r := r || public._qa_s13_ok('N4R35.B19 no money column on any R3.5 table',
        NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
          AND table_name LIKE 'marche_fulfillment%'
          AND (column_name LIKE '%gnf%' OR column_name LIKE '%fee%' OR column_name LIKE '%price%'
            OR column_name LIKE '%payout%' OR column_name LIKE '%amount%')), NULL);
  r := r || public._qa_s13_ok('N4R35.B20 no prediction/ETA column on any R3.5 table',
        NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
          AND table_name LIKE 'marche_fulfillment%'
          AND (column_name LIKE '%eta%' OR column_name LIKE '%predict%'
            OR column_name LIKE '%estimate%' OR column_name LIKE '%forecast%')), NULL);

  r := r || public._qa_s13_ok('N4R35.C1 distance bucket: unknown when unmeasured',
        public.marche_distance_bucket(NULL) = 'unknown', NULL);
  r := r || public._qa_s13_ok('N4R35.C2 distance bucket 0-1km lower edge',
        public.marche_distance_bucket(0) = '0-1km', NULL);
  r := r || public._qa_s13_ok('N4R35.C3 distance bucket 0-1km upper edge',
        public.marche_distance_bucket(999.9) = '0-1km', NULL);
  r := r || public._qa_s13_ok('N4R35.C4 distance bucket 1-3km boundary',
        public.marche_distance_bucket(1000) = '1-3km' AND public.marche_distance_bucket(2999) = '1-3km', NULL);
  r := r || public._qa_s13_ok('N4R35.C5 distance bucket 3-7km boundary',
        public.marche_distance_bucket(3000) = '3-7km' AND public.marche_distance_bucket(6999) = '3-7km', NULL);
  r := r || public._qa_s13_ok('N4R35.C6 distance bucket 7-15km boundary',
        public.marche_distance_bucket(7000) = '7-15km' AND public.marche_distance_bucket(14999) = '7-15km', NULL);
  r := r || public._qa_s13_ok('N4R35.C7 distance bucket 15km+ boundary',
        public.marche_distance_bucket(15000) = '15km+', NULL);
  r := r || public._qa_s13_ok('N4R35.C8 basket bucket single',
        public.marche_basket_bucket(1,1) = 'single', NULL);
  r := r || public._qa_s13_ok('N4R35.C9 basket bucket small',
        public.marche_basket_bucket(2,1) = 'small' AND public.marche_basket_bucket(5,3) = 'small', NULL);
  r := r || public._qa_s13_ok('N4R35.C10 basket bucket medium',
        public.marche_basket_bucket(6,2) = 'medium' AND public.marche_basket_bucket(15,9) = 'medium', NULL);
  r := r || public._qa_s13_ok('N4R35.C11 basket bucket large',
        public.marche_basket_bucket(16,4) = 'large', NULL);
  r := r || public._qa_s13_ok('N4R35.C12 basket bucket empty',
        public.marche_basket_bucket(0,0) = 'empty', NULL);
  r := r || public._qa_s13_ok('N4R35.C13 multi-unit single product is not "single"',
        public.marche_basket_bucket(3,1) = 'small', NULL);
  r := r || public._qa_s13_ok('N4R35.C14 freshness none when never observed',
        public.marche_fulfillment_freshness(NULL) = 'none', NULL);
  r := r || public._qa_s13_ok('N4R35.C15 freshness fresh under 7 days',
        public.marche_fulfillment_freshness(now() - interval '2 days') = 'fresh', NULL);
  r := r || public._qa_s13_ok('N4R35.C16 freshness aging between 7 and 30 days',
        public.marche_fulfillment_freshness(now() - interval '20 days') = 'aging', NULL);
  r := r || public._qa_s13_ok('N4R35.C17 freshness stale past 30 days',
        public.marche_fulfillment_freshness(now() - interval '90 days') = 'stale', NULL);
  r := r || public._qa_s13_ok('N4R35.C18 confidence insufficient below 10 samples',
        public.marche_fulfillment_confidence(0, now()) = 'insufficient'
    AND public.marche_fulfillment_confidence(9, now()) = 'insufficient', NULL);
  r := r || public._qa_s13_ok('N4R35.C19 confidence medium at 10 fresh samples',
        public.marche_fulfillment_confidence(10, now()) = 'medium', NULL);
  r := r || public._qa_s13_ok('N4R35.C20 confidence high at 30 fresh samples',
        public.marche_fulfillment_confidence(30, now()) = 'high', NULL);
  r := r || public._qa_s13_ok('N4R35.C21 stale data downgrades confidence to low',
        public.marche_fulfillment_confidence(500, now() - interval '120 days') = 'low', NULL);
  r := r || public._qa_s13_ok('N4R35.C22 aging data caps confidence at medium',
        public.marche_fulfillment_confidence(500, now() - interval '20 days') = 'medium', NULL);
  r := r || public._qa_s13_ok('N4R35.C23 freshness is distinct from confidence',
        public.marche_fulfillment_freshness(now()) = 'fresh'
    AND public.marche_fulfillment_confidence(1, now()) = 'insufficient', NULL);
  r := r || public._qa_s13_ok('N4R35.C24 confidence is deterministic (same input, same output)',
        public.marche_fulfillment_confidence(12, now() - interval '1 day')
      = public.marche_fulfillment_confidence(12, now() - interval '1 day'), NULL);

  v_src := (SELECT prosrc FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='marche_order_commit');
  r := r || public._qa_s13_ok('N4R35.C25 commit creates the measurement profile',
        v_src LIKE '%marche_fulfillment_profile_create%', NULL);
  r := r || public._qa_s13_ok('N4R35.C26 commit emits ORDER_COMMITTED',
        v_src LIKE '%ORDER_COMMITTED%', NULL);
  r := r || public._qa_s13_ok('N4R35.C27 commit still refuses client money (R3 law intact)',
        v_src LIKE '%CLIENT_PRICE_NOT_ALLOWED%', NULL);
  r := r || public._qa_s13_ok('N4R35.C28 commit still locks rows deterministically (R3 law intact)',
        v_src LIKE '%ORDER BY id FOR UPDATE%', NULL);
  r := r || public._qa_s13_ok('N4R35.C29 commit snapshots the listing category',
        v_src LIKE '%category_snapshot%', NULL);
  r := r || public._qa_s13_ok('N4R35.C30 R3.5 introduces no fee/settlement call',
        v_src NOT LIKE '%transaction_fee_bps%' AND v_src NOT LIKE '%finance_policies%'
    AND v_src NOT LIKE '%payment_intent%', NULL);

  -- ================= RUNTIME =================
  BEGIN
    v_buy := gen_random_uuid(); v_merch := gen_random_uuid(); v_adm := gen_random_uuid();
    PERFORM public._qa_s13_user(v_buy,'n435b'); PERFORM public._qa_s13_user(v_merch,'n435m');
    PERFORM public._qa_s13_user(v_adm,'n435a'); PERFORM public._qa_s13_admin(v_adm);

    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status, latitude, longitude)
      VALUES (v_merch,'qa-n435-a-'||substr(v_merch::text,1,8),'QA N435 Store A','active','approved', 9.5370, -13.6785)
      RETURNING id INTO v_store;
    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status)
      VALUES (v_adm,'qa-n435-nc-'||substr(v_adm::text,1,8),'QA N435 Store NoCoords','active','approved')
      RETURNING id INTO v_store_nc;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    l_a := public.marche_listing_create(jsonb_build_object('store_id',v_store,'title','QA N435 Riz',
      'category','Alimentation','price_gnf',10000,'quantity_in_stock',200,'publish',true));
    l_b := public.marche_listing_create(jsonb_build_object('store_id',v_store,'title','QA N435 Huile',
      'category','ALIMENTATION','price_gnf',20000,'quantity_in_stock',50,'publish',true));
    l_bulk := public.marche_listing_create(jsonb_build_object('store_id',v_store,'title','QA N435 Savon',
      'category','Maison','price_gnf',5000,'quantity_in_stock',200,'publish',true));
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_adm), true);
    l_nc := public.marche_listing_create(jsonb_build_object('store_id',v_store_nc,'title','QA N435 Sans Coords',
      'category','Autre','price_gnf',7000,'quantity_in_stock',50,'publish',true));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_res := public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n435-main-0001',
      'delivery_address','QA Kaloum',
      'dropoff_lat', 9.5550, 'dropoff_lng', -13.6785,
      'items', jsonb_build_array(
        jsonb_build_object('listing_id', l_a, 'qty', 2),
        jsonb_build_object('listing_id', l_b, 'qty', 3))));
    v_o := (v_res->>'id')::uuid;
    SELECT * INTO p FROM public.marche_fulfillment_profiles WHERE order_id = v_o;
    SELECT * INTO v_ord FROM public.marche_orders WHERE id = v_o;

    r := r || public._qa_s13_ok('N4R35.D1 commit created exactly one profile',
          (SELECT count(*) FROM public.marche_fulfillment_profiles WHERE order_id = v_o) = 1, NULL);
    r := r || public._qa_s13_ok('N4R35.D2 commit emitted exactly one ORDER_COMMITTED',
          (SELECT count(*) FROM public.marche_fulfillment_events
            WHERE order_id = v_o AND event_type='ORDER_COMMITTED') = 1, NULL);
    r := r || public._qa_s13_ok('N4R35.D3 commit emitted no other milestone',
          (SELECT count(*) FROM public.marche_fulfillment_events WHERE order_id = v_o) = 1, NULL);
    r := r || public._qa_s13_ok('N4R35.D4 basket_units is exact (2+3)',
          p.basket_units = 5, p.basket_units::text);
    r := r || public._qa_s13_ok('N4R35.D5 distinct_products is exact',
          p.distinct_products = 2, p.distinct_products::text);
    r := r || public._qa_s13_ok('N4R35.D6 basket_units equals R3 item_count',
          p.basket_units = v_ord.item_count, NULL);
    r := r || public._qa_s13_ok('N4R35.D7 distinct_products equals R3 line_count',
          p.distinct_products = v_ord.line_count, NULL);
    r := r || public._qa_s13_ok('N4R35.D8 store snapshot is exact',
          p.merchant_store_id = v_store, NULL);
    r := r || public._qa_s13_ok('N4R35.D9 categories normalized, de-duplicated and sorted',
          p.product_categories = ARRAY['alimentation']::text[], array_to_string(p.product_categories,','));
    r := r || public._qa_s13_ok('N4R35.D10 order lines carry a frozen category snapshot',
          (SELECT count(*) FROM public.marche_order_items
            WHERE order_id = v_o AND category_snapshot IS NOT NULL) = 2, NULL);
    r := r || public._qa_s13_ok('N4R35.D11 fulfillment mode is explicit server truth, not client-authored',
          p.fulfillment_mode = 'unspecified' AND p.fulfillment_mode_source IS NOT NULL, p.fulfillment_mode);
    r := r || public._qa_s13_ok('N4R35.D12 known coordinates produce a measured distance',
          p.distance_m IS NOT NULL AND p.distance_m > 0, p.distance_m::text);
    r := r || public._qa_s13_ok('N4R35.D13 distance method is honest (geodesic, never claimed road)',
          p.distance_method = 'geodesic', p.distance_method);
    r := r || public._qa_s13_ok('N4R35.D14 distance source is recorded',
          p.distance_source = 'store_coords+order_dropoff', p.distance_source);
    r := r || public._qa_s13_ok('N4R35.D15 geodesic distance matches the canonical helper exactly',
          p.distance_m = public._map_distance_meters(9.5370,-13.6785,9.5550,-13.6785), NULL);
    r := r || public._qa_s13_ok('N4R35.D16 both endpoints of the measurement are retained',
          p.origin_lat = 9.5370 AND p.origin_lng = -13.6785
      AND p.dropoff_lat = 9.5550 AND p.dropoff_lng = -13.6785, NULL);
    r := r || public._qa_s13_ok('N4R35.D17 weight stays NULL without a trusted source',
          p.weight_grams IS NULL, NULL);
    r := r || public._qa_s13_ok('N4R35.D18 bulk complexity stays NULL without a trusted source',
          p.bulk_complexity IS NULL, NULL);
    r := r || public._qa_s13_ok('N4R35.D19 profile frozen_at mirrors order commitment time',
          p.frozen_at = v_ord.created_at, NULL);
    r := r || public._qa_s13_ok('N4R35.D20 ORDER_COMMITTED occurred_at is the commitment truth',
          (SELECT occurred_at FROM public.marche_fulfillment_events
            WHERE order_id = v_o AND event_type='ORDER_COMMITTED') = v_ord.created_at, NULL);
    r := r || public._qa_s13_ok('N4R35.D21 ORDER_COMMITTED records provenance',
          (SELECT source_type='marche_order_commit' AND source_key='commit' AND actor_role='system'
             FROM public.marche_fulfillment_events
            WHERE order_id = v_o AND event_type='ORDER_COMMITTED'), NULL);
    r := r || public._qa_s13_ok('N4R35.D22 R3 money fields remain NULL after R3.5 wiring',
          v_ord.merchant_fee_gnf IS NULL AND v_ord.delivery_charge_gnf IS NULL
      AND v_ord.fee_policy_id IS NULL, NULL);

    v_res2 := public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n435-main-0001',
      'delivery_address','QA Kaloum',
      'dropoff_lat', 9.5550, 'dropoff_lng', -13.6785,
      'items', jsonb_build_array(
        jsonb_build_object('listing_id', l_a, 'qty', 2),
        jsonb_build_object('listing_id', l_b, 'qty', 3))));
    r := r || public._qa_s13_ok('N4R35.E1 replay returns the same order (R3 law intact)',
          (v_res2->>'id')::uuid = v_o, NULL);
    r := r || public._qa_s13_ok('N4R35.E2 replay does not duplicate the profile',
          (SELECT count(*) FROM public.marche_fulfillment_profiles WHERE order_id = v_o) = 1, NULL);
    r := r || public._qa_s13_ok('N4R35.E3 replay does not duplicate ORDER_COMMITTED',
          (SELECT count(*) FROM public.marche_fulfillment_events
            WHERE order_id = v_o AND event_type='ORDER_COMMITTED') = 1, NULL);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    PERFORM public.marche_listing_update(l_a, jsonb_build_object('category','Electronique'));
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    r := r || public._qa_s13_ok('N4R35.E4 line category snapshot survives a merchant category edit',
          (SELECT count(*) FROM public.marche_order_items
            WHERE order_id = v_o AND lower(category_snapshot) = 'alimentation') = 2, NULL);
    r := r || public._qa_s13_ok('N4R35.E5 profile categories are historical, not current listing truth',
          (SELECT product_categories FROM public.marche_fulfillment_profiles WHERE order_id = v_o)
          = ARRAY['alimentation']::text[], NULL);
    r := r || public._qa_s13_ok('N4R35.E6 current listing category really did change (control)',
          (SELECT lower(category) FROM public.marketplace_listings WHERE id = l_a) = 'electronique', NULL);

    v_res := public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n435-nocoord-0001',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_nc, 'qty', 1))));
    v_onc := (v_res->>'id')::uuid;
    SELECT * INTO p FROM public.marche_fulfillment_profiles WHERE order_id = v_onc;
    r := r || public._qa_s13_ok('N4R35.F1 unmeasurable distance is NULL, never 0',
          p.distance_m IS NULL, COALESCE(p.distance_m::text,'null'));
    r := r || public._qa_s13_ok('N4R35.F2 unmeasurable distance declares "unverified"',
          p.distance_method = 'unverified', p.distance_method);
    r := r || public._qa_s13_ok('N4R35.F3 unverified measurement claims no source',
          p.distance_source IS NULL, NULL);
    r := r || public._qa_s13_ok('N4R35.F4 methods are never silently mixed',
          (SELECT count(DISTINCT distance_method) FROM public.marche_fulfillment_profiles
            WHERE order_id IN (v_o, v_onc)) = 2, NULL);
    r := r || public._qa_s13_ok('N4R35.F5 unmeasured distance buckets as unknown',
          public.marche_distance_bucket(p.distance_m) = 'unknown', NULL);
    r := r || public._qa_s13_ok('N4R35.F6 single-unit basket buckets as single',
          public.marche_basket_bucket(p.basket_units, p.distinct_products) = 'single', NULL);

    PERFORM public.marche_fulfillment_event_append(v_o,'MERCHANT_ACCEPTED', v_now, 'qa_harness', v_o::text, 'accept-1','merchant');
    PERFORM public.marche_fulfillment_event_append(v_o,'MERCHANT_ACCEPTED', v_now + interval '5 minutes', 'qa_harness', v_o::text, 'accept-1','merchant');
    r := r || public._qa_s13_ok('N4R35.G1 same event source key ingests exactly once',
          (SELECT count(*) FROM public.marche_fulfillment_events
            WHERE order_id = v_o AND event_type='MERCHANT_ACCEPTED') = 1, NULL);
    r := r || public._qa_s13_ok('N4R35.G2 first-write history is not rewritten',
          (SELECT occurred_at FROM public.marche_fulfillment_events
            WHERE order_id = v_o AND event_type='MERCHANT_ACCEPTED') = v_now, NULL);
    r := r || public._qa_s13_ok('N4R35.G3 ingestion time is recorded separately from event time',
          (SELECT created_at >= occurred_at FROM public.marche_fulfillment_events
            WHERE order_id = v_o AND event_type='MERCHANT_ACCEPTED'), NULL);

    BEGIN
      UPDATE public.marche_fulfillment_events SET occurred_at = now()
       WHERE order_id = v_o AND event_type='MERCHANT_ACCEPTED';
      v_err := 'no-error';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R35.G4 events cannot be updated (append-only)',
          v_err = 'FULFILLMENT_EVENT_APPEND_ONLY', v_err);
    BEGIN
      DELETE FROM public.marche_fulfillment_events WHERE order_id = v_o;
      v_err := 'no-error';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R35.G5 events cannot be deleted (append-only)',
          v_err = 'FULFILLMENT_EVENT_APPEND_ONLY', v_err);
    BEGIN
      UPDATE public.marche_fulfillment_profiles SET basket_units = 999 WHERE order_id = v_o;
      v_err := 'no-error';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R35.G6 profiles are immutable',
          v_err = 'FULFILLMENT_PROFILE_IMMUTABLE', v_err);
    BEGIN
      INSERT INTO public.marche_fulfillment_observations(order_id, metric_name, duration_seconds,
        start_event_at, end_event_at, merchant_store_id, fulfillment_mode, distance_bucket,
        basket_units, distinct_products, basket_bucket, observed_at)
      VALUES (v_o,'COMMIT_TO_DELIVERED', 1, now(), now(), v_store, 'delivery','0-1km',1,1,'single', now());
      v_err := 'no-error';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R35.G7 observations cannot be hand-written',
          v_err = 'FULFILLMENT_OBSERVATION_DERIVED_ONLY', v_err);

    r := r || public._qa_s13_ok('N4R35.H1 observation created for a complete endpoint pair',
          (SELECT count(*) FROM public.marche_fulfillment_observations
            WHERE order_id = v_o AND metric_name='COMMIT_TO_MERCHANT_ACCEPTED') = 1, NULL);
    r := r || public._qa_s13_ok('N4R35.H2 no observation for an incomplete pair',
          (SELECT count(*) FROM public.marche_fulfillment_observations
            WHERE order_id = v_o AND metric_name='MERCHANT_ACCEPTED_TO_READY') = 0, NULL);
    r := r || public._qa_s13_ok('N4R35.H3 no observation without any endpoint',
          (SELECT count(*) FROM public.marche_fulfillment_observations
            WHERE order_id = v_o AND metric_name='SHOPPING_START_TO_COMPLETE') = 0, NULL);
    r := r || public._qa_s13_ok('N4R35.H4 observation inherits the immutable cohort dimensions',
          (SELECT basket_units = 5 AND distinct_products = 2 AND merchant_store_id = v_store
             FROM public.marche_fulfillment_observations
            WHERE order_id = v_o AND metric_name='COMMIT_TO_MERCHANT_ACCEPTED'), NULL);
    r := r || public._qa_s13_ok('N4R35.H5 observation retains raw distance and its bucket',
          (SELECT distance_m IS NOT NULL AND distance_bucket = public.marche_distance_bucket(distance_m)
             FROM public.marche_fulfillment_observations
            WHERE order_id = v_o AND metric_name='COMMIT_TO_MERCHANT_ACCEPTED'), NULL);

    PERFORM public.marche_fulfillment_event_append(v_o,'MERCHANT_READY', v_now + interval '600 seconds','qa_harness', v_o::text,'ready-1','merchant');
    r := r || public._qa_s13_ok('N4R35.H6 MERCHANT_ACCEPTED_TO_READY equals exactly 600s',
          (SELECT duration_seconds FROM public.marche_fulfillment_observations
            WHERE order_id = v_o AND metric_name='MERCHANT_ACCEPTED_TO_READY') = 600, NULL);
    PERFORM public.marche_fulfillment_event_append(v_o,'COURIER_ENGAGED', v_now + interval '700 seconds','qa_harness', v_o::text,'eng-1','courier');
    PERFORM public.marche_fulfillment_event_append(v_o,'COURIER_AT_STORE', v_now + interval '1000 seconds','qa_harness', v_o::text,'atstore-1','courier');
    r := r || public._qa_s13_ok('N4R35.H7 COURIER_ENGAGED_TO_STORE_ARRIVAL equals exactly 300s',
          (SELECT duration_seconds FROM public.marche_fulfillment_observations
            WHERE order_id = v_o AND metric_name='COURIER_ENGAGED_TO_STORE_ARRIVAL') = 300, NULL);
    PERFORM public.marche_fulfillment_event_append(v_o,'SHOPPING_STARTED', v_now + interval '1010 seconds','qa_harness', v_o::text,'shop-s','courier');
    PERFORM public.marche_fulfillment_event_append(v_o,'SHOPPING_COMPLETED', v_now + interval '1460 seconds','qa_harness', v_o::text,'shop-e','courier');
    r := r || public._qa_s13_ok('N4R35.H8 SHOPPING_START_TO_COMPLETE equals exactly 450s',
          (SELECT duration_seconds FROM public.marche_fulfillment_observations
            WHERE order_id = v_o AND metric_name='SHOPPING_START_TO_COMPLETE') = 450, NULL);
    PERFORM public.marche_fulfillment_event_append(v_o,'PICKED_UP', v_now + interval '1500 seconds','qa_harness', v_o::text,'pick-1','courier');
    PERFORM public.marche_fulfillment_event_append(v_o,'DELIVERED', v_now + interval '2400 seconds','qa_harness', v_o::text,'deliv-1','courier');
    r := r || public._qa_s13_ok('N4R35.H9 PICKUP_TO_DELIVERED equals exactly 900s',
          (SELECT duration_seconds FROM public.marche_fulfillment_observations
            WHERE order_id = v_o AND metric_name='PICKUP_TO_DELIVERED') = 900, NULL);
    r := r || public._qa_s13_ok('N4R35.H10 COMMIT_TO_DELIVERED spans the whole lifecycle',
          (SELECT duration_seconds > 2000 FROM public.marche_fulfillment_observations
            WHERE order_id = v_o AND metric_name='COMMIT_TO_DELIVERED'), NULL);
    r := r || public._qa_s13_ok('N4R35.H11 all six canonical intervals now observed exactly once',
          (SELECT count(*) FROM public.marche_fulfillment_observations WHERE order_id = v_o) = 6, NULL);
    r := r || public._qa_s13_ok('N4R35.H12 no duplicate observation per (order, metric)',
          (SELECT count(*) FROM (SELECT order_id, metric_name FROM public.marche_fulfillment_observations
             WHERE order_id = v_o GROUP BY 1,2 HAVING count(*) > 1) d) = 0, NULL);
    PERFORM public.marche_fulfillment_event_append(v_o,'DELIVERED', v_now + interval '9999 seconds','qa_harness', v_o::text,'deliv-2','courier');
    r := r || public._qa_s13_ok('N4R35.H13 a duplicate endpoint event does not duplicate the observation',
          (SELECT count(*) FROM public.marche_fulfillment_observations
            WHERE order_id = v_o AND metric_name='PICKUP_TO_DELIVERED') = 1, NULL);
    r := r || public._qa_s13_ok('N4R35.H14 earliest endpoint remains the observation truth',
          (SELECT duration_seconds FROM public.marche_fulfillment_observations
            WHERE order_id = v_o AND metric_name='PICKUP_TO_DELIVERED') = 900, NULL);
    r := r || public._qa_s13_ok('N4R35.H15 every observation duration is non-negative',
          (SELECT count(*) FROM public.marche_fulfillment_observations WHERE duration_seconds < 0) = 0, NULL);

    v_res := public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n435-neg-0001',
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_bulk, 'qty', 1))));
    v_oneg := (v_res->>'id')::uuid;
    PERFORM public.marche_fulfillment_event_append(v_oneg,'PICKED_UP', v_now,'qa_harness', v_oneg::text,'pick','courier');
    PERFORM public.marche_fulfillment_event_append(v_oneg,'DELIVERED', v_now - interval '1 hour','qa_harness', v_oneg::text,'deliv','courier');
    r := r || public._qa_s13_ok('N4R35.I1 impossible negative interval produces no observation',
          (SELECT count(*) FROM public.marche_fulfillment_observations
            WHERE order_id = v_oneg AND metric_name='PICKUP_TO_DELIVERED') = 0, NULL);
    r := r || public._qa_s13_ok('N4R35.I2 impossible interval is not clamped to zero',
          (SELECT count(*) FROM public.marche_fulfillment_observations
            WHERE order_id = v_oneg AND duration_seconds = 0) = 0, NULL);
    r := r || public._qa_s13_ok('N4R35.I3 the raw impossible events are still retained as evidence',
          (SELECT count(*) FROM public.marche_fulfillment_events
            WHERE order_id = v_oneg AND event_type IN ('PICKED_UP','DELIVERED')) = 2, NULL);

    FOR v_i IN 1..10 LOOP
      v_res := public.marche_order_commit(jsonb_build_object(
        'client_request_id','qa-n435-cohort-'||lpad(v_i::text,4,'0'),
        'dropoff_lat', 9.5550, 'dropoff_lng', -13.6785,
        'items', jsonb_build_array(jsonb_build_object('listing_id', l_bulk, 'qty', 1))));
      v_tmp := (v_res->>'id')::uuid;
      v_ids := v_ids || v_tmp;
      PERFORM public.marche_fulfillment_set_mode(v_tmp,'delivery','qa_harness');
      PERFORM public.marche_fulfillment_event_append(v_tmp,'PICKED_UP', v_now,'qa_harness', v_tmp::text,'pick','courier');
      PERFORM public.marche_fulfillment_event_append(v_tmp,'DELIVERED', v_now + (v_i * 100 || ' seconds')::interval,
        'qa_harness', v_tmp::text,'deliv','courier');
    END LOOP;
    FOR v_i IN 11..12 LOOP
      v_res := public.marche_order_commit(jsonb_build_object(
        'client_request_id','qa-n435-cohort-'||lpad(v_i::text,4,'0'),
        'dropoff_lat', 9.5550, 'dropoff_lng', -13.6785,
        'items', jsonb_build_array(jsonb_build_object('listing_id', l_bulk, 'qty', 1))));
      v_tmp := (v_res->>'id')::uuid;
      v_ids := v_ids || v_tmp;
      PERFORM public.marche_fulfillment_set_mode(v_tmp,'pickup','qa_harness');
      PERFORM public.marche_fulfillment_event_append(v_tmp,'PICKED_UP', v_now,'qa_harness', v_tmp::text,'pick','courier');
      PERFORM public.marche_fulfillment_event_append(v_tmp,'DELIVERED', v_now + interval '5000 seconds',
        'qa_harness', v_tmp::text,'deliv','courier');
    END LOOP;

    r := r || public._qa_s13_ok('N4R35.J1 mode declaration is one-way once set',
          (SELECT fulfillment_mode FROM public.marche_fulfillment_profiles WHERE order_id = v_ids[1]) = 'delivery', NULL);
    BEGIN
      PERFORM public.marche_fulfillment_set_mode(v_ids[1],'pickup','qa_harness');
      v_err := 'no-error';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R35.J2 fulfillment mode cannot be rewritten',
          v_err = 'FULFILLMENT_MODE_FROZEN', v_err);
    BEGIN
      PERFORM public.marche_fulfillment_set_mode(v_ids[1],'teleport','qa_harness');
      v_err := 'no-error';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R35.J3 invalid fulfillment mode refused',
          v_err = 'INVALID_FULFILLMENT_MODE', v_err);

    v_stats := public.marche_fulfillment_cohort_stats('PICKUP_TO_DELIVERED','delivery',
                 public.marche_distance_bucket(public._map_distance_meters(9.5370,-13.6785,9.5550,-13.6785)),'single');
    v_row := v_stats->0;
    r := r || public._qa_s13_ok('N4R35.K1 cohort resolves to exactly one group',
          jsonb_array_length(v_stats) = 1, jsonb_array_length(v_stats)::text);
    r := r || public._qa_s13_ok('N4R35.K2 sample_count is exact (10)',
          (v_row->>'sample_count')::int = 10, v_row->>'sample_count');
    r := r || public._qa_s13_ok('N4R35.K3 P50 is exactly 550s',
          (v_row->>'p50_seconds')::numeric = 550, v_row->>'p50_seconds');
    r := r || public._qa_s13_ok('N4R35.K4 P75 is exactly 775s',
          (v_row->>'p75_seconds')::numeric = 775, v_row->>'p75_seconds');
    r := r || public._qa_s13_ok('N4R35.K5 P90 is exactly 910s',
          (v_row->>'p90_seconds')::numeric = 910, v_row->>'p90_seconds');
    r := r || public._qa_s13_ok('N4R35.K6 min duration is exact',
          (v_row->>'min_duration_seconds')::numeric = 100, v_row->>'min_duration_seconds');
    r := r || public._qa_s13_ok('N4R35.K7 max duration is exact',
          (v_row->>'max_duration_seconds')::numeric = 1000, v_row->>'max_duration_seconds');
    r := r || public._qa_s13_ok('N4R35.K8 latest observation timestamp is exact',
          (v_row->>'latest_observed_at')::timestamptz = v_now + interval '1000 seconds', v_row->>'latest_observed_at');
    r := r || public._qa_s13_ok('N4R35.K9 first observation timestamp is exact',
          (v_row->>'first_observed_at')::timestamptz = v_now + interval '100 seconds', v_row->>'first_observed_at');
    r := r || public._qa_s13_ok('N4R35.K10 freshness reported as fresh',
          v_row->>'freshness' = 'fresh', v_row->>'freshness');
    r := r || public._qa_s13_ok('N4R35.K11 confidence is medium at 10 fresh samples',
          v_row->>'confidence' = 'medium', v_row->>'confidence');
    r := r || public._qa_s13_ok('N4R35.K12 sufficient cohort is not flagged insufficient',
          (v_row->>'insufficient_data')::boolean = false, NULL);
    r := r || public._qa_s13_ok('N4R35.K13 cohort labels echo the partition dimensions',
          v_row->>'metric_name' = 'PICKUP_TO_DELIVERED' AND v_row->>'fulfillment_mode' = 'delivery'
      AND v_row->>'basket_bucket' = 'single', NULL);
    v_keys := (SELECT string_agg(k,',') FROM jsonb_object_keys(v_row) k);
    r := r || public._qa_s13_ok('N4R35.K14 statistics expose no ETA or prediction field',
          v_keys NOT LIKE '%eta%' AND v_keys NOT LIKE '%predict%'
      AND v_keys NOT LIKE '%estimate%' AND v_keys NOT LIKE '%forecast%', v_keys);
    r := r || public._qa_s13_ok('N4R35.K15 statistics expose no money field',
          v_keys NOT LIKE '%price%' AND v_keys NOT LIKE '%fee%'
      AND v_keys NOT LIKE '%payout%' AND v_keys NOT LIKE '%gnf%' AND v_keys NOT LIKE '%amount%', v_keys);
    r := r || public._qa_s13_ok('N4R35.K16 statistics expose no user identity',
          v_keys NOT LIKE '%buyer%' AND v_keys NOT LIKE '%user%' AND v_keys NOT LIKE '%email%', v_keys);

    v_stats := public.marche_fulfillment_cohort_stats('PICKUP_TO_DELIVERED','pickup');
    r := r || public._qa_s13_ok('N4R35.L1 pickup cohort is isolated with its own samples',
          jsonb_array_length(v_stats) = 1 AND (v_stats->0->>'sample_count')::int = 2, NULL);
    r := r || public._qa_s13_ok('N4R35.L2 small cohort honestly reports insufficient data',
          (v_stats->0->>'insufficient_data')::boolean = true
      AND v_stats->0->>'confidence' = 'insufficient', v_stats->0->>'confidence');
    r := r || public._qa_s13_ok('N4R35.L3 records never bleed across fulfillment modes',
          (v_stats->0->>'p50_seconds')::numeric = 5000, v_stats->0->>'p50_seconds');
    v_stats := public.marche_fulfillment_cohort_stats('PICKUP_TO_DELIVERED','delivery','15km+');
    r := r || public._qa_s13_ok('N4R35.L4 wrong distance bucket yields an empty cohort',
          v_stats = '[]'::jsonb, v_stats::text);
    v_stats := public.marche_fulfillment_cohort_stats('PICKUP_TO_DELIVERED','delivery',NULL,'large');
    r := r || public._qa_s13_ok('N4R35.L5 wrong basket bucket yields an empty cohort',
          v_stats = '[]'::jsonb, v_stats::text);
    v_stats := public.marche_fulfillment_cohort_stats('SHOPPING_START_TO_COMPLETE','delivery');
    r := r || public._qa_s13_ok('N4R35.L6 metric partitions do not bleed into one another',
          v_stats = '[]'::jsonb, v_stats::text);
    v_stats := public.marche_fulfillment_cohort_stats('COMMIT_TO_MERCHANT_ACCEPTED');
    r := r || public._qa_s13_ok('N4R35.L7 unknown-mode observations are excluded from cohort output',
          v_stats = '[]'::jsonb, v_stats::text);
    v_stats := public.marche_fulfillment_cohort_stats('COMMIT_TO_MERCHANT_ACCEPTED',NULL,NULL,NULL,true);
    r := r || public._qa_s13_ok('N4R35.L8 unknown-mode data is still retained and inspectable',
          jsonb_array_length(v_stats) = 1 AND v_stats->0->>'fulfillment_mode' = 'unspecified', v_stats::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_adm), true);
    r := r || public._qa_s13_ok('N4R35.M1 admin can read a basket profile',
          (public.marche_fulfillment_profile_admin(v_o))->>'order_id' = v_o::text, NULL);
    r := r || public._qa_s13_ok('N4R35.M2 admin can read the raw event timeline',
          jsonb_array_length(public.marche_fulfillment_events_admin(v_o)) >= 6, NULL);
    r := r || public._qa_s13_ok('N4R35.M3 admin can read derived observations',
          jsonb_array_length(public.marche_fulfillment_observations_admin('PICKUP_TO_DELIVERED', 500)) >= 10, NULL);
    r := r || public._qa_s13_ok('N4R35.M4 admin can read cohort statistics',
          jsonb_array_length(public.marche_fulfillment_cohorts_admin('PICKUP_TO_DELIVERED','delivery')) = 1, NULL);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    BEGIN
      PERFORM public.marche_fulfillment_profile_admin(v_o);
      v_err := 'no-error';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R35.M5 buyer cannot read profiles', v_err = 'NOT_AUTHORIZED', v_err);
    BEGIN
      PERFORM public.marche_fulfillment_events_admin(v_o);
      v_err := 'no-error';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R35.M6 buyer cannot read the raw event timeline', v_err = 'NOT_AUTHORIZED', v_err);
    BEGIN
      PERFORM public.marche_fulfillment_cohorts_admin();
      v_err := 'no-error';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R35.M7 buyer cannot read cohort statistics', v_err = 'NOT_AUTHORIZED', v_err);
    BEGIN
      PERFORM public.marche_fulfillment_event_append(gen_random_uuid(),'DELIVERED', now(),'spoof');
      v_err := 'no-error';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R35.M8 milestones cannot be attached to a non-existent order',
          v_err = 'ORDER_NOT_FOUND', v_err);
    BEGIN
      PERFORM public.marche_fulfillment_event_append(v_o,'DELIVERED', NULL,'qa_harness');
      v_err := 'no-error';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R35.M9 an event without a timestamp is refused',
          v_err = 'OCCURRED_AT_REQUIRED', v_err);
    BEGIN
      PERFORM public.marche_fulfillment_event_append(v_o,'DELIVERED', now(),'');
      v_err := 'no-error';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R35.M10 an event without provenance is refused',
          v_err = 'SOURCE_REQUIRED', v_err);

    r := r || public._qa_s13_ok('N4R35.N1 R3 order snapshots unchanged by measurement',
          (SELECT merchandise_subtotal_gnf FROM public.marche_orders WHERE id = v_o) = 80000,
          (SELECT merchandise_subtotal_gnf::text FROM public.marche_orders WHERE id = v_o));
    r := r || public._qa_s13_ok('N4R35.N2 R3 reservation still applied on commit',
          (SELECT quantity_reserved FROM public.marketplace_listings WHERE id = l_a) = 2, NULL);
    r := r || public._qa_s13_ok('N4R35.N3 all fixture orders still carry NULL money fields',
          (SELECT count(*) FROM public.marche_orders
            WHERE buyer_user_id = v_buy
              AND (merchant_fee_gnf IS NOT NULL OR delivery_charge_gnf IS NOT NULL
                OR fee_policy_id IS NOT NULL)) = 0, NULL);
    r := r || public._qa_s13_ok('N4R35.N4 cancellation still releases reserved stock',
          (SELECT (public.marche_order_cancel(v_onc,'qa'))->>'status') = 'cancelled', NULL);
    r := r || public._qa_s13_ok('N4R35.N5 measurement survives order cancellation as evidence',
          (SELECT count(*) FROM public.marche_fulfillment_profiles WHERE order_id = v_onc) = 1, NULL);
    r := r || public._qa_s13_ok('N4R35.N6 R1.5 supply doctrine still holds',
          (SELECT count(*) FROM public.v_marche_listing_truth
            WHERE is_orderable AND (store_id IS NULL OR kind <> 'merchant'::listing_kind)) = 0, NULL);

  EXCEPTION WHEN OTHERS THEN
    r := r || public._qa_s13_ok('N4R35.FIXTURE runtime block completed without unhandled error', false, SQLERRM);
  END;

  -- ================= CLEANUP =================
  PERFORM set_config('request.jwt.claims','', true);
  PERFORM set_config('marche.rpc','1', true);
  DELETE FROM public.marche_order_items WHERE order_id IN
    (SELECT id FROM public.marche_orders WHERE buyer_user_id IN (v_buy, v_merch, v_adm));
  DELETE FROM public.marche_orders WHERE buyer_user_id IN (v_buy, v_merch, v_adm);
  PERFORM set_config('marche.rpc','', true);
  DELETE FROM public.listing_images WHERE listing_id IN (l_a,l_b,l_bulk,l_nc);
  DELETE FROM public.listing_metrics WHERE listing_id IN (l_a,l_b,l_bulk,l_nc);
  DELETE FROM public.marketplace_listings WHERE seller_id IN (v_buy,v_merch,v_adm);
  DELETE FROM public.account_bans WHERE user_id IN (v_buy,v_merch,v_adm);
  DELETE FROM public.merchant_stores WHERE owner_user_id IN (v_merch, v_adm);
  DELETE FROM public.admin_users WHERE user_id = v_adm;
  DELETE FROM public.wallet_transactions WHERE from_wallet_id IN (SELECT id FROM public.wallets WHERE owner_user_id IN (v_buy,v_merch,v_adm))
     OR to_wallet_id IN (SELECT id FROM public.wallets WHERE owner_user_id IN (v_buy,v_merch,v_adm));
  DELETE FROM public.wallets WHERE owner_user_id IN (v_buy,v_merch,v_adm);
  DELETE FROM auth.users WHERE id IN (v_buy,v_merch,v_adm);

  -- ================= SYSTEMIC =================
  SELECT count(*) INTO v_w1 FROM public.wallets;
  SELECT count(*) INTO v_wt1 FROM public.wallet_transactions;
  SELECT count(*) INTO v_lj1 FROM public.ledger_journals;
  SELECT count(*) INTO v_ms1 FROM public.missions;
  SELECT count(*) INTO v_pi1 FROM public.payment_intents;
  SELECT count(*) INTO v_lp1 FROM public.ledger_postings;
  SELECT count(*) INTO v_total1 FROM public.marketplace_listings;
  SELECT count(*) INTO v_none1 FROM public.marketplace_listings WHERE store_id IS NULL;
  SELECT COALESCE(sum(quantity_reserved),0) INTO v_reserved1 FROM public.marketplace_listings;
  SELECT count(*) INTO v_fp1 FROM public.marche_fulfillment_profiles;
  SELECT count(*) INTO v_ev1 FROM public.marche_fulfillment_events;
  SELECT count(*) INTO v_ob1 FROM public.marche_fulfillment_observations;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;

  r := r || public._qa_s13_ok('N4R35.S1 zero wallet drift', v_w1 = v_w0 AND v_wt1 = v_wt0, NULL);
  r := r || public._qa_s13_ok('N4R35.S2 zero ledger drift', v_lj1 = v_lj0 AND v_lp1 = v_lp0, NULL);
  r := r || public._qa_s13_ok('N4R35.S3 zero mission/courier drift', v_ms1 = v_ms0, NULL);
  r := r || public._qa_s13_ok('N4R35.S4 zero payment/settlement drift', v_pi1 = v_pi0, NULL);
  r := r || public._qa_s13_ok('N4R35.S5 feature flags byte-identical', v_flags1 = v_flags0, NULL);
  r := r || public._qa_s13_ok('N4R35.S6 listing population unchanged', v_total1 = v_total0, format('%s->%s', v_total0, v_total1));
  r := r || public._qa_s13_ok('N4R35.S7 storeless quarantine unchanged', v_none1 = v_none0, format('%s->%s', v_none0, v_none1));
  r := r || public._qa_s13_ok('N4R35.S8 reserved stock returns to baseline', v_reserved1 = v_reserved0, format('%s->%s', v_reserved0, v_reserved1));
  r := r || public._qa_s13_ok('N4R35.S9 zero profile residue', v_fp1 = v_fp0, format('%s->%s', v_fp0, v_fp1));
  r := r || public._qa_s13_ok('N4R35.S10 zero event residue', v_ev1 = v_ev0, format('%s->%s', v_ev0, v_ev1));
  r := r || public._qa_s13_ok('N4R35.S11 zero observation residue', v_ob1 = v_ob0, format('%s->%s', v_ob0, v_ob1));
  SELECT count(*) INTO v_n FROM public.marketplace_listings WHERE title LIKE 'QA N435%';
  r := r || public._qa_s13_ok('N4R35.S12 zero listing fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_orders WHERE client_request_id LIKE 'qa-n435-%';
  r := r || public._qa_s13_ok('N4R35.S13 zero order fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.merchant_stores WHERE slug LIKE 'qa-n435-%';
  r := r || public._qa_s13_ok('N4R35.S14 zero store fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM auth.users WHERE id IN (v_buy, v_merch, v_adm);
  r := r || public._qa_s13_ok('N4R35.S15 zero auth fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_fulfillment_events e
    LEFT JOIN public.marche_orders o ON o.id = e.order_id WHERE o.id IS NULL;
  r := r || public._qa_s13_ok('N4R35.S16 zero orphan events', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_fulfillment_observations ob
    LEFT JOIN public.marche_orders o ON o.id = ob.order_id WHERE o.id IS NULL;
  r := r || public._qa_s13_ok('N4R35.S17 zero orphan observations', v_n = 0, v_n::text);
  r := r || public._qa_s13_ok('N4R35.S18 has_role still not executable by anon',
        NOT has_function_privilege('anon','public.has_role(uuid,app_role)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R35.S19 finance policy surface untouched by R3.5',
        (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace
          AND proname LIKE 'marche_fulfillment%'
          AND (prosrc LIKE '%finance_policies%' OR prosrc LIKE '%wallet%'
            OR prosrc LIKE '%ledger%' OR prosrc LIKE '%payment_intent%')) = 0, NULL);
  r := r || public._qa_s13_ok('N4R35.S20 no R3.5 function emits a prediction',
        (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace
          AND proname LIKE 'marche_fulfillment%'
          AND (prosrc ILIKE '%predicted_eta%' OR prosrc ILIKE '%estimated_delivery%'
            OR prosrc ILIKE '%recommended_price%')) = 0, NULL);

  RETURN public._qa_s13_summary(35, r);
END $function$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r35() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node4_marche_r35() TO service_role;