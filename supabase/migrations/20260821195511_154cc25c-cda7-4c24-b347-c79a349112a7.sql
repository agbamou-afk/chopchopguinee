CREATE OR REPLACE FUNCTION public._qa_node5_identity_a14()
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public
SET statement_timeout = '300s'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  u_d   uuid := gen_random_uuid();  -- driver lane, closes cleanly
  u_m   uuid := gen_random_uuid();  -- merchant lane with a store
  u_bl  uuid := gen_random_uuid();  -- blocker probe
  u_gov uuid := gen_random_uuid();  -- active governance account, self-close refused
  u_god uuid := gen_random_uuid();  -- governance actor
  u_re  uuid := gen_random_uuid();  -- re-registration successor
  ids uuid[];
  s_m uuid := gen_random_uuid();
  p1 text; p2 text;
  res jsonb; bl jsonb; v_n bigint; v_txt text; v_ok boolean;
  b_pr bigint; b_w bigint; b_pi bigint; b_lp bigint; b_ls numeric; b_ur bigint;
  b_au bigint; b_ms bigint; b_dp bigint; b_al bigint; b_adr bigint; b_flags jsonb;
  a_pr bigint; a_w bigint; a_pi bigint; a_lp bigint; a_ls numeric; a_ur bigint;
  a_au bigint; a_ms bigint; a_dp bigint; a_al bigint; a_adr bigint; a_flags jsonb;
  k_pr bigint; k_w bigint; k_ur bigint; k_au bigint;
