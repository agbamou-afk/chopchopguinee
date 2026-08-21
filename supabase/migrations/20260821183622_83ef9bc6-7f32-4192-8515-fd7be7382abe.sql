CREATE OR REPLACE FUNCTION public._qa_node5_identity_a12()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
SET statement_timeout TO '300s'
AS $fn$
DECLARE
  r jsonb := '[]'::jsonb;
  u_god uuid := gen_random_uuid();
  u_ops uuid := gen_random_uuid();
  u_adm uuid := gen_random_uuid();
  u_stf uuid := gen_random_uuid();
  u_drv uuid := gen_random_uuid();
  u_mer uuid := gen_random_uuid();
  u_ad  uuid := gen_random_uuid();
  u_am  uuid := gen_random_uuid();
  u_fin uuid := gen_random_uuid();
  u_out uuid := gen_random_uuid();
  ids uuid[];
  s_mer uuid := gen_random_uuid();
  s_am  uuid := gen_random_uuid();
  res jsonb; ok boolean; v_txt text; v_n bigint; v_bal bigint;
  fake text;
  a12_fns text[] := ARRAY[
    'admin_governance_set_status(uuid,text,text)',
    'admin_staff_role_grant(uuid,text,text)',
    'admin_staff_role_revoke(uuid,text,text)',
    'admin_professional_offboard(uuid,text)',
    'admin_professional_restore(uuid,text,text)',
    'professional_offboard_blockers(uuid)'];
  fq text; v_bad text[] := '{}';
  refusals text[] := ARRAY[
    'AUTH_REQUIRED','NOT_AUTHORIZED','PROFESSIONAL_IDENTITY_REQUIRED',
    'PROFESSIONAL_IDENTITY_CONFLICT','DRIVER_PROFILE_REQUIRED','DRIVER_NOT_OPERATIONAL',
    'DRIVER_CAPABILITY_MISSING','No driver profile','MERCHANT_STORE_NOT_FOUND',
    'MERCHANT_STORE_NOT_OPERATIONAL','NOT_STORE_OWNER','not store owner',
    'MERCHANT_IDENTITY_REQUIRED','PROFESSIONAL_LANE_RELEASED'];
  b_pi bigint; b_au bigint; b_ur bigint; b_up bigint; b_w bigint; b_wt bigint;
  b_lp bigint; b_ls numeric; b_ms bigint; b_dp bigint; b_pr bigint; b_al bigint;
  b_mfh bigint; b_flags jsonb; b_gov_initial jsonb;
  a_pi bigint; a_au bigint; a_ur bigint; a_up bigint; a_w bigint; a_wt bigint;
  a_lp bigint; a_ls numeric; a_ms bigint; a_dp bigint; a_pr bigint; a_al bigint;
  a_mfh bigint; a_flags jsonb; a_gov jsonb;
