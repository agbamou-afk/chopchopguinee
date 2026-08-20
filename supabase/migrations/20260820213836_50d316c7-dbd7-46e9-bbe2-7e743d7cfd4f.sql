CREATE OR REPLACE FUNCTION public._qa_a3_cleanup(p_ids uuid[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
BEGIN
  DELETE FROM public.notification_log WHERE user_id = ANY(p_ids);
  DELETE FROM public.driver_referrals WHERE referred_driver_user_id = ANY(p_ids) OR referrer_user_id = ANY(p_ids);
  DELETE FROM public.driver_applications WHERE user_id = ANY(p_ids);
  DELETE FROM public.driver_profiles WHERE user_id = ANY(p_ids);
  DELETE FROM public.merchant_stores WHERE owner_user_id = ANY(p_ids) OR created_by = ANY(p_ids);
  DELETE FROM public.food_restaurants WHERE owner_user_id = ANY(p_ids);
  DELETE FROM public.merchants WHERE owner_user_id = ANY(p_ids);
  PERFORM public._qa_a2_cleanup(p_ids);
END $fn$;
REVOKE ALL ON FUNCTION public._qa_a3_cleanup(uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._qa_a3_cleanup(uuid[]) FROM anon;
REVOKE ALL ON FUNCTION public._qa_a3_cleanup(uuid[]) FROM authenticated;
GRANT EXECUTE ON FUNCTION public._qa_a3_cleanup(uuid[]) TO service_role;

CREATE OR REPLACE FUNCTION public._qa_node5_identity_a3()
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public'
SET statement_timeout TO '120s'
AS $function$
DECLARE
  v_qa_role text := current_user;
  r jsonb := '[]'::jsonb;
  u_none uuid := gen_random_uuid();
  u_drv  uuid := gen_random_uuid();
  u_mer  uuid := gen_random_uuid();
  u_rel  uuid := gen_random_uuid();
  u_susp uuid := gen_random_uuid();
  u_rej  uuid := gen_random_uuid();
  u_adm  uuid := gen_random_uuid();
  u_xfer uuid := gen_random_uuid();
  ids uuid[];
  v_err text; v_n int; v_n2 int; v_json jsonb;
  v_id uuid; v_id2 uuid; v_store uuid;
  p1 boolean; p2 boolean; p3 boolean; d1 text; d2 text; d3 text;
  f_ur int; f_w int;
  b_pr bigint; a_pr bigint; b_au bigint; a_au bigint; b_ur bigint; a_ur bigint;
  b_w bigint; a_w bigint; b_wt bigint; a_wt bigint;
  b_lj bigint; a_lj bigint; b_lp bigint; a_lp bigint; b_ls bigint; a_ls bigint;
  b_dp bigint; a_dp bigint; b_da bigint; a_da bigint;
  b_ms bigint; a_ms bigint; b_fr bigint; a_fr bigint; b_me bigint; a_me bigint;
  b_pi bigint; a_pi bigint; b_pia bigint; a_pia bigint;
  b_apr bigint; a_apr bigint; b_flags jsonb; a_flags jsonb;
  b_mo bigint; a_mo bigint; b_fo bigint; a_fo bigint; b_mp bigint; a_mp bigint;
BEGIN
  ids := ARRAY[u_none,u_drv,u_mer,u_rel,u_susp,u_rej,u_adm,u_xfer];

  SELECT count(*) INTO b_pr FROM public.profiles;
  b_au := public._qa_auth_user_count();
  SELECT count(*) INTO b_ur FROM public.user_roles;
  SELECT count(*) INTO b_w  FROM public.wallets;
  SELECT count(*) INTO b_wt FROM public.wallet_transactions;
  SELECT count(*) INTO b_lj FROM public.ledger_journals;
  SELECT count(*) INTO b_lp FROM public.ledger_postings;
  SELECT COALESCE(sum(amount_gnf),0) INTO b_ls FROM public.ledger_postings;
  SELECT count(*) INTO b_dp FROM public.driver_profiles;
  SELECT count(*) INTO b_da FROM public.driver_applications;
  SELECT count(*) INTO b_ms FROM public.merchant_stores;
  SELECT count(*) INTO b_fr FROM public.food_restaurants;
  SELECT count(*) INTO b_me FROM public.merchants;
  SELECT count(*) INTO b_pi FROM public.professional_identities;
  SELECT count(*) INTO b_pia FROM public.professional_identities WHERE claim_state='active';
  SELECT count(*) INTO b_apr FROM public.merchant_stores WHERE onboarding_status='approved';
  SELECT count(*) INTO b_mo FROM public.marche_orders;
  SELECT count(*) INTO b_fo FROM public.food_orders;
  SELECT count(*) INTO b_mp FROM public.marche_procurement_price_observations;
  SELECT jsonb_object_agg(key, enabled) INTO b_flags FROM public.feature_flags;

  -- ============ A. GUARD ARCHITECTURE ============
  r := r || public._qa_s13_ok('N5A3.A1 driver_profiles carries the professional lane guard',
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.driver_profiles'::regclass
                 AND tgname='professional_lane_guard' AND NOT tgisinternal), NULL);
  r := r || public._qa_s13_ok('N5A3.A2 driver_applications carries the professional lane guard',
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.driver_applications'::regclass
                 AND tgname='professional_lane_guard' AND NOT tgisinternal), NULL);
  r := r || public._qa_s13_ok('N5A3.A3 merchant_stores carries the professional lane guard',
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.merchant_stores'::regclass
                 AND tgname='professional_lane_guard' AND NOT tgisinternal), NULL);
  r := r || public._qa_s13_ok('N5A3.A4 food_restaurants carries the professional lane guard',
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.food_restaurants'::regclass
                 AND tgname='professional_lane_guard' AND NOT tgisinternal), NULL);
  r := r || public._qa_s13_ok('N5A3.A5 merchants carries the professional lane guard',
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.merchants'::regclass
                 AND tgname='professional_lane_guard' AND NOT tgisinternal), NULL);
  r := r || public._qa_s13_ok('N5A3.A6 guards fire BEFORE the artifact row is written',
        NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='professional_lane_guard'
                     AND NOT tgisinternal AND (tgtype & 2) = 0), NULL);
  r := r || public._qa_s13_ok('N5A3.A7 guard covers INSERT and owner-column UPDATE on every artifact table',
        (SELECT count(*) FROM pg_trigger WHERE tgname='professional_lane_guard' AND NOT tgisinternal
          AND (tgtype & 4) > 0 AND (tgtype & 16) > 0) = 5, NULL);
  r := r || public._qa_s13_ok('N5A3.A8 lane guard function is SECURITY DEFINER with a pinned search_path',
        (SELECT prosecdef FROM pg_proc WHERE proname='_professional_artifact_guard')
        AND (SELECT 'search_path=public' = ANY(proconfig) FROM pg_proc WHERE proname='_professional_artifact_guard'), NULL);
  r := r || public._qa_s13_ok('N5A3.A9 lane require primitive is SECURITY DEFINER with a pinned search_path',
        (SELECT prosecdef FROM pg_proc WHERE proname='_professional_lane_require')
        AND (SELECT 'search_path=public' = ANY(proconfig) FROM pg_proc WHERE proname='_professional_lane_require'), NULL);
  r := r || public._qa_s13_ok('N5A3.A10 lane require primitive is not executable by anon',
        NOT has_function_privilege('anon','public._professional_lane_require(uuid,text,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A3.A11 lane require primitive is not executable by authenticated',
        NOT has_function_privilege('authenticated','public._professional_lane_require(uuid,text,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A3.A12 internal claim primitive stays server-only for anon',
        NOT has_function_privilege('anon','public._professional_identity_claim(uuid,text,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A3.A13 internal claim primitive stays server-only for authenticated',
        NOT has_function_privilege('authenticated','public._professional_identity_claim(uuid,text,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A3.A14 internal release primitive stays server-only for authenticated',
        NOT has_function_privilege('authenticated','public._professional_identity_release(uuid,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A3.A15 no publicly exposed cross-user claim RPC was introduced',
        NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                     WHERE n.nspname='public' AND p.proname='professional_identity_claim'), NULL);
  r := r || public._qa_s13_ok('N5A3.A16 driver_apply still derives its caller from auth.uid()',
        (SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname='driver_apply') ILIKE '%auth.uid()%', NULL);
  r := r || public._qa_s13_ok('N5A3.A17 A3 did not weaken the one-active-lane unique index',
        EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public'
                 AND tablename='professional_identities'
                 AND indexdef ILIKE 'CREATE UNIQUE INDEX%(user_id)%WHERE (claim_state = ''active''::text)'), NULL);

  PERFORM public._qa_users_new(u_none, 'qa-n5a3-none-'||substr(u_none::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_drv,  'qa-n5a3-drv-'||substr(u_drv::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_mer,  'qa-n5a3-mer-'||substr(u_mer::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_rel,  'qa-n5a3-rel-'||substr(u_rel::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_susp, 'qa-n5a3-susp-'||substr(u_susp::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_rej,  'qa-n5a3-rej-'||substr(u_rej::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_adm,  'qa-n5a3-adm-'||substr(u_adm::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_xfer, 'qa-n5a3-xfer-'||substr(u_xfer::text,1,8)||'@example.com');

  SELECT count(*) INTO f_ur FROM public.user_roles WHERE user_id = ANY(ids);
  SELECT count(*) INTO f_w  FROM public.wallets    WHERE owner_user_id = ANY(ids);

  -- ============ B. DRIVER COMPOSITION ============
  r := r || public._qa_s13_ok('N5A3.B0 fresh customer starts with no professional lane',
        NOT EXISTS (SELECT 1 FROM public.professional_identities WHERE user_id = u_drv), NULL);

  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_drv), true);
  BEGIN
    PERFORM public.driver_apply(jsonb_build_object('vehicle_type','moto','plate_number','QA-A3-1'));
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A3.B1 customer with no lane can complete driver_apply', v_err IS NULL, v_err);

  SELECT count(*) INTO v_n FROM public.professional_identities
   WHERE user_id = u_drv AND professional_type='driver' AND claim_state='active';
  r := r || public._qa_s13_ok('N5A3.B2 driver_apply produced exactly one ACTIVE driver lane', v_n = 1, 'n='||v_n);
  SELECT id INTO v_id FROM public.professional_identities WHERE user_id=u_drv AND claim_state='active';

  SELECT count(*) INTO v_n FROM public.driver_profiles WHERE user_id = u_drv;
  r := r || public._qa_s13_ok('N5A3.B3 driver onboarding profile artifact exists', v_n = 1, 'n='||v_n);
  SELECT count(*) INTO v_n FROM public.driver_applications WHERE user_id = u_drv;
  r := r || public._qa_s13_ok('N5A3.B4 driver application artifact exists', v_n = 1, 'n='||v_n);
  SELECT count(*) INTO v_n FROM public.driver_profiles WHERE user_id = u_drv AND status = 'pending';
  r := r || public._qa_s13_ok('N5A3.B5 lane claim does not approve the driver (status stays pending)', v_n = 1, 'n='||v_n);
  r := r || public._qa_s13_ok('N5A3.B6 claim recorded its onboarding provenance',
        (SELECT claim_source FROM public.professional_identities WHERE user_id=u_drv AND claim_state='active')
          IN ('driver_profiles','driver_applications'), NULL);

  BEGIN
    PERFORM public.driver_apply(jsonb_build_object('vehicle_type','toktok','plate_number','QA-A3-1B'));
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A3.C1 same-lane driver reapply still succeeds', v_err IS NULL, v_err);
  SELECT count(*) INTO v_n FROM public.professional_identities WHERE user_id=u_drv;
  r := r || public._qa_s13_ok('N5A3.C2 reapply created no second identity row', v_n = 1, 'n='||v_n);
  r := r || public._qa_s13_ok('N5A3.C3 reapply preserved the original identity id',
        (SELECT id FROM public.professional_identities WHERE user_id=u_drv) = v_id, NULL);
  SELECT count(*) INTO v_n FROM public.driver_profiles WHERE user_id=u_drv;
  r := r || public._qa_s13_ok('N5A3.C4 reapply did not duplicate the driver profile', v_n = 1, 'n='||v_n);
  r := r || public._qa_s13_ok('N5A3.C5 reapply legitimately updated the existing profile',
        (SELECT vehicle_type::text FROM public.driver_profiles WHERE user_id=u_drv) = 'toktok', NULL);
  SELECT count(*) INTO v_n FROM public.driver_applications WHERE user_id=u_drv;
  r := r || public._qa_s13_ok('N5A3.C6 resubmission history preserved (2 applications)', v_n = 2, 'n='||v_n);

  -- ============ D. MERCHANT COMPOSITION ============
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_mer), true);
  BEGIN
    INSERT INTO public.merchant_stores(owner_user_id, created_by, name, slug, status, onboarding_status)
    VALUES (u_mer, u_mer, 'QA A3 Store', 'qa-a3-store-'||substr(u_mer::text,1,8), 'pending','submitted')
    RETURNING id INTO v_store;
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A3.D1 customer with no lane can create first merchant ownership', v_err IS NULL, v_err);
  SELECT count(*) INTO v_n FROM public.professional_identities
   WHERE user_id=u_mer AND professional_type='merchant' AND claim_state='active';
  r := r || public._qa_s13_ok('N5A3.D2 store creation produced exactly one ACTIVE merchant lane', v_n = 1, 'n='||v_n);
  r := r || public._qa_s13_ok('N5A3.D3 merchant lane does not approve the store',
        (SELECT onboarding_status FROM public.merchant_stores WHERE id=v_store) <> 'approved', NULL);
  BEGIN
    INSERT INTO public.food_restaurants(owner_user_id, name, slug)
    VALUES (u_mer, 'QA A3 Resto', 'qa-a3-resto-'||substr(u_mer::text,1,8));
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A3.D4 existing merchant may add a restaurant (one class, many assets)', v_err IS NULL, v_err);
  BEGIN
    INSERT INTO public.merchant_stores(owner_user_id, created_by, name, slug)
    VALUES (u_mer, u_mer, 'QA A3 Store 2', 'qa-a3-store2-'||substr(u_mer::text,1,8));
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A3.D5 existing merchant may own an additional store', v_err IS NULL, v_err);
  SELECT count(*) INTO v_n FROM public.professional_identities WHERE user_id=u_mer;
  r := r || public._qa_s13_ok('N5A3.D6 additional merchant assets create no extra identity rows', v_n = 1, 'n='||v_n);

  -- ============ E. CROSS-LANE CONFLICT MATRIX ============
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_drv), true);
  BEGIN
    INSERT INTO public.merchant_stores(owner_user_id, created_by, name, slug)
    VALUES (u_drv, u_drv, 'QA A3 Illegal', 'qa-a3-illegal-'||substr(u_drv::text,1,8));
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A3.E1 DRIVER creating a merchant store is refused with PROFESSIONAL_IDENTITY_CONFLICT',
        v_err = 'PROFESSIONAL_IDENTITY_CONFLICT', v_err);
  SELECT count(*) INTO v_n FROM public.merchant_stores WHERE owner_user_id = u_drv;
  r := r || public._qa_s13_ok('N5A3.E2 refused merchant store left no artifact', v_n = 0, 'n='||v_n);

  BEGIN
    INSERT INTO public.food_restaurants(owner_user_id, name, slug)
    VALUES (u_drv, 'QA A3 Illegal Resto', 'qa-a3-ir-'||substr(u_drv::text,1,8));
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A3.E3 DRIVER creating a restaurant is refused',
        v_err = 'PROFESSIONAL_IDENTITY_CONFLICT', v_err);
  SELECT count(*) INTO v_n FROM public.food_restaurants WHERE owner_user_id = u_drv;
  r := r || public._qa_s13_ok('N5A3.E4 refused restaurant left no artifact', v_n = 0, 'n='||v_n);

  BEGIN
    INSERT INTO public.merchants(owner_user_id, name) VALUES (u_drv, 'QA A3 Illegal Merchant');
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A3.E5 DRIVER creating a merchant entity is refused',
        v_err = 'PROFESSIONAL_IDENTITY_CONFLICT', v_err);
  SELECT count(*) INTO v_n FROM public.merchants WHERE owner_user_id = u_drv;
  r := r || public._qa_s13_ok('N5A3.E6 refused merchant entity left no artifact', v_n = 0, 'n='||v_n);

  SELECT count(*) INTO v_n FROM public.professional_identities WHERE user_id=u_drv;
  r := r || public._qa_s13_ok('N5A3.E7 refused merchant attempts created no merchant lane', v_n = 1, 'n='||v_n);
  r := r || public._qa_s13_ok('N5A3.E8 driver lane survived the refused merchant attempts',
        (SELECT professional_type FROM public.professional_identities WHERE user_id=u_drv) = 'driver', NULL);

  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_mer), true);
  BEGIN
    PERFORM public.driver_apply(jsonb_build_object('vehicle_type','moto'));
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A3.E9 MERCHANT calling driver_apply is refused',
        v_err = 'PROFESSIONAL_IDENTITY_CONFLICT', v_err);
  SELECT count(*) INTO v_n FROM public.driver_profiles WHERE user_id=u_mer;
  SELECT count(*) INTO v_n2 FROM public.driver_applications WHERE user_id=u_mer;
  r := r || public._qa_s13_ok('N5A3.E10 refused driver_apply left no driver profile', v_n = 0, 'n='||v_n);
  r := r || public._qa_s13_ok('N5A3.E11 refused driver_apply left no driver application', v_n2 = 0, 'n='||v_n2);
  r := r || public._qa_s13_ok('N5A3.E12 refused driver_apply granted no driver role',
        NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id=u_mer AND role='driver'), NULL);
  r := r || public._qa_s13_ok('N5A3.E13 refused driver_apply created no driver wallet',
        NOT EXISTS (SELECT 1 FROM public.wallets WHERE owner_user_id=u_mer AND party_type='driver'), NULL);
  r := r || public._qa_s13_ok('N5A3.E14 refused driver_apply emitted no onboarding notification',
        NOT EXISTS (SELECT 1 FROM public.notification_log WHERE user_id=u_mer), NULL);
  SELECT count(*) INTO v_n FROM public.professional_identities WHERE user_id=u_mer;
  r := r || public._qa_s13_ok('N5A3.E15 merchant kept exactly one lane after the refused driver attempt', v_n = 1, 'n='||v_n);

  BEGIN
    INSERT INTO public.driver_profiles(user_id, status, vehicle_type)
    VALUES (u_mer, 'pending', 'moto');
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A3.E16 direct driver_profiles insert for a merchant is refused',
        v_err = 'PROFESSIONAL_IDENTITY_CONFLICT', v_err);
  BEGIN
    INSERT INTO public.driver_applications(user_id, payload, decision)
    VALUES (u_mer, '{}'::jsonb, 'pending');
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A3.E17 direct driver_applications insert for a merchant is refused',
        v_err = 'PROFESSIONAL_IDENTITY_CONFLICT', v_err);

  -- ============ F. DIRECT TABLE BYPASS UNDER authenticated ============
  p1 := NULL; p2 := NULL; p3 := NULL;
  BEGIN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(u_mer), true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    BEGIN
      EXECUTE format('INSERT INTO public.driver_profiles(user_id,status,vehicle_type) VALUES (%L,%L,%L)', u_mer,'pending','moto');
      p1 := false; d1 := 'insert unexpectedly succeeded';
    EXCEPTION WHEN others THEN p1 := true; d1 := SQLERRM; END;
    BEGIN
      EXECUTE format('INSERT INTO public.driver_applications(user_id,payload,decision) VALUES (%L,%L,%L)', u_mer,'{}','pending');
      p2 := false; d2 := 'insert unexpectedly succeeded';
    EXCEPTION WHEN others THEN p2 := true; d2 := SQLERRM; END;
    BEGIN
      EXECUTE format('UPDATE public.professional_identities SET professional_type=%L WHERE user_id=%L', 'driver', u_mer);
      p3 := false; d3 := 'update unexpectedly succeeded';
    EXCEPTION WHEN others THEN p3 := true; d3 := SQLERRM; END;
    EXECUTE format('SET LOCAL ROLE %I', v_qa_role);
  EXCEPTION WHEN others THEN
    EXECUTE format('SET LOCAL ROLE %I', v_qa_role);
    d1 := COALESCE(d1,'probe error: '||SQLERRM);
  END;
  r := r || public._qa_s13_ok('N5A3.F1 authenticated direct driver_profiles bypass denied', p1 IS TRUE, d1);
  r := r || public._qa_s13_ok('N5A3.F2 authenticated direct driver_applications bypass denied', p2 IS TRUE, d2);
  r := r || public._qa_s13_ok('N5A3.F3 authenticated cannot rewrite its own professional class', p3 IS TRUE, d3);
  SELECT count(*) INTO v_n FROM public.driver_profiles WHERE user_id=u_mer;
  r := r || public._qa_s13_ok('N5A3.F4 no driver artifact survived the bypass attempts', v_n = 0, 'n='||v_n);
  r := r || public._qa_s13_ok('N5A3.F5 merchant lane unchanged after bypass attempts',
        (SELECT professional_type FROM public.professional_identities WHERE user_id=u_mer AND claim_state='active') = 'merchant', NULL);

  -- ============ G. ADMIN DOES NOT BYPASS ============
  INSERT INTO public.user_roles(user_id, role) VALUES (u_adm,'admin') ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_adm), true);
  r := r || public._qa_s13_ok('N5A3.G0 admin fixture actually holds the admin role',
        public.has_role(u_adm,'admin'), NULL);
  BEGIN
    INSERT INTO public.merchant_stores(owner_user_id, created_by, name, slug)
    VALUES (u_drv, u_adm, 'QA A3 Admin Store', 'qa-a3-admin-'||substr(u_drv::text,1,8));
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A3.G1 admin cannot assign merchant ownership to an active DRIVER',
        v_err = 'PROFESSIONAL_IDENTITY_CONFLICT', v_err);
  SELECT count(*) INTO v_n FROM public.merchant_stores WHERE owner_user_id=u_drv;
  r := r || public._qa_s13_ok('N5A3.G2 admin refusal left no merchant artifact', v_n = 0, 'n='||v_n);
  BEGIN
    INSERT INTO public.driver_profiles(user_id,status,vehicle_type) VALUES (u_mer,'approved','moto');
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A3.G3 admin cannot create a driver profile for an active MERCHANT',
        v_err = 'PROFESSIONAL_IDENTITY_CONFLICT', v_err);
  BEGIN
    UPDATE public.driver_profiles SET status='approved' WHERE user_id=u_drv;
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A3.G4 admin may still approve a legitimate same-lane driver', v_err IS NULL, v_err);
  r := r || public._qa_s13_ok('N5A3.G5 approval is domain truth, not identity truth',
        (SELECT status::text FROM public.driver_profiles WHERE user_id=u_drv)='approved'
        AND (SELECT professional_type FROM public.professional_identities WHERE user_id=u_drv)='driver', NULL);
  BEGIN
    UPDATE public.merchant_stores SET onboarding_status='approved', status='active' WHERE id=v_store;
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A3.G6 admin may still approve a legitimate same-lane merchant store', v_err IS NULL, v_err);

  -- ============ H. OWNERSHIP TRANSFER ============
  BEGIN
    UPDATE public.merchant_stores SET owner_user_id = u_drv WHERE id = v_store;
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A3.H1 store ownership cannot be transferred to an active DRIVER',
        v_err = 'PROFESSIONAL_IDENTITY_CONFLICT', v_err);
  r := r || public._qa_s13_ok('N5A3.H2 refused transfer left ownership intact',
        (SELECT owner_user_id FROM public.merchant_stores WHERE id=v_store) = u_mer, NULL);
  BEGIN
    UPDATE public.merchant_stores SET owner_user_id = u_xfer WHERE id = v_store;
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A3.H3 transfer to a lane-free customer atomically claims MERCHANT', v_err IS NULL, v_err);
  r := r || public._qa_s13_ok('N5A3.H4 the new owner now holds exactly one ACTIVE merchant lane',
        (SELECT count(*) FROM public.professional_identities
          WHERE user_id=u_xfer AND professional_type='merchant' AND claim_state='active') = 1, NULL);
  BEGIN
    UPDATE public.merchant_stores SET name = 'QA A3 Store renamed' WHERE id = v_store;
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A3.H5 non-ownership updates of an owned asset are untouched by the guard', v_err IS NULL, v_err);

  -- ============ I. RELEASED-LANE HISTORY ============
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_rel), true);
  PERFORM public.driver_apply(jsonb_build_object('vehicle_type','moto'));
  SELECT id INTO v_id FROM public.professional_identities WHERE user_id=u_rel AND claim_state='active';
  DELETE FROM public.driver_profiles WHERE user_id=u_rel;
  DELETE FROM public.driver_applications WHERE user_id=u_rel;
  PERFORM public._professional_identity_release(u_rel, 'qa-a3');
  r := r || public._qa_s13_ok('N5A3.I1 released driver lane leaves no active lane',
        NOT EXISTS (SELECT 1 FROM public.professional_identities WHERE user_id=u_rel AND claim_state='active'), NULL);
  BEGIN
    INSERT INTO public.merchant_stores(owner_user_id, created_by, name, slug)
    VALUES (u_rel, u_rel, 'QA A3 After Release', 'qa-a3-rel-'||substr(u_rel::text,1,8));
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A3.I2 released driver may later claim MERCHANT', v_err IS NULL, v_err);
  SELECT id INTO v_id2 FROM public.professional_identities WHERE user_id=u_rel AND claim_state='active';
  r := r || public._qa_s13_ok('N5A3.I3 a genuinely new claim creates a NEW identity row', v_id2 IS NOT NULL AND v_id2 <> v_id, NULL);
  r := r || public._qa_s13_ok('N5A3.I4 the historical released driver row is preserved untouched',
        (SELECT professional_type FROM public.professional_identities WHERE id=v_id) = 'driver'
        AND (SELECT claim_state FROM public.professional_identities WHERE id=v_id) = 'released', NULL);
  SELECT count(*) INTO v_n FROM public.professional_identities WHERE user_id=u_rel AND claim_state='active';
  r := r || public._qa_s13_ok('N5A3.I5 exactly one active lane after re-entry', v_n = 1, 'n='||v_n);
  r := r || public._qa_s13_ok('N5A3.I6 released rows are never resurrected to active',
        (SELECT claim_state FROM public.professional_identities WHERE id=v_id) = 'released', NULL);

  -- ============ J. SUSPENDED / REJECTED ============
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_susp), true);
  PERFORM public.driver_apply(jsonb_build_object('vehicle_type','moto'));
  UPDATE public.driver_profiles SET status='suspended', suspended_reason='qa-a3' WHERE user_id=u_susp;
  BEGIN
    INSERT INTO public.merchant_stores(owner_user_id, created_by, name, slug)
    VALUES (u_susp, u_susp, 'QA A3 Susp', 'qa-a3-susp-'||substr(u_susp::text,1,8));
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A3.J1 SUSPENDED driver still cannot switch to merchant',
        v_err = 'PROFESSIONAL_IDENTITY_CONFLICT', v_err);
  r := r || public._qa_s13_ok('N5A3.J2 suspension does not free the professional lane',
        (SELECT professional_type FROM public.professional_identities WHERE user_id=u_susp AND claim_state='active')='driver', NULL);

  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_rej), true);
  PERFORM public.driver_apply(jsonb_build_object('vehicle_type','moto'));
  UPDATE public.driver_profiles SET status='rejected', rejected_reason='qa-a3' WHERE user_id=u_rej;
  UPDATE public.driver_applications SET decision='rejected' WHERE user_id=u_rej;
  BEGIN
    INSERT INTO public.food_restaurants(owner_user_id, name, slug)
    VALUES (u_rej, 'QA A3 Rej', 'qa-a3-rej-'||substr(u_rej::text,1,8));
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A3.J3 REJECTED driver with an active lane still cannot become merchant',
        v_err = 'PROFESSIONAL_IDENTITY_CONFLICT', v_err);
  r := r || public._qa_s13_ok('N5A3.J4 rejection does not free the professional lane',
        (SELECT professional_type FROM public.professional_identities WHERE user_id=u_rej AND claim_state='active')='driver', NULL);
  r := r || public._qa_s13_ok('N5A3.J5 refused merchant attempt by a rejected driver left no restaurant',
        NOT EXISTS (SELECT 1 FROM public.food_restaurants WHERE owner_user_id=u_rej), NULL);

  -- ============ K. NO SIDE EFFECTS ============
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_none), true);
  SELECT count(*) INTO v_n FROM public.wallets WHERE owner_user_id=u_none;
  INSERT INTO public.merchants(owner_user_id, name) VALUES (u_none, 'QA A3 Claim Only');
  r := r || public._qa_s13_ok('N5A3.K1 lane-free customer claims MERCHANT through merchant entity creation',
        (SELECT count(*) FROM public.professional_identities WHERE user_id=u_none AND claim_state='active') = 1, NULL);
  r := r || public._qa_s13_ok('N5A3.K2 claim created no wallet',
        (SELECT count(*) FROM public.wallets WHERE owner_user_id=u_none) = v_n, NULL);
  r := r || public._qa_s13_ok('N5A3.K3 claim granted no driver/merchant role',
        NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id=u_none AND role IN ('driver','merchant')), NULL);
  r := r || public._qa_s13_ok('N5A3.K4 claim created no wallet transaction',
        NOT EXISTS (SELECT 1 FROM public.wallet_transactions wt
                     JOIN public.wallets w ON w.id IN (wt.from_wallet_id, wt.to_wallet_id)
                    WHERE w.owner_user_id = u_none), NULL);
  r := r || public._qa_s13_ok('N5A3.K5 claim created no merchant payable',
        NOT EXISTS (SELECT 1 FROM public.merchant_payables mp
                     WHERE mp.merchant_store_id IN (SELECT id FROM public.merchant_stores WHERE owner_user_id=u_none)), NULL);
  r := r || public._qa_s13_ok('N5A3.K6 claim created no mission',
        NOT EXISTS (SELECT 1 FROM public.missions WHERE courier_id = u_none), NULL);

  -- ============ L. READ SURFACE ============
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_drv), true);
  v_json := public.professional_identity_current();
  r := r || public._qa_s13_ok('N5A3.L1 current-read reports the DRIVER lane acquired through onboarding',
        v_json->>'professional_type' = 'driver', v_json::text);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_mer), true);
  v_json := public.professional_identity_current();
  r := r || public._qa_s13_ok('N5A3.L2 current-read reports the MERCHANT lane acquired through onboarding',
        v_json->>'professional_type' = 'merchant', v_json::text);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_xfer), true);
  v_json := public.professional_identity_current();
  r := r || public._qa_s13_ok('N5A3.L3 current-read reports the lane acquired through ownership transfer',
        v_json->>'professional_type' = 'merchant', v_json::text);
  r := r || public._qa_s13_ok('N5A3.L4 current-read still leaks no other-user identifier',
        NOT (v_json::text ILIKE '%user_id%'), v_json::text);
  PERFORM set_config('request.jwt.claims', NULL, true);

  BEGIN
    INSERT INTO public.user_preferences(user_id, app_mode) VALUES (u_drv,'merchant')
    ON CONFLICT (user_id) DO UPDATE SET app_mode='merchant';
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A3.L5 preferred client mode does not change the server lane',
        (SELECT professional_type FROM public.professional_identities WHERE user_id=u_drv AND claim_state='active')='driver', v_err);
  DELETE FROM public.user_preferences WHERE user_id = ANY(ids);

  -- ============ M. GLOBAL INVARIANT ============
  SELECT count(*) INTO v_n FROM (
    SELECT user_id FROM public.professional_identities WHERE claim_state='active'
    GROUP BY user_id HAVING count(*) > 1) s;
  r := r || public._qa_s13_ok('N5A3.M1 no user holds more than one ACTIVE professional lane', v_n = 0, 'n='||v_n);
  SELECT count(*) INTO v_n FROM public.professional_identities a
    JOIN public.professional_identities b ON b.user_id=a.user_id AND b.id<>a.id
   WHERE a.claim_state='active' AND b.claim_state='active';
  r := r || public._qa_s13_ok('N5A3.M2 no active driver/merchant intersection exists platform-wide', v_n = 0, 'n='||v_n);
  SELECT count(*) INTO v_n FROM public.driver_profiles dp
   WHERE NOT EXISTS (SELECT 1 FROM public.professional_identities pi
                      WHERE pi.user_id=dp.user_id AND pi.professional_type='driver');
  r := r || public._qa_s13_ok('N5A3.M3 every driver profile is backed by a driver lane record', v_n = 0, 'n='||v_n);
  SELECT count(*) INTO v_n FROM public.merchant_stores ms
   WHERE ms.owner_user_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.professional_identities pi
                      WHERE pi.user_id=ms.owner_user_id AND pi.professional_type='merchant');
  r := r || public._qa_s13_ok('N5A3.M4 every owned store is backed by a merchant lane record', v_n = 0, 'n='||v_n);

  -- ============ N. CLEANUP + NON-DRIFT ============
  PERFORM public._qa_a3_cleanup(ids);

  SELECT count(*) INTO a_pr FROM public.profiles;
  a_au := public._qa_auth_user_count();
  SELECT count(*) INTO a_ur FROM public.user_roles;
  SELECT count(*) INTO a_w  FROM public.wallets;
  SELECT count(*) INTO a_wt FROM public.wallet_transactions;
  SELECT count(*) INTO a_lj FROM public.ledger_journals;
  SELECT count(*) INTO a_lp FROM public.ledger_postings;
  SELECT COALESCE(sum(amount_gnf),0) INTO a_ls FROM public.ledger_postings;
  SELECT count(*) INTO a_dp FROM public.driver_profiles;
  SELECT count(*) INTO a_da FROM public.driver_applications;
  SELECT count(*) INTO a_ms FROM public.merchant_stores;
  SELECT count(*) INTO a_fr FROM public.food_restaurants;
  SELECT count(*) INTO a_me FROM public.merchants;
  SELECT count(*) INTO a_pi FROM public.professional_identities;
  SELECT count(*) INTO a_pia FROM public.professional_identities WHERE claim_state='active';
  SELECT count(*) INTO a_apr FROM public.merchant_stores WHERE onboarding_status='approved';
  SELECT count(*) INTO a_mo FROM public.marche_orders;
  SELECT count(*) INTO a_fo FROM public.food_orders;
  SELECT count(*) INTO a_mp FROM public.marche_procurement_price_observations;
  SELECT jsonb_object_agg(key, enabled) INTO a_flags FROM public.feature_flags;

  r := r || public._qa_s13_ok('N5A3.N1 QA fixtures fully purged from auth', a_au = b_au, b_au||'->'||a_au);
  r := r || public._qa_s13_ok('N5A3.N2 profiles unchanged', a_pr = b_pr, b_pr||'->'||a_pr);
  r := r || public._qa_s13_ok('N5A3.N3 user_roles unchanged', a_ur = b_ur, b_ur||'->'||a_ur);
  r := r || public._qa_s13_ok('N5A3.N4 wallets unchanged', a_w = b_w, b_w||'->'||a_w);
  r := r || public._qa_s13_ok('N5A3.N5 wallet_transactions unchanged', a_wt = b_wt, b_wt||'->'||a_wt);
  r := r || public._qa_s13_ok('N5A3.N6 ledger_journals unchanged', a_lj = b_lj, b_lj||'->'||a_lj);
  r := r || public._qa_s13_ok('N5A3.N7 ledger_postings unchanged', a_lp = b_lp, b_lp||'->'||a_lp);
  r := r || public._qa_s13_ok('N5A3.N8 ledger balance sum unchanged', a_ls = b_ls, b_ls||'->'||a_ls);
  r := r || public._qa_s13_ok('N5A3.N9 driver_profiles unchanged', a_dp = b_dp, b_dp||'->'||a_dp);
  r := r || public._qa_s13_ok('N5A3.N10 driver_applications unchanged', a_da = b_da, b_da||'->'||a_da);
  r := r || public._qa_s13_ok('N5A3.N11 merchant_stores unchanged', a_ms = b_ms, b_ms||'->'||a_ms);
  r := r || public._qa_s13_ok('N5A3.N12 food_restaurants unchanged', a_fr = b_fr, b_fr||'->'||a_fr);
  r := r || public._qa_s13_ok('N5A3.N13 merchants unchanged', a_me = b_me, b_me||'->'||a_me);
  r := r || public._qa_s13_ok('N5A3.N14 professional_identities returned to baseline', a_pi = b_pi, b_pi||'->'||a_pi);
  r := r || public._qa_s13_ok('N5A3.N15 active professional census unchanged', a_pia = b_pia, b_pia||'->'||a_pia);
  r := r || public._qa_s13_ok('N5A3.N16 approved-store population unchanged', a_apr = b_apr, b_apr||'->'||a_apr);
  r := r || public._qa_s13_ok('N5A3.N17 Marché orders unchanged', a_mo = b_mo, b_mo||'->'||a_mo);
  r := r || public._qa_s13_ok('N5A3.N18 Repas orders unchanged', a_fo = b_fo, b_fo||'->'||a_fo);
  r := r || public._qa_s13_ok('N5A3.N19 price observations unchanged', a_mp = b_mp, b_mp||'->'||a_mp);
  r := r || public._qa_s13_ok('N5A3.N20 feature flags unchanged', a_flags = b_flags, NULL);
  r := r || public._qa_s13_ok('N5A3.N21 no QA residue in professional_identities',
        NOT EXISTS (SELECT 1 FROM public.professional_identities WHERE user_id = ANY(ids)), NULL);

  RETURN jsonb_build_object(
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'failures', (SELECT COALESCE(jsonb_agg(e),'[]'::jsonb) FROM jsonb_array_elements(r) e
                  WHERE (e->>'ok')::boolean IS NOT TRUE)
  );
EXCEPTION WHEN others THEN
  PERFORM set_config('request.jwt.claims', NULL, true);
  BEGIN PERFORM public._qa_a3_cleanup(ids); EXCEPTION WHEN others THEN NULL; END;
  RAISE;
END $function$;

REVOKE ALL ON FUNCTION public._qa_node5_identity_a3() FROM PUBLIC;
REVOKE ALL ON FUNCTION public._qa_node5_identity_a3() FROM anon;
REVOKE ALL ON FUNCTION public._qa_node5_identity_a3() FROM authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node5_identity_a3() TO service_role;