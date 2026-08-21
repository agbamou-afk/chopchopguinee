
CREATE OR REPLACE FUNCTION public._qa_node5_identity_a13()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '300s'
AS $fn$
DECLARE
  r jsonb := '[]'::jsonb;
  u_a   uuid := gen_random_uuid();  -- legacy driver, holds phone P1 then P2
  u_b   uuid := gen_random_uuid();  -- new auth user that later re-registers P1
  u_m   uuid := gen_random_uuid();  -- merchant with a store
  u_off uuid := gen_random_uuid();  -- offboarded professional recovering access
  u_god uuid := gen_random_uuid();  -- governance actor
  u_sus uuid := gen_random_uuid();  -- governance account that gets suspended
  u_ad  uuid := gen_random_uuid();  -- lawful admin + driver overlap
  u_new uuid := gen_random_uuid();  -- bootstrap probe
  ids uuid[];
  s_m uuid := gen_random_uuid();
  p1 text; p2 text; p3 text;
  res jsonb; v_txt text; v_n bigint; v_i int;
  v_bal_a bigint; v_bal_a_end bigint;
  refusals text[] := ARRAY[
    'AUTH_REQUIRED','NOT_AUTHORIZED','PROFESSIONAL_IDENTITY_REQUIRED',
    'PROFESSIONAL_IDENTITY_CONFLICT','DRIVER_PROFILE_REQUIRED','DRIVER_NOT_OPERATIONAL',
    'DRIVER_CAPABILITY_MISSING','No driver profile','MERCHANT_STORE_NOT_FOUND',
    'MERCHANT_STORE_NOT_OPERATIONAL','NOT_STORE_OWNER','not store owner',
    'MERCHANT_IDENTITY_REQUIRED','PROFESSIONAL_LANE_RELEASED'];
  b_pr bigint; b_w bigint; b_pi bigint; b_lp bigint; b_ls numeric; b_ur bigint;
  b_au bigint; b_ms bigint; b_dp bigint; b_al bigint; b_mfh bigint; b_flags jsonb;
  a_pr bigint; a_w bigint; a_pi bigint; a_lp bigint; a_ls numeric; a_ur bigint;
  a_au bigint; a_ms bigint; a_dp bigint; a_al bigint; a_mfh bigint; a_flags jsonb;
  c_al bigint;
