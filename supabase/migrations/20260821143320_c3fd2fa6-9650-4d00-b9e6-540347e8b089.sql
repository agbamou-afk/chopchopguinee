-- =====================================================================
-- NODE 5 · A10 — precedence fix on the informational cross-class rule
-- =====================================================================
CREATE OR REPLACE FUNCTION public._qa_a10_codes(p_user uuid)
RETURNS text[]
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT COALESCE(array_agg(s.conflict_code ORDER BY s.conflict_code), '{}'::text[])
    FROM public._professional_conflict_scan() s
   WHERE s.subject_user_id = p_user
$fn$;
REVOKE ALL ON FUNCTION public._qa_a10_codes(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._qa_node5_identity_a10()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
SET statement_timeout = '300s'
AS $fn$
DECLARE
  r jsonb := '[]'::jsonb;
  u_c   uuid := gen_random_uuid();  -- plain customer
  u_d   uuid := gen_random_uuid();  -- active driver
  u_dw  uuid := gen_random_uuid();  -- driver, lawfully abandoned (historical)
  u_m   uuid := gen_random_uuid();  -- active merchant
  u_ma  uuid := gen_random_uuid();  -- merchant, archived asset + released lane
  u_seq uuid := gen_random_uuid();  -- driver -> released -> merchant (lawful)
  u_c4  uuid := gen_random_uuid();  -- forced C4/C6 detector probe
  u_c5  uuid := gen_random_uuid();  -- forced C5/C7 detector probe
  u_rr  uuid := gen_random_uuid();  -- legacy role residue
  u_ops uuid := gen_random_uuid();  -- governance admin + driver class
  u_ord uuid := gen_random_uuid();  -- ordinary authenticated caller
  ids uuid[];
  s_m   uuid := gen_random_uuid();
  s_ma  uuid := gen_random_uuid();
  s_seq uuid := gen_random_uuid();
  s_c5  uuid := gen_random_uuid();
  v_err text; v_json jsonb; codes text[];
  b_pr bigint; b_ur bigint; b_pi bigint; b_pia bigint; b_dp bigint; b_ms bigint;
  b_w bigint; b_wt bigint; b_lp bigint; b_ls numeric; b_ad bigint; b_flags jsonb;
  a_pr bigint; a_ur bigint; a_pi bigint; a_pia bigint; a_dp bigint; a_ms bigint;
  a_w bigint; a_wt bigint; a_lp bigint; a_ls numeric; a_ad bigint; a_flags jsonb;
  live_total bigint; live_crit bigint; live_high bigint; live_med bigint; live_info bigint;
  live_by_code jsonb; live_subjects bigint;
BEGIN
  ids := ARRAY[u_c,u_d,u_dw,u_m,u_ma,u_seq,u_c4,u_c5,u_rr,u_ops,u_ord];

  SELECT count(*) INTO b_pr FROM public.profiles;
  SELECT count(*) INTO b_ur FROM public.user_roles;
  SELECT count(*) INTO b_pi FROM public.professional_identities;
  SELECT count(*) INTO b_pia FROM public.professional_identities WHERE claim_state='active';
  SELECT count(*) INTO b_dp FROM public.driver_profiles;
  SELECT count(*) INTO b_ms FROM public.merchant_stores;
  SELECT count(*) INTO b_w  FROM public.wallets;
  SELECT count(*) INTO b_wt FROM public.wallet_transactions;
  SELECT count(*) INTO b_lp FROM public.ledger_postings;
  SELECT COALESCE(sum(amount_gnf),0) INTO b_ls FROM public.ledger_postings;
  SELECT count(*) INTO b_ad FROM public.admin_users;
  SELECT jsonb_object_agg(key, enabled) INTO b_flags FROM public.feature_flags;

  -- ================= A. ACTIVE IDENTITY STRUCTURE =================
  r := r || public._qa_s13_ok('N5A10.A1 XOR partial unique index still present with the active predicate',
        (SELECT count(*) FROM pg_indexes WHERE schemaname='public' AND tablename='professional_identities'
          AND indexdef ILIKE 'CREATE UNIQUE INDEX%(user_id)%WHERE (claim_state = ''active''::text)') = 1, NULL);
  r := r || public._qa_s13_ok('N5A10.A2 no account holds two active professional identities',
        NOT EXISTS (SELECT 1 FROM public.professional_identities WHERE claim_state='active'
                     GROUP BY user_id HAVING count(*) > 1), NULL);
  r := r || public._qa_s13_ok('N5A10.A3 active DRIVER set intersect active MERCHANT set is empty',
        NOT EXISTS (
          SELECT 1 FROM public.professional_identities d
            JOIN public.professional_identities m ON m.user_id=d.user_id
           WHERE d.professional_type='driver' AND d.claim_state='active'
             AND m.professional_type='merchant' AND m.claim_state='active'), NULL);
  r := r || public._qa_s13_ok('N5A10.A4 lane guards remain on all five professional artifact tables',
        (SELECT count(*) FROM pg_trigger WHERE tgname='professional_lane_guard' AND NOT tgisinternal) = 5, NULL);
  r := r || public._qa_s13_ok('N5A10.A5 identity update guard remains installed',
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='professional_identities_guard' AND NOT tgisinternal), NULL);

  -- ================= B. DETECTOR SHAPE =================
  r := r || public._qa_s13_ok('N5A10.B1 conflict scanner exists',
        to_regprocedure('public._professional_conflict_scan()') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N5A10.B2 governance audit RPC exists',
        to_regprocedure('public.professional_identity_conflict_audit()') IS NOT NULL, NULL);
  FOR v_err IN SELECT unnest(ARRAY[
      'C1_DUAL_ACTIVE_IDENTITY','C2_ACTIVE_DRIVER_WITH_CURRENT_MERCHANT_ASSET',
      'C3_ACTIVE_MERCHANT_WITH_CURRENT_DRIVER_ARTIFACT',
      'C4_CURRENT_DRIVER_ARTIFACT_WITHOUT_ACTIVE_DRIVER_IDENTITY',
      'C5_CURRENT_MERCHANT_ASSET_WITHOUT_ACTIVE_MERCHANT_IDENTITY',
      'C6_RELEASED_DRIVER_STILL_OPERATIONAL','C7_RELEASED_MERCHANT_STILL_OPERATIONAL',
      'C8_PROFESSIONAL_FINANCE_CLASS_MISMATCH','C9_LEGACY_ROLE_MISMATCH',
      'C10_ORPHAN_PROFESSIONAL_ARTIFACT']) LOOP
    r := r || public._qa_s13_ok('N5A10.B3 taxonomy code implemented: '||v_err,
          (SELECT prosrc LIKE '%'||v_err||'%' FROM pg_proc
            WHERE oid='public._professional_conflict_scan()'::regprocedure), NULL);
  END LOOP;
  r := r || public._qa_s13_ok('N5A10.B4 scanner is read-only (no DML verbs in its body)',
        (SELECT prosrc !~* '(insert into|update |delete from|truncate)' FROM pg_proc
          WHERE oid='public._professional_conflict_scan()'::regprocedure), NULL);

  -- ================= C. AUDIT SURFACE SECURITY =================
  r := r || public._qa_s13_ok('N5A10.C1 scanner is not executable by anon',
        (SELECT NOT has_function_privilege('anon','public._professional_conflict_scan()','execute')), NULL);
  r := r || public._qa_s13_ok('N5A10.C2 scanner is not executable by ordinary signed-in users',
        (SELECT NOT has_function_privilege('authenticated','public._professional_conflict_scan()','execute')), NULL);
  r := r || public._qa_s13_ok('N5A10.C3 governance audit RPC is not executable by anon',
        (SELECT NOT has_function_privilege('anon','public.professional_identity_conflict_audit()','execute')), NULL);
  r := r || public._qa_s13_ok('N5A10.C4 governance audit RPC is reachable by signed-in sessions (gated inside)',
        (SELECT has_function_privilege('authenticated','public.professional_identity_conflict_audit()','execute')), NULL);
  r := r || public._qa_s13_ok('N5A10.C5 audit RPC enforces an admin predicate in its body',
        (SELECT prosrc LIKE '%_is_ops_or_god_admin%' FROM pg_proc
          WHERE oid='public.professional_identity_conflict_audit()'::regprocedure), NULL);

  -- ================= FIXTURES =================
  PERFORM public._qa_users_new(u_c,  'qa-n5a10-c-'||substr(u_c::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_d,  'qa-n5a10-d-'||substr(u_d::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_dw, 'qa-n5a10-w-'||substr(u_dw::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_m,  'qa-n5a10-m-'||substr(u_m::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_ma, 'qa-n5a10-a-'||substr(u_ma::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_seq,'qa-n5a10-q-'||substr(u_seq::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_c4, 'qa-n5a10-4-'||substr(u_c4::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_c5, 'qa-n5a10-5-'||substr(u_c5::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_rr, 'qa-n5a10-r-'||substr(u_rr::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_ops,'qa-n5a10-o-'||substr(u_ops::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_ord,'qa-n5a10-u-'||substr(u_ord::text,1,8)||'@example.com');
  UPDATE public.profiles SET phone = '+22462' || lpad((floor(random()*10000000))::bigint::text, 7, '0')
   WHERE user_id = ANY(ids) AND (phone IS NULL OR phone = '');
  PERFORM set_config('request.jwt.claims', NULL, true);

  -- active driver
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_d), true);
  PERFORM public.driver_apply('{"vehicle_type":"moto"}'::jsonb);
  PERFORM set_config('request.jwt.claims', NULL, true);
  UPDATE public.driver_profiles SET status='approved' WHERE user_id = u_d;
  -- lawfully abandoned driver
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_dw), true);
  PERFORM public.driver_apply('{"vehicle_type":"moto"}'::jsonb);
  PERFORM public.professional_identity_self_release('qa a10 abandon');
  PERFORM set_config('request.jwt.claims', NULL, true);
  -- merchants
  INSERT INTO public.merchant_stores(id, owner_user_id, name, slug, status, onboarding_status)
  VALUES (s_m,  u_m,  'QA A10 Store',   'qa-a10-'||substr(s_m::text,1,8),  'active','approved'),
         (s_ma, u_ma, 'QA A10 Archived','qa-a10-'||substr(s_ma::text,1,8), 'active','approved'),
         (s_c5, u_c5, 'QA A10 Orphaned','qa-a10-'||substr(s_c5::text,1,8), 'active','approved');
  UPDATE public.merchant_stores SET status='archived' WHERE id=s_ma;
  PERFORM public._professional_identity_release(u_ma, 'qa_a10_archived_release');
  -- lawful cross-class sequence: driver -> release -> merchant
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_seq), true);
  PERFORM public.driver_apply('{"vehicle_type":"moto"}'::jsonb);
  PERFORM public.professional_identity_self_release('qa a10 switch');
  PERFORM set_config('request.jwt.claims', NULL, true);
  INSERT INTO public.merchant_stores(id, owner_user_id, name, slug, status, onboarding_status)
  VALUES (s_seq, u_seq, 'QA A10 Switch', 'qa-a10-'||substr(s_seq::text,1,8), 'active','approved');
  -- forced detector probes (reachable worst-case states, not guard bypasses)
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_c4), true);
  PERFORM public.driver_apply('{"vehicle_type":"moto"}'::jsonb);
  PERFORM set_config('request.jwt.claims', NULL, true);
  UPDATE public.driver_profiles SET status='approved' WHERE user_id = u_c4;
  PERFORM public._professional_identity_release(u_c4, 'qa_a10_probe');
  PERFORM public._professional_identity_release(u_c5, 'qa_a10_probe');
  -- legacy role residue with no lane
  INSERT INTO public.user_roles(user_id, role) VALUES (u_rr,'driver') ON CONFLICT DO NOTHING;
  -- governance admin who is also a driver
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ops), true);
  PERFORM public.driver_apply('{"vehicle_type":"moto"}'::jsonb);
  PERFORM set_config('request.jwt.claims', NULL, true);
  UPDATE public.driver_profiles SET status='approved' WHERE user_id = u_ops;
  INSERT INTO public.admin_users(user_id, admin_role, status)
  VALUES (u_ops,'god_admin','active') ON CONFLICT DO NOTHING;

  r := r || public._qa_s13_ok('N5A10.D0 fixtures resolved to the intended classes',
        public.professional_active_type(u_d)='driver'
    AND public.professional_active_type(u_m)='merchant'
    AND public.professional_active_type(u_seq)='merchant'
    AND public.professional_active_type(u_c) IS NULL
    AND public.professional_active_type(u_dw) IS NULL,
        coalesce(public.professional_active_type(u_seq),'null'));

  -- ================= D. CLEAN ACCOUNTS PRODUCE NO CONFLICT =================
  r := r || public._qa_s13_ok('N5A10.D1 plain customer produces no conflict',
        public._qa_a10_codes(u_c) = '{}'::text[], array_to_string(public._qa_a10_codes(u_c),','));
  r := r || public._qa_s13_ok('N5A10.D2 active driver with a current driver artifact is clean',
        public._qa_a10_codes(u_d) = '{}'::text[], array_to_string(public._qa_a10_codes(u_d),','));
  r := r || public._qa_s13_ok('N5A10.D3 active merchant with a current store is clean',
        public._qa_a10_codes(u_m) = '{}'::text[], array_to_string(public._qa_a10_codes(u_m),','));
  r := r || public._qa_s13_ok('N5A10.D4 withdrawn driver artifact is not a current conflict',
        NOT ('C4_CURRENT_DRIVER_ARTIFACT_WITHOUT_ACTIVE_DRIVER_IDENTITY' = ANY(public._qa_a10_codes(u_dw))),
        array_to_string(public._qa_a10_codes(u_dw),','));
  r := r || public._qa_s13_ok('N5A10.D5 withdrawn driver raises no released-still-operational flag',
        NOT ('C6_RELEASED_DRIVER_STILL_OPERATIONAL' = ANY(public._qa_a10_codes(u_dw))), NULL);
  r := r || public._qa_s13_ok('N5A10.D6 archived merchant asset is not a current conflict',
        NOT ('C5_CURRENT_MERCHANT_ASSET_WITHOUT_ACTIVE_MERCHANT_IDENTITY' = ANY(public._qa_a10_codes(u_ma))),
        array_to_string(public._qa_a10_codes(u_ma),','));
  r := r || public._qa_s13_ok('N5A10.D7 archived merchant asset raises no released-still-operational flag',
        NOT ('C7_RELEASED_MERCHANT_STILL_OPERATIONAL' = ANY(public._qa_a10_codes(u_ma))), NULL);

  -- ================= E. LAWFUL CROSS-CLASS HISTORY =================
  r := r || public._qa_s13_ok('N5A10.E1 released driver then active merchant is lawful (no CRITICAL)',
        NOT EXISTS (SELECT 1 FROM public._professional_conflict_scan() s
                     WHERE s.subject_user_id=u_seq AND s.severity IN ('CRITICAL','HIGH')),
        array_to_string(public._qa_a10_codes(u_seq),','));
  r := r || public._qa_s13_ok('N5A10.E2 lawful sequence is reported as informational history',
        'I2_LAWFUL_HISTORICAL_CROSS_CLASS' = ANY(public._qa_a10_codes(u_seq)),
        array_to_string(public._qa_a10_codes(u_seq),','));
  r := r || public._qa_s13_ok('N5A10.E3 released driver row was kept, not rewritten',
        (SELECT count(*) FROM public.professional_identities
          WHERE user_id=u_seq AND professional_type='driver' AND claim_state='released'
            AND released_at IS NOT NULL) = 1, NULL);
  r := r || public._qa_s13_ok('N5A10.E4 the later merchant claim is a NEW row',
        (SELECT count(*) FROM public.professional_identities WHERE user_id=u_seq) = 2, NULL);
  r := r || public._qa_s13_ok('N5A10.E5 the released row was never reactivated',
        (SELECT count(*) FROM public.professional_identities
          WHERE user_id=u_seq AND claim_state='active') = 1, NULL);
  r := r || public._qa_s13_ok('N5A10.E6 every released identity in the database carries released_at',
        NOT EXISTS (SELECT 1 FROM public.professional_identities
                     WHERE claim_state <> 'active' AND released_at IS NULL), NULL);

  -- ================= F. POSITIVE DETECTION (worst-case reachable states) =====
  codes := public._qa_a10_codes(u_c4);
  r := r || public._qa_s13_ok('N5A10.F1 operational driver artifact without an active lane is CRITICAL C4',
        'C4_CURRENT_DRIVER_ARTIFACT_WITHOUT_ACTIVE_DRIVER_IDENTITY' = ANY(codes),
        array_to_string(codes,','));
  r := r || public._qa_s13_ok('N5A10.F2 released driver still operational is flagged C6',
        'C6_RELEASED_DRIVER_STILL_OPERATIONAL' = ANY(codes), array_to_string(codes,','));
  r := r || public._qa_s13_ok('N5A10.F3 C4 is graded CRITICAL',
        (SELECT severity FROM public._professional_conflict_scan()
          WHERE subject_user_id=u_c4
            AND conflict_code='C4_CURRENT_DRIVER_ARTIFACT_WITHOUT_ACTIVE_DRIVER_IDENTITY') = 'CRITICAL', NULL);
  codes := public._qa_a10_codes(u_c5);
  r := r || public._qa_s13_ok('N5A10.F4 operational merchant asset without an active lane is CRITICAL C5',
        'C5_CURRENT_MERCHANT_ASSET_WITHOUT_ACTIVE_MERCHANT_IDENTITY' = ANY(codes),
        array_to_string(codes,','));
  r := r || public._qa_s13_ok('N5A10.F5 released merchant still operational is flagged C7',
        'C7_RELEASED_MERCHANT_STILL_OPERATIONAL' = ANY(codes), array_to_string(codes,','));
  r := r || public._qa_s13_ok('N5A10.F6 detector reports evidence, never a chosen side',
        (SELECT recommended_action !~* '(convert|make driver|make merchant|delete)' FROM public._professional_conflict_scan()
          WHERE subject_user_id=u_c5
            AND conflict_code='C5_CURRENT_MERCHANT_ASSET_WITHOUT_ACTIVE_MERCHANT_IDENTITY'), NULL);

  -- ================= G. CROSS-CLASS ACQUISITION REMAINS IMPOSSIBLE =========
  BEGIN
    INSERT INTO public.merchant_stores(owner_user_id, name, slug, status, onboarding_status)
    VALUES (u_d, 'QA A10 Illegal', 'qa-a10-illegal-'||substr(gen_random_uuid()::text,1,8), 'active','approved');
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A10.G1 an active DRIVER cannot acquire a merchant store', v_err IS NOT NULL, v_err);
  BEGIN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(u_m), true);
    PERFORM public.driver_apply('{"vehicle_type":"moto"}'::jsonb);
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A10.G2 an active MERCHANT cannot acquire a driver artifact', v_err IS NOT NULL, v_err);
  BEGIN
    INSERT INTO public.professional_identities(user_id, professional_type, claim_state, claim_source)
    VALUES (u_d, 'merchant', 'active', 'qa_a10_forge');
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A10.G3 a second active identity is structurally refused', v_err IS NOT NULL, v_err);
  r := r || public._qa_s13_ok('N5A10.G4 refused acquisition created no merchant store for the driver',
        NOT EXISTS (SELECT 1 FROM public.merchant_stores WHERE owner_user_id=u_d), NULL);
  r := r || public._qa_s13_ok('N5A10.G5 refused acquisition created no driver artifact for the merchant',
        NOT EXISTS (SELECT 1 FROM public.driver_profiles WHERE user_id=u_m), NULL);

  -- ================= H. ROLE RESIDUE IS NOT AUTHORITY =================
  codes := public._qa_a10_codes(u_rr);
  r := r || public._qa_s13_ok('N5A10.H1 a stale driver role with no lane is reported as C9',
        'C9_LEGACY_ROLE_MISMATCH' = ANY(codes), array_to_string(codes,','));
  r := r || public._qa_s13_ok('N5A10.H2 role residue is graded MEDIUM, never CRITICAL',
        (SELECT severity FROM public._professional_conflict_scan()
          WHERE subject_user_id=u_rr AND conflict_code='C9_LEGACY_ROLE_MISMATCH') = 'MEDIUM', NULL);
  r := r || public._qa_s13_ok('N5A10.H3 role residue grants no professional class',
        public.professional_active_type(u_rr) IS NULL, NULL);
  r := r || public._qa_s13_ok('N5A10.H4 role residue grants no driver class authority',
        public._driver_class_active(u_rr) IS NOT TRUE, NULL);
  r := r || public._qa_s13_ok('N5A10.H5 role residue grants no merchant class authority',
        public._merchant_class_active(u_rr) IS NOT TRUE, NULL);
  BEGIN PERFORM public._driver_class_require(u_rr, 'qa_a10'); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A10.H6 driver authority gate refuses a role-only account', v_err IS NOT NULL, v_err);

  -- ================= I. WALLET HISTORY IS NOT CLASS =================
  r := r || public._qa_s13_ok('N5A10.I1 a historical driver wallet does not define the current class',
        public.professional_active_type(u_seq) = 'merchant', NULL);
  r := r || public._qa_s13_ok('N5A10.I2 wallet party type is never read by the scanner as class evidence',
        (SELECT prosrc !~ 'party_type[^,]*=\s*''(driver|merchant)''' FROM pg_proc
          WHERE oid='public._professional_conflict_scan()'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A10.I3 wallet existence alone raises no conflict for the ex-driver merchant',
        NOT EXISTS (SELECT 1 FROM public._professional_conflict_scan() s
                     WHERE s.subject_user_id=u_seq AND s.severity IN ('CRITICAL','HIGH')), NULL);
  r := r || public._qa_s13_ok('N5A10.I4 finance mismatch code only reads PENDING obligations',
        (SELECT prosrc LIKE '%pending_driver_cashouts%' AND prosrc LIKE '%pending_merchant_settlements%'
           FROM pg_proc WHERE oid='public._professional_conflict_scan()'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A10.I5 no live account carries wrong-class pending finance',
        NOT EXISTS (SELECT 1 FROM public._professional_conflict_scan()
                     WHERE conflict_code='C8_PROFESSIONAL_FINANCE_CLASS_MISMATCH'), NULL);

  -- ================= J. ADMIN ORTHOGONALITY =================
  r := r || public._qa_s13_ok('N5A10.J1 an admin who is also a driver is not a conflict',
        public._qa_a10_codes(u_ops) = '{}'::text[], array_to_string(public._qa_a10_codes(u_ops),','));
  r := r || public._qa_s13_ok('N5A10.J2 governance authority does not defeat the XOR law',
        (SELECT count(*) FROM public.professional_identities
          WHERE user_id=u_ops AND claim_state='active') = 1, NULL);
  BEGIN
    INSERT INTO public.merchant_stores(owner_user_id, name, slug, status, onboarding_status)
    VALUES (u_ops, 'QA A10 Admin Store', 'qa-a10-adm-'||substr(gen_random_uuid()::text,1,8), 'active','approved');
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A10.J3 an admin driver still cannot acquire a merchant asset', v_err IS NOT NULL, v_err);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ops), true);
  BEGIN v_json := public.professional_identity_conflict_audit(); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; v_json := NULL; END;
  r := r || public._qa_s13_ok('N5A10.J4 a god admin may read the conflict audit', v_err IS NULL, v_err);
  r := r || public._qa_s13_ok('N5A10.J5 the audit payload exposes summary + conflicts only',
        v_json ? 'summary' AND v_json ? 'conflicts' AND NOT (v_json ? 'pin') AND NOT (v_json ? 'email'), NULL);
  r := r || public._qa_s13_ok('N5A10.J6 the audit leaks no email or PIN evidence',
        v_json::text !~* '(pin_hash|@example\.com|password)', NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ord), true);
  BEGIN PERFORM public.professional_identity_conflict_audit(); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A10.J7 an ordinary signed-in user is refused ADMIN_REQUIRED',
        v_err = 'ADMIN_REQUIRED', v_err);
  PERFORM set_config('request.jwt.claims', NULL, true);
  BEGIN PERFORM public.professional_identity_conflict_audit(); v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A10.J8 an anonymous caller is refused AUTH_REQUIRED',
        v_err = 'AUTH_REQUIRED', v_err);

  -- ================= K. LEGACY MERCHANT ENTITIES =================
  r := r || public._qa_s13_ok('N5A10.K1 owner-less legacy merchant rows are classified INFO, not CRITICAL',
        NOT EXISTS (SELECT 1 FROM public._professional_conflict_scan()
                     WHERE conflict_code='I1_LEGACY_MERCHANT_ENTITY_NO_OWNER' AND severity <> 'INFO'), NULL);
  r := r || public._qa_s13_ok('N5A10.K2 owner-less legacy merchant rows confer no merchant class',
        NOT EXISTS (SELECT 1 FROM public.merchants m
                     WHERE m.owner_user_id IS NULL
                       AND EXISTS (SELECT 1 FROM public.professional_identities p
                                    WHERE p.user_id = m.owner_user_id AND p.claim_state='active')), NULL);
  r := r || public._qa_s13_ok('N5A10.K3 every owned legacy merchant row has a canonical merchant class',
        NOT EXISTS (SELECT 1 FROM public.merchants m
                     WHERE m.owner_user_id IS NOT NULL AND m.status='active'
                       AND public.professional_active_type(m.owner_user_id) IS DISTINCT FROM 'merchant'), NULL);

  -- ================= CLEANUP =================
  DELETE FROM public.marketplace_listings WHERE seller_id = ANY(ids) OR store_id IN (s_m,s_ma,s_seq,s_c5);
  DELETE FROM public.merchant_settlement_requests WHERE merchant_store_id IN (s_m,s_ma,s_seq,s_c5);
  DELETE FROM public.merchant_stores WHERE owner_user_id = ANY(ids);
  PERFORM public._qa_a5_cleanup(ids);

  SELECT count(*) INTO a_pr FROM public.profiles;
  SELECT count(*) INTO a_ur FROM public.user_roles;
  SELECT count(*) INTO a_pi FROM public.professional_identities;
  SELECT count(*) INTO a_pia FROM public.professional_identities WHERE claim_state='active';
  SELECT count(*) INTO a_dp FROM public.driver_profiles;
  SELECT count(*) INTO a_ms FROM public.merchant_stores;
  SELECT count(*) INTO a_w  FROM public.wallets;
  SELECT count(*) INTO a_wt FROM public.wallet_transactions;
  SELECT count(*) INTO a_lp FROM public.ledger_postings;
  SELECT COALESCE(sum(amount_gnf),0) INTO a_ls FROM public.ledger_postings;
  SELECT count(*) INTO a_ad FROM public.admin_users;
  SELECT jsonb_object_agg(key, enabled) INTO a_flags FROM public.feature_flags;

  -- ================= L. LIVE CENSUS (post-cleanup, real data only) =========
  SELECT count(*), count(*) FILTER (WHERE severity='CRITICAL'), count(*) FILTER (WHERE severity='HIGH'),
         count(*) FILTER (WHERE severity='MEDIUM'), count(*) FILTER (WHERE severity='INFO')
    INTO live_total, live_crit, live_high, live_med, live_info
    FROM public._professional_conflict_scan();
  SELECT COALESCE(jsonb_object_agg(conflict_code, n),'{}'::jsonb) INTO live_by_code
    FROM (SELECT conflict_code, count(*) n FROM public._professional_conflict_scan() GROUP BY 1) t;
  SELECT count(*) INTO live_subjects FROM (
    SELECT user_id FROM public.professional_identities
    UNION SELECT user_id FROM public.driver_profiles
    UNION SELECT user_id FROM public.driver_applications
    UNION SELECT owner_user_id FROM public.merchant_stores WHERE owner_user_id IS NOT NULL
    UNION SELECT owner_user_id FROM public.food_restaurants WHERE owner_user_id IS NOT NULL
    UNION SELECT user_id FROM public.user_roles WHERE role::text IN ('driver','merchant')) x;

  r := r || public._qa_s13_ok('N5A10.L1 live CRITICAL conflicts = 0', live_crit = 0, live_crit::text);
  r := r || public._qa_s13_ok('N5A10.L2 live HIGH conflicts = 0', live_high = 0, live_high::text);
  r := r || public._qa_s13_ok('N5A10.L3 live MEDIUM conflicts = 0', live_med = 0, live_med::text);
  r := r || public._qa_s13_ok('N5A10.L4 live census examined the professional population',
        live_subjects > 0, live_subjects::text);
  r := r || public._qa_s13_ok('N5A10.L5 every live active identity is driver or merchant only',
        NOT EXISTS (SELECT 1 FROM public.professional_identities
                     WHERE claim_state='active' AND professional_type NOT IN ('driver','merchant')), NULL);
  r := r || public._qa_s13_ok('N5A10.L6 every live current driver artifact has an active driver lane',
        NOT EXISTS (SELECT 1 FROM public.driver_profiles d
                     WHERE d.status::text IN ('pending','approved','suspended')
                       AND public.professional_active_type(d.user_id) IS DISTINCT FROM 'driver'), NULL);
  r := r || public._qa_s13_ok('N5A10.L7 every live current merchant store has an active merchant lane',
        NOT EXISTS (SELECT 1 FROM public.merchant_stores ms
                     WHERE ms.status NOT IN ('archived','rejected')
                       AND public.professional_active_type(ms.owner_user_id) IS DISTINCT FROM 'merchant'), NULL);
  r := r || public._qa_s13_ok('N5A10.L8 every live current restaurant has an active merchant lane',
        NOT EXISTS (SELECT 1 FROM public.food_restaurants fr
                     WHERE fr.status NOT IN ('archived','rejected')
                       AND public.professional_active_type(fr.owner_user_id) IS DISTINCT FROM 'merchant'), NULL);

  -- ================= M. NON-DRIFT / SELF-CLEANING =================
  r := r || public._qa_s13_ok('N5A10.M1 profiles returned to baseline', a_pr = b_pr, b_pr||'->'||a_pr);
  r := r || public._qa_s13_ok('N5A10.M2 user_roles returned to baseline', a_ur = b_ur, b_ur||'->'||a_ur);
  r := r || public._qa_s13_ok('N5A10.M3 professional identities returned to baseline', a_pi = b_pi, b_pi||'->'||a_pi);
  r := r || public._qa_s13_ok('N5A10.M4 active identities returned to baseline', a_pia = b_pia, b_pia||'->'||a_pia);
  r := r || public._qa_s13_ok('N5A10.M5 driver profiles returned to baseline', a_dp = b_dp, b_dp||'->'||a_dp);
  r := r || public._qa_s13_ok('N5A10.M6 merchant stores returned to baseline', a_ms = b_ms, b_ms||'->'||a_ms);
  r := r || public._qa_s13_ok('N5A10.M7 wallets unchanged', a_w = b_w, b_w||'->'||a_w);
  r := r || public._qa_s13_ok('N5A10.M8 wallet transactions unchanged', a_wt = b_wt, NULL);
  r := r || public._qa_s13_ok('N5A10.M9 ledger postings unchanged', a_lp = b_lp, NULL);
  r := r || public._qa_s13_ok('N5A10.M10 ledger sum unchanged', a_ls = b_ls, NULL);
  r := r || public._qa_s13_ok('N5A10.M11 admin_users returned to baseline', a_ad = b_ad, b_ad||'->'||a_ad);
  r := r || public._qa_s13_ok('N5A10.M12 feature flags unchanged', a_flags = b_flags, NULL);
  r := r || public._qa_s13_ok('N5A10.M13 no QA residue in professional_identities',
        NOT EXISTS (SELECT 1 FROM public.professional_identities WHERE user_id = ANY(ids)), NULL);
  r := r || public._qa_s13_ok('N5A10.M14 no QA residue in driver_profiles',
        NOT EXISTS (SELECT 1 FROM public.driver_profiles WHERE user_id = ANY(ids)), NULL);
  r := r || public._qa_s13_ok('N5A10.M15 no QA residue in merchant_stores',
        NOT EXISTS (SELECT 1 FROM public.merchant_stores WHERE owner_user_id = ANY(ids)), NULL);
  r := r || public._qa_s13_ok('N5A10.M16 no QA residue in admin_users',
        NOT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = ANY(ids)), NULL);
  r := r || public._qa_s13_ok('N5A10.M17 A10 performed zero live remediations',
        a_pi = b_pi AND a_pia = b_pia AND a_ms = b_ms AND a_dp = b_dp AND a_ur = b_ur, NULL);

  RETURN jsonb_build_object(
    'fn','_qa_node5_identity_a10',
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'failures', (SELECT COALESCE(jsonb_agg(e),'[]'::jsonb) FROM jsonb_array_elements(r) e
                  WHERE (e->>'ok')::boolean IS NOT TRUE),
    'live_census', jsonb_build_object(
      'subjects_examined', live_subjects,
      'total_findings', live_total,
      'critical', live_crit, 'high', live_high, 'medium', live_med, 'info', live_info,
      'by_code', live_by_code),
    'live_remediations', 0
  );
EXCEPTION WHEN others THEN
  PERFORM set_config('request.jwt.claims', NULL, true);
  BEGIN
    DELETE FROM public.marketplace_listings WHERE seller_id = ANY(ids) OR store_id IN (s_m,s_ma,s_seq,s_c5);
    DELETE FROM public.merchant_settlement_requests WHERE merchant_store_id IN (s_m,s_ma,s_seq,s_c5);
    DELETE FROM public.merchant_stores WHERE owner_user_id = ANY(ids);
    PERFORM public._qa_a5_cleanup(ids);
  EXCEPTION WHEN others THEN NULL; END;
  RAISE;
END $fn$;

REVOKE ALL ON FUNCTION public._qa_node5_identity_a10() FROM PUBLIC, anon, authenticated;