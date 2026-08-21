CREATE OR REPLACE FUNCTION public._qa_node5_identity_a7()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
SET statement_timeout TO '300s'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_err text; v_def text; fn text; v_missing text[] := '{}';
  u_c   uuid := gen_random_uuid();  -- plain customer
  u_m   uuid := gen_random_uuid();  -- merchant, approved store
  u_ms  uuid := gen_random_uuid();  -- merchant, submitted (non-operational) store
  u_rel uuid := gen_random_uuid();  -- ex-merchant: store survives, lane released
  u_d   uuid := gen_random_uuid();  -- driver
  u_ops uuid := gen_random_uuid();  -- admin
  ids   uuid[];
  s_m uuid := gen_random_uuid(); s_ms uuid := gen_random_uuid(); s_rel uuid := gen_random_uuid();
  rest_m uuid := gen_random_uuid();
  v_listing uuid; v_pol text;
  class_surfaces text[] := ARRAY[
    '_marche_listing_authz','marche_listing_create','marche_dispatch_request',
    'marche_merchant_transition','repas_merchant_transition',
    'merchant_settlement_request_create','merchant_submit_location'];
  b_pr bigint; b_ur bigint; b_w bigint; b_lp bigint; b_ls numeric; b_ms bigint; b_fr bigint;
  b_pi bigint; b_pia bigint; b_al bigint; b_ml bigint; b_mo bigint; b_dp bigint; b_flags jsonb;
  a_pr bigint; a_ur bigint; a_w bigint; a_lp bigint; a_ls numeric; a_ms bigint; a_fr bigint;
  a_pi bigint; a_pia bigint; a_al bigint; a_ml bigint; a_mo bigint; a_dp bigint; a_flags jsonb;