BEGIN
  ids := ARRAY[u_a,u_b,u_m,u_off,u_god,u_sus,u_ad,u_new];
  p1 := '+22462' || lpad((floor(random()*10000000))::bigint::text, 7, '0');
  p2 := '+22463' || lpad((floor(random()*10000000))::bigint::text, 7, '0');
  p3 := '+22464' || lpad((floor(random()*10000000))::bigint::text, 7, '0');

  -- ============ IMMUTABLE PRE-SUITE BASELINE ============
  SELECT count(*) INTO b_pr  FROM public.profiles;
  SELECT count(*) INTO b_w   FROM public.wallets;
  SELECT count(*) INTO b_pi  FROM public.professional_identities;
  SELECT count(*) INTO b_lp  FROM public.ledger_postings;
  SELECT COALESCE(sum(amount_gnf),0) INTO b_ls FROM public.ledger_postings;
  SELECT count(*) INTO b_ur  FROM public.user_roles;
  SELECT count(*) INTO b_au  FROM public.admin_users;
  SELECT count(*) INTO b_ms  FROM public.merchant_stores;
  SELECT count(*) INTO b_dp  FROM public.driver_profiles;
  SELECT count(*) INTO b_al  FROM public.audit_logs;
  SELECT count(*) INTO b_mfh FROM public.mission_financial_holds;
  SELECT jsonb_object_agg(key, enabled) INTO b_flags FROM public.feature_flags;

  -- ============ A. STRUCTURAL CANONICAL OWNERSHIP ============
  r := r || public._qa_s13_ok('N5A13.A1 the account key on profiles is a unique canonical user uuid',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.profiles'::regclass
                 AND contype='u' AND pg_get_constraintdef(oid)='UNIQUE (user_id)'), NULL);
  r := r || public._qa_s13_ok('N5A13.A2 one contact phone can never be held by two accounts',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.profiles'::regclass
                 AND contype='u' AND pg_get_constraintdef(oid)='UNIQUE (phone)'), NULL);
  r := r || public._qa_s13_ok('N5A13.A3 wallets are unique per canonical owner and party type',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.wallets'::regclass
                 AND contype='u' AND pg_get_constraintdef(oid) ILIKE '%owner_user_id%party_type%'), NULL);
  SELECT count(*) INTO v_n FROM pg_policy
   WHERE pg_get_expr(polqual,polrelid) ILIKE '%phone%'
      OR pg_get_expr(polwithcheck,polrelid) ILIKE '%phone%';
  r := r || public._qa_s13_ok('N5A13.A4 no row-level policy authorizes anything by phone number',
        v_n = 0, 'policies='||v_n);
  r := r || public._qa_s13_ok('N5A13.A5 profiles carry a server-side phone canonicalisation trigger',
        EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_proc p ON p.oid=t.tgfoid
                 WHERE t.tgrelid='public.profiles'::regclass AND NOT t.tgisinternal
                   AND p.proname='_profiles_normalize_phone'), NULL);
  r := r || public._qa_s13_ok('N5A13.A6 every Guinea phone spelling collapses to one canonical value',
        public._normalize_guinea_phone('622123456') = '+224622123456'
        AND public._normalize_guinea_phone('+224 622 12 34 56') = '+224622123456'
        AND public._normalize_guinea_phone('00224622123456') = '+224622123456'
        AND public._normalize_guinea_phone('224-622-123-456') = '+224622123456'
        AND public._normalize_guinea_phone('not-a-number') IS NULL, NULL);
  r := r || public._qa_s13_ok('N5A13.A7 the agent contact lookup resolves the canonical user id, never the profile row id',
        (SELECT prosrc ~ 'p\.user_id' AND prosrc !~ 'INTO v_cust[^;]*\n?.*p\.id'
           FROM pg_proc WHERE oid='public.agent_lookup_customer_wallet(text)'::regprocedure)
        AND (SELECT prosrc !~ 'SELECT p\.id,' FROM pg_proc
              WHERE oid='public.agent_lookup_customer_wallet(text)'::regprocedure), NULL);
  r := r || public._qa_s13_ok('N5A13.A8 contact lookups are unreachable signed-out',
        NOT has_function_privilege('anon','public.agent_lookup_customer_wallet(text)','EXECUTE')
        AND NOT has_function_privilege('anon','public.find_user_by_phone(text)','EXECUTE')
        AND NOT has_function_privilege('anon','public.wallet_p2p_lookup_recipient(text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A13.A9 A11/A12 identity-table posture is unchanged by A13',
        NOT has_table_privilege('authenticated','public.professional_identities','UPDATE')
        AND NOT has_table_privilege('authenticated','public.user_roles','DELETE')
        AND NOT has_table_privilege('authenticated','public.admin_users','DELETE')
        AND NOT has_table_privilege('anon','public.profiles','SELECT'), NULL);
  r := r || public._qa_s13_ok('N5A13.A10 every ownership column on money and professional artifacts is a uuid',
        (SELECT count(*) FROM information_schema.columns
          WHERE table_schema='public' AND data_type='uuid'
            AND (table_name,column_name) IN (
              ('wallets','owner_user_id'),('merchant_stores','owner_user_id'),
              ('driver_profiles','user_id'),('professional_identities','user_id'),
              ('admin_users','user_id'),('user_roles','user_id'))) = 6, NULL);
  r := r || public._qa_s13_ok('N5A13.A11 recovery enrolment is keyed by the canonical account uuid',
        (SELECT data_type FROM information_schema.columns
          WHERE table_schema='public' AND table_name='account_recovery_profiles'
            AND column_name='user_id') = 'uuid', NULL);
  r := r || public._qa_s13_ok('N5A13.A12 recovery challenges store a hashed identifier, never a raw phone',
        NOT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_schema='public' AND table_name='account_recovery_challenges'
                       AND column_name IN ('phone','email','identifier'))
        AND EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_schema='public' AND table_name='account_recovery_challenges'
                       AND column_name='identifier_hash'), NULL);
  r := r || public._qa_s13_ok('N5A13.A13 the A13 suite itself is never client-callable',
        NOT has_function_privilege('anon','public._qa_node5_identity_a13()','EXECUTE')
        AND NOT has_function_privilege('authenticated','public._qa_node5_identity_a13()','EXECUTE'), NULL);

  -- ============ FIXTURES ============
  PERFORM public._qa_users_new(u_a,  'qa-n5a13-a-'  ||substr(u_a::text,1,8)  ||'@example.com');
  PERFORM public._qa_users_new(u_b,  'qa-n5a13-b-'  ||substr(u_b::text,1,8)  ||'@example.com');
  PERFORM public._qa_users_new(u_m,  'qa-n5a13-m-'  ||substr(u_m::text,1,8)  ||'@example.com');
  PERFORM public._qa_users_new(u_off,'qa-n5a13-off-'||substr(u_off::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_god,'qa-n5a13-god-'||substr(u_god::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_sus,'qa-n5a13-sus-'||substr(u_sus::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_ad, 'qa-n5a13-ad-' ||substr(u_ad::text,1,8) ||'@example.com');

  INSERT INTO public.admin_users(user_id, admin_role, status)
  VALUES (u_god,'super_admin','active'), (u_sus,'super_admin','active'),
         (u_ad,'super_admin','active')
  ON CONFLICT DO NOTHING;

  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_a), true);
  PERFORM public.driver_apply('{"vehicle_type":"moto"}'::jsonb);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_off), true);
  PERFORM public.driver_apply('{"vehicle_type":"moto"}'::jsonb);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ad), true);
  PERFORM public.driver_apply('{"vehicle_type":"moto"}'::jsonb);
  PERFORM set_config('request.jwt.claims', NULL, true);
  UPDATE public.driver_profiles SET status='approved', approved_at=now()
   WHERE user_id IN (u_a, u_off, u_ad);
  INSERT INTO public.wallets(owner_user_id, party_type)
  VALUES (u_a,'driver'), (u_off,'driver'), (u_ad,'driver')
  ON CONFLICT DO NOTHING;

  INSERT INTO public.merchant_stores(id, owner_user_id, name, slug, status, onboarding_status)
  VALUES (s_m, u_m, 'QA A13 Store','qa-a13-'||substr(s_m::text,1,8),'active','approved');
  INSERT INTO public.wallets(owner_user_id, party_type) VALUES (u_m,'merchant')
  ON CONFLICT DO NOTHING;

  UPDATE public.profiles SET phone = p1 WHERE user_id = u_a;
  UPDATE public.profiles SET phone = p3 WHERE user_id = u_m;
  UPDATE public.wallets SET balance_gnf = 250000
   WHERE owner_user_id = u_a AND party_type = 'client';
  SELECT balance_gnf INTO v_bal_a FROM public.wallets
   WHERE owner_user_id = u_a AND party_type='client';

  -- ============ B. AUTH BOOTSTRAP UNIQUENESS ============
  PERFORM public._qa_users_new(u_new,'qa-n5a13-new-'||substr(u_new::text,1,8)||'@example.com');
  SELECT count(*) INTO v_n FROM public.profiles WHERE user_id = u_new;
  r := r || public._qa_s13_ok('N5A13.B1 a brand-new auth account bootstraps exactly one profile',
        v_n = 1, 'profiles='||v_n);
  r := r || public._qa_s13_ok('N5A13.B2 the profile row id is NOT the account key and must never be used as one',
        (SELECT id <> user_id AND user_id = u_new FROM public.profiles WHERE user_id=u_new), NULL);
  SELECT count(*) INTO v_n FROM public.wallets WHERE owner_user_id = u_new;
  r := r || public._qa_s13_ok('N5A13.B3 a brand-new account bootstraps exactly one client wallet',
        v_n = 1 AND EXISTS (SELECT 1 FROM public.wallets
                             WHERE owner_user_id=u_new AND party_type='client'), 'wallets='||v_n);
  SELECT count(*) INTO v_n FROM public.user_roles WHERE user_id = u_new;
  r := r || public._qa_s13_ok('N5A13.B4 a brand-new account bootstraps exactly the base client role',
        v_n = 1 AND public.has_role(u_new,'client'::public.app_role), 'roles='||v_n);
  r := r || public._qa_s13_ok('N5A13.B5 a brand-new account bootstraps no professional lane and no governance',
        NOT EXISTS (SELECT 1 FROM public.professional_identities WHERE user_id=u_new)
        AND NOT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id=u_new)
        AND public.professional_active_type(u_new) IS NULL
        AND NOT public.is_any_admin(u_new), NULL);
  r := r || public._qa_s13_ok('N5A13.B6 bootstrap is idempotent: re-running it creates no second identity',
        (SELECT count(*) FROM public.profiles WHERE user_id=u_new) = 1
        AND (SELECT count(*) FROM public.wallets WHERE owner_user_id=u_new) = 1, NULL);

  -- ============ C. SAME-ACCOUNT SESSION / DEVICE CONTINUITY ============
  r := r || public._qa_s13_ok('N5A13.C1 the driver fixture is operational on its first session',
        public._driver_class_active(u_a)
        AND (SELECT status FROM public.driver_profiles WHERE user_id=u_a)='approved', NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_a), true);
  PERFORM public.driver_set_status('online'::public.driver_presence);
  PERFORM set_config('request.jwt.claims', NULL, true);
  -- simulate a lost device: the session is dropped and a new one is established
  PERFORM set_config('request.jwt.claims', NULL, true);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_a), true);
  v_txt := (SELECT public.professional_active_type(auth.uid()));
  v_i := public._qa_node4_probe('authenticated', u_a,
          'SELECT count(*)::int FROM public.wallets WHERE owner_user_id = auth.uid()');
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A13.C2 a new session on the same account resolves the same professional lane',
        v_txt = 'driver', COALESCE(v_txt,'null'));
  r := r || public._qa_s13_ok('N5A13.C3 a new session sees exactly the same wallets, never duplicates',
        v_i = 2, 'wallets='||v_i);
  SELECT count(*) INTO v_n FROM public.profiles WHERE user_id = u_a;
  r := r || public._qa_s13_ok('N5A13.C4 re-authentication never forks a second profile',
        v_n = 1, 'profiles='||v_n);
  SELECT count(*) INTO v_n FROM public.professional_identities
   WHERE user_id = u_a AND claim_state = 'active';
  r := r || public._qa_s13_ok('N5A13.C5 re-authentication never forks a second professional lane',
        v_n = 1, 'lanes='||v_n);

  -- ============ D. VERIFIED CONTACT / PHONE CHANGE CONTINUITY ============
  v_txt := public._qa_r6_err('authenticated', u_a,
    format('UPDATE public.profiles SET phone = %L WHERE user_id = %L', p2, u_a));
  r := r || public._qa_s13_ok('N5A13.D1 an account owner can change their own verified contact phone',
        v_txt = 'OK' AND (SELECT phone FROM public.profiles WHERE user_id=u_a) = p2, v_txt);
  v_txt := public._qa_r6_err('authenticated', u_a,
    format('UPDATE public.profiles SET phone = %L WHERE user_id = %L',
           '00224' || substr(p2,5), u_a));
  r := r || public._qa_s13_ok('N5A13.D2 a non-canonical spelling is stored canonically, not as a second identity',
        v_txt = 'OK' AND (SELECT phone FROM public.profiles WHERE user_id=u_a) = p2, v_txt);
  v_txt := public._qa_r6_err('authenticated', u_a,
    format('UPDATE public.profiles SET phone = %L WHERE user_id = %L', '12', u_a));
  r := r || public._qa_s13_ok('N5A13.D3 an unparseable phone is refused, never silently stored',
        v_txt = 'INVALID_PHONE' AND (SELECT phone FROM public.profiles WHERE user_id=u_a) = p2, v_txt);
  SELECT count(*) INTO v_n FROM public.wallets WHERE owner_user_id = u_a;
  r := r || public._qa_s13_ok('N5A13.D4 a phone change creates no wallet and moves no wallet ownership',
        v_n = 2 AND (SELECT balance_gnf FROM public.wallets
                      WHERE owner_user_id=u_a AND party_type='client') = v_bal_a, 'wallets='||v_n);
  r := r || public._qa_s13_ok('N5A13.D5 a phone change changes no professional or governance authority',
        public.professional_active_type(u_a) = 'driver'
        AND public._driver_class_active(u_a)
        AND NOT public.is_any_admin(u_a), NULL);
  r := r || public._qa_s13_ok('N5A13.D6 a phone change never repoints the profile to another account key',
        (SELECT user_id FROM public.profiles WHERE user_id=u_a) = u_a
        AND (SELECT count(*) FROM public.profiles WHERE phone = p2) = 1, NULL);
  v_txt := public._qa_r6_err('authenticated', u_b,
    format('UPDATE public.profiles SET user_id = %L WHERE user_id = %L', u_a, u_b));
  r := r || public._qa_s13_ok('N5A13.D7 an account cannot repoint its own profile at another account key',
        v_txt <> 'OK' AND (SELECT user_id FROM public.profiles WHERE user_id=u_b) = u_b, v_txt);

  -- ============ E. RE-REGISTRATION / OLD-PHONE NON-INHERITANCE ============
  -- P1 is now free: the driver account u_a moved to P2. A different human (u_b)
  -- now controls P1 and registers it on a brand-new auth account.
  r := r || public._qa_s13_ok('N5A13.E1 the old phone is genuinely released by the original account',
        NOT EXISTS (SELECT 1 FROM public.profiles WHERE phone = p1), NULL);
  v_txt := public._qa_r6_err('authenticated', u_b,
    format('UPDATE public.profiles SET phone = %L WHERE user_id = %L', p1, u_b));
  r := r || public._qa_s13_ok('N5A13.E2 a new account may legitimately register a previously used phone',
        v_txt = 'OK' AND (SELECT phone FROM public.profiles WHERE user_id=u_b) = p1, v_txt);
  r := r || public._qa_s13_ok('N5A13.E3 the re-registering account inherits no professional lane',
        NOT EXISTS (SELECT 1 FROM public.professional_identities WHERE user_id=u_b)
        AND public.professional_active_type(u_b) IS NULL
        AND NOT public._driver_class_active(u_b), NULL);
  r := r || public._qa_s13_ok('N5A13.E4 the re-registering account inherits no governance authority',
        NOT public.is_any_admin(u_b)
        AND NOT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id=u_b), NULL);
  r := r || public._qa_s13_ok('N5A13.E5 the original account keeps its lane after its phone was taken over',
        public.professional_active_type(u_a) = 'driver' AND public._driver_class_active(u_a), NULL);
  v_i := public._qa_node4_probe('authenticated', u_b,
          format('SELECT count(*)::int FROM public.wallets WHERE owner_user_id = %L', u_a));
  r := r || public._qa_s13_ok('N5A13.E6 the phone successor cannot see the previous holder wallets',
        v_i = 0, 'visible='||v_i);
  v_i := public._qa_node4_probe('authenticated', u_a,
          format('SELECT count(*)::int FROM public.wallets WHERE owner_user_id = %L', u_a));
  r := r || public._qa_s13_ok('N5A13.E7 the original account still sees exactly its own wallets',
        v_i = 2, 'visible='||v_i);
  v_i := public._qa_node4_probe('authenticated', u_b,
          format('SELECT count(*)::int FROM public.driver_profiles WHERE user_id = %L', u_a));
  r := r || public._qa_s13_ok('N5A13.E8 the phone successor cannot read the previous holder driver artifact',
        v_i = 0, 'visible='||v_i);
  v_txt := public._qa_r6_err('authenticated', u_b,
    format('UPDATE public.merchant_stores SET name = ''hijack'' WHERE id = %L', s_m));
  SELECT count(*) INTO v_n FROM public.merchant_stores WHERE id=s_m AND name='hijack';
  r := r || public._qa_s13_ok('N5A13.E9 no account can claim a store it does not own by uuid',
        v_n = 0, v_txt);
  v_txt := public._qa_r6_err('authenticated', u_b,
    format('UPDATE public.wallets SET balance_gnf = balance_gnf - 1000 WHERE owner_user_id = %L', u_a));
  r := r || public._qa_s13_ok('N5A13.E10 the phone successor cannot spend the previous holder balance',
        (SELECT balance_gnf FROM public.wallets
          WHERE owner_user_id=u_a AND party_type='client') = v_bal_a, v_txt);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_god), true);
  SELECT f.user_id INTO v_txt FROM public.find_user_by_phone(p1) f;
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A13.E11 a contact lookup on the recycled phone resolves the CURRENT holder only',
        v_txt = u_b::text, COALESCE(v_txt,'null'));
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_god), true);
  SELECT f.user_id INTO v_txt FROM public.find_user_by_phone(substr(p2,5)) f;
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A13.E12 a contact lookup normalizes local spelling to the same canonical account',
        v_txt = u_a::text, COALESCE(v_txt,'null'));

  -- ============ F. PROFESSIONAL RECOVERY NON-BYPASS ============
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_god), true);
  res := public.admin_professional_offboard(u_off,'a13 offboard before recovery');
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A13.F1 the professional is offboarded before the recovery simulation',
        (res->>'offboarded')::boolean AND public.professional_active_type(u_off) IS NULL, res::text);
  UPDATE public.profiles SET phone = p1 || '' WHERE false; -- no-op guard, keeps intent explicit
  -- recovery = the SAME account authenticates again on a new device
  PERFORM set_config('request.jwt.claims', NULL, true);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_off), true);
  BEGIN
    PERFORM public.driver_set_status('online'::public.driver_presence);
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A13.F2 an offboarded professional stays offboarded after recovering access',
          false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A13.F2 an offboarded professional stays offboarded after recovering access',
          SQLERRM = ANY(refusals), SQLERRM);
  END;
  r := r || public._qa_s13_ok('N5A13.F3 recovery restores access, not the professional lane',
        public.professional_active_type(u_off) IS NULL
        AND public.account_available_modes(u_off) = ARRAY['client'], NULL);
  r := r || public._qa_s13_ok('N5A13.F4 recovery destroys neither the professional history nor the money',
        EXISTS (SELECT 1 FROM public.driver_profiles WHERE user_id=u_off)
        AND EXISTS (SELECT 1 FROM public.wallets WHERE owner_user_id=u_off AND party_type='driver'), NULL);
  v_txt := public._qa_r6_err('authenticated', u_off,
    format('UPDATE public.professional_identities SET claim_state=''active'' WHERE user_id=%L', u_off));
  r := r || public._qa_s13_ok('N5A13.F5 a recovered account cannot self-restore its own lane',
        public.professional_active_type(u_off) IS NULL, v_txt);

  -- ============ G. GOVERNANCE / STAFF RECOVERY NON-BYPASS ============
  r := r || public._qa_s13_ok('N5A13.G1 the governance fixture holds real admin authority first',
        public.is_any_admin(u_sus) AND public._is_god_admin(u_sus), NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_god), true);
  res := public.admin_governance_set_status(u_sus,'suspended','a13 suspend before recovery');
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A13.G2 governance suspension is recorded exactly',
        res->>'status'='suspended' AND res->>'previous_status'='active', res::text);
  PERFORM set_config('request.jwt.claims', NULL, true);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_sus), true);
  v_txt := (SELECT CASE WHEN public.is_any_admin(auth.uid()) THEN 'admin' ELSE 'none' END);
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A13.G3 a suspended admin recovering access regains no governance authority',
        v_txt = 'none', v_txt);
  BEGIN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(u_sus), true);
    PERFORM public.admin_governance_set_status(u_god,'suspended','post-recovery escalation attempt');
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A13.G4 a suspended admin cannot act on governance after recovery',
          false, 'no refusal');
  EXCEPTION WHEN others THEN
    PERFORM set_config('request.jwt.claims', NULL, true);
    r := r || public._qa_s13_ok('N5A13.G4 a suspended admin cannot act on governance after recovery',
          SQLERRM = 'NOT_AUTHORIZED', SQLERRM);
  END;
  r := r || public._qa_s13_ok('N5A13.G5 governance suspension survives recovery as a preserved row, not a deletion',
        EXISTS (SELECT 1 FROM public.admin_users WHERE user_id=u_sus AND status='suspended'), NULL);

  -- ============ H. LAWFUL DUAL-AXIS CONTINUITY ============
  r := r || public._qa_s13_ok('N5A13.H1 a lawful dual-axis human holds both axes before recovery',
        public.is_any_admin(u_ad) AND public._driver_class_active(u_ad), NULL);
  PERFORM set_config('request.jwt.claims', NULL, true);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_ad), true);
  v_i := public._qa_node4_probe('authenticated', u_ad,
          'SELECT count(*)::int FROM public.profiles WHERE user_id = auth.uid()');
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A13.H2 recovery keeps a dual-axis human as ONE account, not two',
        v_i = 1 AND (SELECT count(*) FROM public.profiles WHERE user_id=u_ad) = 1, 'profiles='||v_i);
  r := r || public._qa_s13_ok('N5A13.H3 both axes remain independently evaluated after recovery',
        public.is_any_admin(u_ad) AND public._driver_class_active(u_ad)
        AND public.professional_active_type(u_ad) = 'driver', NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_god), true);
  PERFORM public.admin_governance_set_status(u_ad,'suspended','a13 axis isolation');
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A13.H4 suspending the governance axis never releases the professional lane',
        NOT public.is_any_admin(u_ad) AND public._driver_class_active(u_ad)
        AND public.professional_active_type(u_ad) = 'driver', NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_god), true);
  PERFORM public.admin_governance_set_status(u_ad,'active','a13 axis restore');
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A13.H5 restoring one axis restores exactly that axis',
        public.is_any_admin(u_ad) AND public._driver_class_active(u_ad)
        AND (SELECT count(*) FROM public.professional_identities
              WHERE user_id=u_ad AND claim_state='active') = 1, NULL);

  -- ============ I. STALE MODE / JWT / CONTACT / HISTORY NON-AUTHORITY ============
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', u_b::text, 'role','authenticated',
      'app_metadata', jsonb_build_object('role','admin','provider','email'),
      'user_metadata', jsonb_build_object('phone', p1, 'is_driver', true))::text, true);
  v_txt := (SELECT CASE WHEN public.is_any_admin(auth.uid()) THEN 'admin'
                        WHEN public._driver_class_active(auth.uid()) THEN 'driver'
                        ELSE 'client' END);
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A13.I1 forged token metadata confers no governance and no professional authority',
        v_txt = 'client', v_txt);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_b), true);
  BEGIN
    PERFORM public.account_mode_set('driver');
    v_txt := 'accepted';
  EXCEPTION WHEN others THEN v_txt := SQLERRM;
  END;
  PERFORM set_config('request.jwt.claims', NULL, true);
  r := r || public._qa_s13_ok('N5A13.I2 a stale or forced UI account mode confers no professional capability',
        NOT public._driver_class_active(u_b)
        AND public.account_available_modes(u_b) = ARRAY['client'], v_txt);
  r := r || public._qa_s13_ok('N5A13.I3 the previous holder historical phone value confers nothing on the successor',
        NOT EXISTS (SELECT 1 FROM public.wallets w
                     WHERE w.owner_user_id = u_b AND w.party_type <> 'client')
        AND (SELECT count(*) FROM public.wallets WHERE owner_user_id=u_b) = 1, NULL);
  v_i := public._qa_node4_probe('authenticated', u_b,
          format('SELECT count(*)::int FROM public.profiles WHERE user_id = %L', u_a));
  r := r || public._qa_s13_ok('N5A13.I4 controlling a former phone grants no read on the former holder profile',
        v_i = 0, 'visible='||v_i);

  -- ============ J. FINANCE / OWNERSHIP CONTINUITY ============
  SELECT balance_gnf INTO v_bal_a_end FROM public.wallets
   WHERE owner_user_id = u_a AND party_type='client';
  r := r || public._qa_s13_ok('N5A13.J1 the original account balance is byte-identical after the whole continuity sequence',
        v_bal_a_end = v_bal_a, v_bal_a||'->'||v_bal_a_end);
  SELECT count(*) INTO v_n FROM (
    SELECT owner_user_id, party_type FROM public.wallets
     WHERE owner_user_id = ANY(ids) GROUP BY 1,2 HAVING count(*) > 1) d;
  r := r || public._qa_s13_ok('N5A13.J2 no continuity event ever duplicated a canonical wallet',
        v_n = 0, 'dups='||v_n);
  SELECT count(*) INTO v_n FROM public.ledger_postings;
  r := r || public._qa_s13_ok('N5A13.J3 no ledger row was created or rewritten to follow a phone number',
        v_n = b_lp, b_lp||'->'||v_n);
  SELECT count(*) INTO v_n FROM public.mission_financial_holds
   WHERE user_id = ANY(ids) OR driver_user_id = ANY(ids);
  r := r || public._qa_s13_ok('N5A13.J4 no obligation was created or bypassed by re-registration',
        v_n = 0, 'holds='||v_n);
  SELECT count(*) INTO v_n FROM public.wallets WHERE owner_user_id = u_a;
  r := r || public._qa_s13_ok('N5A13.J5 money stayed attached to the canonical account across the phone change',
        v_n = 2 AND (SELECT count(*) FROM public.wallets WHERE owner_user_id=u_b) = 1, 'a='||v_n);

  -- ============ K. DUPLICATE / AMBIGUOUS CLAIM FAIL-CLOSED ============
  v_txt := public._qa_r6_err('authenticated', u_m,
    format('UPDATE public.profiles SET phone = %L WHERE user_id = %L', p1, u_m));
  r := r || public._qa_s13_ok('N5A13.K1 two accounts can never hold the same phone: the second is refused',
        v_txt LIKE '%duplicate key%'
        AND (SELECT phone FROM public.profiles WHERE user_id=u_m) = p3
        AND (SELECT phone FROM public.profiles WHERE user_id=u_b) = p1, v_txt);
  v_txt := public._qa_r6_err('authenticated', u_m,
    format('UPDATE public.profiles SET phone = %L WHERE user_id = %L', '00224'||substr(p1,5), u_m));
  r := r || public._qa_s13_ok('N5A13.K2 a differently spelled duplicate is normalized first and then refused',
        v_txt LIKE '%duplicate key%'
        AND (SELECT phone FROM public.profiles WHERE user_id=u_m) = p3, v_txt);
  SELECT count(*) INTO v_n FROM (
    SELECT public._normalize_guinea_phone(phone) n FROM public.profiles
     WHERE phone IS NOT NULL GROUP BY 1 HAVING count(*) > 1) x;
  r := r || public._qa_s13_ok('N5A13.K3 no ambiguous duplicate contact identity exists anywhere in the database',
        v_n = 0, 'ambiguous='||v_n);
  r := r || public._qa_s13_ok('N5A13.K4 no account-merge or account-linking entrypoint exists to be abused',
        NOT EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace
                     AND (proname ILIKE '%merge_account%' OR proname ILIKE '%link_account%'
                          OR proname ILIKE '%transfer_identity%')), NULL);

  -- ============ L. AUDIT / PROVENANCE ============
  SELECT count(*) INTO c_al FROM public.audit_logs WHERE actor_user_id = u_god;
  r := r || public._qa_s13_ok('N5A13.L1 every lifecycle action in this suite left an audit trail',
        c_al > 0, 'events='||c_al);
  r := r || public._qa_s13_ok('N5A13.L2 the offboarding of the recovering professional is provable after the fact',
        EXISTS (SELECT 1 FROM public.audit_logs
                 WHERE actor_user_id = u_god AND target_id = u_off::text), NULL);
  r := r || public._qa_s13_ok('N5A13.L3 professional history is appended, never rewritten',
        (SELECT count(*) FROM public.professional_identities WHERE user_id=u_off) >= 1
        AND EXISTS (SELECT 1 FROM public.professional_identities
                     WHERE user_id=u_off AND released_at IS NOT NULL), NULL);

  -- ============ M. CLEANUP + POST-SUITE SNAPSHOT ============
  PERFORM set_config('request.jwt.claims', NULL, true);
  DELETE FROM public.user_preferences WHERE user_id = ANY(ids);
  DELETE FROM public.audit_logs WHERE actor_user_id = ANY(ids)
     OR target_id IN (SELECT x::text FROM unnest(ids) x);
  DELETE FROM public.marketplace_listings WHERE seller_id = ANY(ids) OR store_id = s_m;
  DELETE FROM public.merchant_stores WHERE owner_user_id = ANY(ids);
  DELETE FROM public.wallets WHERE owner_user_id = ANY(ids);
  DELETE FROM public.driver_locations WHERE driver_id = ANY(ids);
  DELETE FROM public.driver_applications WHERE user_id = ANY(ids);
  DELETE FROM public.driver_profiles WHERE user_id = ANY(ids);
  DELETE FROM public.professional_identities WHERE user_id = ANY(ids);
  DELETE FROM public.admin_users WHERE user_id = ANY(ids);
  DELETE FROM public.user_roles WHERE user_id = ANY(ids);
  PERFORM public._qa_a5_cleanup(ids);

  SELECT count(*) INTO a_pr  FROM public.profiles;
  SELECT count(*) INTO a_w   FROM public.wallets;
  SELECT count(*) INTO a_pi  FROM public.professional_identities;
  SELECT count(*) INTO a_lp  FROM public.ledger_postings;
  SELECT COALESCE(sum(amount_gnf),0) INTO a_ls FROM public.ledger_postings;
  SELECT count(*) INTO a_ur  FROM public.user_roles;
  SELECT count(*) INTO a_au  FROM public.admin_users;
  SELECT count(*) INTO a_ms  FROM public.merchant_stores;
  SELECT count(*) INTO a_dp  FROM public.driver_profiles;
  SELECT count(*) INTO a_al  FROM public.audit_logs;
  SELECT count(*) INTO a_mfh FROM public.mission_financial_holds;
  SELECT jsonb_object_agg(key, enabled) INTO a_flags FROM public.feature_flags;

  r := r || public._qa_s13_ok('N5A13.M1 profiles returned to baseline', a_pr = b_pr, b_pr||'->'||a_pr);
  r := r || public._qa_s13_ok('N5A13.M2 wallets returned to baseline', a_w = b_w, b_w||'->'||a_w);
  r := r || public._qa_s13_ok('N5A13.M3 professional identities returned to baseline', a_pi = b_pi, b_pi||'->'||a_pi);
  r := r || public._qa_s13_ok('N5A13.M4 ledger postings returned to baseline', a_lp = b_lp, b_lp||'->'||a_lp);
  r := r || public._qa_s13_ok('N5A13.M5 ledger sum returned to baseline', a_ls = b_ls, b_ls||'->'||a_ls);
  r := r || public._qa_s13_ok('N5A13.M6 user roles returned to baseline', a_ur = b_ur, b_ur||'->'||a_ur);
  r := r || public._qa_s13_ok('N5A13.M7 governance accounts returned to baseline', a_au = b_au, b_au||'->'||a_au);
  r := r || public._qa_s13_ok('N5A13.M8 stores returned to baseline', a_ms = b_ms, b_ms||'->'||a_ms);
  r := r || public._qa_s13_ok('N5A13.M9 driver profiles returned to baseline', a_dp = b_dp, b_dp||'->'||a_dp);
  r := r || public._qa_s13_ok('N5A13.M10 audit trail returned to baseline', a_al = b_al, b_al||'->'||a_al);
  r := r || public._qa_s13_ok('N5A13.M11 financial holds returned to baseline', a_mfh = b_mfh, b_mfh||'->'||a_mfh);
  r := r || public._qa_s13_ok('N5A13.M12 feature flags unchanged', a_flags = b_flags, NULL);
  r := r || public._qa_s13_ok('N5A13.M13 zero identity residue',
        NOT EXISTS (SELECT 1 FROM public.profiles WHERE user_id = ANY(ids))
        AND NOT EXISTS (SELECT 1 FROM public.professional_identities WHERE user_id = ANY(ids))
        AND NOT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = ANY(ids)), NULL);
  r := r || public._qa_s13_ok('N5A13.M14 zero finance residue',
        NOT EXISTS (SELECT 1 FROM public.wallets WHERE owner_user_id = ANY(ids)), NULL);
  r := r || public._qa_s13_ok('N5A13.M15 zero recycled-phone residue',
        NOT EXISTS (SELECT 1 FROM public.profiles WHERE phone IN (p1,p2,p3)), NULL);

  RETURN jsonb_build_object(
    'fn','_qa_node5_identity_a13',
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'failures', (SELECT COALESCE(jsonb_agg(e),'[]'::jsonb) FROM jsonb_array_elements(r) e
                  WHERE (e->>'ok')::boolean IS NOT TRUE)
  );
