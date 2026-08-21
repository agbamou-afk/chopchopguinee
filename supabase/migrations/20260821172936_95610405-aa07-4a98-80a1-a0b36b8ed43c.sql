CREATE OR REPLACE FUNCTION public._qa_node5_identity_a11()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
SET statement_timeout TO '300s'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  u_admin uuid := gen_random_uuid();
  u_ops   uuid := gen_random_uuid();
  u_fin   uuid := gen_random_uuid();
  u_agent uuid := gen_random_uuid();
  u_field uuid := gen_random_uuid();
  u_onb   uuid := gen_random_uuid();
  u_drv   uuid := gen_random_uuid();
  u_mer   uuid := gen_random_uuid();
  u_ad    uuid := gen_random_uuid();
  u_am    uuid := gen_random_uuid();
  u_rel   uuid := gen_random_uuid();
  u_vic   uuid := gen_random_uuid();
  ids uuid[];
  s_mer uuid := gen_random_uuid();
  s_am  uuid := gen_random_uuid();
  tb text; v_bad text[] := '{}';
  res jsonb; forged text; v_wallet boolean;
  gov_tables text[] := ARRAY['admin_users','user_roles','approval_requests',
                             'agent_profiles','field_pilots','field_assignments','audit_logs'];
  gov_fns text[] := ARRAY['is_admin','is_any_admin','has_admin_role','_is_god_admin',
                          '_is_ops_or_god_admin','_finance_privileged','_repas_caller_is_staff'];
  prof_fns text[] := ARRAY['_driver_class_active','_driver_class_require','_merchant_class_active',
                           '_merchant_class_require','professional_active_type','account_available_modes'];
  refusals text[] := ARRAY[
    'AUTH_REQUIRED','PROFESSIONAL_IDENTITY_REQUIRED','PROFESSIONAL_IDENTITY_CONFLICT',
    'DRIVER_PROFILE_REQUIRED','DRIVER_NOT_OPERATIONAL','DRIVER_CAPABILITY_MISSING',
    'No driver profile','Offer not found','mission_not_found','ORDER_NOT_FOUND',
    'MERCHANT_STORE_NOT_FOUND','NOT_STORE_OWNER','not store owner',
    'MERCHANT_STORE_NOT_OPERATIONAL','INVALID_MODE'];
  b_pi bigint; b_pia bigint; b_au bigint; b_ur bigint; b_up bigint; b_w bigint; b_wt bigint;
  b_lp bigint; b_ls numeric; b_ms bigint; b_dp bigint; b_pr bigint; b_al bigint; b_flags jsonb;
  a_pi bigint; a_pia bigint; a_au bigint; a_ur bigint; a_up bigint; a_w bigint; a_wt bigint;
  a_lp bigint; a_ls numeric; a_ms bigint; a_dp bigint; a_pr bigint; a_al bigint; a_flags jsonb;
  b_gov_initial jsonb; b_gov_checkpoint jsonb; a_gov jsonb;
  b_fin_count bigint; b_fin_fp text; a_fin_count bigint; a_fin_fp text;