BEGIN
  ids := ARRAY[u_d,u_m,u_bl,u_gov,u_god,u_re];
  p1 := '+22465' || lpad((floor(random()*10000000))::bigint::text, 7, '0');
  p2 := '+22466' || lpad((floor(random()*10000000))::bigint::text, 7, '0');

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
  SELECT count(*) INTO b_adr FROM public.account_deletion_requests;
  SELECT jsonb_object_agg(key, enabled) INTO b_flags FROM public.feature_flags;

  -- ================= A. STRUCTURAL CLOSURE LAW =================
  r := r || public._qa_s13_ok('N5A14.A1 a single canonical closure-blocker engine exists',
        to_regprocedure('public._account_closure_blockers(uuid,text)') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N5A14.A2 a single canonical closure core exists',
        to_regprocedure('public._account_closure_core(uuid,text,text)') IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N5A14.A3 no parallel deletion subsystem was invented',
        (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
          WHERE n.nspname='public' AND p.proname ~ '^(admin_)?(anonymize|purge|erase)_user') <= 1, NULL);
  r := r || public._qa_s14_noop() IS NULL;
  r := r || public._qa_s13_ok('N5A14.A4 the closure core is unreachable from any client role',
        NOT has_function_privilege('anon','public._account_closure_core(uuid,text,text)','EXECUTE')
        AND NOT has_function_privilege('authenticated','public._account_closure_core(uuid,text,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A14.A5 the blocker engine is unreachable from any client role',
        NOT has_function_privilege('anon','public._account_closure_blockers(uuid,text)','EXECUTE')
        AND NOT has_function_privilege('authenticated','public._account_closure_blockers(uuid,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A14.A6 the eligibility read surface is signed-in only',
        NOT has_function_privilege('anon','public.account_closure_blockers(uuid)','EXECUTE')
        AND has_function_privilege('authenticated','public.account_closure_blockers(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A14.A7 self closure stays signed-in only',
        NOT has_function_privilege('anon','public.request_account_deletion(text)','EXECUTE')
        AND has_function_privilege('authenticated','public.request_account_deletion(text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A14.A8 admin closure is never signed-out callable',
        NOT has_function_privilege('anon','public.admin_anonymize_user(uuid,text)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A14.A9 the hard-delete evidence gate is never signed-out callable',
        NOT has_function_privilege('anon','public.user_has_financial_history(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N5A14.A10 the A14 suite itself is never client-callable',
        NOT has_function_privilege('anon','public._qa_node5_identity_a14()','EXECUTE')
        AND NOT has_function_privilege('authenticated','public._qa_node5_identity_a14()','EXECUTE'), NULL);

  -- FK provenance protection: deleting the login may not shred history
  r := r || public._qa_s13_ok('N5A14.A11 driver payout history blocks hard deletion of the login',
        (SELECT confdeltype FROM pg_constraint
          WHERE conname='driver_cashout_requests_driver_user_id_fkey') = 'r', NULL);
  r := r || public._qa_s13_ok('N5A14.A12 professional identity history blocks hard deletion of the login',
        (SELECT confdeltype FROM pg_constraint
          WHERE conname='professional_identities_user_id_fkey') = 'r', NULL);
  r := r || public._qa_s13_ok('N5A14.A13 account freeze history blocks hard deletion of the login',
        (SELECT confdeltype FROM pg_constraint
          WHERE conname='account_freezes_user_id_fkey') = 'r', NULL);
  r := r || public._qa_s13_ok('N5A14.A14 field daily reports block hard deletion of the login',
        (SELECT confdeltype FROM pg_constraint
          WHERE conname='field_daily_reports_user_id_fkey') = 'r', NULL);
  r := r || public._qa_s13_ok('N5A14.A15 field merchant visits block hard deletion of the login',
        (SELECT confdeltype FROM pg_constraint
          WHERE conname='field_merchant_visits_assigned_user_id_fkey') = 'r', NULL);
  r := r || public._qa_s13_ok('N5A14.A16 wallet ledger postings are never cascade-deleted by an account',
        NOT EXISTS (SELECT 1 FROM pg_constraint
                     WHERE conrelid='public.ledger_postings'::regclass
                       AND contype='f' AND confdeltype='c'), NULL);
  r := r || public._qa_s13_ok('N5A14.A17 closure requests keep a permanent record table',
        to_regclass('public.account_deletion_requests') IS NOT NULL, NULL);

  -- ================= FIXTURES =================
  PERFORM public._qa_users_new(u_d,  'qa-n5a14-d-'  ||substr(u_d::text,1,8)  ||'@example.com');
  PERFORM public._qa_users_new(u_m,  'qa-n5a14-m-'  ||substr(u_m::text,1,8)  ||'@example.com');
  PERFORM public._qa_users_new(u_bl, 'qa-n5a14-bl-' ||substr(u_bl::text,1,8) ||'@example.com');
  PERFORM public._qa_users_new(u_gov,'qa-n5a14-gov-'||substr(u_gov::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_god,'qa-n5a14-god-'||substr(u_god::text,1,8)||'@example.com');

  UPDATE public.profiles SET phone = p1 WHERE user_id = u_d;
  INSERT INTO public.admin_users(user_id, role, status)
  VALUES (u_god,'god_admin'::public.admin_role,'active'::public.admin_user_status),
         (u_gov,'ops_admin'::public.admin_role,'active'::public.admin_user_status);

  -- driver lane, clean and offline
  PERFORM public._professional_identity_claim(u_d,'driver','qa-n5a14');
  INSERT INTO public.driver_profiles(user_id, status, presence, cash_debt_gnf)
  VALUES (u_d,'approved'::public.driver_status,'offline'::public.driver_presence,0)
  ON CONFLICT (user_id) DO UPDATE
    SET status='approved'::public.driver_status,
        presence='offline'::public.driver_presence, cash_debt_gnf=0;
  INSERT INTO public.user_roles(user_id, role) VALUES (u_d,'driver'::public.app_role)
    ON CONFLICT DO NOTHING;
  INSERT INTO public.wallets(owner_user_id, party_type, balance_gnf)
  VALUES (u_d,'driver'::public.party_type,0) ON CONFLICT DO NOTHING;
  INSERT INTO public.account_recovery_profiles(
    user_id, birthdate_hash, question_1_id, answer_1_hash, question_2_id, answer_2_hash,
    question_3_id, answer_3_hash, recovery_key_hash)
  VALUES (u_d,'h','q1','h1','q2','h2','q3','h3','rk');

  -- merchant lane with a store
  PERFORM public._professional_identity_claim(u_m,'merchant','qa-n5a14');
  INSERT INTO public.merchant_stores(id, owner_user_id, slug, name, status, is_active)
  VALUES (s_m, u_m, 'qa-n5a14-'||substr(s_m::text,1,8), 'QA A14 Store','active',true);

  -- ================= B. BLOCKER ENGINE =================
  bl := public._account_closure_blockers(u_bl,'self');
  r := r || public._qa_s13_ok('N5A14.B1 a clean account with no obligations is closure-eligible',
        (bl->>'eligible')::boolean, bl::text);

  UPDATE public.wallets SET balance_gnf = 5000 WHERE owner_user_id = u_d;
  bl := public._account_closure_blockers(u_d,'self');
  r := r || public._qa_s13_ok('N5A14.B2 remaining wallet money blocks closure',
        bl->'blockers' @> '["WALLET_BALANCE_NONZERO"]'::jsonb, bl::text);
  r := r || public._qa_s13_ok('N5A14.B3 a blocked account is not reported eligible',
        (bl->>'eligible')::boolean IS FALSE, bl::text);

  UPDATE public.wallets SET balance_gnf = 0, held_gnf = 2500 WHERE owner_user_id = u_d;
  bl := public._account_closure_blockers(u_d,'self');
  r := r || public._qa_s13_ok('N5A14.B4 funds still on hold block closure',
        bl->'blockers' @> '["WALLET_FUNDS_HELD"]'::jsonb, bl::text);
  UPDATE public.wallets SET held_gnf = 0 WHERE owner_user_id = u_d;

  UPDATE public.driver_profiles SET cash_debt_gnf = 12000 WHERE user_id = u_d;
  bl := public._account_closure_blockers(u_d,'self');
  r := r || public._qa_s13_ok('N5A14.B5 unpaid driver cash debt blocks closure',
        bl->'blockers' @> '["DRIVER_CASH_DEBT_OUTSTANDING"]'::jsonb, bl::text);
  UPDATE public.driver_profiles SET cash_debt_gnf = 0 WHERE user_id = u_d;

  INSERT INTO public.account_freezes(user_id, status, reason)
  VALUES (u_bl,'active','qa-n5a14');
  bl := public._account_closure_blockers(u_bl,'self');
  r := r || public._qa_s13_ok('N5A14.B6 an active account freeze blocks closure',
        bl->'blockers' @> '["ACCOUNT_FREEZE_ACTIVE"]'::jsonb, bl::text);
  UPDATE public.account_freezes SET status='lifted' WHERE user_id = u_bl;
  bl := public._account_closure_blockers(u_bl,'self');
  r := r || public._qa_s13_ok('N5A14.B7 a lifted freeze no longer blocks closure',
        (bl->>'eligible')::boolean, bl::text);

  bl := public._account_closure_blockers(u_gov,'self');
  r := r || public._qa_s13_ok('N5A14.B8 an active staff account cannot self-close',
        bl->'blockers' @> '["GOVERNANCE_AUTHORITY_ACTIVE"]'::jsonb, bl::text);
  bl := public._account_closure_blockers(u_gov,'admin');
  r := r || public._qa_s13_ok('N5A14.B9 governance closure of a staff account is an admin act, not a staff self-service act',
        NOT (bl->'blockers' @> '["GOVERNANCE_AUTHORITY_ACTIVE"]'::jsonb), bl::text);

  bl := public._account_closure_blockers(u_d,'self');
  r := r || public._qa_s13_ok('N5A14.B10 the blocker report names the professional lane',
        bl->>'lane' = 'driver', bl::text);
  bl := public._account_closure_blockers(u_bl,'self');
  r := r || public._qa_s13_ok('N5A14.B11 an account with no professional lane reports none',
        bl->>'lane' = 'none', bl::text);
  r := r || public._qa_s13_ok('N5A14.B12 blockers are returned as a machine-readable array',
        jsonb_typeof(bl->'blockers') = 'array', bl::text);
  UPDATE public.wallets SET balance_gnf = 7000 WHERE owner_user_id = u_d;
  bl := public._account_closure_blockers(u_d,'self');
  r := r || public._qa_s13_ok('N5A14.B13 blocker tokens are deduplicated and stable',
        (SELECT count(*) = count(DISTINCT x) FROM jsonb_array_elements_text(bl->'blockers') x), bl::text);
  r := r || public._qa_s13_ok('N5A14.B14 the blocker report is never anonymous',
        (bl->>'user_id')::uuid = u_d, bl::text);

  -- ================= C. FAIL-CLOSED: BLOCKED CHANGES NOTHING =================
  SELECT count(*) INTO k_pr FROM public.profiles WHERE account_status = 'deleted';
  SELECT count(*) INTO k_ur FROM public.user_roles WHERE user_id = u_d;
  SELECT count(*) INTO k_w  FROM public.wallets WHERE owner_user_id = u_d;

  BEGIN
    res := public._account_closure_core(u_d,'self','qa blocked probe');
    r := r || public._qa_s13_ok('N5A14.C1 a blocked closure is refused', false, 'no exception raised');
  EXCEPTION WHEN OTHERS THEN
    v_txt := SQLERRM;
    r := r || public._qa_s13_ok('N5A14.C1 a blocked closure is refused',
          v_txt LIKE 'ACCOUNT_CLOSURE_BLOCKED%', v_txt);
  END;
  r := r || public._qa_s13_ok('N5A14.C2 the refusal names the exact reason',
        v_txt LIKE '%WALLET_BALANCE_NONZERO%', v_txt);
  r := r || public._qa_s13_ok('N5A14.C3 a blocked closure did not mark the account closed',
        (SELECT account_status FROM public.profiles WHERE user_id = u_d) IS DISTINCT FROM 'deleted', NULL);
  r := r || public._qa_s13_ok('N5A14.C4 a blocked closure did not revoke capability roles',
        (SELECT count(*) FROM public.user_roles WHERE user_id = u_d) = k_ur, NULL);
  r := r || public._qa_s13_ok('N5A14.C5 a blocked closure did not release the professional lane',
        EXISTS (SELECT 1 FROM public.professional_identities
                 WHERE user_id = u_d AND claim_state = 'active'), NULL);
  r := r || public._qa_s13_ok('N5A14.C6 a blocked closure did not erase recovery enrolment',
        EXISTS (SELECT 1 FROM public.account_recovery_profiles WHERE user_id = u_d), NULL);
  r := r || public._qa_s13_ok('N5A14.C7 a blocked closure did not touch the money',
        (SELECT balance_gnf FROM public.wallets WHERE owner_user_id = u_d) = 7000, NULL);
  r := r || public._qa_s13_ok('N5A14.C8 a blocked closure did not clear contact identity',
        (SELECT phone FROM public.profiles WHERE user_id = u_d) = p1, NULL);
  r := r || public._qa_s13_ok('N5A14.C9 a blocked closure created no closure record',
        (SELECT count(*) FROM public.account_deletion_requests WHERE user_id = u_d) = 0, NULL);

  -- admin path returns the blockers rather than throwing
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_god), true);
  res := public.admin_anonymize_user(u_d,'qa blocked admin probe');
  PERFORM set_config('request.jwt.claims','',true);
  r := r || public._qa_s13_ok('N5A14.C10 governance closure of a blocked account is refused',
        (res->>'ok')::boolean IS FALSE, res::text);
  r := r || public._qa_s13_ok('N5A14.C11 governance refusal returns machine-readable blockers',
        res->'blockers' @> '["WALLET_BALANCE_NONZERO"]'::jsonb, res::text);
  r := r || public._qa_s13_ok('N5A14.C12 governance refusal did not close the account',
        (SELECT account_status FROM public.profiles WHERE user_id = u_d) IS DISTINCT FROM 'deleted', NULL);

  -- ================= D. AUTHORITY STAND-DOWN ON CLOSURE =================
  UPDATE public.wallets SET balance_gnf = 0 WHERE owner_user_id = u_d;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_god), true);
  res := public.admin_anonymize_user(u_d,'qa a14 closure');
  PERFORM set_config('request.jwt.claims','',true);

  r := r || public._qa_s13_ok('N5A14.D1 an eligible account closes successfully',
        (res->>'ok')::boolean, res::text);
  r := r || public._qa_s13_ok('N5A14.D2 the account is marked closed',
        (SELECT account_status FROM public.profiles WHERE user_id = u_d) = 'deleted', NULL);
  r := r || public._qa_s13_ok('N5A14.D3 closure released the professional lane',
        NOT EXISTS (SELECT 1 FROM public.professional_identities
                     WHERE user_id = u_d AND claim_state = 'active'), NULL);
  r := r || public._qa_s13_ok('N5A14.D4 the released lane is retained as history, not deleted',
        EXISTS (SELECT 1 FROM public.professional_identities WHERE user_id = u_d), NULL);
  r := r || public._qa_s13_ok('N5A14.D5 the driver operating profile is stood down',
        (SELECT status FROM public.driver_profiles WHERE user_id = u_d)
          = 'suspended'::public.driver_status, NULL);
  r := r || public._qa_s13_ok('N5A14.D6 the driver is forced offline',
        (SELECT presence FROM public.driver_profiles WHERE user_id = u_d)
          = 'offline'::public.driver_presence, NULL);
  r := r || public._qa_s13_ok('N5A14.D7 capability roles are revoked',
        NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = u_d), NULL);
  r := r || public._qa_s13_ok('N5A14.D8 recovery enrolment is erased at closure',
        NOT EXISTS (SELECT 1 FROM public.account_recovery_profiles WHERE user_id = u_d), NULL);
  r := r || public._qa_s13_ok('N5A14.D9 recovery challenges are erased at closure',
        NOT EXISTS (SELECT 1 FROM public.account_recovery_challenges WHERE user_id = u_d), NULL);
  r := r || public._qa_s13_ok('N5A14.D10 contact PII is released',
        (SELECT phone FROM public.profiles WHERE user_id = u_d) IS DISTINCT FROM p1, NULL);
  r := r || public._qa_s13_ok('N5A14.D11 the closure is audited',
        EXISTS (SELECT 1 FROM public.audit_logs
                 WHERE action = 'account.closure' AND target_id = u_d::text), NULL);
  r := r || public._qa_s13_ok('N5A14.D12 the closure request is recorded permanently',
        EXISTS (SELECT 1 FROM public.account_deletion_requests
                 WHERE user_id = u_d AND status = 'processed'), NULL);
  r := r || public._qa_s13_ok('N5A14.D13 the closure result reports the authority actually removed',
        res->'authority' ? 'roles_revoked' AND res->'authority' ? 'governance_suspended', res::text);

  -- history retention
  r := r || public._qa_s13_ok('N5A14.D14 the canonical account row survives closure',
        EXISTS (SELECT 1 FROM public.profiles WHERE user_id = u_d), NULL);
  r := r || public._qa_s13_ok('N5A14.D15 the wallet record survives closure as financial provenance',
        EXISTS (SELECT 1 FROM public.wallets WHERE owner_user_id = u_d), NULL);
  r := r || public._qa_s13_ok('N5A14.D16 the audit trail still points at the original account uuid',
        (SELECT count(*) FROM public.audit_logs
          WHERE action='account.closure' AND target_id = u_d::text) >= 1, NULL);

  -- idempotency
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_god), true);
  res := public.admin_anonymize_user(u_d,'qa a14 second closure');
  PERFORM set_config('request.jwt.claims','',true);
  r := r || public._qa_s13_ok('N5A14.D17 an already-closed account cannot be closed twice',
        (res->>'ok')::boolean IS FALSE, res::text);
  r := r || public._qa_s13_ok('N5A14.D18 the repeat refusal is explicit, not silent success',
        COALESCE(res->>'detail', res->>'error','') ILIKE '%ALREADY_CLOSED%', res::text);
  r := r || public._qa_s13_ok('N5A14.D19 the repeat attempt created no second closure record',
        (SELECT count(*) FROM public.account_deletion_requests WHERE user_id = u_d) = 1, NULL);

  -- ================= E. GOVERNANCE AXIS STAND-DOWN =================
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_god), true);
  res := public.admin_anonymize_user(u_gov,'qa a14 staff closure');
  PERFORM set_config('request.jwt.claims','',true);
  r := r || public._qa_s13_ok('N5A14.E1 governance may close a staff account',
        (res->>'ok')::boolean, res::text);
  r := r || public._qa_s13_ok('N5A14.E2 staff authority is suspended by closure',
        (SELECT status FROM public.admin_users WHERE user_id = u_gov)
          = 'suspended'::public.admin_user_status, NULL);
  r := r || public._qa_s13_ok('N5A14.E3 the staff record is retained as governance provenance',
        EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = u_gov), NULL);
  r := r || public._qa_s13_ok('N5A14.E4 a closed staff account holds no live admin authority',
        NOT public.has_admin_role(u_gov,'ops_admin'::public.admin_role), NULL);
  r := r || public._qa_s13_ok('N5A14.E5 closure did not touch the acting governance account',
        (SELECT status FROM public.admin_users WHERE user_id = u_god)
          = 'active'::public.admin_user_status, NULL);

  -- merchant lane closure
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_god), true);
  res := public.admin_anonymize_user(u_m,'qa a14 merchant closure');
  PERFORM set_config('request.jwt.claims','',true);
  r := r || public._qa_s13_ok('N5A14.E6 a merchant account closes',
        (res->>'ok')::boolean, res::text);
  r := r || public._qa_s13_ok('N5A14.E7 merchant storefronts are stood down at closure',
        (SELECT status FROM public.merchant_stores WHERE id = s_m) = 'suspended', NULL);
  r := r || public._qa_s13_ok('N5A14.E8 a stood-down storefront is not publicly active',
        (SELECT is_active FROM public.merchant_stores WHERE id = s_m) IS FALSE, NULL);
  r := r || public._qa_s13_ok('N5A14.E9 the merchant lane is released',
        NOT EXISTS (SELECT 1 FROM public.professional_identities
                     WHERE user_id = u_m AND claim_state='active'), NULL);
  r := r || public._qa_s13_ok('N5A14.E10 the storefront row survives as commercial provenance',
        EXISTS (SELECT 1 FROM public.merchant_stores WHERE id = s_m), NULL);

  -- ================= F. RE-REGISTRATION IS A NEW IDENTITY =================
  PERFORM public._qa_users_new(u_re, 'qa-n5a14-re-'||substr(u_re::text,1,8)||'@example.com');
  UPDATE public.profiles SET phone = p1 WHERE user_id = u_re;
  r := r || public._qa_s13_ok('N5A14.F1 a released contact number can be taken by a new account',
        (SELECT phone FROM public.profiles WHERE user_id = u_re) = p1, NULL);
  r := r || public._qa_s13_ok('N5A14.F2 the new account is a different canonical uuid',
        u_re <> u_d, NULL);
  r := r || public._qa_s13_ok('N5A14.F3 the successor inherits no professional lane',
        NOT EXISTS (SELECT 1 FROM public.professional_identities WHERE user_id = u_re), NULL);
  r := r || public._qa_s13_ok('N5A14.F4 the successor inherits no capability roles',
        NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = u_re), NULL);
  r := r || public._qa_s13_ok('N5A14.F5 the successor inherits no governance authority',
        NOT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = u_re), NULL);
  r := r || public._qa_s13_ok('N5A14.F6 the successor inherits no driver operating profile',
        NOT EXISTS (SELECT 1 FROM public.driver_profiles WHERE user_id = u_re), NULL);
  r := r || public._qa_s13_ok('N5A14.F7 the successor inherits no wallet from the closed account',
        NOT EXISTS (SELECT 1 FROM public.wallets WHERE owner_user_id = u_re), NULL);
  r := r || public._qa_s13_ok('N5A14.F8 the closed account keeps its own wallet history',
        EXISTS (SELECT 1 FROM public.wallets WHERE owner_user_id = u_d), NULL);
  r := r || public._qa_s13_ok('N5A14.F9 closure history never migrates to the successor',
        NOT EXISTS (SELECT 1 FROM public.account_deletion_requests WHERE user_id = u_re), NULL);
  r := r || public._qa_s13_ok('N5A14.F10 the successor is an open account, not a resurrected closed one',
        (SELECT account_status FROM public.profiles WHERE user_id = u_re) IS DISTINCT FROM 'deleted', NULL);
  r := r || public._qa_s13_ok('N5A14.F11 the successor starts closure-eligible with no inherited obligations',
        (public._account_closure_blockers(u_re,'self')->>'eligible')::boolean, NULL);
  r := r || public._qa_s13_ok('N5A14.F12 the closed account still owns its released lane record',
        (SELECT count(*) FROM public.professional_identities WHERE user_id = u_d) = 1, NULL);

  -- ================= G. HARD-DELETE EVIDENCE GATE =================
  r := r || public._qa_s13_ok('N5A14.G1 an account with a wallet is never eligible for hard deletion',
        public.user_has_financial_history(u_d), NULL);
  r := r || public._qa_s13_ok('N5A14.G2 professional history alone blocks hard deletion',
        public.user_has_financial_history(u_m), NULL);
  r := r || public._qa_s13_ok('N5A14.G3 governance history alone blocks hard deletion',
        public.user_has_financial_history(u_gov), NULL);
  r := r || public._qa_s13_ok('N5A14.G4 an account with no history at all is not falsely flagged',
        NOT public.user_has_financial_history(u_re), NULL);

  -- ================= H. AUTHORISATION MATRIX =================
  PERFORM set_config('request.jwt.claims','',true);
  BEGIN
    bl := public.account_closure_blockers(u_d);
    r := r || public._qa_s13_ok('N5A14.H1 signed-out callers cannot read closure eligibility', false, 'no exception');
  EXCEPTION WHEN OTHERS THEN
    r := r || public._qa_s13_ok('N5A14.H1 signed-out callers cannot read closure eligibility',
          SQLERRM LIKE '%AUTH_REQUIRED%', SQLERRM);
  END;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_re), true);
  BEGIN
    bl := public.account_closure_blockers(u_d);
    r := r || public._qa_s13_ok('N5A14.H2 a signed-in user cannot inspect another account''s closure state', false, 'no exception');
  EXCEPTION WHEN OTHERS THEN
    r := r || public._qa_s13_ok('N5A14.H2 a signed-in user cannot inspect another account''s closure state',
          SQLERRM LIKE '%NOT_AUTHORIZED%', SQLERRM);
  END;
  bl := public.account_closure_blockers(NULL);
  r := r || public._qa_s13_ok('N5A14.H3 a signed-in user can inspect their own closure state',
        (bl->>'user_id')::uuid = u_re, bl::text);
  BEGIN
    res := public.admin_anonymize_user(u_re,'qa non admin');
    r := r || public._qa_s13_ok('N5A14.H4 a non-admin cannot close another account', false, 'no exception');
  EXCEPTION WHEN OTHERS THEN
    r := r || public._qa_s13_ok('N5A14.H4 a non-admin cannot close another account',
          SQLSTATE = '42501', SQLSTATE);
  END;
  PERFORM set_config('request.jwt.claims','',true);
  BEGIN
    PERFORM public.request_account_deletion('qa signed out');
    r := r || public._qa_s13_ok('N5A14.H5 signed-out self closure is refused', false, 'no exception');
  EXCEPTION WHEN OTHERS THEN
    r := r || public._qa_s13_ok('N5A14.H5 signed-out self closure is refused',
          SQLERRM ILIKE '%not_authenticated%', SQLERRM);
  END;

  -- self-service closure end to end
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_re), true);
  res := public.request_account_deletion('qa a14 self closure');
  PERFORM set_config('request.jwt.claims','',true);
  r := r || public._qa_s13_ok('N5A14.H6 a clean user can close their own account',
        (res->>'ok')::boolean, res::text);
  r := r || public._qa_s13_ok('N5A14.H7 self closure marks the account closed',
        (SELECT account_status FROM public.profiles WHERE user_id = u_re) = 'deleted', NULL);
  r := r || public._qa_s13_ok('N5A14.H8 self closure is recorded as a self-initiated request',
        EXISTS (SELECT 1 FROM public.account_deletion_requests
                 WHERE user_id = u_re AND request_type = 'self_delete'), NULL);
  r := r || public._qa_s13_ok('N5A14.H9 self closure releases the contact number again',
        (SELECT phone FROM public.profiles WHERE user_id = u_re) IS DISTINCT FROM p1, NULL);
  r := r || public._qa_s13_ok('N5A14.H10 self closure is audited like governance closure',
        EXISTS (SELECT 1 FROM public.audit_logs
                 WHERE action='account.closure' AND target_id = u_re::text), NULL);

  -- ================= CLEANUP =================
  PERFORM set_config('request.jwt.claims', NULL, true);
  DELETE FROM public.account_deletion_requests WHERE user_id = ANY(ids) OR requested_by = ANY(ids);
  DELETE FROM public.account_recovery_challenges WHERE user_id = ANY(ids);
  DELETE FROM public.account_recovery_profiles WHERE user_id = ANY(ids);
  DELETE FROM public.account_freezes WHERE user_id = ANY(ids);
  DELETE FROM public.audit_logs WHERE actor_user_id = ANY(ids)
     OR target_id IN (SELECT x::text FROM unnest(ids) x);
  DELETE FROM public.user_preferences WHERE user_id = ANY(ids);
  DELETE FROM public.marketplace_listings WHERE seller_id = ANY(ids) OR store_id = s_m;
  DELETE FROM public.merchant_stores WHERE owner_user_id = ANY(ids) OR id = s_m;
  DELETE FROM public.wallets WHERE owner_user_id = ANY(ids);
  DELETE FROM public.driver_locations WHERE user_id = ANY(ids);
  DELETE FROM public.driver_applications WHERE user_id = ANY(ids);
  DELETE FROM public.driver_profiles WHERE user_id = ANY(ids);
  DELETE FROM public.professional_identities WHERE user_id = ANY(ids);
  DELETE FROM public.admin_users WHERE user_id = ANY(ids);
  DELETE FROM public.user_roles WHERE user_id = ANY(ids);
  PERFORM public._qa_a5_cleanup(ids);

  -- ================= M. MASS BALANCE =================
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
  SELECT count(*) INTO a_adr FROM public.account_deletion_requests;
  SELECT jsonb_object_agg(key, enabled) INTO a_flags FROM public.feature_flags;

  r := r || public._qa_s13_ok('N5A14.M1 profiles returned to baseline', a_pr = b_pr, b_pr||'->'||a_pr);
  r := r || public._qa_s13_ok('N5A14.M2 wallets returned to baseline', a_w = b_w, b_w||'->'||a_w);
  r := r || public._qa_s13_ok('N5A14.M3 professional identities returned to baseline', a_pi = b_pi, b_pi||'->'||a_pi);
  r := r || public._qa_s13_ok('N5A14.M4 ledger postings returned to baseline', a_lp = b_lp, b_lp||'->'||a_lp);
  r := r || public._qa_s13_ok('N5A14.M5 ledger sum unchanged', a_ls = b_ls, b_ls||'->'||a_ls);
  r := r || public._qa_s13_ok('N5A14.M6 capability roles returned to baseline', a_ur = b_ur, b_ur||'->'||a_ur);
  r := r || public._qa_s13_ok('N5A14.M7 governance records returned to baseline', a_au = b_au, b_au||'->'||a_au);
  r := r || public._qa_s13_ok('N5A14.M8 stores returned to baseline', a_ms = b_ms, b_ms||'->'||a_ms);
  r := r || public._qa_s13_ok('N5A14.M9 driver profiles returned to baseline', a_dp = b_dp, b_dp||'->'||a_dp);
  r := r || public._qa_s13_ok('N5A14.M10 audit trail returned to baseline', a_al = b_al, b_al||'->'||a_al);
  r := r || public._qa_s13_ok('N5A14.M11 closure records returned to baseline', a_adr = b_adr, b_adr||'->'||a_adr);
  r := r || public._qa_s13_ok('N5A14.M12 feature flags unchanged', a_flags = b_flags, NULL);
  r := r || public._qa_s13_ok('N5A14.M13 zero identity residue',
        NOT EXISTS (SELECT 1 FROM public.profiles WHERE user_id = ANY(ids))
        AND NOT EXISTS (SELECT 1 FROM public.professional_identities WHERE user_id = ANY(ids))
        AND NOT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = ANY(ids)), NULL);
  r := r || public._qa_s13_ok('N5A14.M14 zero finance residue',
        NOT EXISTS (SELECT 1 FROM public.wallets WHERE owner_user_id = ANY(ids)), NULL);
  r := r || public._qa_s13_ok('N5A14.M15 zero recycled-phone residue',
        NOT EXISTS (SELECT 1 FROM public.profiles WHERE phone IN (p1,p2)), NULL);

  RETURN jsonb_build_object(
    'fn','_qa_node5_identity_a14',
    'total', jsonb_array_length(r),
    'failed', (SELECT count(*) FROM jsonb_array_elements(r) e WHERE (e->>'ok')::boolean IS NOT TRUE),
    'failures', (SELECT COALESCE(jsonb_agg(e),'[]'::jsonb) FROM jsonb_array_elements(r) e
                  WHERE (e->>'ok')::boolean IS NOT TRUE)
  );
