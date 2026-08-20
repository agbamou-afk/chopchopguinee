CREATE OR REPLACE FUNCTION public.marche_ranking_policy_public()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE pol jsonb := public._marche_ranking_policy(now());
BEGIN
  IF pol IS NULL THEN
    RETURN jsonb_build_object('available', false, 'reason', 'NO_EFFECTIVE_RANKING_POLICY');
  END IF;
  RETURN jsonb_build_object(
    'available', true,
    'version', (pol->>'version')::int,
    'label', pol->>'label',
    'effective_from', pol->>'effective_from',
    'weights_bps', jsonb_build_object(
      'price', (pol->>'w_price')::int,
      'reputation', (pol->>'w_reputation')::int,
      'reliability', (pol->>'w_reliability')::int,
      'distance', (pol->>'w_distance')::int,
      'price_freshness', (pol->>'w_freshness')::int,
      'responsiveness', (pol->>'w_responsiveness')::int,
      'preparation', (pol->>'w_preparation')::int),
    'thresholds', jsonb_build_object(
      'min_price_observations', (pol->>'min_price_observations')::int,
      'min_reputation_events', (pol->>'min_reputation_events')::int,
      'min_fulfillment_history', (pol->>'min_fulfillment_history')::int,
      'min_fulfillment_observations', (pol->>'min_fulfillment_observations')::int,
      'min_qualified_components', (pol->>'min_qualified_components')::int,
      'distance_max_m', (pol->>'distance_max_m')::int),
    'lookbacks', jsonb_build_object(
      'price_hours', (pol->>'price_lookback_hours')::int,
      'reliability_days', (pol->>'reliability_lookback_days')::int,
      'fulfillment_days', (pol->>'fulfillment_lookback_days')::int),
    'doctrine', 'Classement fondé sur des preuves. Aucune mise en avant payante.',
    'price_freshness_source', 'observations_de_prix_verifiees',
    'availability_accuracy_collected', false,
    'cold_start_behaviour', 'aucun_score_invente',
    'distance_method', 'haversine_great_circle'
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public._qa_node4_marche_r10()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_buy uuid := gen_random_uuid();
  v_m1 uuid := gen_random_uuid(); v_m2 uuid := gen_random_uuid();
  v_m3 uuid := gen_random_uuid(); v_m4 uuid := gen_random_uuid();
  v_drv uuid := gen_random_uuid(); v_nodrv uuid := gen_random_uuid();
  s1 uuid; s2 uuid; s3 uuid; s4 uuid;
  la uuid; lb uuid; lc uuid; ld uuid; le uuid; lf uuid;
  lz1 uuid; lz2 uuid; lz3 uuid; lz4 uuid; lz5 uuid;
  ln uuid; l3 uuid; l4 uuid; lag uuid; lst uuid;
  v_opt uuid; v_var uuid; v_oid uuid;
  base_obs int; base_rep int; base_ord int; base_pol int; base_lst int;
  base_req int; base_fob int; base_mis int;
  ev jsonb; ev2 jsonb; ev3 jsonb; j jsonb; pol jsonb; cmp jsonb;
  v_n bigint; v_err text; i int; rq uuid; fdef text;
  d1 jsonb; d2 jsonb; pa int; pe int; ordid uuid;
BEGIN
  SELECT count(*) INTO base_obs FROM public.marche_procurement_price_observations;
  SELECT count(*) INTO base_rep FROM public.marche_reputation_events;
  SELECT count(*) INTO base_ord FROM public.marche_orders;
  SELECT count(*) INTO base_pol FROM public.marche_ranking_policies;
  SELECT count(*) INTO base_lst FROM public.marketplace_listings;
  SELECT count(*) INTO base_req FROM public.marche_procurement_requests;
  SELECT count(*) INTO base_fob FROM public.marche_fulfillment_observations;
  SELECT count(*) INTO base_mis FROM public.marche_procurement_missions;

  ---------------------------------------------------------------- A) STATIC LAW
  FOR fdef IN SELECT unnest(ARRAY[
      '_marche_rank_evidence','_marche_ranking_policy','marche_ranking_policy_public',
      'marche_listing_rank_explain','marche_ranking_policy_admin_list',
      'marche_ranking_policy_publish','marche_ranking_audit_listing',
      'marche_shopper_performance','marche_listings_discover'])
  LOOP
    r := r || public._qa_s13_ok(
      format('N4R10.A search_path is pinned on %s', fdef),
      (SELECT bool_and(p.proconfig::text LIKE '%search_path=public%')
         FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.proname=fdef), fdef);
  END LOOP;

  r := r || public._qa_s13_ok('N4R10.A1 the ranking policy table exists and is versioned',
    (SELECT count(*) FROM information_schema.columns
      WHERE table_schema='public' AND table_name='marche_ranking_policies'
        AND column_name IN ('version','effective_from','effective_to')) = 3, NULL);
  r := r || public._qa_s13_ok('N4R10.A2 exactly one ranking policy is currently effective',
    (SELECT count(*) FROM public.marche_ranking_policies WHERE effective_to IS NULL) = 1, NULL);
  r := r || public._qa_s13_ok('N4R10.A3 the policy declares every weight explicitly',
    (SELECT count(*) FROM information_schema.columns
      WHERE table_schema='public' AND table_name='marche_ranking_policies'
        AND column_name IN ('w_price','w_reputation','w_reliability','w_distance',
                            'w_freshness','w_responsiveness','w_preparation')) = 7, NULL);
  r := r || public._qa_s13_ok('N4R10.A4 the policy declares every observation window explicitly',
    (SELECT count(*) FROM information_schema.columns
      WHERE table_schema='public' AND table_name='marche_ranking_policies'
        AND column_name IN ('price_lookback_hours','reliability_lookback_days',
                            'fulfillment_lookback_days','min_fulfillment_observations',
                            'min_qualified_components')) = 5, NULL);
  r := r || public._qa_s13_ok('N4R10.A5 listing age is no longer a ranking law',
    NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='marche_ranking_policies'
                   AND column_name='freshness_half_life_days'), NULL);
  r := r || public._qa_s13_ok('N4R10.A6 the declared weights always add up to 100%',
    (SELECT bool_and(w_price+w_reputation+w_reliability+w_distance+w_freshness
                     +w_responsiveness+w_preparation = 10000)
       FROM public.marche_ranking_policies), NULL);
  r := r || public._qa_s13_ok('N4R10.A7 price evidence requires at least five observations',
    (SELECT bool_and(min_price_observations >= 5) FROM public.marche_ranking_policies), NULL);
  r := r || public._qa_s13_ok('N4R10.A8 the evidence engine is read-only (STABLE)',
    (SELECT provolatile FROM pg_proc
      WHERE oid='public._marche_rank_evidence(uuid,double precision,double precision,jsonb,timestamptz)'::regprocedure) = 's', NULL);
  r := r || public._qa_s13_ok('N4R10.A9 shopper intelligence is read-only (STABLE)',
    (SELECT provolatile FROM pg_proc WHERE oid='public.marche_shopper_performance(uuid)'::regprocedure) = 's', NULL);

  fdef := (SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname='_marche_rank_evidence');
  r := r || public._qa_s13_ok('N4R10.A10 ranking never reads a paid boost / sponsorship field',
    fdef !~* '(sponsor|boost|promoted|paid_rank|ad_spend)', NULL);
  r := r || public._qa_s13_ok('N4R10.A11 discovery never reads a paid boost / sponsorship field',
    (SELECT bool_and(pg_get_functiondef(oid) !~* '(sponsor|boost|promoted|paid_rank|ad_spend)')
       FROM pg_proc WHERE proname='marche_listings_discover'), NULL);
  r := r || public._qa_s13_ok('N4R10.A12 price freshness is read from observed prices only',
    fdef LIKE '%marche_price_freshness(own_latest)%'
    AND fdef LIKE '%r8_merchant_ask_freshness%'
    AND fdef NOT LIKE '%half_life%', NULL);
  r := r || public._qa_s13_ok('N4R10.A13 price evidence excludes the listing''s own observation',
    fdef LIKE '%o.listing_id <> l.id%', NULL);
  r := r || public._qa_s13_ok('N4R10.A14 price cohorts are isolated by zone and canonical unit',
    fdef LIKE '%o.zone_commune IS NOT DISTINCT FROM own_zone%'
    AND fdef LIKE '%o.canonical_base_unit = own_unit%', NULL);
  r := r || public._qa_s13_ok('N4R10.A15 reliability counts merchant decisions only',
    fdef LIKE '%buyer_cancellation_counted%' AND fdef LIKE '%courier_failure_counted%', NULL);
  r := r || public._qa_s13_ok('N4R10.A16 responsiveness and preparation come from observed timings',
    fdef LIKE '%COMMIT_TO_MERCHANT_ACCEPTED%' AND fdef LIKE '%MERCHANT_ACCEPTED_TO_READY%', NULL);
  r := r || public._qa_s13_ok('N4R10.A17 a policy publication must state every field',
    (SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname='marche_ranking_policy_publish')
      LIKE '%POLICY_FIELD_REQUIRED%', NULL);

  --------------------------------------------------------------- B) SECURITY LAW
  r := r || public._qa_s13_ok('N4R10.B1 anon cannot read the ranking policy table',
    NOT has_table_privilege('anon','public.marche_ranking_policies','SELECT'), NULL);
  r := r || public._qa_s13_ok('N4R10.B2 signed-in users cannot read the ranking policy table',
    NOT has_table_privilege('authenticated','public.marche_ranking_policies','SELECT'), NULL);
  r := r || public._qa_s13_ok('N4R10.B3 signed-in users cannot write the ranking policy table',
    NOT has_table_privilege('authenticated','public.marche_ranking_policies','INSERT')
    AND NOT has_table_privilege('authenticated','public.marche_ranking_policies','UPDATE')
    AND NOT has_table_privilege('authenticated','public.marche_ranking_policies','DELETE'), NULL);
  r := r || public._qa_s13_ok('N4R10.B4 anon cannot execute the internal evidence engine',
    NOT has_function_privilege('anon','public._marche_rank_evidence(uuid,double precision,double precision,jsonb,timestamptz)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R10.B5 signed-in users cannot execute the internal evidence engine',
    NOT has_function_privilege('authenticated','public._marche_rank_evidence(uuid,double precision,double precision,jsonb,timestamptz)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R10.B6 anon cannot execute any R10 admin surface',
    NOT has_function_privilege('anon','public.marche_ranking_policy_publish(jsonb)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_ranking_policy_admin_list()','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_ranking_audit_listing(uuid,double precision,double precision)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_shopper_performance(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R10.B7 anon can browse with and without coordinates',
    has_function_privilege('anon','public.marche_listings_discover(text,text,uuid,text,integer,integer)','EXECUTE')
    AND has_function_privilege('anon','public.marche_listings_discover(text,text,uuid,text,integer,integer,double precision,double precision)','EXECUTE')
    AND has_function_privilege('anon','public.marche_ranking_policy_public()','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R10.B8 anon still cannot execute the admin role helper (P15.5)',
    NOT has_function_privilege('anon','public.has_role(uuid,app_role)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R10.B9 exactly two discovery arities exist (no ambiguity)',
    (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='marche_listings_discover') = 2
    AND (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
          WHERE n.nspname='public' AND p.proname='marche_listings_discover'
            AND p.pronargdefaults > 0 AND p.pronargs = 8) = 0, NULL);

  ------------------------------------------------------------- C) LIVE FIXTURES
  BEGIN
    SELECT po.id, po.variant_id INTO v_opt, v_var
      FROM public.marche_staple_purchase_options po
     WHERE po.is_active AND po.normalization_kind='exact' AND po.canonical_quantity = 1
     ORDER BY po.created_at LIMIT 1;
    IF v_opt IS NULL THEN RAISE EXCEPTION 'QA_R10_NO_CANONICAL_OPTION'; END IF;

    PERFORM public._qa_s13_user(v_buy,'n410b');
    PERFORM public._qa_s13_user(v_m1,'n410m1');
    PERFORM public._qa_s13_user(v_m2,'n410m2');
    PERFORM public._qa_s13_user(v_m3,'n410m3');
    PERFORM public._qa_s13_user(v_m4,'n410m4');
    PERFORM public._qa_s13_driver(v_drv,'n410d',0);
    PERFORM public._qa_s13_driver(v_nodrv,'n410nd',0);
    UPDATE public.driver_profiles
       SET capabilities = capabilities || ARRAY['marche_shopper']
     WHERE user_id = v_drv;

    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status,
                                       latitude, longitude, address_label, commune)
      VALUES (v_m1,'qa-n410-1-'||substr(v_m1::text,1,8),'QA N410 Boutique 1','active','approved',
              9.5370,-13.6785,'QA Madina','QA-N410-ZONE-A') RETURNING id INTO s1;
    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status,
                                       latitude, longitude, address_label, commune)
      VALUES (v_m2,'qa-n410-2-'||substr(v_m2::text,1,8),'QA N410 Boutique 2','active','approved',
              9.6400,-13.5800,'QA Ratoma','QA-N410-ZONE-B') RETURNING id INTO s2;
    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status,
                                       address_label, commune)
      VALUES (v_m3,'qa-n410-3-'||substr(v_m3::text,1,8),'QA N410 Boutique 3','active','approved',
              'QA sans coordonnees','QA-N410-ZONE-A') RETURNING id INTO s3;
    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status,
                                       latitude, longitude, address_label, commune)
      VALUES (v_m4,'qa-n410-4-'||substr(v_m4::text,1,8),'QA N410 Boutique 4','active','approved',
              9.5372,-13.6787,'QA Madina 2','QA-N410-ZONE-C') RETURNING id INTO s4;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_m1), true);
    la := public.marche_listing_create(jsonb_build_object('store_id',s1,'title','QA N410 Riz A','category','Alimentation','price_gnf',8000,'quantity_in_stock',50,'publish',true));
    lb := public.marche_listing_create(jsonb_build_object('store_id',s1,'title','QA N410 Riz B','category','Alimentation','price_gnf',12000,'quantity_in_stock',50,'publish',true));
    lc := public.marche_listing_create(jsonb_build_object('store_id',s1,'title','QA N410 Riz C','category','Alimentation','price_gnf',16000,'quantity_in_stock',50,'publish',true));
    ld := public.marche_listing_create(jsonb_build_object('store_id',s1,'title','QA N410 Riz D','category','Alimentation','price_gnf',20000,'quantity_in_stock',50,'publish',true));
    le := public.marche_listing_create(jsonb_build_object('store_id',s1,'title','QA N410 Riz E','category','Alimentation','price_gnf',24000,'quantity_in_stock',50,'publish',true));
    lf := public.marche_listing_create(jsonb_build_object('store_id',s1,'title','QA N410 Riz F','category','Alimentation','price_gnf',28000,'quantity_in_stock',50,'publish',true));
    lag := public.marche_listing_create(jsonb_build_object('store_id',s1,'title','QA N410 Riz Vieillissant','category','Alimentation','price_gnf',15000,'quantity_in_stock',5,'publish',true));
    lst := public.marche_listing_create(jsonb_build_object('store_id',s1,'title','QA N410 Riz Perime','category','Alimentation','price_gnf',15000,'quantity_in_stock',5,'publish',true));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_m2), true);
    lz1 := public.marche_listing_create(jsonb_build_object('store_id',s2,'title','QA N410 Zone B 1','category','Alimentation','price_gnf',1000,'quantity_in_stock',50,'publish',true));
    lz2 := public.marche_listing_create(jsonb_build_object('store_id',s2,'title','QA N410 Zone B 2','category','Alimentation','price_gnf',2000,'quantity_in_stock',50,'publish',true));
    lz3 := public.marche_listing_create(jsonb_build_object('store_id',s2,'title','QA N410 Zone B 3','category','Alimentation','price_gnf',3000,'quantity_in_stock',50,'publish',true));
    lz4 := public.marche_listing_create(jsonb_build_object('store_id',s2,'title','QA N410 Zone B 4','category','Alimentation','price_gnf',4000,'quantity_in_stock',50,'publish',true));
    lz5 := public.marche_listing_create(jsonb_build_object('store_id',s2,'title','QA N410 Zone B 5','category','Alimentation','price_gnf',5000,'quantity_in_stock',50,'publish',true));
    ln := public.marche_listing_create(jsonb_build_object('store_id',s2,'title','QA N410 Non mappe','category','Alimentation','price_gnf',15000,'quantity_in_stock',5,'publish',true));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_m3), true);
    l3 := public.marche_listing_create(jsonb_build_object('store_id',s3,'title','QA N410 Sans GPS','category','Alimentation','price_gnf',15000,'quantity_in_stock',5,'publish',true));
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_m4), true);
    l4 := public.marche_listing_create(jsonb_build_object('store_id',s4,'title','QA N410 Nouvelle boutique','category','Alimentation','price_gnf',15000,'quantity_in_stock',5,'publish',true));

    PERFORM set_config('request.jwt.claims','', true);
    PERFORM set_config('marche.rpc','1', true);
    UPDATE public.marketplace_listings
       SET staple_variant_id = v_var, staple_purchase_option_id = v_opt
     WHERE id IN (la,lb,lc,ld,le,lf,lz1,lz2,lz3,lz4,lz5,lag,lst);
    PERFORM set_config('marche.rpc','', true);

    PERFORM public.marche_price_ingest_merchant_ask(la);
    PERFORM public.marche_price_ingest_merchant_ask(lb);
    PERFORM public.marche_price_ingest_merchant_ask(lc);
    PERFORM public.marche_price_ingest_merchant_ask(ld);
    PERFORM public.marche_price_ingest_merchant_ask(le);
    PERFORM public.marche_price_ingest_merchant_ask(lf);
    PERFORM public.marche_price_ingest_merchant_ask(lz1);
    PERFORM public.marche_price_ingest_merchant_ask(lz2);
    PERFORM public.marche_price_ingest_merchant_ask(lz3);
    PERFORM public.marche_price_ingest_merchant_ask(lz4);
    PERFORM public.marche_price_ingest_merchant_ask(lz5);

    -- Deliberately aged / stale observations, recorded through the canonical R8 writer.
    PERFORM public._marche_price_record(v_opt,'merchant_ask','merchant_ask',
      'listing:'||lag::text||':1', 15000, 1, now() - interval '100 hours', NULL, s1, lag,
      'QA-N410-ZONE-A', 'QA Madina', NULL);
    PERFORM public._marche_price_record(v_opt,'merchant_ask','merchant_ask',
      'listing:'||lst::text||':1', 15000, 1, now() - interval '400 hours', NULL, s1, lst,
      'QA-N410-ZONE-A', 'QA Madina', NULL);

    SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations
     WHERE listing_id IN (la,lb,lc,ld,le,lf);
    r := r || public._qa_s13_ok('N4R10.C1 the six zone-A asks produced six canonical observations',
      v_n = 6, v_n::text);
    SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations
     WHERE listing_id IN (lz1,lz2,lz3,lz4,lz5);
    r := r || public._qa_s13_ok('N4R10.C2 the five zone-B asks produced five canonical observations',
      v_n = 5, v_n::text);

    ------------------------------------------------------ D) PRICE EVIDENCE (R8)
    ev := public._marche_rank_evidence(la, NULL, NULL, NULL);
    cmp := ev->'components'->'price';
    r := r || public._qa_s13_ok('N4R10.D1 the cheapest listing has usable price evidence',
      (cmp->>'available')::boolean, cmp#>>'{}');
    r := r || public._qa_s13_ok('N4R10.D2 a listing is never benchmarked against itself',
      (cmp->>'self_excluded')::boolean AND (cmp->>'sample_count')::int = 5, cmp#>>'{}');
    r := r || public._qa_s13_ok('N4R10.D3 a price cohort never mixes two different zones',
      cmp->>'cohort_zone_commune' = 'QA-N410-ZONE-A'
      AND (cmp->>'sample_count')::int = 5, cmp#>>'{}');
    r := r || public._qa_s13_ok('N4R10.D4 the cohort declares its statistical confidence',
      cmp->>'cohort_confidence' IN ('low','medium','high'), cmp->>'cohort_confidence');
    ev2 := public._marche_rank_evidence(le, NULL, NULL, NULL);
    r := r || public._qa_s13_ok('N4R10.D5 a cheaper ask scores strictly better than a dearer ask',
      (cmp->>'score')::numeric > (ev2->'components'->'price'->>'score')::numeric,
      format('%s vs %s', cmp->>'score', ev2->'components'->'price'->>'score'));
    r := r || public._qa_s13_ok('N4R10.D6 price scores stay inside the 0..1 band',
      (cmp->>'score')::numeric BETWEEN 0 AND 1
      AND (ev2->'components'->'price'->>'score')::numeric BETWEEN 0 AND 1, NULL);

    ev3 := public._marche_rank_evidence(lz1, NULL, NULL, NULL);
    r := r || public._qa_s13_ok('N4R10.D7 a four-peer cohort is refused, not scored',
      (ev3->'components'->'price'->>'available')::boolean IS FALSE
      AND ev3->'components'->'price'->>'reason' = 'INSUFFICIENT_PRICE_EVIDENCE'
      AND (ev3->'components'->'price'->>'sample_count')::int = 4,
      ev3->'components'->'price'#>>'{}');

    ev3 := public._marche_rank_evidence(ln, NULL, NULL, NULL);
    r := r || public._qa_s13_ok('N4R10.D8 an unmapped listing gets an honest missing-price reason',
      (ev3->'components'->'price'->>'available')::boolean IS FALSE
      AND ev3->'components'->'price'->>'reason' = 'LISTING_NOT_MAPPED_TO_VARIANT', NULL);
    r := r || public._qa_s13_ok('N4R10.D9 missing price evidence is never faked as a zero score',
      (ev3->'components'->'price'->'score') = 'null'::jsonb, NULL);
    r := r || public._qa_s13_ok('N4R10.D10 uncollected stock accuracy is declared, not invented',
      ev->'components'->'availability_accuracy'->>'reason' = 'NOT_COLLECTED'
      AND (ev->'components'->'availability_accuracy'->'score') = 'null'::jsonb, NULL);

    ------------------------------------------------- E) PRICE FRESHNESS (R8 only)
    cmp := ev->'components'->'price_freshness';
    r := r || public._qa_s13_ok('N4R10.E1 a just-published ask is at maximum price freshness',
      (cmp->>'available')::boolean AND cmp->>'freshness' = 'fresh'
      AND (cmp->>'score')::numeric = 1, cmp#>>'{}');
    ev2 := public._marche_rank_evidence(lag, NULL, NULL, NULL);
    r := r || public._qa_s13_ok('N4R10.E2 an ageing observed price scores lower, not zero',
      ev2->'components'->'price_freshness'->>'freshness' = 'aging'
      AND (ev2->'components'->'price_freshness'->>'score')::numeric = 0.5,
      ev2->'components'->'price_freshness'#>>'{}');
    ev3 := public._marche_rank_evidence(lst, NULL, NULL, NULL);
    r := r || public._qa_s13_ok('N4R10.E3 a stale observed price scores zero on freshness',
      ev3->'components'->'price_freshness'->>'freshness' = 'stale'
      AND (ev3->'components'->'price_freshness'->>'score')::numeric = 0,
      ev3->'components'->'price_freshness'#>>'{}');
    ev3 := public._marche_rank_evidence(ln, NULL, NULL, NULL);
    r := r || public._qa_s13_ok('N4R10.E4 a listing without any observed price has no freshness score',
      (ev3->'components'->'price_freshness'->>'available')::boolean IS FALSE
      AND ev3->'components'->'price_freshness'->>'reason' = 'NO_PRICE_OBSERVATION', NULL);

    PERFORM set_config('marche.rpc','1', true);
    UPDATE public.marketplace_listings SET created_at = now() - interval '400 days' WHERE id = la;
    PERFORM set_config('marche.rpc','', true);
    ev2 := public._marche_rank_evidence(la, NULL, NULL, NULL);
    r := r || public._qa_s13_ok('N4R10.E5 an old listing with a fresh price stays fresh',
      ev2->'components'->'price_freshness'->>'freshness' = 'fresh'
      AND (ev2->'components'->'price_freshness'->>'score')::numeric = 1,
      ev2->'components'->'price_freshness'#>>'{}');

    ------------------------------------------------- F) REPUTATION EVIDENCE (R9)
    r := r || public._qa_s13_ok('N4R10.F1 a store with no ratings is not punished with a zero',
      (ev->'components'->'reputation'->>'available')::boolean IS FALSE
      AND ev->'components'->'reputation'->>'reason' = 'INSUFFICIENT_REPUTATION_SAMPLE'
      AND (ev->'components'->'reputation'->'score') = 'null'::jsonb, NULL);

    INSERT INTO public.marche_reputation_events(transaction_kind, transaction_id, rater_user_id,
      subject_kind, subject_store_id, overall_score, provenance)
    SELECT 'merchant_order', gen_random_uuid(), gen_random_uuid(), 'merchant_store', s1, sc,
           jsonb_build_object('qa','n4r10')
      FROM unnest(ARRAY[5,4,3]) sc;
    INSERT INTO public.marche_reputation_events(transaction_kind, transaction_id, rater_user_id,
      subject_kind, subject_user_id, overall_score, provenance)
    SELECT 'merchant_order', gen_random_uuid(), gen_random_uuid(), 'delivery_driver', v_drv, 1,
           jsonb_build_object('qa','n4r10')
      FROM generate_series(1,3);

    ev := public._marche_rank_evidence(la, NULL, NULL, NULL);
    r := r || public._qa_s13_ok('N4R10.F2 verified store ratings become usable reputation evidence',
      (ev->'components'->'reputation'->>'available')::boolean
      AND (ev->'components'->'reputation'->>'sample_count')::int = 3,
      ev->'components'->'reputation'#>>'{}');
    r := r || public._qa_s13_ok('N4R10.F3 an average of 4/5 maps to the expected 0.75 score',
      round((ev->'components'->'reputation'->>'score')::numeric, 4) = 0.7500,
      ev->'components'->'reputation'->>'score');
    r := r || public._qa_s13_ok('N4R10.F4 driver ratings never contaminate store reputation',
      (ev->'components'->'reputation'->>'sample_count')::int = 3
      AND ev->'components'->'reputation'->>'subject_kind' = 'merchant_store', NULL);
    ev2 := public._marche_rank_evidence(l4, NULL, NULL, NULL);
    r := r || public._qa_s13_ok('N4R10.F5 one store''s reputation never leaks to another store',
      (ev2->'components'->'reputation'->>'available')::boolean IS FALSE, NULL);

    ----------------------------------- G) MERCHANT RELIABILITY (merchant acts only)
    r := r || public._qa_s13_ok('N4R10.G1 a store with no fulfilment history is not scored',
      (ev2->'components'->'reliability'->>'available')::boolean IS FALSE
      AND ev2->'components'->'reliability'->>'reason' = 'INSUFFICIENT_FULFILLMENT_HISTORY', NULL);

    INSERT INTO public.marche_orders(buyer_user_id, merchant_store_id, merchant_user_id,
      merchandise_subtotal_gnf, item_count, line_count, client_request_id, request_fingerprint,
      fulfillment_state, delivered_at)
    SELECT v_buy, s1, v_m1, 10000, 1, 1, 'qa-n410-d'||g, 'qa-n410-d'||g, 'delivered', now()
      FROM generate_series(1,4) g;
    INSERT INTO public.marche_orders(buyer_user_id, merchant_store_id, merchant_user_id,
      merchandise_subtotal_gnf, item_count, line_count, client_request_id, request_fingerprint,
      fulfillment_state, rejected_at)
    VALUES (v_buy, s1, v_m1, 10000, 1, 1, 'qa-n410-r1', 'qa-n410-r1', 'rejected', now());

    ev := public._marche_rank_evidence(la, NULL, NULL, NULL);
    r := r || public._qa_s13_ok('N4R10.G2 delivered vs merchant-rejected produces the true rate',
      (ev->'components'->'reliability'->>'available')::boolean
      AND (ev->'components'->'reliability'->>'sample_count')::int = 5
      AND round((ev->'components'->'reliability'->>'score')::numeric,4) = 0.8000,
      ev->'components'->'reliability'#>>'{}');

    INSERT INTO public.marche_orders(buyer_user_id, merchant_store_id, merchant_user_id,
      merchandise_subtotal_gnf, item_count, line_count, client_request_id, request_fingerprint,
      status, fulfillment_state)
    SELECT v_buy, s1, v_m1, 10000, 1, 1, 'qa-n410-c'||g, 'qa-n410-c'||g, 'cancelled', 'committed'
      FROM generate_series(1,4) g;

    ev2 := public._marche_rank_evidence(la, NULL, NULL, NULL);
    r := r || public._qa_s13_ok('N4R10.G3 buyer cancellations never damage merchant reliability',
      (ev2->'components'->'reliability'->>'sample_count')::int = 5
      AND (ev2->'components'->'reliability'->>'score') = (ev->'components'->'reliability'->>'score'),
      ev2->'components'->'reliability'#>>'{}');
    r := r || public._qa_s13_ok('N4R10.G4 the reliability component declares its exclusions',
      (ev2->'components'->'reliability'->>'buyer_cancellation_counted')::boolean IS FALSE
      AND (ev2->'components'->'reliability'->>'courier_failure_counted')::boolean IS FALSE, NULL);

    INSERT INTO public.marche_orders(buyer_user_id, merchant_store_id, merchant_user_id,
      merchandise_subtotal_gnf, item_count, line_count, client_request_id, request_fingerprint,
      fulfillment_state, rejected_at, created_at)
    SELECT v_buy, s1, v_m1, 10000, 1, 1, 'qa-n410-old'||g, 'qa-n410-old'||g, 'rejected',
           now() - interval '400 days', now() - interval '400 days'
      FROM generate_series(1,6) g;
    ev3 := public._marche_rank_evidence(la, NULL, NULL, NULL);
    r := r || public._qa_s13_ok('N4R10.G5 reliability only looks at the declared recent window',
      (ev3->'components'->'reliability'->>'sample_count')::int = 5
      AND (ev3->'components'->'reliability'->>'lookback_days')::int > 0,
      ev3->'components'->'reliability'#>>'{}');

    ------------------------- H) RESPONSIVENESS + PREPARATION (observed durations)
    r := r || public._qa_s13_ok('N4R10.H1 a store without timing observations is not scored',
      (ev3->'components'->'responsiveness'->>'available')::boolean IS FALSE
      AND ev3->'components'->'responsiveness'->>'reason' = 'INSUFFICIENT_RESPONSIVENESS_OBSERVATIONS'
      AND (ev3->'components'->'preparation'->>'available')::boolean IS FALSE, NULL);

    FOR i IN 1..5 LOOP
      INSERT INTO public.marche_orders(buyer_user_id, merchant_store_id, merchant_user_id,
        merchandise_subtotal_gnf, item_count, line_count, client_request_id, request_fingerprint,
        fulfillment_state, delivered_at)
      VALUES (v_buy, s1, v_m1, 10000, 1, 1, 'qa-n410-f1'||i, 'qa-n410-f1'||i, 'delivered', now())
      RETURNING id INTO ordid;
      PERFORM set_config('marche.fulfillment_derive_token', ordid::text||':COMMIT_TO_MERCHANT_ACCEPTED', true);
      INSERT INTO public.marche_fulfillment_observations(order_id, metric_name, duration_seconds,
        start_event_at, end_event_at, merchant_store_id, fulfillment_mode, distance_m,
        distance_bucket, basket_units, distinct_products, basket_bucket, observed_at)
      VALUES (ordid,'COMMIT_TO_MERCHANT_ACCEPTED',60, now()-interval '60 s', now(), s1,
              'merchant_delivery', NULL, public.marche_distance_bucket(NULL), 1, 1,
              public.marche_basket_bucket(1,1), now());
      PERFORM set_config('marche.fulfillment_derive_token', ordid::text||':MERCHANT_ACCEPTED_TO_READY', true);
      INSERT INTO public.marche_fulfillment_observations(order_id, metric_name, duration_seconds,
        start_event_at, end_event_at, merchant_store_id, fulfillment_mode, distance_m,
        distance_bucket, basket_units, distinct_products, basket_bucket, observed_at)
      VALUES (ordid,'MERCHANT_ACCEPTED_TO_READY',300, now()-interval '300 s', now(), s1,
              'merchant_delivery', NULL, public.marche_distance_bucket(NULL), 1, 1,
              public.marche_basket_bucket(1,1), now());

      INSERT INTO public.marche_orders(buyer_user_id, merchant_store_id, merchant_user_id,
        merchandise_subtotal_gnf, item_count, line_count, client_request_id, request_fingerprint,
        fulfillment_state, delivered_at)
      VALUES (v_buy, s2, v_m2, 10000, 1, 1, 'qa-n410-f2'||i, 'qa-n410-f2'||i, 'delivered', now())
      RETURNING id INTO ordid;
      PERFORM set_config('marche.fulfillment_derive_token', ordid::text||':COMMIT_TO_MERCHANT_ACCEPTED', true);
      INSERT INTO public.marche_fulfillment_observations(order_id, metric_name, duration_seconds,
        start_event_at, end_event_at, merchant_store_id, fulfillment_mode, distance_m,
        distance_bucket, basket_units, distinct_products, basket_bucket, observed_at)
      VALUES (ordid,'COMMIT_TO_MERCHANT_ACCEPTED',3600, now()-interval '3600 s', now(), s2,
              'merchant_delivery', NULL, public.marche_distance_bucket(NULL), 1, 1,
              public.marche_basket_bucket(1,1), now());
      PERFORM set_config('marche.fulfillment_derive_token', ordid::text||':MERCHANT_ACCEPTED_TO_READY', true);
      INSERT INTO public.marche_fulfillment_observations(order_id, metric_name, duration_seconds,
        start_event_at, end_event_at, merchant_store_id, fulfillment_mode, distance_m,
        distance_bucket, basket_units, distinct_products, basket_bucket, observed_at)
      VALUES (ordid,'MERCHANT_ACCEPTED_TO_READY',7200, now()-interval '7200 s', now(), s2,
              'merchant_delivery', NULL, public.marche_distance_bucket(NULL), 1, 1,
              public.marche_basket_bucket(1,1), now());
    END LOOP;

    ev := public._marche_rank_evidence(la, NULL, NULL, NULL);
    r := r || public._qa_s13_ok('N4R10.H2 a fast-accepting store earns a real responsiveness score',
      (ev->'components'->'responsiveness'->>'available')::boolean
      AND (ev->'components'->'responsiveness'->>'sample_count')::int = 5
      AND (ev->'components'->'responsiveness'->>'score')::numeric = 1,
      ev->'components'->'responsiveness'#>>'{}');
    r := r || public._qa_s13_ok('N4R10.H3 responsiveness is measured against the platform median',
      (ev->'components'->'responsiveness'->>'store_median_seconds')::numeric = 60
      AND (ev->'components'->'responsiveness'->>'platform_median_seconds')::numeric > 60,
      ev->'components'->'responsiveness'#>>'{}');
    r := r || public._qa_s13_ok('N4R10.H4 a fast-preparing store earns a real preparation score',
      (ev->'components'->'preparation'->>'available')::boolean
      AND (ev->'components'->'preparation'->>'score')::numeric BETWEEN 0 AND 1,
      ev->'components'->'preparation'#>>'{}');
    ev2 := public._marche_rank_evidence(lz1, NULL, NULL, NULL);
    r := r || public._qa_s13_ok('N4R10.H5 a slow store scores strictly below a fast store',
      (ev2->'components'->'responsiveness'->>'score')::numeric
        < (ev->'components'->'responsiveness'->>'score')::numeric
      AND (ev2->'components'->'responsiveness'->>'score')::numeric > 0,
      ev2->'components'->'responsiveness'#>>'{}');
    r := r || public._qa_s13_ok('N4R10.H6 timing evidence never crosses store boundaries',
      (ev->'components'->'responsiveness'->>'sample_count')::int = 5
      AND (ev2->'components'->'responsiveness'->>'sample_count')::int = 5, NULL);

    --------------------------------------------------------------- I) DISTANCE
    r := r || public._qa_s13_ok('N4R10.I1 without customer coordinates distance is declared missing',
      (ev->'components'->'distance'->>'available')::boolean IS FALSE
      AND ev->'components'->'distance'->>'reason' = 'NO_CUSTOMER_COORDINATES'
      AND (ev->'components'->'distance'->>'penalised')::boolean IS FALSE, NULL);
    ev2 := public._marche_rank_evidence(la, 9.5370, -13.6785, NULL);
    ev3 := public._marche_rank_evidence(la, 9.9500, -13.9500, NULL);
    r := r || public._qa_s13_ok('N4R10.I2 a near customer scores better than a far customer',
      (ev2->'components'->'distance'->>'score')::numeric
        > (ev3->'components'->'distance'->>'score')::numeric, NULL);
    r := r || public._qa_s13_ok('N4R10.I3 an unknown distance is never worse than a bad distance',
      (ev->>'score')::numeric >= (ev3->>'score')::numeric,
      format('unknown=%s far=%s', ev->>'score', ev3->>'score'));
    r := r || public._qa_s13_ok('N4R10.I4 distance is honestly labelled as straight-line, not road',
      (ev2->'components'->'distance'->>'road_distance')::boolean IS FALSE
      AND ev2->'components'->'distance'->>'method' = 'haversine_great_circle', NULL);
    ev3 := public._marche_rank_evidence(l3, 9.5370, -13.6785, NULL);
    r := r || public._qa_s13_ok('N4R10.I5 a store without coordinates is not invented a distance',
      (ev3->'components'->'distance'->>'available')::boolean IS FALSE
      AND ev3->'components'->'distance'->>'reason' = 'NO_STORE_COORDINATES'
      AND (ev3->'components'->'distance'->'distance_m') = 'null'::jsonb, NULL);

    ------------------------------------------------------- J) TRUE COLD START
    ev3 := public._marche_rank_evidence(l4, 9.5370, -13.6785, NULL);
    r := r || public._qa_s13_ok('N4R10.J1 a brand-new listing qualifies too few components',
      (ev3->>'qualified_components')::int < (ev3->>'min_qualified_components')::int,
      ev3->>'qualified_components');
    r := r || public._qa_s13_ok('N4R10.J2 a cold-start listing gets no invented score',
      (ev3->>'cold_start')::boolean AND (ev3->'score') = 'null'::jsonb
      AND (ev3->'score_bps') = 'null'::jsonb, ev3#>>'{}');
    r := r || public._qa_s13_ok('N4R10.J3 the cold-start state is explained honestly',
      ev3->>'cold_start_reason' = 'INSUFFICIENT_EVIDENCE', NULL);
    r := r || public._qa_s13_ok('N4R10.J4 a cold-start listing advertises no ranking reason',
      jsonb_array_length(ev3->'why_ranked') = 0, ev3->'why_ranked'#>>'{}');
    r := r || public._qa_s13_ok('N4R10.J5 an evidenced listing is not cold start',
      (ev->>'cold_start')::boolean IS FALSE AND (ev->>'score_bps')::int IS NOT NULL,
      ev->>'score_bps');
    r := r || public._qa_s13_ok('N4R10.J6 evidence completeness is reported honestly',
      (ev->>'evidence_completeness')::numeric < 1
      AND (ev->>'qualified_components')::int < (ev->>'components_total')::int,
      ev->>'evidence_completeness');
    r := r || public._qa_s13_ok('N4R10.J7 promotion has strictly zero ranking effect',
      (ev->>'promotion_effect')::int = 0, NULL);

    ---------------------------------------------------- K) SERVER-AUTHORED REASONS
    r := r || public._qa_s13_ok('N4R10.K1 ranking reasons are limited to two',
      jsonb_array_length(ev->'why_ranked') <= 2, ev->'why_ranked'#>>'{}');
    r := r || public._qa_s13_ok('N4R10.K2 every reason carries a server code and a French label',
      (SELECT bool_and((w->>'code') IS NOT NULL AND (w->>'label') IS NOT NULL AND (w->>'label') <> '')
         FROM jsonb_array_elements(ev->'why_ranked') w), ev->'why_ranked'#>>'{}');
    r := r || public._qa_s13_ok('N4R10.K3 a genuinely cheap listing is credited for its value',
      ev->'why_ranked'#>>'{0,code}' = 'GOOD_VALUE', ev->'why_ranked'#>>'{}');
    r := r || public._qa_s13_ok('N4R10.K4 reasons only ever describe qualified evidence',
      (SELECT bool_and(w->>'code' IN ('GOOD_VALUE','WELL_RATED','FAST_PREPARATION',
                                      'NEARBY','PRICE_RECENTLY_UPDATED'))
         FROM jsonb_array_elements(ev->'why_ranked') w), NULL);

    ------------------------------------------------------ L) DISCOVERY BEHAVIOUR
    PERFORM set_config('request.jwt.claims','', true);
    d1 := to_jsonb(ARRAY(SELECT x.id FROM public.marche_listings_discover(
            'QA N410', NULL, NULL, 'recommended', 60, 0, 9.5370, -13.6785) x));
    d2 := to_jsonb(ARRAY(SELECT x.id FROM public.marche_listings_discover(
            'QA N410', NULL, NULL, 'recommended', 60, 0, 9.5370, -13.6785) x));
    r := r || public._qa_s13_ok('N4R10.L1 recommended discovery returns every orderable fixture',
      jsonb_array_length(d1) = 16, jsonb_array_length(d1)::text);
    r := r || public._qa_s13_ok('N4R10.L2 the recommended order is deterministic',
      d1 = d2, NULL);
    r := r || public._qa_s13_ok('N4R10.L3 cold-start listings are listed without a score',
      (SELECT x.rank_score_bps IS NULL FROM public.marche_listings_discover(
        'QA N410', NULL, NULL, 'recommended', 60, 0, 9.5370, -13.6785) x WHERE x.id = l4), NULL);
    r := r || public._qa_s13_ok('N4R10.L4 scored listings always precede cold-start listings',
      (SELECT bool_and(a IS NOT NULL OR b IS NULL) FROM (
         SELECT x.rank_score_bps a, lead(x.rank_score_bps) OVER () b
           FROM public.marche_listings_discover('QA N410', NULL, NULL, 'recommended', 60, 0,
                                                9.5370, -13.6785) x) t), NULL);
    r := r || public._qa_s13_ok('N4R10.L5 recommended results carry server-authored reasons only',
      (SELECT bool_and(x.rank_evidence ? 'why_ranked'
                       AND jsonb_array_length(x.rank_evidence->'why_ranked') <= 2)
         FROM public.marche_listings_discover('QA N410', NULL, NULL, 'recommended', 60, 0,
                                              9.5370, -13.6785) x), NULL);
    r := r || public._qa_s13_ok('N4R10.L6 discovery never ships raw rival evidence to the client',
      (SELECT bool_and(NOT (x.rank_evidence ? 'components'))
         FROM public.marche_listings_discover('QA N410', NULL, NULL, 'recommended', 60, 0,
                                              9.5370, -13.6785) x), NULL);

    SELECT o INTO pa FROM (SELECT y.id, row_number() OVER () o FROM public.marche_listings_discover(
      'QA N410 Riz', NULL, NULL, 'recommended', 60, 0, 9.5370, -13.6785) y) t WHERE t.id = la;
    SELECT o INTO pe FROM (SELECT y.id, row_number() OVER () o FROM public.marche_listings_discover(
      'QA N410 Riz', NULL, NULL, 'recommended', 60, 0, 9.5370, -13.6785) y) t WHERE t.id = le;
    r := r || public._qa_s13_ok('N4R10.L7 between two identical listings the cheaper one ranks higher',
      pa IS NOT NULL AND pe IS NOT NULL AND pa < pe, format('cheap@%s dear@%s', pa, pe));

    r := r || public._qa_s13_ok('N4R10.L8 an explicit price sort remains an exact override',
      (SELECT array_agg(x.price_gnf ORDER BY o) = array_agg(x.price_gnf ORDER BY x.price_gnf)
         FROM (SELECT y.*, row_number() OVER () o FROM public.marche_listings_discover(
                 'QA N410', NULL, NULL, 'price_asc', 60, 0, 9.5370, -13.6785) y) x), NULL);
    r := r || public._qa_s13_ok('N4R10.L9 an explicit recency sort remains an exact override',
      (SELECT bool_and(a >= b) FROM (
         SELECT x.created_at a, lead(x.created_at) OVER () b
           FROM public.marche_listings_discover('QA N410', NULL, NULL, 'recent', 60, 0) x) t
        WHERE b IS NOT NULL), NULL);
    r := r || public._qa_s13_ok('N4R10.L10 a manual sort is never annotated with ranking evidence',
      (SELECT bool_and(x.rank_score_bps IS NULL AND x.rank_evidence IS NULL)
         FROM public.marche_listings_discover('QA N410', NULL, NULL, 'price_asc', 60, 0) x), NULL);
    r := r || public._qa_s13_ok('N4R10.L11 both discovery call shapes agree without coordinates',
      (SELECT count(*) FROM public.marche_listings_discover('QA N410', NULL, NULL, 'recent', 60, 0))
      = (SELECT count(*) FROM public.marche_listings_discover('QA N410', NULL, NULL, 'recent', 60, 0,
                                                              NULL, NULL)), NULL);

    PERFORM set_config('marche.rpc','1', true);
    UPDATE public.marketplace_listings SET status='paused' WHERE id = la;
    PERFORM set_config('marche.rpc','', true);
    d2 := to_jsonb(ARRAY(SELECT x.id FROM public.marche_listings_discover(
            'QA N410', NULL, NULL, 'recommended', 60, 0, 9.5370, -13.6785) x));
    r := r || public._qa_s13_ok('N4R10.L12 ranking can never resurrect a non-orderable listing',
      NOT (d2 @> to_jsonb(ARRAY[la])) AND jsonb_array_length(d2) = 15,
      jsonb_array_length(d2)::text);
    PERFORM set_config('marche.rpc','1', true);
    UPDATE public.marketplace_listings SET status='active' WHERE id = la;
    PERFORM set_config('marche.rpc','', true);

    --------------------------------------------------- M) PUBLIC EXPLAINABILITY
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    j := public.marche_listing_rank_explain(la, 9.5370, -13.6785);
    r := r || public._qa_s13_ok('N4R10.M1 a shopper can see why a listing ranks where it does',
      j ? 'why_ranked' AND j ? 'components', j#>>'{}');
    r := r || public._qa_s13_ok('N4R10.M2 the public explanation leaks no rival identity',
      j::text NOT LIKE '%'||lb::text||'%' AND j::text NOT LIKE '%'||v_m2::text||'%', NULL);
    pol := public.marche_ranking_policy_public();
    r := r || public._qa_s13_ok('N4R10.M3 the ranking policy in force is publicly disclosed',
      (pol->>'version') IS NOT NULL
      AND pol->'weights_bps' ? 'responsiveness' AND pol->'weights_bps' ? 'preparation'
      AND pol->'lookbacks' ? 'price_hours', pol#>>'{}');
    r := r || public._qa_s13_ok('N4R10.M4 the disclosure states the cold-start doctrine',
      pol->>'cold_start_behaviour' = 'aucun_score_invente'
      AND pol->>'price_freshness_source' = 'observations_de_prix_verifiees', NULL);

    ------------------------------------------------------ N) ADMIN AUTHORITY LAW
    v_err := NULL;
    BEGIN PERFORM public.marche_ranking_policy_publish(jsonb_build_object('w_price',9000));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R10.N1 an ordinary user cannot publish a ranking policy',
      v_err = 'NOT_AUTHORIZED', COALESCE(v_err,'no error'));
    v_err := NULL;
    BEGIN PERFORM public.marche_ranking_policy_admin_list();
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R10.N2 an ordinary user cannot read the policy history',
      v_err = 'NOT_AUTHORIZED', COALESCE(v_err,'no error'));
    v_err := NULL;
    BEGIN PERFORM public.marche_ranking_audit_listing(la, NULL, NULL);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R10.N3 an ordinary user cannot open the ranking audit',
      v_err = 'NOT_AUTHORIZED', COALESCE(v_err,'no error'));
    v_err := NULL;
    BEGIN PERFORM public.marche_shopper_performance(v_drv);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R10.N4 nobody can read another person''s performance record',
      v_err = 'NOT_AUTHORIZED', COALESCE(v_err,'no error'));

    ---------------------------------------- O) SHOPPER PERFORMANCE INTELLIGENCE
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_nodrv), true);
    j := public.marche_shopper_performance(NULL);
    r := r || public._qa_s13_ok('N4R10.O1 a driver without the shopper capability is refused',
      (j->>'available')::boolean IS FALSE AND j->>'reason' = 'SHOPPER_NOT_ELIGIBLE', j#>>'{}');

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    j := public.marche_shopper_performance(NULL);
    r := r || public._qa_s13_ok('N4R10.O2 an eligible shopper with no history gets an honest answer',
      (j->>'available')::boolean IS FALSE AND j->>'reason' = 'NO_PROCUREMENT_HISTORY', j#>>'{}');
    r := r || public._qa_s13_ok('N4R10.O3 performance intelligence declares it is read-only',
      (j->>'read_only')::boolean AND (j->>'affects_assignment')::boolean IS FALSE, NULL);

    PERFORM set_config('request.jwt.claims','', true);
    FOR i IN 1..3 LOOP
      INSERT INTO public.marche_procurement_requests(
        buyer_user_id, authorized_ceiling_gnf, estimate_status, estimate_basis,
        estimated_subtotal_gnf, estimate_confidence, estimate_sample_count,
        line_count, item_count, client_request_id, request_fingerprint)
      VALUES (v_buy, 100000, 'available', 'observed_procurement', 50000, 'medium', 5,
              1, 1, gen_random_uuid(), 'qa-n410-req'||i)
      RETURNING id INTO rq;

      IF i < 3 THEN
        INSERT INTO public.marche_procurement_missions(request_id, buyer_user_id, shopper_user_id,
          state, assigned_at, shopping_started_at, purchase_submitted_at, completed_at)
        VALUES (rq, v_buy, v_drv, 'completed', now() - interval '90 min',
                now() - interval '60 min', now() - interval '40 min', now() - interval '30 min');
      ELSE
        INSERT INTO public.marche_procurement_missions(request_id, buyer_user_id, shopper_user_id,
          state, assigned_at, cancelled_at)
        VALUES (rq, v_buy, v_drv, 'cancelled', now() - interval '70 min', now());
      END IF;
    END LOOP;

    INSERT INTO public.marche_reputation_events(transaction_kind, transaction_id, rater_user_id,
      subject_kind, subject_user_id, overall_score, provenance)
    SELECT 'procurement', gen_random_uuid(), gen_random_uuid(), 'shopper', v_drv, sc,
           jsonb_build_object('qa','n4r10')
      FROM unnest(ARRAY[5,4,3]) sc;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    j := public.marche_shopper_performance(NULL);
    r := r || public._qa_s13_ok('N4R10.O4 completed procurement history becomes real intelligence',
      (j->>'available')::boolean AND (j->>'missions_assigned')::int = 3
      AND (j->>'missions_completed')::int = 2, j#>>'{}');
    r := r || public._qa_s13_ok('N4R10.O5 cancellations are reported but never scored',
      NOT (j ? 'completion_rate')
      AND (j->'missions_cancelled_unattributed'->>'value')::int = 1
      AND (j->'missions_cancelled_unattributed'->>'scored')::boolean IS FALSE
      AND j->'missions_cancelled_unattributed'->>'reason' = 'NO_CANONICAL_CANCELLATION_ATTRIBUTION',
      j->'missions_cancelled_unattributed'#>>'{}');
    r := r || public._qa_s13_ok('N4R10.O6 median shopping duration is computed from real timestamps',
      round((j->>'median_shopping_minutes')::numeric) = 20, j->>'median_shopping_minutes');
    r := r || public._qa_s13_ok('N4R10.O7 verified shopper ratings are surfaced to the shopper',
      (j->'reputation'->>'available')::boolean
      AND (j->'reputation'->>'sample_count')::int = 3
      AND (j->'reputation'->>'average_score')::numeric = 4.00
      AND j->'reputation'->>'subject_kind' = 'shopper', j->'reputation'#>>'{}');
    r := r || public._qa_s13_ok('N4R10.O8 delivery-driver ratings never inflate shopper reputation',
      (j->'reputation'->>'sample_count')::int = 3, j->'reputation'#>>'{}');
    r := r || public._qa_s13_ok('N4R10.O9 performance never exposes buyer or basket identity',
      NOT (j ? 'buyer_user_id') AND j::text NOT LIKE '%'||v_buy::text||'%', NULL);
    r := r || public._qa_s13_ok('N4R10.O10 reading performance writes nothing back',
      (SELECT count(*) FROM public.marche_procurement_missions WHERE shopper_user_id=v_drv) = 3, NULL);

    ------------------------------------------------------- P) POLICY EFFECTIVITY
    PERFORM set_config('request.jwt.claims','', true);
    pol := public._marche_ranking_policy(now());
    r := r || public._qa_s13_ok('N4R10.P1 an effective policy always resolves for ranking',
      pol IS NOT NULL AND (pol->>'version')::int >= 1, pol->>'version');
    ev := public._marche_rank_evidence(la, NULL, NULL,
      jsonb_build_object('id', pol->>'id', 'version', 999,
        'w_price', 10000, 'w_reputation', 0, 'w_reliability', 0, 'w_distance', 0,
        'w_freshness', 0, 'w_responsiveness', 0, 'w_preparation', 0,
        'min_price_observations', 5, 'min_reputation_events', 3, 'min_fulfillment_history', 5,
        'min_fulfillment_observations', 5, 'min_qualified_components', 2,
        'distance_max_m', 15000, 'price_lookback_hours', 168,
        'reliability_lookback_days', 90, 'fulfillment_lookback_days', 90));
    r := r || public._qa_s13_ok('N4R10.P2 weights genuinely change the resulting score',
      (ev->>'score')::numeric = (ev->'components'->'price'->>'score')::numeric,
      format('%s / %s', ev->>'score', ev->'components'->'price'->>'score'));
    r := r || public._qa_s13_ok('N4R10.P3 the score carries the policy version that produced it',
      (ev->>'policy_version')::int = 999, ev->>'policy_version');

    PERFORM set_config('request.jwt.claims','', true);
    RAISE EXCEPTION 'QA_N4R10_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_N4R10_ROLLBACK' THEN
      r := r || public._qa_s13_ok('HARNESS_R10_UNEXPECTED_ABORT', false, SQLERRM);
    END IF;
  END;

  PERFORM set_config('request.jwt.claims','', true);
  PERFORM set_config('marche.rpc','', true);
  PERFORM set_config('marche.fulfillment_derive_token','', true);

  ------------------------------------------------------------------ Q) RESIDUE
  SELECT count(*) INTO v_n FROM public.marketplace_listings;
  r := r || public._qa_s13_ok('N4R10.Q1 zero listing residue', v_n = base_lst, format('%s->%s', base_lst, v_n));
  SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations;
  r := r || public._qa_s13_ok('N4R10.Q2 zero price observation residue', v_n = base_obs, format('%s->%s', base_obs, v_n));
  SELECT count(*) INTO v_n FROM public.marche_reputation_events;
  r := r || public._qa_s13_ok('N4R10.Q3 zero reputation residue', v_n = base_rep, format('%s->%s', base_rep, v_n));
  SELECT count(*) INTO v_n FROM public.marche_orders;
  r := r || public._qa_s13_ok('N4R10.Q4 zero order residue', v_n = base_ord, format('%s->%s', base_ord, v_n));
  SELECT count(*) INTO v_n FROM public.marche_ranking_policies;
  r := r || public._qa_s13_ok('N4R10.Q5 zero ranking policy residue', v_n = base_pol, format('%s->%s', base_pol, v_n));
  SELECT count(*) INTO v_n FROM public.marche_procurement_requests;
  r := r || public._qa_s13_ok('N4R10.Q6 zero procurement request residue', v_n = base_req, format('%s->%s', base_req, v_n));
  SELECT count(*) INTO v_n FROM public.marche_fulfillment_observations;
  r := r || public._qa_s13_ok('N4R10.Q7 zero fulfilment observation residue', v_n = base_fob, format('%s->%s', base_fob, v_n));
  SELECT count(*) INTO v_n FROM public.marche_procurement_missions;
  r := r || public._qa_s13_ok('N4R10.Q8 zero procurement mission residue', v_n = base_mis, format('%s->%s', base_mis, v_n));

  RETURN jsonb_build_object(
    'suite','node4_marche_r10',
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) x WHERE (x->>'ok')::boolean IS NOT TRUE),
    'results', r);
END;
$function$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r10() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node4_marche_r10() TO service_role;