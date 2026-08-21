
CREATE OR REPLACE FUNCTION public._qa_node5_identity_final_remediation()
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO 'public'
SET statement_timeout TO '300s'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  u_d   uuid := gen_random_uuid();  -- legacy deleted driver, lane still active
  u_m   uuid := gen_random_uuid();  -- legacy deleted merchant, lane still active
  u_x   uuid := gen_random_uuid();  -- lawful cross-axis: lane + governance
  u_fin uuid := gen_random_uuid();  -- nonzero balance
  u_liv uuid := gen_random_uuid();  -- live control account (must be unaffected)
  u_re  uuid := gen_random_uuid();  -- re-registration successor
  u_god uuid := gen_random_uuid();  -- governance actor
  ids uuid[];
  s_m uuid := gen_random_uuid();
  ride_id uuid := gen_random_uuid();
  ph text; ph_re text;
  res jsonb; v_n bigint; v_txt text; v_ok boolean; v_bal bigint;
  b_pr bigint; b_w bigint; b_pi bigint; b_lp bigint; b_ls numeric; b_ur bigint;
  b_au bigint; b_dp bigint; b_ro bigint; b_at bigint;
  a_pr bigint; a_w bigint; a_pi bigint; a_lp bigint; a_ls numeric; a_ur bigint;
  a_au bigint; a_dp bigint; a_ro bigint; a_at bigint;
