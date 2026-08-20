CREATE OR REPLACE FUNCTION public._qa_node4_marche_r10()
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  r jsonb := '[]'::jsonb;
  v_buy uuid := gen_random_uuid();
  v_m1 uuid := gen_random_uuid(); v_m2 uuid := gen_random_uuid(); v_m3 uuid := gen_random_uuid();
  v_drv uuid := gen_random_uuid();
  s1 uuid; s2 uuid; s3 uuid;
  la uuid; lb uuid; lc uuid; ld uuid; le uuid; ln uuid; l3 uuid;
  v_opt uuid; v_var uuid;
  base_obs int; base_rep int; base_ord int; base_pol int; base_lst int;
  ev jsonb; ev2 jsonb; j jsonb; j2 jsonb; pol jsonb;
  v_n bigint; v_err text; v_ok boolean;
  d1 jsonb; d2 jsonb; ids1 text; ids2 text;
  fdef text;
BEGIN
  SELECT count(*) INTO base_obs FROM public.marche_procurement_price_observations;
  SELECT count(*) INTO base_rep FROM public.marche_reputation_events;
  SELECT count(*) INTO base_ord FROM public.marche_orders;
  SELECT count(*) INTO base_pol FROM public.marche_ranking_policies;
  SELECT count(*) INTO base_lst FROM public.marketplace_listings;

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
  r := r || public._qa_s13_ok('N4R10.A3 the evidence engine is read-only (STABLE)',
    (SELECT provolatile FROM pg_proc WHERE oid='public._marche_rank_evidence(uuid,double precision,double precision,jsonb,timestamptz)'::regprocedure) = 's', NULL);
  r := r || public._qa_s13_ok('N4R10.A4 shopper performance intelligence is read-only (STABLE)',
    (SELECT provolatile FROM pg_proc WHERE oid='public.marche_shopper_performance(uuid)'::regprocedure) = 's', NULL);
  fdef := (SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname='_marche_rank_evidence');
  r := r || public._qa_s13_ok('N4R10.A5 ranking never reads a paid boost / sponsorship field',
    fdef !~* '(sponsor|boost|promoted|paid_rank|ad_spend)', NULL);
  r := r || public._qa_s13_ok('N4R10.A6 discovery never reads a paid boost / sponsorship field',
    (SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname='marche_listings_discover')
      !~* '(sponsor|boost|promoted|paid_rank|ad_spend)', NULL);
  r := r || public._qa_s13_ok('N4R10.A7 price evidence excludes the listing''s own observation',
    fdef LIKE '%o.listing_id <> l.id%', NULL);
  r := r || public._qa_s13_ok('N4R10.A8 reliability never counts buyer cancellations',
    fdef LIKE '%rejected_at IS NOT NULL%' AND fdef LIKE '%buyer_cancellation_counted%', NULL);

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
  r := r || public._qa_s13_ok('N4R10.B7 anon may still browse and see the public ranking policy',
    has_function_privilege('anon','public.marche_listings_discover(text,text,uuid,text,integer,integer,double precision,double precision)','EXECUTE')
    AND has_function_privilege('anon','public.marche_ranking_policy_public()','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R10.B8 anon still cannot execute the admin role helper (P15.5)',
    NOT has_function_privilege('anon','public.has_role(uuid,app_role)','EXECUTE'), NULL);

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
    PERFORM public._qa_s13_driver(v_drv,'n410d',0);

    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status,
                                       latitude, longitude, address_label)
      VALUES (v_m1,'qa-n410-1-'||substr(v_m1::text,1,8),'QA N410 Boutique 1','active','approved',
              9.5370,-13.6785,'QA Madina') RETURNING id INTO s1;
    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status,
                                       latitude, longitude, address_label)
      VALUES (v_m2,'qa-n410-2-'||substr(v_m2::text,1,8),'QA N410 Boutique 2','active','approved',
              9.6400,-13.5800,'QA Ratoma') RETURNING id INTO s2;
    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status,
                                       address_label)
      VALUES (v_m3,'qa-n410-3-'||substr(v_m3::text,1,8),'QA N410 Boutique 3','active','approved',
              'QA sans coordonnees') RETURNING id INTO s3;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_m1), true);
    la := public.marche_listing_create(jsonb_build_object('store_id',s1,'title','QA N410 Riz A','category','Alimentation','price_gnf',8000,'quantity_in_stock',50,'publish',true));
    lb := public.marche_listing_create(jsonb_build_object('store_id',s1,'title','QA N410 Riz B','category','Alimentation','price_gnf',12000,'quantity_in_stock',50,'publish',true));
    lc := public.marche_listing_create(jsonb_build_object('store_id',s1,'title','QA N410 Riz C','category','Alimentation','price_gnf',16000,'quantity_in_stock',50,'publish',true));
    ld := public.marche_listing_create(jsonb_build_object('store_id',s1,'title','QA N410 Riz D','category','Alimentation','price_gnf',20000,'quantity_in_stock',50,'publish',true));
    le := public.marche_listing_create(jsonb_build_object('store_id',s1,'title','QA N410 Riz E','category','Alimentation','price_gnf',24000,'quantity_in_stock',50,'publish',true));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_m2), true);
    ln := public.marche_listing_create(jsonb_build_object('store_id',s2,'title','QA N410 Nouveau','category','Alimentation','price_gnf',15000,'quantity_in_stock',5,'publish',true));
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_m3), true);
    l3 := public.marche_listing_create(jsonb_build_object('store_id',s3,'title','QA N410 Sans GPS','category','Alimentation','price_gnf',15000,'quantity_in_stock',5,'publish',true));

    PERFORM set_config('request.jwt.claims','', true);
    PERFORM set_config('marche.rpc','1', true);
    UPDATE public.marketplace_listings
       SET staple_variant_id = v_var, staple_purchase_option_id = v_opt
     WHERE id IN (la,lb,lc,ld,le);
    PERFORM set_config('marche.rpc','', true);
    PERFORM public.marche_price_ingest_merchant_ask(la);
    PERFORM public.marche_price_ingest_merchant_ask(lb);
    PERFORM public.marche_price_ingest_merchant_ask(lc);
    PERFORM public.marche_price_ingest_merchant_ask(ld);
    PERFORM public.marche_price_ingest_merchant_ask(le);

    SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations
     WHERE listing_id IN (la,lb,lc,ld,le);
    r := r || public._qa_s13_ok('N4R10.C1 the five fixture asks produced five canonical observations',
      v_n = 5, v_n::text);

    ------------------------------------------------------ D) PRICE EVIDENCE (R8)
    ev := public._marche_rank_evidence(la, NULL, NULL, NULL);
    r := r || public._qa_s13_ok('N4R10.D1 the cheapest listing has usable price evidence',
      (ev->'components'->'price'->>'available')::boolean, ev->'components'->'price'#>>'{}');
    r := r || public._qa_s13_ok('N4R10.D2 a listing is never benchmarked against itself',
      (ev->'components'->'price'->>'self_excluded')::boolean
      AND (ev->'components'->'price'->>'sample_count')::int
          = (SELECT count(*) FROM public.marche_procurement_price_observations o
              WHERE o.variant_id=v_var AND o.comparable AND o.superseded_by IS NULL
                AND (o.listing_id IS NULL OR o.listing_id <> la)),
      ev->'components'->'price'#>>'{}');
    ev2 := public._marche_rank_evidence(le, NULL, NULL, NULL);
    r := r || public._qa_s13_ok('N4R10.D3 a cheaper ask scores strictly better than a dearer ask',
      (ev->'components'->'price'->>'score')::numeric > (ev2->'components'->'price'->>'score')::numeric,
      format('%s vs %s', ev->'components'->'price'->>'score', ev2->'components'->'price'->>'score'));
    r := r || public._qa_s13_ok('N4R10.D4 price scores stay inside the 0..1 band',
      (ev->'components'->'price'->>'score')::numeric BETWEEN 0 AND 1
      AND (ev2->'components'->'price'->>'score')::numeric BETWEEN 0 AND 1, NULL);

    ev := public._marche_rank_evidence(ln, NULL, NULL, NULL);
    r := r || public._qa_s13_ok('N4R10.D5 an unmapped listing gets an honest missing-price reason',
      (ev->'components'->'price'->>'available')::boolean IS FALSE
      AND ev->'components'->'price'->>'reason' = 'LISTING_NOT_MAPPED_TO_VARIANT', NULL);
    r := r || public._qa_s13_ok('N4R10.D6 missing price evidence is never faked as a zero score',
      (ev->'components'->'price'->'score') = 'null'::jsonb, NULL);
    r := r || public._qa_s13_ok('N4R10.D7 a brand-new listing is still rankable (cold start)',
      (ev->>'ranked')::boolean AND (ev->>'score') IS NOT NULL AND (ev->>'cold_start')::boolean, ev->>'score');
    r := r || public._qa_s13_ok('N4R10.D8 evidence completeness is reported honestly',
      (ev->>'evidence_completeness')::numeric < 1
      AND (ev->>'components_available')::int < (ev->>'components_total')::int, ev->>'evidence_completeness');
    r := r || public._qa_s13_ok('N4R10.D9 uncollected stock accuracy is declared, not invented',
      ev->'components'->'availability_accuracy'->>'reason' = 'NOT_COLLECTED'
      AND (ev->'components'->'availability_accuracy'->'score') = 'null'::jsonb, NULL);

    ------------------------------------------------- E) REPUTATION EVIDENCE (R9)
    ev := public._marche_rank_evidence(la, NULL, NULL, NULL);
    r := r || public._qa_s13_ok('N4R10.E1 a store with no ratings is not punished with a zero',
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
    r := r || public._qa_s13_ok('N4R10.E2 verified store ratings become usable reputation evidence',
      (ev->'components'->'reputation'->>'available')::boolean
      AND (ev->'components'->'reputation'->>'sample_count')::int = 3, ev->'components'->'reputation'#>>'{}');
    r := r || public._qa_s13_ok('N4R10.E3 an average of 4/5 maps to the expected 0.75 score',
      round((ev->'components'->'reputation'->>'score')::numeric, 4) = 0.7500,
      ev->'components'->'reputation'->>'score');
    r := r || public._qa_s13_ok('N4R10.E4 driver ratings never contaminate store reputation',
      (ev->'components'->'reputation'->>'sample_count')::int = 3
      AND ev->'components'->'reputation'->>'subject_kind' = 'merchant_store', NULL);
    ev2 := public._marche_rank_evidence(ln, NULL, NULL, NULL);
    r := r || public._qa_s13_ok('N4R10.E5 one store''s reputation never leaks to another store',
      (ev2->'components'->'reputation'->>'available')::boolean IS FALSE, NULL);

    ------------------------------------------------ F) RELIABILITY EVIDENCE (R5)
    r := r || public._qa_s13_ok('N4R10.F1 a store with no fulfilment history is not scored',
      (ev->'components'->'reliability'->>'available')::boolean IS FALSE
      AND ev->'components'->'reliability'->>'reason' = 'INSUFFICIENT_FULFILLMENT_HISTORY', NULL);

    INSERT INTO public.marche_orders(buyer_user_id, merchant_store_id, merchant_user_id,
      merchandise_subtotal_gnf, item_count, line_count, client_request_id, request_fingerprint,
      fulfillment_state, delivered_at)
    SELECT v_buy, s1, v_m1, 10000, 1, 1, 'qa-n410-d'||g, 'qa-n410-d'||g, 'delivered', now()
      FROM generate_series(1,3) g;
    INSERT INTO public.marche_orders(buyer_user_id, merchant_store_id, merchant_user_id,
      merchandise_subtotal_gnf, item_count, line_count, client_request_id, request_fingerprint,
      fulfillment_state, rejected_at)
    VALUES (v_buy, s1, v_m1, 10000, 1, 1, 'qa-n410-r1', 'qa-n410-r1', 'rejected', now());

    ev := public._marche_rank_evidence(la, NULL, NULL, NULL);
    r := r || public._qa_s13_ok('N4R10.F2 delivered vs merchant-rejected produces the true rate',
      (ev->'components'->'reliability'->>'available')::boolean
      AND (ev->'components'->'reliability'->>'sample_count')::int = 4
      AND round((ev->'components'->'reliability'->>'score')::numeric,4) = 0.7500,
      ev->'components'->'reliability'#>>'{}');

    INSERT INTO public.marche_orders(buyer_user_id, merchant_store_id, merchant_user_id,
      merchandise_subtotal_gnf, item_count, line_count, client_request_id, request_fingerprint,
      status, fulfillment_state)
    SELECT v_buy, s1, v_m1, 10000, 1, 1, 'qa-n410-c'||g, 'qa-n410-c'||g, 'cancelled', 'committed'
      FROM generate_series(1,4) g;

    ev2 := public._marche_rank_evidence(la, NULL, NULL, NULL);
    r := r || public._qa_s13_ok('N4R10.F3 buyer cancellations never damage merchant reliability',
      (ev2->'components'->'reliability'->>'sample_count')::int = 4
      AND (ev2->'components'->'reliability'->>'score') = (ev->'components'->'reliability'->>'score'),
      ev2->'components'->'reliability'#>>'{}');
    r := r || public._qa_s13_ok('N4R10.F4 the reliability component declares its cancellation law',
      (ev2->'components'->'reliability'->>'buyer_cancellation_counted')::boolean IS FALSE, NULL);

    --------------------------------------------------------------- G) DISTANCE
    ev := public._marche_rank_evidence(la, NULL, NULL, NULL);
    r := r || public._qa_s13_ok('N4R10.G1 without customer coordinates distance is declared missing',
      (ev->'components'->'distance'->>'available')::boolean IS FALSE
      AND ev->'components'->'distance'->>'reason' = 'NO_CUSTOMER_COORDINATES', NULL);
    ev := public._marche_rank_evidence(la, 9.5370, -13.6785, NULL);
    ev2 := public._marche_rank_evidence(ln, 9.5370, -13.6785, NULL);
    r := r || public._qa_s13_ok('N4R10.G2 a nearby store beats a far store on distance',
      (ev->'components'->'distance'->>'available')::boolean
      AND (ev2->'components'->'distance'->>'available')::boolean
      AND (ev->'components'->'distance'->>'score')::numeric > (ev2->'components'->'distance'->>'score')::numeric,
      format('%s vs %s', ev->'components'->'distance'->>'distance_m', ev2->'components'->'distance'->>'distance_m'));
    r := r || public._qa_s13_ok('N4R10.G3 distance is honestly labelled as straight-line, not road',
      (ev->'components'->'distance'->>'road_distance')::boolean IS FALSE
      AND ev->'components'->'distance'->>'method' = 'haversine_great_circle', NULL);
    ev := public._marche_rank_evidence(l3, 9.5370, -13.6785, NULL);
    r := r || public._qa_s13_ok('N4R10.G4 a store without coordinates is not invented a distance',
      (ev->'components'->'distance'->>'available')::boolean IS FALSE
      AND ev->'components'->'distance'->>'reason' = 'NO_STORE_COORDINATES'
      AND (ev->'components'->'distance'->'distance_m') = 'null'::jsonb, NULL);
    r := r || public._qa_s13_ok('N4R10.G5 a coordinate-less store is still rankable, not excluded',
      (ev->>'ranked')::boolean AND (ev->>'score') IS NOT NULL, ev->>'score');

    -------------------------------------------------------------- H) FRESHNESS
    r := r || public._qa_s13_ok('N4R10.H1 a listing published now is at maximum freshness',
      round((ev->'components'->'freshness'->>'score')::numeric, 2) = 1.00, ev->'components'->'freshness'#>>'{}');
    ev2 := public._marche_rank_evidence(la, NULL, NULL, NULL, now() + interval '14 days');
    r := r || public._qa_s13_ok('N4R10.H2 freshness halves after exactly one half-life',
      round((ev2->'components'->'freshness'->>'score')::numeric, 2) = 0.50,
      ev2->'components'->'freshness'->>'score');

    ------------------------------------------------------ I) DISCOVERY BEHAVIOUR
    PERFORM set_config('request.jwt.claims','', true);
    d1 := to_jsonb(ARRAY(SELECT x.id FROM public.marche_listings_discover(
            'QA N410', NULL, NULL, 'recommended', 60, 0, 9.5370, -13.6785) x));
    d2 := to_jsonb(ARRAY(SELECT x.id FROM public.marche_listings_discover(
            'QA N410', NULL, NULL, 'recommended', 60, 0, 9.5370, -13.6785) x));
    r := r || public._qa_s13_ok('N4R10.I1 recommended discovery returns the fixture listings',
      jsonb_array_length(d1) = 7, jsonb_array_length(d1)::text);
    r := r || public._qa_s13_ok('N4R10.I2 the recommended order is deterministic',
      d1 = d2, NULL);
    r := r || public._qa_s13_ok('N4R10.I3 recommended results carry a server-computed score',
      (SELECT bool_and(x.rank_score_bps IS NOT NULL) FROM public.marche_listings_discover(
        'QA N410', NULL, NULL, 'recommended', 60, 0, 9.5370, -13.6785) x), NULL);
    r := r || public._qa_s13_ok('N4R10.I4 recommended results carry explainable evidence',
      (SELECT bool_and(x.rank_evidence ? 'components') FROM public.marche_listings_discover(
        'QA N410', NULL, NULL, 'recommended', 60, 0, 9.5370, -13.6785) x), NULL);
    r := r || public._qa_s13_ok('N4R10.I5 the cheapest, nearest, best-rated fixture ranks first',
      (d1->>0)::uuid = la, d1#>>'{}');
    r := r || public._qa_s13_ok('N4R10.I6 an explicit price sort remains an exact override',
      (SELECT array_agg(x.price_gnf ORDER BY o) = array_agg(x.price_gnf ORDER BY x.price_gnf)
         FROM (SELECT y.*, row_number() OVER () o FROM public.marche_listings_discover(
                 'QA N410', NULL, NULL, 'price_asc', 60, 0, 9.5370, -13.6785) y) x), NULL);
    r := r || public._qa_s13_ok('N4R10.I7 an explicit recency sort remains an exact override',
      (SELECT bool_and(a >= b) FROM (
         SELECT x.created_at a, lead(x.created_at) OVER () b
           FROM public.marche_listings_discover('QA N410', NULL, NULL, 'recent', 60, 0, NULL, NULL) x) t
        WHERE b IS NOT NULL), NULL);

    -- ranking never overrides commercial eligibility
    PERFORM set_config('marche.rpc','1', true);
    UPDATE public.marketplace_listings SET status='paused' WHERE id = la;
    PERFORM set_config('marche.rpc','', true);
    d2 := to_jsonb(ARRAY(SELECT x.id FROM public.marche_listings_discover(
            'QA N410', NULL, NULL, 'recommended', 60, 0, 9.5370, -13.6785) x));
    r := r || public._qa_s13_ok('N4R10.I8 ranking can never resurrect a non-orderable listing',
      NOT (d2 @> to_jsonb(ARRAY[la])) AND jsonb_array_length(d2) = 6, jsonb_array_length(d2)::text);
    PERFORM set_config('marche.rpc','1', true);
    UPDATE public.marketplace_listings SET status='active' WHERE id = la;
    PERFORM set_config('marche.rpc','', true);

    --------------------------------------------------- J) PUBLIC EXPLAINABILITY
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    j := public.marche_listing_rank_explain(la, 9.5370, -13.6785);
    r := r || public._qa_s13_ok('N4R10.J1 a shopper can see why a listing ranks where it does',
      j ? 'components' OR j ? 'reasons', j#>>'{}');
    r := r || public._qa_s13_ok('N4R10.J2 the public explanation leaks no rival identity',
      j::text NOT LIKE '%'||lb::text||'%' AND j::text NOT LIKE '%'||v_m2::text||'%', NULL);
    pol := public.marche_ranking_policy_public();
    r := r || public._qa_s13_ok('N4R10.J3 the ranking policy in force is publicly disclosed',
      (pol->>'version') IS NOT NULL, pol#>>'{}');

    ------------------------------------------------------ K) ADMIN AUTHORITY LAW
    v_err := NULL;
    BEGIN PERFORM public.marche_ranking_policy_publish(jsonb_build_object('w_price',9000));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R10.K1 an ordinary user cannot publish a ranking policy',
      v_err = 'NOT_AUTHORIZED', COALESCE(v_err,'no error'));
    v_err := NULL;
    BEGIN PERFORM public.marche_ranking_policy_admin_list();
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R10.K2 an ordinary user cannot read the policy history',
      v_err = 'NOT_AUTHORIZED', COALESCE(v_err,'no error'));
    v_err := NULL;
    BEGIN PERFORM public.marche_ranking_audit_listing(la, NULL, NULL);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R10.K3 an ordinary user cannot open the ranking audit',
      v_err = 'NOT_AUTHORIZED', COALESCE(v_err,'no error'));
    v_err := NULL;
    BEGIN PERFORM public.marche_shopper_performance(v_drv);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R10.K4 nobody can read another person''s performance record',
      v_err = 'NOT_AUTHORIZED', COALESCE(v_err,'no error'));

    ---------------------------------------- L) SHOPPER PERFORMANCE INTELLIGENCE
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    j := public.marche_shopper_performance(NULL);
    r := r || public._qa_s13_ok('N4R10.L1 a shopper with no history gets an honest empty answer',
      (j->>'available')::boolean IS FALSE AND j->>'reason' = 'NO_PROCUREMENT_HISTORY', j#>>'{}');
    r := r || public._qa_s13_ok('N4R10.L2 performance intelligence declares it is read-only',
      (j->>'read_only')::boolean AND (j->>'affects_assignment')::boolean IS FALSE, NULL);

    INSERT INTO public.marche_procurement_missions(request_id, buyer_user_id, shopper_user_id,
      state, assigned_at, shopping_started_at, purchase_submitted_at, completed_at)
    VALUES (gen_random_uuid(), v_buy, v_drv, 'completed',
            now() - interval '90 min', now() - interval '60 min',
            now() - interval '40 min', now() - interval '30 min'),
           (gen_random_uuid(), v_buy, v_drv, 'completed',
            now() - interval '80 min', now() - interval '50 min',
            now() - interval '30 min', now() - interval '20 min'),
           (gen_random_uuid(), v_buy, v_drv, 'cancelled', now() - interval '70 min',
            NULL, NULL, NULL);
    UPDATE public.marche_procurement_missions SET cancelled_at = now()
     WHERE shopper_user_id = v_drv AND state = 'cancelled';

    j := public.marche_shopper_performance(NULL);
    r := r || public._qa_s13_ok('N4R10.L3 completed procurement history becomes real intelligence',
      (j->>'available')::boolean AND (j->>'missions_assigned')::int = 3
      AND (j->>'missions_completed')::int = 2, j#>>'{}');
    r := r || public._qa_s13_ok('N4R10.L4 the completion rate is derived, not declared',
      round((j->>'completion_rate')::numeric, 4) = round(2::numeric/3, 4), j->>'completion_rate');
    r := r || public._qa_s13_ok('N4R10.L5 median shopping duration is computed from real timestamps',
      round((j->>'median_shopping_minutes')::numeric) = 20, j->>'median_shopping_minutes');
    r := r || public._qa_s13_ok('N4R10.L6 performance never exposes buyer or basket identity',
      NOT (j ? 'buyer_user_id') AND j::text NOT LIKE '%'||v_buy::text||'%', NULL);
    r := r || public._qa_s13_ok('N4R10.L7 reading performance writes nothing back',
      (SELECT count(*) FROM public.marche_procurement_missions WHERE shopper_user_id=v_drv) = 3, NULL);

    ------------------------------------------------------- M) POLICY EFFECTIVITY
    PERFORM set_config('request.jwt.claims','', true);
    pol := public._marche_ranking_policy(now());
    r := r || public._qa_s13_ok('N4R10.M1 an effective policy always resolves for ranking',
      pol IS NOT NULL AND (pol->>'version')::int >= 1, pol->>'version');
    ev := public._marche_rank_evidence(la, NULL, NULL,
      jsonb_build_object('id', pol->>'id', 'version', 999,
        'w_price', 10000, 'w_reputation', 0, 'w_reliability', 0, 'w_distance', 0, 'w_freshness', 0,
        'min_price_observations', 3, 'min_reputation_events', 3, 'min_fulfillment_history', 3,
        'distance_max_m', 15000, 'freshness_half_life_days', 14));
    r := r || public._qa_s13_ok('N4R10.M2 weights genuinely change the resulting score',
      (ev->>'score')::numeric = (ev->'components'->'price'->>'score')::numeric,
      format('%s / %s', ev->>'score', ev->'components'->'price'->>'score'));
    r := r || public._qa_s13_ok('N4R10.M3 the score carries the policy version that produced it',
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

  ------------------------------------------------------------------ N) RESIDUE
  SELECT count(*) INTO v_n FROM public.marketplace_listings;
  r := r || public._qa_s13_ok('N4R10.N1 zero listing residue', v_n = base_lst, format('%s->%s', base_lst, v_n));
  SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations;
  r := r || public._qa_s13_ok('N4R10.N2 zero price observation residue', v_n = base_obs, format('%s->%s', base_obs, v_n));
  SELECT count(*) INTO v_n FROM public.marche_reputation_events;
  r := r || public._qa_s13_ok('N4R10.N3 zero reputation residue', v_n = base_rep, format('%s->%s', base_rep, v_n));
  SELECT count(*) INTO v_n FROM public.marche_orders;
  r := r || public._qa_s13_ok('N4R10.N4 zero order residue', v_n = base_ord, format('%s->%s', base_ord, v_n));
  SELECT count(*) INTO v_n FROM public.marche_ranking_policies;
  r := r || public._qa_s13_ok('N4R10.N5 zero ranking policy residue', v_n = base_pol, format('%s->%s', base_pol, v_n));

  RETURN r;
END;
$fn$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r10() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node4_marche_r10() TO service_role;