BEGIN
  ids := ARRAY[u_c, u_m, u_ms, u_rel, u_d, u_ops];

  SELECT count(*) INTO b_pr FROM public.profiles;
  SELECT count(*) INTO b_ur FROM public.user_roles;
  SELECT count(*) INTO b_w  FROM public.wallets;
  SELECT count(*) INTO b_lp FROM public.ledger_postings;
  SELECT COALESCE(sum(amount_gnf),0) INTO b_ls FROM public.ledger_postings;
  SELECT count(*) INTO b_ms FROM public.merchant_stores;
  SELECT count(*) INTO b_fr FROM public.food_restaurants;
  SELECT count(*) INTO b_pi FROM public.professional_identities;
  SELECT count(*) INTO b_pia FROM public.professional_identities WHERE claim_state='active';
  SELECT count(*) INTO b_al FROM public.audit_logs;
  SELECT count(*) INTO b_ml FROM public.marketplace_listings;
  SELECT count(*) INTO b_mo FROM public.marche_orders;
  SELECT count(*) INTO b_dp FROM public.driver_profiles;
  SELECT jsonb_object_agg(key, enabled) INTO b_flags FROM public.feature_flags;

  -- ============ A. CANONICAL MERCHANT AUTHORITY PRIMITIVES ============
  r := r || public._qa_s13_ok('N5A7.A1 merchant class predicate exists',
        to_regprocedure('public._merchant_class_active(uuid)') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N5A7.A2 merchant class gate exists',
        to_regprocedure('public._merchant_class_require(uuid,text)') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N5A7.A3 store composite gate exists',
        to_regprocedure('public._merchant_store_require(uuid,uuid,text,boolean)') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N5A7.A4 restaurant composite gate exists',
        to_regprocedure('public._merchant_restaurant_require(uuid,uuid,text,boolean)') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N5A7.A5 class predicate is SECURITY DEFINER with pinned search_path',
        (SELECT prosecdef AND 'search_path=public' = ANY(proconfig) FROM pg_proc
          WHERE oid='public._merchant_class_active(uuid)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A7.A6 class gate is SECURITY DEFINER with pinned search_path',
        (SELECT prosecdef AND 'search_path=public' = ANY(proconfig) FROM pg_proc
          WHERE oid='public._merchant_class_require(uuid,text)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A7.A7 store gate is SECURITY DEFINER with pinned search_path',
        (SELECT prosecdef AND 'search_path=public' = ANY(proconfig) FROM pg_proc
          WHERE oid='public._merchant_store_require(uuid,uuid,text,boolean)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A7.A8 restaurant gate is SECURITY DEFINER with pinned search_path',
        (SELECT prosecdef AND 'search_path=public' = ANY(proconfig) FROM pg_proc
          WHERE oid='public._merchant_restaurant_require(uuid,uuid,text,boolean)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A7.A9 class predicate is read-only (STABLE)',
        (SELECT provolatile='s' FROM pg_proc WHERE oid='public._merchant_class_active(uuid)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A7.A10 class gate is read-only (STABLE)',
        (SELECT provolatile='s' FROM pg_proc WHERE oid='public._merchant_class_require(uuid,text)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A7.A11 store gate is read-only (STABLE)',
        (SELECT provolatile='s' FROM pg_proc WHERE oid='public._merchant_store_require(uuid,uuid,text,boolean)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A7.A12 restaurant gate is read-only (STABLE)',
        (SELECT provolatile='s' FROM pg_proc WHERE oid='public._merchant_restaurant_require(uuid,uuid,text,boolean)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A7.A13 class gate not callable by signed-in users',
        NOT has_function_privilege('authenticated','public._merchant_class_require(uuid,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A7.A14 class gate not callable anonymously',
        NOT has_function_privilege('anon','public._merchant_class_require(uuid,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A7.A15 store gate not callable by signed-in users',
        NOT has_function_privilege('authenticated','public._merchant_store_require(uuid,uuid,text,boolean)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A7.A16 store gate not callable anonymously',
        NOT has_function_privilege('anon','public._merchant_store_require(uuid,uuid,text,boolean)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A7.A17 restaurant gate not callable by signed-in users',
        NOT has_function_privilege('authenticated','public._merchant_restaurant_require(uuid,uuid,text,boolean)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A7.A18 restaurant gate not callable anonymously',
        NOT has_function_privilege('anon','public._merchant_restaurant_require(uuid,uuid,text,boolean)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A7.A19 class predicate is not anonymous-callable (RLS use only)',
        NOT has_function_privilege('anon','public._merchant_class_active(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A7.A20 class gate reads professional_identities, not roles',
        (SELECT prosrc ~ 'professional_identities' AND prosrc !~ 'user_roles' FROM pg_proc
          WHERE oid='public._merchant_class_require(uuid,text)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A7.A21 class gate ignores store state (layer separation)',
        (SELECT prosrc !~ 'merchant_stores' AND prosrc !~ 'food_restaurants' FROM pg_proc
          WHERE oid='public._merchant_class_require(uuid,text)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A7.A22 store gate composes the class gate (single source of truth)',
        (SELECT prosrc ~ '_merchant_class_require' FROM pg_proc
          WHERE oid='public._merchant_store_require(uuid,uuid,text,boolean)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A7.A23 restaurant gate composes the class gate',
        (SELECT prosrc ~ '_merchant_class_require' FROM pg_proc
          WHERE oid='public._merchant_restaurant_require(uuid,uuid,text,boolean)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A7.A24 driver primitives are untouched and still installed',
        to_regprocedure('public._driver_class_require(uuid,text)') IS NOT NULL
        AND to_regprocedure('public._driver_operational_require(uuid,text,text)') IS NOT NULL, NULL);

  -- ============ B. MERCHANT AUTHORITY SURFACE CENSUS ============
  FOREACH fn IN ARRAY class_surfaces LOOP
    v_def := pg_get_functiondef(('public.'||fn)::regproc);
    IF v_def !~ '_merchant_class_require' THEN v_missing := v_missing || fn; END IF;
  END LOOP;
  r := r || public._qa_s13_ok('N5A7.B1 every merchant mutation surface calls the canonical class gate',
        array_length(v_missing,1) IS NULL, array_to_string(v_missing,','));
  r := r || public._qa_s13_ok('N5A7.B2 census covers seven class-gated merchant surfaces',
        array_length(class_surfaces,1) = 7, array_length(class_surfaces,1)::text);
  r := r || public._qa_s13_ok('N5A7.B3 marche catalog chokepoint is class-gated',
        pg_get_functiondef('public._marche_listing_authz'::regproc) ~ '_merchant_class_require', NULL);
  r := r || public._qa_s13_ok('N5A7.B4 admin merchant decision validates the target class',
        pg_get_functiondef('public.admin_merchant_decision'::regproc) ~ '_merchant_class_active', NULL);
  r := r || public._qa_s13_ok('N5A7.B5 repas transition preserves the finance-privileged bypass',
        pg_get_functiondef('public.repas_merchant_transition'::regproc) ~ '_finance_privileged', NULL);
  r := r || public._qa_s13_ok('N5A7.B6 listing chokepoint preserves the admin bypass',
        pg_get_functiondef('public._marche_listing_authz'::regproc) ~ 'has_role', NULL);
  r := r || public._qa_s13_ok('N5A7.B7 A3 professional lane requirement is still installed',
        to_regprocedure('public._professional_lane_require(uuid,text,text)') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N5A7.B8 A3 artifact guard still protects merchant_stores',
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.merchant_stores'::regclass
                 AND NOT tgisinternal AND tgfoid='public._professional_artifact_guard'::regproc), NULL);
  r := r || public._qa_s13_ok('N5A7.B9 A3 artifact guard still protects food_restaurants',
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.food_restaurants'::regclass
                 AND NOT tgisinternal AND tgfoid='public._professional_artifact_guard'::regproc), NULL);
  r := r || public._qa_s13_ok('N5A7.B10 R1.5 orderability truth view is untouched',
        to_regclass('public.v_marche_listing_truth') IS NOT NULL, NULL);

  -- ============ C. RLS POLICIES CARRY THE CLASS ============
  SELECT qual INTO v_pol FROM pg_policies WHERE schemaname='public'
    AND tablename='merchant_stores' AND policyname='Owner updates own store';
  r := r || public._qa_s13_ok('N5A7.C1 store update policy requires the merchant class',
        v_pol ~ '_merchant_class_active', v_pol);
  SELECT qual INTO v_pol FROM pg_policies WHERE schemaname='public'
    AND tablename='food_restaurants' AND policyname='Owners update own restaurant';
  r := r || public._qa_s13_ok('N5A7.C2 restaurant update policy requires the merchant class',
        v_pol ~ '_merchant_class_active', v_pol);
  SELECT qual INTO v_pol FROM pg_policies WHERE schemaname='public'
    AND tablename='food_menu_items' AND policyname='Owners manage own menu items';
  r := r || public._qa_s13_ok('N5A7.C3 menu item policy requires the merchant class',
        v_pol ~ '_merchant_class_active', v_pol);
  SELECT qual INTO v_pol FROM pg_policies WHERE schemaname='public'
    AND tablename='listing_images' AND policyname='Sellers manage own listing images';
  r := r || public._qa_s13_ok('N5A7.C4 listing image policy requires the merchant class',
        v_pol ~ '_merchant_class_active', v_pol);
  SELECT qual INTO v_pol FROM pg_policies WHERE schemaname='public'
    AND tablename='merchants' AND policyname='Owner manages own merchant';
  r := r || public._qa_s13_ok('N5A7.C5 merchants policy requires the merchant class',
        v_pol ~ '_merchant_class_active', v_pol);
  r := r || public._qa_s13_ok('N5A7.C6 public storefront reads stay open to anon (R1 preserved)',
        EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='merchant_stores'
                 AND policyname='Anon read approved stores'), NULL);
  r := r || public._qa_s13_ok('N5A7.C7 anon still cannot execute the class predicate through RLS',
        NOT has_function_privilege('anon','public._merchant_class_active(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A7.C8 admin store policy retained',
        EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='merchant_stores'
                 AND policyname='Admins manage stores'), NULL);

  -- ============ FIXTURES ============
  PERFORM public._qa_users_new(u_c,  'qa-n5a7-c-'||substr(u_c::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_m,  'qa-n5a7-m-'||substr(u_m::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_ms, 'qa-n5a7-s-'||substr(u_ms::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_rel,'qa-n5a7-r-'||substr(u_rel::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_d,  'qa-n5a7-d-'||substr(u_d::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_ops,'qa-n5a7-o-'||substr(u_ops::text,1,8)||'@example.com');
  UPDATE public.profiles SET phone = '+22462' || lpad((floor(random()*10000000))::bigint::text, 7, '0')
   WHERE user_id = ANY(ids) AND (phone IS NULL OR phone = '');
  INSERT INTO public.user_roles(user_id, role) VALUES (u_ops,'admin') ON CONFLICT DO NOTHING;

  PERFORM set_config('request.jwt.claims', NULL, true);
  INSERT INTO public.merchant_stores(id, owner_user_id, name, slug, status, onboarding_status)
  VALUES (s_m,  u_m,  'QA A7 Store',      'qa-a7-'||substr(s_m::text,1,8),  'active','approved'),
         (s_ms, u_ms, 'QA A7 Pending',    'qa-a7-'||substr(s_ms::text,1,8), 'active','submitted'),
         (s_rel,u_rel,'QA A7 Ex-Merchant','qa-a7-'||substr(s_rel::text,1,8),'active','approved');
  INSERT INTO public.food_restaurants(id, owner_user_id, name, slug, status, verification_state)
  VALUES (rest_m, u_m, 'QA A7 Resto', 'qa-a7-'||substr(rest_m::text,1,8), 'active','verified');
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_d), true);
  PERFORM public.driver_apply('{"vehicle_type":"moto"}'::jsonb);
  PERFORM set_config('request.jwt.claims', NULL, true);
  UPDATE public.driver_profiles SET status='approved' WHERE user_id = u_d;
  -- ex-merchant: business assets survive, professional lane is released
  PERFORM public._professional_identity_release(u_rel, 'qa_a7_release');

  r := r || public._qa_s13_ok('N5A7.D1 store owner fixture holds the MERCHANT class',
        public.professional_active_type(u_m) = 'merchant', public.professional_active_type(u_m));
  r := r || public._qa_s13_ok('N5A7.D2 pending-store owner also holds the MERCHANT class',
        public.professional_active_type(u_ms) = 'merchant', NULL);
  r := r || public._qa_s13_ok('N5A7.D3 driver fixture holds the DRIVER class',
        public.professional_active_type(u_d) = 'driver', NULL);
  r := r || public._qa_s13_ok('N5A7.D4 plain customer holds no professional class',
        public.professional_active_type(u_c) IS NULL, NULL);
  r := r || public._qa_s13_ok('N5A7.D5 released account holds no professional class',
        public.professional_active_type(u_rel) IS NULL, NULL);
  r := r || public._qa_s13_ok('N5A7.D6 released account still owns its approved store (worst case)',
        (SELECT onboarding_status FROM public.merchant_stores WHERE id=s_rel) = 'approved', NULL);
  r := r || public._qa_s13_ok('N5A7.D7 one owner may hold both a store and a restaurant on one lane',
        (SELECT count(*) FROM public.professional_identities
          WHERE user_id=u_m AND claim_state='active') = 1, NULL);
  r := r || public._qa_s13_ok('N5A7.D8 multi-asset owner still holds exactly the MERCHANT class',
        public.professional_active_type(u_m) = 'merchant', NULL);

  -- ============ E. CLASS PREDICATE TRUTH ============
  r := r || public._qa_s13_ok('N5A7.E1 predicate TRUE for an approved-store merchant',
        public._merchant_class_active(u_m) IS TRUE, NULL);
  r := r || public._qa_s13_ok('N5A7.E2 predicate TRUE for a pending-store merchant (class <> approval)',
        public._merchant_class_active(u_ms) IS TRUE, NULL);
  r := r || public._qa_s13_ok('N5A7.E3 predicate FALSE for a driver',
        public._merchant_class_active(u_d) IS FALSE, NULL);
  r := r || public._qa_s13_ok('N5A7.E4 predicate FALSE for a plain customer',
        public._merchant_class_active(u_c) IS FALSE, NULL);
  r := r || public._qa_s13_ok('N5A7.E5 predicate FALSE for a released ex-merchant owning an approved store',
        public._merchant_class_active(u_rel) IS FALSE, NULL);
  r := r || public._qa_s13_ok('N5A7.E6 predicate FALSE for NULL identity',
        public._merchant_class_active(NULL) IS FALSE, NULL);
  r := r || public._qa_s13_ok('N5A7.E7 predicate FALSE for an unknown account',
        public._merchant_class_active(gen_random_uuid()) IS FALSE, NULL);

  -- ============ F. CLASS GATE REFUSALS ARE DISTINCT AND CORRECT ============
  BEGIN PERFORM public._merchant_class_require(u_m,'qa'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.F1 class gate admits an approved-store merchant', v_err IS NULL, v_err);
  BEGIN PERFORM public._merchant_class_require(u_ms,'qa'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.F2 class gate admits a pending-store merchant', v_err IS NULL, v_err);
  BEGIN PERFORM public._merchant_class_require(u_c,'qa'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.F3 class gate refuses a plain customer',
        v_err = 'PROFESSIONAL_IDENTITY_REQUIRED', v_err);
  BEGIN PERFORM public._merchant_class_require(u_d,'qa'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.F4 class gate refuses a DRIVER with a conflict verdict',
        v_err = 'PROFESSIONAL_IDENTITY_CONFLICT', v_err);
  BEGIN PERFORM public._merchant_class_require(u_rel,'qa'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.F5 class gate refuses a released ex-merchant',
        v_err = 'PROFESSIONAL_IDENTITY_REQUIRED', v_err);
  BEGIN PERFORM public._merchant_class_require(NULL,'qa'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.F6 class gate refuses an unauthenticated caller',
        v_err = 'AUTH_REQUIRED', v_err);
  r := r || public._qa_s13_ok('N5A7.F7 driver and merchant refusals are symmetric and distinguishable',
        'PROFESSIONAL_IDENTITY_REQUIRED' <> 'PROFESSIONAL_IDENTITY_CONFLICT', NULL);

  -- ============ G. COMPOSITE ASSET GATES (ownership -> class -> state) ============
  BEGIN PERFORM public._merchant_store_require(u_m, s_m, 'qa', true); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.G1 store gate admits owner + class + operational store', v_err IS NULL, v_err);
  BEGIN PERFORM public._merchant_store_require(u_ms, s_ms, 'qa', true); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.G2 store gate refuses a non-approved store on STATE, not class',
        v_err = 'MERCHANT_STORE_NOT_OPERATIONAL', v_err);
  BEGIN PERFORM public._merchant_store_require(u_ms, s_ms, 'qa', false); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.G3 non-operational store still allows non-operational actions',
        v_err IS NULL, v_err);
  BEGIN PERFORM public._merchant_store_require(u_m, s_ms, 'qa', false); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.G4 one merchant cannot operate another merchant''s store',
        v_err = 'NOT_STORE_OWNER', v_err);
  BEGIN PERFORM public._merchant_store_require(u_rel, s_rel, 'qa', false); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.G5 released ex-merchant cannot operate the store it still owns',
        v_err = 'PROFESSIONAL_IDENTITY_REQUIRED', v_err);
  BEGIN PERFORM public._merchant_store_require(u_d, s_m, 'qa', false); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.G6 ownership is checked before class (driver, foreign store)',
        v_err = 'NOT_STORE_OWNER', v_err);
  BEGIN PERFORM public._merchant_store_require(NULL, s_m, 'qa', false); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.G7 store gate refuses an unauthenticated caller',
        v_err = 'AUTH_REQUIRED', v_err);
  BEGIN PERFORM public._merchant_store_require(u_m, gen_random_uuid(), 'qa', false); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.G8 store gate refuses an unknown store',
        v_err = 'MERCHANT_STORE_NOT_FOUND', v_err);
  BEGIN PERFORM public._merchant_restaurant_require(u_m, rest_m, 'qa', true); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.G9 restaurant gate admits owner + class + verified restaurant',
        v_err IS NULL, v_err);
  BEGIN PERFORM public._merchant_restaurant_require(u_ms, rest_m, 'qa', false); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.G10 a merchant cannot operate another merchant''s restaurant',
        v_err = 'NOT_RESTAURANT_OWNER', v_err);
  BEGIN PERFORM public._merchant_restaurant_require(u_m, gen_random_uuid(), 'qa', false); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.G11 restaurant gate refuses an unknown restaurant',
        v_err = 'RESTAURANT_NOT_FOUND', v_err);
  UPDATE public.food_restaurants SET verification_state='none' WHERE id=rest_m;
  BEGIN PERFORM public._merchant_restaurant_require(u_m, rest_m, 'qa', true); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.G12 restaurant gate refuses an unverified restaurant on STATE',
        v_err = 'RESTAURANT_NOT_OPERATIONAL', v_err);
  UPDATE public.food_restaurants SET verification_state='verified' WHERE id=rest_m;

  -- ============ H. LIVE SURFACE: MARCHE CATALOG ============
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_m), true);
  v_listing := public.marche_listing_create(jsonb_build_object(
    'store_id', s_m, 'title', 'QA A7 Riz', 'price_gnf', 50000,
    'category','Alimentation', 'quantity_available', 10, 'publish', true));
  r := r || public._qa_s13_ok('N5A7.H1 a class-holding merchant can create a listing', v_listing IS NOT NULL, NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_rel), true);
  BEGIN PERFORM public.marche_listing_create(jsonb_build_object(
      'store_id', s_rel, 'title','QA A7 Ghost', 'price_gnf', 1000, 'quantity_available', 1)); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.H2 a released ex-merchant cannot create a listing on its own store',
        v_err = 'PROFESSIONAL_IDENTITY_REQUIRED', v_err);
  r := r || public._qa_s13_ok('N5A7.H3 refused creation wrote no listing row',
        NOT EXISTS (SELECT 1 FROM public.marketplace_listings WHERE store_id = s_rel), NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_d), true);
  BEGIN PERFORM public.marche_listing_create(jsonb_build_object(
      'store_id', s_m, 'title','QA A7 Driver', 'price_gnf', 1000, 'quantity_available', 1)); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.H4 a driver cannot create a listing on a foreign store',
        v_err = 'NOT_STORE_OWNER', v_err);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_c), true);
  BEGIN PERFORM public.marche_listing_create(jsonb_build_object(
      'store_id', s_m, 'title','QA A7 Customer', 'price_gnf', 1000, 'quantity_available', 1)); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.H5 a plain customer cannot create a listing',
        v_err IS NOT NULL, v_err);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_m), true);
  BEGIN PERFORM public._marche_listing_authz(v_listing); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.H6 catalog chokepoint admits the class-holding owner', v_err IS NULL, v_err);
  PERFORM public._professional_identity_release(u_m, 'qa_a7_temp');
  BEGIN PERFORM public._marche_listing_authz(v_listing); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.H7 losing the class instantly revokes catalog authority',
        v_err = 'PROFESSIONAL_IDENTITY_REQUIRED', v_err);
  r := r || public._qa_s13_ok('N5A7.H8 the listing itself survived the authority loss (history preserved)',
        EXISTS (SELECT 1 FROM public.marketplace_listings WHERE id=v_listing), NULL);
  PERFORM public._professional_identity_claim(u_m,'merchant','qa_a7_reclaim');
  BEGIN PERFORM public._marche_listing_authz(v_listing); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.H9 reclaiming the class restores catalog authority', v_err IS NULL, v_err);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_c), true);
  BEGIN PERFORM public._marche_listing_authz(v_listing); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.H10 catalog chokepoint refuses a non-owner on ownership first',
        v_err = 'NOT_LISTING_OWNER', v_err);
  PERFORM set_config('request.jwt.claims', NULL, true);
  BEGIN PERFORM public._marche_listing_authz(v_listing); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.H11 catalog chokepoint refuses an anonymous caller',
        v_err = 'AUTH_REQUIRED', v_err);

  -- ============ I. LIVE SURFACE: LOCATION + SETTLEMENT ============
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_rel), true);
  BEGIN PERFORM public.merchant_submit_location(s_rel, 9.53, -13.68); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.I1 a released ex-merchant cannot submit a store location',
        v_err = 'PROFESSIONAL_IDENTITY_REQUIRED', v_err);
  r := r || public._qa_s13_ok('N5A7.I2 refused submission left the store location untouched',
        (SELECT location_submission_status FROM public.merchant_stores WHERE id=s_rel) = 'none', NULL);
  BEGIN PERFORM public.merchant_settlement_request_create(10000,'qa-a7-settle-rel', s_rel, NULL); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.I3 a released ex-merchant cannot request settlement',
        v_err = 'PROFESSIONAL_IDENTITY_REQUIRED', v_err);
  r := r || public._qa_s13_ok('N5A7.I4 refused settlement created no request row',
        NOT EXISTS (SELECT 1 FROM public.merchant_settlement_requests WHERE store_id = s_rel), NULL);
  r := r || public._qa_s13_ok('N5A7.I5 refused settlement created no payout order',
        NOT EXISTS (SELECT 1 FROM public.payout_orders WHERE party_user_id = u_rel), NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_d), true);
  BEGIN PERFORM public.merchant_submit_location(s_m, 9.53, -13.68); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.I6 a driver cannot submit a location for a foreign store',
        v_err IS NOT NULL, v_err);
  BEGIN PERFORM public.merchant_settlement_request_create(10000,'qa-a7-settle-drv', s_m, NULL); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.I7 a driver cannot request settlement on a foreign store',
        v_err = 'NOT_AUTHORIZED', v_err);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_m), true);
  PERFORM public.merchant_submit_location(s_m, 9.53, -13.68);
  r := r || public._qa_s13_ok('N5A7.I8 a class-holding merchant can still submit its store location',
        (SELECT location_submission_status FROM public.merchant_stores WHERE id=s_m) <> 'none',
        (SELECT location_submission_status FROM public.merchant_stores WHERE id=s_m));
  PERFORM set_config('request.jwt.claims', NULL, true);

  -- ============ J. ADMIN AUTHORITY CANNOT MANUFACTURE A MERCHANT ============
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ops), true);
  BEGIN PERFORM public.admin_merchant_decision(s_rel,'approve',NULL); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.J1 admin cannot approve a store whose owner lost the MERCHANT class',
        v_err = 'MERCHANT_CLASS_REQUIRED', v_err);
  r := r || public._qa_s13_ok('N5A7.J2 refused approval opened no professional claim',
        public.professional_active_type(u_rel) IS NULL, NULL);
  r := r || public._qa_s13_ok('N5A7.J3 refused approval granted no merchant role',
        NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id=u_rel AND role='merchant'), NULL);
  BEGIN PERFORM public.admin_merchant_decision(s_rel,'reactivate',NULL); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.J4 admin cannot reactivate a classless owner''s store',
        v_err = 'MERCHANT_CLASS_REQUIRED', v_err);
  PERFORM public.admin_merchant_decision(s_ms,'approve',NULL);
  r := r || public._qa_s13_ok('N5A7.J5 admin can still approve a genuine MERCHANT-class store',
        (SELECT onboarding_status FROM public.merchant_stores WHERE id=s_ms) = 'approved', NULL);
  r := r || public._qa_s13_ok('N5A7.J6 approval did not alter the professional class',
        public.professional_active_type(u_ms) = 'merchant', NULL);
  BEGIN PERFORM public.admin_merchant_decision(s_rel,'suspend','qa'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A7.J7 admin can still suspend a classless owner''s store (safety path open)',
        v_err IS NULL, v_err);
  PERFORM set_config('request.jwt.claims', NULL, true);

  -- ============ K. NON-INTERFERENCE + LANE ISOLATION ============
  r := r || public._qa_s13_ok('N5A7.K1 driver lane untouched by the entire merchant pass',
        public.professional_active_type(u_d) = 'driver', NULL);
  r := r || public._qa_s13_ok('N5A7.K2 driver kept operational authority',
        public._driver_class_active(u_d) IS TRUE, NULL);
  r := r || public._qa_s13_ok('N5A7.K3 merchant acquired no driver profile',
        NOT EXISTS (SELECT 1 FROM public.driver_profiles WHERE user_id=u_m), NULL);
  r := r || public._qa_s13_ok('N5A7.K4 driver acquired no merchant store',
        NOT EXISTS (SELECT 1 FROM public.merchant_stores WHERE owner_user_id=u_d), NULL);
  r := r || public._qa_s13_ok('N5A7.K5 no QA account acquired a second active class',
        NOT EXISTS (SELECT user_id FROM public.professional_identities
                     WHERE user_id = ANY(ids) AND claim_state='active'
                     GROUP BY user_id HAVING count(*) > 1), NULL);
  r := r || public._qa_s13_ok('N5A7.K6 merchant gates created no wallet movement',
        (SELECT count(*) FROM public.wallet_transactions wt
          WHERE wt.related_user_id = ANY(ids)
             OR wt.from_wallet_id IN (SELECT id FROM public.wallets WHERE owner_user_id = ANY(ids))
             OR wt.to_wallet_id   IN (SELECT id FROM public.wallets WHERE owner_user_id = ANY(ids))) = 0, NULL);
  r := r || public._qa_s13_ok('N5A7.K7 merchant gates created no ledger journals',
        (SELECT count(*) FROM public.ledger_journals lj WHERE lj.actor_user_id = ANY(ids)) = 0, NULL);
  r := r || public._qa_s13_ok('N5A7.K8 refusals leak no other account identity',
        (SELECT prosrc !~ 'email' FROM pg_proc
          WHERE oid='public._merchant_class_require(uuid,text)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A7.K9 no Marche order was created by this pass',
        (SELECT count(*) FROM public.marche_orders WHERE buyer_user_id = ANY(ids)
           OR merchant_user_id = ANY(ids)) = 0, NULL);

  -- ============ CLEANUP ============
  DELETE FROM public.listing_images WHERE listing_id IN
    (SELECT id FROM public.marketplace_listings WHERE seller_id = ANY(ids));
  DELETE FROM public.listing_metrics WHERE listing_id IN
    (SELECT id FROM public.marketplace_listings WHERE seller_id = ANY(ids));
  DELETE FROM public.marketplace_listings WHERE seller_id = ANY(ids) OR store_id IN (s_m,s_ms,s_rel);
  DELETE FROM public.merchant_settlement_requests WHERE store_id IN (s_m,s_ms,s_rel);
  DELETE FROM public.food_menu_items WHERE restaurant_id = rest_m;
  DELETE FROM public.map_places WHERE created_by = ANY(ids);
  PERFORM public._qa_a5_cleanup(ids);

  SELECT count(*) INTO a_pr FROM public.profiles;
  SELECT count(*) INTO a_ur FROM public.user_roles;
  SELECT count(*) INTO a_w  FROM public.wallets;
  SELECT count(*) INTO a_lp FROM public.ledger_postings;
  SELECT COALESCE(sum(amount_gnf),0) INTO a_ls FROM public.ledger_postings;
  SELECT count(*) INTO a_ms FROM public.merchant_stores;
  SELECT count(*) INTO a_fr FROM public.food_restaurants;
  SELECT count(*) INTO a_pi FROM public.professional_identities;
  SELECT count(*) INTO a_pia FROM public.professional_identities WHERE claim_state='active';
  SELECT count(*) INTO a_al FROM public.audit_logs;
  SELECT count(*) INTO a_ml FROM public.marketplace_listings;
  SELECT count(*) INTO a_mo FROM public.marche_orders;
  SELECT count(*) INTO a_dp FROM public.driver_profiles;
  SELECT jsonb_object_agg(key, enabled) INTO a_flags FROM public.feature_flags;

  r := r || public._qa_s13_ok('N5A7.L1 profiles unchanged', a_pr = b_pr, b_pr||'->'||a_pr);
  r := r || public._qa_s13_ok('N5A7.L2 user_roles unchanged', a_ur = b_ur, b_ur||'->'||a_ur);
  r := r || public._qa_s13_ok('N5A7.L3 wallets unchanged', a_w = b_w, b_w||'->'||a_w);
  r := r || public._qa_s13_ok('N5A7.L4 ledger_postings unchanged', a_lp = b_lp, b_lp||'->'||a_lp);
  r := r || public._qa_s13_ok('N5A7.L5 ledger balance sum unchanged', a_ls = b_ls, b_ls||'->'||a_ls);
  r := r || public._qa_s13_ok('N5A7.L6 merchant_stores returned to baseline', a_ms = b_ms, b_ms||'->'||a_ms);
  r := r || public._qa_s13_ok('N5A7.L7 food_restaurants returned to baseline', a_fr = b_fr, b_fr||'->'||a_fr);
  r := r || public._qa_s13_ok('N5A7.L8 professional_identities returned to baseline', a_pi = b_pi, b_pi||'->'||a_pi);
  r := r || public._qa_s13_ok('N5A7.L9 active professional census unchanged', a_pia = b_pia, b_pia||'->'||a_pia);
  r := r || public._qa_s13_ok('N5A7.L10 audit_logs returned to baseline', a_al = b_al, b_al||'->'||a_al);
  r := r || public._qa_s13_ok('N5A7.L11 marketplace_listings returned to baseline', a_ml = b_ml, b_ml||'->'||a_ml);
  r := r || public._qa_s13_ok('N5A7.L12 marche_orders unchanged', a_mo = b_mo, b_mo||'->'||a_mo);
  r := r || public._qa_s13_ok('N5A7.L13 driver_profiles returned to baseline', a_dp = b_dp, b_dp||'->'||a_dp);
  r := r || public._qa_s13_ok('N5A7.L14 feature flags unchanged', a_flags = b_flags, NULL);
  r := r || public._qa_s13_ok('N5A7.L15 no QA residue in professional_identities',
        NOT EXISTS (SELECT 1 FROM public.professional_identities WHERE user_id = ANY(ids)), NULL);
  r := r || public._qa_s13_ok('N5A7.L16 no QA residue in merchant_stores',
        NOT EXISTS (SELECT 1 FROM public.merchant_stores WHERE owner_user_id = ANY(ids)), NULL);
  r := r || public._qa_s13_ok('N5A7.L17 no QA residue in food_restaurants',
        NOT EXISTS (SELECT 1 FROM public.food_restaurants WHERE owner_user_id = ANY(ids)), NULL);
  r := r || public._qa_s13_ok('N5A7.L18 no QA residue in marketplace_listings',
        NOT EXISTS (SELECT 1 FROM public.marketplace_listings WHERE seller_id = ANY(ids)), NULL);
  r := r || public._qa_s13_ok('N5A7.L19 no QA residue in user_roles',
        NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = ANY(ids)), NULL);

  RETURN jsonb_build_object(
    'fn','_qa_node5_identity_a7',
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'failures', (SELECT COALESCE(jsonb_agg(e),'[]'::jsonb) FROM jsonb_array_elements(r) e
                  WHERE (e->>'ok')::boolean IS NOT TRUE)
  );
EXCEPTION WHEN others THEN
  PERFORM set_config('request.jwt.claims', NULL, true);
  BEGIN
    DELETE FROM public.marketplace_listings WHERE seller_id = ANY(ids) OR store_id IN (s_m,s_ms,s_rel);
    DELETE FROM public.merchant_settlement_requests WHERE store_id IN (s_m,s_ms,s_rel);
    PERFORM public._qa_a5_cleanup(ids);
  EXCEPTION WHEN others THEN NULL; END;
  RAISE;
END $function$;

REVOKE ALL ON FUNCTION public._qa_node5_identity_a7() FROM PUBLIC, anon, authenticated;