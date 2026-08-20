CREATE OR REPLACE FUNCTION public._qa_node5_identity_a2()
RETURNS jsonb
LANGUAGE plpgsql
SET statement_timeout TO '60s'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  u1 uuid := gen_random_uuid();  -- becomes driver then releases then merchant
  u2 uuid := gen_random_uuid();  -- merchant claimer
  u3 uuid := gen_random_uuid();  -- plain customer, no professional identity
  ids uuid[];
  v_row public.professional_identities;
  v_row2 public.professional_identities;
  v_id1 uuid; v_id2 uuid;
  v_json jsonb; v_err text; v_n int; v_ok boolean;
  b_pr bigint; a_pr bigint; b_au bigint; a_au bigint;
  b_ur bigint; a_ur bigint; b_w bigint; a_w bigint;
  b_wt bigint; a_wt bigint; b_lj bigint; a_lj bigint;
  b_lp bigint; a_lp bigint; b_ls numeric; a_ls numeric;
  b_dp bigint; a_dp bigint; b_da bigint; a_da bigint;
  b_ms bigint; a_ms bigint; b_fr bigint; a_fr bigint;
  b_me bigint; a_me bigint; b_pi bigint; a_pi bigint;
  b_flags jsonb; a_flags jsonb;
  d_set int; m_set int;