BEGIN
  ids := ARRAY[u_god,u_ops,u_adm,u_stf,u_drv,u_mer,u_ad,u_am,u_fin,u_out];

  SELECT count(*) INTO b_pi  FROM public.professional_identities;
  SELECT count(*) INTO b_au  FROM public.admin_users;
  SELECT count(*) INTO b_ur  FROM public.user_roles;
  SELECT count(*) INTO b_up  FROM public.user_preferences;
  SELECT count(*) INTO b_w   FROM public.wallets;
  SELECT count(*) INTO b_wt  FROM public.wallet_transactions;
  SELECT count(*) INTO b_lp  FROM public.ledger_postings;
  SELECT COALESCE(sum(amount_gnf),0) INTO b_ls FROM public.ledger_postings;
  SELECT count(*) INTO b_ms  FROM public.merchant_stores;
  SELECT count(*) INTO b_dp  FROM public.driver_profiles;
  SELECT count(*) INTO b_pr  FROM public.profiles;
  SELECT count(*) INTO b_al  FROM public.audit_logs;
  SELECT count(*) INTO b_mfh FROM public.mission_financial_holds;
  SELECT jsonb_object_agg(key, enabled) INTO b_flags FROM public.feature_flags;
  SELECT COALESCE(jsonb_agg(jsonb_build_array(user_id, admin_role, status) ORDER BY user_id),'[]'::jsonb)
    INTO b_gov_initial FROM public.admin_users;

  -- ================= A. STRUCTURE / LIFECYCLE SOURCE OF TRUTH =================
  FOREACH fq IN ARRAY a12_fns LOOP
    IF to_regprocedure('public.'||fq) IS NULL THEN v_bad := v_bad || fq; END IF;
  END LOOP;
  r := r || public._qa_s13_ok('N5A12.A1 every A12 lifecycle entrypoint exists',
        array_length(v_bad,1) IS NULL, array_to_string(v_bad,','));
  v_bad := '{}';
  FOREACH fq IN ARRAY a12_fns LOOP
    IF NOT (SELECT prosecdef FROM pg_proc WHERE oid = ('public.'||fq)::regprocedure)
      THEN v_bad := v_bad || fq; END IF;
  END LOOP;
  r := r || public._qa_s13_ok('N5A12.A2 lifecycle entrypoints are SECURITY DEFINER',
        array_length(v_bad,1) IS NULL, array_to_string(v_bad,','));
  v_bad := '{}';
  FOREACH fq IN ARRAY a12_fns LOOP
    IF has_function_privilege('anon','public.'||fq,'EXECUTE') THEN v_bad := v_bad || fq; END IF;
  END LOOP;
  r := r || public._qa_s13_ok('N5A12.A3 no lifecycle entrypoint is reachable signed-out',
        array_length(v_bad,1) IS NULL, array_to_string(v_bad,','));
  r := r || public._qa_s13_ok('N5A12.A4 governance role whitelist helper stays server-internal',
        NOT has_function_privilege('anon','public._governance_role_allowed(text)','EXECUTE')
        AND NOT has_function_privilege('authenticated','public._governance_role_allowed(text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A12.A5 professional roles are refused by the governance whitelist',
        NOT public._governance_role_allowed('driver')
        AND NOT public._governance_role_allowed('merchant')
        AND NOT public._governance_role_allowed('client')
        AND NOT public._governance_role_allowed('user'), NULL);
  r := r || public._qa_s13_ok('N5A12.A6 governance roles are accepted by the governance whitelist',
        public._governance_role_allowed('operations_admin')
        AND public._governance_role_allowed('field_captain')
        AND public._governance_role_allowed('finance_admin'), NULL);
  r := r || public._qa_s13_ok('N5A12.A7 no parallel professional status system was introduced',
        (SELECT pg_get_constraintdef(oid) FROM pg_constraint
          WHERE conname='professional_identities_state_ck')
          = 'CHECK ((claim_state = ANY (ARRAY[''active''::text, ''released''::text])))',
        (SELECT pg_get_constraintdef(oid) FROM pg_constraint
          WHERE conname='professional_identities_state_ck'));
  r := r || public._qa_s13_ok('N5A12.A8 raw lane release helper is never client-callable',
        NOT has_function_privilege('anon','public._professional_identity_release(uuid,text)','EXECUTE')
        AND NOT has_function_privilege('authenticated','public._professional_identity_release(uuid,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A12.A9 raw lane claim helper is never client-callable',
        NOT has_function_privilege('anon','public._professional_identity_claim(uuid,text,text)','EXECUTE')
        AND NOT has_function_privilege('authenticated','public._professional_identity_claim(uuid,text,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A12.A10 A11 governance grant posture is preserved',
        NOT has_table_privilege('authenticated','public.user_roles','DELETE')
        AND NOT has_table_privilege('authenticated','public.admin_users','DELETE')
        AND NOT has_table_privilege('anon','public.user_roles','SELECT')
        AND NOT has_table_privilege('authenticated','public.professional_identities','UPDATE'), NULL);
  r := r || public._qa_s13_ok('N5A12.A11 offboarding never deletes money, orders or history',
        (SELECT prosrc !~* 'delete\s+from\s+public\.(wallets|ledger_postings|ledger_journals|wallet_transactions|marche_orders|missions|merchant_stores|driver_profiles|audit_logs)'
           FROM pg_proc WHERE oid='public.admin_professional_offboard(uuid,text)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A12.A12 restoration never re-grants roles or operational approval',
        (SELECT prosrc !~* 'insert\s+into\s+public\.user_roles'
            AND prosrc !~* 'driver_admin_decide'
            AND prosrc !~* '''approved'''
           FROM pg_proc WHERE oid='public.admin_professional_restore(uuid,text,text)'::regprocedure), NULL);

  -- ================= FIXTURES =================
  PERFORM public._qa_users_new(u_god,'qa-n5a12-god-'||substr(u_god::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_ops,'qa-n5a12-ops-'||substr(u_ops::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_adm,'qa-n5a12-adm-'||substr(u_adm::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_stf,'qa-n5a12-stf-'||substr(u_stf::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_drv,'qa-n5a12-drv-'||substr(u_drv::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_mer,'qa-n5a12-mer-'||substr(u_mer::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_ad, 'qa-n5a12-ad-' ||substr(u_ad::text,1,8) ||'@example.com');
  PERFORM public._qa_users_new(u_am, 'qa-n5a12-am-' ||substr(u_am::text,1,8) ||'@example.com');
  PERFORM public._qa_users_new(u_fin,'qa-n5a12-fin-'||substr(u_fin::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_out,'qa-n5a12-out-'||substr(u_out::text,1,8)||'@example.com');
  UPDATE public.profiles SET phone = '+22462' || lpad((floor(random()*10000000))::bigint::text, 7, '0')
   WHERE user_id = ANY(ids) AND (phone IS NULL OR phone = '');

  INSERT INTO public.admin_users(user_id, admin_role, status) VALUES
    (u_god,'super_admin','active'),
    (u_ops,'operations_admin','active'),
    (u_adm,'super_admin','active'),
    (u_ad, 'super_admin','active'),
    (u_am, 'super_admin','active')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.user_roles(user_id, role) VALUES (u_stf,'field_captain')
  ON CONFLICT DO NOTHING;

  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_drv), true);
  PERFORM public.driver_apply('{"vehicle_type":"moto"}'::jsonb);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ad), true);
  PERFORM public.driver_apply('{"vehicle_type":"moto"}'::jsonb);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_fin), true);
  PERFORM public.driver_apply('{"vehicle_type":"moto"}'::jsonb);
  PERFORM set_config('request.jwt.claims', NULL, true);
  UPDATE public.driver_profiles SET status='approved', approved_at=now()
   WHERE user_id IN (u_drv, u_ad, u_fin);
  INSERT INTO public.wallets(owner_user_id, party_type) VALUES
    (u_drv,'driver'), (u_ad,'driver'), (u_fin,'driver')
  ON CONFLICT DO NOTHING;

  INSERT INTO public.merchant_stores(id, owner_user_id, name, slug, status, onboarding_status)
  VALUES (s_mer, u_mer,'QA A12 Store M','qa-a12-m-'||substr(s_mer::text,1,8),'active','approved'),
         (s_am,  u_am, 'QA A12 Store AM','qa-a12-am-'||substr(s_am::text,1,8),'active','approved');
  INSERT INTO public.wallets(owner_user_id, party_type) VALUES
    (u_mer,'merchant'), (u_am,'merchant')
  ON CONFLICT DO NOTHING;

  -- ================= B. ADMIN-ONLY OFFBOARDING / RESTORATION =================
  r := r || public._qa_s13_ok('N5A12.B1 admin-only fixture holds governance and no professional lane',
        public.is_any_admin(u_adm) AND public._is_god_admin(u_adm)
        AND public.professional_active_type(u_adm) IS NULL, NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_god), true);
  res := public.admin_governance_set_status(u_adm,'suspended','a12 offboard');
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A12.B2 governance suspension reports the exact transition',
        res->>'status'='suspended' AND res->>'previous_status'='active', res::text);
  r := r || public._qa_s13_ok('N5A12.B3 suspended admin loses admin authority',
        NOT public.is_admin(u_adm) AND NOT public.is_any_admin(u_adm), NULL);
  r := r || public._qa_s13_ok('N5A12.B4 suspended admin loses god and ops predicates',
        NOT public._is_god_admin(u_adm) AND NOT public._is_ops_or_god_admin(u_adm)
        AND NOT public.can_manage_operations(u_adm), NULL);
  r := r || public._qa_s13_ok('N5A12.B5 governance row is preserved, not deleted',
        EXISTS (SELECT 1 FROM public.admin_users WHERE user_id=u_adm AND status='suspended'), NULL);
  r := r || public._qa_s13_ok('N5A12.B6 governance suspension created no professional lane',
        public.professional_active_type(u_adm) IS NULL
        AND NOT EXISTS (SELECT 1 FROM public.professional_identities WHERE user_id=u_adm)
        AND public.account_available_modes(u_adm) = ARRAY['client'], NULL);
  BEGIN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(u_adm), true);
    PERFORM public.admin_governance_set_status(u_god,'suspended','escalation attempt');
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A12.B7 a suspended admin can no longer act on governance', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A12.B7 a suspended admin can no longer act on governance',
          SQLERRM = 'NOT_AUTHORIZED', SQLERRM);
  END;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_god), true);
  res := public.admin_governance_set_status(u_adm,'active','a12 restore');
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A12.B8 governance restoration is explicit and reports both states',
        res->>'status'='active' AND res->>'previous_status'='suspended', res::text);
  r := r || public._qa_s13_ok('N5A12.B9 restored admin regains exactly its prior governance grade',
        public.is_any_admin(u_adm) AND public._is_god_admin(u_adm)
        AND (SELECT admin_role::text FROM public.admin_users WHERE user_id=u_adm)='super_admin', NULL);
  BEGIN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(u_god), true);
    PERFORM public.admin_governance_set_status(u_god,'suspended','self');
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A12.B10 an admin cannot suspend itself', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A12.B10 an admin cannot suspend itself',
          SQLERRM = 'CANNOT_SUSPEND_SELF', SQLERRM);
  END;

  -- ================= C. STAFF ROLE REVOCATION / RESTORATION =================
  r := r || public._qa_s13_ok('N5A12.C1 staff fixture actually holds its staff role',
        public.has_role(u_stf,'field_captain'::public.app_role), NULL);
  BEGIN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(u_out), true);
    PERFORM public.admin_staff_role_revoke(u_stf,'field_captain','unauthorized');
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A12.C2 a non-admin cannot revoke a staff role', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A12.C2 a non-admin cannot revoke a staff role',
          SQLERRM = 'NOT_AUTHORIZED', SQLERRM);
  END;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_god), true);
  res := public.admin_staff_role_revoke(u_stf,'field_captain','a12 offboard');
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A12.C3 staff role revocation removes exactly one row',
        (res->>'removed')::int = 1, res::text);
  r := r || public._qa_s13_ok('N5A12.C4 revoked staff role no longer satisfies has_role',
        NOT public.has_role(u_stf,'field_captain'::public.app_role)
        AND NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id=u_stf), NULL);
  r := r || public._qa_s13_ok('N5A12.C5 staff revocation created no professional lane',
        public.professional_active_type(u_stf) IS NULL
        AND public.account_available_modes(u_stf) = ARRAY['client'], NULL);
  BEGIN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(u_god), true);
    PERFORM public.admin_staff_role_revoke(u_drv,'driver','axis violation');
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A12.C6 governance tooling refuses to revoke a professional role', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A12.C6 governance tooling refuses to revoke a professional role',
          SQLERRM = 'PROFESSIONAL_ROLE_NOT_GOVERNANCE', SQLERRM);
  END;
  BEGIN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(u_god), true);
    PERFORM public.admin_staff_role_grant(u_stf,'merchant','axis violation');
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A12.C7 governance tooling refuses to grant a professional role', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A12.C7 governance tooling refuses to grant a professional role',
          SQLERRM = 'PROFESSIONAL_ROLE_NOT_GOVERNANCE', SQLERRM);
  END;
  r := r || public._qa_s13_ok('N5A12.C8 the refused grant left no role row behind',
        NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id=u_stf), NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_god), true);
  res := public.admin_staff_role_grant(u_stf,'field_captain','a12 restore');
  v_txt := (public.admin_staff_role_grant(u_stf,'field_captain','a12 idempotent'))->>'inserted';
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A12.C9 staff restoration is explicit and idempotent',
        (res->>'inserted')::int = 1 AND v_txt = '0'
        AND public.has_role(u_stf,'field_captain'::public.app_role), res::text||'/'||v_txt);
  r := r || public._qa_s13_ok('N5A12.C10 a staff role never creates a governance grade',
        NOT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id=u_stf)
        AND NOT public.is_any_admin(u_stf), NULL);

  -- ================= D. DRIVER LIFECYCLE =================
  r := r || public._qa_s13_ok('N5A12.D1 driver fixture holds lane, approval and a professional wallet',
        public._driver_class_active(u_drv)
        AND (SELECT status FROM public.driver_profiles WHERE user_id=u_drv)='approved'
        AND EXISTS (SELECT 1 FROM public.wallets WHERE owner_user_id=u_drv AND party_type='driver'), NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_drv), true);
  PERFORM public.driver_set_status('online'::public.driver_presence);
  PERFORM public.account_mode_set('driver');
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A12.D2 driver is operational before offboarding',
        (SELECT presence::text FROM public.driver_profiles WHERE user_id=u_drv)='online', NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ops), true);
  res := public.admin_professional_offboard(u_drv,'a12 driver offboard');
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A12.D3 admin offboarding of a driver succeeds and names the lane',
        (res->>'offboarded')::boolean AND res->>'lane'='driver', res::text);
  r := r || public._qa_s13_ok('N5A12.D4 the driver lane is no longer active',
        public.professional_active_type(u_drv) IS NULL, NULL);
  r := r || public._qa_s13_ok('N5A12.D5 the driver professional class is gone',
        NOT public._driver_class_active(u_drv), NULL);
  r := r || public._qa_s13_ok('N5A12.D6 the driver profile is preserved and suspended, not deleted',
        (SELECT status::text FROM public.driver_profiles WHERE user_id=u_drv)='suspended'
        AND (SELECT presence::text FROM public.driver_profiles WHERE user_id=u_drv)='offline'
        AND (SELECT approved_at FROM public.driver_profiles WHERE user_id=u_drv) IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N5A12.D7 the driver wallet survives offboarding',
        EXISTS (SELECT 1 FROM public.wallets WHERE owner_user_id=u_drv AND party_type='driver'), NULL);
  BEGIN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(u_drv), true);
    PERFORM public.driver_set_status('online'::public.driver_presence);
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A12.D8 an offboarded driver cannot go online', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A12.D8 an offboarded driver cannot go online',
          SQLERRM = ANY(refusals), SQLERRM);
  END;
  r := r || public._qa_s13_ok('N5A12.D9 an offboarded driver keeps only the client workspace',
        public.account_available_modes(u_drv) = ARRAY['client'], NULL);
  r := r || public._qa_s13_ok('N5A12.D10 the historical driver role row is preserved and non-authoritative',
        public.has_role(u_drv,'driver'::public.app_role)
        AND NOT public._driver_class_active(u_drv), NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ops), true);
  res := public.admin_professional_restore(u_drv, NULL, 'a12 driver restore');
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A12.D11 lane restoration does not restore operational approval',
        (res->>'restored')::boolean AND res->>'lane'='driver'
        AND (res->>'operational_authority_restored')::boolean IS FALSE
        AND public._driver_class_active(u_drv)
        AND (SELECT status::text FROM public.driver_profiles WHERE user_id=u_drv)='suspended', res::text);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ops), true);
  PERFORM public.driver_admin_decide(u_drv,'reactivate','a12');
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_drv), true);
  PERFORM public.driver_set_status('online'::public.driver_presence);
  PERFORM set_config('request.jwt.claims', NULL, true);
  SELECT count(*) INTO v_n FROM public.wallets WHERE owner_user_id=u_drv AND party_type='driver';
  r := r || public._qa_s13_ok('N5A12.D12 explicit reactivation restores operation without duplicating the wallet',
        (SELECT presence::text FROM public.driver_profiles WHERE user_id=u_drv)='online'
        AND v_n = 1, 'wallets='||v_n);

  -- ================= E. MERCHANT LIFECYCLE =================
  r := r || public._qa_s13_ok('N5A12.E1 merchant fixture holds lane, an approved store and a wallet',
        public._merchant_class_active(u_mer)
        AND (SELECT status FROM public.merchant_stores WHERE id=s_mer)='active'
        AND EXISTS (SELECT 1 FROM public.wallets WHERE owner_user_id=u_mer AND party_type='merchant'), NULL);
  r := r || public._qa_s13_ok('N5A12.E2 merchant workspace is available before offboarding',
        public.account_available_modes(u_mer) = ARRAY['client','merchant'], NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ops), true);
  res := public.admin_professional_offboard(u_mer,'a12 merchant offboard');
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A12.E3 admin offboarding of a merchant succeeds and names the lane',
        (res->>'offboarded')::boolean AND res->>'lane'='merchant', res::text);
  r := r || public._qa_s13_ok('N5A12.E4 the merchant lane is no longer active',
        public.professional_active_type(u_mer) IS NULL, NULL);
  r := r || public._qa_s13_ok('N5A12.E5 the merchant professional class is gone',
        NOT public._merchant_class_active(u_mer), NULL);
  r := r || public._qa_s13_ok('N5A12.E6 the store is preserved and suspended, not deleted or archived',
        (SELECT status FROM public.merchant_stores WHERE id=s_mer)='suspended'
        AND (SELECT owner_user_id FROM public.merchant_stores WHERE id=s_mer)=u_mer
        AND (SELECT onboarding_status FROM public.merchant_stores WHERE id=s_mer)='approved', NULL);
  r := r || public._qa_s13_ok('N5A12.E7 the merchant wallet survives offboarding',
        EXISTS (SELECT 1 FROM public.wallets WHERE owner_user_id=u_mer AND party_type='merchant'), NULL);
  BEGIN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(u_mer), true);
    PERFORM public.marche_listing_create(jsonb_build_object('store_id',s_mer,'title','a12','price_gnf',1000));
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A12.E8 an offboarded merchant cannot originate supply', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A12.E8 an offboarded merchant cannot originate supply',
          SQLERRM = ANY(refusals), SQLERRM);
  END;
  r := r || public._qa_s13_ok('N5A12.E9 an offboarded merchant keeps only the client workspace',
        public.account_available_modes(u_mer) = ARRAY['client'], NULL);
  SELECT count(*) INTO v_n FROM public.merchant_stores WHERE owner_user_id=u_mer;
  r := r || public._qa_s13_ok('N5A12.E10 offboarding created no extra store and destroyed none',
        v_n = 1, 'stores='||v_n);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ops), true);
  res := public.admin_professional_restore(u_mer, NULL, 'a12 merchant restore');
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A12.E11 lane restoration does not reactivate the store',
        (res->>'restored')::boolean AND res->>'lane'='merchant'
        AND public._merchant_class_active(u_mer)
        AND (SELECT status FROM public.merchant_stores WHERE id=s_mer)='suspended', res::text);
  UPDATE public.merchant_stores SET status='active' WHERE id=s_mer;
  SELECT count(*) INTO v_n FROM public.merchant_stores WHERE owner_user_id=u_mer;
  r := r || public._qa_s13_ok('N5A12.E12 explicit store reactivation restores merchant operation in place',
        (SELECT status FROM public.merchant_stores WHERE id=s_mer)='active'
        AND v_n = 1 AND public._merchant_class_active(u_mer), 'stores='||v_n);

  -- ================= F. OVERLAP — GOVERNANCE AXIS ISOLATION (admin + driver) =================
  r := r || public._qa_s13_ok('N5A12.F1 overlap fixture holds both axes lawfully',
        public._is_god_admin(u_ad) AND public._driver_class_active(u_ad)
        AND (SELECT status::text FROM public.driver_profiles WHERE user_id=u_ad)='approved', NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_god), true);
  PERFORM public.admin_governance_set_status(u_ad,'suspended','a12 governance-only revocation');
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A12.F2 governance revocation removes governance authority',
        NOT public.is_any_admin(u_ad) AND NOT public._is_god_admin(u_ad), NULL);
  r := r || public._qa_s13_ok('N5A12.F3 the driver lane survives governance revocation',
        public._driver_class_active(u_ad)
        AND public.professional_active_type(u_ad)='driver', NULL);
  r := r || public._qa_s13_ok('N5A12.F4 the driver profile survives governance revocation',
        (SELECT status::text FROM public.driver_profiles WHERE user_id=u_ad)='approved', NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ad), true);
  PERFORM public.driver_set_status('online'::public.driver_presence);
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A12.F5 the account retains lawful driver capability after governance revocation',
        (SELECT presence::text FROM public.driver_profiles WHERE user_id=u_ad)='online', NULL);
  r := r || public._qa_s13_ok('N5A12.F6 the professional wallet is untouched by governance revocation',
        EXISTS (SELECT 1 FROM public.wallets WHERE owner_user_id=u_ad AND party_type='driver'), NULL);
  r := r || public._qa_s13_ok('N5A12.F7 the driver workspace is still offered',
        public.account_available_modes(u_ad) = ARRAY['client','driver'], NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_god), true);
  PERFORM public.admin_governance_set_status(u_ad,'active','a12 governance restore');
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A12.F8 governance restoration returns only governance authority',
        public._is_god_admin(u_ad) AND public.professional_active_type(u_ad)='driver', NULL);
  SELECT count(*) INTO v_n FROM public.professional_identities WHERE user_id=u_ad;
  r := r || public._qa_s13_ok('N5A12.F9 governance transitions created no professional identity rows',
        v_n = 1, 'identity_rows='||v_n);
  SELECT count(*) INTO v_n FROM public.admin_users WHERE user_id=u_ad;
  r := r || public._qa_s13_ok('N5A12.F10 governance transitions neither duplicated nor deleted the grade row',
        v_n = 1 AND (SELECT status::text FROM public.admin_users WHERE user_id=u_ad)='active', 'grade_rows='||v_n);

  -- ================= G. OVERLAP — PROFESSIONAL AXIS ISOLATION (admin + merchant) =================
  r := r || public._qa_s13_ok('N5A12.G1 overlap fixture holds governance and a merchant lane',
        public._is_god_admin(u_am) AND public._merchant_class_active(u_am), NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ops), true);
  res := public.admin_professional_offboard(u_am,'a12 professional-only revocation');
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A12.G2 professional offboarding of an overlap account succeeds',
        (res->>'offboarded')::boolean AND res->>'lane'='merchant', res::text);
  r := r || public._qa_s13_ok('N5A12.G3 the merchant class is gone',
        NOT public._merchant_class_active(u_am)
        AND public.professional_active_type(u_am) IS NULL, NULL);
  r := r || public._qa_s13_ok('N5A12.G4 governance authority survives professional offboarding',
        public.is_any_admin(u_am) AND public._is_god_admin(u_am)
        AND public._is_ops_or_god_admin(u_am), NULL);
  r := r || public._qa_s13_ok('N5A12.G5 the governance grade row is untouched',
        (SELECT status::text FROM public.admin_users WHERE user_id=u_am)='active'
        AND (SELECT admin_role::text FROM public.admin_users WHERE user_id=u_am)='super_admin', NULL);
  r := r || public._qa_s13_ok('N5A12.G6 the store is preserved and suspended',
        (SELECT status FROM public.merchant_stores WHERE id=s_am)='suspended'
        AND (SELECT owner_user_id FROM public.merchant_stores WHERE id=s_am)=u_am, NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_am), true);
  res := public.professional_identity_conflict_audit();
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A12.G7 the account still exercises real governance capability',
        res IS NOT NULL AND jsonb_typeof(res) IN ('object','array'), jsonb_typeof(res));
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ops), true);
  res := public.admin_professional_restore(u_am,'merchant','a12 professional restore');
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A12.G8 professional restoration returns only the professional axis',
        public._merchant_class_active(u_am) AND public._is_god_admin(u_am), res::text);
  SELECT count(*) INTO v_n FROM public.admin_users;
  r := r || public._qa_s13_ok('N5A12.G9 professional transitions changed no governance census',
        v_n = b_au + 5, 'admin_users='||v_n);
  SELECT count(*) INTO v_n FROM public.professional_identities WHERE user_id=u_am;
  r := r || public._qa_s13_ok('N5A12.G10 release is terminal and restoration appends a new provenance row',
        v_n = 2
        AND EXISTS (SELECT 1 FROM public.professional_identities
                     WHERE user_id=u_am AND claim_state='released' AND released_at IS NOT NULL),
        'identity_rows='||v_n);

  -- ================= H. STALE UI / METADATA / ARTIFACT NON-AUTHORITY =================
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ad), true);
  PERFORM public.account_mode_set('driver');
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A12.H1 the overlap driver genuinely holds the driver workspace preference',
        (SELECT app_mode FROM public.user_preferences WHERE user_id=u_ad)='driver', NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ops), true);
  PERFORM public.admin_professional_offboard(u_ad,'a12 stale-state probe');
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A12.H2 the stale driver workspace preference row is still on disk',
        (SELECT app_mode FROM public.user_preferences WHERE user_id=u_ad)='driver', NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ad), true);
  res := public.account_mode_context();
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A12.H3 the effective workspace collapses to client despite the stale row',
        res->>'effective_mode'='client' AND res->>'professional_type'='none', res::text);
  BEGIN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ad), true);
    PERFORM public.driver_set_status('online'::public.driver_presence);
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A12.H4 a stale workspace preference grants no driver authority', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A12.H4 a stale workspace preference grants no driver authority',
          SQLERRM = ANY(refusals), SQLERRM);
  END;
  fake := (public._as_user_claims(u_ad)::jsonb
           || '{"professional_type":"driver","app_mode":"driver","claim_state":"active"}'::jsonb)::text;
  BEGIN
    PERFORM set_config('request.jwt.claims', fake, true);
    PERFORM public.driver_set_status('online'::public.driver_presence);
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A12.H5 a forged professional claim grants no driver authority', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A12.H5 a forged professional claim grants no driver authority',
          SQLERRM = ANY(refusals), SQLERRM);
  END;
  fake := (public._as_user_claims(u_out)::jsonb
           || '{"is_admin":true,"admin_role":"god_admin","role":"service_role"}'::jsonb)::text;
  BEGIN
    PERFORM set_config('request.jwt.claims', fake, true);
    PERFORM public.admin_professional_offboard(u_drv,'forged');
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A12.H6 a forged governance claim grants no offboarding authority', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A12.H6 a forged governance claim grants no offboarding authority',
          SQLERRM = 'NOT_AUTHORIZED', SQLERRM);
  END;
  r := r || public._qa_s13_ok('N5A12.H7 the retained driver role row grants no professional class',
        public.has_role(u_ad,'driver'::public.app_role) AND NOT public._driver_class_active(u_ad), NULL);
  r := r || public._qa_s13_ok('N5A12.H8 the retained driver profile artifact grants no professional class',
        EXISTS (SELECT 1 FROM public.driver_profiles WHERE user_id=u_ad)
        AND NOT public._driver_class_active(u_ad), NULL);
  r := r || public._qa_s13_ok('N5A12.H9 the retained professional wallet grants no professional class',
        EXISTS (SELECT 1 FROM public.wallets WHERE owner_user_id=u_ad AND party_type='driver')
        AND NOT public._driver_class_active(u_ad)
        AND public.account_available_modes(u_ad) = ARRAY['client'], NULL);
  r := r || public._qa_s13_ok('N5A12.H10 class helpers read canonical identity tables, never request claims',
        (SELECT bool_and(prosrc ~ 'professional_identities' AND prosrc !~ 'request\.jwt')
           FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
          WHERE n.nspname='public'
            AND p.proname IN ('_driver_class_active','_merchant_class_active',
                              'professional_active_type','account_available_modes')), NULL);

  -- ================= I. FINANCE-SAFE OFFBOARDING =================
  INSERT INTO public.mission_financial_holds(
    driver_user_id, party_type, party_user_id, mission_type, source_module, source_id,
    kind, amount_gnf, unrestricted_gnf, state)
  VALUES (u_fin,'driver',u_fin,'ride','qa_a12', gen_random_uuid(),
          'collateral', 1000, 1000, 'held');
  UPDATE public.wallets SET balance_gnf = 5000 WHERE owner_user_id=u_fin AND party_type='driver';
  r := r || public._qa_s13_ok('N5A12.I1 finance fixture holds an active lane and a real open hold',
        public._driver_class_active(u_fin)
        AND EXISTS (SELECT 1 FROM public.mission_financial_holds
                     WHERE driver_user_id=u_fin AND state='held'), NULL);
  res := public.professional_offboard_blockers(u_fin);
  r := r || public._qa_s13_ok('N5A12.I2 the blocker surface names the exact open obligation',
        (res->'blockers') @> '["DRIVER_OPEN_FINANCIAL_HOLD"]'::jsonb
        AND (res->>'eligible')::boolean IS FALSE, res::text);
  BEGIN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ops), true);
    PERFORM public.admin_professional_offboard(u_fin,'a12 unsafe');
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A12.I3 offboarding fails closed on an open financial hold', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A12.I3 offboarding fails closed on an open financial hold',
          SQLERRM LIKE 'PROFESSIONAL_OFFBOARD_BLOCKED:%DRIVER_OPEN_FINANCIAL_HOLD%', SQLERRM);
  END;
  r := r || public._qa_s13_ok('N5A12.I4 the blocked attempt left the lane active',
        public._driver_class_active(u_fin)
        AND (SELECT status::text FROM public.driver_profiles WHERE user_id=u_fin)='approved', NULL);
  r := r || public._qa_s13_ok('N5A12.I5 the blocked attempt did not touch the hold or the balance',
        EXISTS (SELECT 1 FROM public.mission_financial_holds
                 WHERE driver_user_id=u_fin AND state='held' AND amount_gnf=1000)
        AND (SELECT balance_gnf FROM public.wallets
              WHERE owner_user_id=u_fin AND party_type='driver') = 5000, NULL);
  UPDATE public.mission_financial_holds SET state='released', released_gnf=1000
   WHERE driver_user_id=u_fin AND state='held';
  UPDATE public.driver_profiles SET cash_debt_gnf = 2500 WHERE user_id=u_fin;
  res := public.professional_offboard_blockers(u_fin);
  BEGIN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ops), true);
    PERFORM public.admin_professional_offboard(u_fin,'a12 unsafe debt');
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A12.I6 offboarding fails closed on outstanding cash debt', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A12.I6 offboarding fails closed on outstanding cash debt',
          SQLERRM LIKE 'PROFESSIONAL_OFFBOARD_BLOCKED:%DRIVER_CASH_DEBT_OUTSTANDING%', SQLERRM);
  END;
  r := r || public._qa_s13_ok('N5A12.I7 the cash-debt blocker is reported before the attempt too',
        (res->'blockers') @> '["DRIVER_CASH_DEBT_OUTSTANDING"]'::jsonb
        AND NOT ((res->'blockers') @> '["DRIVER_OPEN_FINANCIAL_HOLD"]'::jsonb), res::text);
  UPDATE public.driver_profiles SET cash_debt_gnf = 0 WHERE user_id=u_fin;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ops), true);
  res := public.admin_professional_offboard(u_fin,'a12 safe offboard');
  PERFORM set_config('request.jwt.claims', NULL, true);
  SELECT balance_gnf INTO v_bal FROM public.wallets WHERE owner_user_id=u_fin AND party_type='driver';
  r := r || public._qa_s13_ok('N5A12.I8 a settled professional offboards cleanly with money intact',
        (res->>'offboarded')::boolean AND v_bal = 5000, 'balance='||v_bal);
  SELECT count(*) INTO v_n FROM public.wallets WHERE owner_user_id=u_fin;
  r := r || public._qa_s13_ok('N5A12.I9 the offboarded wallet is neither deleted nor duplicated',
        v_n = 1, 'wallets='||v_n);
  r := r || public._qa_s13_ok('N5A12.I10 the preserved wallet confers no professional class',
        NOT public._driver_class_active(u_fin)
        AND public.account_available_modes(u_fin) = ARRAY['client'], NULL);

  -- ================= J. AUDIT / PROVENANCE =================
  r := r || public._qa_s13_ok('N5A12.J1 professional offboarding is audited',
        EXISTS (SELECT 1 FROM public.audit_logs
                 WHERE action='professional_identity.admin_offboard' AND target_id=u_drv::text), NULL);
  r := r || public._qa_s13_ok('N5A12.J2 professional restoration is audited',
        EXISTS (SELECT 1 FROM public.audit_logs
                 WHERE action='professional_identity.admin_restore' AND target_id=u_drv::text), NULL);
  r := r || public._qa_s13_ok('N5A12.J3 governance status changes are audited with before and after',
        EXISTS (SELECT 1 FROM public.audit_logs
                 WHERE action='governance.set_status' AND target_id=u_adm::text
                   AND before->>'status'='active' AND after->>'status'='suspended'), NULL);
  r := r || public._qa_s13_ok('N5A12.J4 staff role revocation is audited',
        EXISTS (SELECT 1 FROM public.audit_logs
                 WHERE action='governance.role_revoke' AND target_id=u_stf::text
                   AND before->>'role'='field_captain'), NULL);
  r := r || public._qa_s13_ok('N5A12.J5 released identity rows retain their release provenance',
        EXISTS (SELECT 1 FROM public.professional_identities
                 WHERE user_id=u_drv AND claim_state='released'
                   AND released_at IS NOT NULL AND release_reason IS NOT NULL), NULL);
  SELECT count(*) INTO v_n FROM public.professional_identities WHERE user_id=u_drv;
  r := r || public._qa_s13_ok('N5A12.J6 identity history is appended, never overwritten',
        v_n = 2, 'identity_rows='||v_n);

  -- ================= CLEANUP =================
  PERFORM set_config('request.jwt.claims', NULL, true);
  DELETE FROM public.mission_financial_holds WHERE source_module='qa_a12';
  DELETE FROM public.driver_group_memberships WHERE driver_user_id = ANY(ids);
  DELETE FROM public.user_preferences WHERE user_id = ANY(ids);
  DELETE FROM public.driver_locations WHERE user_id = ANY(ids);
  DELETE FROM public.audit_logs WHERE actor_user_id = ANY(ids)
     OR target_id IN (SELECT x::text FROM unnest(ids) x);
  DELETE FROM public.marketplace_listings WHERE seller_id = ANY(ids) OR store_id IN (s_mer,s_am);
  DELETE FROM public.merchant_stores WHERE owner_user_id = ANY(ids);
  DELETE FROM public.wallets WHERE owner_user_id = ANY(ids);
  DELETE FROM public.driver_applications WHERE user_id = ANY(ids);
  DELETE FROM public.driver_profiles WHERE user_id = ANY(ids);
  DELETE FROM public.professional_identities WHERE user_id = ANY(ids);
  DELETE FROM public.admin_users WHERE user_id = ANY(ids);
  DELETE FROM public.user_roles WHERE user_id = ANY(ids);
  PERFORM public._qa_a5_cleanup(ids);

  SELECT count(*) INTO a_pi  FROM public.professional_identities;
  SELECT count(*) INTO a_au  FROM public.admin_users;
  SELECT count(*) INTO a_ur  FROM public.user_roles;
  SELECT count(*) INTO a_up  FROM public.user_preferences;
  SELECT count(*) INTO a_w   FROM public.wallets;
  SELECT count(*) INTO a_wt  FROM public.wallet_transactions;
  SELECT count(*) INTO a_lp  FROM public.ledger_postings;
  SELECT COALESCE(sum(amount_gnf),0) INTO a_ls FROM public.ledger_postings;
  SELECT count(*) INTO a_ms  FROM public.merchant_stores;
  SELECT count(*) INTO a_dp  FROM public.driver_profiles;
  SELECT count(*) INTO a_pr  FROM public.profiles;
  SELECT count(*) INTO a_al  FROM public.audit_logs;
  SELECT count(*) INTO a_mfh FROM public.mission_financial_holds;
  SELECT jsonb_object_agg(key, enabled) INTO a_flags FROM public.feature_flags;
  SELECT COALESCE(jsonb_agg(jsonb_build_array(user_id, admin_role, status) ORDER BY user_id),'[]'::jsonb)
    INTO a_gov FROM public.admin_users;

  r := r || public._qa_s13_ok('N5A12.K1 professional_identities returned to baseline', a_pi = b_pi, b_pi||'->'||a_pi);
  r := r || public._qa_s13_ok('N5A12.K2 admin_users returned to baseline', a_au = b_au, b_au||'->'||a_au);
  r := r || public._qa_s13_ok('N5A12.K3 full governance snapshot byte-identical to the pre-suite snapshot',
        a_gov = b_gov_initial, NULL);
  r := r || public._qa_s13_ok('N5A12.K4 user_roles returned to baseline', a_ur = b_ur, b_ur||'->'||a_ur);
  r := r || public._qa_s13_ok('N5A12.K5 user_preferences returned to baseline', a_up = b_up, b_up||'->'||a_up);
  r := r || public._qa_s13_ok('N5A12.K6 wallets returned to baseline', a_w = b_w, b_w||'->'||a_w);
  r := r || public._qa_s13_ok('N5A12.K7 wallet transactions returned to baseline', a_wt = b_wt, b_wt||'->'||a_wt);
  r := r || public._qa_s13_ok('N5A12.K8 ledger postings returned to baseline', a_lp = b_lp, b_lp||'->'||a_lp);
  r := r || public._qa_s13_ok('N5A12.K9 ledger sum returned to baseline', a_ls = b_ls, b_ls||'->'||a_ls);
  r := r || public._qa_s13_ok('N5A12.K10 merchant_stores returned to baseline', a_ms = b_ms, b_ms||'->'||a_ms);
  r := r || public._qa_s13_ok('N5A12.K11 driver_profiles returned to baseline', a_dp = b_dp, b_dp||'->'||a_dp);
  r := r || public._qa_s13_ok('N5A12.K12 profiles returned to baseline', a_pr = b_pr, b_pr||'->'||a_pr);
  r := r || public._qa_s13_ok('N5A12.K13 audit trail returned to baseline', a_al = b_al, b_al||'->'||a_al);
  r := r || public._qa_s13_ok('N5A12.K14 financial holds returned to baseline', a_mfh = b_mfh, b_mfh||'->'||a_mfh);
  r := r || public._qa_s13_ok('N5A12.K15 feature flags unchanged', a_flags = b_flags, NULL);
  r := r || public._qa_s13_ok('N5A12.K16 zero governance residue',
        NOT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = ANY(ids))
        AND NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = ANY(ids)), NULL);
  r := r || public._qa_s13_ok('N5A12.K17 zero professional residue',
        NOT EXISTS (SELECT 1 FROM public.professional_identities WHERE user_id = ANY(ids))
        AND NOT EXISTS (SELECT 1 FROM public.driver_profiles WHERE user_id = ANY(ids))
        AND NOT EXISTS (SELECT 1 FROM public.merchant_stores WHERE owner_user_id = ANY(ids)), NULL);
  r := r || public._qa_s13_ok('N5A12.K18 zero finance residue',
        NOT EXISTS (SELECT 1 FROM public.wallets WHERE owner_user_id = ANY(ids))
        AND NOT EXISTS (SELECT 1 FROM public.mission_financial_holds WHERE source_module='qa_a12'), NULL);

  RETURN jsonb_build_object(
    'fn','_qa_node5_identity_a12',
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'failures', (SELECT COALESCE(jsonb_agg(e),'[]'::jsonb) FROM jsonb_array_elements(r) e
                  WHERE (e->>'ok')::boolean IS NOT TRUE)
  );
