-- =====================================================================
-- NODE 5 · A5 QA SUITE — PROFESSIONAL IDENTITY VS CAPABILITY
-- =====================================================================

CREATE OR REPLACE FUNCTION public._qa_a5_cleanup(p_ids uuid[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  DELETE FROM public.audit_logs WHERE actor_user_id = ANY(p_ids);
  DELETE FROM public.admin_users WHERE user_id = ANY(p_ids);
  PERFORM public._qa_a3_cleanup(p_ids);
END $$;
REVOKE ALL ON FUNCTION public._qa_a5_cleanup(uuid[]) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._qa_node5_identity_a5()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
SET statement_timeout TO '300s'
AS $$
DECLARE
  r jsonb := '[]'::jsonb;
  v_err text;
  v_n bigint;
  v_b boolean;
  v_caps text[];
  v_json jsonb;
  u_c   uuid := gen_random_uuid();  -- plain customer
  u_d   uuid := gen_random_uuid();  -- pending driver
  u_da  uuid := gen_random_uuid();  -- approved driver
  u_m   uuid := gen_random_uuid();  -- merchant
  u_ops uuid := gen_random_uuid();  -- operations admin
  ids   uuid[];
  b_pr bigint; b_au bigint; b_ur bigint; b_w bigint; b_lp bigint; b_ls numeric;
  b_dp bigint; b_da bigint; b_ms bigint; b_pi bigint; b_pia bigint; b_al bigint;
  b_mi bigint; b_ad bigint; b_flags jsonb;
  a_pr bigint; a_au bigint; a_ur bigint; a_w bigint; a_lp bigint; a_ls numeric;
  a_dp bigint; a_da bigint; a_ms bigint; a_pi bigint; a_pia bigint; a_al bigint;
  a_mi bigint; a_ad bigint; a_flags jsonb;
BEGIN
  ids := ARRAY[u_c, u_d, u_da, u_m, u_ops];

  SELECT count(*) INTO b_pr FROM public.profiles;
  b_au := public._qa_auth_user_count();
  SELECT count(*) INTO b_ur FROM public.user_roles;
  SELECT count(*) INTO b_w  FROM public.wallets;
  SELECT count(*) INTO b_lp FROM public.ledger_postings;
  SELECT COALESCE(sum(amount_gnf),0) INTO b_ls FROM public.ledger_postings;
  SELECT count(*) INTO b_dp FROM public.driver_profiles;
  SELECT count(*) INTO b_da FROM public.driver_applications;
  SELECT count(*) INTO b_ms FROM public.merchant_stores;
  SELECT count(*) INTO b_pi FROM public.professional_identities;
  SELECT count(*) INTO b_pia FROM public.professional_identities WHERE claim_state='active';
  SELECT count(*) INTO b_al FROM public.audit_logs;
  SELECT count(*) INTO b_mi FROM public.missions;
  SELECT count(*) INTO b_ad FROM public.admin_users;
  SELECT jsonb_object_agg(key, enabled) INTO b_flags FROM public.feature_flags;

  -- ============ A. VOCABULARY IS CANONICAL AND SINGULAR ============
  v_caps := public.driver_capability_vocabulary();
  r := r || public._qa_s13_ok('N5A5.A1 capability vocabulary function exists',
        v_caps IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N5A5.A2 vocabulary holds exactly seven capabilities',
        array_length(v_caps,1) = 7, array_to_string(v_caps,','));
  r := r || public._qa_s13_ok('N5A5.A3 vocabulary carries rides_moto', 'rides_moto' = ANY(v_caps), NULL);
  r := r || public._qa_s13_ok('N5A5.A4 vocabulary carries rides_toktok', 'rides_toktok' = ANY(v_caps), NULL);
  r := r || public._qa_s13_ok('N5A5.A5 vocabulary carries rides_taxi', 'rides_taxi' = ANY(v_caps), NULL);
  r := r || public._qa_s13_ok('N5A5.A6 vocabulary carries repas_delivery', 'repas_delivery' = ANY(v_caps), NULL);
  r := r || public._qa_s13_ok('N5A5.A7 vocabulary carries marche_delivery', 'marche_delivery' = ANY(v_caps), NULL);
  r := r || public._qa_s13_ok('N5A5.A8 vocabulary carries package_delivery', 'package_delivery' = ANY(v_caps), NULL);
  r := r || public._qa_s13_ok('N5A5.A9 vocabulary carries marche_shopper', 'marche_shopper' = ANY(v_caps), NULL);
  r := r || public._qa_s13_ok('N5A5.A10 vocabulary has no duplicate members',
        (SELECT count(DISTINCT c) FROM unnest(v_caps) c) = 7, NULL);
  r := r || public._qa_s13_ok('N5A5.A11 vocabulary invents no professional class values',
        NOT ('driver' = ANY(v_caps)) AND NOT ('merchant' = ANY(v_caps)), NULL);
  r := r || public._qa_s13_ok('N5A5.A12 vocabulary is immutable (no per-call drift)',
        public.driver_capability_vocabulary() = v_caps, NULL);

  -- ============ B. LAW SURFACE / SECURITY POSTURE ============
  r := r || public._qa_s13_ok('N5A5.B1 driver_profiles carries the capability guard trigger',
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.driver_profiles'::regclass
                 AND tgname='driver_capability_guard' AND NOT tgisinternal), NULL);
  r := r || public._qa_s13_ok('N5A5.B2 capability guard fires BEFORE the row is written',
        NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='driver_capability_guard'
                     AND NOT tgisinternal AND (tgtype & 2) = 0), NULL);
  r := r || public._qa_s13_ok('N5A5.B3 capability guard fn is SECURITY DEFINER with pinned search_path',
        (SELECT prosecdef AND 'search_path=public' = ANY(proconfig) FROM pg_proc
          WHERE proname='_driver_capability_guard'), NULL);
  r := r || public._qa_s13_ok('N5A5.B4 lane gate fn is SECURITY DEFINER with pinned search_path',
        (SELECT prosecdef AND 'search_path=public' = ANY(proconfig) FROM pg_proc
          WHERE proname='_driver_capability_lane_gate'), NULL);
  r := r || public._qa_s13_ok('N5A5.B5 lane gate is not callable by signed-in users',
        NOT has_function_privilege('authenticated','public._driver_capability_lane_gate(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A5.B6 lane gate is not callable anonymously',
        NOT has_function_privilege('anon','public._driver_capability_lane_gate(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A5.B7 capability guard fn is not callable by signed-in users',
        NOT has_function_privilege('authenticated','public._driver_capability_guard()','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A5.B8 capability truth is not probeable anonymously',
        NOT has_function_privilege('anon','public.driver_has_capability(uuid,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A5.B9 capability truth stays available to signed-in callers',
        has_function_privilege('authenticated','public.driver_has_capability(uuid,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A5.B10 stored-assignment read is not anonymous',
        NOT has_function_privilege('anon','public.driver_capability_assigned(uuid,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A5.B11 professional class read is not anonymous',
        NOT has_function_privilege('anon','public.professional_active_type(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A5.B12 vocabulary is not anonymous',
        NOT has_function_privilege('anon','public.driver_capability_vocabulary()','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A5.B13 no capability column exists on the identity table',
        NOT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_schema='public' AND table_name='professional_identities'
                       AND column_name ILIKE '%capabilit%'), NULL);
  r := r || public._qa_s13_ok('N5A5.B14 no self-service capability grant surface exists',
        NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                     WHERE n.nspname='public'
                       AND (p.proname ILIKE '%capability_grant%' OR p.proname ILIKE '%grant_capability%')), NULL);
  r := r || public._qa_s13_ok('N5A5.B15 A2 one-active-lane index still governs identity',
        EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public'
                 AND tablename='professional_identities'
                 AND indexdef ILIKE '%(user_id)%WHERE (claim_state = ''active''::text)'), NULL);
  r := r || public._qa_s13_ok('N5A5.B16 A3 lane guards remain on all five artifact tables',
        (SELECT count(*) FROM pg_trigger WHERE tgname='professional_lane_guard' AND NOT tgisinternal) = 5, NULL);

  -- fixtures
  PERFORM public._qa_users_new(u_c,  'qa-n5a5-c-'||substr(u_c::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_d,  'qa-n5a5-d-'||substr(u_d::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_da, 'qa-n5a5-da-'||substr(u_da::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_m,  'qa-n5a5-m-'||substr(u_m::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_ops,'qa-n5a5-ops-'||substr(u_ops::text,1,8)||'@example.com');
  PERFORM set_config('request.jwt.claims', NULL, true);
  INSERT INTO public.admin_users(user_id, admin_role, status)
  VALUES (u_ops, 'operations_admin', 'active') ON CONFLICT DO NOTHING;

  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_d), true);
  PERFORM public.driver_apply('{"vehicle_type":"moto"}'::jsonb);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_da), true);
  PERFORM public.driver_apply('{"vehicle_type":"moto"}'::jsonb);
  PERFORM set_config('request.jwt.claims', NULL, true);
  UPDATE public.driver_profiles SET status='approved' WHERE user_id=u_da;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_m), true);
  INSERT INTO public.merchants(owner_user_id, name) VALUES (u_m, 'QA A5 Merchant');
  PERFORM set_config('request.jwt.claims', NULL, true);

  r := r || public._qa_s13_ok('N5A5.B17 driver fixture holds the DRIVER class',
        public.professional_active_type(u_d) = 'driver', NULL);
  r := r || public._qa_s13_ok('N5A5.B18 merchant fixture holds the MERCHANT class',
        public.professional_active_type(u_m) = 'merchant', NULL);
  r := r || public._qa_s13_ok('N5A5.B19 plain customer holds no professional class',
        public.professional_active_type(u_c) IS NULL, NULL);

  -- ============ C. NO CLASS = NO CAPABILITY ============
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ops), true);
  BEGIN PERFORM public.admin_set_driver_capability(u_c,'rides_moto',true); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A5.C1 admin cannot grant a capability to a plain customer',
        v_err = 'PROFESSIONAL_IDENTITY_REQUIRED', v_err);
  r := r || public._qa_s13_ok('N5A5.C2 refused grant created no driver profile',
        NOT EXISTS (SELECT 1 FROM public.driver_profiles WHERE user_id=u_c), NULL);
  r := r || public._qa_s13_ok('N5A5.C3 refused grant created no professional identity',
        NOT EXISTS (SELECT 1 FROM public.professional_identities WHERE user_id=u_c), NULL);
  r := r || public._qa_s13_ok('N5A5.C4 refused grant granted no role',
        NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id=u_c AND role IN ('driver','merchant')), NULL);
  r := r || public._qa_s13_ok('N5A5.C5 plain customer has no operational capability',
        public.driver_has_capability(u_c,'rides_moto') IS FALSE, NULL);
  r := r || public._qa_s13_ok('N5A5.C6 plain customer has no stored capability',
        public.driver_capability_assigned(u_c,'rides_moto') IS FALSE, NULL);

  -- ============ D. WRONG CLASS = NO CAPABILITY ============
  BEGIN PERFORM public.admin_set_driver_capability(u_m,'marche_delivery',true); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A5.D1 admin cannot grant a driver capability to a MERCHANT',
        v_err = 'PROFESSIONAL_IDENTITY_CONFLICT', v_err);
  r := r || public._qa_s13_ok('N5A5.D2 merchant class survived the refusal untouched',
        public.professional_active_type(u_m) = 'merchant', NULL);
  r := r || public._qa_s13_ok('N5A5.D3 merchant gained no driver profile',
        NOT EXISTS (SELECT 1 FROM public.driver_profiles WHERE user_id=u_m), NULL);
  r := r || public._qa_s13_ok('N5A5.D4 merchant holds exactly one active class',
        (SELECT count(*) FROM public.professional_identities
          WHERE user_id=u_m AND claim_state='active') = 1, NULL);
  r := r || public._qa_s13_ok('N5A5.D5 capability refusal did not open a driver claim',
        NOT EXISTS (SELECT 1 FROM public.professional_identities
                     WHERE user_id=u_m AND professional_type='driver'), NULL);

  -- ============ E. UNKNOWN CAPABILITY IS REFUSED ============
  BEGIN PERFORM public.admin_set_driver_capability(u_d,'rides_helicopter',true); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A5.E1 unknown capability is refused by the admin surface',
        v_err = 'unknown_capability', v_err);
  BEGIN PERFORM public.admin_set_driver_capability(u_d, NULL, true); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A5.E2 null capability is refused', v_err = 'unknown_capability', v_err);
  PERFORM set_config('request.jwt.claims', NULL, true);
  BEGIN
    UPDATE public.driver_profiles SET capabilities = ARRAY['rides_hovercraft'] WHERE user_id=u_d;
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A5.E3 direct write of an unknown capability is refused at the DB boundary',
        v_err ILIKE 'DRIVER_CAPABILITY_UNKNOWN%', v_err);
  r := r || public._qa_s13_ok('N5A5.E4 refused direct write left capabilities empty',
        COALESCE(array_length((SELECT capabilities FROM public.driver_profiles WHERE user_id=u_d),1),0) = 0, NULL);

  -- ============ F. RIGHT CLASS = CAPABILITY IS ASSIGNABLE ============
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ops), true);
  PERFORM public.admin_set_driver_capability(u_d,'rides_moto',true);
  r := r || public._qa_s13_ok('N5A5.F1 capability is assignable to a DRIVER-class account',
        public.driver_capability_assigned(u_d,'rides_moto'), NULL);
  r := r || public._qa_s13_ok('N5A5.F2 assignment is audited',
        EXISTS (SELECT 1 FROM public.audit_logs WHERE actor_user_id=u_ops
                 AND action='driver.capability.granted' AND target_id=u_d::text), NULL);
  r := r || public._qa_s13_ok('N5A5.F3 capability did NOT upgrade the professional class',
        public.professional_active_type(u_d) = 'driver', NULL);
  r := r || public._qa_s13_ok('N5A5.F4 capability created no additional identity row',
        (SELECT count(*) FROM public.professional_identities WHERE user_id=u_d) = 1, NULL);
  r := r || public._qa_s13_ok('N5A5.F5 capability granted no platform role',
        NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id=u_d AND role='driver'), NULL);
  r := r || public._qa_s13_ok('N5A5.F6 stored assignment is NOT operational truth while pending approval',
        public.driver_has_capability(u_d,'rides_moto') IS FALSE, NULL);
  r := r || public._qa_s13_ok('N5A5.F7 unassigned capability is false for the same driver',
        public.driver_has_capability(u_d,'marche_shopper') IS FALSE, NULL);
  PERFORM set_config('request.jwt.claims', NULL, true);
  UPDATE public.driver_profiles SET status='approved' WHERE user_id=u_d;
  r := r || public._qa_s13_ok('N5A5.F8 approved DRIVER class + assignment = operational capability',
        public.driver_has_capability(u_d,'rides_moto') IS TRUE, NULL);
  r := r || public._qa_s13_ok('N5A5.F9 approval did not silently widen the capability set',
        public.driver_has_capability(u_d,'package_delivery') IS FALSE, NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ops), true);
  PERFORM public.admin_set_driver_capability(u_d,'rides_moto',true);
  r := r || public._qa_s13_ok('N5A5.F10 repeat grant is idempotent (no duplicate capability)',
        (SELECT count(*) FROM unnest((SELECT capabilities FROM public.driver_profiles WHERE user_id=u_d)) c
          WHERE c='rides_moto') = 1, NULL);
  PERFORM public.admin_set_driver_capability(u_d,'marche_shopper',true);
  r := r || public._qa_s13_ok('N5A5.F11 a second capability may coexist within the same class',
        public.driver_has_capability(u_d,'marche_shopper') IS TRUE, NULL);
  PERFORM public.admin_set_driver_capability(u_d,'marche_shopper',false);
  r := r || public._qa_s13_ok('N5A5.F12 revocation removes operational capability',
        public.driver_has_capability(u_d,'marche_shopper') IS FALSE, NULL);
  r := r || public._qa_s13_ok('N5A5.F13 revocation left the other capability intact',
        public.driver_has_capability(u_d,'rides_moto') IS TRUE, NULL);
  r := r || public._qa_s13_ok('N5A5.F14 revocation is audited',
        EXISTS (SELECT 1 FROM public.audit_logs WHERE actor_user_id=u_ops
                 AND action='driver.capability.revoked' AND target_id=u_d::text), NULL);
  r := r || public._qa_s13_ok('N5A5.F15 revocation did not touch the professional class',
        public.professional_active_type(u_d) = 'driver', NULL);

  -- ============ G. CAPABILITY IS NOT SELF-SERVICE AUTHORITY ============
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_d), true);
  BEGIN PERFORM public.admin_set_driver_capability(u_d,'package_delivery',true); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A5.G1 a driver cannot grant themselves a capability',
        v_err IS NOT NULL, v_err);
  r := r || public._qa_s13_ok('N5A5.G2 self-grant attempt changed nothing',
        public.driver_capability_assigned(u_d,'package_delivery') IS FALSE, NULL);
  BEGIN PERFORM public.driver_set_capabilities(ARRAY['rides_moto','package_delivery']); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A5.G3 a driver cannot self-select an ungranted capability',
        v_err ILIKE 'capability_not_granted%', v_err);
  PERFORM public.driver_set_capabilities(ARRAY['rides_moto']);
  r := r || public._qa_s13_ok('N5A5.G4 a driver may narrow to already-granted capabilities',
        public.driver_has_capability(u_d,'rides_moto') IS TRUE, NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_da), true);
  BEGIN PERFORM public.driver_set_capabilities(ARRAY['rides_taxi']); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A5.G5 approved driver with no grant cannot self-select',
        v_err ILIKE 'capability_not_granted%', v_err);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_m), true);
  BEGIN PERFORM public.driver_set_capabilities(ARRAY['rides_moto']); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A5.G6 a MERCHANT cannot enter the driver capability surface',
        v_err = 'PROFESSIONAL_IDENTITY_CONFLICT', v_err);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_c), true);
  BEGIN PERFORM public.driver_set_capabilities(ARRAY['rides_moto']); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A5.G7 a plain customer cannot enter the driver capability surface',
        v_err = 'PROFESSIONAL_IDENTITY_REQUIRED', v_err);
  PERFORM set_config('request.jwt.claims', NULL, true);
  BEGIN PERFORM public.driver_set_capabilities(ARRAY['rides_moto']); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A5.G8 unauthenticated capability selection is refused',
        v_err = 'AUTH_REQUIRED', v_err);

  -- ============ H. CLASS LOSS = IMMEDIATE CAPABILITY LOSS ============
  PERFORM set_config('request.jwt.claims', NULL, true);
  PERFORM public._professional_identity_release(u_d, 'qa a5 release');
  r := r || public._qa_s13_ok('N5A5.H1 released driver holds no professional class',
        public.professional_active_type(u_d) IS NULL, NULL);
  r := r || public._qa_s13_ok('N5A5.H2 released driver loses operational capability immediately',
        public.driver_has_capability(u_d,'rides_moto') IS FALSE, NULL);
  r := r || public._qa_s13_ok('N5A5.H3 stored capability history is preserved, not erased',
        public.driver_capability_assigned(u_d,'rides_moto') IS TRUE, NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ops), true);
  BEGIN PERFORM public.admin_set_driver_capability(u_d,'package_delivery',true); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A5.H4 no capability can be granted after class release',
        v_err = 'PROFESSIONAL_IDENTITY_REQUIRED', v_err);
  PERFORM public.admin_set_driver_capability(u_d,'rides_moto',false);
  r := r || public._qa_s13_ok('N5A5.H5 revocation remains possible after release (cleanup is never blocked)',
        public.driver_capability_assigned(u_d,'rides_moto') IS FALSE, NULL);
  PERFORM set_config('request.jwt.claims', NULL, true);
  BEGIN
    UPDATE public.driver_profiles SET capabilities = ARRAY['rides_moto'] WHERE user_id=u_d;
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A5.H6 direct DB write cannot re-create capability without a class',
        v_err = 'PROFESSIONAL_IDENTITY_REQUIRED', v_err);
  r := r || public._qa_s13_ok('N5A5.H7 refused bypass left capabilities empty',
        COALESCE(array_length((SELECT capabilities FROM public.driver_profiles WHERE user_id=u_d),1),0) = 0, NULL);
  BEGIN
    UPDATE public.driver_profiles SET presence='offline' WHERE user_id=u_d;
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A5.H8 non-capability driver writes are unaffected by the guard', v_err IS NULL, v_err);

  -- ============ I. CLASS RE-ENTRY RESTORES ONLY THE CLASS ============
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_d), true);
  PERFORM public.driver_apply('{"vehicle_type":"moto"}'::jsonb);
  r := r || public._qa_s13_ok('N5A5.I1 re-entry restores the DRIVER class',
        public.professional_active_type(u_d) = 'driver', NULL);
  r := r || public._qa_s13_ok('N5A5.I2 re-entry restores no capability automatically',
        COALESCE(array_length((SELECT capabilities FROM public.driver_profiles WHERE user_id=u_d),1),0) = 0, NULL);
  r := r || public._qa_s13_ok('N5A5.I3 re-entry grants no operational capability',
        public.driver_has_capability(u_d,'rides_moto') IS FALSE, NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ops), true);
  PERFORM public.admin_set_driver_capability(u_d,'repas_delivery',true);
  r := r || public._qa_s13_ok('N5A5.I4 capability is re-grantable once the class is back',
        public.driver_capability_assigned(u_d,'repas_delivery') IS TRUE, NULL);
  r := r || public._qa_s13_ok('N5A5.I5 re-granted capability is not operational until re-approval',
        public.driver_has_capability(u_d,'repas_delivery') IS FALSE, NULL);

  -- ============ J. CROSS-CLASS ISOLATION ============
  r := r || public._qa_s13_ok('N5A5.J1 capability of one driver never leaks to another',
        public.driver_has_capability(u_da,'repas_delivery') IS FALSE, NULL);
  r := r || public._qa_s13_ok('N5A5.J2 merchant class never reports driver capability',
        public.driver_has_capability(u_m,'marche_delivery') IS FALSE, NULL);
  r := r || public._qa_s13_ok('N5A5.J3 null subject reports no capability',
        public.driver_has_capability(NULL,'rides_moto') IS FALSE, NULL);
  r := r || public._qa_s13_ok('N5A5.J4 null capability reports no capability',
        public.driver_has_capability(u_d, NULL) IS FALSE, NULL);
  r := r || public._qa_s13_ok('N5A5.J5 professional class of a driver is never merchant',
        public.professional_active_type(u_d) <> 'merchant', NULL);

  -- ============ K. LIVE-DATA INVARIANTS ============
  PERFORM set_config('request.jwt.claims', NULL, true);
  SELECT count(*) INTO v_n FROM public.driver_profiles dp
   WHERE COALESCE(array_length(dp.capabilities,1),0) > 0
     AND NOT EXISTS (SELECT 1 FROM public.professional_identities pi
                      WHERE pi.user_id=dp.user_id AND pi.claim_state='active'
                        AND pi.professional_type='driver');
  r := r || public._qa_s13_ok('N5A5.K1 no live capability exists outside the DRIVER class', v_n = 0, 'n='||v_n);
  SELECT count(*) INTO v_n FROM public.driver_profiles dp, unnest(COALESCE(dp.capabilities,'{}')) c
   WHERE c <> ALL (public.driver_capability_vocabulary());
  r := r || public._qa_s13_ok('N5A5.K2 no live capability falls outside the canonical vocabulary', v_n = 0, 'n='||v_n);
  SELECT count(*) INTO v_n FROM public.professional_identities
   WHERE claim_state='active' AND professional_type NOT IN ('driver','merchant');
  r := r || public._qa_s13_ok('N5A5.K3 no live professional class outside driver/merchant', v_n = 0, 'n='||v_n);
  SELECT count(*) INTO v_n FROM (
    SELECT user_id FROM public.professional_identities WHERE claim_state='active'
     GROUP BY user_id HAVING count(*) > 1) x;
  r := r || public._qa_s13_ok('N5A5.K4 no account holds two active professional classes', v_n = 0, 'n='||v_n);
  SELECT count(*) INTO v_n FROM public.driver_profiles dp
   WHERE dp.status='approved'
     AND NOT EXISTS (SELECT 1 FROM public.professional_identities pi
                      WHERE pi.user_id=dp.user_id AND pi.claim_state='active'
                        AND pi.professional_type='driver');
  r := r || public._qa_s13_ok('N5A5.K5 every approved driver still holds the DRIVER class', v_n = 0, 'n='||v_n);

  -- ============ L. CLEANUP + NON-DRIFT ============
  PERFORM set_config('request.jwt.claims', NULL, true);
  PERFORM public._qa_a5_cleanup(ids);

  SELECT count(*) INTO a_pr FROM public.profiles;
  a_au := public._qa_auth_user_count();
  SELECT count(*) INTO a_ur FROM public.user_roles;
  SELECT count(*) INTO a_w  FROM public.wallets;
  SELECT count(*) INTO a_lp FROM public.ledger_postings;
  SELECT COALESCE(sum(amount_gnf),0) INTO a_ls FROM public.ledger_postings;
  SELECT count(*) INTO a_dp FROM public.driver_profiles;
  SELECT count(*) INTO a_da FROM public.driver_applications;
  SELECT count(*) INTO a_ms FROM public.merchant_stores;
  SELECT count(*) INTO a_pi FROM public.professional_identities;
  SELECT count(*) INTO a_pia FROM public.professional_identities WHERE claim_state='active';
  SELECT count(*) INTO a_al FROM public.audit_logs;
  SELECT count(*) INTO a_mi FROM public.missions;
  SELECT count(*) INTO a_ad FROM public.admin_users;
  SELECT jsonb_object_agg(key, enabled) INTO a_flags FROM public.feature_flags;

  r := r || public._qa_s13_ok('N5A5.L1 QA fixtures fully purged from auth', a_au = b_au, b_au||'->'||a_au);
  r := r || public._qa_s13_ok('N5A5.L2 profiles unchanged', a_pr = b_pr, b_pr||'->'||a_pr);
  r := r || public._qa_s13_ok('N5A5.L3 user_roles unchanged', a_ur = b_ur, b_ur||'->'||a_ur);
  r := r || public._qa_s13_ok('N5A5.L4 wallets unchanged', a_w = b_w, b_w||'->'||a_w);
  r := r || public._qa_s13_ok('N5A5.L5 ledger_postings unchanged', a_lp = b_lp, b_lp||'->'||a_lp);
  r := r || public._qa_s13_ok('N5A5.L6 ledger balance sum unchanged', a_ls = b_ls, b_ls||'->'||a_ls);
  r := r || public._qa_s13_ok('N5A5.L7 driver_profiles unchanged', a_dp = b_dp, b_dp||'->'||a_dp);
  r := r || public._qa_s13_ok('N5A5.L8 driver_applications unchanged', a_da = b_da, b_da||'->'||a_da);
  r := r || public._qa_s13_ok('N5A5.L9 merchant_stores unchanged', a_ms = b_ms, b_ms||'->'||a_ms);
  r := r || public._qa_s13_ok('N5A5.L10 professional_identities returned to baseline', a_pi = b_pi, b_pi||'->'||a_pi);
  r := r || public._qa_s13_ok('N5A5.L11 active professional census unchanged', a_pia = b_pia, b_pia||'->'||a_pia);
  r := r || public._qa_s13_ok('N5A5.L12 audit_logs returned to baseline', a_al = b_al, b_al||'->'||a_al);
  r := r || public._qa_s13_ok('N5A5.L13 missions unchanged', a_mi = b_mi, b_mi||'->'||a_mi);
  r := r || public._qa_s13_ok('N5A5.L14 admin_users unchanged', a_ad = b_ad, b_ad||'->'||a_ad);
  r := r || public._qa_s13_ok('N5A5.L15 feature flags unchanged', a_flags = b_flags, NULL);
  r := r || public._qa_s13_ok('N5A5.L16 no QA residue in professional_identities',
        NOT EXISTS (SELECT 1 FROM public.professional_identities WHERE user_id = ANY(ids)), NULL);
  r := r || public._qa_s13_ok('N5A5.L17 no QA residue in driver_profiles',
        NOT EXISTS (SELECT 1 FROM public.driver_profiles WHERE user_id = ANY(ids)), NULL);

  RETURN jsonb_build_object(
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'failures', (SELECT COALESCE(jsonb_agg(e),'[]'::jsonb) FROM jsonb_array_elements(r) e
                  WHERE (e->>'ok')::boolean IS NOT TRUE)
  );
EXCEPTION WHEN others THEN
  PERFORM set_config('request.jwt.claims', NULL, true);
  BEGIN PERFORM public._qa_a5_cleanup(ids); EXCEPTION WHEN others THEN NULL; END;
  RAISE;
END $$;
REVOKE ALL ON FUNCTION public._qa_node5_identity_a5() FROM PUBLIC, anon, authenticated;