BEGIN
  ids := ARRAY[u_admin,u_ops,u_fin,u_agent,u_field,u_onb,u_drv,u_mer,u_ad,u_am,u_rel,u_vic];

  SELECT count(*) INTO b_pi  FROM public.professional_identities;
  SELECT count(*) INTO b_pia FROM public.professional_identities WHERE claim_state='active';
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
  SELECT jsonb_object_agg(key, enabled) INTO b_flags FROM public.feature_flags;
  -- Immutable pre-suite governance snapshot (never overwritten; H4 compares to this).
  SELECT COALESCE(jsonb_agg(jsonb_build_array(user_id, admin_role, status) ORDER BY user_id),'[]'::jsonb)
    INTO b_gov_initial FROM public.admin_users;
  -- Finance policy baseline: real count plus deterministic content fingerprint.
  SELECT count(*) INTO b_fin_count FROM public.finance_policies;
  SELECT md5(COALESCE(string_agg(t, '|' ORDER BY t), ''))
    INTO b_fin_fp
    FROM (SELECT to_jsonb(fp.*)::text AS t FROM public.finance_policies fp) s;

  -- ============ A. STRUCTURE / CANONICAL SOURCES ============
  r := r || public._qa_s13_ok('N5A11.A1 governance storage is admin_users plus user_roles only',
        to_regclass('public.admin_users') IS NOT NULL AND to_regclass('public.user_roles') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N5A11.A2 professional class storage is professional_identities',
        to_regclass('public.professional_identities') IS NOT NULL, NULL);
  v_bad := '{}';
  FOREACH tb IN ARRAY gov_fns LOOP
    IF (SELECT bool_or(prosrc ~ 'professional_identities' OR prosrc ~ 'driver_profiles'
                       OR prosrc ~ 'user_preferences' OR prosrc ~ 'app_mode')
          FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname='public' AND p.proname=tb) THEN
      v_bad := v_bad || tb;
    END IF;
  END LOOP;
  r := r || public._qa_s13_ok('N5A11.A3 no governance predicate reads professional identity or mode',
        array_length(v_bad,1) IS NULL, array_to_string(v_bad,','));
  v_bad := '{}';
  FOREACH tb IN ARRAY prof_fns LOOP
    IF (SELECT bool_or(prosrc ~ 'admin_users' OR prosrc ~ 'has_admin_role' OR prosrc ~ 'is_any_admin'
                       OR prosrc ~ 'is_admin' OR prosrc ~ 'god_admin')
          FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname='public' AND p.proname=tb) THEN
      v_bad := v_bad || tb;
    END IF;
  END LOOP;
  r := r || public._qa_s13_ok('N5A11.A4 no professional predicate reads governance state',
        array_length(v_bad,1) IS NULL, array_to_string(v_bad,','));
  r := r || public._qa_s13_ok('N5A11.A5 mode derivation is professional-only, never governance',
        (SELECT prosrc ~ 'professional_active_type' AND prosrc !~ 'admin' AND prosrc !~ 'user_roles'
           FROM pg_proc WHERE oid='public.account_available_modes(uuid)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A11.A6 lane claim never consults governance',
        (SELECT prosrc !~ 'admin_users' AND prosrc !~ 'has_admin_role' AND prosrc !~ 'user_roles'
           FROM pg_proc WHERE oid='public._professional_identity_claim(uuid,text,text)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A11.A7 admin_users carries no professional class column',
        NOT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_schema='public' AND table_name='admin_users'
                       AND column_name ~ '(professional|driver|merchant|lane|app_mode)'),
        (SELECT string_agg(column_name,',') FROM information_schema.columns
          WHERE table_schema='public' AND table_name='admin_users'));
  r := r || public._qa_s13_ok('N5A11.A8 professional_identities carries no governance column',
        NOT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_schema='public' AND table_name='professional_identities'
                       AND column_name ~ '(admin|staff|role)'),
        (SELECT string_agg(column_name,',') FROM information_schema.columns
          WHERE table_schema='public' AND table_name='professional_identities'));
  v_bad := '{}';
  FOREACH tb IN ARRAY gov_tables LOOP
    IF has_table_privilege('anon','public.'||tb,'SELECT')
       OR has_table_privilege('anon','public.'||tb,'INSERT')
       OR has_table_privilege('anon','public.'||tb,'UPDATE')
       OR has_table_privilege('anon','public.'||tb,'DELETE')
       OR has_table_privilege('anon','public.'||tb,'TRUNCATE') THEN
      v_bad := v_bad || tb;
    END IF;
  END LOOP;
  r := r || public._qa_s13_ok('N5A11.A9 anon holds no privilege on any governance table',
        array_length(v_bad,1) IS NULL, array_to_string(v_bad,','));
  v_bad := '{}';
  FOREACH tb IN ARRAY gov_tables LOOP
    IF has_table_privilege('authenticated','public.'||tb,'TRUNCATE')
       OR has_table_privilege('authenticated','public.'||tb,'DELETE')
       OR has_table_privilege('authenticated','public.'||tb,'TRIGGER')
       OR has_table_privilege('authenticated','public.'||tb,'REFERENCES') THEN
      v_bad := v_bad || tb;
    END IF;
  END LOOP;
  r := r || public._qa_s13_ok('N5A11.A10 signed-in clients cannot delete, truncate or re-wire governance tables',
        array_length(v_bad,1) IS NULL, array_to_string(v_bad,','));
  v_bad := '{}';
  FOREACH tb IN ARRAY gov_tables LOOP
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = ('public.'||tb)::regclass) THEN
      v_bad := v_bad || tb;
    END IF;
  END LOOP;
  r := r || public._qa_s13_ok('N5A11.A11 every governance table enforces row level security',
        array_length(v_bad,1) IS NULL, array_to_string(v_bad,','));
  r := r || public._qa_s13_ok('N5A11.A12 audit trail is read-only for signed-in clients',
        has_table_privilege('authenticated','public.audit_logs','SELECT')
        AND NOT has_table_privilege('authenticated','public.audit_logs','INSERT')
        AND NOT has_table_privilege('authenticated','public.audit_logs','UPDATE'), NULL);
  r := r || public._qa_s13_ok('N5A11.A13 admin_users mutation policy is super-admin scoped',
        EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='admin_users'
                 AND cmd='ALL' AND COALESCE(qual,'') ~ 'has_admin_role'
                 AND COALESCE(with_check,'') ~ 'has_admin_role'), NULL);
  r := r || public._qa_s13_ok('N5A11.A14 user_roles mutation stays super-admin scoped (A9 preserved)',
        NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='user_roles'
                     AND cmd <> 'SELECT'
                     AND (COALESCE(qual,'') !~ 'has_admin_role' OR COALESCE(with_check,'') !~ 'has_admin_role')), NULL);
  r := r || public._qa_s13_ok('N5A11.A15 no RLS policy mixes governance and professional predicates',
        NOT EXISTS (SELECT 1 FROM pg_policies
                     WHERE schemaname='public'
                       AND (COALESCE(qual,'')||COALESCE(with_check,'')) ~ 'professional_identities'
                       AND (COALESCE(qual,'')||COALESCE(with_check,'')) ~ 'admin_users'),
        (SELECT string_agg(tablename||'.'||policyname,',') FROM pg_policies
          WHERE schemaname='public'
            AND (COALESCE(qual,'')||COALESCE(with_check,'')) ~ 'professional_identities'
            AND (COALESCE(qual,'')||COALESCE(with_check,'')) ~ 'admin_users'));
  r := r || public._qa_s13_ok('N5A11.A16 professional identity table is not writable by clients',
        NOT has_table_privilege('authenticated','public.professional_identities','INSERT')
        AND NOT has_table_privilege('authenticated','public.professional_identities','UPDATE')
        AND NOT has_table_privilege('anon','public.professional_identities','SELECT'), NULL);
  r := r || public._qa_s13_ok('N5A11.A17 internal conflict scanner stays server-only',
        NOT has_function_privilege('anon','public._professional_conflict_scan()','EXECUTE')
        AND NOT has_function_privilege('authenticated','public._professional_conflict_scan()','EXECUTE'), NULL);

  -- ============ FIXTURES ============
  PERFORM public._qa_users_new(u_admin,'qa-n5a11-adm-'||substr(u_admin::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_ops,  'qa-n5a11-ops-'||substr(u_ops::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_fin,  'qa-n5a11-fin-'||substr(u_fin::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_agent,'qa-n5a11-agt-'||substr(u_agent::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_field,'qa-n5a11-fld-'||substr(u_field::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_onb,  'qa-n5a11-onb-'||substr(u_onb::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_drv,  'qa-n5a11-drv-'||substr(u_drv::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_mer,  'qa-n5a11-mer-'||substr(u_mer::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_ad,   'qa-n5a11-ad-' ||substr(u_ad::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_am,   'qa-n5a11-am-' ||substr(u_am::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_rel,  'qa-n5a11-rel-'||substr(u_rel::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_vic,  'qa-n5a11-vic-'||substr(u_vic::text,1,8)||'@example.com');
  UPDATE public.profiles SET phone = '+22462' || lpad((floor(random()*10000000))::bigint::text, 7, '0')
   WHERE user_id = ANY(ids) AND (phone IS NULL OR phone = '');

  INSERT INTO public.admin_users(user_id, admin_role, status) VALUES
    (u_admin,'super_admin','active'),
    (u_ops,  'operations_admin','active'),
    (u_fin,  'finance_admin','active'),
    (u_ad,   'super_admin','active'),
    (u_am,   'operations_admin','active'),
    (u_rel,  'super_admin','active')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.user_roles(user_id, role) VALUES
    (u_admin,'admin'), (u_field,'field_captain'), (u_onb,'onboarding_specialist')
  ON CONFLICT DO NOTHING;
  INSERT INTO public.agent_profiles(user_id, business_name, status)
  VALUES (u_agent, 'QA A11 Agent', 'active')
  ON CONFLICT DO NOTHING;

  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_drv), true);
  PERFORM public.driver_apply('{"vehicle_type":"moto"}'::jsonb);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ad), true);
  PERFORM public.driver_apply('{"vehicle_type":"moto"}'::jsonb);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_rel), true);
  PERFORM public.driver_apply('{"vehicle_type":"moto"}'::jsonb);
  PERFORM set_config('request.jwt.claims', NULL, true);
  UPDATE public.driver_profiles SET status='approved' WHERE user_id IN (u_drv, u_ad);

  INSERT INTO public.merchant_stores(id, owner_user_id, name, slug, status, onboarding_status)
  VALUES (s_mer, u_mer, 'QA A11 Store M', 'qa-a11-m-'||substr(s_mer::text,1,8), 'active','approved'),
         (s_am,  u_am,  'QA A11 Store AM','qa-a11-am-'||substr(s_am::text,1,8), 'active','approved');

  -- ============ B. GOVERNANCE DOES NOT IMPLY PROFESSIONAL ============
  r := r || public._qa_s13_ok('N5A11.B1 super admin has no professional class',
        public.professional_active_type(u_admin) IS NULL, NULL);
  r := r || public._qa_s13_ok('N5A11.B2 super admin exposes the client workspace only',
        public.account_available_modes(u_admin) = ARRAY['client'],
        array_to_string(public.account_available_modes(u_admin),','));
  r := r || public._qa_s13_ok('N5A11.B3 super admin is not a driver class',
        NOT public._driver_class_active(u_admin), NULL);
  r := r || public._qa_s13_ok('N5A11.B4 super admin is not a merchant class',
        NOT public._merchant_class_active(u_admin), NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_admin), true);
  res := public.account_mode_set('driver');
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A11.B5 super admin cannot select a driver workspace',
        res->>'effective_mode' = 'client' AND (res->>'refused')::boolean, res::text);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_admin), true);
  res := public.account_mode_set('merchant');
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A11.B6 super admin cannot select a merchant workspace',
        res->>'effective_mode' = 'client' AND (res->>'refused')::boolean, res::text);
  BEGIN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(u_admin), true);
    PERFORM public.driver_set_status('online'::public.driver_presence);
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A11.B7 super admin cannot go online as a driver', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A11.B7 super admin cannot go online as a driver',
          SQLERRM = ANY(refusals), SQLERRM);
  END;
  BEGIN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(u_admin), true);
    PERFORM public.driver_offer_accept(gen_random_uuid());
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A11.B8 super admin cannot accept a driver offer', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A11.B8 super admin cannot accept a driver offer',
          SQLERRM = ANY(refusals), SQLERRM);
  END;
  BEGIN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(u_admin), true);
    PERFORM public.marche_listing_create(jsonb_build_object('store_id',s_mer,'title','a11','price_gnf',1000));
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A11.B9 super admin cannot create merchant supply', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A11.B9 super admin cannot create merchant supply',
          SQLERRM = ANY(refusals), SQLERRM);
  END;
  BEGIN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(u_admin), true);
    PERFORM public.merchant_submit_location(s_mer, 9.5, -13.7, 'a11-admin', NULL, NULL, NULL, NULL);
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A11.B10 super admin is refused store ownership on a store it does not own',
          false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A11.B10 super admin is refused store ownership on a store it does not own',
          SQLERRM IN ('not store owner','NOT_STORE_OWNER'), SQLERRM);
  END;
  r := r || public._qa_s13_ok('N5A11.B11 admin traffic created no professional identity',
        NOT EXISTS (SELECT 1 FROM public.professional_identities WHERE user_id=u_admin), NULL);
  r := r || public._qa_s13_ok('N5A11.B12 admin traffic created no driver profile',
        NOT EXISTS (SELECT 1 FROM public.driver_profiles WHERE user_id=u_admin), NULL);
  r := r || public._qa_s13_ok('N5A11.B13 admin traffic created no store',
        NOT EXISTS (SELECT 1 FROM public.merchant_stores WHERE owner_user_id=u_admin), NULL);
  r := r || public._qa_s13_ok('N5A11.B14 admin traffic created no professional wallet',
        NOT EXISTS (SELECT 1 FROM public.wallets WHERE owner_user_id=u_admin
                     AND COALESCE(party_type::text,'') IN ('driver','merchant')), NULL);
  r := r || public._qa_s13_ok('N5A11.B15 admin traffic granted no driver capability',
        NOT public.driver_has_capability(u_admin,'marche_shopper'), NULL);
  r := r || public._qa_s13_ok('N5A11.B16 admin is still a lawful non-conflict under A10 taxonomy',
        public._professional_actor_class(u_admin) IS NOT NULL, public._professional_actor_class(u_admin));

  -- ============ C. STAFF CLASSES ============
  r := r || public._qa_s13_ok('N5A11.C1 operations admin has no professional class',
        public.professional_active_type(u_ops) IS NULL
        AND public.account_available_modes(u_ops) = ARRAY['client'], NULL);
  r := r || public._qa_s13_ok('N5A11.C2 operations governance predicate is satisfied legitimately',
        public._is_ops_or_god_admin(u_ops) AND public.is_any_admin(u_ops), NULL);
  r := r || public._qa_s13_ok('N5A11.C3 operations admin is not god admin',
        NOT public._is_god_admin(u_ops), NULL);
  r := r || public._qa_s13_ok('N5A11.C4 finance admin has no professional class',
        public.professional_active_type(u_fin) IS NULL
        AND public.account_available_modes(u_fin) = ARRAY['client'], NULL);
  r := r || public._qa_s13_ok('N5A11.C5 finance governance predicate is satisfied legitimately',
        public._finance_privileged(u_fin), NULL);
  r := r || public._qa_s13_ok('N5A11.C6 finance admin is neither driver nor merchant class',
        NOT public._driver_class_active(u_fin) AND NOT public._merchant_class_active(u_fin), NULL);
  BEGIN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(u_fin), true);
    PERFORM public.driver_set_status('online'::public.driver_presence);
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A11.C7 finance admin cannot operate as a driver', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A11.C7 finance admin cannot operate as a driver',
          SQLERRM = ANY(refusals), SQLERRM);
  END;
  r := r || public._qa_s13_ok('N5A11.C8 service agent staff has no professional class',
        public.professional_active_type(u_agent) IS NULL
        AND public.account_available_modes(u_agent) = ARRAY['client'], NULL);
  r := r || public._qa_s13_ok('N5A11.C9 agent staff row grants no admin authority',
        NOT public.is_any_admin(u_agent) AND NOT public._is_ops_or_god_admin(u_agent)
        AND NOT public._finance_privileged(u_agent), NULL);
  r := r || public._qa_s13_ok('N5A11.C10 agent staff is not an approved merchant service agent',
        NOT public._is_approved_service_agent(u_agent), NULL);
  r := r || public._qa_s13_ok('N5A11.C11 field captain has no professional class',
        public.professional_active_type(u_field) IS NULL
        AND public.account_available_modes(u_field) = ARRAY['client'], NULL);
  r := r || public._qa_s13_ok('N5A11.C12 field captain role is readable as a staff role only',
        public.has_role(u_field,'field_captain'::public.app_role)
        AND NOT public.is_any_admin(u_field), NULL);
  r := r || public._qa_s13_ok('N5A11.C13 onboarding specialist has no professional class',
        public.professional_active_type(u_onb) IS NULL
        AND public.account_available_modes(u_onb) = ARRAY['client'], NULL);
  r := r || public._qa_s13_ok('N5A11.C14 onboarding specialist holds no admin predicate',
        NOT public.is_any_admin(u_onb) AND NOT public._is_god_admin(u_onb), NULL);
  BEGIN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(u_onb), true);
    PERFORM public.marche_listing_create(jsonb_build_object('store_id',s_mer,'title','a11-onb','price_gnf',1000));
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A11.C15 onboarding staff cannot create merchant supply', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A11.C15 onboarding staff cannot create merchant supply',
          SQLERRM = ANY(refusals), SQLERRM);
  END;
  r := r || public._qa_s13_ok('N5A11.C16 no staff fixture produced a professional identity',
        NOT EXISTS (SELECT 1 FROM public.professional_identities
                     WHERE user_id IN (u_admin,u_ops,u_fin,u_agent,u_field,u_onb)), NULL);

  -- ============ D. PROFESSIONAL DOES NOT IMPLY GOVERNANCE ============
  r := r || public._qa_s13_ok('N5A11.D1 approved driver fixture is a real driver class',
        public._driver_class_active(u_drv), NULL);
  r := r || public._qa_s13_ok('N5A11.D2 driver satisfies no admin predicate',
        NOT public.is_admin(u_drv) AND NOT public.is_any_admin(u_drv)
        AND NOT public._is_god_admin(u_drv) AND NOT public._is_ops_or_god_admin(u_drv), NULL);
  r := r || public._qa_s13_ok('N5A11.D3 driver satisfies no finance predicate',
        NOT public._finance_privileged(u_drv), NULL);
  r := r || public._qa_s13_ok('N5A11.D4 driver holds no admin_role grade',
        NOT public.has_admin_role(u_drv,'super_admin'::admin_role)
        AND NOT public.has_admin_role(u_drv,'operations_admin'::admin_role)
        AND NOT public.has_admin_role(u_drv,'finance_admin'::admin_role), NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_drv), true);
  r := r || public._qa_s13_ok('N5A11.D5 driver does not read as repas staff',
        NOT public._repas_caller_is_staff(), NULL);
  res := public.admin_ban_user(u_vic, 'a11 adversarial ban attempt');
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A11.D6 driver cannot execute a governance RPC',
        (res->>'ok')::boolean IS FALSE AND res->>'error' = 'forbidden', res::text);
  r := r || public._qa_s13_ok('N5A11.D7 the governance RPC attempt banned nobody',
        (SELECT account_status FROM public.profiles WHERE user_id=u_vic) <> 'banned'
        AND NOT EXISTS (SELECT 1 FROM public.account_bans WHERE user_id=u_vic), NULL);
  r := r || public._qa_s13_ok('N5A11.D8 merchant fixture is a real merchant class',
        public._merchant_class_active(u_mer), NULL);
  r := r || public._qa_s13_ok('N5A11.D9 merchant satisfies no governance predicate',
        NOT public.is_any_admin(u_mer) AND NOT public._is_god_admin(u_mer)
        AND NOT public._is_ops_or_god_admin(u_mer) AND NOT public._finance_privileged(u_mer), NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_mer), true);
  res := public.admin_ban_user(u_vic, 'a11 adversarial merchant ban attempt');
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A11.D10 merchant cannot execute a governance RPC',
        (res->>'ok')::boolean IS FALSE AND res->>'error' = 'forbidden', res::text);
  forged := jsonb_build_object('sub',u_drv::text,'role','authenticated','app_mode','client',
              'is_admin',true,'admin_role','god_admin','user_role','admin',
              'professional_type','driver')::text;
  PERFORM set_config('request.jwt.claims', forged, true);
  res := public.admin_ban_user(u_vic, 'a11 forged admin claim ban attempt');
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A11.D11 forged admin JWT claims grant no governance authority',
        (res->>'ok')::boolean IS FALSE AND res->>'error' = 'forbidden', res::text);
  r := r || public._qa_s13_ok('N5A11.D12 forged admin claims created no admin_users row',
        NOT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id IN (u_drv,u_mer)), NULL);
  r := r || public._qa_s13_ok('N5A11.D13 forged admin claims created no admin role row',
        NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id IN (u_drv,u_mer)
                     AND role::text IN ('admin','god_admin','operations_admin','finance_admin')), NULL);
  INSERT INTO public.user_preferences(user_id, app_mode) VALUES (u_drv,'driver')
    ON CONFLICT (user_id) DO UPDATE SET app_mode='driver';
  r := r || public._qa_s13_ok('N5A11.D14 selecting a professional workspace grants no governance',
        NOT public.is_any_admin(u_drv) AND NOT public._finance_privileged(u_drv), NULL);
  -- D15: prove the wallet actually exists before claiming it grants nothing.
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_drv), true);
  PERFORM public.driver_set_status('online'::public.driver_presence);
  PERFORM set_config('request.jwt.claims', NULL, true);
  SELECT EXISTS (SELECT 1 FROM public.wallets
                  WHERE owner_user_id=u_drv AND party_type::text='driver') INTO v_wallet;
  r := r || public._qa_s13_ok('N5A11.D15 an existing professional wallet grants no governance',
        v_wallet AND NOT public.is_any_admin(u_drv) AND NOT public.is_admin(u_drv)
        AND NOT public._finance_privileged(u_drv),
        'wallet_exists=' || v_wallet::text);

  -- ============ E. LAWFUL OVERLAP ============
  r := r || public._qa_s13_ok('N5A11.E1 admin plus driver coexist on both axes',
        public._is_god_admin(u_ad) AND public._driver_class_active(u_ad), NULL);
  r := r || public._qa_s13_ok('N5A11.E2 overlap account exposes the driver workspace from the lane, not the badge',
        public.account_available_modes(u_ad) = ARRAY['client','driver'],
        array_to_string(public.account_available_modes(u_ad),','));
  r := r || public._qa_s13_ok('N5A11.E3 admin plus merchant coexist on both axes',
        public._is_ops_or_god_admin(u_am) AND public._merchant_class_active(u_am), NULL);
  r := r || public._qa_s13_ok('N5A11.E4 merchant overlap exposes the merchant workspace only',
        public.account_available_modes(u_am) = ARRAY['client','merchant'],
        array_to_string(public.account_available_modes(u_am),','));
  r := r || public._qa_s13_ok('N5A11.E5 overlap is not an A10 conflict',
        public._professional_actor_class(u_ad) IS NOT NULL, public._professional_actor_class(u_ad));
  BEGIN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ad), true);
    PERFORM public.marche_listing_create(jsonb_build_object('store_id',s_am,'title','a11-overlap','price_gnf',1000));
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A11.E6 admin-driver overlap cannot act as a merchant', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A11.E6 admin-driver overlap cannot act as a merchant',
          SQLERRM = ANY(refusals), SQLERRM);
  END;
  BEGIN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(u_am), true);
    PERFORM public.driver_set_status('online'::public.driver_presence);
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A11.E7 admin-merchant overlap cannot act as a driver', false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A11.E7 admin-merchant overlap cannot act as a driver',
          SQLERRM = ANY(refusals), SQLERRM);
  END;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ad), true);
  PERFORM public.driver_set_status('online'::public.driver_presence);
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A11.E8 overlap driver operates from the real lane and approval',
        (SELECT presence::text FROM public.driver_profiles WHERE user_id=u_ad) = 'online',
        (SELECT presence::text FROM public.driver_profiles WHERE user_id=u_ad));
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ad), true);
  res := public.admin_ban_user(u_vic, 'a11 overlap lawful governance probe');
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A11.E9 overlap admin authority comes from real governance, and it works',
        (res->>'ok')::boolean IS TRUE, res::text);
  DELETE FROM public.account_bans WHERE user_id = u_vic;
  UPDATE public.profiles SET account_status='active' WHERE user_id = u_vic;
  DELETE FROM public.admin_users WHERE user_id = u_ad;
  r := r || public._qa_s13_ok('N5A11.E10 revoking governance leaves the professional lane intact',
        public._driver_class_active(u_ad)
        AND public.account_available_modes(u_ad) = ARRAY['client','driver'], NULL);
  r := r || public._qa_s13_ok('N5A11.E11 revoking governance leaves the driver approval intact',
        (SELECT status FROM public.driver_profiles WHERE user_id=u_ad)::text = 'approved', NULL);
  r := r || public._qa_s13_ok('N5A11.E12 revoking governance removes only governance',
        NOT public._is_god_admin(u_ad) AND NOT public.is_any_admin(u_ad), NULL);
  PERFORM public._professional_identity_release(u_rel, 'qa_a11_release');
  r := r || public._qa_s13_ok('N5A11.E13 releasing a lane leaves governance authority intact',
        public._is_god_admin(u_rel) AND public.is_any_admin(u_rel), NULL);
  r := r || public._qa_s13_ok('N5A11.E14 releasing a lane clears only professional truth',
        public.professional_active_type(u_rel) IS NULL
        AND public.account_available_modes(u_rel) = ARRAY['client'], NULL);

  -- ============ F. CROSS-AXIS TRANSITION ISOLATION ============
  -- Live (non-fixture) checkpoint; distinct from the immutable pre-suite snapshot.
  b_gov_checkpoint := (SELECT COALESCE(jsonb_agg(jsonb_build_array(user_id, admin_role, status) ORDER BY user_id),'[]'::jsonb)
              FROM public.admin_users WHERE NOT (user_id = ANY(ids)));
  r := r || public._qa_s13_ok('N5A11.F1 driver claim created no governance row',
        NOT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id IN (u_drv,u_mer))
        AND NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id IN (u_drv,u_mer)
                         AND role::text <> 'client'), NULL);
  r := r || public._qa_s13_ok('N5A11.F2 lane release created or removed no governance row',
        (SELECT count(*) FROM public.admin_users WHERE user_id=u_rel) = 1, NULL);
  INSERT INTO public.admin_users(user_id, admin_role, status)
  VALUES (u_drv,'operations_admin','active') ON CONFLICT DO NOTHING;
  r := r || public._qa_s13_ok('N5A11.F3 granting governance to a driver changes no professional truth',
        public.professional_active_type(u_drv) = 'driver'
        AND public.account_available_modes(u_drv) = ARRAY['client','driver'], NULL);
  r := r || public._qa_s13_ok('N5A11.F4 granting governance created no second professional identity',
        (SELECT count(*) FROM public.professional_identities WHERE user_id=u_drv AND claim_state='active') = 1, NULL);
  DELETE FROM public.admin_users WHERE user_id = u_drv;
  r := r || public._qa_s13_ok('N5A11.F5 revoking that governance still changes no professional truth',
        public.professional_active_type(u_drv) = 'driver', NULL);
  INSERT INTO public.admin_users(user_id, admin_role, status)
  VALUES (u_agent,'operations_admin','active') ON CONFLICT DO NOTHING;
  r := r || public._qa_s13_ok('N5A11.F6 granting governance to staff creates no professional lane',
        public.professional_active_type(u_agent) IS NULL
        AND public.account_available_modes(u_agent) = ARRAY['client'], NULL);
  DELETE FROM public.admin_users WHERE user_id = u_agent;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ad), true);
  PERFORM public.account_mode_set('driver');
  PERFORM public.account_mode_set('client');
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A11.F7 mode switching changed neither axis',
        public.professional_active_type(u_ad) = 'driver'
        AND NOT public.is_any_admin(u_ad), NULL);
  r := r || public._qa_s13_ok('N5A11.F8 no live governance row was touched by A11 fixtures',
        (SELECT COALESCE(jsonb_agg(jsonb_build_array(user_id, admin_role, status) ORDER BY user_id),'[]'::jsonb)
           FROM public.admin_users WHERE NOT (user_id = ANY(ids))) = b_gov_checkpoint, NULL);

  -- ============ G. FINANCE NON-INTERFERENCE ============
  r := r || public._qa_s13_ok('N5A11.G1 no governance fixture owns a professional wallet',
        NOT EXISTS (SELECT 1 FROM public.wallets
                     WHERE owner_user_id IN (u_admin,u_ops,u_fin,u_field,u_onb)
                       AND COALESCE(party_type::text,'') IN ('driver','merchant')), NULL);
  r := r || public._qa_s13_ok('N5A11.G2 ledger postings unchanged during A11 probes',
        (SELECT count(*) FROM public.ledger_postings) = b_lp, NULL);
  r := r || public._qa_s13_ok('N5A11.G3 ledger sum unchanged during A11 probes',
        (SELECT COALESCE(sum(amount_gnf),0) FROM public.ledger_postings) = b_ls, NULL);
  r := r || public._qa_s13_ok('N5A11.G4 wallet transactions unchanged during A11 probes',
        (SELECT count(*) FROM public.wallet_transactions) = b_wt, NULL);
  SELECT count(*) INTO a_fin_count FROM public.finance_policies;
  SELECT md5(COALESCE(string_agg(t, '|' ORDER BY t), ''))
    INTO a_fin_fp
    FROM (SELECT to_jsonb(fp.*)::text AS t FROM public.finance_policies fp) s;
  r := r || public._qa_s13_ok('N5A11.G5 finance policy rows byte-identical to the pre-suite baseline',
        a_fin_count = b_fin_count AND a_fin_fp = b_fin_fp,
        b_fin_count||':'||b_fin_fp||' -> '||a_fin_count||':'||a_fin_fp);

  -- ============ CLEANUP ============
  PERFORM set_config('request.jwt.claims', NULL, true);
  DELETE FROM public.user_preferences WHERE user_id = ANY(ids);
  DELETE FROM public.driver_locations WHERE user_id = ANY(ids);
  DELETE FROM public.account_bans WHERE user_id = ANY(ids);
  DELETE FROM public.audit_logs WHERE actor_user_id = ANY(ids)
     OR target_id IN (SELECT x::text FROM unnest(ids) x);
  DELETE FROM public.marketplace_listings WHERE seller_id = ANY(ids) OR store_id IN (s_mer,s_am);
  DELETE FROM public.merchant_stores WHERE owner_user_id = ANY(ids);
  DELETE FROM public.agent_profiles WHERE user_id = ANY(ids);
  DELETE FROM public.admin_users WHERE user_id = ANY(ids);
  DELETE FROM public.user_roles WHERE user_id = ANY(ids);
  PERFORM public._qa_a5_cleanup(ids);

  SELECT count(*) INTO a_pi  FROM public.professional_identities;
  SELECT count(*) INTO a_pia FROM public.professional_identities WHERE claim_state='active';
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
  SELECT jsonb_object_agg(key, enabled) INTO a_flags FROM public.feature_flags;
  SELECT COALESCE(jsonb_agg(jsonb_build_array(user_id, admin_role, status) ORDER BY user_id),'[]'::jsonb)
    INTO a_gov FROM public.admin_users;

  r := r || public._qa_s13_ok('N5A11.H1 professional_identities returned to baseline', a_pi = b_pi, b_pi||'->'||a_pi);
  r := r || public._qa_s13_ok('N5A11.H2 active professional census unchanged', a_pia = b_pia, b_pia||'->'||a_pia);
  r := r || public._qa_s13_ok('N5A11.H3 admin_users returned to baseline', a_au = b_au, b_au||'->'||a_au);
  r := r || public._qa_s13_ok('N5A11.H4 full governance snapshot byte-identical to the pre-suite snapshot',
        a_gov = b_gov_initial, NULL);
  r := r || public._qa_s13_ok('N5A11.H5 user_roles returned to baseline', a_ur = b_ur, b_ur||'->'||a_ur);
  r := r || public._qa_s13_ok('N5A11.H6 user_preferences returned to baseline', a_up = b_up, b_up||'->'||a_up);
  r := r || public._qa_s13_ok('N5A11.H7 wallets returned to baseline', a_w = b_w, b_w||'->'||a_w);
  r := r || public._qa_s13_ok('N5A11.H8 wallet transactions returned to baseline', a_wt = b_wt, NULL);
  r := r || public._qa_s13_ok('N5A11.H9 ledger postings returned to baseline', a_lp = b_lp, NULL);
  r := r || public._qa_s13_ok('N5A11.H10 ledger sum returned to baseline', a_ls = b_ls, NULL);
  r := r || public._qa_s13_ok('N5A11.H11 merchant_stores returned to baseline', a_ms = b_ms, b_ms||'->'||a_ms);
  r := r || public._qa_s13_ok('N5A11.H12 driver_profiles returned to baseline', a_dp = b_dp, b_dp||'->'||a_dp);
  r := r || public._qa_s13_ok('N5A11.H13 profiles returned to baseline', a_pr = b_pr, b_pr||'->'||a_pr);
  r := r || public._qa_s13_ok('N5A11.H14 audit trail returned to baseline', a_al = b_al, b_al||'->'||a_al);
  r := r || public._qa_s13_ok('N5A11.H15 feature flags unchanged', a_flags = b_flags, NULL);
  r := r || public._qa_s13_ok('N5A11.H16 zero governance residue',
        NOT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = ANY(ids))
        AND NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = ANY(ids))
        AND NOT EXISTS (SELECT 1 FROM public.agent_profiles WHERE user_id = ANY(ids)), NULL);
  r := r || public._qa_s13_ok('N5A11.H17 zero professional residue',
        NOT EXISTS (SELECT 1 FROM public.professional_identities WHERE user_id = ANY(ids))
        AND NOT EXISTS (SELECT 1 FROM public.driver_profiles WHERE user_id = ANY(ids))
        AND NOT EXISTS (SELECT 1 FROM public.merchant_stores WHERE owner_user_id = ANY(ids)), NULL);

  RETURN jsonb_build_object(
    'fn','_qa_node5_identity_a11',
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'failures', (SELECT COALESCE(jsonb_agg(e),'[]'::jsonb) FROM jsonb_array_elements(r) e
                  WHERE (e->>'ok')::boolean IS NOT TRUE)
  );