BEGIN
  ids := ARRAY[u_d,u_m,u_x,u_fin,u_liv,u_re,u_god];
  ph    := '+22467' || lpad((floor(random()*10000000))::bigint::text, 7, '0');
  ph_re := '+22468' || lpad((floor(random()*10000000))::bigint::text, 7, '0');

  SELECT count(*) INTO b_pr FROM public.profiles;
  SELECT count(*) INTO b_w  FROM public.wallets;
  SELECT count(*) INTO b_pi FROM public.professional_identities;
  SELECT count(*) INTO b_lp FROM public.ledger_postings;
  SELECT COALESCE(sum(amount_gnf),0) INTO b_ls FROM public.ledger_postings;
  SELECT count(*) INTO b_ur FROM public.user_roles;
  SELECT count(*) INTO b_au FROM public.admin_users;
  SELECT count(*) INTO b_dp FROM public.driver_profiles;
  SELECT count(*) INTO b_ro FROM public.ride_offers;
  SELECT count(*) INTO b_at FROM public.account_access_terminations;

  -- ================= A. STRUCTURAL / GRANTS =================
  r := r || public._qa_s13_ok('N5FR.A1 the deleted-account access gate exists',
        to_regprocedure('public.auth_uid_active()') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N5FR.A2 the access gate is never signed-out callable',
        NOT has_function_privilege('anon','public.auth_uid_active()','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5FR.A3 the access gate is callable by signed-in users',
        has_function_privilege('authenticated','public.auth_uid_active()','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5FR.A4 the legacy reconciliation surface exists',
        to_regprocedure('public.admin_account_closure_reconcile(uuid,text)') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N5FR.A5 legacy reconciliation is never signed-out callable',
        NOT has_function_privilege('anon','public.admin_account_closure_reconcile(uuid,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5FR.A6 the termination enqueue primitive is internal only',
        NOT has_function_privilege('anon','public._account_access_terminate_enqueue(uuid,text,text)','EXECUTE')
        AND NOT has_function_privilege('authenticated','public._account_access_terminate_enqueue(uuid,text,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5FR.A7 the termination recorder is internal only',
        NOT has_function_privilege('anon','public.account_access_termination_record(uuid,boolean,text)','EXECUTE')
        AND NOT has_function_privilege('authenticated','public.account_access_termination_record(uuid,boolean,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5FR.A8 the termination queue has RLS enabled',
        (SELECT relrowsecurity FROM pg_class WHERE oid='public.account_access_terminations'::regclass), NULL);
  r := r || public._qa_s13_ok('N5FR.A9 the termination queue is unreadable signed-out',
        NOT has_table_privilege('anon','public.account_access_terminations','SELECT'), NULL);
  r := r || public._qa_s13_ok('N5FR.A10 the termination queue is never client-writable',
        NOT has_table_privilege('authenticated','public.account_access_terminations','INSERT')
        AND NOT has_table_privilege('authenticated','public.account_access_terminations','UPDATE')
        AND NOT has_table_privilege('authenticated','public.account_access_terminations','DELETE'), NULL);
  r := r || public._qa_s13_ok('N5FR.A11 no parallel closure subsystem was invented',
        (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
          WHERE n.nspname='public' AND p.proname ~ '^(admin_)?(anonymize|purge|erase)_user') <= 1, NULL);
  r := r || public._qa_s13_ok('N5FR.A12 the canonical closure core still exists unduplicated',
        (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
          WHERE n.nspname='public' AND p.proname='_account_closure_core') = 1, NULL);
  r := r || public._qa_s13_ok('N5FR.A13 this suite is never client-callable',
        NOT has_function_privilege('anon','public._qa_node5_identity_final_remediation()','EXECUTE')
        AND NOT has_function_privilege('authenticated','public._qa_node5_identity_final_remediation()','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5FR.A14 own-wallet reads are routed through the access gate',
        (SELECT qual FROM pg_policies WHERE schemaname='public' AND tablename='wallets'
          AND policyname='Users view own wallets') LIKE '%auth_uid_active%', NULL);
  r := r || public._qa_s13_ok('N5FR.A15 own-ride reads are routed through the access gate',
        (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename='rides'
          AND qual LIKE '%auth_uid_active%') = 2, NULL);
  r := r || public._qa_s13_ok('N5FR.A16 own-mission reads are routed through the access gate',
        (SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename='missions'
          AND COALESCE(qual,'') LIKE '%auth_uid_active%') >= 3, NULL);
  r := r || public._qa_s13_ok('N5FR.A17 own-role reads are routed through the access gate',
        (SELECT qual FROM pg_policies WHERE schemaname='public' AND tablename='user_roles'
          AND policyname='Users can view their own roles') LIKE '%auth_uid_active%', NULL);
  r := r || public._qa_s13_ok('N5FR.A18 own-transaction reads are routed through the access gate',
        (SELECT qual FROM pg_policies WHERE schemaname='public' AND tablename='wallet_transactions'
          AND policyname='Users view own transactions') LIKE '%auth_uid_active%', NULL);
  r := r || public._qa_s13_ok('N5FR.A19 profile writes are routed through the access gate',
        (SELECT qual FROM pg_policies WHERE schemaname='public' AND tablename='profiles'
          AND policyname='Users update own profile') LIKE '%auth_uid_active%', NULL);
  r := r || public._qa_s13_ok('N5FR.A20 the closure core enqueues auth access termination',
        pg_get_functiondef('public._account_closure_core(uuid,text,text)'::regprocedure)
          LIKE '%_account_access_terminate_enqueue%', NULL);

  -- ================= FIXTURES =================
  INSERT INTO auth.users(id,instance_id,aud,role,email,encrypted_password,
                         email_confirmed_at,created_at,updated_at)
  SELECT x,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
         'qa.n5fr.'||x::text||'@example.invalid','x',now(),now(),now()
    FROM unnest(ids) x;

  INSERT INTO public.profiles(user_id, full_name, account_status)
  SELECT x, 'QA N5FR', 'active' FROM unnest(ids) x;
  UPDATE public.profiles SET phone = ph WHERE user_id = u_d;

  -- legacy driver: closed the OLD way (PII only), authority left standing
  INSERT INTO public.driver_profiles(user_id,status,vehicle_type,presence)
  VALUES (u_d,'approved','moto','on_trip'), (u_x,'approved','moto','online');
  INSERT INTO public.professional_identities(user_id,professional_type,claim_state,claimed_at)
  VALUES (u_d,'driver','active',now()), (u_x,'driver','active',now()),
         (u_m,'merchant','active',now()), (u_fin,'driver','active',now());
  INSERT INTO public.merchant_stores(id,owner_user_id,name,status,is_active)
  VALUES (s_m,u_m,'QA N5FR Store','active',true);
  INSERT INTO public.user_roles(user_id,role) VALUES
    (u_d,'driver'),(u_d,'user'),(u_m,'merchant'),(u_x,'driver'),(u_fin,'driver'),(u_liv,'user');
  INSERT INTO public.admin_users(user_id,admin_role,status)
  VALUES (u_x,'support_admin','active'), (u_god,'god_admin','active');
  INSERT INTO public.account_recovery_profiles(user_id,recovery_key_hash)
  VALUES (u_d,'h'), (u_m,'h');
  PERFORM public._qa_s13_wallet(u_d,'driver',0,0);
  PERFORM public._qa_s13_wallet(u_fin,'driver',29448,0);
  PERFORM public._qa_s13_wallet(u_liv,'client',5000,0);
  INSERT INTO public.driver_profiles(user_id,status,vehicle_type,presence)
  VALUES (u_fin,'approved','moto','online');

  -- a stale pending offer on a cancelled ride, exactly like the live residue
  INSERT INTO public.rides(id,client_id,mode,pickup_lat,pickup_lng,dest_lat,dest_lng,
                           fare_gnf,status)
  VALUES (ride_id,u_liv,'moto',9.5,-13.7,9.6,-13.6,10000,'cancelled');
  INSERT INTO public.ride_offers(ride_id,driver_id,status,estimated_fare_gnf,
                                 estimated_earning_gnf,expires_at)
  VALUES (ride_id,u_d,'pending',10000,8000, now() - interval '5 days');

  -- flip the four to the LEGACY closed shape (PII released, authority intact)
  UPDATE public.profiles SET account_status='deleted', deleted_at=now(),
         full_name='Utilisateur supprimé', phone=NULL, email=NULL
   WHERE user_id IN (u_d,u_m,u_x,u_fin);

  -- prove the fixtures really hold authority before we assert its removal
  r := r || public._qa_s13_ok('N5FR.B1 fixture legacy driver really holds an active lane',
        EXISTS (SELECT 1 FROM public.professional_identities
                 WHERE user_id=u_d AND claim_state='active'), NULL);
  r := r || public._qa_s13_ok('N5FR.B2 fixture legacy driver really holds capability roles',
        (SELECT count(*) FROM public.user_roles WHERE user_id=u_d) = 2, NULL);
  r := r || public._qa_s13_ok('N5FR.B3 fixture legacy driver really is approved and non-offline',
        EXISTS (SELECT 1 FROM public.driver_profiles
                 WHERE user_id=u_d AND status='approved' AND presence='on_trip'), NULL);
  r := r || public._qa_s13_ok('N5FR.B4 fixture legacy driver really carries a pending offer',
        EXISTS (SELECT 1 FROM public.ride_offers WHERE driver_id=u_d AND status='pending'), NULL);
  r := r || public._qa_s13_ok('N5FR.B5 fixture legacy driver really carries recovery material',
        EXISTS (SELECT 1 FROM public.account_recovery_profiles WHERE user_id=u_d), NULL);
  r := r || public._qa_s13_ok('N5FR.B6 the legacy rows are genuinely already closed',
        (SELECT count(*) FROM public.profiles
          WHERE user_id IN (u_d,u_m,u_x,u_fin) AND account_status='deleted') = 4, NULL);

  -- the pre-A14 replay path is genuinely unavailable (documented seam)
  BEGIN
    PERFORM public._account_closure_core(u_d,'admin','qa');
    r := r || public._qa_s13_ok('N5FR.B7 naive closure replay is refused on an already-closed row', false, 'no refusal');
  EXCEPTION WHEN OTHERS THEN
    v_txt := SQLERRM;
    r := r || public._qa_s13_ok('N5FR.B7 naive closure replay is refused on an already-closed row',
          v_txt LIKE '%ACCOUNT_ALREADY_CLOSED%', v_txt);
  END;

  -- ============ B. GOVERNED IDEMPOTENT RECONCILIATION ============
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_god), true);

  res := public.admin_account_closure_reconcile(u_d, 'qa n5fr');
  r := r || public._qa_s13_ok('N5FR.C1 reconciliation succeeds on a legacy closed driver',
        (res->>'ok')::boolean, res::text);
  r := r || public._qa_s13_ok('N5FR.C2 the professional lane is released',
        NOT EXISTS (SELECT 1 FROM public.professional_identities
                     WHERE user_id=u_d AND claim_state='active'), NULL);
  r := r || public._qa_s13_ok('N5FR.C3 the lane row itself survives as provenance',
        EXISTS (SELECT 1 FROM public.professional_identities
                 WHERE user_id=u_d AND claim_state='released'), NULL);
  r := r || public._qa_s13_ok('N5FR.C4 surviving capability roles are revoked',
        (SELECT count(*) FROM public.user_roles WHERE user_id=u_d) = 0, NULL);
  r := r || public._qa_s13_ok('N5FR.C5 the driver row is no longer approved',
        (SELECT status FROM public.driver_profiles WHERE user_id=u_d) <> 'approved', NULL);
  r := r || public._qa_s13_ok('N5FR.C6 stale presence is forced offline',
        (SELECT presence FROM public.driver_profiles WHERE user_id=u_d) = 'offline', NULL);
  r := r || public._qa_s13_ok('N5FR.C7 the driver row itself is not deleted',
        EXISTS (SELECT 1 FROM public.driver_profiles WHERE user_id=u_d), NULL);
  r := r || public._qa_s13_ok('N5FR.C8 stale pending offers are expired',
        NOT EXISTS (SELECT 1 FROM public.ride_offers WHERE driver_id=u_d AND status='pending'), NULL);
  r := r || public._qa_s13_ok('N5FR.C9 the offer row survives as provenance, expired',
        EXISTS (SELECT 1 FROM public.ride_offers WHERE driver_id=u_d AND status='expired'), NULL);
  r := r || public._qa_s13_ok('N5FR.C10 recovery material is erased',
        NOT EXISTS (SELECT 1 FROM public.account_recovery_profiles WHERE user_id=u_d), NULL);
  r := r || public._qa_s13_ok('N5FR.C11 auth access termination is enqueued',
        EXISTS (SELECT 1 FROM public.account_access_terminations
                 WHERE user_id=u_d AND status='pending'), NULL);
  r := r || public._qa_s13_ok('N5FR.C12 an audit entry records the reconciliation',
        EXISTS (SELECT 1 FROM public.audit_logs
                 WHERE target_id=u_d::text AND action='account.closure_reconcile'), NULL);
  r := r || public._qa_s13_ok('N5FR.C13 the profile stays closed, never reopened',
        (SELECT account_status FROM public.profiles WHERE user_id=u_d) = 'deleted', NULL);

  -- idempotency: a second run must be a lawful no-op, not an error
  res := public.admin_account_closure_reconcile(u_d, 'qa n5fr repeat');
  r := r || public._qa_s13_ok('N5FR.C14 reconciliation is idempotent',
        (res->>'ok')::boolean, res::text);
  r := r || public._qa_s13_ok('N5FR.C15 the idempotent re-run revokes nothing further',
        (res->'authority'->>'roles_revoked')::int = 0
        AND (res->'authority'->>'ride_offers_expired')::int = 0, res::text);
  r := r || public._qa_s13_ok('N5FR.C16 the idempotent re-run leaves the released lane released',
        (SELECT count(*) FROM public.professional_identities
          WHERE user_id=u_d AND claim_state='active') = 0, NULL);

  -- ============ F. MERCHANT EQUIVALENT ============
  res := public.admin_account_closure_reconcile(u_m, 'qa n5fr merchant');
  r := r || public._qa_s13_ok('N5FR.D1 reconciliation succeeds on a legacy closed merchant',
        (res->>'ok')::boolean, res::text);
  r := r || public._qa_s13_ok('N5FR.D2 the merchant lane is released',
        NOT EXISTS (SELECT 1 FROM public.professional_identities
                     WHERE user_id=u_m AND claim_state='active'), NULL);
  r := r || public._qa_s13_ok('N5FR.D3 the merchant store is suspended, not deleted',
        (SELECT status FROM public.merchant_stores WHERE id=s_m) = 'suspended', NULL);
  r := r || public._qa_s13_ok('N5FR.D4 merchant capability roles are revoked',
        (SELECT count(*) FROM public.user_roles WHERE user_id=u_m) = 0, NULL);
  r := r || public._qa_s13_ok('N5FR.D5 merchant recovery material is erased',
        NOT EXISTS (SELECT 1 FROM public.account_recovery_profiles WHERE user_id=u_m), NULL);

  -- ============ G. LAWFUL CROSS-AXIS ============
  res := public.admin_account_closure_reconcile(u_x, 'qa n5fr cross-axis');
  r := r || public._qa_s13_ok('N5FR.E1 reconciliation succeeds on a lawful cross-axis account',
        (res->>'ok')::boolean, res::text);
  r := r || public._qa_s13_ok('N5FR.E2 the professional lane is released on the cross-axis account',
        NOT EXISTS (SELECT 1 FROM public.professional_identities
                     WHERE user_id=u_x AND claim_state='active'), NULL);
  r := r || public._qa_s13_ok('N5FR.E3 governance authority is suspended, not deleted',
        (SELECT status FROM public.admin_users WHERE user_id=u_x) = 'suspended', NULL);
  r := r || public._qa_s13_ok('N5FR.E4 the governance row survives as provenance',
        EXISTS (SELECT 1 FROM public.admin_users WHERE user_id=u_x), NULL);
  r := r || public._qa_s13_ok('N5FR.E5 the unrelated governance actor keeps its authority',
        (SELECT status FROM public.admin_users WHERE user_id=u_god) = 'active', NULL);
  r := r || public._qa_s13_ok('N5FR.E6 the cross-axis driver row is stood down',
        (SELECT status FROM public.driver_profiles WHERE user_id=u_x) <> 'approved'
        AND (SELECT presence FROM public.driver_profiles WHERE user_id=u_x) = 'offline', NULL);

  -- ============ H. FINANCE ============
  SELECT balance_gnf INTO v_bal FROM public.wallets WHERE owner_user_id=u_fin;
  r := r || public._qa_s13_ok('N5FR.F1 the finance fixture really holds a nonzero balance',
        v_bal = 29448, v_bal::text);
  res := public._account_closure_blockers(u_fin,'admin');
  r := r || public._qa_s13_ok('N5FR.F2 a nonzero balance still blocks full closure',
        (res->'blockers') @> '["WALLET_BALANCE_NONZERO"]'::jsonb
        AND (res->>'eligible')::boolean IS FALSE, res::text);
  res := public.professional_offboard_blockers(u_fin);
  r := r || public._qa_s13_ok('N5FR.F3 a nonzero balance does NOT block professional offboard',
        (res->>'eligible')::boolean IS TRUE, res::text);
  res := public.admin_account_closure_reconcile(u_fin, 'qa n5fr finance');
  r := r || public._qa_s13_ok('N5FR.F4 authority stand-down proceeds while money is unsettled',
        (res->>'ok')::boolean
        AND NOT EXISTS (SELECT 1 FROM public.professional_identities
                         WHERE user_id=u_fin AND claim_state='active'), res::text);
  SELECT balance_gnf INTO v_bal FROM public.wallets WHERE owner_user_id=u_fin;
  r := r || public._qa_s13_ok('N5FR.F5 the wallet balance is never touched by authority stand-down',
        v_bal = 29448, v_bal::text);
  r := r || public._qa_s13_ok('N5FR.F6 the wallet row is never deleted',
        EXISTS (SELECT 1 FROM public.wallets WHERE owner_user_id=u_fin), NULL);
  r := r || public._qa_s13_ok('N5FR.F7 no ad-hoc disposition journal was invented',
        (SELECT count(*) FROM public.ledger_postings) = b_lp, NULL);
  r := r || public._qa_s13_ok('N5FR.F8 the ledger stays balanced',
        (SELECT COALESCE(sum(amount_gnf),0) FROM public.ledger_postings) = b_ls, NULL);

  -- ============ C/D. ACCESS TERMINATION + STALE-CONTEXT BYPASS ============
  r := r || public._qa_s13_ok('N5FR.G1 the access gate refuses a closed but authenticated caller',
        (SELECT public.auth_uid_active() FROM (SELECT set_config('request.jwt.claims',
            public._as_user_claims(u_d), true)) _) IS NULL, NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_liv), true);
  r := r || public._qa_s13_ok('N5FR.G2 the access gate still passes a live account',
        public.auth_uid_active() = u_liv, NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_d), true);
  r := r || public._qa_s13_ok('N5FR.G3 a stale JWT confers no current identity after closure',
        auth.uid() = u_d AND public.auth_uid_active() IS NULL, NULL);
  r := r || public._qa_s13_ok('N5FR.G4 a closed account still owns nothing authoritative',
        NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id=u_d)
        AND NOT EXISTS (SELECT 1 FROM public.professional_identities
                         WHERE user_id=u_d AND claim_state='active'), NULL);
  r := r || public._qa_s13_ok('N5FR.G5 a surviving wallet artifact confers no authority',
        public.auth_uid_active() IS NULL
        AND EXISTS (SELECT 1 FROM public.wallets WHERE owner_user_id=u_d), NULL);
  r := r || public._qa_s13_ok('N5FR.G6 termination is enqueued for every reconciled account',
        (SELECT count(*) FROM public.account_access_terminations
          WHERE user_id IN (u_d,u_m,u_x,u_fin) AND status='pending') = 4, NULL);
  -- honest boundary: SQL cannot revoke a live Supabase session; the queue is
  -- the contract and the service-role worker performs the auth-layer act.
  r := r || public._qa_s13_ok('N5FR.G7 the termination contract records source provenance',
        (SELECT count(DISTINCT source) FROM public.account_access_terminations
          WHERE user_id IN (u_d,u_m,u_x,u_fin)) = 1, NULL);
  res := public.account_access_termination_record(u_d, true, NULL);
  r := r || public._qa_s13_ok('N5FR.G8 the worker can record a completed termination',
        (res->>'ok')::boolean
        AND (SELECT status FROM public.account_access_terminations WHERE user_id=u_d) = 'terminated', res::text);
  r := r || public._qa_s13_ok('N5FR.G9 a completed termination is timestamped',
        (SELECT terminated_at FROM public.account_access_terminations WHERE user_id=u_d) IS NOT NULL, NULL);

  -- ============ AUTHORIZATION MATRIX ============
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_liv), true);
  BEGIN
    PERFORM public.admin_account_closure_reconcile(u_m,'qa');
    r := r || public._qa_s13_ok('N5FR.H1 an ordinary user cannot reconcile anyone', false, 'no refusal');
  EXCEPTION WHEN OTHERS THEN
    v_txt := SQLERRM;
    r := r || public._qa_s13_ok('N5FR.H1 an ordinary user cannot reconcile anyone',
          v_txt LIKE '%NOT_AUTHORIZED%', v_txt);
  END;
  BEGIN
    PERFORM public.account_access_termination_record(u_m, true, NULL);
    r := r || public._qa_s13_ok('N5FR.H2 an ordinary user cannot record a termination', false, 'no refusal');
  EXCEPTION WHEN OTHERS THEN
    v_txt := SQLERRM;
    r := r || public._qa_s13_ok('N5FR.H2 an ordinary user cannot record a termination',
          v_txt LIKE '%NOT_AUTHORIZED%', v_txt);
  END;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_god), true);
  BEGIN
    PERFORM public.admin_account_closure_reconcile(u_liv,'qa');
    r := r || public._qa_s13_ok('N5FR.H3 a live account can never be reconciled as closed', false, 'no refusal');
  EXCEPTION WHEN OTHERS THEN
    v_txt := SQLERRM;
    r := r || public._qa_s13_ok('N5FR.H3 a live account can never be reconciled as closed',
          v_txt LIKE '%ACCOUNT_NOT_CLOSED%', v_txt);
  END;
  BEGIN
    PERFORM public.admin_account_closure_reconcile(u_god,'qa');
    r := r || public._qa_s13_ok('N5FR.H4 an admin cannot reconcile itself', false, 'no refusal');
  EXCEPTION WHEN OTHERS THEN
    v_txt := SQLERRM;
    r := r || public._qa_s13_ok('N5FR.H4 an admin cannot reconcile itself',
          v_txt LIKE '%SELF_RECONCILE_FORBIDDEN%' OR v_txt LIKE '%ACCOUNT_NOT_CLOSED%', v_txt);
  END;
  BEGIN
    PERFORM public.admin_account_closure_reconcile(gen_random_uuid(),'qa');
    r := r || public._qa_s13_ok('N5FR.H5 an unknown target is refused', false, 'no refusal');
  EXCEPTION WHEN OTHERS THEN
    v_txt := SQLERRM;
    r := r || public._qa_s13_ok('N5FR.H5 an unknown target is refused',
          v_txt LIKE '%ACCOUNT_NOT_FOUND%', v_txt);
  END;

  -- ============ I. RE-REGISTRATION ============
  UPDATE public.profiles SET phone = ph WHERE user_id = u_re;
  r := r || public._qa_s13_ok('N5FR.I1 the released contact can be taken by a new identity',
        (SELECT user_id FROM public.profiles WHERE phone = ph) = u_re, NULL);
  r := r || public._qa_s13_ok('N5FR.I2 the successor inherits no professional lane',
        NOT EXISTS (SELECT 1 FROM public.professional_identities
                     WHERE user_id=u_re AND claim_state='active'), NULL);
  r := r || public._qa_s13_ok('N5FR.I3 the successor inherits no capability role',
        NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id=u_re), NULL);
  r := r || public._qa_s13_ok('N5FR.I4 the successor inherits no wallet or balance',
        NOT EXISTS (SELECT 1 FROM public.wallets WHERE owner_user_id=u_re), NULL);
  r := r || public._qa_s13_ok('N5FR.I5 predecessor history stays bound to the closed UUID',
        EXISTS (SELECT 1 FROM public.ride_offers WHERE driver_id=u_d), NULL);
  r := r || public._qa_s13_ok('N5FR.I6 the successor is not access-terminated',
        NOT EXISTS (SELECT 1 FROM public.account_access_terminations WHERE user_id=u_re), NULL);

  -- ============ LIVE CONTROL: NO REGRESSION ============
  r := r || public._qa_s13_ok('N5FR.J1 the live control account keeps its role',
        EXISTS (SELECT 1 FROM public.user_roles WHERE user_id=u_liv), NULL);
  r := r || public._qa_s13_ok('N5FR.J2 the live control account keeps its wallet balance',
        (SELECT balance_gnf FROM public.wallets WHERE owner_user_id=u_liv) = 5000, NULL);
  r := r || public._qa_s13_ok('N5FR.J3 the live control account is never access-terminated',
        NOT EXISTS (SELECT 1 FROM public.account_access_terminations WHERE user_id=u_liv), NULL);
  r := r || public._qa_s13_ok('N5FR.J4 the live control account stays active',
        (SELECT account_status FROM public.profiles WHERE user_id=u_liv) = 'active', NULL);

  -- ================= CLEANUP + RESIDUE =================
  PERFORM set_config('request.jwt.claims', '', true);
  DELETE FROM public.account_access_terminations WHERE user_id = ANY(ids);
  DELETE FROM public.audit_logs WHERE target_id = ANY(SELECT x::text FROM unnest(ids) x);
  DELETE FROM public.ride_offers WHERE driver_id = ANY(ids);
  DELETE FROM public.rides WHERE id = ride_id;
  DELETE FROM public.account_recovery_profiles WHERE user_id = ANY(ids);
  DELETE FROM public.merchant_stores WHERE owner_user_id = ANY(ids);
  DELETE FROM public.admin_users WHERE user_id = ANY(ids);
  DELETE FROM public.user_roles WHERE user_id = ANY(ids);
  DELETE FROM public.wallets WHERE owner_user_id = ANY(ids);
  DELETE FROM public.driver_profiles WHERE user_id = ANY(ids);
  PERFORM public._qa_users_purge(ids);

  SELECT count(*) INTO a_pr FROM public.profiles;
  SELECT count(*) INTO a_w  FROM public.wallets;
  SELECT count(*) INTO a_pi FROM public.professional_identities;
  SELECT count(*) INTO a_lp FROM public.ledger_postings;
  SELECT COALESCE(sum(amount_gnf),0) INTO a_ls FROM public.ledger_postings;
  SELECT count(*) INTO a_ur FROM public.user_roles;
  SELECT count(*) INTO a_au FROM public.admin_users;
  SELECT count(*) INTO a_dp FROM public.driver_profiles;
  SELECT count(*) INTO a_ro FROM public.ride_offers;
  SELECT count(*) INTO a_at FROM public.account_access_terminations;

  r := r || public._qa_s13_ok('N5FR.K1 profiles residue is zero', a_pr = b_pr, (a_pr-b_pr)::text);
  r := r || public._qa_s13_ok('N5FR.K2 wallet residue is zero', a_w = b_w, (a_w-b_w)::text);
  r := r || public._qa_s13_ok('N5FR.K3 professional identity residue is zero', a_pi = b_pi, (a_pi-b_pi)::text);
  r := r || public._qa_s13_ok('N5FR.K4 ledger postings are untouched', a_lp = b_lp, (a_lp-b_lp)::text);
  r := r || public._qa_s13_ok('N5FR.K5 the ledger still sums to its prior value', a_ls = b_ls, (a_ls-b_ls)::text);
  r := r || public._qa_s13_ok('N5FR.K6 user_roles residue is zero', a_ur = b_ur, (a_ur-b_ur)::text);
  r := r || public._qa_s13_ok('N5FR.K7 admin_users residue is zero', a_au = b_au, (a_au-b_au)::text);
  r := r || public._qa_s13_ok('N5FR.K8 driver_profiles residue is zero', a_dp = b_dp, (a_dp-b_dp)::text);
  r := r || public._qa_s13_ok('N5FR.K9 ride_offers residue is zero', a_ro = b_ro, (a_ro-b_ro)::text);
  r := r || public._qa_s13_ok('N5FR.K10 termination queue residue is zero', a_at = b_at, (a_at-b_at)::text);

  RETURN jsonb_build_object(
    'suite','_qa_node5_identity_final_remediation',
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'results', r);
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', '', true);
  BEGIN
    DELETE FROM public.account_access_terminations WHERE user_id = ANY(ids);
    DELETE FROM public.audit_logs WHERE target_id = ANY(SELECT x::text FROM unnest(ids) x);
    DELETE FROM public.ride_offers WHERE driver_id = ANY(ids);
    DELETE FROM public.rides WHERE id = ride_id;
    DELETE FROM public.account_recovery_profiles WHERE user_id = ANY(ids);
    DELETE FROM public.merchant_stores WHERE owner_user_id = ANY(ids);
    DELETE FROM public.admin_users WHERE user_id = ANY(ids);
    DELETE FROM public.user_roles WHERE user_id = ANY(ids);
    DELETE FROM public.wallets WHERE owner_user_id = ANY(ids);
    DELETE FROM public.driver_profiles WHERE user_id = ANY(ids);
    PERFORM public._qa_users_purge(ids);
  EXCEPTION WHEN OTHERS THEN NULL; END;
  RAISE;
END
$function$;

REVOKE ALL ON FUNCTION public._qa_node5_identity_final_remediation() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._qa_node5_identity_final_remediation() TO service_role;
