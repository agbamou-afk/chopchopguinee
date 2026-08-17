
CREATE OR REPLACE FUNCTION public._qa_node4_marche_r7_fxcore()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  r jsonb := '[]'::jsonb;
  v_err text; v_n bigint; v_res jsonb; v_j jsonb;
  v_master0 bigint; v_master1 bigint; v_flags0 jsonb; v_flags1 jsonb;
  v_buy uuid := gen_random_uuid(); v_buy2 uuid := gen_random_uuid();
  v_shop uuid := gen_random_uuid(); v_shop2 uuid := gen_random_uuid();
  v_drv uuid := gen_random_uuid(); v_mer uuid := gen_random_uuid();
  v_com uuid; v_v1 uuid; v_v2 uuid; v_v3 uuid; v_o1 uuid; v_o2 uuid; v_o3 uuid;
  v_r1 uuid; v_r2 uuid; v_bal0 bigint; v_held0 bigint; v_bal1 bigint; v_held1 bigint;
  v_obs0 bigint; v_ev0 bigint; v_ms0 bigint;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;
  SELECT count(*) INTO v_ms0 FROM public.missions;

  BEGIN
    -- ================= A. STRUCTURE + GRANT LAW =================
    r := r || public._qa_s13_ok('N4R7.A1 shopper mission table exists',
      to_regclass('public.marche_procurement_missions') IS NOT NULL, NULL);
    r := r || public._qa_s13_ok('N4R7.A2 per-line resolution table exists',
      to_regclass('public.marche_procurement_line_resolutions') IS NOT NULL, NULL);
    r := r || public._qa_s13_ok('N4R7.A3 append-only proposal table exists',
      to_regclass('public.marche_procurement_proposals') IS NOT NULL, NULL);
    r := r || public._qa_s13_ok('N4R7.A4 append-only mission event table exists',
      to_regclass('public.marche_procurement_mission_events') IS NOT NULL, NULL);
    r := r || public._qa_s13_ok('N4R7.A5 purchase evidence table exists',
      to_regclass('public.marche_procurement_purchase_evidence') IS NOT NULL, NULL);
    r := r || public._qa_s13_ok('N4R7.A6 evidence bucket is private',
      EXISTS (SELECT 1 FROM storage.buckets WHERE id='marche-procurement-evidence' AND public = false), NULL);
    SELECT count(*) INTO v_n FROM information_schema.role_table_grants
     WHERE table_schema='public' AND grantee IN ('anon','authenticated')
       AND table_name IN ('marche_procurement_missions','marche_procurement_line_resolutions',
           'marche_procurement_proposals','marche_procurement_mission_events',
           'marche_procurement_purchase_evidence');
    r := r || public._qa_s13_ok('N4R7.A7 no direct anon/authenticated grants on R7 tables', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace nsp ON nsp.oid=p.pronamespace
     WHERE nsp.nspname='public' AND (p.proname LIKE 'marche_shopper%' OR p.proname LIKE 'marche_procurement_mission%'
        OR p.proname = 'marche_customer_decide_proposal')
       AND has_function_privilege('anon', p.oid, 'EXECUTE');
    r := r || public._qa_s13_ok('N4R7.A8 anon cannot execute any R7 RPC', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM pg_proc p JOIN pg_namespace nsp ON nsp.oid=p.pronamespace
     WHERE nsp.nspname='public' AND (p.proname LIKE 'marche_shopper%' OR p.proname LIKE '\_marche\_pm%'
        OR p.proname='marche_customer_decide_proposal' OR p.proname='_marche_procurement_settle_core')
       AND p.prosecdef AND NOT ('search_path=public' = ANY(COALESCE(p.proconfig, ARRAY[]::text[])));
    r := r || public._qa_s13_ok('N4R7.A9 every R7 definer function pins search_path=public', v_n = 0, v_n::text);
    r := r || public._qa_s13_ok('N4R7.A10 has_role remains non-executable by anon',
      NOT has_function_privilege('anon','public.has_role(uuid,app_role)','EXECUTE'), NULL);
    r := r || public._qa_s13_ok('N4R7.A11 settlement stays privileged-only for staff RPC',
      NOT has_function_privilege('authenticated',
        'public.marche_procurement_settle_internal(uuid,bigint,text)','EXECUTE'), NULL);
    r := r || public._qa_s13_ok('N4R7.A12 single settlement engine (core reused by staff wrapper)',
      (SELECT pg_get_functiondef(oid) FROM pg_proc WHERE oid =
        'public.marche_procurement_settle_internal(uuid,bigint,text)'::regprocedure)
        LIKE '%_marche_procurement_settle_core%', NULL);
    r := r || public._qa_s13_ok('N4R7.A13 no parallel wallet/ledger writes in R7 lifecycle RPCs',
      NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace nsp ON nsp.oid=p.pronamespace
        WHERE nsp.nspname='public' AND p.proname LIKE 'marche_shopper%'
          AND (pg_get_functiondef(p.oid) ILIKE '%UPDATE public.wallets%'
            OR pg_get_functiondef(p.oid) ILIKE '%INSERT INTO public.ledger_%'
            OR pg_get_functiondef(p.oid) ILIKE '%_ledger_post%')), NULL);
    r := r || public._qa_s13_ok('N4R7.A14 no new role/professional identity enum introduced',
      NOT EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid
                   WHERE t.typname='app_role' AND e.enumlabel='shopper'), NULL);

    -- ================= FIXTURES =================
    PERFORM public._qa_s13_user(v_buy, 'r7buy');
    PERFORM public._qa_s13_user(v_buy2, 'r7buy2');
    PERFORM public._qa_s13_user(v_mer, 'r7mer');
    PERFORM public._qa_s13_wallet(v_buy, 'client', 5000000, 0);
    PERFORM public._qa_s13_wallet(v_buy2, 'client', 5000000, 0);
    PERFORM public._qa_s13_driver(v_shop, 'r7shop', 0);
    PERFORM public._qa_s13_driver(v_shop2, 'r7shop2', 0);
    PERFORM public._qa_s13_driver(v_drv, 'r7drv', 0);
    UPDATE public.driver_profiles
       SET capabilities = capabilities || ARRAY['marche_shopper']
     WHERE user_id IN (v_shop, v_shop2);

    INSERT INTO public.marche_staple_categories(code, name_fr) VALUES ('qa_r7_cat','QA R7')
      ON CONFLICT (code) DO NOTHING;
    INSERT INTO public.marche_staple_commodities(code, category_code, name_fr, unit_family)
    VALUES ('qa_r7_riz','qa_r7_cat','QA Riz', (SELECT unit_family FROM public.marche_staple_commodities LIMIT 1))
    RETURNING id INTO v_com;
    IF v_com IS NULL THEN RAISE EXCEPTION 'QA_R7_FIXTURE_COMMODITY'; END IF;
    INSERT INTO public.marche_staple_variants(commodity_id, code, name_fr)
      VALUES (v_com,'v1','QA V1') RETURNING id INTO v_v1;
    INSERT INTO public.marche_staple_variants(commodity_id, code, name_fr)
      VALUES (v_com,'v2','QA V2') RETURNING id INTO v_v2;
    INSERT INTO public.marche_staple_variants(commodity_id, code, name_fr)
      VALUES (v_com,'v3','QA V3') RETURNING id INTO v_v3;
    INSERT INTO public.marche_staple_purchase_options(variant_id, code, sale_unit, label_fr,
        normalization_kind, canonical_base_unit, canonical_quantity, min_qty, max_qty, step_qty)
      VALUES (v_v1,'o1','kg','Sac 1kg','exact','kg',1,1,20,1) RETURNING id INTO v_o1;
    INSERT INTO public.marche_staple_purchase_options(variant_id, code, sale_unit, label_fr,
        normalization_kind, canonical_base_unit, canonical_quantity, min_qty, max_qty, step_qty)
      VALUES (v_v2,'o2','kg','Sac 1kg','exact','kg',1,1,20,1) RETURNING id INTO v_o2;
    INSERT INTO public.marche_staple_purchase_options(variant_id, code, sale_unit, label_fr,
        normalization_kind, canonical_base_unit, canonical_quantity, min_qty, max_qty, step_qty)
      VALUES (v_v3,'o3','kg','Sac 1kg','exact','kg',1,1,20,1) RETURNING id INTO v_o3;

    INSERT INTO public.marche_procurement_price_observations
      (purchase_option_id, variant_id, commodity_id, observed_unit_price_gnf, observed_at, source_kind)
    SELECT o.id, o.vid, v_com, 10000, now() - (s.i || ' hours')::interval, 'ops_survey'
      FROM (VALUES (v_o1, v_v1),(v_o2, v_v2),(v_o3, v_v3)) o(id, vid),
           generate_series(1,3) s(i);

    SELECT count(*) INTO v_obs0 FROM public.marche_procurement_price_observations;

    -- ================= B. AUTHORIZED BASKET (R6.5 sovereign) =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_res := public.marche_procurement_authorize(jsonb_build_object(
      'client_request_id', gen_random_uuid(),
      'ceiling_gnf', 40000,
      'lines', jsonb_build_array(
        jsonb_build_object('commodity_code','qa_r7_riz','variant_code','v1','option_code','o1','qty',2),
        jsonb_build_object('commodity_code','qa_r7_riz','variant_code','v2','option_code','o2','qty',1),
        jsonb_build_object('commodity_code','qa_r7_riz','variant_code','v3','option_code','o3','qty',1))));
    v_r1 := (v_res->>'id')::uuid;
    r := r || public._qa_s13_ok('N4R7.B1 R6.5 authorization still produces a sovereign basket',
      v_r1 IS NOT NULL AND v_res->>'status' = 'authorized', v_res::text);
    r := r || public._qa_s13_ok('N4R7.B2 ceiling frozen at authorization',
      (v_res->>'authorized_ceiling_gnf')::bigint = 40000, v_res->>'authorized_ceiling_gnf');
    SELECT balance_gnf, held_gnf INTO v_bal0, v_held0
      FROM public.wallets WHERE owner_user_id = v_buy AND party_type='client';
    r := r || public._qa_s13_ok('N4R7.B3 ceiling is held on the customer wallet (Slice13 rail)',
      v_held0 = 40000, format('bal=%s held=%s', v_bal0, v_held0));

    v_res := public.marche_procurement_set_destination(jsonb_build_object(
      'request_id', v_r1, 'destination_address','Kaloum, Conakry'));
    r := r || public._qa_s13_ok('N4R7.B4 customer sets delivery destination',
      v_res->>'destination_address' = 'Kaloum, Conakry', v_res::text);

    -- ================= C. ELIGIBILITY =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    BEGIN v_res := public.marche_shopper_claim(v_r1); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R7.C1 approved driver WITHOUT marche_shopper is denied',
      v_err = 'PROCUREMENT_SHOPPER_NOT_ELIGIBLE', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    BEGIN v_res := public.marche_shopper_claim(v_r1); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R7.C2 customer cannot become a shopper',
      v_err = 'PROCUREMENT_SHOPPER_NOT_ELIGIBLE', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_mer), true);
    BEGIN v_res := public.marche_shopper_claim(v_r1); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R7.C3 merchant/non-driver cannot become a shopper',
      v_err = 'PROCUREMENT_SHOPPER_NOT_ELIGIBLE', v_err);

    UPDATE public.driver_profiles SET status='suspended' WHERE user_id = v_shop2;
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_shop2), true);
    BEGIN v_res := public.marche_shopper_claim(v_r1); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R7.C4 suspended shopper-capable driver is denied',
      v_err = 'PROCUREMENT_SHOPPER_NOT_ELIGIBLE', v_err);
    UPDATE public.driver_profiles SET status='approved' WHERE user_id = v_shop2;

    PERFORM set_config('request.jwt.claims', '', true);
    BEGIN v_res := public.marche_shopper_claim(v_r1); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R7.C5 unauthenticated claim is denied',
      v_err = 'PROCUREMENT_AUTH_REQUIRED', v_err);

    -- ================= D. ASSIGNMENT =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_shop), true);
    v_res := public.marche_shopper_claim(v_r1);
    r := r || public._qa_s13_ok('N4R7.D1 eligible shopper claims the basket',
      v_res->>'state' = 'assigned', v_res::text);
    r := r || public._qa_s13_ok('N4R7.D2 assignment actor + time recorded server-side',
      (v_res->>'shopper_user_id')::uuid = v_shop AND v_res->>'assigned_at' IS NOT NULL, NULL);
    v_res := public.marche_shopper_claim(v_r1);
    r := r || public._qa_s13_ok('N4R7.D3 replayed claim is idempotent',
      (v_res->>'replayed')::boolean AND (v_res->>'shopper_user_id')::uuid = v_shop, v_res::text);
    SELECT count(*) INTO v_n FROM public.marche_procurement_mission_events
     WHERE request_id = v_r1 AND event='shopper_assigned';
    r := r || public._qa_s13_ok('N4R7.D4 replay creates no duplicate assignment event', v_n = 1, v_n::text);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_shop2), true);
    BEGIN v_res := public.marche_shopper_claim(v_r1); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R7.D5 second shopper cannot steal an owned basket',
      v_err = 'PROCUREMENT_MISSION_ALREADY_ASSIGNED', v_err);
    SELECT shopper_user_id INTO v_buy2 FROM public.marche_procurement_missions WHERE request_id = v_r1;
    r := r || public._qa_s13_ok('N4R7.D6 exactly one owner survives contention',
      v_buy2 = v_shop, v_buy2::text);
    BEGIN v_res := public.marche_shopper_arrive_market(v_r1, NULL); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R7.D7 non-assigned shopper cannot mutate the mission',
      v_err = 'PROCUREMENT_NOT_ASSIGNED_SHOPPER', v_err);
    SELECT count(*) INTO v_n FROM public.marche_procurement_line_resolutions WHERE request_id = v_r1;
    r := r || public._qa_s13_ok('N4R7.D8 line resolution ledger materialised from frozen basket',
      v_n = 3, v_n::text);

    -- ================= E. LIFECYCLE ORDER =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_shop), true);
    BEGIN v_res := public.marche_shopper_start_shopping(v_r1); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R7.E1 cannot start shopping before reaching the market',
      v_err = 'PROCUREMENT_ILLEGAL_TRANSITION', v_err);
    BEGIN v_res := public.marche_shopper_start_delivery(v_r1); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R7.E2 cannot start delivery before purchase verification',
      v_err = 'PROCUREMENT_PURCHASE_VERIFICATION_REQUIRED', v_err);

    v_res := public.marche_shopper_arrive_market(v_r1, NULL);
    r := r || public._qa_s13_ok('N4R7.E3 market arrival is server-timestamped',
      v_res->>'state'='at_market' AND v_res->>'arrived_market_at' IS NOT NULL, v_res::text);
    v_res := public.marche_shopper_arrive_market(v_r1, NULL);
    r := r || public._qa_s13_ok('N4R7.E4 arrival replay is idempotent',
      (v_res->>'replayed')::boolean, v_res::text);
    v_res := public.marche_shopper_start_shopping(v_r1);
    r := r || public._qa_s13_ok('N4R7.E5 shopping start is server-timestamped',
      v_res->>'state'='shopping' AND v_res->>'shopping_started_at' IS NOT NULL, v_res::text);
    v_res := public.marche_shopper_start_shopping(v_r1);
    r := r || public._qa_s13_ok('N4R7.E6 shopping start replay is idempotent',
      (v_res->>'replayed')::boolean, v_res::text);

    -- ================= F. LINE RESOLUTION =================
    v_res := public.marche_shopper_resolve_line(jsonb_build_object(
      'request_id', v_r1, 'line_no', 1, 'kind','acquired', 'actual_unit_price_gnf', 9000));
    r := r || public._qa_s13_ok('N4R7.F1 line acquired as requested at a real unit price',
      (SELECT actual_line_total_gnf FROM public.marche_procurement_line_resolutions
        WHERE request_id=v_r1 AND line_no=1) = 18000, v_res::text);
    r := r || public._qa_s13_ok('N4R7.F2 weight-based normalized actual quantity captured',
      (SELECT actual_normalized_quantity FROM public.marche_procurement_line_resolutions
        WHERE request_id=v_r1 AND line_no=1) = 2, NULL);

    BEGIN v_res := public.marche_shopper_resolve_line(jsonb_build_object(
      'request_id', v_r1, 'line_no', 1, 'kind','acquired', 'actual_qty', 5,
      'actual_unit_price_gnf', 9000)); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R7.F3 silent quantity change is refused without approval',
      v_err = 'PROCUREMENT_APPROVAL_REQUIRED', v_err);
    BEGIN v_res := public.marche_shopper_resolve_line(jsonb_build_object(
      'request_id', v_r1, 'line_no', 1, 'kind','acquired', 'actual_unit_price_gnf', 9000,
      'substitute_label_fr','Autre riz')); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R7.F4 silent substitution is refused without approval',
      v_err = 'PROCUREMENT_APPROVAL_REQUIRED', v_err);
    BEGIN v_res := public.marche_shopper_resolve_line(jsonb_build_object(
      'request_id', v_r1, 'line_no', 1, 'kind','acquired')); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R7.F5 acquisition without a real price is refused',
      v_err = 'PROCUREMENT_ACTUAL_PRICE_REQUIRED', v_err);

    v_res := public.marche_shopper_resolve_line(jsonb_build_object(
      'request_id', v_r1, 'line_no', 2, 'kind','unavailable', 'note_fr','Rupture'));
    r := r || public._qa_s13_ok('N4R7.F6 unavailable item stays truthful (no fake acquisition)',
      (SELECT state FROM public.marche_procurement_line_resolutions
        WHERE request_id=v_r1 AND line_no=2) = 'unavailable'
      AND (SELECT actual_line_total_gnf FROM public.marche_procurement_line_resolutions
        WHERE request_id=v_r1 AND line_no=2) = 0, v_res::text);

    -- ================= G. SUBSTITUTION + CUSTOMER APPROVAL =================
    v_res := public.marche_shopper_resolve_line(jsonb_build_object(
      'request_id', v_r1, 'line_no', 3, 'kind','propose_substitution',
      'substitute_label_fr','Riz local équivalent'));
    r := r || public._qa_s13_ok('N4R7.G1 substitution proposal recorded, item not acquired',
      (SELECT state FROM public.marche_procurement_line_resolutions
        WHERE request_id=v_r1 AND line_no=3) = 'substitution_proposed', v_res::text);
    BEGIN v_res := public.marche_shopper_resolve_line(jsonb_build_object(
      'request_id', v_r1, 'line_no', 3, 'kind','acquired',
      'actual_unit_price_gnf', 12000, 'substitute_label_fr','Riz local équivalent'));
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R7.G2 pending approval blocks acquisition of that line',
      v_err = 'PROCUREMENT_APPROVAL_PENDING', v_err);
    BEGIN v_res := public.marche_shopper_submit_purchase(jsonb_build_object('request_id', v_r1));
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R7.G3 pending approval blocks purchase verification',
      v_err IN ('PROCUREMENT_LINES_UNRESOLVED','PROCUREMENT_APPROVAL_PENDING'), v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy2), true);
    BEGIN v_res := public.marche_customer_decide_proposal(jsonb_build_object(
      'request_id', v_r1, 'line_no', 3, 'version', 1, 'decision','approve')); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R7.G4 a different customer cannot approve this basket',
      v_err = 'PROCUREMENT_NOT_AUTHORIZED', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_shop), true);
    BEGIN v_res := public.marche_customer_decide_proposal(jsonb_build_object(
      'request_id', v_r1, 'line_no', 3, 'version', 1, 'decision','approve')); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R7.G5 the shopper cannot approve their own proposal',
      v_err = 'PROCUREMENT_NOT_AUTHORIZED', v_err);

    -- shopper supersedes v1 with v2 -> stale approval must fail
    v_res := public.marche_shopper_resolve_line(jsonb_build_object(
      'request_id', v_r1, 'line_no', 3, 'kind','propose_substitution',
      'substitute_label_fr','Riz local premium'));
    r := r || public._qa_s13_ok('N4R7.G6 a new proposal supersedes the previous version',
      (SELECT status FROM public.marche_procurement_proposals
        WHERE request_id=v_r1 AND line_no=3 AND version=1) = 'superseded', NULL);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    BEGIN v_res := public.marche_customer_decide_proposal(jsonb_build_object(
      'request_id', v_r1, 'line_no', 3, 'version', 1, 'decision','approve')); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R7.G7 stale proposal approval fails safely',
      v_err = 'PROCUREMENT_PROPOSAL_STALE', v_err);

    v_res := public.marche_customer_decide_proposal(jsonb_build_object(
      'request_id', v_r1, 'line_no', 3, 'version', 2, 'decision','approve'));
    r := r || public._qa_s13_ok('N4R7.G8 customer approves the current proposal',
      (SELECT status FROM public.marche_procurement_proposals
        WHERE request_id=v_r1 AND line_no=3 AND version=2) = 'approved', v_res::text);
    v_res := public.marche_customer_decide_proposal(jsonb_build_object(
      'request_id', v_r1, 'line_no', 3, 'version', 2, 'decision','approve'));
    r := r || public._qa_s13_ok('N4R7.G9 approval replay is idempotent',
      (v_res->>'replayed')::boolean, v_res::text);
    BEGIN v_res := public.marche_customer_decide_proposal(jsonb_build_object(
      'request_id', v_r1, 'line_no', 3, 'version', 2, 'decision','reject')); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R7.G10 a decided proposal cannot be flipped',
      v_err = 'PROCUREMENT_PROPOSAL_ALREADY_DECIDED', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_shop), true);
    BEGIN v_res := public.marche_shopper_resolve_line(jsonb_build_object(
      'request_id', v_r1, 'line_no', 3, 'kind','acquired',
      'actual_unit_price_gnf', 12000, 'substitute_label_fr','Riz local premium'));
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R7.G11 approved substitution can now be acquired',
      v_err = 'NO_ERROR' AND (SELECT actual_line_total_gnf FROM public.marche_procurement_line_resolutions
        WHERE request_id=v_r1 AND line_no=3) = 12000, v_err);

    -- ================= H. EVIDENCE + VERIFICATION =================
    BEGIN v_res := public.marche_shopper_submit_purchase(jsonb_build_object('request_id', v_r1));
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R7.H1 purchase verification requires receipt evidence',
      v_err = 'PROCUREMENT_EVIDENCE_REQUIRED', v_err);
    BEGIN v_res := public.marche_shopper_attach_evidence(jsonb_build_object(
      'request_id', v_r1, 'storage_path', gen_random_uuid()::text || '/receipt.jpg')); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R7.H2 evidence path outside the basket folder is refused',
      v_err = 'PROCUREMENT_EVIDENCE_PATH_INVALID', v_err);
    v_res := public.marche_shopper_attach_evidence(jsonb_build_object(
      'request_id', v_r1, 'storage_path', v_r1::text || '/receipt.jpg'));
    r := r || public._qa_s13_ok('N4R7.H3 receipt evidence linked to basket/actor/time',
      (SELECT count(*) FROM public.marche_procurement_purchase_evidence
        WHERE request_id = v_r1 AND uploaded_by = v_shop) = 1, v_res::text);
    v_res := public.marche_shopper_attach_evidence(jsonb_build_object(
      'request_id', v_r1, 'storage_path', v_r1::text || '/receipt.jpg'));
    r := r || public._qa_s13_ok('N4R7.H4 duplicate evidence attach does not duplicate rows',
      (SELECT count(*) FROM public.marche_procurement_purchase_evidence WHERE request_id = v_r1) = 1, NULL);

    SELECT count(*) INTO v_obs0 FROM public.marche_procurement_price_observations
      WHERE source_kind = 'procurement';
    v_res := public.marche_shopper_submit_purchase(jsonb_build_object('request_id', v_r1));
    r := r || public._qa_s13_ok('N4R7.H5 purchase verified with server-computed real spend',
      v_res->>'state'='purchase_verified' AND (v_res->>'verified_spend_gnf')::bigint = 30000, v_res::text);
    r := r || public._qa_s13_ok('N4R7.H6 verification is server-timestamped',
      v_res->>'purchase_verified_at' IS NOT NULL, NULL);
    v_res := public.marche_shopper_submit_purchase(jsonb_build_object('request_id', v_r1));
    r := r || public._qa_s13_ok('N4R7.H7 verification replay is idempotent',
      (v_res->>'replayed')::boolean, v_res::text);
    SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations
      WHERE source_kind='procurement' AND source_ref LIKE v_r1::text || ':%';
    r := r || public._qa_s13_ok('N4R7.H8 R8 substrate: truthful observations only for real purchases',
      v_n = 1, v_n::text);
    r := r || public._qa_s13_ok('N4R7.H9 substituted line emits no false catalog observation',
      NOT EXISTS (SELECT 1 FROM public.marche_procurement_price_observations
        WHERE source_ref = v_r1::text || ':3'), NULL);
    r := r || public._qa_s13_ok('N4R7.H10 unavailable line emits no observation',
      NOT EXISTS (SELECT 1 FROM public.marche_procurement_price_observations
        WHERE source_ref = v_r1::text || ':2'), NULL);
    SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations
      WHERE source_kind='procurement' AND source_ref LIKE v_r1::text || ':%';
    r := r || public._qa_s13_ok('N4R7.H11 verification replay records no duplicate observation',
      v_n = 1, v_n::text);

    -- money must not have moved yet
    SELECT balance_gnf, held_gnf INTO v_bal1, v_held1
      FROM public.wallets WHERE owner_user_id = v_buy AND party_type='client';
    r := r || public._qa_s13_ok('N4R7.H12 no capture before delivery completion',
      v_held1 = 40000 AND v_bal1 = v_bal0, format('bal=%s held=%s', v_bal1, v_held1));

    -- ================= I. DELIVERY + SETTLEMENT =================
    v_res := public.marche_shopper_start_delivery(v_r1);
    r := r || public._qa_s13_ok('N4R7.I1 delivery starts on the certified mission rail',
      v_res->>'state'='delivering' AND (v_res->>'mission_id') IS NOT NULL, v_res::text);
    r := r || public._qa_s13_ok('N4R7.I2 the assigned shopper is the delivering courier',
      (SELECT courier_id FROM public.missions WHERE id = (v_res->>'mission_id')::uuid) = v_shop, NULL);
    v_j := public.marche_shopper_start_delivery(v_r1);
    r := r || public._qa_s13_ok('N4R7.I3 delivery replay creates no second mission',
      (v_j->>'replayed')::boolean AND v_j->>'mission_id' = v_res->>'mission_id', v_j::text);
    SELECT count(*) INTO v_n FROM public.missions WHERE customer_id = v_buy;
    r := r || public._qa_s13_ok('N4R7.I4 exactly one delivery mission exists for this basket', v_n = 1, v_n::text);

    v_res := public.marche_shopper_complete_delivery(v_r1);
    r := r || public._qa_s13_ok('N4R7.I5 completion reconciles procurement + delivery',
      v_res->>'state'='completed', v_res::text);
    r := r || public._qa_s13_ok('N4R7.I6 settlement captured the actual spend only',
      (v_res->'settlement'->>'captured_gnf')::bigint = 30000, (v_res->'settlement')::text);
    r := r || public._qa_s13_ok('N4R7.I7 unused authorization released',
      (v_res->'settlement'->>'released_gnf')::bigint = 10000, (v_res->'settlement')::text);
    SELECT balance_gnf, held_gnf INTO v_bal1, v_held1
      FROM public.wallets WHERE owner_user_id = v_buy AND party_type='client';
    r := r || public._qa_s13_ok('N4R7.I8 customer wallet debited exactly the real spend',
      v_bal1 = v_bal0 - 30000 AND v_held1 = 0, format('bal=%s held=%s', v_bal1, v_held1));
    v_j := public.marche_shopper_complete_delivery(v_r1);
    r := r || public._qa_s13_ok('N4R7.I9 completion replay is idempotent (no double capture)',
      (v_j->>'replayed')::boolean, v_j::text);
    SELECT balance_gnf INTO v_n FROM public.wallets WHERE owner_user_id = v_buy AND party_type='client';
    r := r || public._qa_s13_ok('N4R7.I10 replayed completion moved no additional money',
      v_n = v_bal1, v_n::text);
    r := r || public._qa_s13_ok('N4R7.I11 request is terminal/settled',
      (SELECT status FROM public.marche_procurement_requests WHERE id=v_r1) = 'settled', NULL);
    BEGIN v_res := public.marche_shopper_resolve_line(jsonb_build_object(
      'request_id', v_r1, 'line_no', 1, 'kind','acquired','actual_unit_price_gnf', 1000));
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R7.I12 a completed mission cannot be rewound',
      v_err = 'PROCUREMENT_ILLEGAL_TRANSITION', v_err);

    -- ================= J. OVER-CEILING BASKET =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_res := public.marche_procurement_authorize(jsonb_build_object(
      'client_request_id', gen_random_uuid(), 'ceiling_gnf', 10000,
      'lines', jsonb_build_array(
        jsonb_build_object('commodity_code','qa_r7_riz','variant_code','v1','option_code','o1','qty',1))));
    v_r2 := (v_res->>'id')::uuid;
    PERFORM public.marche_procurement_set_destination(jsonb_build_object(
      'request_id', v_r2, 'destination_address','Matam, Conakry'));
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_shop), true);
    PERFORM public.marche_shopper_claim(v_r2);
    PERFORM public.marche_shopper_arrive_market(v_r2, NULL);
    PERFORM public.marche_shopper_start_shopping(v_r2);
    PERFORM public.marche_shopper_resolve_line(jsonb_build_object(
      'request_id', v_r2, 'line_no', 1, 'kind','acquired', 'actual_unit_price_gnf', 25000));
    PERFORM public.marche_shopper_attach_evidence(jsonb_build_object(
      'request_id', v_r2, 'storage_path', v_r2::text || '/receipt.jpg'));
    SELECT balance_gnf, held_gnf INTO v_bal0, v_held0
      FROM public.wallets WHERE owner_user_id = v_buy AND party_type='client';
    v_res := public.marche_shopper_submit_purchase(jsonb_build_object('request_id', v_r2));
    r := r || public._qa_s13_ok('N4R7.J1 spend above the ceiling is refused, approval required',
      v_res->>'code' = 'PROCUREMENT_AUTHORIZATION_REQUIRED'
      AND (v_res->>'required_ceiling_gnf')::bigint = 25000, v_res::text);
    r := r || public._qa_s13_ok('N4R7.J2 over-ceiling attempt does not verify the purchase',
      (SELECT state FROM public.marche_procurement_missions WHERE request_id=v_r2) = 'shopping', NULL);
    SELECT balance_gnf, held_gnf INTO v_bal1, v_held1
      FROM public.wallets WHERE owner_user_id = v_buy AND party_type='client';
    r := r || public._qa_s13_ok('N4R7.J3 no overspend: wallet untouched by the refused purchase',
      v_bal1 = v_bal0 AND v_held1 = v_held0, format('%s/%s', v_bal1, v_held1));
    BEGIN v_res := public.marche_shopper_start_delivery(v_r2); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R7.J4 delivery blocked while purchase is unverified',
      v_err = 'PROCUREMENT_PURCHASE_VERIFICATION_REQUIRED', v_err);

    -- customer raises the ceiling through the sovereign R6.5 path only
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_shop), true);
    BEGIN v_res := public.marche_procurement_increase(jsonb_build_object(
      'request_id', v_r2, 'new_ceiling_gnf', 25000, 'client_request_id', gen_random_uuid()));
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R7.J5 shopper cannot raise the authorized ceiling',
      v_err = 'PROCUREMENT_NOT_AUTHORIZED', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_res := public.marche_procurement_increase(jsonb_build_object(
      'request_id', v_r2, 'new_ceiling_gnf', 25000, 'client_request_id', gen_random_uuid()));
    r := r || public._qa_s13_ok('N4R7.J6 customer extends authorization via the R6.5 authority path',
      (v_res->>'authorized_ceiling_gnf')::bigint = 25000, v_res::text);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_shop), true);
    v_res := public.marche_shopper_submit_purchase(jsonb_build_object('request_id', v_r2));
    r := r || public._qa_s13_ok('N4R7.J7 purchase verifies once authorization covers the spend',
      v_res->>'state' = 'purchase_verified', v_res::text);
    PERFORM public.marche_shopper_start_delivery(v_r2);
    v_res := public.marche_shopper_complete_delivery(v_r2);
    r := r || public._qa_s13_ok('N4R7.J8 exact-cap purchase captures all, releases nothing',
      (v_res->'settlement'->>'captured_gnf')::bigint = 25000
      AND (v_res->'settlement'->>'released_gnf')::bigint = 0, (v_res->'settlement')::text);

    -- ================= K. CROSS-ORDER / SPOOFING =================
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_shop2), true);
    BEGIN v_res := public.marche_shopper_submit_purchase(jsonb_build_object('request_id', v_r1));
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R7.K1 cross-order shopper mutation denied',
      v_err = 'PROCUREMENT_NOT_ASSIGNED_SHOPPER', v_err);
    BEGIN v_res := public.marche_procurement_mission_get(v_r1); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R7.K2 foreign shopper cannot read another mission',
      v_err = 'PROCUREMENT_NOT_AUTHORIZED', v_err);
    BEGIN v_res := public.marche_shopper_claim(gen_random_uuid()); v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R7.K3 forged basket id cannot be claimed',
      v_err = 'PROCUREMENT_NOT_FOUND', v_err);
    v_err := public._qa_r6_err('authenticated', v_shop,
      'SELECT 1 FROM public.marche_procurement_missions');
    r := r || public._qa_s13_ok('N4R7.K4 authenticated role has no direct mission table read',
      v_err <> 'OK', v_err);
    v_err := public._qa_r6_err('anon', NULL,
      'SELECT public.marche_shopper_available_baskets(5)');
    r := r || public._qa_s13_ok('N4R7.K5 anon cannot call the shopper queue', v_err <> 'OK', v_err);
    v_err := public._qa_r6_err('authenticated', v_buy,
      'UPDATE public.marche_procurement_missions SET state = ''completed''');
    r := r || public._qa_s13_ok('N4R7.K6 customer cannot author lifecycle state directly', v_err <> 'OK', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_shop), true);
    r := r || public._qa_s13_ok('N4R7.K7 shopper queue only lists unassigned authorized baskets',
      NOT (public.marche_shopper_available_baskets(50))::text LIKE '%'||v_r1::text||'%', NULL);

    -- ================= L. AUDIT TRAIL =================
    r := r || public._qa_s13_ok('N4R7.L1 mission event trail is append-only',
      (SELECT count(*) FROM public.marche_procurement_mission_events WHERE request_id = v_r1) >= 8, NULL);
    BEGIN UPDATE public.marche_procurement_mission_events SET event='tampered' WHERE request_id=v_r1;
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R7.L2 mission events cannot be rewritten',
      v_err = 'PROCUREMENT_MISSION_APPEND_ONLY', v_err);
    BEGIN UPDATE public.marche_procurement_proposals SET payload='{}'::jsonb WHERE request_id=v_r1;
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R7.L3 proposals are immutable once written',
      v_err = 'PROCUREMENT_PROPOSAL_IMMUTABLE', v_err);

    -- ================= M. LEDGER INTEGRITY =================
    SELECT count(*) INTO v_n FROM (
      SELECT j.id FROM public.ledger_journals j
       JOIN public.ledger_postings p ON p.journal_id = j.id
       GROUP BY j.id HAVING sum(p.amount_gnf) <> 0) z;
    r := r || public._qa_s13_ok('N4R7.M1 no imbalanced journal after the shopper rail', v_n = 0, v_n::text);
    SELECT COALESCE(sum(amount_gnf),0) INTO v_n FROM public.ledger_postings;
    r := r || public._qa_s13_ok('N4R7.M2 global ledger sum is zero', v_n = 0, v_n::text);
    SELECT COALESCE(sum(GREATEST(amount_gnf - captured_gnf - released_gnf,0)),0) INTO v_n
      FROM public.mission_financial_holds
     WHERE source_module = 'marche_procurement';
    r := r || public._qa_s13_ok('N4R7.M3 no dangling procurement hold after completion', v_n = 0, v_n::text);

    PERFORM set_config('request.jwt.claims', '', true);
    RAISE EXCEPTION 'QA_N4R7_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_N4R7_ROLLBACK' THEN
      r := r || public._qa_s13_ok('HARNESS_R7_UNEXPECTED_ABORT', false, SQLERRM);
    END IF;
  END;

  PERFORM set_config('request.jwt.claims', '', true);
  SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;
  r := r || public._qa_s13_ok('N4R7.Z1 master wallet unchanged after fixture rollback',
    v_master1 = v_master0, v_master1::text);
  r := r || public._qa_s13_ok('N4R7.Z2 feature flags byte-identical after fixture rollback',
    v_flags1 = v_flags0, NULL);
  SELECT count(*) INTO v_n FROM public.marche_procurement_missions;
  r := r || public._qa_s13_ok('N4R7.Z3 zero shopper-mission fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_procurement_line_resolutions;
  r := r || public._qa_s13_ok('N4R7.Z4 zero line-resolution fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_procurement_proposals;
  r := r || public._qa_s13_ok('N4R7.Z5 zero proposal fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_procurement_purchase_evidence;
  r := r || public._qa_s13_ok('N4R7.Z6 zero evidence fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_staple_commodities WHERE code = 'qa_r7_riz';
  r := r || public._qa_s13_ok('N4R7.Z7 zero staples catalog fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.missions;
  r := r || public._qa_s13_ok('N4R7.Z8 zero mission fixture residue', v_n = v_ms0, v_n::text);

  RETURN public._qa_s13_summary(47, r);
END $$;

CREATE OR REPLACE FUNCTION public._qa_node4_marche_r7()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  RETURN public._qa_node4_marche_r7_fxcore();
END $$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r7() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._qa_node4_marche_r7_fxcore() FROM PUBLIC, anon, authenticated;