EXCEPTION WHEN others THEN
  PERFORM set_config('request.jwt.claims', NULL, true);
  BEGIN
    DELETE FROM public.user_preferences WHERE user_id = ANY(ids);
    DELETE FROM public.driver_locations WHERE user_id = ANY(ids);
    DELETE FROM public.account_bans WHERE user_id = ANY(ids);
    UPDATE public.profiles SET account_status='active' WHERE user_id = ANY(ids);
    DELETE FROM public.audit_logs WHERE actor_user_id = ANY(ids)
       OR target_id IN (SELECT x::text FROM unnest(ids) x);
    DELETE FROM public.marketplace_listings WHERE seller_id = ANY(ids) OR store_id IN (s_mer,s_am);
    DELETE FROM public.merchant_stores WHERE owner_user_id = ANY(ids);
    DELETE FROM public.agent_profiles WHERE user_id = ANY(ids);
    DELETE FROM public.admin_users WHERE user_id = ANY(ids);
    DELETE FROM public.user_roles WHERE user_id = ANY(ids);
    PERFORM public._qa_a5_cleanup(ids);
  EXCEPTION WHEN others THEN NULL; END;
  RAISE;
END $function$;

REVOKE ALL ON FUNCTION public._qa_node5_identity_a11() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node5_identity_a11() TO service_role;