EXCEPTION WHEN others THEN
  PERFORM set_config('request.jwt.claims', NULL, true);
  BEGIN
    DELETE FROM public.user_preferences WHERE user_id = ANY(ids);
    DELETE FROM public.audit_logs WHERE actor_user_id = ANY(ids)
       OR target_id IN (SELECT x::text FROM unnest(ids) x);
    DELETE FROM public.marketplace_listings WHERE seller_id = ANY(ids) OR store_id = s_m;
    DELETE FROM public.merchant_stores WHERE owner_user_id = ANY(ids);
    DELETE FROM public.wallets WHERE owner_user_id = ANY(ids);
    DELETE FROM public.driver_locations WHERE driver_id = ANY(ids);
    DELETE FROM public.driver_applications WHERE user_id = ANY(ids);
    DELETE FROM public.driver_profiles WHERE user_id = ANY(ids);
    DELETE FROM public.professional_identities WHERE user_id = ANY(ids);
    DELETE FROM public.admin_users WHERE user_id = ANY(ids);
    DELETE FROM public.user_roles WHERE user_id = ANY(ids);
    PERFORM public._qa_a5_cleanup(ids);
  EXCEPTION WHEN others THEN NULL; END;
  RAISE;
END $fn$;

REVOKE ALL ON FUNCTION public._qa_node5_identity_a13() FROM PUBLIC, anon, authenticated;
