-- Helper: run arbitrary SQL under a given DB role + JWT identity, return SQLSTATE-free error text.
CREATE OR REPLACE FUNCTION public._qa_r6_err(p_role text, p_uid uuid, p_sql text)
RETURNS text LANGUAGE plpgsql SET search_path = public AS $$
DECLARE v_err text := 'OK';
BEGIN
  PERFORM set_config('request.jwt.claims',
    CASE WHEN p_uid IS NULL THEN '{"role":"anon"}' ELSE public._as_user_claims(p_uid) END, true);
  EXECUTE 'SET LOCAL ROLE ' || quote_ident(p_role);
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM;
  END;
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN v_err;
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  RETURN 'HARNESS_ERROR:' || SQLERRM;
END $$;
REVOKE ALL ON FUNCTION public._qa_r6_err(text,uuid,text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._qa_node4_marche_r6()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r jsonb := '[]'::jsonb;
  v_adm uuid; v_buy uuid; v_mer uuid; v_drv uuid;
  v_err text; v_json jsonb; v_j2 jsonb; v_n bigint; v_num numeric;
  v_cid uuid; v_vid uuid; v_oid uuid; v_oid_bag uuid; v_oid_bunch uuid;
  -- baselines
  v_w0 bigint; v_wt0 bigint; v_lj0 bigint; v_lp0 bigint; v_pi0 bigint; v_ms0 bigint;
  v_mp0 bigint; v_ss0 bigint; v_mo0 bigint; v_moi0 bigint; v_ft0 bigint; v_fe0 bigint;
  v_ml0 bigint; v_res0 bigint; v_orderable0 bigint; v_flags0 jsonb; v_fee0 int;
  v_cat0 bigint; v_com0 bigint; v_var0 bigint; v_opt0 bigint;
BEGIN
  -- ---------- baselines ----------
  SELECT count(*) INTO v_w0 FROM public.wallets;
  SELECT count(*) INTO v_wt0 FROM public.wallet_transactions;
  SELECT count(*) INTO v_lj0 FROM public.ledger_journals;
  SELECT count(*) INTO v_lp0 FROM public.ledger_postings;
  SELECT count(*) INTO v_pi0 FROM public.payment_intents;
  SELECT count(*) INTO v_ms0 FROM public.missions;
  SELECT count(*) INTO v_mp0 FROM public.merchant_payables;
  SELECT count(*) INTO v_ss0 FROM public.merchant_settlement_requests;
  SELECT count(*) INTO v_mo0 FROM public.marche_orders;
  SELECT count(*) INTO v_moi0 FROM public.marche_order_items;
  SELECT count(*) INTO v_ft0 FROM public.marche_fulfillment_transitions;
  SELECT count(*) INTO v_fe0 FROM public.marche_fulfillment_events;
  SELECT count(*) INTO v_ml0 FROM public.marketplace_listings;
  SELECT COALESCE(sum(quantity_reserved),0) INTO v_res0 FROM public.marketplace_listings;
  SELECT count(*) INTO v_orderable0 FROM public.marche_listing_truth() t WHERE (t).is_orderable;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;
  SELECT merchant_platform_fee_bps INTO v_fee0 FROM public.finance_policies
   WHERE effective_to IS NULL ORDER BY effective_from DESC LIMIT 1;
  SELECT count(*) INTO v_cat0 FROM public.marche_staple_categories;
  SELECT count(*) INTO v_com0 FROM public.marche_staple_commodities;
  SELECT count(*) INTO v_var0 FROM public.marche_staple_variants;
  SELECT count(*) INTO v_opt0 FROM public.marche_staple_purchase_options;

  -- ================= A. STRUCTURAL LAW =================
  r := r || public._qa_s13_ok('N4R6.A1 commodity table exists',
        to_regclass('public.marche_staple_commodities') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N4R6.A2 variant table exists',
        to_regclass('public.marche_staple_variants') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N4R6.A3 purchase option table exists',
        to_regclass('public.marche_staple_purchase_options') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N4R6.A4 category table exists',
        to_regclass('public.marche_staple_categories') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N4R6.A5 catalog is normalized (variant FK to commodity)',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.marche_staple_variants'::regclass
                AND contype='f' AND confrelid='public.marche_staple_commodities'::regclass), NULL);
  r := r || public._qa_s13_ok('N4R6.A6 option FK to variant',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.marche_staple_purchase_options'::regclass
                AND contype='f' AND confrelid='public.marche_staple_variants'::regclass), NULL);
  r := r || public._qa_s13_ok('N4R6.A7 staples carry NO listing/store coupling column',
        NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
          AND table_name IN ('marche_staple_commodities','marche_staple_variants','marche_staple_purchase_options')
          AND column_name IN ('listing_id','store_id','seller_id','merchant_id')), NULL);
  r := r || public._qa_s13_ok('N4R6.A8 staples carry NO price column (no price engine in R6)',
        NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
          AND table_name LIKE 'marche_staple%' AND (column_name LIKE '%price%' OR column_name LIKE '%gnf%')), NULL);
  r := r || public._qa_s13_ok('N4R6.A9 no staple price observation/ranking table exists yet',
        to_regclass('public.marche_staple_price_observations') IS NULL
    AND to_regclass('public.marche_staple_prices') IS NULL, NULL);
  r := r || public._qa_s13_ok('N4R6.A10 commodity code is unique',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.marche_staple_commodities'::regclass
                AND contype='u'), NULL);
  r := r || public._qa_s13_ok('N4R6.A11 variant code unique per commodity',
        EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='marche_staple_variant_code_unique'), NULL);
  r := r || public._qa_s13_ok('N4R6.A12 option code unique per variant',
        EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='marche_staple_option_code_unique'), NULL);
  r := r || public._qa_s13_ok('N4R6.A13 normalization kind is constrained',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conname='marche_staple_option_norm_kind_chk'), NULL);
  r := r || public._qa_s13_ok('N4R6.A14 canonical base unit is constrained to kg/l/piece',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conname='marche_staple_option_base_unit_chk'), NULL);
  r := r || public._qa_s13_ok('N4R6.A15 option validation trigger installed',
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='trg_marche_staple_option_guard'), NULL);
  r := r || public._qa_s13_ok('N4R6.A16 all four catalog tables have RLS enabled with zero policies',
        (SELECT bool_and(relrowsecurity) FROM pg_class WHERE oid IN (
           'public.marche_staple_categories'::regclass,'public.marche_staple_commodities'::regclass,
           'public.marche_staple_variants'::regclass,'public.marche_staple_purchase_options'::regclass))
        AND (SELECT count(*) FROM pg_policies WHERE tablename LIKE 'marche_staple%') = 0, NULL);
  r := r || public._qa_s13_ok('N4R6.A17 catalog tables are unreachable directly by anon/authenticated',
        NOT has_table_privilege('anon','public.marche_staple_commodities','SELECT')
    AND NOT has_table_privilege('authenticated','public.marche_staple_commodities','SELECT')
    AND NOT has_table_privilege('authenticated','public.marche_staple_purchase_options','INSERT')
    AND NOT has_table_privilege('authenticated','public.marche_staple_variants','UPDATE')
    AND NOT has_table_privilege('anon','public.marche_staple_purchase_options','SELECT'), NULL);
  r := r || public._qa_s13_ok('N4R6.A18 sanitized public view is not client-readable',
        NOT has_table_privilege('anon','public.v_marche_staple_public','SELECT')
    AND NOT has_table_privilege('authenticated','public.v_marche_staple_public','SELECT'), NULL);
  r := r || public._qa_s13_ok('N4R6.A19 public read RPCs exist and are definer',
        (SELECT bool_and(prosecdef) FROM pg_proc WHERE pronamespace='public'::regnamespace
          AND proname IN ('marche_staples_discover','marche_staple_get','marche_staple_categories_public')), NULL);
  r := r || public._qa_s13_ok('N4R6.A20 admin mutation RPCs exist and are definer',
        (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace
          AND prosecdef AND proname IN ('marche_staple_commodity_upsert','marche_staple_variant_upsert',
          'marche_staple_option_upsert','marche_staple_set_active','marche_staples_admin')) = 5, NULL);
  r := r || public._qa_s13_ok('N4R6.A21 every R6 function pins search_path',
        NOT EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace
          AND proname LIKE '%staple%'
          AND NOT (COALESCE(array_to_string(proconfig,','),'') LIKE '%search_path=public%')), NULL);
  r := r || public._qa_s13_ok('N4R6.A22 anon MAY execute the public read RPCs',
        has_function_privilege('anon','public.marche_staples_discover(text,text,int,int)','EXECUTE')
    AND has_function_privilege('anon','public.marche_staple_get(text)','EXECUTE')
    AND has_function_privilege('anon','public.marche_staple_categories_public()','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R6.A23 anon may NOT execute any catalog mutation RPC',
        NOT has_function_privilege('anon','public.marche_staple_commodity_upsert(jsonb)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_staple_variant_upsert(jsonb)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_staple_option_upsert(jsonb)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_staple_set_active(text,uuid,boolean)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_staples_admin()','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R6.A24 internal authority primitives are not client-callable',
        NOT has_function_privilege('authenticated','public._marche_staple_require_admin()','EXECUTE')
    AND NOT has_function_privilege('authenticated','public.marche_staple_can_manage(uuid)','EXECUTE')
    AND NOT has_function_privilege('authenticated','public._marche_staple_audit(uuid,text,text,text,jsonb)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R6.A25 anon still cannot execute has_role (P15.5 preserved)',
        NOT has_function_privilege('anon','public.has_role(uuid,app_role)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R6.A26 code immutability guard installed on all catalog tables',
        (SELECT count(*) FROM pg_trigger WHERE tgname IN (
          'trg_marche_staple_category_touch','trg_marche_staple_commodity_touch',
          'trg_marche_staple_variant_touch','trg_marche_staple_option_touch')) = 4, NULL);
  r := r || public._qa_s13_ok('N4R6.A27 staples rail does not reference marketplace_listings at all',
        NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid IN (
            'public.marche_staple_commodities'::regclass,'public.marche_staple_variants'::regclass,
            'public.marche_staple_purchase_options'::regclass)
          AND contype='f' AND confrelid='public.marketplace_listings'::regclass), NULL);
  r := r || public._qa_s13_ok('N4R6.A28 R1.5 merchant supply doctrine untouched (truth still needs a store)',
        (SELECT prosrc FROM pg_proc WHERE pronamespace='public'::regnamespace
          AND proname='marche_listing_truth') LIKE '%MERCHANT_STORE_REQUIRED%', NULL);

  -- ---------- fixtures ----------
  v_adm := gen_random_uuid(); v_buy := gen_random_uuid();
  v_mer := gen_random_uuid(); v_drv := gen_random_uuid();
  PERFORM public._qa_s13_user(v_adm,'r6adm');
  PERFORM public._qa_s13_user(v_buy,'r6buy');
  PERFORM public._qa_s13_user(v_mer,'r6mer');
  PERFORM public._qa_s13_user(v_drv,'r6drv');
  INSERT INTO public.admin_users(user_id, email, admin_role, status)
  VALUES (v_adm, 'qa-r6-adm@qa.invalid', 'god_admin', 'active');
  INSERT INTO public.user_roles(user_id, role) VALUES (v_mer,'merchant'), (v_drv,'driver');

  -- ================= B. HIERARCHY RUNTIME =================
  v_err := public._qa_r6_err('authenticated', v_adm,
    $q$SELECT public.marche_staple_commodity_upsert('{"code":"qa_r6_grain","category_code":"cereals_starch","name_fr":"QA R6 Grain","aliases":["qa r6 grain","céréale qa"],"unit_family":"mass","sort_order":900}'::jsonb)$q$);
  r := r || public._qa_s13_ok('N4R6.B1 admin can create a commodity via RPC', v_err = 'OK', v_err);
  SELECT id INTO v_cid FROM public.marche_staple_commodities WHERE code='qa_r6_grain';
  r := r || public._qa_s13_ok('N4R6.B2 created commodity is persisted', v_cid IS NOT NULL, NULL);

  v_err := public._qa_r6_err('authenticated', v_adm,
    $q$SELECT public.marche_staple_variant_upsert('{"commodity_code":"qa_r6_grain","code":"general","name_fr":"QA R6 Général","is_default":true}'::jsonb)$q$);
  r := r || public._qa_s13_ok('N4R6.B3 admin can create a variant via RPC', v_err = 'OK', v_err);
  SELECT id INTO v_vid FROM public.marche_staple_variants WHERE commodity_id=v_cid AND code='general';
  r := r || public._qa_s13_ok('N4R6.B4 variant is linked to its commodity', v_vid IS NOT NULL, NULL);

  v_err := public._qa_r6_err('authenticated', v_adm,
    $q$SELECT public.marche_staple_option_upsert('{"commodity_code":"qa_r6_grain","variant_code":"general","code":"kg","sale_unit":"kg","label_fr":"Au kilo","normalization_kind":"exact","canonical_base_unit":"kg","canonical_quantity":1,"min_qty":1,"max_qty":50,"step_qty":1}'::jsonb)$q$);
  r := r || public._qa_s13_ok('N4R6.B5 admin can create a kg purchase option', v_err = 'OK', v_err);
  v_err := public._qa_r6_err('authenticated', v_adm,
    $q$SELECT public.marche_staple_option_upsert('{"commodity_code":"qa_r6_grain","variant_code":"general","code":"sac_25kg","sale_unit":"sac_25kg","label_fr":"Sac de 25 kg","normalization_kind":"exact","canonical_base_unit":"kg","canonical_quantity":25,"min_qty":1,"max_qty":10,"step_qty":1}'::jsonb)$q$);
  r := r || public._qa_s13_ok('N4R6.B6 admin can create a 25 kg sack option', v_err = 'OK', v_err);
  v_err := public._qa_r6_err('authenticated', v_adm,
    $q$SELECT public.marche_staple_option_upsert('{"commodity_code":"qa_r6_grain","variant_code":"general","code":"botte","sale_unit":"botte","label_fr":"La botte","normalization_kind":"unit_native","min_qty":1,"max_qty":20,"step_qty":1}'::jsonb)$q$);
  r := r || public._qa_s13_ok('N4R6.B7 admin can create an honest unit-native option', v_err = 'OK', v_err);
  SELECT count(*) INTO v_n FROM public.marche_staple_purchase_options WHERE variant_id=v_vid;
  r := r || public._qa_s13_ok('N4R6.B8 variant owns exactly its three options', v_n = 3, v_n::text);
  r := r || public._qa_s13_ok('N4R6.B9 commodity->variant->option chain is queryable',
        EXISTS (SELECT 1 FROM public.marche_staple_commodities c
                JOIN public.marche_staple_variants v ON v.commodity_id=c.id
                JOIN public.marche_staple_purchase_options o ON o.variant_id=v.id
                WHERE c.code='qa_r6_grain' AND o.code='sac_25kg'), NULL);
  v_err := public._qa_r6_err('authenticated', v_adm,
    $q$SELECT public.marche_staple_commodity_upsert('{"code":"qa_r6_grain","category_code":"cereals_starch","name_fr":"QA R6 Grain v2"}'::jsonb)$q$);
  r := r || public._qa_s13_ok('N4R6.B10 upsert updates display metadata in place', v_err='OK'
        AND (SELECT name_fr FROM public.marche_staple_commodities WHERE id=v_cid)='QA R6 Grain v2', v_err);
  SELECT count(*) INTO v_n FROM public.marche_staple_commodities WHERE code='qa_r6_grain';
  r := r || public._qa_s13_ok('N4R6.B11 update did not duplicate identity', v_n = 1, v_n::text);

  -- ================= C. EXACT NORMALIZATION MATH =================
  v_json := public.marche_staple_get('qa_r6_grain');
  SELECT (o->>'canonical_quantity')::numeric INTO v_num
    FROM jsonb_array_elements(v_json->'variants') v,
         jsonb_array_elements(v->'purchase_options') o WHERE o->>'option_code'='sac_25kg';
  r := r || public._qa_s13_ok('N4R6.C1 25 kg sack exposes factor 25', v_num = 25, v_num::text);
  r := r || public._qa_s13_ok('N4R6.C2 normalized unit price of a 250000 GNF sack is 10000/kg',
        (250000::numeric / v_num) = 10000, NULL);
  SELECT (o->>'canonical_base_unit') INTO v_err
    FROM jsonb_array_elements(v_json->'variants') v,
         jsonb_array_elements(v->'purchase_options') o WHERE o->>'option_code'='sac_25kg';
  r := r || public._qa_s13_ok('N4R6.C3 sack normalizes to kg base unit', v_err='kg', v_err);
  SELECT (o->>'canonical_quantity')::numeric INTO v_num
    FROM jsonb_array_elements(v_json->'variants') v,
         jsonb_array_elements(v->'purchase_options') o WHERE o->>'option_code'='kg';
  r := r || public._qa_s13_ok('N4R6.C4 kg option factor is 1', v_num = 1, v_num::text);
  SELECT canonical_quantity INTO v_num FROM public.marche_staple_purchase_options o
    JOIN public.marche_staple_variants v ON v.id=o.variant_id
    JOIN public.marche_staple_commodities c ON c.id=v.commodity_id
   WHERE c.code='cooking_oil' AND o.code='bidon_5l';
  r := r || public._qa_s13_ok('N4R6.C5 seeded 5 L container normalizes to 5 L', v_num = 5, v_num::text);
  r := r || public._qa_s13_ok('N4R6.C6 normalized L price of a 90000 GNF 5 L container is 18000/L',
        (90000::numeric / v_num) = 18000, NULL);
  SELECT canonical_quantity INTO v_num FROM public.marche_staple_purchase_options o
    JOIN public.marche_staple_variants v ON v.id=o.variant_id
    JOIN public.marche_staple_commodities c ON c.id=v.commodity_id
   WHERE c.code='water' AND o.code='pack_6x1_5l';
  r := r || public._qa_s13_ok('N4R6.C7 explicit 6x1.5L pack normalizes to 9 L', v_num = 9, v_num::text);
  SELECT canonical_base_unit INTO v_err FROM public.marche_staple_purchase_options o
    JOIN public.marche_staple_variants v ON v.id=o.variant_id
    JOIN public.marche_staple_commodities c ON c.id=v.commodity_id
   WHERE c.code='bread' AND o.code='piece';
  r := r || public._qa_s13_ok('N4R6.C8 bread is normalized as piece, never silently as kg', v_err='piece', v_err);
  SELECT canonical_base_unit INTO v_err FROM public.marche_staple_purchase_options o
    JOIN public.marche_staple_variants v ON v.id=o.variant_id
    JOIN public.marche_staple_commodities c ON c.id=v.commodity_id
   WHERE c.code='chicken' AND o.code='piece';
  r := r || public._qa_s13_ok('N4R6.C9 chicken piece is NOT converted to kg', v_err='piece', v_err);
  r := r || public._qa_s13_ok('N4R6.C10 every exact option carries a positive factor and base unit',
        NOT EXISTS (SELECT 1 FROM public.marche_staple_purchase_options
                    WHERE normalization_kind='exact'
                      AND (canonical_base_unit IS NULL OR COALESCE(canonical_quantity,0) <= 0)), NULL);
  v_err := public._qa_r6_err('authenticated', v_adm,
    $q$SELECT public.marche_staple_option_upsert('{"commodity_code":"qa_r6_grain","variant_code":"general","code":"bad_exact","sale_unit":"x","label_fr":"x","normalization_kind":"exact"}'::jsonb)$q$);
  r := r || public._qa_s13_ok('N4R6.C11 exact without base unit is refused',
        v_err LIKE '%STAPLE_UNKNOWN_BASE_UNIT%', v_err);
  v_err := public._qa_r6_err('authenticated', v_adm,
    $q$SELECT public.marche_staple_option_upsert('{"commodity_code":"qa_r6_grain","variant_code":"general","code":"bad_exact2","sale_unit":"x","label_fr":"x","normalization_kind":"exact","canonical_base_unit":"kg","canonical_quantity":0}'::jsonb)$q$);
  r := r || public._qa_s13_ok('N4R6.C12 exact with zero factor is refused',
        v_err LIKE '%STAPLE_INVALID_CONVERSION_FACTOR%', v_err);
  v_err := public._qa_r6_err('authenticated', v_adm,
    $q$SELECT public.marche_staple_option_upsert('{"commodity_code":"qa_r6_grain","variant_code":"general","code":"bad_exact3","sale_unit":"x","label_fr":"x","normalization_kind":"exact","canonical_base_unit":"kg","canonical_quantity":-3}'::jsonb)$q$);
  r := r || public._qa_s13_ok('N4R6.C13 negative conversion factor is refused',
        v_err LIKE '%STAPLE_INVALID_CONVERSION_FACTOR%', v_err);
  v_err := public._qa_r6_err('authenticated', v_adm,
    $q$SELECT public.marche_staple_option_upsert('{"commodity_code":"qa_r6_grain","variant_code":"general","code":"bad_unit","sale_unit":"x","label_fr":"x","normalization_kind":"exact","canonical_base_unit":"tonne","canonical_quantity":1}'::jsonb)$q$);
  r := r || public._qa_s13_ok('N4R6.C14 unsupported base unit is refused',
        v_err LIKE '%STAPLE_UNKNOWN_BASE_UNIT%', v_err);

  -- ================= D. HONEST NON-STANDARD UNITS =================
  SELECT id INTO v_oid_bunch FROM public.marche_staple_purchase_options
   WHERE variant_id=v_vid AND code='botte';
  r := r || public._qa_s13_ok('N4R6.D1 bunch option exists without a fake kg factor',
        EXISTS (SELECT 1 FROM public.marche_staple_purchase_options
                WHERE id=v_oid_bunch AND normalization_kind='unit_native'
                  AND canonical_base_unit IS NULL AND canonical_quantity IS NULL), NULL);
  v_err := public._qa_r6_err('authenticated', v_adm,
    $q$SELECT public.marche_staple_option_upsert('{"commodity_code":"qa_r6_grain","variant_code":"general","code":"tas","sale_unit":"tas","label_fr":"Tas","normalization_kind":"non_comparable","min_qty":1,"max_qty":5,"step_qty":1}'::jsonb)$q$);
  r := r || public._qa_s13_ok('N4R6.D2 non-comparable heap option is accepted', v_err='OK', v_err);
  v_err := public._qa_r6_err('authenticated', v_adm,
    $q$SELECT public.marche_staple_option_upsert('{"commodity_code":"qa_r6_grain","variant_code":"general","code":"botte","sale_unit":"botte","label_fr":"La botte","normalization_kind":"unit_native","canonical_base_unit":"kg","canonical_quantity":2,"min_qty":1,"max_qty":20,"step_qty":1}'::jsonb)$q$);
  r := r || public._qa_s13_ok('N4R6.D3 unit-native option may NOT claim a cross-unit factor',
        v_err LIKE '%STAPLE_NON_EXACT_CANNOT_NORMALIZE%', v_err);
  v_err := public._qa_r6_err('authenticated', v_adm,
    $q$SELECT public.marche_staple_option_upsert('{"commodity_code":"qa_r6_grain","variant_code":"general","code":"tas","sale_unit":"tas","label_fr":"Tas","normalization_kind":"non_comparable","canonical_base_unit":"kg","canonical_quantity":3,"min_qty":1,"max_qty":5,"step_qty":1}'::jsonb)$q$);
  r := r || public._qa_s13_ok('N4R6.D4 non-comparable option may NOT claim a factor',
        v_err LIKE '%STAPLE_NON_EXACT_CANNOT_NORMALIZE%', v_err);
  r := r || public._qa_s13_ok('N4R6.D5 bunch option is still discoverable to customers',
        EXISTS (SELECT 1 FROM jsonb_array_elements(public.marche_staple_get('qa_r6_grain')->'variants') v,
                     jsonb_array_elements(v->'purchase_options') o WHERE o->>'option_code'='botte'), NULL);
  r := r || public._qa_s13_ok('N4R6.D6 seeded leafy greens are sold by unit-native bunch',
        EXISTS (SELECT 1 FROM public.marche_staple_purchase_options o
                JOIN public.marche_staple_variants v ON v.id=o.variant_id
                JOIN public.marche_staple_commodities c ON c.id=v.commodity_id
                WHERE c.code='cassava_leaf' AND o.code='botte'
                  AND o.normalization_kind='unit_native' AND o.canonical_quantity IS NULL), NULL);
  r := r || public._qa_s13_ok('N4R6.D7 undeclared charcoal sack is non-comparable, not fake-kg',
        EXISTS (SELECT 1 FROM public.marche_staple_purchase_options o
                JOIN public.marche_staple_variants v ON v.id=o.variant_id
                JOIN public.marche_staple_commodities c ON c.id=v.commodity_id
                WHERE c.code='charcoal' AND o.code='sac'
                  AND o.normalization_kind='non_comparable' AND o.canonical_base_unit IS NULL), NULL);
  r := r || public._qa_s13_ok('N4R6.D8 no non-exact option anywhere carries a normalization factor',
        NOT EXISTS (SELECT 1 FROM public.marche_staple_purchase_options
                    WHERE normalization_kind <> 'exact'
                      AND (canonical_base_unit IS NOT NULL OR canonical_quantity IS NOT NULL)), NULL);

  -- ================= E. QUANTITY LAW =================
  v_err := public._qa_r6_err('authenticated', v_adm,
    $q$SELECT public.marche_staple_option_upsert('{"commodity_code":"qa_r6_grain","variant_code":"general","code":"q1","sale_unit":"kg","label_fr":"q","normalization_kind":"exact","canonical_base_unit":"kg","canonical_quantity":1,"min_qty":0,"max_qty":5,"step_qty":1}'::jsonb)$q$);
  r := r || public._qa_s13_ok('N4R6.E1 min qty of 0 is refused', v_err LIKE '%STAPLE_MIN_QTY_INVALID%', v_err);
  v_err := public._qa_r6_err('authenticated', v_adm,
    $q$SELECT public.marche_staple_option_upsert('{"commodity_code":"qa_r6_grain","variant_code":"general","code":"q2","sale_unit":"kg","label_fr":"q","normalization_kind":"exact","canonical_base_unit":"kg","canonical_quantity":1,"min_qty":-2,"max_qty":5,"step_qty":1}'::jsonb)$q$);
  r := r || public._qa_s13_ok('N4R6.E2 negative min qty is refused', v_err LIKE '%STAPLE_MIN_QTY_INVALID%', v_err);
  v_err := public._qa_r6_err('authenticated', v_adm,
    $q$SELECT public.marche_staple_option_upsert('{"commodity_code":"qa_r6_grain","variant_code":"general","code":"q3","sale_unit":"kg","label_fr":"q","normalization_kind":"exact","canonical_base_unit":"kg","canonical_quantity":1,"min_qty":5,"max_qty":2,"step_qty":1}'::jsonb)$q$);
  r := r || public._qa_s13_ok('N4R6.E3 max below min is refused', v_err LIKE '%STAPLE_MAX_QTY_INVALID%', v_err);
  v_err := public._qa_r6_err('authenticated', v_adm,
    $q$SELECT public.marche_staple_option_upsert('{"commodity_code":"qa_r6_grain","variant_code":"general","code":"q4","sale_unit":"kg","label_fr":"q","normalization_kind":"exact","canonical_base_unit":"kg","canonical_quantity":1,"min_qty":1,"max_qty":5,"step_qty":0}'::jsonb)$q$);
  r := r || public._qa_s13_ok('N4R6.E4 zero step is refused', v_err LIKE '%STAPLE_STEP_QTY_INVALID%', v_err);
  v_err := public._qa_r6_err('authenticated', v_adm,
    $q$SELECT public.marche_staple_option_upsert('{"commodity_code":"qa_r6_grain","variant_code":"general","code":"q5","sale_unit":"kg","label_fr":"q","normalization_kind":"exact","canonical_base_unit":"kg","canonical_quantity":1,"min_qty":1,"max_qty":5,"step_qty":-1}'::jsonb)$q$);
  r := r || public._qa_s13_ok('N4R6.E5 negative step is refused', v_err LIKE '%STAPLE_STEP_QTY_INVALID%', v_err);
  v_err := public._qa_r6_err('authenticated', v_adm,
    $q$SELECT public.marche_staple_option_upsert('{"commodity_code":"qa_r6_grain","variant_code":"general","code":"q6","sale_unit":"kg","label_fr":"q","normalization_kind":"exact","canonical_base_unit":"kg","canonical_quantity":1,"min_qty":1,"max_qty":6,"step_qty":2}'::jsonb)$q$);
  r := r || public._qa_s13_ok('N4R6.E6 range not aligned to step is refused',
        v_err LIKE '%STAPLE_QTY_RANGE_NOT_STEP_ALIGNED%', v_err);
  v_err := public._qa_r6_err('authenticated', v_adm,
    $q$SELECT public.marche_staple_option_upsert('{"commodity_code":"qa_r6_grain","variant_code":"general","code":"q7","sale_unit":"kg","label_fr":"Demi-kilo","normalization_kind":"exact","canonical_base_unit":"kg","canonical_quantity":0.5,"min_qty":1,"max_qty":5,"step_qty":2}'::jsonb)$q$);
  r := r || public._qa_s13_ok('N4R6.E7 a correctly step-aligned range is accepted', v_err='OK', v_err);
  SELECT count(*) INTO v_n FROM public.marche_staple_purchase_options
   WHERE variant_id=v_vid AND code IN ('q1','q2','q3','q4','q5','q6');
  r := r || public._qa_s13_ok('N4R6.E8 no invalid quantity option leaked into the catalog', v_n = 0, v_n::text);
  r := r || public._qa_s13_ok('N4R6.E9 quantity rules are machine-readable numerics, not copy',
        (SELECT count(*) FROM information_schema.columns WHERE table_schema='public'
          AND table_name='marche_staple_purchase_options'
          AND column_name IN ('min_qty','max_qty','step_qty') AND data_type='numeric') = 3, NULL);
  r := r || public._qa_s13_ok('N4R6.E10 public read exposes min/max/step to the client',
        (SELECT o ? 'min_qty' AND o ? 'max_qty' AND o ? 'step_qty'
           FROM jsonb_array_elements(public.marche_staple_get('rice')->'variants') v,
                jsonb_array_elements(v->'purchase_options') o LIMIT 1), NULL);
  -- direct table write bypass must also fail closed
  BEGIN
    INSERT INTO public.marche_staple_purchase_options(variant_id, code, sale_unit, label_fr,
      normalization_kind, min_qty, max_qty, step_qty)
    VALUES (v_vid,'q_direct','kg','q','unit_native',0,5,1);
    v_err := 'NO_ERROR';
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N4R6.E11 direct table insert is validated too',
        v_err LIKE '%STAPLE_MIN_QTY_INVALID%', v_err);

  -- ================= F. DUPLICATE / IDENTITY LAW =================
  v_err := public._qa_r6_err('authenticated', v_adm,
    $q$SELECT public.marche_staple_variant_upsert('{"commodity_code":"qa_r6_grain","code":"general","name_fr":"Doublon"}'::jsonb)$q$);
  SELECT count(*) INTO v_n FROM public.marche_staple_variants WHERE commodity_id=v_cid AND code='general';
  r := r || public._qa_s13_ok('N4R6.F1 duplicate variant code cannot create a second row', v_n = 1, v_n::text);
  BEGIN
    INSERT INTO public.marche_staple_commodities(code, category_code, name_fr, unit_family)
    VALUES ('qa_r6_grain','cereals_starch','dup','mass');
    v_err := 'NO_ERROR';
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N4R6.F2 duplicate commodity code is refused at the table',
        v_err <> 'NO_ERROR', v_err);
  BEGIN
    INSERT INTO public.marche_staple_variants(commodity_id, code, name_fr)
    VALUES (v_cid,'general','dup');
    v_err := 'NO_ERROR';
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N4R6.F3 duplicate variant code is refused at the table',
        v_err <> 'NO_ERROR', v_err);
  BEGIN
    INSERT INTO public.marche_staple_purchase_options(variant_id, code, sale_unit, label_fr,
      normalization_kind, canonical_base_unit, canonical_quantity, min_qty, max_qty, step_qty)
    VALUES (v_vid,'kg','kg','dup','exact','kg',1,1,5,1);
    v_err := 'NO_ERROR';
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N4R6.F4 duplicate option code is refused at the table',
        v_err <> 'NO_ERROR', v_err);
  BEGIN
    UPDATE public.marche_staple_commodities SET code='qa_r6_grain_renamed' WHERE id=v_cid;
    v_err := 'NO_ERROR';
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N4R6.F5 canonical commodity code is immutable',
        v_err LIKE '%STAPLE_CODE_IMMUTABLE%', v_err);
  BEGIN
    UPDATE public.marche_staple_variants SET code='renamed' WHERE id=v_vid;
    v_err := 'NO_ERROR';
  EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N4R6.F6 variant code is immutable', v_err LIKE '%STAPLE_CODE_IMMUTABLE%', v_err);
  v_err := public._qa_r6_err('authenticated', v_adm,
    $q$SELECT public.marche_staple_variant_upsert('{"commodity_code":"qa_r6_nope","code":"x","name_fr":"x"}'::jsonb)$q$);
  r := r || public._qa_s13_ok('N4R6.F7 unknown commodity is refused',
        v_err LIKE '%STAPLE_UNKNOWN_COMMODITY%', v_err);
  v_err := public._qa_r6_err('authenticated', v_adm,
    $q$SELECT public.marche_staple_option_upsert('{"commodity_code":"qa_r6_grain","variant_code":"nope","code":"x","sale_unit":"kg","label_fr":"x","normalization_kind":"exact","canonical_base_unit":"kg","canonical_quantity":1}'::jsonb)$q$);
  r := r || public._qa_s13_ok('N4R6.F8 unknown variant is refused', v_err LIKE '%STAPLE_UNKNOWN_VARIANT%', v_err);
  v_err := public._qa_r6_err('authenticated', v_adm,
    $q$SELECT public.marche_staple_commodity_upsert('{"code":"qa_r6_x","category_code":"nope","name_fr":"x"}'::jsonb)$q$);
  r := r || public._qa_s13_ok('N4R6.F9 unknown category is refused', v_err LIKE '%STAPLE_UNKNOWN_CATEGORY%', v_err);

  -- ================= G. ACTIVE-STATE DISCOVERY CASCADE =================
  SELECT count(*) INTO v_n FROM jsonb_array_elements(public.marche_staples_discover(null,null,500,0)) x
   WHERE x->>'commodity_code'='qa_r6_grain';
  r := r || public._qa_s13_ok('N4R6.G1 active commodity is publicly discoverable', v_n = 1, v_n::text);
  v_err := public._qa_r6_err('authenticated', v_adm,
    format($q$SELECT public.marche_staple_set_active('option','%s',false)$q$, v_oid_bunch));
  r := r || public._qa_s13_ok('N4R6.G2 admin can deactivate an option', v_err='OK', v_err);
  r := r || public._qa_s13_ok('N4R6.G3 deactivated option disappears from public read',
        NOT EXISTS (SELECT 1 FROM jsonb_array_elements(public.marche_staple_get('qa_r6_grain')->'variants') v,
                    jsonb_array_elements(v->'purchase_options') o WHERE o->>'option_code'='botte'), NULL);
  r := r || public._qa_s13_ok('N4R6.G4 deactivated option row still exists (identity preserved)',
        EXISTS (SELECT 1 FROM public.marche_staple_purchase_options
                WHERE id=v_oid_bunch AND is_active=false), NULL);
  v_err := public._qa_r6_err('authenticated', v_adm,
    format($q$SELECT public.marche_staple_set_active('variant','%s',false)$q$, v_vid));
  r := r || public._qa_s13_ok('N4R6.G5 admin can deactivate a variant', v_err='OK', v_err);
  r := r || public._qa_s13_ok('N4R6.G6 inactive variant removes the commodity from discovery',
        public.marche_staple_get('qa_r6_grain') IS NULL, NULL);
  v_err := public._qa_r6_err('authenticated', v_adm,
    format($q$SELECT public.marche_staple_set_active('variant','%s',true)$q$, v_vid));
  r := r || public._qa_s13_ok('N4R6.G7 reactivation restores discovery without recreating rows',
        v_err='OK' AND public.marche_staple_get('qa_r6_grain') IS NOT NULL, v_err);
  v_err := public._qa_r6_err('authenticated', v_adm,
    format($q$SELECT public.marche_staple_set_active('commodity','%s',false)$q$, v_cid));
  SELECT count(*) INTO v_n FROM jsonb_array_elements(public.marche_staples_discover(null,null,500,0)) x
   WHERE x->>'commodity_code'='qa_r6_grain';
  r := r || public._qa_s13_ok('N4R6.G8 inactive commodity is hidden from discovery', v_n = 0, v_n::text);
  r := r || public._qa_s13_ok('N4R6.G9 inactive commodity cannot be read by code either',
        public.marche_staple_get('qa_r6_grain') IS NULL, NULL);
  r := r || public._qa_s13_ok('N4R6.G10 inactive commodity historical identity is preserved',
        EXISTS (SELECT 1 FROM public.marche_staple_commodities WHERE id=v_cid AND is_active=false), NULL);
  SELECT count(*) INTO v_n FROM public.marche_staple_variants WHERE commodity_id=v_cid;
  r := r || public._qa_s13_ok('N4R6.G11 deactivation deleted nothing downstream', v_n = 1, v_n::text);
  v_err := public._qa_r6_err('authenticated', v_adm,
    format($q$SELECT public.marche_staple_set_active('commodity','%s',true)$q$, v_cid));
  r := r || public._qa_s13_ok('N4R6.G12 commodity reactivation restores public truth',
        v_err='OK' AND public.marche_staple_get('qa_r6_grain') IS NOT NULL, v_err);
  v_err := public._qa_r6_err('authenticated', v_adm,
    format($q$SELECT public.marche_staple_set_active('option','%s',true)$q$, v_oid_bunch));
  r := r || public._qa_s13_ok('N4R6.G13 option reactivation works', v_err='OK', v_err);
  v_err := public._qa_r6_err('authenticated', v_adm,
    $q$SELECT public.marche_staple_set_active('bogus','00000000-0000-0000-0000-000000000000',true)$q$);
  r := r || public._qa_s13_ok('N4R6.G14 unknown activation target kind is refused',
        v_err LIKE '%STAPLE_UNKNOWN_TARGET_KIND%', v_err);
  v_err := public._qa_r6_err('authenticated', v_adm,
    $q$SELECT public.marche_staple_set_active('commodity','00000000-0000-0000-0000-000000000000',true)$q$);
  r := r || public._qa_s13_ok('N4R6.G15 activating a missing row is refused',
        v_err LIKE '%STAPLE_TARGET_NOT_FOUND%', v_err);

  -- ================= I. AUTHORITY =================
  v_err := public._qa_r6_err('authenticated', v_buy,
    $q$SELECT public.marche_staple_commodity_upsert('{"code":"qa_r6_hack","category_code":"cereals_starch","name_fr":"hack"}'::jsonb)$q$);
  r := r || public._qa_s13_ok('N4R6.I1 ordinary buyer cannot create a staple',
        v_err LIKE '%STAPLE_ADMIN_ONLY%', v_err);
  v_err := public._qa_r6_err('authenticated', v_mer,
    $q$SELECT public.marche_staple_commodity_upsert('{"code":"qa_r6_hack","category_code":"cereals_starch","name_fr":"hack"}'::jsonb)$q$);
  r := r || public._qa_s13_ok('N4R6.I2 merchant cannot create a staple', v_err LIKE '%STAPLE_ADMIN_ONLY%', v_err);
  v_err := public._qa_r6_err('authenticated', v_drv,
    $q$SELECT public.marche_staple_variant_upsert('{"commodity_code":"rice","code":"hack","name_fr":"hack"}'::jsonb)$q$);
  r := r || public._qa_s13_ok('N4R6.I3 driver cannot create a variant', v_err LIKE '%STAPLE_ADMIN_ONLY%', v_err);
  v_err := public._qa_r6_err('authenticated', v_buy,
    format($q$SELECT public.marche_staple_set_active('commodity','%s',false)$q$, v_cid));
  r := r || public._qa_s13_ok('N4R6.I4 buyer cannot deactivate a staple', v_err LIKE '%STAPLE_ADMIN_ONLY%', v_err);
  v_err := public._qa_r6_err('authenticated', v_mer,
    $q$SELECT public.marche_staple_option_upsert('{"commodity_code":"rice","variant_code":"local","code":"hack","sale_unit":"kg","label_fr":"x","normalization_kind":"exact","canonical_base_unit":"kg","canonical_quantity":1}'::jsonb)$q$);
  r := r || public._qa_s13_ok('N4R6.I5 merchant cannot add a purchase option',
        v_err LIKE '%STAPLE_ADMIN_ONLY%', v_err);
  v_err := public._qa_r6_err('anon', NULL,
    $q$SELECT public.marche_staple_commodity_upsert('{"code":"qa_r6_hack","category_code":"cereals_starch","name_fr":"hack"}'::jsonb)$q$);
  r := r || public._qa_s13_ok('N4R6.I6 anon cannot call the mutation RPC at all', v_err <> 'OK', v_err);
  v_err := public._qa_r6_err('authenticated', v_buy,
    $q$SELECT count(*) FROM public.marche_staple_commodities$q$);
  r := r || public._qa_s13_ok('N4R6.I7 buyer cannot read the raw catalog table', v_err <> 'OK', v_err);
  v_err := public._qa_r6_err('anon', NULL,
    $q$SELECT count(*) FROM public.marche_staple_purchase_options$q$);
  r := r || public._qa_s13_ok('N4R6.I8 anon cannot read the raw option table', v_err <> 'OK', v_err);
  v_err := public._qa_r6_err('authenticated', v_mer,
    $q$UPDATE public.marche_staple_commodities SET name_fr='x' WHERE code='rice'$q$);
  r := r || public._qa_s13_ok('N4R6.I9 merchant cannot UPDATE the catalog table directly', v_err <> 'OK', v_err);
  v_err := public._qa_r6_err('authenticated', v_buy, $q$SELECT public.marche_staples_admin()$q$);
  r := r || public._qa_s13_ok('N4R6.I10 buyer cannot use the admin read RPC',
        v_err LIKE '%STAPLE_ADMIN_ONLY%', v_err);
  v_err := public._qa_r6_err('authenticated', v_adm, $q$SELECT public.marche_staples_admin()$q$);
  r := r || public._qa_s13_ok('N4R6.I11 admin CAN use the admin read RPC', v_err='OK', v_err);
  SELECT count(*) INTO v_n FROM public.marche_staple_commodities WHERE code='qa_r6_hack';
  r := r || public._qa_s13_ok('N4R6.I12 no unauthorized row was created', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.audit_logs
   WHERE module='marche' AND action LIKE 'staple_%' AND actor_user_id = v_adm;
  r := r || public._qa_s13_ok('N4R6.I13 admin catalog mutations are audit-logged', v_n > 0, v_n::text);

  -- ================= J. PUBLIC DISCOVERY / SEARCH =================
  v_json := public.marche_staples_discover(null,null,500,0);
  r := r || public._qa_s13_ok('N4R6.J1 discovery returns the production starter catalog',
        jsonb_array_length(v_json) >= 20, jsonb_array_length(v_json)::text);
  v_j2 := public.marche_staples_discover('riz',null,50,0);
  r := r || public._qa_s13_ok('N4R6.J2 French name search finds rice',
        EXISTS (SELECT 1 FROM jsonb_array_elements(v_j2) x WHERE x->>'commodity_code'='rice'), NULL);
  v_j2 := public.marche_staples_discover('saka saka',null,50,0);
  r := r || public._qa_s13_ok('N4R6.J3 alias search finds cassava leaves',
        EXISTS (SELECT 1 FROM jsonb_array_elements(v_j2) x WHERE x->>'commodity_code'='cassava_leaf'), NULL);
  v_j2 := public.marche_staples_discover('tulu',null,50,0);
  r := r || public._qa_s13_ok('N4R6.J4 alias search finds cooking oil',
        EXISTS (SELECT 1 FROM jsonb_array_elements(v_j2) x WHERE x->>'commodity_code'='cooking_oil'), NULL);
  v_j2 := public.marche_staples_discover(null,'fish',50,0);
  r := r || public._qa_s13_ok('N4R6.J5 category filter isolates the fish category',
        jsonb_array_length(v_j2) = 2
    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_j2) x WHERE x->>'category_code' <> 'fish'),
        jsonb_array_length(v_j2)::text);
  r := r || public._qa_s13_ok('N4R6.J6 discovery never leaks internal audit metadata',
        NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_json) x
                    WHERE x ? 'created_at' OR x ? 'updated_at' OR x ? 'is_active'), NULL);
  r := r || public._qa_s13_ok('N4R6.J7 discovery ordering is deterministic',
        (SELECT string_agg(x->>'commodity_code', ',' ORDER BY ord)
           FROM jsonb_array_elements(public.marche_staples_discover(null,null,500,0)) WITH ORDINALITY t(x,ord))
        = (SELECT string_agg(x->>'commodity_code', ',' ORDER BY ord)
           FROM jsonb_array_elements(public.marche_staples_discover(null,null,500,0)) WITH ORDINALITY t(x,ord)), NULL);
  r := r || public._qa_s13_ok('N4R6.J8 pagination works',
        jsonb_array_length(public.marche_staples_discover(null,null,5,0)) = 5
    AND jsonb_array_length(public.marche_staples_discover(null,null,5,5)) = 5, NULL);
  r := r || public._qa_s13_ok('N4R6.J9 category listing is public and non-empty',
        jsonb_array_length(public.marche_staple_categories_public()) >= 11, NULL);
  r := r || public._qa_s13_ok('N4R6.J10 unknown commodity read returns nothing, not an error',
        public.marche_staple_get('does_not_exist') IS NULL, NULL);
  v_err := public._qa_r6_err('anon', NULL, $q$SELECT public.marche_staples_discover(null,null,10,0)$q$);
  r := r || public._qa_s13_ok('N4R6.J11 signed-out customer can browse staples', v_err='OK', v_err);
  v_err := public._qa_r6_err('anon', NULL, $q$SELECT public.marche_staple_get('rice')$q$);
  r := r || public._qa_s13_ok('N4R6.J12 signed-out customer can read one staple', v_err='OK', v_err);
  v_err := public._qa_r6_err('anon', NULL, $q$SELECT public.marche_staple_categories_public()$q$);
  r := r || public._qa_s13_ok('N4R6.J13 signed-out customer can read categories', v_err='OK', v_err);
  r := r || public._qa_s13_ok('N4R6.J14 no staple payload carries a price or money field',
        NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_json) x, jsonb_object_keys(x) k
                    WHERE k ILIKE '%price%' OR k ILIKE '%gnf%' OR k ILIKE '%rating%' OR k ILIKE '%rank%'), NULL);
  r := r || public._qa_s13_ok('N4R6.J15 staple detail payload carries no price or rating field',
        NOT EXISTS (SELECT 1 FROM jsonb_object_keys(public.marche_staple_get('rice')) k
                    WHERE k ILIKE '%price%' OR k ILIKE '%gnf%' OR k ILIKE '%rating%'), NULL);

  -- ================= L. RAIL SEPARATION =================
  r := r || public._qa_s13_ok('N4R6.L1 zero staple codes leaked into marketplace_listings',
        NOT EXISTS (SELECT 1 FROM public.marketplace_listings l
                    JOIN public.marche_staple_commodities c ON l.title = c.name_fr), NULL);
  SELECT count(*) INTO v_n FROM public.marketplace_listings;
  r := r || public._qa_s13_ok('N4R6.L2 marketplace_listings total unchanged by R6', v_n = v_ml0,
        v_n::text || ' vs ' || v_ml0::text);
  SELECT count(*) INTO v_n FROM public.marche_listing_truth() t WHERE (t).is_orderable;
  r := r || public._qa_s13_ok('N4R6.L3 orderable merchant supply unchanged', v_n = v_orderable0,
        v_n::text || ' vs ' || v_orderable0::text);
  r := r || public._qa_s13_ok('N4R6.L4 no fake merchant store was created for staples',
        NOT EXISTS (SELECT 1 FROM public.merchant_stores WHERE name ILIKE '%essentiel%chopchop%'), NULL);
  r := r || public._qa_s13_ok('N4R6.L5 staple catalog needs no store to be discoverable',
        jsonb_array_length(public.marche_staples_discover(null,null,5,0)) > 0, NULL);

  -- ================= M/N. NO MONEY / FULFILLMENT DRIFT =================
  SELECT count(*) INTO v_n FROM public.wallets;
  r := r || public._qa_s13_ok('N4R6.M1 wallets unchanged', v_n = v_w0, v_n::text);
  SELECT count(*) INTO v_n FROM public.wallet_transactions;
  r := r || public._qa_s13_ok('N4R6.M2 wallet transactions unchanged', v_n = v_wt0, v_n::text);
  SELECT count(*) INTO v_n FROM public.ledger_journals;
  r := r || public._qa_s13_ok('N4R6.M3 ledger journals unchanged', v_n = v_lj0, v_n::text);
  SELECT count(*) INTO v_n FROM public.ledger_postings;
  r := r || public._qa_s13_ok('N4R6.M4 ledger postings unchanged', v_n = v_lp0, v_n::text);
  SELECT count(*) INTO v_n FROM public.payment_intents;
  r := r || public._qa_s13_ok('N4R6.M5 payment intents unchanged', v_n = v_pi0, v_n::text);
  SELECT count(*) INTO v_n FROM public.missions;
  r := r || public._qa_s13_ok('N4R6.M6 missions unchanged', v_n = v_ms0, v_n::text);
  SELECT count(*) INTO v_n FROM public.merchant_payables;
  r := r || public._qa_s13_ok('N4R6.M7 merchant payables unchanged', v_n = v_mp0, v_n::text);
  SELECT count(*) INTO v_n FROM public.merchant_settlement_requests;
  r := r || public._qa_s13_ok('N4R6.M8 settlement requests unchanged', v_n = v_ss0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_orders;
  r := r || public._qa_s13_ok('N4R6.M9 marche orders unchanged', v_n = v_mo0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_order_items;
  r := r || public._qa_s13_ok('N4R6.M10 marche order items unchanged', v_n = v_moi0, v_n::text);
  SELECT COALESCE(sum(quantity_reserved),0) INTO v_n FROM public.marketplace_listings;
  r := r || public._qa_s13_ok('N4R6.M11 reserved stock unchanged', v_n = v_res0, v_n::text);
  SELECT merchant_platform_fee_bps INTO v_n FROM public.finance_policies
   WHERE effective_to IS NULL ORDER BY effective_from DESC LIMIT 1;
  r := r || public._qa_s13_ok('N4R6.M12 merchant platform fee still 100 bps', v_n = 100 AND v_n = v_fee0, v_n::text);
  r := r || public._qa_s13_ok('N4R6.M13 R6 introduced no delivery price resolution',
        NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
          AND table_name LIKE 'marche_staple%' AND column_name LIKE '%delivery%'), NULL);
  SELECT jsonb_object_agg(key, enabled) INTO v_json FROM public.feature_flags;
  r := r || public._qa_s13_ok('N4R6.M14 feature flags unchanged', v_json = v_flags0, NULL);
  SELECT count(*) INTO v_n FROM public.marche_fulfillment_transitions;
  r := r || public._qa_s13_ok('N4R6.N1 R5 fulfillment transitions unchanged', v_n = v_ft0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_fulfillment_events;
  r := r || public._qa_s13_ok('N4R6.N2 R3.5 fulfillment events unchanged', v_n = v_fe0, v_n::text);
  r := r || public._qa_s13_ok('N4R6.N3 R5 lifecycle vocabulary unchanged',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conname='marche_orders_fulfillment_state_legal'), NULL);
  r := r || public._qa_s13_ok('N4R6.N4 R6 wired no procurement/checkout primitive',
        to_regclass('public.marche_staple_orders') IS NULL
    AND to_regclass('public.marche_staple_baskets') IS NULL, NULL);

  -- ================= P. CLEANUP + RESIDUE =================
  DELETE FROM public.marche_staple_purchase_options WHERE variant_id = v_vid;
  DELETE FROM public.marche_staple_variants WHERE commodity_id = v_cid;
  DELETE FROM public.marche_staple_commodities WHERE id = v_cid;
  DELETE FROM public.audit_logs WHERE actor_user_id = v_adm;
  DELETE FROM public.admin_users WHERE user_id = v_adm;
  DELETE FROM public.user_roles WHERE user_id IN (v_mer, v_drv);
  DELETE FROM public.profiles WHERE id IN (v_adm, v_buy, v_mer, v_drv);
  DELETE FROM auth.users WHERE id IN (v_adm, v_buy, v_mer, v_drv);

  SELECT count(*) INTO v_n FROM public.marche_staple_commodities WHERE code LIKE 'qa_r6%';
  r := r || public._qa_s13_ok('N4R6.P1 zero QA commodity residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_staple_categories;
  r := r || public._qa_s13_ok('N4R6.P2 production categories intact', v_n = v_cat0 AND v_n = 11, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_staple_commodities;
  r := r || public._qa_s13_ok('N4R6.P3 production commodities exactly once', v_n = v_com0 AND v_n = 20, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_staple_variants;
  r := r || public._qa_s13_ok('N4R6.P4 production variants exactly once', v_n = v_var0 AND v_n = 21, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_staple_purchase_options;
  r := r || public._qa_s13_ok('N4R6.P5 production purchase options exactly once', v_n = v_opt0 AND v_n = 29, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_staple_commodities WHERE NOT is_active;
  r := r || public._qa_s13_ok('N4R6.P6 all production commodities left active', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM auth.users WHERE id IN (v_adm, v_buy, v_mer, v_drv);
  r := r || public._qa_s13_ok('N4R6.P7 zero QA identity residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.audit_logs WHERE actor_user_id = v_adm;
  r := r || public._qa_s13_ok('N4R6.P8 zero QA audit residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_staple_purchase_options
   WHERE normalization_kind='exact' AND canonical_quantity > 0;
  r := r || public._qa_s13_ok('N4R6.P9 25 exact-normalizable production options', v_n = 25, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_staple_purchase_options
   WHERE normalization_kind <> 'exact';
  r := r || public._qa_s13_ok('N4R6.P10 4 honest non-exact production options', v_n = 4, v_n::text);

  RETURN public._qa_s13_summary(46, r);
END $$;
REVOKE ALL ON FUNCTION public._qa_node4_marche_r6() FROM PUBLIC, anon, authenticated;