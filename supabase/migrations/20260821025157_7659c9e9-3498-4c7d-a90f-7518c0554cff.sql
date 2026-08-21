CREATE OR REPLACE FUNCTION public._qa_node5_identity_a6()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' SET statement_timeout TO '300s'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_err text; v_def text; fn text; v_missing text[] := '{}';
  u_c   uuid := gen_random_uuid();  -- plain customer
  u_d   uuid := gen_random_uuid();  -- approved driver
  u_p   uuid := gen_random_uuid();  -- pending driver
  u_rel uuid := gen_random_uuid();  -- ex-driver: profile remains, lane released
  u_m   uuid := gen_random_uuid();  -- merchant
  u_ops uuid := gen_random_uuid();  -- ops admin
  ids   uuid[];
  b_pr bigint; b_ur bigint; b_w bigint; b_lp bigint; b_ls numeric; b_dp bigint;
  b_pi bigint; b_pia bigint; b_al bigint; b_mi bigint; b_ri bigint; b_ms bigint; b_flags jsonb;
  a_pr bigint; a_ur bigint; a_w bigint; a_lp bigint; a_ls numeric; a_dp bigint;
  a_pi bigint; a_pia bigint; a_al bigint; a_mi bigint; a_ri bigint; a_ms bigint; a_flags jsonb;
  class_surfaces text[] := ARRAY[
    'driver_set_status','driver_offer_accept','driver_offer_decline','driver_update_location_signal',
    'ride_accept','ride_start','ride_complete','ride_set_phase',
    'mission_set_state','mission_confirm_pickup','mission_confirm_dropoff',
    'mission_confirm_pickup_with_proof','mission_confirm_dropoff_with_proof','mission_report_issue',
    'repas_custody_confirm_handoff','repas_custody_confirm_delivery',
    'package_verify_pickup','package_verify_delivery',
    'marche_courier_transition','_marche_pm_shopper_lock'];
  op_surfaces text[] := ARRAY['mission_claim','marche_shopper_claim'];
