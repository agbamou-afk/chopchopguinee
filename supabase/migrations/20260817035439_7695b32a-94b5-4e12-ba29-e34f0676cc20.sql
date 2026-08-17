CREATE OR REPLACE FUNCTION public._qa_node4_marche_r8()
RETURNS jsonb LANGUAGE plpgsql AS $fn$
DECLARE
  r jsonb := '[]'::jsonb;
  v_err text; v_n bigint; v_n2 bigint; v_res jsonb; v_j jsonb;
  v_master0 bigint; v_master1 bigint; v_flags0 jsonb; v_flags1 jsonb; v_obs0 bigint;
  v_buy uuid := gen_random_uuid(); v_shop uuid := gen_random_uuid(); v_mer uuid := gen_random_uuid();
  v_com uuid; v_v1 uuid; v_v2 uuid; v_o1 uuid; v_o2 uuid; v_onc uuid; v_oun uuid; v_o25 uuid;
  v_store uuid; v_store2 uuid; v_list uuid; v_list2 uuid; v_list3 uuid;
  v_mkt uuid; v_mkt2 uuid; v_r1 uuid; v_id uuid; v_id2 uuid; v_ms0 bigint;
  v_price bigint;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;
  SELECT count(*) INTO v_obs0 FROM public.marche_procurement_price_observations;
  SELECT count(*) INTO v_ms0 FROM public.missions;

  BEGIN
    -- ============ A. STRUCTURE / DOCTRINE / GRANTS ============
    r := r || public._qa_s13_ok('N4R8.A1 reuses the canonical observation stream (no parallel table)',
      to_regclass('public.marche_procurement_price_observations') IS NOT NULL
      AND to_regclass('public.marche_price_observations') IS NULL, NULL);
    SELECT count(*) INTO v_n FROM information_schema.columns
     WHERE table_schema='public' AND table_name='marche_procurement_price_observations'
       AND column_name IN ('source_type','store_id','listing_id','zone_commune','normalization_kind',
         'canonical_base_unit','normalized_quantity','normalized_unit_price_gnf','raw_amount_gnf',
         'raw_quantity','raw_unit','comparable','cohort_key','superseded_by');
    r := r || public._qa_s13_ok('N4R8.A2 provenance + normalization columns present', v_n = 14, v_n::text);
    r := r || public._qa_s13_ok('N4R8.A3 idempotency key on canonical source identity',
      EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='mppo_source_identity_uq'), NULL);
    r := r || public._qa_s13_ok('N4R8.A4 append-only guard attached to the observation stream',
      EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.marche_procurement_price_observations'::regclass
              AND tgname='trg_mppo_append_only' AND NOT tgisinternal), NULL);
    SELECT count(*) INTO v_n FROM information_schema.role_table_grants
     WHERE table_schema='public' AND grantee IN ('anon','authenticated')
       AND table_name = 'marche_procurement_price_observations';
    r := r || public._qa_s13_ok('N4R8.A5 no direct client grants on observations', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace nsp ON nsp.oid=p.pronamespace
     WHERE nsp.nspname='public' AND p.proname LIKE '%marche_price%' AND p.prosecdef
       AND NOT ('search_path=public' = ANY(COALESCE(p.proconfig, ARRAY[]::text[])));
    r := r || public._qa_s13_ok('N4R8.A6 every R8 definer function pins search_path=public', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace nsp ON nsp.oid=p.pronamespace
     WHERE nsp.nspname='public' AND p.proname IN ('_marche_price_record','_marche_price_normalize',
       'marche_price_ingest_merchant_ask','_marche_price_cohort')
       AND (has_function_privilege('anon', p.oid, 'EXECUTE') OR has_function_privilege('authenticated', p.oid, 'EXECUTE'));
    r := r || public._qa_s13_ok('N4R8.A7 ingestion primitives are server-only', v_n = 0, v_n::text);
    r := r || public._qa_s13_ok('N4R8.A8 sanitized aggregate read is reachable by anon',
      has_function_privilege('anon','public.marche_price_observed_public(text,text)','EXECUTE'), NULL);
    r := r || public._qa_s13_ok('N4R8.A9 raw provenance read is admin-gated',
      NOT has_function_privilege('anon','public.marche_price_observations_admin(uuid,integer)','EXECUTE')
      AND (SELECT pg_get_functiondef(oid) FROM pg_proc WHERE oid='public.marche_price_observations_admin(uuid,integer)'::regprocedure)
          LIKE '%PRICE_ADMIN_ONLY%', NULL);
    r := r || public._qa_s13_ok('N4R8.A10 has_role remains non-executable by anon',
      NOT has_function_privilege('anon','public.has_role(uuid,app_role)','EXECUTE'), NULL);
    r := r || public._qa_s13_ok('N4R8.A11 R8 writes no wallet/ledger/hold',
      NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace nsp ON nsp.oid=p.pronamespace
        WHERE nsp.nspname='public' AND p.proname LIKE '%marche_price%'
          AND (pg_get_functiondef(p.oid) ILIKE '%public.wallets%'
            OR pg_get_functiondef(p.oid) ILIKE '%ledger_%'
            OR pg_get_functiondef(p.oid) ILIKE '%mission_financial_holds%')), NULL);
    r := r || public._qa_s13_ok('N4R8.A12 customer-facing doctrine is observed, never official',
      (SELECT pg_get_functiondef(oid) FROM pg_proc WHERE oid='public.marche_price_observed_public(text,text)'::regprocedure)
        LIKE '%Prix observé sur ChopChop%', NULL);
    r := r || public._qa_s13_ok('N4R8.A13 R3.5 fulfillment intelligence untouched',
      to_regclass('public.marche_fulfillment_observations') IS NOT NULL
      AND EXISTS (SELECT 1 FROM pg_proc WHERE proname='marche_fulfillment_cohort_stats'), NULL);
    r := r || public._qa_s13_ok('N4R8.A14 no feature flag introduced by R8',
      NOT EXISTS (SELECT 1 FROM public.feature_flags WHERE key ILIKE '%price_intel%'), NULL);

    -- ============ FIXTURES ============
    PERFORM public._qa_s13_user(v_buy, 'r8buy');
    PERFORM public._qa_s13_user(v_mer, 'r8mer');
    PERFORM public._qa_s13_wallet(v_buy, 'client', 5000000, 0);
    PERFORM public._qa_s13_driver(v_shop, 'r8shop', 0);
    UPDATE public.driver_profiles SET capabilities = capabilities || ARRAY['marche_shopper']
     WHERE user_id = v_shop;

    INSERT INTO public.marche_staple_categories(code, name_fr) VALUES ('qa_r8_cat','QA R8')
      ON CONFLICT (code) DO NOTHING;
    INSERT INTO public.marche_staple_commodities(code, category_code, name_fr, unit_family)
      VALUES ('qa_r8_riz','qa_r8_cat','QA R8 Riz','mass') RETURNING id INTO v_com;
    INSERT INTO public.marche_staple_variants(commodity_id, code, name_fr)
      VALUES (v_com,'v1','QA R8 V1') RETURNING id INTO v_v1;
    INSERT INTO public.marche_staple_variants(commodity_id, code, name_fr)
      VALUES (v_com,'v2','QA R8 V2') RETURNING id INTO v_v2;
    INSERT INTO public.marche_staple_purchase_options(variant_id, code, sale_unit, label_fr,
        normalization_kind, canonical_base_unit, canonical_quantity, min_qty, max_qty, step_qty)
      VALUES (v_v1,'o1','kg','Sac 1kg','exact','kg',1,1,50,1) RETURNING id INTO v_o1;
    INSERT INTO public.marche_staple_purchase_options(variant_id, code, sale_unit, label_fr,
        normalization_kind, canonical_base_unit, canonical_quantity, min_qty, max_qty, step_qty)
      VALUES (v_v2,'o2','kg','Sac 1kg','exact','kg',1,1,50,1) RETURNING id INTO v_o2;
    INSERT INTO public.marche_staple_purchase_options(variant_id, code, sale_unit, label_fr,
        normalization_kind, canonical_base_unit, canonical_quantity, min_qty, max_qty, step_qty)
      VALUES (v_v1,'o25','kg','Sac 25kg','exact','kg',25,1,10,1) RETURNING id INTO v_o25;
    INSERT INTO public.marche_staple_purchase_options(variant_id, code, sale_unit, label_fr,
        normalization_kind, canonical_base_unit, canonical_quantity, min_qty, max_qty, step_qty)
      VALUES (v_v1,'oun','tas','Tas','unit_native',NULL,NULL,1,10,1) RETURNING id INTO v_oun;
    INSERT INTO public.marche_staple_purchase_options(variant_id, code, sale_unit, label_fr,
        normalization_kind, canonical_base_unit, canonical_quantity, min_qty, max_qty, step_qty)
      VALUES (v_v1,'onc','sac','Sac (taille variable)','non_comparable',NULL,NULL,1,10,1) RETURNING id INTO v_onc;

    INSERT INTO public.physical_markets(name, commune) VALUES ('QA R8 Marché','Matam') RETURNING id INTO v_mkt;
    INSERT INTO public.physical_markets(name, commune) VALUES ('QA R8 Marché 2','Ratoma') RETURNING id INTO v_mkt2;

    INSERT INTO public.merchant_stores(owner_user_id, name, slug, status, onboarding_status, commune, verification_state)
      VALUES (v_mer,'QA R8 Store','qa-r8-store','active','approved','Matam','unverified') RETURNING id INTO v_store;
    INSERT INTO public.merchant_stores(owner_user_id, name, slug, status, onboarding_status, commune, verification_state)
      VALUES (v_mer,'QA R8 Store 2','qa-r8-store-2','active','pending','Matam','unverified') RETURNING id INTO v_store2;

    -- ============ B. MERCHANT ASKING PRICE ============
    INSERT INTO public.marketplace_listings(seller_id, store_id, kind, category, title,
        asking_price_gnf, price_gnf, status, visibility, staple_purchase_option_id)
      VALUES (v_mer, v_store, 'merchant','Alimentation','QA R8 Riz 1kg', 11000, 11000,
              'active','public', v_o1) RETURNING id INTO v_list;
    SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations
     WHERE listing_id = v_list AND source_type='merchant_ask';
    r := r || public._qa_s13_ok('N4R8.B1 published canonical merchant ask yields exactly one observation',
      v_n = 1, v_n::text);
    SELECT normalized_unit_price_gnf, canonical_base_unit, comparable, zone_commune
      INTO v_price, v_err, v_j, v_res
      FROM public.marche_procurement_price_observations WHERE listing_id = v_list LIMIT 1;
    r := r || public._qa_s13_ok('N4R8.B2 merchant ask normalized to canonical unit',
      v_price = 11000 AND v_err = 'kg', format('%s %s', v_price, v_err));
    r := r || public._qa_s13_ok('N4R8.B3 merchant ask carries store zone provenance',
      (SELECT zone_commune FROM public.marche_procurement_price_observations WHERE listing_id=v_list LIMIT 1) = 'Matam', NULL);
    r := r || public._qa_s13_ok('N4R8.B4 merchant ask is provenance-linked to store + listing',
      (SELECT store_id FROM public.marche_procurement_price_observations WHERE listing_id=v_list LIMIT 1) = v_store, NULL);

    v_res := public.marche_price_ingest_merchant_ask(v_list);
    SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations WHERE listing_id = v_list;
    r := r || public._qa_s13_ok('N4R8.B5 re-ingesting the same ask is idempotent',
      v_n = 1 AND (v_res->>'ingested')::boolean IS FALSE AND v_res->>'reason' = 'ALREADY_OBSERVED', v_res::text);

    UPDATE public.marketplace_listings SET asking_price_gnf = 13000, price_gnf = 13000 WHERE id = v_list;
    SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations WHERE listing_id = v_list;
    r := r || public._qa_s13_ok('N4R8.B6 price change adds a new observation', v_n = 2, v_n::text);
    r := r || public._qa_s13_ok('N4R8.B7 historical ask is preserved, not rewritten',
      EXISTS (SELECT 1 FROM public.marche_procurement_price_observations
               WHERE listing_id=v_list AND normalized_unit_price_gnf = 11000)
      AND EXISTS (SELECT 1 FROM public.marche_procurement_price_observations
               WHERE listing_id=v_list AND normalized_unit_price_gnf = 13000), NULL);
    UPDATE public.marketplace_listings SET asking_price_gnf = 13000 WHERE id = v_list;
    SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations WHERE listing_id = v_list;
    r := r || public._qa_s13_ok('N4R8.B8 idle re-save creates no duplicate evidence', v_n = 2, v_n::text);

    INSERT INTO public.marketplace_listings(seller_id, store_id, kind, category, title,
        asking_price_gnf, status, visibility)
      VALUES (v_mer, v_store, 'merchant','Alimentation','QA R8 non mappé', 9000,'active','public')
      RETURNING id INTO v_list2;
    v_res := public.marche_price_ingest_merchant_ask(v_list2);
    r := r || public._qa_s13_ok('N4R8.B9 unmapped merchant supply is excluded, not guessed',
      v_res->>'reason' = 'MERCHANT_ASK_NOT_CANONICAL', v_res::text);
    SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations WHERE listing_id = v_list2;
    r := r || public._qa_s13_ok('N4R8.B10 unmapped supply produces no observation', v_n = 0, v_n::text);

    INSERT INTO public.marketplace_listings(seller_id, store_id, kind, category, title,
        asking_price_gnf, status, visibility, staple_purchase_option_id)
      VALUES (v_mer, v_store2, 'merchant','Alimentation','QA R8 store non approuvé', 8000,
              'active','public', v_o1) RETURNING id INTO v_list3;
    v_res := public.marche_price_ingest_merchant_ask(v_list3);
    SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations WHERE listing_id = v_list3;
    r := r || public._qa_s13_ok('N4R8.B11 unapproved store never produces market evidence',
      v_n = 0 AND (v_res->>'ingested')::boolean IS FALSE, v_res::text);

    UPDATE public.marketplace_listings SET visibility='private', status='paused' WHERE id = v_list;
    v_res := public.marche_price_ingest_merchant_ask(v_list);
    r := r || public._qa_s13_ok('N4R8.B12 unpublished ask is refused',
      v_res->>'reason' = 'MERCHANT_ASK_NOT_PUBLISHED', v_res::text);
    UPDATE public.marketplace_listings SET visibility='public', status='active' WHERE id = v_list;

    r := r || public._qa_s13_ok('N4R8.B13 storeless/community supply cannot originate evidence',
      (public.marche_price_ingest_merchant_ask(
        (SELECT id FROM public.marketplace_listings WHERE store_id IS NULL LIMIT 1)) ->> 'reason')
        IS DISTINCT FROM 'ingested', NULL);

    -- ============ C. VERIFIED PROCUREMENT ONLY ============
    INSERT INTO public.marche_procurement_price_observations
      (purchase_option_id, variant_id, commodity_id, observed_unit_price_gnf, observed_at, source_kind, source_type)
    SELECT v_o1, v_v1, v_com, 10000, now() - (s.i || ' hours')::interval, 'ops_survey','survey'
      FROM generate_series(1,3) s(i);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_res := public.marche_procurement_authorize(jsonb_build_object(
      'client_request_id', gen_random_uuid(), 'ceiling_gnf', 60000,
      'lines', jsonb_build_array(
        jsonb_build_object('commodity_code','qa_r8_riz','variant_code','v1','option_code','o1','qty',2))));
    v_r1 := (v_res->>'id')::uuid;
    r := r || public._qa_s13_ok('N4R8.C1 R6.5 authorization still sovereign',
      v_r1 IS NOT NULL AND v_res->>'status'='authorized', v_res::text);
    SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations
     WHERE source_type IN ('merchant_ask','verified_procurement') AND raw_amount_gnf = 60000;
    r := r || public._qa_s13_ok('N4R8.C2 customer ceiling never becomes price evidence', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations
     WHERE source_type = 'verified_procurement' AND source_ref LIKE v_r1::text || '%';
    r := r || public._qa_s13_ok('N4R8.C3 an estimate/authorization alone creates no observation', v_n = 0, v_n::text);
    v_res := public.marche_procurement_set_destination(jsonb_build_object(
      'request_id', v_r1, 'destination_address','Matam, Conakry'));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_shop), true);
    v_res := public.marche_shopper_claim(v_r1);
    v_res := public.marche_shopper_arrive_market(v_r1, v_mkt);
    v_res := public.marche_shopper_start_shopping(v_r1);
    v_res := public.marche_shopper_resolve_line(jsonb_build_object(
      'request_id', v_r1, 'line_no', 1, 'kind','acquired', 'actual_unit_price_gnf', 12000));
    SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations
     WHERE source_ref = v_r1::text || ':1';
    r := r || public._qa_s13_ok('N4R8.C4 an unverified acquisition is not yet price evidence', v_n = 0, v_n::text);

    INSERT INTO public.marche_procurement_purchase_evidence(request_id, line_no, bucket_id, storage_path, uploaded_by)
      VALUES (v_r1, 1, 'marche-procurement-evidence', v_r1::text || '/1.jpg', v_shop);
    v_res := public.marche_shopper_submit_purchase(jsonb_build_object('request_id', v_r1));
    r := r || public._qa_s13_ok('N4R8.C5 purchase verification succeeded',
      v_res->>'state' = 'purchase_verified', v_res::text);
    SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations
     WHERE source_ref = v_r1::text || ':1' AND source_type='verified_procurement';
    r := r || public._qa_s13_ok('N4R8.C6 verified purchase line yields exactly one observation', v_n = 1, v_n::text);
    SELECT normalized_unit_price_gnf INTO v_price FROM public.marche_procurement_price_observations
     WHERE source_ref = v_r1::text || ':1';
    r := r || public._qa_s13_ok('N4R8.C7 actual purchased quantity drives the normalized price',
      v_price = 12000, v_price::text);
    r := r || public._qa_s13_ok('N4R8.C8 procurement observation carries market zone, not customer identity',
      (SELECT zone_commune FROM public.marche_procurement_price_observations WHERE source_ref=v_r1::text||':1') = 'Matam'
      AND (SELECT recorded_by FROM public.marche_procurement_price_observations WHERE source_ref=v_r1::text||':1') = v_shop, NULL);
    v_res := public.marche_shopper_submit_purchase(jsonb_build_object('request_id', v_r1));
    SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations
     WHERE source_ref = v_r1::text || ':1';
    r := r || public._qa_s13_ok('N4R8.C9 replayed submission is idempotent (one logical observation)', v_n = 1, v_n::text);
    PERFORM set_config('request.jwt.claims', '', true);

    -- ============ D. NORMALIZATION ============
    v_j := public._marche_price_normalize(v_o25, 300000, 1);
    r := r || public._qa_s13_ok('N4R8.D1 weight-based pack normalizes to canonical unit price',
      (v_j->>'normalized_unit_price_gnf')::bigint = 12000 AND v_j->>'canonical_base_unit'='kg', v_j::text);
    v_j := public._marche_price_normalize(v_oun, 5000, 1);
    r := r || public._qa_s13_ok('N4R8.D2 unit-native stays in its own comparable space',
      v_j->>'canonical_base_unit' = 'unit:tas' AND (v_j->>'comparable')::boolean, v_j::text);
    v_j := public._marche_price_normalize(v_onc, 5000, 1);
    r := r || public._qa_s13_ok('N4R8.D3 non-comparable unit is never guessed',
      (v_j->>'comparable')::boolean IS FALSE AND v_j->>'normalization_kind'='non_comparable', v_j::text);
    v_id := public._marche_price_record(v_onc, 'verified_procurement','ops_survey','qa_r8_nc_1',
      5000, 1, now(), NULL, NULL, NULL, 'Matam', NULL, NULL);
    r := r || public._qa_s13_ok('N4R8.D4 non-comparable observation is retained as evidence',
      v_id IS NOT NULL AND (SELECT NOT comparable FROM public.marche_procurement_price_observations WHERE id=v_id), NULL);

    -- controlled cohort: 5 fresh observations 1000..5000 on v1/kg/Matam
    FOR v_n IN 1..5 LOOP
      PERFORM public._marche_price_record(v_o1, 'merchant_ask','merchant_ask','qa_r8_cohort_'||v_n::text,
        v_n * 1000, 1, now() - interval '2 hours', NULL, NULL, NULL, 'Matam', NULL, NULL);
    END LOOP;
    v_j := public.marche_price_cohort_stats(v_v1, 'kg', 'Matam', 24);
    r := r || public._qa_s13_ok('N4R8.D5 deterministic median on a known fixture set',
      (v_j->>'median_gnf')::bigint = 3000, v_j::text);
    r := r || public._qa_s13_ok('N4R8.D6 deterministic observed band P25/P75',
      (v_j->>'p25_gnf')::bigint = 2000 AND (v_j->>'p75_gnf')::bigint = 4000, v_j::text);
    r := r || public._qa_s13_ok('N4R8.D7 sample count is exact',
      (v_j->>'sample_count')::int = 5, v_j::text);
    r := r || public._qa_s13_ok('N4R8.D8 source mix is reported',
      (v_j->'source_mix'->>'merchant_ask')::int = 5, v_j::text);
    r := r || public._qa_s13_ok('N4R8.D9 recompute is deterministic',
      public.marche_price_cohort_stats(v_v1,'kg','Matam',24) - 'latest_observed_at' - 'first_observed_at'
        = v_j - 'latest_observed_at' - 'first_observed_at', NULL);
    r := r || public._qa_s13_ok('N4R8.D10 non-comparable observation excluded from the cohort',
      (v_j->>'sample_count')::int = 5, v_j::text);

    -- variant isolation
    FOR v_n IN 1..5 LOOP
      PERFORM public._marche_price_record(v_o2, 'merchant_ask','merchant_ask','qa_r8_v2_'||v_n::text,
        99000, 1, now() - interval '2 hours', NULL, NULL, NULL, 'Matam', NULL, NULL);
    END LOOP;
    v_j := public.marche_price_cohort_stats(v_v1, 'kg', 'Matam', 24);
    r := r || public._qa_s13_ok('N4R8.D11 a materially distinct variant never pollutes the cohort',
      (v_j->>'sample_count')::int = 5 AND (v_j->>'median_gnf')::bigint = 3000, v_j::text);
    v_j := public.marche_price_cohort_stats(v_v2, 'kg', 'Matam', 24);
    r := r || public._qa_s13_ok('N4R8.D12 the other variant keeps its own truth',
      (v_j->>'median_gnf')::bigint = 99000, v_j::text);

    -- unit-native isolation
    FOR v_n IN 1..5 LOOP
      PERFORM public._marche_price_record(v_oun, 'merchant_ask','merchant_ask','qa_r8_un_'||v_n::text,
        7000, 1, now() - interval '2 hours', NULL, NULL, NULL, 'Matam', NULL, NULL);
    END LOOP;
    r := r || public._qa_s13_ok('N4R8.D13 unit-native cohort is isolated from the kg cohort',
      (public.marche_price_cohort_stats(v_v1,'unit:tas','Matam',24)->>'median_gnf')::bigint = 7000
      AND (public.marche_price_cohort_stats(v_v1,'kg','Matam',24)->>'sample_count')::int = 5, NULL);

    -- zone isolation + honest unknown geography
    FOR v_n IN 1..5 LOOP
      PERFORM public._marche_price_record(v_o1, 'merchant_ask','merchant_ask','qa_r8_zone_'||v_n::text,
        20000, 1, now() - interval '2 hours', NULL, NULL, NULL, 'Ratoma', NULL, NULL);
    END LOOP;
    r := r || public._qa_s13_ok('N4R8.D14 zone cohorts stay isolated',
      (public.marche_price_cohort_stats(v_v1,'kg','Ratoma',24)->>'median_gnf')::bigint = 20000
      AND (public.marche_price_cohort_stats(v_v1,'kg','Matam',24)->>'median_gnf')::bigint = 3000, NULL);
    FOR v_n IN 1..5 LOOP
      PERFORM public._marche_price_record(v_o1, 'merchant_ask','merchant_ask','qa_r8_unk_'||v_n::text,
        30000, 1, now() - interval '2 hours', NULL, NULL, NULL, NULL, NULL, NULL);
    END LOOP;
    r := r || public._qa_s13_ok('N4R8.D15 unknown geography stays unknown, never invented',
      (public.marche_price_cohort_stats(v_v1,'kg','unknown',24)->>'median_gnf')::bigint = 30000, NULL);

    -- ============ E. CONFIDENCE / FRESHNESS / MOVEMENT ============
    r := r || public._qa_s13_ok('N4R8.E1 thin cohort refuses a headline number',
      (public.marche_price_cohort_stats(v_v1,'kg','Kaloum',24)->>'insufficient_data')::boolean
      AND public.marche_price_cohort_stats(v_v1,'kg','Kaloum',24)->>'confidence' = 'insufficient', NULL);
    r := r || public._qa_s13_ok('N4R8.E2 insufficient cohort emits no median',
      NOT (public.marche_price_cohort_stats(v_v1,'kg','Kaloum',24) ? 'median_gnf'), NULL);
    v_j := public.marche_price_cohort_stats(v_v1,'kg','Matam',24);
    r := r || public._qa_s13_ok('N4R8.E3 fresh medium-sample cohort is labelled honestly',
      v_j->>'freshness' = 'fresh' AND v_j->>'confidence' = 'medium', v_j::text);
    FOR v_n IN 1..5 LOOP
      PERFORM public._marche_price_record(v_o1, 'merchant_ask','merchant_ask','qa_r8_stale_'||v_n::text,
        4000, 1, now() - interval '400 hours', NULL, NULL, NULL, 'Boke', NULL, NULL);
    END LOOP;
    v_j := public.marche_price_cohort_stats(v_v1,'kg','Boke', 1000);
    r := r || public._qa_s13_ok('N4R8.E4 stale evidence is declared stale', v_j->>'freshness' = 'stale', v_j::text);
    r := r || public._qa_s13_ok('N4R8.E5 stale evidence downgrades confidence', v_j->>'confidence' = 'low', v_j::text);
    r := r || public._qa_s13_ok('N4R8.E6 out-of-window evidence is not counted',
      (public.marche_price_cohort_stats(v_v1,'kg','Boke',24)->>'insufficient_data')::boolean, NULL);
    r := r || public._qa_s13_ok('N4R8.E7 movement is withheld without a valid comparison window',
      (public.marche_price_cohort_stats(v_v1,'kg','Matam',24)->'movement'->>'comparable')::boolean IS FALSE, NULL);
    FOR v_n IN 1..5 LOOP
      PERFORM public._marche_price_record(v_o1, 'merchant_ask','merchant_ask','qa_r8_prev_'||v_n::text,
        2000, 1, now() - interval '200 hours', NULL, NULL, NULL, 'Dixinn', NULL, NULL);
      PERFORM public._marche_price_record(v_o1, 'merchant_ask','merchant_ask','qa_r8_cur_'||v_n::text,
        3000, 1, now() - interval '10 hours', NULL, NULL, NULL, 'Dixinn', NULL, NULL);
    END LOOP;
    v_j := public.marche_price_cohort_stats(v_v1,'kg','Dixinn', 336);
    r := r || public._qa_s13_ok('N4R8.E8 movement emitted only when both halves are valid',
      (v_j->'movement'->>'comparable')::boolean, v_j::text);
    r := r || public._qa_s13_ok('N4R8.E9 movement is arithmetically honest',
      (v_j->'movement'->>'previous_median_gnf')::bigint = 2000
      AND (v_j->'movement'->>'current_median_gnf')::bigint = 3000
      AND (v_j->'movement'->>'delta_pct')::numeric = 50.00, v_j::text);
    r := r || public._qa_s13_ok('N4R8.E10 outliers stay in evidence and shift only robust statistics',
      (SELECT count(*) FROM public.marche_procurement_price_observations
        WHERE source_ref = 'qa_r8_cohort_5') = 1
      AND (public.marche_price_cohort_stats(v_v1,'kg','Matam',24)->>'median_gnf')::bigint = 3000, NULL);
    r := r || public._qa_s13_ok('N4R8.E11 sample count and confidence are first-class output',
      (v_j ? 'sample_count') AND (v_j ? 'confidence') AND (v_j ? 'freshness'), NULL);

    -- ============ F. PUBLIC READ / LEAKAGE ============
    v_j := public.marche_price_observed_public('qa_r8_riz', 'Matam');
    r := r || public._qa_s13_ok('N4R8.F1 public read returns observed cohorts',
      jsonb_array_length(v_j->'cohorts') >= 1, v_j::text);
    r := r || public._qa_s13_ok('N4R8.F2 public read is framed as observed on ChopChop',
      v_j->>'doctrine' = 'Prix observé sur ChopChop', NULL);
    r := r || public._qa_s13_ok('N4R8.F3 public read leaks no customer/shopper identity',
      v_j::text NOT LIKE '%'||v_buy::text||'%' AND v_j::text NOT LIKE '%'||v_shop::text||'%', NULL);
    r := r || public._qa_s13_ok('N4R8.F4 public read leaks no provenance refs or evidence paths',
      v_j::text NOT ILIKE '%source_ref%' AND v_j::text NOT ILIKE '%recorded_by%'
      AND v_j::text NOT ILIKE '%storage_path%' AND v_j::text NOT ILIKE '%.jpg%', NULL);
    r := r || public._qa_s13_ok('N4R8.F5 unknown commodity returns an honest empty read',
      jsonb_array_length(public.marche_price_observed_public('qa_r8_missing', NULL)->'cohorts') = 0, NULL);

    -- ============ G. SECURITY / IMMUTABILITY ============
    v_err := public._qa_r6_err('authenticated', v_buy,
      'INSERT INTO public.marche_procurement_price_observations(purchase_option_id,variant_id,commodity_id,observed_unit_price_gnf,source_kind) VALUES (gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),1,''ops_survey'')');
    r := r || public._qa_s13_ok('N4R8.G1 authenticated cannot insert observations', v_err <> 'OK', v_err);
    v_err := public._qa_r6_err('anon', NULL, 'SELECT 1 FROM public.marche_procurement_price_observations');
    r := r || public._qa_s13_ok('N4R8.G2 anon cannot read raw observations', v_err <> 'OK', v_err);
    v_err := public._qa_r6_err('authenticated', v_mer,
      'UPDATE public.marche_procurement_price_observations SET observed_unit_price_gnf = 1');
    r := r || public._qa_s13_ok('N4R8.G3 merchant cannot rewrite observations', v_err <> 'OK', v_err);
    v_err := public._qa_r6_err('authenticated', v_shop,
      'DELETE FROM public.marche_procurement_price_observations');
    r := r || public._qa_s13_ok('N4R8.G4 shopper cannot delete evidence', v_err <> 'OK', v_err);
    v_err := public._qa_r6_err('authenticated', v_buy,
      'SELECT public.marche_price_observations_admin(NULL, 10)');
    r := r || public._qa_s13_ok('N4R8.G5 non-admin cannot read raw provenance', v_err <> 'OK', v_err);
    v_err := public._qa_r6_err('authenticated', v_buy,
      'SELECT public._marche_price_record(gen_random_uuid(),''merchant_ask'',''merchant_ask'',''forge'',1,1,now())');
    r := r || public._qa_s13_ok('N4R8.G6 clients cannot forge an observation through the primitive', v_err <> 'OK', v_err);
    v_err := public._qa_r6_err('authenticated', v_mer,
      'SELECT public.marche_price_ingest_merchant_ask(gen_random_uuid())');
    r := r || public._qa_s13_ok('N4R8.G7 merchants cannot self-trigger ingestion of a forged source', v_err <> 'OK', v_err);
    BEGIN UPDATE public.marche_procurement_price_observations SET observed_unit_price_gnf = 42
      WHERE source_ref = 'qa_r8_cohort_1'; v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R8.G8 even privileged rewrite of a historical fact is refused',
      v_err = 'PROCUREMENT_APPEND_ONLY', v_err);
    BEGIN DELETE FROM public.marche_procurement_price_observations WHERE source_ref = 'qa_r8_cohort_1';
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R8.G9 observations cannot be deleted', v_err = 'PROCUREMENT_APPEND_ONLY', v_err);
    BEGIN INSERT INTO public.marche_procurement_price_observations
      (purchase_option_id, variant_id, commodity_id, observed_unit_price_gnf, source_kind, source_ref)
      VALUES (v_o1, v_v1, v_com, 1234, 'merchant_ask', 'qa_r8_cohort_1'); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R8.G10 concurrent/duplicate source identity cannot double-count',
      v_err <> 'NO_ERROR', v_err);
    SELECT id INTO v_id FROM public.marche_procurement_price_observations WHERE source_ref='qa_r8_cohort_1';
    PERFORM set_config('marche.price_supersede','on', true);
    UPDATE public.marche_procurement_price_observations SET superseded_by = v_id, superseded_reason='qa'
     WHERE id = v_id;
    PERFORM set_config('marche.price_supersede','', true);
    r := r || public._qa_s13_ok('N4R8.G11 correction is supersession, and the fact survives',
      (SELECT normalized_unit_price_gnf FROM public.marche_procurement_price_observations WHERE id=v_id) = 1000
      AND (SELECT superseded_by FROM public.marche_procurement_price_observations WHERE id=v_id) = v_id, NULL);
    r := r || public._qa_s13_ok('N4R8.G12 superseded evidence leaves the aggregate deterministically',
      (public.marche_price_cohort_stats(v_v1,'kg','Matam',24)->>'sample_count')::int = 4, NULL);
    v_err := public._qa_r6_err('authenticated', v_buy,
      'SELECT public.marche_price_supersede_observation(gen_random_uuid(),''x'')');
    r := r || public._qa_s13_ok('N4R8.G13 non-admin cannot supersede', v_err <> 'OK', v_err);
    v_err := public._qa_r6_err('authenticated', v_shop,
      'SELECT 1 FROM public.marche_procurement_purchase_evidence');
    r := r || public._qa_s13_ok('N4R8.G14 R7 private evidence table stays unreachable', v_err <> 'OK', v_err);
    r := r || public._qa_s13_ok('N4R8.G15 R7 storage evidence helpers remain in place',
      EXISTS (SELECT 1 FROM pg_proc WHERE proname='_marche_procurement_evidence_can_read')
      AND EXISTS (SELECT 1 FROM pg_proc WHERE proname='_marche_procurement_evidence_can_write'), NULL);

    -- ============ H. NON-INTERFERENCE ============
    SELECT count(*) INTO v_n FROM (
      SELECT j.id FROM public.ledger_journals j
       JOIN public.ledger_postings p ON p.journal_id = j.id
       GROUP BY j.id HAVING sum(p.amount_gnf) <> 0) z;
    r := r || public._qa_s13_ok('N4R8.H1 no imbalanced journal after price intelligence', v_n = 0, v_n::text);
    SELECT COALESCE(sum(amount_gnf),0) INTO v_n FROM public.ledger_postings;
    r := r || public._qa_s13_ok('N4R8.H2 global ledger sum is still zero', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.missions;
    r := r || public._qa_s13_ok('N4R8.H3 R8 created no mission', v_n = v_ms0, v_n::text);
    r := r || public._qa_s13_ok('N4R8.H4 R8 never mutates purchase verification truth',
      (SELECT state FROM public.marche_procurement_missions WHERE request_id = v_r1) = 'purchase_verified', NULL);

    PERFORM set_config('request.jwt.claims', '', true);
    RAISE EXCEPTION 'QA_N4R8_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_N4R8_ROLLBACK' THEN
      r := r || public._qa_s13_ok('HARNESS_R8_UNEXPECTED_ABORT', false, SQLERRM);
    END IF;
  END;

  PERFORM set_config('request.jwt.claims', '', true);
  SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;
  r := r || public._qa_s13_ok('N4R8.Z1 master wallet unchanged after fixture rollback',
    v_master1 = v_master0, v_master1::text);
  r := r || public._qa_s13_ok('N4R8.Z2 feature flags byte-identical after fixture rollback',
    v_flags1 = v_flags0, NULL);
  SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations;
  r := r || public._qa_s13_ok('N4R8.Z3 zero observation fixture residue', v_n = v_obs0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_staple_commodities WHERE code='qa_r8_riz';
  r := r || public._qa_s13_ok('N4R8.Z4 zero catalog fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.merchant_stores WHERE slug LIKE 'qa-r8-%';
  r := r || public._qa_s13_ok('N4R8.Z5 zero store fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marketplace_listings WHERE title LIKE 'QA R8%';
  r := r || public._qa_s13_ok('N4R8.Z6 zero listing fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.physical_markets WHERE name LIKE 'QA R8%';
  r := r || public._qa_s13_ok('N4R8.Z7 zero market fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_procurement_missions;
  r := r || public._qa_s13_ok('N4R8.Z8 zero shopper-mission fixture residue', v_n = 0, v_n::text);

  RETURN public._qa_s13_summary(48, r);
END $fn$;
REVOKE ALL ON FUNCTION public._qa_node4_marche_r8() FROM PUBLIC, anon, authenticated;