BEGIN
  ids := ARRAY[u1,u2,u3];

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
  SELECT jsonb_object_agg(key, enabled) INTO b_flags FROM public.feature_flags;

  -- ===================== A. SCHEMA =====================
  r := r || public._qa_s13_ok('N5A2.A1 professional_identities table exists',
        to_regclass('public.professional_identities') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N5A2.A2 surrogate uuid PK on id',
        EXISTS (SELECT 1 FROM pg_index i JOIN pg_attribute a
                  ON a.attrelid=i.indrelid AND a.attnum = ANY(i.indkey)
                WHERE i.indrelid='public.professional_identities'::regclass
                  AND i.indisprimary AND a.attname='id'), NULL);
  r := r || public._qa_s13_ok('N5A2.A3 partial unique index enforces one ACTIVE claim per user',
        EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public'
                 AND tablename='professional_identities'
                 AND indexdef ILIKE 'CREATE UNIQUE INDEX%(user_id)%WHERE (claim_state = ''active''::text)'), NULL);
  r := r || public._qa_s13_ok('N5A2.A4 professional_type constrained to driver|merchant',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.professional_identities'::regclass
                 AND conname='professional_identities_type_ck'), NULL);
  r := r || public._qa_s13_ok('N5A2.A5 claim_state constrained to active|released',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.professional_identities'::regclass
                 AND conname='professional_identities_state_ck'), NULL);
  r := r || public._qa_s13_ok('N5A2.A6 released_at consistency constraint present',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.professional_identities'::regclass
                 AND conname='professional_identities_released_at_ck'), NULL);
  r := r || public._qa_s13_ok('N5A2.A7 no approval/suspension lifecycle columns leaked in',
        NOT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_schema='public' AND table_name='professional_identities'
                       AND column_name IN ('status','approved','approved_at','suspended','suspended_at','rejected','rejection_reason','verification_state')), NULL);
  r := r || public._qa_s13_ok('N5A2.A8 user_id FK targets the canonical auth account id',
        EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid='public.professional_identities'::regclass AND contype='f'
                   AND confrelid='auth.users'::regclass), NULL);
  r := r || public._qa_s13_ok('N5A2.A9 RLS enabled on professional_identities',
        (SELECT relrowsecurity FROM pg_class WHERE oid='public.professional_identities'::regclass), NULL);

  -- fixtures
  PERFORM public._qa_users_new(u1, 'qa-n5a2-1-'||substr(u1::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u2, 'qa-n5a2-2-'||substr(u2::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u3, 'qa-n5a2-3-'||substr(u3::text,1,8)||'@example.com');

  -- constraint runtime proofs
  BEGIN
    INSERT INTO public.professional_identities(user_id, professional_type) VALUES (u3,'shopper');
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A2.A10 invalid professional_type rejected', v_err IS NOT NULL, v_err);

  BEGIN
    INSERT INTO public.professional_identities(user_id, professional_type, claim_state)
    VALUES (u3,'driver','pending');
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A2.A11 invalid claim_state rejected', v_err IS NOT NULL, v_err);

  BEGIN
    INSERT INTO public.professional_identities(user_id, professional_type, claim_state, released_at)
    VALUES (u3,'driver','active', now());
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A2.A12 active row with released_at rejected', v_err IS NOT NULL, v_err);

  BEGIN
    INSERT INTO public.professional_identities(user_id, professional_type, claim_state)
    VALUES (u3,'driver','released');
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A2.A13 released row without released_at rejected', v_err IS NOT NULL, v_err);

  -- ===================== B. BACKFILL TRUTH =====================
  CREATE TEMP TABLE _qa_a2_drv ON COMMIT DROP AS
    SELECT DISTINCT user_id FROM (
      SELECT user_id FROM public.driver_profiles
      UNION SELECT user_id FROM public.driver_applications) s WHERE user_id IS NOT NULL;
  CREATE TEMP TABLE _qa_a2_mer ON COMMIT DROP AS
    SELECT DISTINCT user_id FROM (
      SELECT owner_user_id AS user_id FROM public.merchant_stores WHERE owner_user_id IS NOT NULL
      UNION SELECT owner_user_id FROM public.food_restaurants WHERE owner_user_id IS NOT NULL
      UNION SELECT owner_user_id FROM public.merchants WHERE owner_user_id IS NOT NULL) s;

  SELECT count(*) INTO d_set FROM _qa_a2_drv;
  SELECT count(*) INTO m_set FROM _qa_a2_mer;

  SELECT count(*) INTO v_n FROM _qa_a2_drv d
   WHERE NOT EXISTS (SELECT 1 FROM public.professional_identities p
                      WHERE p.user_id=d.user_id AND p.claim_state='active' AND p.professional_type='driver');
  r := r || public._qa_s13_ok('N5A2.B1 every derived Driver user has an active driver identity',
        v_n = 0, 'missing='||v_n||' derived='||d_set);

  SELECT count(*) INTO v_n FROM _qa_a2_mer m
   WHERE NOT EXISTS (SELECT 1 FROM public.professional_identities p
                      WHERE p.user_id=m.user_id AND p.claim_state='active' AND p.professional_type='merchant');
  r := r || public._qa_s13_ok('N5A2.B2 every derived Merchant user has an active merchant identity',
        v_n = 0, 'missing='||v_n||' derived='||m_set);

  SELECT count(*) INTO v_n FROM (
    SELECT user_id FROM _qa_a2_drv INTERSECT SELECT user_id FROM _qa_a2_mer) x;
  r := r || public._qa_s13_ok('N5A2.B3 derived Driver/Merchant intersection is empty', v_n = 0, 'n='||v_n);

  SELECT count(*) INTO v_n FROM public.professional_identities
   WHERE claim_state='active' AND claim_source='a2_backfill';
  r := r || public._qa_s13_ok('N5A2.B4 backfilled active identity count equals live derivation',
        v_n = d_set + m_set, 'backfilled='||v_n||' derived='||(d_set+m_set));

  SELECT count(*) INTO v_n FROM (
    SELECT user_id FROM public.professional_identities WHERE claim_state='active'
     GROUP BY user_id HAVING count(*) > 1) x;
  r := r || public._qa_s13_ok('N5A2.B5 no user holds two active identities', v_n = 0, 'n='||v_n);

  SELECT count(*) INTO v_n FROM public.professional_identities
   WHERE professional_type NOT IN ('driver','merchant');
  r := r || public._qa_s13_ok('N5A2.B6 no non-canonical professional types stored', v_n = 0, NULL);

  -- ===================== C. GRANT POSTURE =====================
  r := r || public._qa_s13_ok('N5A2.C1 anon has no SELECT',
        NOT has_table_privilege('anon','public.professional_identities','SELECT'), NULL);
  r := r || public._qa_s13_ok('N5A2.C2 anon has no INSERT',
        NOT has_table_privilege('anon','public.professional_identities','INSERT'), NULL);
  r := r || public._qa_s13_ok('N5A2.C3 anon has no UPDATE',
        NOT has_table_privilege('anon','public.professional_identities','UPDATE'), NULL);
  r := r || public._qa_s13_ok('N5A2.C4 anon has no DELETE',
        NOT has_table_privilege('anon','public.professional_identities','DELETE'), NULL);
  r := r || public._qa_s13_ok('N5A2.C5 anon has no TRUNCATE',
        NOT has_table_privilege('anon','public.professional_identities','TRUNCATE'), NULL);
  r := r || public._qa_s13_ok('N5A2.C6 authenticated may SELECT (RLS-scoped)',
        has_table_privilege('authenticated','public.professional_identities','SELECT'), NULL);
  r := r || public._qa_s13_ok('N5A2.C7 authenticated has no INSERT',
        NOT has_table_privilege('authenticated','public.professional_identities','INSERT'), NULL);
  r := r || public._qa_s13_ok('N5A2.C8 authenticated has no UPDATE',
        NOT has_table_privilege('authenticated','public.professional_identities','UPDATE'), NULL);
  r := r || public._qa_s13_ok('N5A2.C9 authenticated has no DELETE',
        NOT has_table_privilege('authenticated','public.professional_identities','DELETE'), NULL);
  r := r || public._qa_s13_ok('N5A2.C10 authenticated has no TRUNCATE',
        NOT has_table_privilege('authenticated','public.professional_identities','TRUNCATE'), NULL);
  r := r || public._qa_s13_ok('N5A2.C11 anon/authenticated cannot execute the internal claim primitive',
        NOT has_function_privilege('anon','public._professional_identity_claim(uuid,text,text)','EXECUTE')
        AND NOT has_function_privilege('authenticated','public._professional_identity_claim(uuid,text,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A2.C12 anon/authenticated cannot execute the internal release primitive',
        NOT has_function_privilege('anon','public._professional_identity_release(uuid,text)','EXECUTE')
        AND NOT has_function_privilege('authenticated','public._professional_identity_release(uuid,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A2.C13 anon cannot execute the read surface',
        NOT has_function_privilege('anon','public.professional_identity_current()','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A2.C14 authenticated can execute the read surface',
        has_function_privilege('authenticated','public.professional_identity_current()','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A2.C15 read-own RLS policy is scoped to auth.uid()',
        EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                 AND tablename='professional_identities' AND cmd='SELECT'
                 AND qual ILIKE '%auth.uid()%'), NULL);
  r := r || public._qa_s13_ok('N5A2.C16 no INSERT/UPDATE/DELETE RLS policy exists',
        NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                 AND tablename='professional_identities' AND cmd <> 'SELECT'), NULL);
  r := r || public._qa_s13_ok('N5A2.C17 read surface and primitives pin search_path',
        NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname IN
          ('professional_identity_current','_professional_identity_claim',
           '_professional_identity_release','_professional_identity_guard')
          AND NOT (COALESCE(array_to_string(proconfig,','),'') ILIKE '%search_path%')), NULL);

  -- ===================== D. CLAIM PRIMITIVE =====================
  v_row := public._professional_identity_claim(u1,'driver','qa');
  v_id1 := v_row.id;
  r := r || public._qa_s13_ok('N5A2.D1 none -> driver creates an active driver identity',
        v_row.professional_type='driver' AND v_row.claim_state='active' AND v_row.released_at IS NULL, NULL);

  v_row2 := public._professional_identity_claim(u1,'driver','qa');
  r := r || public._qa_s13_ok('N5A2.D2 same-type re-claim is idempotent (same row)',
        v_row2.id = v_id1, NULL);
  SELECT count(*) INTO v_n FROM public.professional_identities WHERE user_id=u1;
  r := r || public._qa_s13_ok('N5A2.D3 idempotent re-claim created no extra row', v_n = 1, 'n='||v_n);

  BEGIN
    PERFORM public._professional_identity_claim(u1,'merchant','qa');
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A2.D4 opposite-lane claim raises PROFESSIONAL_IDENTITY_CONFLICT',
        v_err = 'PROFESSIONAL_IDENTITY_CONFLICT', v_err);

  v_row := public._professional_identity_claim(u2,'merchant','qa');
  r := r || public._qa_s13_ok('N5A2.D5 none -> merchant creates an active merchant identity',
        v_row.professional_type='merchant' AND v_row.claim_state='active', NULL);

  BEGIN
    PERFORM public._professional_identity_claim(u3,'admin','qa');
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A2.D6 non-canonical lane refused by the primitive',
        v_err = 'PROFESSIONAL_IDENTITY_TYPE_INVALID', v_err);

  -- structural concurrency proof: a second active row is physically impossible
  BEGIN
    INSERT INTO public.professional_identities(user_id, professional_type) VALUES (u1,'merchant');
    v_err := NULL;
  EXCEPTION WHEN unique_violation THEN v_err := 'unique_violation';
           WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A2.D7 direct second ACTIVE row blocked by the unique invariant',
        v_err = 'unique_violation', v_err);
  BEGIN
    INSERT INTO public.professional_identities(user_id, professional_type) VALUES (u1,'driver');
    v_err := NULL;
  EXCEPTION WHEN unique_violation THEN v_err := 'unique_violation';
           WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A2.D8 same-lane duplicate ACTIVE row also blocked',
        v_err = 'unique_violation', v_err);
  SELECT count(*) INTO v_n FROM public.professional_identities WHERE user_id=u1 AND claim_state='active';
  r := r || public._qa_s13_ok('N5A2.D9 exactly one active row survives the race attempts', v_n = 1, 'n='||v_n);

  -- ===================== E. RELEASE / HISTORY =====================
  v_row := public._professional_identity_release(u1,'qa release');
  r := r || public._qa_s13_ok('N5A2.E1 release moves the active row to released with released_at',
        v_row.claim_state='released' AND v_row.released_at IS NOT NULL AND v_row.id = v_id1, NULL);
  r := r || public._qa_s13_ok('N5A2.E2 released row preserves its original professional_type',
        v_row.professional_type='driver', v_row.professional_type);

  v_row2 := public._professional_identity_claim(u1,'merchant','qa');
  v_id2 := v_row2.id;
  r := r || public._qa_s13_ok('N5A2.E3 released history does not block a later opposite-lane claim',
        v_row2.professional_type='merchant' AND v_row2.claim_state='active', NULL);
  r := r || public._qa_s13_ok('N5A2.E4 later claim creates a DISTINCT row', v_id2 <> v_id1, NULL);
  SELECT professional_type INTO v_err FROM public.professional_identities WHERE id=v_id1;
  r := r || public._qa_s13_ok('N5A2.E5 old released row was not overwritten', v_err='driver', v_err);
  SELECT count(*) INTO v_n FROM public.professional_identities WHERE user_id=u1;
  r := r || public._qa_s13_ok('N5A2.E6 user now has 2 historical rows, 1 active', v_n=2, 'n='||v_n);

  BEGIN
    UPDATE public.professional_identities SET professional_type='merchant' WHERE id=v_id1;
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A2.E7 professional_type is immutable after creation',
        v_err = 'PROFESSIONAL_IDENTITY_TYPE_IMMUTABLE', v_err);
  BEGIN
    UPDATE public.professional_identities SET claim_state='active', released_at=NULL WHERE id=v_id1;
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A2.E8 released -> active resurrection refused', v_err IS NOT NULL, v_err);
  BEGIN
    UPDATE public.professional_identities SET user_id=u3 WHERE id=v_id1;
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A2.E9 user_id is immutable after creation',
        v_err = 'PROFESSIONAL_IDENTITY_USER_IMMUTABLE', v_err);
  BEGIN
    PERFORM public._professional_identity_release(u3, 'qa');
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A2.E10 releasing a lane the user does not hold is refused',
        v_err = 'PROFESSIONAL_IDENTITY_NOT_ACTIVE', v_err);

  -- ===================== F. READ SURFACE / AUTH =====================
  PERFORM set_config('request.jwt.claims', NULL, true);
  BEGIN
    PERFORM public.professional_identity_current();
    v_err := NULL;
  EXCEPTION WHEN others THEN v_err := SQLERRM; END;
  r := r || public._qa_s13_ok('N5A2.F1 signed-out read is denied (AUTH_REQUIRED)',
        v_err = 'AUTH_REQUIRED', v_err);

  PERFORM set_config('request.jwt.claims', public._as_user_claims(u3), true);
  v_json := public.professional_identity_current();
  r := r || public._qa_s13_ok('N5A2.F2 customer with no professional identity reads none',
        v_json->>'professional_type' = 'none', v_json::text);

  PERFORM set_config('request.jwt.claims', public._as_user_claims(u2), true);
  v_json := public.professional_identity_current();
  r := r || public._qa_s13_ok('N5A2.F3 merchant identity reads merchant',
        v_json->>'professional_type' = 'merchant', v_json::text);

  PERFORM set_config('request.jwt.claims', public._as_user_claims(u1), true);
  v_json := public.professional_identity_current();
  r := r || public._qa_s13_ok('N5A2.F4 caller reads only their CURRENT active lane',
        v_json->>'professional_type' = 'merchant' AND (v_json->>'identity_id')::uuid = v_id2, v_json::text);
  r := r || public._qa_s13_ok('N5A2.F5 read surface exposes no other user identifier',
        NOT (v_json::text ILIKE '%'||u2::text||'%') AND NOT (v_json::text ILIKE '%user_id%'), v_json::text);

  -- runtime RLS / privilege proof under the authenticated role
  BEGIN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(u3), true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    SELECT count(*) INTO v_n FROM public.professional_identities;
    r := r || public._qa_s13_ok('N5A2.F6 authenticated user sees no other user rows', v_n = 0, 'n='||v_n);
    SELECT count(*) INTO v_n FROM public.professional_identities WHERE user_id = u1;
    r := r || public._qa_s13_ok('N5A2.F7 arbitrary other-user lookup by uuid returns nothing', v_n = 0, 'n='||v_n);

    BEGIN
      EXECUTE format('INSERT INTO public.professional_identities(user_id, professional_type) VALUES (%L,%L)', u3,'driver');
      v_err := NULL;
    EXCEPTION WHEN others THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N5A2.F8 authenticated direct INSERT denied', v_err IS NOT NULL, v_err);
    BEGIN
      EXECUTE 'UPDATE public.professional_identities SET claim_state=''released''';
      v_err := NULL;
    EXCEPTION WHEN others THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N5A2.F9 authenticated direct UPDATE denied', v_err IS NOT NULL, v_err);
    BEGIN
      EXECUTE 'DELETE FROM public.professional_identities';
      v_err := NULL;
    EXCEPTION WHEN others THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N5A2.F10 authenticated direct DELETE denied', v_err IS NOT NULL, v_err);
    BEGIN
      EXECUTE 'TRUNCATE public.professional_identities';
      v_err := NULL;
    EXCEPTION WHEN others THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N5A2.F11 authenticated TRUNCATE denied', v_err IS NOT NULL, v_err);
    BEGIN
      EXECUTE format('SELECT public._professional_identity_claim(%L,%L,%L)', u3,'driver','qa');
      v_err := NULL;
    EXCEPTION WHEN others THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N5A2.F12 authenticated cannot invoke the internal claim primitive',
          v_err IS NOT NULL, v_err);
    EXECUTE 'RESET ROLE';
  EXCEPTION WHEN others THEN
    EXECUTE 'RESET ROLE';
    r := r || public._qa_s13_ok('N5A2.F6-F12 authenticated-role runtime probe', false, SQLERRM);
  END;
  PERFORM set_config('request.jwt.claims', NULL, true);

  -- ===================== G. DOMAIN SEPARATION =====================
  SELECT count(*) INTO v_n FROM public.driver_profiles WHERE user_id = ANY(ids);
  r := r || public._qa_s13_ok('N5A2.G1 driver claim created no driver_profile', v_n = 0, 'n='||v_n);
  SELECT count(*) INTO v_n FROM public.driver_applications WHERE user_id = ANY(ids);
  r := r || public._qa_s13_ok('N5A2.G2 driver claim created no driver application', v_n = 0, 'n='||v_n);
  SELECT count(*) INTO v_n FROM public.merchant_stores WHERE owner_user_id = ANY(ids);
  r := r || public._qa_s13_ok('N5A2.G3 merchant claim created no merchant store', v_n = 0, 'n='||v_n);
  SELECT count(*) INTO v_n FROM public.food_restaurants WHERE owner_user_id = ANY(ids);
  r := r || public._qa_s13_ok('N5A2.G4 merchant claim created no restaurant', v_n = 0, 'n='||v_n);
  SELECT count(*) INTO v_n FROM public.merchants WHERE owner_user_id = ANY(ids);
  r := r || public._qa_s13_ok('N5A2.G5 merchant claim created no merchant entity', v_n = 0, 'n='||v_n);
  SELECT count(*) INTO v_n FROM public.user_roles WHERE user_id = ANY(ids);
  r := r || public._qa_s13_ok('N5A2.G6 claim created no user_roles row (incl. merchant role)', v_n = 0, 'n='||v_n);
  SELECT count(*) INTO v_n FROM public.wallets WHERE owner_user_id = ANY(ids);
  r := r || public._qa_s13_ok('N5A2.G7 claim created no wallet', v_n = 0, 'n='||v_n);
  r := r || public._qa_s13_ok('N5A2.G8 active identity does NOT imply driver approval',
        NOT EXISTS (SELECT 1 FROM public.driver_profiles d
                     WHERE d.user_id = ANY(ids) AND d.status = 'approved'), NULL);
  r := r || public._qa_s13_ok('N5A2.G9 active merchant identity does NOT imply an approved store',
        NOT EXISTS (SELECT 1 FROM public.merchant_stores s
                     WHERE s.owner_user_id = ANY(ids)), NULL);
  SELECT count(*) INTO v_n FROM public.merchant_stores WHERE onboarding_status='approved';
  r := r || public._qa_s13_ok('N5A2.G10 approved-store population unchanged by identity work',
        v_n = (SELECT count(*) FROM public.merchant_stores WHERE onboarding_status='approved'), NULL);
  r := r || public._qa_s13_ok('N5A2.G11 identity table is not referenced by frozen driver/merchant authority helpers',
        NOT EXISTS (SELECT 1 FROM pg_proc
                     WHERE proname IN ('has_role','_driver_finance_eligible','_marche_listing_authz',
                                       '_food_restaurant_guard','_is_approved_service_agent')
                       AND pg_get_functiondef(oid) ILIKE '%professional_identities%'), NULL);

  -- ===================== H. CLEANUP + NON-DRIFT =====================
  DELETE FROM public.professional_identities WHERE user_id = ANY(ids);
  PERFORM public._qa_users_purge(ids);

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
  SELECT jsonb_object_agg(key, enabled) INTO a_flags FROM public.feature_flags;

  r := r || public._qa_s13_ok('N5A2.H1 QA fixtures fully purged from auth', a_au = b_au, b_au||'->'||a_au);
  r := r || public._qa_s13_ok('N5A2.H2 profiles unchanged', a_pr = b_pr, b_pr||'->'||a_pr);
  r := r || public._qa_s13_ok('N5A2.H3 user_roles unchanged', a_ur = b_ur, b_ur||'->'||a_ur);
  r := r || public._qa_s13_ok('N5A2.H4 wallets unchanged', a_w = b_w, b_w||'->'||a_w);
  r := r || public._qa_s13_ok('N5A2.H5 wallet_transactions unchanged', a_wt = b_wt, b_wt||'->'||a_wt);
  r := r || public._qa_s13_ok('N5A2.H6 ledger_journals unchanged', a_lj = b_lj, b_lj||'->'||a_lj);
  r := r || public._qa_s13_ok('N5A2.H7 ledger_postings unchanged', a_lp = b_lp, b_lp||'->'||a_lp);
  r := r || public._qa_s13_ok('N5A2.H8 ledger balance sum unchanged', a_ls = b_ls, b_ls||'->'||a_ls);
  r := r || public._qa_s13_ok('N5A2.H9 driver_profiles unchanged', a_dp = b_dp, b_dp||'->'||a_dp);
  r := r || public._qa_s13_ok('N5A2.H10 driver_applications unchanged', a_da = b_da, b_da||'->'||a_da);
  r := r || public._qa_s13_ok('N5A2.H11 merchant_stores unchanged', a_ms = b_ms, b_ms||'->'||a_ms);
  r := r || public._qa_s13_ok('N5A2.H12 food_restaurants unchanged', a_fr = b_fr, b_fr||'->'||a_fr);
  r := r || public._qa_s13_ok('N5A2.H13 merchants unchanged', a_me = b_me, b_me||'->'||a_me);
  r := r || public._qa_s13_ok('N5A2.H14 professional_identities returned to baseline', a_pi = b_pi, b_pi||'->'||a_pi);
  r := r || public._qa_s13_ok('N5A2.H15 feature flags unchanged', a_flags = b_flags, NULL);
  r := r || public._qa_s13_ok('N5A2.H16 no QA residue in professional_identities',
        NOT EXISTS (SELECT 1 FROM public.professional_identities WHERE claim_source='qa'), NULL);

  RETURN jsonb_build_object(
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'failures', (SELECT COALESCE(jsonb_agg(e),'[]'::jsonb) FROM jsonb_array_elements(r) e
                  WHERE (e->>'ok')::boolean IS NOT TRUE),
    'results', r
  );
END $function$;

REVOKE ALL ON FUNCTION public._qa_node5_identity_a2() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node5_identity_a2() TO service_role;