BEGIN
  ids := ARRAY[u_c, u_d, u_p, u_rel, u_m, u_ops];

  SELECT count(*) INTO b_pr FROM public.profiles;
  SELECT count(*) INTO b_ur FROM public.user_roles;
  SELECT count(*) INTO b_w  FROM public.wallets;
  SELECT count(*) INTO b_lp FROM public.ledger_postings;
  SELECT COALESCE(sum(amount_gnf),0) INTO b_ls FROM public.ledger_postings;
  SELECT count(*) INTO b_dp FROM public.driver_profiles;
  SELECT count(*) INTO b_pi FROM public.professional_identities;
  SELECT count(*) INTO b_pia FROM public.professional_identities WHERE claim_state='active';
  SELECT count(*) INTO b_al FROM public.audit_logs;
  SELECT count(*) INTO b_mi FROM public.missions;
  SELECT count(*) INTO b_ri FROM public.rides;
  SELECT count(*) INTO b_ms FROM public.merchant_stores;
  SELECT jsonb_object_agg(key, enabled) INTO b_flags FROM public.feature_flags;

  -- ================= A. CANONICAL AUTHORITY PRIMITIVE EXISTS =================
  r := r || public._qa_s13_ok('N5A6.A1 canonical class predicate exists',
        to_regprocedure('public._driver_class_active(uuid)') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N5A6.A2 canonical class gate exists',
        to_regprocedure('public._driver_class_require(uuid,text)') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N5A6.A3 canonical operational gate exists',
        to_regprocedure('public._driver_operational_require(uuid,text,text)') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N5A6.A4 class predicate is SECURITY DEFINER with pinned search_path',
        (SELECT prosecdef AND 'search_path=public' = ANY(proconfig) FROM pg_proc
          WHERE oid='public._driver_class_active(uuid)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A6.A5 class gate is SECURITY DEFINER with pinned search_path',
        (SELECT prosecdef AND 'search_path=public' = ANY(proconfig) FROM pg_proc
          WHERE oid='public._driver_class_require(uuid,text)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A6.A6 operational gate is SECURITY DEFINER with pinned search_path',
        (SELECT prosecdef AND 'search_path=public' = ANY(proconfig) FROM pg_proc
          WHERE oid='public._driver_operational_require(uuid,text,text)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A6.A7 class predicate is read-only (STABLE)',
        (SELECT provolatile='s' FROM pg_proc WHERE oid='public._driver_class_active(uuid)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A6.A8 class gate is read-only (STABLE)',
        (SELECT provolatile='s' FROM pg_proc WHERE oid='public._driver_class_require(uuid,text)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A6.A9 operational gate is read-only (STABLE)',
        (SELECT provolatile='s' FROM pg_proc WHERE oid='public._driver_operational_require(uuid,text,text)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A6.A10 class predicate not callable by signed-in users',
        NOT has_function_privilege('authenticated','public._driver_class_active(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A6.A11 class predicate not callable anonymously',
        NOT has_function_privilege('anon','public._driver_class_active(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A6.A12 class gate not callable by signed-in users',
        NOT has_function_privilege('authenticated','public._driver_class_require(uuid,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A6.A13 class gate not callable anonymously',
        NOT has_function_privilege('anon','public._driver_class_require(uuid,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A6.A14 operational gate not callable by signed-in users',
        NOT has_function_privilege('authenticated','public._driver_operational_require(uuid,text,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A6.A15 operational gate not callable anonymously',
        NOT has_function_privilege('anon','public._driver_operational_require(uuid,text,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A6.A16 class gate reads professional_identities, not roles',
        v_def IS NULL AND (SELECT prosrc ~ 'professional_identities' AND prosrc !~ 'user_roles'
                             FROM pg_proc WHERE oid='public._driver_class_require(uuid,text)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A6.A17 class gate ignores driver_profiles status (layer separation)',
        (SELECT prosrc !~ 'driver_profiles' FROM pg_proc
          WHERE oid='public._driver_class_require(uuid,text)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A6.A18 class gate ignores capabilities (layer separation)',
        (SELECT prosrc !~ 'capabilit' FROM pg_proc
          WHERE oid='public._driver_class_require(uuid,text)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A6.A19 operational gate composes the class gate (single source of truth)',
        (SELECT prosrc ~ '_driver_class_require' FROM pg_proc
          WHERE oid='public._driver_operational_require(uuid,text,text)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A6.A20 operational gate consults driver_profiles status',
        (SELECT prosrc ~ 'driver_profiles' FROM pg_proc
          WHERE oid='public._driver_operational_require(uuid,text,text)'::regprocedure), NULL);

  -- ================= B. AUTHORITY SURFACE CENSUS (no surface left ungated) =================
  FOREACH fn IN ARRAY class_surfaces LOOP
    v_def := pg_get_functiondef(('public.'||fn)::regproc);
    IF v_def !~ '_driver_class_require' THEN v_missing := v_missing || fn; END IF;
  END LOOP;
  r := r || public._qa_s13_ok('N5A6.B1 every in-flight driver surface calls the canonical class gate',
        array_length(v_missing,1) IS NULL, array_to_string(v_missing,','));
  r := r || public._qa_s13_ok('N5A6.B2 census covers twenty class-gated surfaces',
        array_length(class_surfaces,1) = 20, array_length(class_surfaces,1)::text);

  v_missing := '{}';
  FOREACH fn IN ARRAY op_surfaces LOOP
    v_def := pg_get_functiondef(('public.'||fn)::regproc);
    IF v_def !~ '_driver_operational_require' THEN v_missing := v_missing || fn; END IF;
  END LOOP;
  r := r || public._qa_s13_ok('N5A6.B3 every work-acquisition surface calls the operational gate',
        array_length(v_missing,1) IS NULL, array_to_string(v_missing,','));
  r := r || public._qa_s13_ok('N5A6.B4 driver_set_status is class-gated',
        pg_get_functiondef('public.driver_set_status'::regproc) ~ '_driver_class_require', NULL);
  r := r || public._qa_s13_ok('N5A6.B5 driver_admin_decide validates the target class',
        pg_get_functiondef('public.driver_admin_decide'::regproc) ~ '_driver_class_active', NULL);
  r := r || public._qa_s13_ok('N5A6.B6 ride_dispatch is class-aware when selecting candidates',
        pg_get_functiondef('public.ride_dispatch'::regproc) ~ '_driver_class_active', NULL);
  r := r || public._qa_s13_ok('N5A6.B7 marche shopper mutation lock is class-gated',
        pg_get_functiondef('public._marche_pm_shopper_lock'::regproc) ~ '_driver_class_require', NULL);
  r := r || public._qa_s13_ok('N5A6.B8 A5 capability lane gate is still installed (not replaced)',
        to_regprocedure('public._driver_capability_lane_gate(uuid)') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N5A6.B9 A3 professional lane requirement is still installed',
        to_regprocedure('public._professional_lane_require(uuid,text,text)') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N5A6.B10 driver_profiles still carries the A5 capability guard trigger',
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.driver_profiles'::regclass
                 AND tgname='driver_capability_guard' AND NOT tgisinternal), NULL);

  -- ================= FIXTURES =================
  PERFORM public._qa_users_new(u_c,  'qa-n5a6-c-'||substr(u_c::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_d,  'qa-n5a6-d-'||substr(u_d::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_p,  'qa-n5a6-p-'||substr(u_p::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_rel,'qa-n5a6-r-'||substr(u_rel::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_m,  'qa-n5a6-m-'||substr(u_m::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_ops,'qa-n5a6-o-'||substr(u_ops::text,1,8)||'@example.com');
  PERFORM set_config('request.jwt.claims', NULL, true);
  INSERT INTO public.admin_users(user_id, admin_role, status)
  VALUES (u_ops,'operations_admin','active') ON CONFLICT DO NOTHING;

  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_d), true);
  PERFORM public.driver_apply('{"vehicle_type":"moto"}'::jsonb);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_p), true);
  PERFORM public.driver_apply('{"vehicle_type":"moto"}'::jsonb);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_rel), true);
  PERFORM public.driver_apply('{"vehicle_type":"moto"}'::jsonb);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_m), true);
  INSERT INTO public.merchants(owner_user_id, name) VALUES (u_m, 'QA A6 Merchant');
  PERFORM set_config('request.jwt.claims', NULL, true);
  UPDATE public.driver_profiles SET status='approved' WHERE user_id IN (u_d, u_rel);
  -- ex-driver: operational artifact survives, professional lane is released
  PERFORM public._professional_identity_release(u_rel, 'qa_a6_release');

  r := r || public._qa_s13_ok('N5A6.C1 approved driver fixture holds the DRIVER class',
        public.professional_active_type(u_d) = 'driver', public.professional_active_type(u_d));
  r := r || public._qa_s13_ok('N5A6.C2 pending driver fixture holds the DRIVER class',
        public.professional_active_type(u_p) = 'driver', NULL);
  r := r || public._qa_s13_ok('N5A6.C3 merchant fixture holds the MERCHANT class',
        public.professional_active_type(u_m) = 'merchant', NULL);
  r := r || public._qa_s13_ok('N5A6.C4 plain customer holds no professional class',
        public.professional_active_type(u_c) IS NULL, NULL);
  r := r || public._qa_s13_ok('N5A6.C5 released account holds no professional class',
        public.professional_active_type(u_rel) IS NULL, NULL);
  r := r || public._qa_s13_ok('N5A6.C6 released account still owns its driver_profiles artifact',
        EXISTS (SELECT 1 FROM public.driver_profiles WHERE user_id=u_rel), NULL);
  r := r || public._qa_s13_ok('N5A6.C7 released account artifact is still marked approved (worst case)',
        (SELECT status FROM public.driver_profiles WHERE user_id=u_rel) = 'approved', NULL);

  -- ================= D. CLASS PREDICATE TRUTH =================
  r := r || public._qa_s13_ok('N5A6.D1 predicate TRUE for an approved driver',
        public._driver_class_active(u_d) IS TRUE, NULL);
  r := r || public._qa_s13_ok('N5A6.D2 predicate TRUE for a pending driver (class <> status)',
        public._driver_class_active(u_p) IS TRUE, NULL);
  r := r || public._qa_s13_ok('N5A6.D3 predicate FALSE for a merchant',
        public._driver_class_active(u_m) IS FALSE, NULL);
  r := r || public._qa_s13_ok('N5A6.D4 predicate FALSE for a plain customer',
        public._driver_class_active(u_c) IS FALSE, NULL);
  r := r || public._qa_s13_ok('N5A6.D5 predicate FALSE for a released ex-driver holding an approved profile',
        public._driver_class_active(u_rel) IS FALSE, NULL);
  r := r || public._qa_s13_ok('N5A6.D6 predicate FALSE for NULL identity',
        public._driver_class_active(NULL) IS FALSE, NULL);
  r := r || public._qa_s13_ok('N5A6.D7 predicate FALSE for an unknown account',
        public._driver_class_active(gen_random_uuid()) IS FALSE, NULL);

  -- ================= E. CLASS GATE REFUSALS ARE DISTINCT AND CORRECT =================
  BEGIN PERFORM public._driver_class_require(u_d,'qa'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A6.E1 class gate admits an approved driver', v_err IS NULL, v_err);
  BEGIN PERFORM public._driver_class_require(u_p,'qa'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A6.E2 class gate admits a pending driver', v_err IS NULL, v_err);
  BEGIN PERFORM public._driver_class_require(u_c,'qa'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A6.E3 class gate refuses a plain customer',
        v_err = 'PROFESSIONAL_IDENTITY_REQUIRED', v_err);
  BEGIN PERFORM public._driver_class_require(u_m,'qa'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A6.E4 class gate refuses a MERCHANT with a conflict verdict',
        v_err = 'PROFESSIONAL_IDENTITY_CONFLICT', v_err);
  BEGIN PERFORM public._driver_class_require(u_rel,'qa'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A6.E5 class gate refuses a released ex-driver',
        v_err = 'PROFESSIONAL_IDENTITY_REQUIRED', v_err);
  BEGIN PERFORM public._driver_class_require(NULL,'qa'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A6.E6 class gate refuses an unauthenticated caller',
        v_err = 'AUTH_REQUIRED', v_err);
  r := r || public._qa_s13_ok('N5A6.E7 refusals are distinguishable (required <> conflict)',
        'PROFESSIONAL_IDENTITY_REQUIRED' <> 'PROFESSIONAL_IDENTITY_CONFLICT', NULL);

  -- ================= F. OPERATIONAL GATE = CLASS + STATUS + CAPABILITY =================
  BEGIN PERFORM public._driver_operational_require(u_d,'qa'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A6.F1 operational gate admits an approved driver', v_err IS NULL, v_err);
  BEGIN PERFORM public._driver_operational_require(u_p,'qa'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A6.F2 operational gate refuses a pending driver on STATUS, not class',
        v_err = 'DRIVER_NOT_OPERATIONAL', v_err);
  BEGIN PERFORM public._driver_operational_require(u_m,'qa'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A6.F3 operational gate refuses a merchant on CLASS first',
        v_err = 'PROFESSIONAL_IDENTITY_CONFLICT', v_err);
  BEGIN PERFORM public._driver_operational_require(u_c,'qa'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A6.F4 operational gate refuses a plain customer on CLASS first',
        v_err = 'PROFESSIONAL_IDENTITY_REQUIRED', v_err);
  BEGIN PERFORM public._driver_operational_require(u_rel,'qa'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A6.F5 class is checked before status (released+approved still refused)',
        v_err = 'PROFESSIONAL_IDENTITY_REQUIRED', v_err);
  BEGIN PERFORM public._driver_operational_require(u_d,'qa','marche_shopper'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A6.F6 operational gate refuses a missing capability',
        v_err = 'DRIVER_CAPABILITY_MISSING', v_err);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ops), true);
  PERFORM public.admin_set_driver_capability(u_d,'marche_shopper',true);
  PERFORM set_config('request.jwt.claims', NULL, true);
  BEGIN PERFORM public._driver_operational_require(u_d,'qa','marche_shopper'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A6.F7 operational gate admits a granted capability', v_err IS NULL, v_err);
  PERFORM public._professional_identity_release(u_d,'qa_a6_temp');
  BEGIN PERFORM public._driver_operational_require(u_d,'qa','marche_shopper'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A6.F8 losing the class instantly revokes operational authority',
        v_err = 'PROFESSIONAL_IDENTITY_REQUIRED', v_err);
  r := r || public._qa_s13_ok('N5A6.F9 losing the class also collapses A5 capability truth',
        public.driver_has_capability(u_d,'marche_shopper') IS FALSE, NULL);
  r := r || public._qa_s13_ok('N5A6.F10 stored capability assignment survived (capability <> authority)',
        public.driver_capability_assigned(u_d,'marche_shopper') IS TRUE, NULL);
  PERFORM public._professional_identity_claim(u_d,'driver','qa_a6_reclaim');
  r := r || public._qa_s13_ok('N5A6.F11 reclaiming the class restores operational authority',
        public.driver_has_capability(u_d,'marche_shopper') IS TRUE, NULL);

  -- ================= G. LIVE SURFACE: GOING ONLINE =================
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_rel), true);
  BEGIN PERFORM public.driver_set_status('online'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A6.G1 a released ex-driver cannot go online',
        v_err = 'PROFESSIONAL_IDENTITY_REQUIRED', v_err);
  r := r || public._qa_s13_ok('N5A6.G2 refused go-online left presence untouched',
        (SELECT presence FROM public.driver_profiles WHERE user_id=u_rel) <> 'online',
        (SELECT presence::text FROM public.driver_profiles WHERE user_id=u_rel));
  BEGIN PERFORM public.driver_update_location_signal(9.5,-13.7,NULL,NULL,NULL,NULL); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A6.G3 a released ex-driver cannot publish a location signal',
        v_err IS NOT NULL, v_err);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_c), true);
  BEGIN PERFORM public.driver_set_status('online'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A6.G4 a plain customer cannot go online', v_err IS NOT NULL, v_err);
  r := r || public._qa_s13_ok('N5A6.G5 refused customer go-online created no driver profile',
        NOT EXISTS (SELECT 1 FROM public.driver_profiles WHERE user_id=u_c), NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_m), true);
  BEGIN PERFORM public.driver_set_status('online'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A6.G6 a merchant cannot go online', v_err IS NOT NULL, v_err);
  r := r || public._qa_s13_ok('N5A6.G7 merchant class survived the refusal',
        public.professional_active_type(u_m) = 'merchant', NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_d), true);
  PERFORM public.driver_set_status('online');
  r := r || public._qa_s13_ok('N5A6.G8 a genuine approved driver can still go online',
        (SELECT presence FROM public.driver_profiles WHERE user_id=u_d) = 'online', NULL);
  PERFORM public.driver_set_status('offline');
  r := r || public._qa_s13_ok('N5A6.G9 a genuine driver can still go offline',
        (SELECT presence FROM public.driver_profiles WHERE user_id=u_d) = 'offline', NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_p), true);
  BEGIN PERFORM public.driver_set_status('online'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A6.G10 a pending driver is still refused on STATUS (frozen law intact)',
        v_err IS NOT NULL AND v_err <> 'PROFESSIONAL_IDENTITY_REQUIRED', v_err);
  PERFORM set_config('request.jwt.claims', NULL, true);

  -- ================= H. WORK ACQUISITION =================
  BEGIN PERFORM public._driver_operational_require(u_rel,'mission_claim'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A6.H1 a released ex-driver cannot acquire mission work',
        v_err = 'PROFESSIONAL_IDENTITY_REQUIRED', v_err);
  BEGIN PERFORM public._driver_operational_require(u_m,'mission_claim'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A6.H2 a merchant cannot acquire mission work',
        v_err = 'PROFESSIONAL_IDENTITY_CONFLICT', v_err);
  BEGIN PERFORM public._driver_operational_require(u_c,'mission_claim'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A6.H3 a plain customer cannot acquire mission work',
        v_err = 'PROFESSIONAL_IDENTITY_REQUIRED', v_err);
  r := r || public._qa_s13_ok('N5A6.H4 marche shopper eligibility is false for a released ex-driver',
        public._marche_shopper_eligible(u_rel) IS FALSE, NULL);
  r := r || public._qa_s13_ok('N5A6.H5 marche shopper eligibility is false for a merchant',
        public._marche_shopper_eligible(u_m) IS FALSE, NULL);
  r := r || public._qa_s13_ok('N5A6.H6 marche shopper eligibility is false for a plain customer',
        public._marche_shopper_eligible(u_c) IS FALSE, NULL);
  r := r || public._qa_s13_ok('N5A6.H7 marche shopper eligibility holds for a capable approved driver',
        public._marche_shopper_eligible(u_d) IS TRUE, NULL);

  -- ================= I. ADMIN AUTHORITY CANNOT MANUFACTURE A DRIVER =================
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ops), true);
  BEGIN PERFORM public.driver_admin_decide(u_rel,'approve',NULL); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A6.I1 admin cannot approve an account without the DRIVER class',
        v_err = 'PROFESSIONAL_IDENTITY_CONFLICT', v_err);
  r := r || public._qa_s13_ok('N5A6.I2 refused approval granted no driver role',
        NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id=u_rel AND role='driver'), NULL);
  r := r || public._qa_s13_ok('N5A6.I3 refused approval opened no professional claim',
        public.professional_active_type(u_rel) IS NULL, NULL);
  BEGIN PERFORM public.driver_admin_decide(u_c,'approve',NULL); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A6.I4 admin approval of a plain customer still fails on the object layer',
        v_err = 'Driver profile not found', v_err);
  PERFORM public.driver_admin_decide(u_p,'approve',NULL);
  r := r || public._qa_s13_ok('N5A6.I5 admin can still approve a genuine DRIVER-class applicant',
        (SELECT status FROM public.driver_profiles WHERE user_id=u_p) = 'approved', NULL);
  r := r || public._qa_s13_ok('N5A6.I6 approval did not alter the professional class',
        public.professional_active_type(u_p) = 'driver', NULL);
  PERFORM set_config('request.jwt.claims', NULL, true);

  -- ================= J. DISPATCH DOES NOT SEE NON-DRIVERS =================
  UPDATE public.driver_profiles SET presence='online' WHERE user_id IN (u_d, u_rel);
  r := r || public._qa_s13_ok('N5A6.J1 released ex-driver is invisible to class-aware dispatch',
        public._driver_class_active(u_rel) IS FALSE, NULL);
  r := r || public._qa_s13_ok('N5A6.J2 genuine driver remains visible to dispatch',
        public._driver_class_active(u_d) IS TRUE, NULL);
  r := r || public._qa_s13_ok('N5A6.J3 dispatch filters on the canonical class, not on roles',
        pg_get_functiondef('public.ride_dispatch'::regproc) ~ '_driver_class_active\(dl\.user_id\)', NULL);
  UPDATE public.driver_profiles SET presence='offline' WHERE user_id IN (u_d, u_rel);

  -- ================= K. NON-INTERFERENCE =================
  r := r || public._qa_s13_ok('N5A6.K1 gates created no wallet side effects',
        (SELECT count(*) FROM public.wallet_transactions WHERE wallet_id IN
           (SELECT id FROM public.wallets WHERE user_id = ANY(ids))) = 0, NULL);
  r := r || public._qa_s13_ok('N5A6.K2 gates created no ledger postings for QA accounts',
        (SELECT count(*) FROM public.ledger_postings lp
          JOIN public.ledger_accounts la ON la.id=lp.account_id
          WHERE la.owner_user_id = ANY(ids)) = 0, NULL);
  r := r || public._qa_s13_ok('N5A6.K3 no QA account acquired a second active class',
        NOT EXISTS (SELECT user_id FROM public.professional_identities
                     WHERE user_id = ANY(ids) AND claim_state='active'
                     GROUP BY user_id HAVING count(*) > 1), NULL);
  r := r || public._qa_s13_ok('N5A6.K4 refusals leaked no identity of other accounts',
        (SELECT prosrc !~ 'email' FROM pg_proc
          WHERE oid='public._driver_class_require(uuid,text)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A6.K5 merchant lane untouched by the entire driver pass',
        public.professional_active_type(u_m) = 'merchant', NULL);
  r := r || public._qa_s13_ok('N5A6.K6 merchant gained no driver profile',
        NOT EXISTS (SELECT 1 FROM public.driver_profiles WHERE user_id=u_m), NULL);

  PERFORM public._qa_a5_cleanup(ids);

  SELECT count(*) INTO a_pr FROM public.profiles;
  SELECT count(*) INTO a_ur FROM public.user_roles;
  SELECT count(*) INTO a_w  FROM public.wallets;
  SELECT count(*) INTO a_lp FROM public.ledger_postings;
  SELECT COALESCE(sum(amount_gnf),0) INTO a_ls FROM public.ledger_postings;
  SELECT count(*) INTO a_dp FROM public.driver_profiles;
  SELECT count(*) INTO a_pi FROM public.professional_identities;
  SELECT count(*) INTO a_pia FROM public.professional_identities WHERE claim_state='active';
  SELECT count(*) INTO a_al FROM public.audit_logs;
  SELECT count(*) INTO a_mi FROM public.missions;
  SELECT count(*) INTO a_ri FROM public.rides;
  SELECT count(*) INTO a_ms FROM public.merchant_stores;
  SELECT jsonb_object_agg(key, enabled) INTO a_flags FROM public.feature_flags;

  r := r || public._qa_s13_ok('N5A6.L1 profiles unchanged', a_pr = b_pr, b_pr||'->'||a_pr);
  r := r || public._qa_s13_ok('N5A6.L2 user_roles unchanged', a_ur = b_ur, b_ur||'->'||a_ur);
  r := r || public._qa_s13_ok('N5A6.L3 wallets unchanged', a_w = b_w, b_w||'->'||a_w);
  r := r || public._qa_s13_ok('N5A6.L4 ledger_postings unchanged', a_lp = b_lp, b_lp||'->'||a_lp);
  r := r || public._qa_s13_ok('N5A6.L5 ledger balance sum unchanged', a_ls = b_ls, b_ls||'->'||a_ls);
  r := r || public._qa_s13_ok('N5A6.L6 driver_profiles unchanged', a_dp = b_dp, b_dp||'->'||a_dp);
  r := r || public._qa_s13_ok('N5A6.L7 professional_identities returned to baseline', a_pi = b_pi, b_pi||'->'||a_pi);
  r := r || public._qa_s13_ok('N5A6.L8 active professional census unchanged', a_pia = b_pia, b_pia||'->'||a_pia);
  r := r || public._qa_s13_ok('N5A6.L9 audit_logs returned to baseline', a_al = b_al, b_al||'->'||a_al);
  r := r || public._qa_s13_ok('N5A6.L10 missions unchanged', a_mi = b_mi, b_mi||'->'||a_mi);
  r := r || public._qa_s13_ok('N5A6.L11 rides unchanged', a_ri = b_ri, b_ri||'->'||a_ri);
  r := r || public._qa_s13_ok('N5A6.L12 merchant_stores unchanged', a_ms = b_ms, b_ms||'->'||a_ms);
  r := r || public._qa_s13_ok('N5A6.L13 feature flags unchanged', a_flags = b_flags, NULL);
  r := r || public._qa_s13_ok('N5A6.L14 no QA residue in professional_identities',
        NOT EXISTS (SELECT 1 FROM public.professional_identities WHERE user_id = ANY(ids)), NULL);
  r := r || public._qa_s13_ok('N5A6.L15 no QA residue in driver_profiles',
        NOT EXISTS (SELECT 1 FROM public.driver_profiles WHERE user_id = ANY(ids)), NULL);
  r := r || public._qa_s13_ok('N5A6.L16 no QA residue in admin_users',
        NOT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = ANY(ids)), NULL);

  RETURN jsonb_build_object(
    'fn','_qa_node5_identity_a6',
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'failures', (SELECT COALESCE(jsonb_agg(e),'[]'::jsonb) FROM jsonb_array_elements(r) e
                  WHERE (e->>'ok')::boolean IS NOT TRUE)
  );
EXCEPTION WHEN others THEN
  PERFORM set_config('request.jwt.claims', NULL, true);
  BEGIN PERFORM public._qa_a5_cleanup(ids); EXCEPTION WHEN others THEN NULL; END;
  RAISE;
END $function$;

REVOKE ALL ON FUNCTION public._qa_node5_identity_a6() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node5_identity_a6() TO service_role;