EXCEPTION WHEN others THEN
  PERFORM set_config('request.jwt.claims', NULL, true);
  BEGIN
    DELETE FROM public.mission_financial_holds WHERE source_module='qa_a12';
    DELETE FROM public.driver_group_memberships WHERE driver_user_id = ANY(ids);
    DELETE FROM public.user_preferences WHERE user_id = ANY(ids);
    DELETE FROM public.driver_locations WHERE user_id = ANY(ids);
    DELETE FROM public.audit_logs WHERE actor_user_id = ANY(ids)
       OR target_id IN (SELECT x::text FROM unnest(ids) x);
    DELETE FROM public.marketplace_listings WHERE seller_id = ANY(ids) OR store_id IN (s_mer,s_am);
    DELETE FROM public.merchant_stores WHERE owner_user_id = ANY(ids);
    DELETE FROM public.wallets WHERE owner_user_id = ANY(ids);
    DELETE FROM public.driver_applications WHERE user_id = ANY(ids);
    DELETE FROM public.driver_profiles WHERE user_id = ANY(ids);
    DELETE FROM public.professional_identities WHERE user_id = ANY(ids);
    DELETE FROM public.admin_users WHERE user_id = ANY(ids);
    DELETE FROM public.user_roles WHERE user_id = ANY(ids);
    PERFORM public._qa_a5_cleanup(ids);
  EXCEPTION WHEN others THEN NULL; END;
  RAISE;
END $fn$;

REVOKE ALL ON FUNCTION public._qa_node5_identity_a12() FROM PUBLIC, anon, authenticated;