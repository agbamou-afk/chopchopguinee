CREATE OR REPLACE FUNCTION public._qa_node4_marche_r65()
RETURNS jsonb LANGUAGE plpgsql SET search_path = public AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_err text; v_n bigint; v_json jsonb; v_j2 jsonb;
  v_adm uuid; v_buy uuid; v_buy2 uuid; v_buy3 uuid; v_other uuid; v_drv uuid; v_mer uuid;
  v_master0 bigint; v_master1 bigint; v_flags0 jsonb; v_flags1 jsonb;
  v_w0 bigint; v_wt0 bigint; v_lj0 bigint; v_lp0 bigint; v_mfh0 bigint;
  v_ms0 bigint; v_mp0 bigint; v_mo0 bigint; v_ml0 bigint;
  v_cat0 bigint; v_com0 bigint; v_var0 bigint; v_opt0 bigint;
  v_k1 uuid; v_k2 uuid; v_k3 uuid; v_k4 uuid; v_k5 uuid;
  v_r1 uuid; v_r3 uuid; v_r4 uuid; v_a1 uuid; v_a2 uuid;
  v_b1 jsonb; v_b2 jsonb; v_bal bigint; v_held bigint;
BEGIN
  SELECT balance_gnf INTO v_master0 FROM public.wallets WHERE party_type='master' LIMIT 1;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;
  SELECT count(*) INTO v_w0  FROM public.wallets;
  SELECT count(*) INTO v_wt0 FROM public.wallet_transactions;
  SELECT count(*) INTO v_lj0 FROM public.ledger_journals;
  SELECT count(*) INTO v_lp0 FROM public.ledger_postings;
  SELECT count(*) INTO v_mfh0 FROM public.mission_financial_holds;
  SELECT count(*) INTO v_ms0 FROM public.missions;
  SELECT count(*) INTO v_mp0 FROM public.merchant_payables;
  SELECT count(*) INTO v_mo0 FROM public.marche_orders;
  SELECT count(*) INTO v_ml0 FROM public.marketplace_listings;
  SELECT count(*) INTO v_cat0 FROM public.marche_staple_categories;
  SELECT count(*) INTO v_com0 FROM public.marche_staple_commodities;
  SELECT count(*) INTO v_var0 FROM public.marche_staple_variants;
  SELECT count(*) INTO v_opt0 FROM public.marche_staple_purchase_options;

  -- ============== A. STRUCTURAL / SECURITY LAW ==============
  r := r || public._qa_s13_ok('N4R65.A1 procurement request table exists',
        to_regclass('public.marche_procurement_requests') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N4R65.A2 immutable basket line table exists',
        to_regclass('public.marche_procurement_request_items') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N4R65.A3 append-only authorization table exists',
        to_regclass('public.marche_procurement_authorizations') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N4R65.A4 append-only event table exists',
        to_regclass('public.marche_procurement_events') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N4R65.A5 real observation source table exists',
        to_regclass('public.marche_procurement_price_observations') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N4R65.A6 procurement rail carries no merchant/listing coupling column',
        NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
          AND table_name LIKE 'marche_procurement%'
          AND column_name IN ('listing_id','store_id','merchant_store_id','merchant_user_id','offer_id','seller_id')), NULL);
  r := r || public._qa_s13_ok('N4R65.A7 procurement rail has no FK to marketplace_listings or merchant_stores',
        NOT EXISTS (SELECT 1 FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid
          WHERE t.relname LIKE 'marche_procurement%' AND c.contype='f'
            AND c.confrelid IN ('public.marketplace_listings'::regclass,'public.merchant_stores'::regclass)), NULL);
  r := r || public._qa_s13_ok('N4R65.A8 basket lines are bound to the R6 staples catalog',
        (SELECT count(*) FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid
          WHERE t.relname='marche_procurement_request_items' AND c.contype='f'
            AND c.confrelid IN ('public.marche_staple_commodities'::regclass,
                                'public.marche_staple_variants'::regclass,
                                'public.marche_staple_purchase_options'::regclass)) = 3, NULL);
  r := r || public._qa_s13_ok('N4R65.A9 no merchant fee / payable / delivery fee column on the procurement rail',
        NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
          AND table_name LIKE 'marche_procurement%'
          AND (column_name LIKE '%fee%' OR column_name LIKE '%payable%'
               OR column_name LIKE '%commission%' OR column_name LIKE '%payout%'
               OR column_name LIKE '%delivery%' OR column_name LIKE '%eta%')), NULL);
  r := r || public._qa_s13_ok('N4R65.A10 all five procurement tables have RLS enabled with zero policies',
        (SELECT bool_and(relrowsecurity) FROM pg_class WHERE oid IN (
           'public.marche_procurement_requests'::regclass,'public.marche_procurement_request_items'::regclass,
           'public.marche_procurement_authorizations'::regclass,'public.marche_procurement_events'::regclass,
           'public.marche_procurement_price_observations'::regclass))
        AND (SELECT count(*) FROM pg_policies WHERE tablename LIKE 'marche_procurement%') = 0, NULL);
  SELECT count(*) INTO v_n FROM information_schema.role_table_grants
   WHERE table_schema='public' AND table_name LIKE 'marche_procurement%' AND grantee IN ('anon','authenticated');
  r := r || public._qa_s13_ok('N4R65.A11 zero direct anon/authenticated grants on procurement tables', v_n = 0, v_n::text);
  r := r || public._qa_s13_ok('N4R65.A12 client roles cannot read the request table directly',
        NOT has_table_privilege('anon','public.marche_procurement_requests','SELECT')
    AND NOT has_table_privilege('authenticated','public.marche_procurement_requests','SELECT'), NULL);
  r := r || public._qa_s13_ok('N4R65.A13 client roles cannot write basket lines directly',
        NOT has_table_privilege('authenticated','public.marche_procurement_request_items','INSERT')
    AND NOT has_table_privilege('authenticated','public.marche_procurement_request_items','UPDATE'), NULL);
  r := r || public._qa_s13_ok('N4R65.A14 client roles cannot write authorizations directly',
        NOT has_table_privilege('authenticated','public.marche_procurement_authorizations','INSERT')
    AND NOT has_table_privilege('anon','public.marche_procurement_authorizations','SELECT'), NULL);
  r := r || public._qa_s13_ok('N4R65.A15 client roles cannot write price observations directly',
        NOT has_table_privilege('authenticated','public.marche_procurement_price_observations','INSERT')
    AND NOT has_table_privilege('anon','public.marche_procurement_price_observations','SELECT'), NULL);
  r := r || public._qa_s13_ok('N4R65.A16 customer RPC surface exists and is security definer',
        (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace AND prosecdef
          AND proname IN ('marche_procurement_quote','marche_procurement_authorize',
                          'marche_procurement_increase','marche_procurement_cancel',
                          'marche_procurement_get','marche_procurement_list')) = 6, NULL);
  r := r || public._qa_s13_ok('N4R65.A17 authenticated may execute exactly the sanctioned customer RPCs',
        has_function_privilege('authenticated','public.marche_procurement_quote(jsonb)','EXECUTE')
    AND has_function_privilege('authenticated','public.marche_procurement_authorize(jsonb)','EXECUTE')
    AND has_function_privilege('authenticated','public.marche_procurement_increase(jsonb)','EXECUTE')
    AND has_function_privilege('authenticated','public.marche_procurement_cancel(uuid,text)','EXECUTE')
    AND has_function_privilege('authenticated','public.marche_procurement_get(uuid)','EXECUTE')
    AND has_function_privilege('authenticated','public.marche_procurement_list(integer)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R65.A18 anon may execute NO procurement RPC at all',
        NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace='public'::regnamespace
          AND p.proname LIKE '%procurement%' AND has_function_privilege('anon', p.oid, 'EXECUTE')), NULL);
  r := r || public._qa_s13_ok('N4R65.A19 settlement primitive is NOT executable by authenticated',
        NOT has_function_privilege('authenticated','public.marche_procurement_settle_internal(uuid,bigint,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R65.A20 settlement primitive IS executable by the service context',
        has_function_privilege('service_role','public.marche_procurement_settle_internal(uuid,bigint,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R65.A21 internal money adapters are not client-callable',
        NOT has_function_privilege('authenticated','public._marche_procurement_capture_internal(uuid,bigint,uuid)','EXECUTE')
    AND NOT has_function_privilege('authenticated','public._marche_procurement_release_internal(uuid,text,uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R65.A22 internal estimate/policy primitives are not client-callable',
        NOT has_function_privilege('authenticated','public._marche_procurement_policy()','EXECUTE')
    AND NOT has_function_privilege('authenticated','public._marche_procurement_resolve(jsonb)','EXECUTE')
    AND NOT has_function_privilege('authenticated','public._marche_procurement_option_estimate(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R65.A23 every R6.5 function pins search_path=public',
        NOT EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace
          AND proname LIKE '%procurement%'
          AND NOT (COALESCE(array_to_string(proconfig,','),'') LIKE '%search_path=public%')), NULL);
  r := r || public._qa_s13_ok('N4R65.A24 anon still cannot execute has_role (Repas R8 P15.5 preserved)',
        NOT has_function_privilege('anon','public.has_role(uuid,app_role)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R65.A25 procurement float ledger account is registered as a liability',
        EXISTS (SELECT 1 FROM public.ledger_accounts WHERE code='L_PROCUREMENT_FLOAT' AND kind='liability'), NULL);
  r := r || public._qa_s13_ok('N4R65.A26 R6.5 defines no parallel wallet or hold table',
        to_regclass('public.marche_procurement_wallets') IS NULL
    AND to_regclass('public.marche_procurement_holds') IS NULL
    AND to_regclass('public.marche_procurement_ledger') IS NULL, NULL);
  r := r || public._qa_s13_ok('N4R65.A27 append-only triggers installed on lines, events and observations',
        (SELECT count(*) FROM pg_trigger WHERE tgname IN
          ('trg_mpri_append_only','trg_mpe_append_only','trg_mppo_append_only')) = 3, NULL);
  r := r || public._qa_s13_ok('N4R65.A28 immutability triggers installed on request and authorization',
        (SELECT count(*) FROM pg_trigger WHERE tgname IN ('trg_mpr_immutable','trg_mpa_immutable')) = 2, NULL);
  r := r || public._qa_s13_ok('N4R65.A29 ceiling, actual spend and estimate coherence are constrained in the schema',
        (SELECT count(*) FROM pg_constraint WHERE conname IN
          ('mpr_ceiling_chk','mpr_actual_chk','mpr_estimate_coherence_chk','mpri_estimate_coherence_chk')) = 4, NULL);
  r := r || public._qa_s13_ok('N4R65.A30 R1.5 merchant supply doctrine untouched',
        (SELECT pg_get_viewdef('public.v_marche_listing_truth'::regclass)) LIKE '%MERCHANT_STORE_REQUIRED%', NULL);
  r := r || public._qa_s13_ok('N4R65.A31 R6 catalog still exposes no price column',
        NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
          AND table_name LIKE 'marche_staple%' AND (column_name LIKE '%price%' OR column_name LIKE '%gnf%')), NULL);
  -- ---- corrected law: no invented fallback price / floor ----
  r := r || public._qa_s13_ok('N4R65.A32 the policy exposes NO invented minimum basket floor',
        NOT (public._marche_procurement_policy() ? 'min_ceiling_gnf'),
        public._marche_procurement_policy()::text);
  r := r || public._qa_s13_ok('N4R65.A33 customer_declared_ceiling is no longer a legal authorization basis',
        (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname='mpr_estimate_basis_chk')
          NOT LIKE '%customer_declared_ceiling%', NULL);
  r := r || public._qa_s13_ok('N4R65.A34 the schema forbids storing an insufficient-data request',
        (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname='mpr_estimate_status_chk')
          NOT LIKE '%insufficient_data%', NULL);
  r := r || public._qa_s13_ok('N4R65.A35 the schema forbids a ceiling below the frozen estimate',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conname='mpr_ceiling_covers_estimate_chk'), NULL);
  r := r || public._qa_s13_ok('N4R65.A36 the schema forbids a priceless frozen basket line',
        (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname='mpri_estimate_source_chk')
          NOT LIKE '%insufficient_data%', NULL);
  r := r || public._qa_s13_ok('N4R65.A37 no procurement code path mentions customer_declared_ceiling',
        NOT EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace
          AND proname LIKE '%procurement%' AND prosrc LIKE '%customer_declared_ceiling%'), NULL);
  -- ---- corrected law: finance reuse, no parallel capture/release ----
  r := r || public._qa_s13_ok('N4R65.A38 generic customer-hold capture/release primitives exist',
        (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace AND prosecdef
          AND proname IN ('_customer_hold_capture_internal','_customer_hold_release_internal')) = 2, NULL);
  r := r || public._qa_s13_ok('N4R65.A39 the generic money primitives are not client-callable',
        NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace='public'::regnamespace
          AND p.proname IN ('_customer_hold_capture_internal','_customer_hold_release_internal')
          AND (has_function_privilege('anon',p.oid,'EXECUTE') OR has_function_privilege('authenticated',p.oid,'EXECUTE'))), NULL);
  r := r || public._qa_s13_ok('N4R65.A40 the procurement capture adapter mutates no wallet itself',
        (SELECT prosrc FROM pg_proc WHERE proname='_marche_procurement_capture_internal')
          NOT LIKE '%UPDATE public.wallets%', NULL);
  r := r || public._qa_s13_ok('N4R65.A41 the procurement release adapter mutates no wallet itself',
        (SELECT prosrc FROM pg_proc WHERE proname='_marche_procurement_release_internal')
          NOT LIKE '%UPDATE public.wallets%', NULL);
  r := r || public._qa_s13_ok('N4R65.A42 the procurement adapters post no ledger journal themselves',
        (SELECT count(*) FROM pg_proc WHERE proname IN
           ('_marche_procurement_capture_internal','_marche_procurement_release_internal')
          AND prosrc LIKE '%_ledger_post%') = 0, NULL);
  r := r || public._qa_s13_ok('N4R65.A43 the procurement adapters delegate to the shared primitives',
        (SELECT count(*) FROM pg_proc WHERE proname IN
           ('_marche_procurement_capture_internal','_marche_procurement_release_internal')
          AND prosrc LIKE '%_customer_hold_%_internal%') = 2, NULL);
  r := r || public._qa_s13_ok('N4R65.A44 the hold is placed by the canonical Slice 13 hold primitive',
        (SELECT prosrc FROM pg_proc WHERE proname='marche_procurement_authorize')
          LIKE '%chop_pay_customer_hold_place%', NULL);
  r := r || public._qa_s13_ok('N4R65.A45 the shared release primitive restores funds to the canonical Chop Pay account',
        (SELECT prosrc FROM pg_proc WHERE proname='_customer_hold_release_internal')
          LIKE '%L_CUSTOMER_CHOPPAY%', NULL);
  r := r || public._qa_s13_ok('N4R65.A46 the shared capture primitive consumes the canonical customer hold account',
        (SELECT prosrc FROM pg_proc WHERE proname='_customer_hold_capture_internal')
          LIKE '%L_CUSTOMER_HOLD%', NULL);

  -- ============== rollback-safe runtime scope ==============
  BEGIN
    v_adm := gen_random_uuid(); v_buy := gen_random_uuid(); v_buy2 := gen_random_uuid();
    v_buy3 := gen_random_uuid(); v_other := gen_random_uuid();
    v_drv := gen_random_uuid(); v_mer := gen_random_uuid();
    PERFORM public._qa_s13_user(v_adm,'r65adm');  PERFORM public._qa_s13_user(v_buy,'r65buy');
    PERFORM public._qa_s13_user(v_buy2,'r65buy2'); PERFORM public._qa_s13_user(v_buy3,'r65buy3');
    PERFORM public._qa_s13_user(v_other,'r65oth'); PERFORM public._qa_s13_user(v_drv,'r65drv');
    PERFORM public._qa_s13_user(v_mer,'r65mer');
    INSERT INTO public.admin_users(user_id, admin_role, status) VALUES (v_adm,'god_admin','active');
    INSERT INTO public.user_roles(user_id, role) VALUES (v_drv,'driver'), (v_mer,'merchant');
    PERFORM public._qa_s13_wallet(v_buy ,'client', 5000000, 0);
    PERFORM public._qa_s13_wallet(v_buy2,'client', 1000, 0);
    PERFORM public._qa_s13_wallet(v_buy3,'client', 500000, 0);
    PERFORM public._qa_s13_wallet(v_other,'client', 100000, 0);

    v_b1 := jsonb_build_array(jsonb_build_object('commodity_code','rice','variant_code','local','option_code','kg','qty',4));
    v_b2 := jsonb_build_array(
      jsonb_build_object('commodity_code','rice','variant_code','local','option_code','kg','qty',4),
      jsonb_build_object('commodity_code','cassava_leaf','variant_code','general','option_code','botte','qty',2));

    -- ============== B. HONEST "NO DATA" QUOTE ==============
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_json := public.marche_procurement_quote(jsonb_build_object('lines', v_b1));
    r := r || public._qa_s13_ok('N4R65.B1 with zero observations the estimate is insufficient_data',
          v_json->>'estimate_status' = 'insufficient_data', v_json->>'estimate_status');
    r := r || public._qa_s13_ok('N4R65.B2 no subtotal is invented when data is missing',
          v_json->'estimated_subtotal_gnf' = 'null'::jsonb, v_json->>'estimated_subtotal_gnf');
    r := r || public._qa_s13_ok('N4R65.B3 no confidence is invented when data is missing',
          v_json->'estimate_confidence' = 'null'::jsonb, v_json->>'estimate_confidence');
    r := r || public._qa_s13_ok('N4R65.B4 no sample count is invented when data is missing',
          v_json->'estimate_sample_count' = 'null'::jsonb, v_json->>'estimate_sample_count');
    r := r || public._qa_s13_ok('N4R65.B5 the unavailability reason is machine-readable',
          v_json->>'estimate_unavailable_reason' = 'NO_RECENT_PROCUREMENT_OBSERVATIONS',
          v_json->>'estimate_unavailable_reason');
    r := r || public._qa_s13_ok('N4R65.B6 no customer-declared fallback basis is offered',
          v_json->'estimate_basis' = 'null'::jsonb, v_json->>'estimate_basis');
    r := r || public._qa_s13_ok('N4R65.B7 the non-guarantee wording is served by the server',
          v_json->>'disclaimer_fr' = 'Estimation — le prix réel au marché peut varier.', v_json->>'disclaimer_fr');
    r := r || public._qa_s13_ok('N4R65.B8 no invented minimum ceiling is published without an estimate',
          v_json->'min_ceiling_gnf' = 'null'::jsonb, v_json->>'min_ceiling_gnf');
    r := r || public._qa_s13_ok('N4R65.B9 the quote resolves R6 unit truth for the line',
          (SELECT l->>'sale_unit' = 'kg' AND l->>'normalization_kind' = 'exact'
             AND (l->>'normalized_quantity')::numeric = 4
             FROM jsonb_array_elements(v_json->'lines') l LIMIT 1), NULL);
    r := r || public._qa_s13_ok('N4R65.B10 the quote never leaks internal catalog primary keys',
          NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_json->'lines') l
                      WHERE l ? 'purchase_option_id' OR l ? 'commodity_id' OR l ? 'variant_id'), NULL);
    r := r || public._qa_s13_ok('N4R65.B11 the quote never mentions a merchant, store or delivery fee',
          NOT (v_json::text ILIKE '%merchant%' OR v_json::text ILIKE '%store%'
               OR v_json::text ILIKE '%delivery%' OR v_json::text ILIKE '%eta%'), NULL);
    r := r || public._qa_s13_ok('N4R65.B12 the quote reports the real evidence gap, not a guess',
          (SELECT (l->>'sample_count_in_window')::int = 0 AND (l->>'min_samples')::int = 3
             FROM jsonb_array_elements(v_json->'lines') l LIMIT 1),
          (SELECT l->>'sample_count_in_window' FROM jsonb_array_elements(v_json->'lines') l LIMIT 1));
    r := r || public._qa_s13_ok('N4R65.B13 the server explicitly forbids authorization without an estimate',
          (v_json->>'authorization_allowed')::boolean IS FALSE, v_json->>'authorization_allowed');

    -- ============== C. INPUT REFUSAL LAW ==============
    BEGIN PERFORM public.marche_procurement_quote(jsonb_build_object('lines','[]'::jsonb)); v_err:='NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.C1 empty basket refused', v_err LIKE '%PROCUREMENT_EMPTY_BASKET%', v_err);
    BEGIN PERFORM public.marche_procurement_quote(jsonb_build_object('lines',
      jsonb_build_array(jsonb_build_object('commodity_code','nope','variant_code','x','option_code','kg','qty',1))));
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.C2 unknown staple refused', v_err LIKE '%PROCUREMENT_UNKNOWN_STAPLE%', v_err);
    BEGIN PERFORM public.marche_procurement_quote(jsonb_build_object('lines',
      jsonb_build_array(jsonb_build_object('commodity_code','rice','variant_code','local','option_code','kg','qty',0))));
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.C3 zero quantity refused', v_err LIKE '%PROCUREMENT_QTY_INVALID%', v_err);
    BEGIN PERFORM public.marche_procurement_quote(jsonb_build_object('lines',
      jsonb_build_array(jsonb_build_object('commodity_code','rice','variant_code','local','option_code','kg','qty',-3))));
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.C4 negative quantity refused', v_err LIKE '%PROCUREMENT_QTY_INVALID%', v_err);
    BEGIN PERFORM public.marche_procurement_quote(jsonb_build_object('lines',
      jsonb_build_array(jsonb_build_object('commodity_code','rice','variant_code','local','option_code','kg','qty',500))));
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.C5 quantity above the R6 maximum refused',
          v_err LIKE '%PROCUREMENT_QTY_OUT_OF_RANGE%', v_err);
    BEGIN PERFORM public.marche_procurement_quote(jsonb_build_object('lines',
      jsonb_build_array(jsonb_build_object('commodity_code','rice','variant_code','local','option_code','kg','qty',1.5))));
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.C6 quantity off the R6 step grid refused',
          v_err LIKE '%PROCUREMENT_QTY_NOT_STEP_ALIGNED%', v_err);
    BEGIN PERFORM public.marche_procurement_quote(jsonb_build_object('lines',
      jsonb_build_array(jsonb_build_object('commodity_code','rice','variant_code','local','option_code','nope','qty',1))));
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.C7 unknown purchase option refused',
          v_err LIKE '%PROCUREMENT_UNKNOWN_STAPLE%', v_err);
    BEGIN PERFORM public.marche_procurement_quote(jsonb_build_object('lines',
      jsonb_build_array(jsonb_build_object('commodity_code','rice','variant_code','local','option_code','kg','qty',1,
                                           'listing_id', gen_random_uuid()))));
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.C8 a marketplace listing id cannot be smuggled into the procurement rail',
          v_err LIKE '%PROCUREMENT_MERCHANT_FIELD_FORBIDDEN%', v_err);
    BEGIN PERFORM public.marche_procurement_quote(jsonb_build_object('lines',
      jsonb_build_array(jsonb_build_object('commodity_code','rice','variant_code','local','option_code','kg','qty',1,
                                           'store_id', gen_random_uuid()))));
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.C9 a merchant store id cannot be smuggled into the procurement rail',
          v_err LIKE '%PROCUREMENT_MERCHANT_FIELD_FORBIDDEN%', v_err);
    BEGIN PERFORM public.marche_procurement_quote(jsonb_build_object('lines',
      jsonb_build_array(jsonb_build_object('commodity_code','rice','variant_code','local','option_code','kg','qty',1,
                                           'estimated_unit_price_gnf', 1))));
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.C10 the client cannot assert a unit price',
          v_err LIKE '%PROCUREMENT_CLIENT_FIELD_FORBIDDEN%', v_err);
    BEGIN PERFORM public.marche_procurement_quote(jsonb_build_object('lines',
      jsonb_build_array(jsonb_build_object('commodity_code','rice','variant_code','local','option_code','kg','qty',1,
                                           'estimate_confidence','high','estimate_sample_count',99))));
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.C11 the client cannot assert confidence or a sample count',
          v_err LIKE '%PROCUREMENT_CLIENT_FIELD_FORBIDDEN%', v_err);
    BEGIN PERFORM public.marche_procurement_quote(jsonb_build_object('lines',
      jsonb_build_array(jsonb_build_object('commodity_code','rice','variant_code','local','option_code','kg','qty',1,
                                           'actual_spend_gnf', 1))));
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.C12 the client cannot assert an actual spend',
          v_err LIKE '%PROCUREMENT_CLIENT_FIELD_FORBIDDEN%', v_err);
    BEGIN PERFORM public.marche_procurement_quote(jsonb_build_object('lines',
      (SELECT jsonb_agg(jsonb_build_object('commodity_code','rice','variant_code','local','option_code','kg','qty',1))
         FROM generate_series(1,30))));
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.C13 an oversized basket is refused',
          v_err LIKE '%PROCUREMENT_TOO_MANY_LINES%', v_err);
    PERFORM set_config('request.jwt.claims','',true);
    v_err := public._qa_r6_err('anon', NULL, $q$SELECT public.marche_procurement_quote('{"lines":[]}'::jsonb)$q$);
    r := r || public._qa_s13_ok('N4R65.C14 a signed-out visitor cannot quote a procurement basket',
          v_err LIKE '%permission denied%', v_err);

    -- ============== X. FAIL CLOSED WITHOUT TRUSTWORTHY DATA ==============
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    BEGIN PERFORM public.marche_procurement_authorize(jsonb_build_object(
      'client_request_id', gen_random_uuid(), 'ceiling_gnf', 500000, 'lines', v_b1));
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.X1 a basket without observations cannot be authorized at all',
          v_err LIKE '%PROCUREMENT_ESTIMATE_INSUFFICIENT_DATA%', v_err);
    SELECT count(*) INTO v_n FROM public.marche_procurement_requests;
    r := r || public._qa_s13_ok('N4R65.X2 the fail-closed refusal created no request', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.marche_procurement_request_items;
    r := r || public._qa_s13_ok('N4R65.X3 the fail-closed refusal froze no basket line', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.marche_procurement_authorizations;
    r := r || public._qa_s13_ok('N4R65.X4 the fail-closed refusal created no authorization', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds WHERE source_module='marche_procurement';
    r := r || public._qa_s13_ok('N4R65.X5 the fail-closed refusal placed no hold', v_n = 0, v_n::text);
    SELECT balance_gnf, held_gnf INTO v_bal, v_held FROM public.wallets
     WHERE owner_user_id=v_buy AND party_type='client';
    r := r || public._qa_s13_ok('N4R65.X6 the customer wallet is untouched by the fail-closed refusal',
          v_bal = 5000000 AND v_held = 0, format('%s/%s', v_bal, v_held));
    SELECT count(*) INTO v_n FROM public.ledger_journals WHERE source_module='marche_procurement';
    r := r || public._qa_s13_ok('N4R65.X7 the fail-closed refusal posted no journal', v_n = 0, v_n::text);

    -- ============== D. OBSERVED ESTIMATE LAW ==============
    v_err := public._qa_r6_err('authenticated', v_buy,
      $q$SELECT public.marche_procurement_observation_record('{"commodity_code":"rice","variant_code":"local","option_code":"kg","observed_unit_price_gnf":1}'::jsonb)$q$);
    r := r || public._qa_s13_ok('N4R65.D1 an ordinary customer cannot record a market price observation',
          v_err LIKE '%PROCUREMENT_OBSERVATION_FORBIDDEN%', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_adm), true);
    PERFORM public.marche_procurement_observation_record(jsonb_build_object(
      'commodity_code','rice','variant_code','local','option_code','kg','observed_unit_price_gnf',12000,'source_kind','field_agent'));
    PERFORM public.marche_procurement_observation_record(jsonb_build_object(
      'commodity_code','rice','variant_code','local','option_code','kg','observed_unit_price_gnf',12500,'source_kind','field_agent'));
    PERFORM public.marche_procurement_observation_record(jsonb_build_object(
      'commodity_code','rice','variant_code','local','option_code','kg','observed_unit_price_gnf',13000,'source_kind','field_agent'));
    PERFORM public.marche_procurement_observation_record(jsonb_build_object(
      'commodity_code','rice','variant_code','local','option_code','kg','observed_unit_price_gnf',13500,'source_kind','ops_survey'));
    PERFORM public.marche_procurement_observation_record(jsonb_build_object(
      'commodity_code','rice','variant_code','local','option_code','kg','observed_unit_price_gnf',14000,'source_kind','ops_survey'));
    PERFORM public.marche_procurement_observation_record(jsonb_build_object(
      'commodity_code','cooking_oil','variant_code','general','option_code','litre','observed_unit_price_gnf',20000));
    PERFORM public.marche_procurement_observation_record(jsonb_build_object(
      'commodity_code','cooking_oil','variant_code','general','option_code','litre','observed_unit_price_gnf',21000));
    BEGIN PERFORM public.marche_procurement_observation_record(jsonb_build_object(
      'commodity_code','rice','variant_code','local','option_code','kg','observed_unit_price_gnf',0));
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.D2 a zero observed price is refused',
          v_err LIKE '%PROCUREMENT_OBSERVATION_PRICE_INVALID%', v_err);
    SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations;
    r := r || public._qa_s13_ok('N4R65.D3 exactly seven honest observations were recorded', v_n = 7, v_n::text);
    BEGIN UPDATE public.marche_procurement_price_observations SET observed_unit_price_gnf = 1;
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.D4 observations are append-only',
          v_err LIKE '%PROCUREMENT_APPEND_ONLY%', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_json := public.marche_procurement_quote(jsonb_build_object('lines', v_b1));
    r := r || public._qa_s13_ok('N4R65.D5 with enough recent observations the estimate becomes available',
          v_json->>'estimate_status' = 'available', v_json->>'estimate_status');
    r := r || public._qa_s13_ok('N4R65.D6 the estimate is the observed median, not an invention',
          (SELECT (l->>'estimated_unit_price_gnf')::bigint = 13000
             FROM jsonb_array_elements(v_json->'lines') l LIMIT 1),
          (SELECT l->>'estimated_unit_price_gnf' FROM jsonb_array_elements(v_json->'lines') l LIMIT 1));
    r := r || public._qa_s13_ok('N4R65.D7 the line total is 13000 x 4 = 52000',
          (SELECT (l->>'estimated_line_total_gnf')::bigint = 52000
             FROM jsonb_array_elements(v_json->'lines') l LIMIT 1), NULL);
    r := r || public._qa_s13_ok('N4R65.D8 the basket subtotal is server-derived at 52000',
          (v_json->>'estimated_subtotal_gnf')::bigint = 52000, v_json->>'estimated_subtotal_gnf');
    r := r || public._qa_s13_ok('N4R65.D9 the sample count is the real number of observations',
          (v_json->>'estimate_sample_count')::int = 5, v_json->>'estimate_sample_count');
    r := r || public._qa_s13_ok('N4R65.D10 five fresh samples produce medium confidence, not high',
          v_json->>'estimate_confidence' = 'medium', v_json->>'estimate_confidence');
    r := r || public._qa_s13_ok('N4R65.D11 freshness is reported in hours and is near zero',
          (v_json->>'estimate_freshness_hours')::numeric < 1, v_json->>'estimate_freshness_hours');
    r := r || public._qa_s13_ok('N4R65.D12 the minimum ceiling is exactly the estimated subtotal',
          (v_json->>'min_ceiling_gnf')::bigint = 52000, v_json->>'min_ceiling_gnf');
    r := r || public._qa_s13_ok('N4R65.D13 authorization is unlocked only once evidence exists',
          (v_json->>'authorization_allowed')::boolean IS TRUE, v_json->>'authorization_allowed');
    v_j2 := public.marche_procurement_quote(jsonb_build_object('lines',
      jsonb_build_array(jsonb_build_object('commodity_code','cooking_oil','variant_code','general','option_code','litre','qty',2))));
    r := r || public._qa_s13_ok('N4R65.D14 two observations are below the evidence gate',
          v_j2->>'estimate_status' = 'insufficient_data', v_j2->>'estimate_status');
    r := r || public._qa_s13_ok('N4R65.D15 the near-miss line reports two real samples against a minimum of three',
          (SELECT (l->>'sample_count_in_window')::int = 2 AND (l->>'min_samples')::int = 3
             FROM jsonb_array_elements(v_j2->'lines') l LIMIT 1),
          (SELECT l->>'sample_count_in_window' FROM jsonb_array_elements(v_j2->'lines') l LIMIT 1));
    v_j2 := public.marche_procurement_quote(jsonb_build_object('lines', v_b2));
    r := r || public._qa_s13_ok('N4R65.D16 one unpriced line makes the whole basket insufficient_data',
          v_j2->>'estimate_status' = 'insufficient_data', v_j2->>'estimate_status');
    r := r || public._qa_s13_ok('N4R65.D17 the priced line keeps its honest provenance inside a mixed basket',
          (SELECT count(*) FROM jsonb_array_elements(v_j2->'lines') l
            WHERE l->>'estimate_source' = 'observed_procurement') = 1, NULL);
    r := r || public._qa_s13_ok('N4R65.D18 the unpriced line is explicitly marked insufficient_data',
          (SELECT count(*) FROM jsonb_array_elements(v_j2->'lines') l
            WHERE l->>'estimate_source' = 'insufficient_data') = 1, NULL);
    BEGIN PERFORM public.marche_procurement_authorize(jsonb_build_object(
      'client_request_id', gen_random_uuid(), 'ceiling_gnf', 500000, 'lines', v_b2));
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.D19 a mixed basket with one unpriced line still fails closed',
          v_err LIKE '%PROCUREMENT_ESTIMATE_INSUFFICIENT_DATA%', v_err);
    SELECT count(*) INTO v_n FROM public.marche_procurement_requests;
    r := r || public._qa_s13_ok('N4R65.D20 the mixed-basket refusal created nothing', v_n = 0, v_n::text);

    -- ============== E. AUTHORIZATION + CHOP PAY HOLD ==============
    v_k1 := gen_random_uuid();
    BEGIN PERFORM public.marche_procurement_authorize(jsonb_build_object(
      'client_request_id', v_k1, 'ceiling_gnf', 50000, 'lines', v_b1));
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.E1 a ceiling below the server estimate is refused',
          v_err LIKE '%PROCUREMENT_CEILING_BELOW_ESTIMATE%', v_err);
    BEGIN PERFORM public.marche_procurement_authorize(jsonb_build_object(
      'client_request_id', v_k1, 'ceiling_gnf', -60000, 'lines', v_b1));
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.E2 a negative ceiling is refused',
          v_err LIKE '%PROCUREMENT_CEILING_INVALID%', v_err);
    BEGIN PERFORM public.marche_procurement_authorize(jsonb_build_object(
      'client_request_id', v_k1, 'ceiling_gnf', 999999999999, 'lines', v_b1));
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.E3 an absurd ceiling is refused',
          v_err LIKE '%PROCUREMENT_CEILING_ABOVE_MAXIMUM%', v_err);
    BEGIN PERFORM public.marche_procurement_authorize(jsonb_build_object(
      'ceiling_gnf', 60000, 'lines', v_b1));
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.E4 a missing idempotency key is refused',
          v_err LIKE '%PROCUREMENT_REQUEST_KEY_REQUIRED%', v_err);
    SELECT count(*) INTO v_n FROM public.marche_procurement_requests;
    r := r || public._qa_s13_ok('N4R65.E5 no refused attempt created a request row', v_n = 0, v_n::text);

    v_json := public.marche_procurement_authorize(jsonb_build_object(
      'client_request_id', v_k1, 'ceiling_gnf', 60000, 'lines', v_b1));
    v_r1 := (v_json->>'id')::uuid;
    r := r || public._qa_s13_ok('N4R65.E6 the basket is authorized', v_json->>'status' = 'authorized', v_json->>'status');
    r := r || public._qa_s13_ok('N4R65.E7 the authorized ceiling is exactly what the customer approved',
          (v_json->>'authorized_ceiling_gnf')::bigint = 60000, v_json->>'authorized_ceiling_gnf');
    r := r || public._qa_s13_ok('N4R65.E8 the frozen estimate is the observed one',
          v_json->>'estimate_status' = 'available'
      AND v_json->>'estimate_basis' = 'observed_procurement'
      AND (v_json->>'estimated_subtotal_gnf')::bigint = 52000
      AND (v_json->>'estimate_sample_count')::int = 5, v_json->>'estimated_subtotal_gnf');
    r := r || public._qa_s13_ok('N4R65.E9 actual spend stays NULL until settlement',
          v_json->'actual_spend_gnf' = 'null'::jsonb, v_json->>'actual_spend_gnf');
    SELECT balance_gnf, held_gnf INTO v_bal, v_held FROM public.wallets
     WHERE owner_user_id = v_buy AND party_type='client';
    r := r || public._qa_s13_ok('N4R65.E10 the ceiling is held, not spent',
          v_bal = 5000000 AND v_held = 60000, format('bal=%s held=%s', v_bal, v_held));
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_module='marche_procurement' AND kind='customer_payment';
    r := r || public._qa_s13_ok('N4R65.E11 exactly one Slice 13 hold was placed', v_n = 1, v_n::text);
    SELECT id INTO v_a1 FROM public.marche_procurement_authorizations WHERE request_id = v_r1 AND seq = 1;
    SELECT amount_gnf INTO v_n FROM public.mission_financial_holds
     WHERE source_module='marche_procurement' AND source_id = v_a1 AND kind='customer_payment';
    r := r || public._qa_s13_ok('N4R65.E12 the hold amount equals the authorized ceiling', v_n = 60000, v_n::text);
    r := r || public._qa_s13_ok('N4R65.E13 the hold is the canonical customer_payment kind on the client party',
          EXISTS (SELECT 1 FROM public.mission_financial_holds WHERE source_id = v_a1
                  AND kind='customer_payment' AND party_type='client' AND party_user_id = v_buy
                  AND state='held' AND driver_user_id IS NULL), NULL);
    r := r || public._qa_s13_ok('N4R65.E14 a pending Chop Pay hold transaction exists',
          EXISTS (SELECT 1 FROM public.wallet_transactions
                  WHERE reference = 'cust-hold:marche_procurement:'||v_a1::text
                    AND type='hold' AND status='pending' AND amount_gnf = 60000), NULL);
    r := r || public._qa_s13_ok('N4R65.E15 the hold posted a balanced Slice 13 journal',
          (SELECT COALESCE(sum(p.amount_gnf),0) = 0 AND count(*) = 2
             FROM public.ledger_postings p JOIN public.ledger_journals j ON j.id=p.journal_id
            WHERE j.journal_key = 'cust-hold:marche_procurement:'||v_a1::text), NULL);
    SELECT count(*) INTO v_n FROM public.marche_procurement_request_items WHERE request_id = v_r1;
    r := r || public._qa_s13_ok('N4R65.E16 the basket line was frozen', v_n = 1, v_n::text);
    r := r || public._qa_s13_ok('N4R65.E17 the frozen line snapshots R6 identity, unit and normalization',
          EXISTS (SELECT 1 FROM public.marche_procurement_request_items
                  WHERE request_id = v_r1 AND commodity_code='rice' AND variant_code='local'
                    AND option_code='kg' AND category_code='cereals_starch' AND sale_unit='kg'
                    AND normalization_kind='exact' AND canonical_base_unit='kg'
                    AND requested_qty=4 AND normalized_quantity=4
                    AND estimated_unit_price_gnf=13000 AND estimated_line_total_gnf=52000
                    AND estimate_sample_count=5), NULL);
    r := r || public._qa_s13_ok('N4R65.E18 an authorization event was appended',
          EXISTS (SELECT 1 FROM public.marche_procurement_events
                  WHERE request_id = v_r1 AND event='authorized'), NULL);

    -- ============== F. IMMUTABILITY ==============
    BEGIN UPDATE public.marche_procurement_request_items SET requested_qty = 99 WHERE request_id = v_r1;
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.F1 a frozen basket line cannot be updated',
          v_err LIKE '%PROCUREMENT_APPEND_ONLY%', v_err);
    BEGIN DELETE FROM public.marche_procurement_request_items WHERE request_id = v_r1;
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.F2 a frozen basket line cannot be deleted',
          v_err LIKE '%PROCUREMENT_APPEND_ONLY%', v_err);
    BEGIN UPDATE public.marche_procurement_requests SET buyer_user_id = v_other WHERE id = v_r1;
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.F3 the buyer identity is immutable',
          v_err LIKE '%PROCUREMENT_REQUEST_IMMUTABLE%', v_err);
    BEGIN UPDATE public.marche_procurement_requests SET estimated_subtotal_gnf = 1 WHERE id = v_r1;
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.F4 the frozen estimate is immutable',
          v_err LIKE '%PROCUREMENT_REQUEST_IMMUTABLE%', v_err);
    BEGIN UPDATE public.marche_procurement_requests SET authorized_ceiling_gnf = 100 WHERE id = v_r1;
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.F5 the ceiling can never be lowered in place',
          v_err LIKE '%PROCUREMENT_CEILING_NOT_MONOTONIC%', v_err);
    BEGIN UPDATE public.marche_procurement_authorizations SET amount_gnf = 1 WHERE id = v_a1;
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.F6 an authorization increment is immutable',
          v_err LIKE '%PROCUREMENT_AUTHORIZATION_IMMUTABLE%', v_err);
    BEGIN DELETE FROM public.marche_procurement_events WHERE request_id = v_r1;
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.F7 the audit trail is append-only',
          v_err LIKE '%PROCUREMENT_APPEND_ONLY%', v_err);
    v_err := public._qa_r6_err('authenticated', v_buy,
      $q$INSERT INTO public.marche_procurement_requests(buyer_user_id,authorized_ceiling_gnf,estimate_status,estimate_basis,line_count,item_count,client_request_id,request_fingerprint) VALUES (auth.uid(),1,'available','observed_procurement',1,1,gen_random_uuid(),'x')$q$);
    r := r || public._qa_s13_ok('N4R65.F8 a customer cannot forge a request row directly',
          v_err LIKE '%permission denied%', v_err);

    -- ============== G. IDEMPOTENCY ==============
    v_json := public.marche_procurement_authorize(jsonb_build_object(
      'client_request_id', v_k1, 'ceiling_gnf', 60000, 'lines', v_b1));
    r := r || public._qa_s13_ok('N4R65.G1 the same key with the same basket replays',
          (v_json->>'replayed')::boolean IS TRUE, v_json->>'replayed');
    r := r || public._qa_s13_ok('N4R65.G2 the replay returns the same procurement request',
          (v_json->>'id')::uuid = v_r1, v_json->>'id');
    SELECT count(*) INTO v_n FROM public.marche_procurement_requests WHERE buyer_user_id = v_buy;
    r := r || public._qa_s13_ok('N4R65.G3 the replay created no second request', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds WHERE source_module='marche_procurement';
    r := r || public._qa_s13_ok('N4R65.G4 the replay placed no second hold', v_n = 1, v_n::text);
    SELECT held_gnf INTO v_held FROM public.wallets WHERE owner_user_id=v_buy AND party_type='client';
    r := r || public._qa_s13_ok('N4R65.G5 the replay did not double-hold the customer', v_held = 60000, v_held::text);
    BEGIN PERFORM public.marche_procurement_authorize(jsonb_build_object(
      'client_request_id', v_k1, 'ceiling_gnf', 80000, 'lines', v_b1));
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.G6 the same key with a different ceiling conflicts',
          v_err LIKE '%IDEMPOTENCY_CONFLICT%', v_err);
    BEGIN PERFORM public.marche_procurement_authorize(jsonb_build_object(
      'client_request_id', v_k1, 'ceiling_gnf', 60000, 'lines',
      jsonb_build_array(jsonb_build_object('commodity_code','rice','variant_code','local','option_code','kg','qty',3))));
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.G7 the same key with a different basket conflicts',
          v_err LIKE '%IDEMPOTENCY_CONFLICT%', v_err);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds WHERE source_module='marche_procurement';
    r := r || public._qa_s13_ok('N4R65.G8 a conflicting replay moved no money', v_n = 1, v_n::text);

    -- ============== H. INSUFFICIENT FUNDS FAILS CLOSED ==============
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy2), true);
    v_k2 := gen_random_uuid();
    BEGIN PERFORM public.marche_procurement_authorize(jsonb_build_object(
      'client_request_id', v_k2, 'ceiling_gnf', 60000, 'lines', v_b1));
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.H1 an underfunded customer is refused with the canonical finance error',
          v_err LIKE '%INSUFFICIENT_CUSTOMER_BALANCE%', v_err);
    SELECT count(*) INTO v_n FROM public.marche_procurement_requests WHERE buyer_user_id = v_buy2;
    r := r || public._qa_s13_ok('N4R65.H2 no half-created request survives the refusal', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.marche_procurement_authorizations a
      JOIN public.marche_procurement_requests q ON q.id=a.request_id WHERE q.buyer_user_id = v_buy2;
    r := r || public._qa_s13_ok('N4R65.H3 no half-created authorization survives the refusal', v_n = 0, v_n::text);
    SELECT balance_gnf, held_gnf INTO v_bal, v_held FROM public.wallets
     WHERE owner_user_id = v_buy2 AND party_type='client';
    r := r || public._qa_s13_ok('N4R65.H4 the underfunded wallet is untouched',
          v_bal = 1000 AND v_held = 0, format('%s/%s', v_bal, v_held));
    SELECT count(*) INTO v_n FROM public.mission_financial_holds WHERE source_module='marche_procurement';
    r := r || public._qa_s13_ok('N4R65.H5 no extra hold exists after the refusal', v_n = 1, v_n::text);

    -- ============== I. CEILING INCREASE LAW ==============
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_other), true);
    BEGIN PERFORM public.marche_procurement_increase(jsonb_build_object(
      'request_id', v_r1, 'client_request_id', gen_random_uuid(), 'new_ceiling_gnf', 100000));
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.I1 a third party cannot raise another customer''s ceiling',
          v_err LIKE '%PROCUREMENT_NOT_AUTHORIZED%', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    BEGIN PERFORM public.marche_procurement_increase(jsonb_build_object(
      'request_id', v_r1, 'client_request_id', gen_random_uuid(), 'new_ceiling_gnf', 55000));
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.I2 lowering the ceiling is refused',
          v_err LIKE '%PROCUREMENT_CEILING_NOT_MONOTONIC%', v_err);
    v_k3 := gen_random_uuid();
    v_json := public.marche_procurement_increase(jsonb_build_object(
      'request_id', v_r1, 'client_request_id', v_k3, 'new_ceiling_gnf', 100000));
    r := r || public._qa_s13_ok('N4R65.I3 the customer can raise their own ceiling',
          (v_json->>'authorized_ceiling_gnf')::bigint = 100000, v_json->>'authorized_ceiling_gnf');
    SELECT balance_gnf, held_gnf INTO v_bal, v_held FROM public.wallets
     WHERE owner_user_id = v_buy AND party_type='client';
    r := r || public._qa_s13_ok('N4R65.I4 only the incremental amount is additionally held',
          v_bal = 5000000 AND v_held = 100000, format('%s/%s', v_bal, v_held));
    SELECT count(*) INTO v_n FROM public.marche_procurement_authorizations WHERE request_id = v_r1;
    r := r || public._qa_s13_ok('N4R65.I5 the prior authorization is preserved as history', v_n = 2, v_n::text);
    r := r || public._qa_s13_ok('N4R65.I6 the increment records the exact ceiling transition',
          EXISTS (SELECT 1 FROM public.marche_procurement_authorizations
                  WHERE request_id=v_r1 AND seq=2 AND kind='increase' AND amount_gnf=40000
                    AND ceiling_before_gnf=60000 AND ceiling_after_gnf=100000 AND approved_by=v_buy), NULL);
    SELECT id INTO v_a2 FROM public.marche_procurement_authorizations WHERE request_id = v_r1 AND seq = 2;
    SELECT amount_gnf INTO v_n FROM public.mission_financial_holds
     WHERE source_module='marche_procurement' AND source_id = v_a2;
    r := r || public._qa_s13_ok('N4R65.I7 the incremental hold is exactly the delta', v_n = 40000, v_n::text);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds WHERE source_module='marche_procurement';
    r := r || public._qa_s13_ok('N4R65.I8 the initial hold was not replaced or duplicated', v_n = 2, v_n::text);
    v_json := public.marche_procurement_increase(jsonb_build_object(
      'request_id', v_r1, 'client_request_id', v_k3, 'new_ceiling_gnf', 100000));
    r := r || public._qa_s13_ok('N4R65.I9 replaying the increase is idempotent',
          (v_json->>'replayed')::boolean IS TRUE, v_json->>'replayed');
    SELECT count(*) INTO v_n FROM public.mission_financial_holds WHERE source_module='marche_procurement';
    r := r || public._qa_s13_ok('N4R65.I10 the increase replay placed no third hold', v_n = 2, v_n::text);
    BEGIN PERFORM public.marche_procurement_increase(jsonb_build_object(
      'request_id', v_r1, 'client_request_id', v_k3, 'new_ceiling_gnf', 120000));
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.I11 the same increase key with a different ceiling conflicts',
          v_err LIKE '%IDEMPOTENCY_CONFLICT%', v_err);
    SELECT held_gnf INTO v_held FROM public.wallets WHERE owner_user_id=v_buy AND party_type='client';
    r := r || public._qa_s13_ok('N4R65.I12 the conflicting increase held nothing extra', v_held = 100000, v_held::text);
    r := r || public._qa_s13_ok('N4R65.I13 a ceiling-increase event is appended',
          EXISTS (SELECT 1 FROM public.marche_procurement_events
                  WHERE request_id=v_r1 AND event='ceiling_increased'), NULL);

    -- ============== J. SETTLEMENT AUTHORITY ==============
    v_err := public._qa_r6_err('authenticated', v_buy,
      format($q$SELECT public.marche_procurement_settle_internal(%L::uuid, 1000, 'qa')$q$, v_r1));
    r := r || public._qa_s13_ok('N4R65.J1 the customer cannot settle their own actual spend',
          v_err LIKE '%permission denied%', v_err);
    v_err := public._qa_r6_err('authenticated', v_mer,
      format($q$SELECT public.marche_procurement_settle_internal(%L::uuid, 1000, 'qa')$q$, v_r1));
    r := r || public._qa_s13_ok('N4R65.J2 a merchant cannot settle a procurement basket',
          v_err LIKE '%permission denied%', v_err);
    v_err := public._qa_r6_err('authenticated', v_drv,
      format($q$SELECT public.marche_procurement_settle_internal(%L::uuid, 1000, 'qa')$q$, v_r1));
    r := r || public._qa_s13_ok('N4R65.J3 a driver/shopper cannot settle a procurement basket',
          v_err LIKE '%permission denied%', v_err);
    v_err := public._qa_r6_err('anon', NULL,
      format($q$SELECT public.marche_procurement_settle_internal(%L::uuid, 1000, 'qa')$q$, v_r1));
    r := r || public._qa_s13_ok('N4R65.J4 a signed-out visitor cannot settle a procurement basket',
          v_err LIKE '%permission denied%', v_err);
    v_err := public._qa_r6_err('authenticated', v_buy,
      format($q$SELECT public._customer_hold_capture_internal('marche_procurement', %L::uuid, 1000, 'x','y','L_PROCUREMENT_FLOAT', NULL, NULL, NULL, NULL, 'z')$q$, v_a1));
    r := r || public._qa_s13_ok('N4R65.J5 a customer cannot call the shared capture primitive',
          v_err LIKE '%permission denied%', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    BEGIN PERFORM public.marche_procurement_settle_internal(v_r1, 1000, 'qa');
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.J6 even with a customer JWT the settlement authority check refuses',
          v_err LIKE '%PROCUREMENT_SETTLEMENT_FORBIDDEN%', v_err);
    SELECT count(*) INTO v_n FROM public.marche_procurement_requests WHERE status='settled';
    r := r || public._qa_s13_ok('N4R65.J7 no refused settlement attempt changed any state', v_n = 0, v_n::text);

    -- ============== K. SPEND ABOVE CEILING ==============
    PERFORM set_config('request.jwt.claims','',true);
    v_json := public.marche_procurement_settle_internal(v_r1, 120000, 'qa-over');
    r := r || public._qa_s13_ok('N4R65.K1 spend above the ceiling returns approval_required',
          v_json->>'status' = 'approval_required', v_json->>'status');
    r := r || public._qa_s13_ok('N4R65.K2 the refusal carries the canonical machine-readable code',
          v_json->>'code' = 'PROCUREMENT_AUTHORIZATION_REQUIRED', v_json->>'code');
    r := r || public._qa_s13_ok('N4R65.K3 the required ceiling is stated to the caller',
          (v_json->>'required_ceiling_gnf')::bigint = 120000, v_json->>'required_ceiling_gnf');
    r := r || public._qa_s13_ok('N4R65.K4 nothing is captured when the ceiling would be exceeded',
          (v_json->>'captured_gnf')::bigint = 0 AND (v_json->>'released_gnf')::bigint = 0, NULL);
    SELECT balance_gnf, held_gnf INTO v_bal, v_held FROM public.wallets
     WHERE owner_user_id=v_buy AND party_type='client';
    r := r || public._qa_s13_ok('N4R65.K5 the customer wallet is untouched by the refusal',
          v_bal = 5000000 AND v_held = 100000, format('%s/%s', v_bal, v_held));
    SELECT count(*) INTO v_n FROM public.ledger_journals WHERE journal_key LIKE 'mproc-capture:%';
    r := r || public._qa_s13_ok('N4R65.K6 no capture journal was written', v_n = 0, v_n::text);
    SELECT status INTO v_err FROM public.marche_procurement_requests WHERE id = v_r1;
    r := r || public._qa_s13_ok('N4R65.K7 the request is still open, not settled', v_err = 'authorized', v_err);
    SELECT actual_spend_gnf INTO v_n FROM public.marche_procurement_requests WHERE id = v_r1;
    r := r || public._qa_s13_ok('N4R65.K8 no actual spend was recorded', v_n IS NULL, v_n::text);

    -- ============== L. SETTLE BELOW CEILING ==============
    v_json := public.marche_procurement_settle_internal(v_r1, 70000, 'qa-under');
    r := r || public._qa_s13_ok('N4R65.L1 the settlement succeeds', v_json->>'status' = 'settled', v_json->>'status');
    r := r || public._qa_s13_ok('N4R65.L2 exactly the actual spend is captured',
          (v_json->>'captured_gnf')::bigint = 70000, v_json->>'captured_gnf');
    r := r || public._qa_s13_ok('N4R65.L3 exactly the unused authorization is released',
          (v_json->>'released_gnf')::bigint = 30000, v_json->>'released_gnf');
    SELECT balance_gnf, held_gnf INTO v_bal, v_held FROM public.wallets
     WHERE owner_user_id=v_buy AND party_type='client';
    r := r || public._qa_s13_ok('N4R65.L4 the customer balance falls by exactly the actual spend',
          v_bal = 4930000, v_bal::text);
    r := r || public._qa_s13_ok('N4R65.L5 nothing remains held after settlement', v_held = 0, v_held::text);
    SELECT balance_gnf INTO v_n FROM public.wallets WHERE party_type='master';
    r := r || public._qa_s13_ok('N4R65.L6 the platform procurement float received exactly the actual spend',
          v_n = v_master0 + 70000, format('%s vs %s', v_n, v_master0 + 70000));
    SELECT COALESCE(sum(p.amount_gnf),0) INTO v_n FROM public.ledger_postings p
      JOIN public.ledger_journals j ON j.id=p.journal_id
     WHERE j.source_module='marche_procurement';
    r := r || public._qa_s13_ok('N4R65.L7 every procurement journal balances to zero', v_n = 0, v_n::text);
    SELECT COALESCE(-sum(p.amount_gnf),0) INTO v_n FROM public.ledger_postings p
     WHERE p.account_code = 'L_PROCUREMENT_FLOAT';
    r := r || public._qa_s13_ok('N4R65.L8 the procurement float ledger balance equals the actual spend',
          v_n = 70000, v_n::text);
    SELECT COALESCE(sum(p.amount_gnf),0) INTO v_n FROM public.ledger_postings p
      JOIN public.ledger_journals j ON j.id=p.journal_id
     WHERE j.action = 'capture_procurement_spend';
    r := r || public._qa_s13_ok('N4R65.L9 the capture postings net to zero', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.marche_procurement_authorizations
     WHERE request_id=v_r1 AND seq=1 AND captured_gnf=60000 AND released_gnf=0;
    r := r || public._qa_s13_ok('N4R65.L10 the first authorization is fully consumed', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.marche_procurement_authorizations
     WHERE request_id=v_r1 AND seq=2 AND captured_gnf=10000 AND released_gnf=30000;
    r := r || public._qa_s13_ok('N4R65.L11 the increment is partially consumed and the rest released', v_n = 1, v_n::text);
    SELECT count(*) INTO v_n FROM public.mission_financial_holds
     WHERE source_module='marche_procurement' AND state='held';
    r := r || public._qa_s13_ok('N4R65.L12 no Slice 13 hold is left open', v_n = 0, v_n::text);
    SELECT actual_spend_gnf INTO v_n FROM public.marche_procurement_requests WHERE id=v_r1;
    r := r || public._qa_s13_ok('N4R65.L13 the actual spend snapshot is frozen at 70000', v_n = 70000, v_n::text);
    r := r || public._qa_s13_ok('N4R65.L14 the settlement timestamp is recorded',
          (SELECT settled_at IS NOT NULL FROM public.marche_procurement_requests WHERE id=v_r1), NULL);
    BEGIN UPDATE public.marche_procurement_requests SET actual_spend_gnf = 1 WHERE id=v_r1;
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.L15 the actual spend snapshot is immutable',
          v_err LIKE '%PROCUREMENT_ACTUAL_SPEND_IMMUTABLE%', v_err);
    SELECT count(*) INTO v_n FROM public.marche_procurement_events WHERE request_id=v_r1 AND event='settled';
    r := r || public._qa_s13_ok('N4R65.L16 a settlement event is appended exactly once', v_n = 1, v_n::text);
    r := r || public._qa_s13_ok('N4R65.L17 the capture used the shared hold-consumption account',
          (SELECT count(*) FROM public.ledger_postings p JOIN public.ledger_journals j ON j.id=p.journal_id
            WHERE j.action='capture_procurement_spend' AND p.account_code='L_CUSTOMER_HOLD'
              AND p.amount_gnf > 0) = 2, NULL);
    r := r || public._qa_s13_ok('N4R65.L18 the release restored funds to the canonical Chop Pay account',
          (SELECT count(*) FROM public.ledger_postings p JOIN public.ledger_journals j ON j.id=p.journal_id
            WHERE j.action='release_procurement_authorization'
              AND p.account_code='L_CUSTOMER_CHOPPAY' AND p.amount_gnf = -30000) = 1, NULL);

    -- ============== M. SETTLEMENT REPLAY SAFETY ==============
    v_json := public.marche_procurement_settle_internal(v_r1, 70000, 'qa-replay');
    r := r || public._qa_s13_ok('N4R65.M1 replaying settlement is recognised',
          v_json->>'status' = 'already_settled', v_json->>'status');
    r := r || public._qa_s13_ok('N4R65.M2 the replay captures nothing',
          (v_json->>'captured_gnf')::bigint = 0, v_json->>'captured_gnf');
    r := r || public._qa_s13_ok('N4R65.M3 the replay releases nothing',
          (v_json->>'released_gnf')::bigint = 0, v_json->>'released_gnf');
    SELECT balance_gnf, held_gnf INTO v_bal, v_held FROM public.wallets
     WHERE owner_user_id=v_buy AND party_type='client';
    r := r || public._qa_s13_ok('N4R65.M4 the replay moved no money',
          v_bal = 4930000 AND v_held = 0, format('%s/%s', v_bal, v_held));
    SELECT balance_gnf INTO v_n FROM public.wallets WHERE party_type='master';
    r := r || public._qa_s13_ok('N4R65.M5 the platform float is unchanged by the replay',
          v_n = v_master0 + 70000, v_n::text);
    SELECT count(*) INTO v_n FROM public.marche_procurement_events WHERE request_id=v_r1 AND event='settled';
    r := r || public._qa_s13_ok('N4R65.M6 no second settlement event was appended', v_n = 1, v_n::text);
    BEGIN PERFORM public.marche_procurement_increase(jsonb_build_object(
      'request_id', v_r1, 'client_request_id', gen_random_uuid(), 'new_ceiling_gnf', 200000));
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.M7 a settled basket cannot be re-authorized',
          v_err LIKE '%PROCUREMENT_NOT_OPEN%' OR v_err LIKE '%PROCUREMENT_NOT_AUTHORIZED%', v_err);

    -- ============== N. SETTLE EXACTLY AT THE CEILING ==============
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy3), true);
    v_k4 := gen_random_uuid();
    v_json := public.marche_procurement_authorize(jsonb_build_object(
      'client_request_id', v_k4, 'ceiling_gnf', 52000, 'lines', v_b1));
    v_r3 := (v_json->>'id')::uuid;
    r := r || public._qa_s13_ok('N4R65.N1 a customer may authorize exactly the estimated subtotal',
          (v_json->>'authorized_ceiling_gnf')::bigint = 52000
      AND (v_json->>'estimated_subtotal_gnf')::bigint = 52000, v_json->>'authorized_ceiling_gnf');
    r := r || public._qa_s13_ok('N4R65.N2 the frozen basis is always the observed evidence',
          v_json->>'estimate_basis' = 'observed_procurement', v_json->>'estimate_basis');
    r := r || public._qa_s13_ok('N4R65.N3 every frozen line carries a real observed price',
          NOT EXISTS (SELECT 1 FROM public.marche_procurement_request_items
                      WHERE request_id=v_r3 AND estimated_unit_price_gnf IS NULL), NULL);
    PERFORM set_config('request.jwt.claims','',true);
    v_json := public.marche_procurement_settle_internal(v_r3, 52000, 'qa-exact');
    r := r || public._qa_s13_ok('N4R65.N4 spending exactly the ceiling captures the whole ceiling',
          (v_json->>'captured_gnf')::bigint = 52000, v_json->>'captured_gnf');
    r := r || public._qa_s13_ok('N4R65.N5 spending exactly the ceiling releases zero',
          (v_json->>'released_gnf')::bigint = 0, v_json->>'released_gnf');
    SELECT balance_gnf, held_gnf INTO v_bal, v_held FROM public.wallets
     WHERE owner_user_id=v_buy3 AND party_type='client';
    r := r || public._qa_s13_ok('N4R65.N6 the exact-ceiling customer paid exactly the ceiling',
          v_bal = 448000 AND v_held = 0, format('%s/%s', v_bal, v_held));

    -- ============== O. CANCELLATION BEFORE SPEND ==============
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_other), true);
    v_k5 := gen_random_uuid();
    v_json := public.marche_procurement_authorize(jsonb_build_object(
      'client_request_id', v_k5, 'ceiling_gnf', 60000, 'lines', v_b1));
    v_r4 := (v_json->>'id')::uuid;
    SELECT held_gnf INTO v_held FROM public.wallets WHERE owner_user_id=v_other AND party_type='client';
    r := r || public._qa_s13_ok('N4R65.O1 the cancellation fixture is authorized and held', v_held = 60000, v_held::text);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    BEGIN PERFORM public.marche_procurement_cancel(v_r4, 'qa'); v_err:='NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.O2 a third party cannot cancel another customer''s procurement',
          v_err LIKE '%PROCUREMENT_NOT_AUTHORIZED%', v_err);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_other), true);
    v_json := public.marche_procurement_cancel(v_r4, 'qa-cancel');
    r := r || public._qa_s13_ok('N4R65.O3 cancellation releases the full remaining authorization',
          (v_json->>'released_gnf')::bigint = 60000, v_json->>'released_gnf');
    SELECT balance_gnf, held_gnf INTO v_bal, v_held FROM public.wallets
     WHERE owner_user_id=v_other AND party_type='client';
    r := r || public._qa_s13_ok('N4R65.O4 the cancelled customer keeps every franc',
          v_bal = 100000 AND v_held = 0, format('%s/%s', v_bal, v_held));
    v_json := public.marche_procurement_cancel(v_r4, 'qa-cancel-again');
    r := r || public._qa_s13_ok('N4R65.O5 cancelling twice releases nothing more',
          (v_json->>'released_gnf')::bigint = 0, v_json->>'released_gnf');
    SELECT balance_gnf, held_gnf INTO v_bal, v_held FROM public.wallets
     WHERE owner_user_id=v_other AND party_type='client';
    r := r || public._qa_s13_ok('N4R65.O6 the double cancellation moved no money',
          v_bal = 100000 AND v_held = 0, format('%s/%s', v_bal, v_held));
    PERFORM set_config('request.jwt.claims','',true);
    BEGIN PERFORM public.marche_procurement_settle_internal(v_r4, 10000, 'qa');
      v_err:='NO_ERROR'; EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.O7 a cancelled procurement can never be settled',
          v_err LIKE '%PROCUREMENT_ALREADY_CANCELLED%', v_err);
    SELECT count(*) INTO v_n FROM public.marche_procurement_events WHERE request_id=v_r4 AND event='cancelled';
    r := r || public._qa_s13_ok('N4R65.O8 exactly one cancellation event is recorded', v_n = 1, v_n::text);

    -- ============== P. CROSS-USER READ LAW ==============
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_other), true);
    BEGIN PERFORM public.marche_procurement_get(v_r1); v_err:='NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.P1 a customer cannot read another customer''s procurement basket',
          v_err LIKE '%PROCUREMENT_NOT_AUTHORIZED%', v_err);
    v_json := public.marche_procurement_list(50);
    r := r || public._qa_s13_ok('N4R65.P2 the list only returns the caller''s own baskets',
          jsonb_array_length(v_json) = 1
      AND (v_json->0->>'id')::uuid = v_r4, jsonb_array_length(v_json)::text);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_json := public.marche_procurement_get(v_r1);
    r := r || public._qa_s13_ok('N4R65.P3 the owner can read their own basket',
          (v_json->>'id')::uuid = v_r1, NULL);
    r := r || public._qa_s13_ok('N4R65.P4 the owner payload never carries a merchant fee or payable',
          NOT (v_json::text ILIKE '%payable%' OR v_json::text ILIKE '%_fee%'), NULL);
    r := r || public._qa_s13_ok('N4R65.P5 the owner payload carries the non-guarantee wording',
          v_json->>'disclaimer_fr' = 'Estimation — le prix réel au marché peut varier.', NULL);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_adm), true);
    BEGIN v_json := public.marche_procurement_get(v_r1); v_err:='NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R65.P6 an admin may audit a procurement basket', v_err = 'NO_ERROR', v_err);

    -- ============== Q. FINANCIAL SEPARATION ==============
    SELECT count(*) INTO v_n FROM public.merchant_payables;
    r := r || public._qa_s13_ok('N4R65.Q1 no merchant payable was created by procurement', v_n = v_mp0, v_n::text);
    SELECT count(*) INTO v_n FROM public.missions;
    r := r || public._qa_s13_ok('N4R65.Q2 no mission was created by procurement', v_n = v_ms0, v_n::text);
    SELECT count(*) INTO v_n FROM public.marche_orders;
    r := r || public._qa_s13_ok('N4R65.Q3 no merchant Marché order was created by procurement', v_n = v_mo0, v_n::text);
    SELECT count(*) INTO v_n FROM public.marketplace_listings;
    r := r || public._qa_s13_ok('N4R65.Q4 the merchant supply population is untouched', v_n = v_ml0, v_n::text);
    SELECT count(*) INTO v_n FROM public.merchant_stores WHERE name ILIKE '%essentiel%' OR name ILIKE '%procurement%';
    r := r || public._qa_s13_ok('N4R65.Q5 no fake ChopChop store was invented', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.ledger_postings p JOIN public.ledger_journals j ON j.id=p.journal_id
     WHERE j.source_module='marche_procurement'
       AND p.account_code IN ('L_MERCHANT_PAYABLE','L_DRIVER_UNRESTRICTED','R_COMMISSION',
                              'R_TRANSACTION_FEE','R_DELIVERY_MARGIN');
    r := r || public._qa_s13_ok('N4R65.Q6 procurement never posts to merchant, courier or fee accounts', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.chop_pay_order_runtime;
    r := r || public._qa_s13_ok('N4R65.Q7 procurement created no merchant Chop Pay runtime row', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM public.marche_staple_commodities;
    r := r || public._qa_s13_ok('N4R65.Q8 the R6 catalog was not mutated by procurement', v_n = v_com0, v_n::text);
    SELECT count(*) INTO v_n FROM public.marche_staple_purchase_options;
    r := r || public._qa_s13_ok('N4R65.Q9 the R6 purchase options were not mutated by procurement', v_n = v_opt0, v_n::text);
    SELECT count(*) INTO v_n FROM public.marche_staple_variants;
    r := r || public._qa_s13_ok('N4R65.Q10 the R6 variants were not mutated by procurement', v_n = v_var0, v_n::text);
    SELECT count(*) INTO v_n FROM public.marche_staple_categories;
    r := r || public._qa_s13_ok('N4R65.Q11 the R6 categories were not mutated by procurement', v_n = v_cat0, v_n::text);
    SELECT COALESCE(sum(amount_gnf),0) INTO v_n FROM public.ledger_postings;
    r := r || public._qa_s13_ok('N4R65.Q12 the global ledger still sums to zero during the run', v_n = 0, v_n::text);
    SELECT count(*) INTO v_n FROM (
      SELECT j.id FROM public.ledger_journals j JOIN public.ledger_postings p ON p.journal_id=j.id
       GROUP BY j.id HAVING sum(p.amount_gnf) <> 0) z;
    r := r || public._qa_s13_ok('N4R65.Q13 no imbalanced journal exists anywhere', v_n = 0, v_n::text);

    PERFORM set_config('request.jwt.claims','',true);
    RAISE EXCEPTION 'QA_N4R65_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'QA_N4R65_ROLLBACK' THEN
      r := r || public._qa_s13_ok('N4R65.HARNESS_UNEXPECTED_ABORT', false, SQLERRM);
    END IF;
  END;

  PERFORM set_config('request.jwt.claims','',true);
  -- ============== Z. POST-ROLLBACK RESIDUE ==============
  SELECT count(*) INTO v_n FROM public.marche_procurement_requests;
  r := r || public._qa_s13_ok('N4R65.Z1 zero procurement request residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_procurement_request_items;
  r := r || public._qa_s13_ok('N4R65.Z2 zero procurement line residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_procurement_authorizations;
  r := r || public._qa_s13_ok('N4R65.Z3 zero authorization residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_procurement_events;
  r := r || public._qa_s13_ok('N4R65.Z4 zero procurement event residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_procurement_price_observations;
  r := r || public._qa_s13_ok('N4R65.Z5 zero QA price observation residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.mission_financial_holds WHERE source_module='marche_procurement';
  r := r || public._qa_s13_ok('N4R65.Z6 zero procurement hold residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.ledger_journals WHERE source_module='marche_procurement';
  r := r || public._qa_s13_ok('N4R65.Z7 zero procurement ledger residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM auth.users WHERE email LIKE 'qa-s13-r65%@qa.invalid';
  r := r || public._qa_s13_ok('N4R65.Z8 zero QA identity residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.wallets;
  r := r || public._qa_s13_ok('N4R65.Z9 wallet population is back to baseline', v_n = v_w0, format('%s->%s', v_w0, v_n));
  SELECT count(*) INTO v_n FROM public.wallet_transactions;
  r := r || public._qa_s13_ok('N4R65.Z10 zero wallet transaction drift', v_n = v_wt0, format('%s->%s', v_wt0, v_n));
  SELECT count(*) INTO v_n FROM public.ledger_journals;
  r := r || public._qa_s13_ok('N4R65.Z11 zero ledger journal drift', v_n = v_lj0, format('%s->%s', v_lj0, v_n));
  SELECT count(*) INTO v_n FROM public.ledger_postings;
  r := r || public._qa_s13_ok('N4R65.Z12 zero ledger posting drift', v_n = v_lp0, format('%s->%s', v_lp0, v_n));
  SELECT count(*) INTO v_n FROM public.mission_financial_holds;
  r := r || public._qa_s13_ok('N4R65.Z13 zero hold drift', v_n = v_mfh0, format('%s->%s', v_mfh0, v_n));
  SELECT balance_gnf INTO v_master1 FROM public.wallets WHERE party_type='master' LIMIT 1;
  r := r || public._qa_s13_ok('N4R65.Z14 the master wallet is exactly back to its live balance',
        v_master1 = v_master0, format('%s->%s', v_master0, v_master1));
  SELECT COALESCE(sum(amount_gnf),0) INTO v_n FROM public.ledger_postings;
  r := r || public._qa_s13_ok('N4R65.Z15 the global ledger posting sum is zero after rollback', v_n = 0, v_n::text);
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;
  r := r || public._qa_s13_ok('N4R65.Z16 feature flags are byte-identical', v_flags1 = v_flags0, NULL);
  SELECT count(*) INTO v_n FROM public.marche_staple_commodities;
  r := r || public._qa_s13_ok('N4R65.Z17 the R6 catalog survives untouched', v_n = v_com0 AND v_n = 20, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_staple_purchase_options;
  r := r || public._qa_s13_ok('N4R65.Z18 the R6 purchase options survive untouched', v_n = v_opt0 AND v_n = 29, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_orders;
  r := r || public._qa_s13_ok('N4R65.Z19 zero merchant order drift', v_n = v_mo0, v_n::text);
  SELECT count(*) INTO v_n FROM public.missions;
  r := r || public._qa_s13_ok('N4R65.Z20 zero mission drift', v_n = v_ms0, v_n::text);
  SELECT count(*) INTO v_n FROM public.merchant_payables;
  r := r || public._qa_s13_ok('N4R65.Z21 zero merchant payable drift', v_n = v_mp0, v_n::text);
  SELECT count(*) INTO v_n FROM pg_proc p
   WHERE p.pronamespace='public'::regnamespace AND p.proname = '_qa_node4_marche_r65'
     AND (has_function_privilege('anon', p.oid,'EXECUTE') OR has_function_privilege('authenticated', p.oid,'EXECUTE'));
  r := r || public._qa_s13_ok('N4R65.Z22 the R6.5 harness is not client-executable', v_n = 0, v_n::text);
  r := r || public._qa_s13_ok('N4R65.Z23 anon still cannot execute has_role after the run',
        NOT has_function_privilege('anon','public.has_role(uuid,app_role)','EXECUTE'), NULL);

  RETURN public._qa_s13_summary(65, r);
END $function$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r65() FROM PUBLIC, anon, authenticated;