EXCEPTION WHEN others THEN
  PERFORM set_config('request.jwt.claims', NULL, true);
  BEGIN
    DELETE FROM public.account_deletion_requests WHERE user_id = ANY(ids) OR requested_by = ANY(ids);
    DELETE FROM public.account_recovery_challenges WHERE user_id = ANY(ids);
    DELETE FROM public.account_recovery_profiles WHERE user_id = ANY(ids);
    DELETE FROM public.account_freezes WHERE user_id = ANY(ids);
    DELETE FROM public.audit_logs WHERE actor_user_id = ANY(ids)
       OR target_id IN (SELECT x::text FROM unnest(ids) x);
    DELETE FROM public.user_preferences WHERE user_id = ANY(ids);
    DELETE FROM public.marketplace_listings WHERE seller_id = ANY(ids) OR store_id = s_m;
    DELETE FROM public.merchant_stores WHERE owner_user_id = ANY(ids) OR id = s_m;
    DELETE FROM public.wallets WHERE owner_user_id = ANY(ids);
    DELETE FROM public.driver_locations WHERE user_id = ANY(ids);
    DELETE FROM public.driver_applications WHERE user_id = ANY(ids);
    DELETE FROM public.driver_profiles WHERE user_id = ANY(ids);
    DELETE FROM public.professional_identities WHERE user_id = ANY(ids);
    DELETE FROM public.admin_users WHERE user_id = ANY(ids);
    DELETE FROM public.user_roles WHERE user_id = ANY(ids);
    PERFORM public._qa_a5_cleanup(ids);
  EXCEPTION WHEN others THEN NULL; END;
  RAISE;
END $function$;

REVOKE ALL ON FUNCTION public._qa_node5_identity_a14() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node5_identity_a14() TO service_role;
