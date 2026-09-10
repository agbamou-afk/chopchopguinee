CREATE OR REPLACE FUNCTION public._qa_g6_admin_architecture_lock()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  res jsonb := '[]'::jsonb; n int := 0;
  god uuid := gen_random_uuid(); god2 uuid := gen_random_uuid();
  ops uuid := gen_random_uuid(); fin uuid := gen_random_uuid();
  plain uuid := gen_random_uuid();
  susp_ops uuid := gen_random_uuid(); susp_fin uuid := gen_random_uuid();
  tmp_ops uuid := gen_random_uuid(); tmp_fin uuid := gen_random_uuid();
  legacy uuid := gen_random_uuid();
  a_ops uuid := gen_random_uuid(); a_operations uuid := gen_random_uuid();
  a_super uuid := gen_random_uuid(); a_god uuid := gen_random_uuid();
  c_of uuid := gen_random_uuid(); c_fg uuid := gen_random_uuid();
  c_og uuid := gen_random_uuid(); c_lf uuid := gen_random_uuid(); c_lo uuid := gen_random_uuid();
  roles_only uuid := gen_random_uuid(); admin_only uuid := gen_random_uuid();
  drv_ops uuid := gen_random_uuid(); mer_fin uuid := gen_random_uuid();
  susp_god uuid := gen_random_uuid(); tmp_god uuid := gen_random_uuid();
  ids uuid[]; ok boolean; err text; v jsonb;
  acc_unused uuid; acc_used uuid; acc_succ uuid; ap uuid; ap2 uuid;
  topup uuid := gen_random_uuid();
  grants_before int; grants_after int;
  ledger_before bigint; ledger_after bigint;
  flags_before text; flags_after text;
  policies_before text; policies_after text;
  ops_fp_before text; ops_fp_after text;
  wallets_before text; wallets_after text;
  evt_before text; evt_after text;
  audit_before bigint;
  old_phone text; hist_phone text;
BEGIN
  ids := ARRAY[god,god2,ops,fin,plain,susp_ops,susp_fin,tmp_ops,tmp_fin,legacy,
               a_ops,a_operations,a_super,a_god,c_of,c_fg,c_og,c_lf,c_lo,
               roles_only,admin_only,drv_ops,mer_fin,susp_god,tmp_god];

  SELECT count(*) INTO grants_before FROM public.admin_capability_grants;
  SELECT count(*) INTO ledger_before FROM public.ledger_postings;
  SELECT count(*) INTO audit_before FROM public.audit_logs;
  SELECT md5(coalesce(string_agg(key||coalesce(enabled::text,''),',' ORDER BY key),'')) INTO flags_before FROM public.feature_flags;
  SELECT md5(coalesce(string_agg(id::text||to_jsonb(t)::text,',' ORDER BY id),'')) INTO policies_before FROM public.finance_policies t;
  SELECT md5(coalesce(string_agg(user_id::text||admin_role::text||status::text||must_change_password::text,',' ORDER BY user_id),''))
    INTO ops_fp_before FROM public.admin_users WHERE coalesce(notes,'') NOT LIKE 'qa_g6%';
  SELECT md5(coalesce(string_agg(id::text||balance_gnf||held_gnf||status::text,',' ORDER BY id),''))
    INTO wallets_before FROM public.wallets WHERE owner_user_id <> ALL(ids);
  SELECT md5(coalesce(string_agg(id::text||coalesce(processing_status,''),',' ORDER BY id),'')) INTO evt_before FROM public.payment_provider_events;

  -- ephemeral fixtures ------------------------------------------------------
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
  SELECT u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
         'qa.g6.'||u::text||'@chopchop.test','',now(),now(),now(),'{}'::jsonb,'{}'::jsonb
  FROM unnest(ids) u;
  INSERT INTO public.profiles (user_id, full_name) SELECT u,'QA G6 fixture' FROM unnest(ids) u
    ON CONFLICT (user_id) DO NOTHING;

  INSERT INTO public.admin_users (user_id, admin_role, status, notes, must_change_password) VALUES
    (god,'god_admin','active','qa_g6_fixture',false),
    (god2,'god_admin','active','qa_g6_fixture',false),
    (ops,'ops_admin','active','qa_g6_fixture',false),
    (fin,'finance_admin','active','qa_g6_fixture',false),
    (susp_ops,'ops_admin','suspended','qa_g6_fixture',false),
    (susp_fin,'finance_admin','suspended','qa_g6_fixture',false),
    (susp_god,'god_admin','suspended','qa_g6_fixture',false),
    (tmp_ops,'ops_admin','active','qa_g6_fixture',true),
    (tmp_fin,'finance_admin','active','qa_g6_fixture',true),
    (tmp_god,'god_admin','active','qa_g6_fixture',true),
    (a_ops,'ops_admin','active','qa_g6_fixture',false),
    (a_operations,'operations_admin','active','qa_g6_fixture',false),
    (a_super,'super_admin','active','qa_g6_fixture',false),
    (a_god,'god_admin','active','qa_g6_fixture',false),
    (c_of,'ops_admin','active','qa_g6_fixture',false),
    (c_fg,'finance_admin','active','qa_g6_fixture',false),
    (c_og,'ops_admin','active','qa_g6_fixture',false),
    (c_lf,'finance_admin','active','qa_g6_fixture',false),
    (c_lo,'ops_admin','active','qa_g6_fixture',false),
    (admin_only,'ops_admin','active','qa_g6_fixture',false),
    (drv_ops,'ops_admin','active','qa_g6_fixture',false),
    (mer_fin,'finance_admin','active','qa_g6_fixture',false);

  INSERT INTO public.user_roles (user_id, role) VALUES
    (legacy,'admin'),
    (c_of,'finance_admin'), (c_fg,'god_admin'), (c_og,'god_admin'),
    (c_lf,'admin'), (c_lo,'admin'),
    (roles_only,'operations_admin'),
    (drv_ops,'driver'), (mer_fin,'merchant'), (plain,'client')
  ON CONFLICT DO NOTHING;

  -- ============================ A · ROLE LAW ==============================
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','god alias god_admin resolves to god','pass',
    public.admin_role_canonical(a_god)='god_admin');
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','legacy alias super_admin normalises to god','pass',
    public.admin_role_canonical(a_super)='god_admin');
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','alias ops_admin normalises to operations','pass',
    public.admin_role_canonical(a_ops)='operations_admin');
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','alias operations_admin normalises to operations','pass',
    public.admin_role_canonical(a_operations)='operations_admin');
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','finance resolves to finance','pass',
    public.admin_role_canonical(fin)='finance_admin');
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','bare legacy admin confers no authority','pass',
    public.admin_role_canonical(legacy) IS NULL
    AND public.admin_capability_mode('governance.staff.manage',legacy) IS NULL
    AND public.admin_capability_mode('finance.wallet.read',legacy) IS NULL);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','ordinary customer holds no admin class','pass',
    public.admin_role_canonical(plain) IS NULL);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','conflict ops+finance fails closed','pass',
    public.admin_role_canonical(c_of) IS NULL);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','conflict finance+god fails closed','pass',
    public.admin_role_canonical(c_fg) IS NULL);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','conflict ops+god fails closed','pass',
    public.admin_role_canonical(c_og) IS NULL);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','legacy admin + finance stays finance, never god','pass',
    coalesce(public.admin_role_canonical(c_lf),'x')='finance_admin');
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','legacy admin + ops stays operations, never god','pass',
    coalesce(public.admin_role_canonical(c_lo),'x')='operations_admin');
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','suspended operations has no authority','pass',
    public.admin_role_canonical(susp_ops) IS NULL AND public.admin_capability_mode('ops.orders.manage',susp_ops) IS NULL);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','suspended finance has no authority','pass',
    public.admin_role_canonical(susp_fin) IS NULL AND public.admin_capability_mode('finance.wallet.read',susp_fin) IS NULL);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','suspended god has no authority','pass',
    public.admin_role_canonical(susp_god) IS NULL);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','temp-password operations has zero capability','pass',
    public.admin_staff_readiness(tmp_ops)='temp_password_required'
    AND public.admin_capability_mode('ops.orders.manage',tmp_ops) IS NULL);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','temp-password finance has zero capability','pass',
    public.admin_capability_mode('finance.wallet.read',tmp_fin) IS NULL);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','temp-password god has zero capability','pass',
    public.admin_capability_mode('governance.staff.manage',tmp_god) IS NULL);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','staff-bearing user_roles without admin_users grants nothing','pass',
    public.admin_role_canonical(roles_only) IS NULL);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','admin_users row without user_roles still resolves (canonical source)','pass',
    public.admin_role_canonical(admin_only)='operations_admin');
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','driver lane does not alter governance class','pass',
    public.admin_role_canonical(drv_ops)='operations_admin'
    AND public.admin_capability_mode('finance.wallet.credit',drv_ops) IS NULL);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','merchant lane does not alter governance class','pass',
    public.admin_role_canonical(mer_fin)='finance_admin'
    AND public.admin_capability_mode('ops.orders.manage',mer_fin)='read');
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','professional identity alone confers no staff authority','pass',
    public.admin_role_canonical(plain) IS NULL AND public.admin_capability_mode('ops.drivers.manage',plain) IS NULL);

  -- ===================== B · GRANT / RLS POSTURE ==========================
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','no raw write on admin_users','pass',
    NOT has_table_privilege('authenticated','public.admin_users','INSERT')
    AND NOT has_table_privilege('authenticated','public.admin_users','UPDATE')
    AND NOT has_table_privilege('authenticated','public.admin_users','DELETE'));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','no raw write on user_roles','pass',
    NOT has_table_privilege('authenticated','public.user_roles','INSERT')
    AND NOT has_table_privilege('authenticated','public.user_roles','UPDATE'));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','no raw write on approval_requests','pass',
    NOT has_table_privilege('authenticated','public.approval_requests','INSERT')
    AND NOT has_table_privilege('authenticated','public.approval_requests','UPDATE'));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','no raw write on payment_intents','pass',
    NOT has_table_privilege('authenticated','public.payment_intents','UPDATE')
    AND NOT has_table_privilege('authenticated','public.payment_intents','INSERT'));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','no raw write on topup_requests','pass',
    NOT has_table_privilege('authenticated','public.topup_requests','UPDATE')
    AND NOT has_table_privilege('authenticated','public.topup_requests','DELETE'));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','no raw write on app_settings','pass',
    NOT has_table_privilege('authenticated','public.app_settings','UPDATE'));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','no raw write on refunds / cashouts','pass',
    NOT has_table_privilege('authenticated','public.payment_refund_requests','UPDATE')
    AND NOT has_table_privilege('authenticated','public.driver_cashout_requests','UPDATE'));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','no raw write on payout / settlement policies','pass',
    NOT has_table_privilege('authenticated','public.driver_payout_policies','UPDATE')
    AND NOT has_table_privilege('authenticated','public.merchant_settlement_policies','UPDATE'));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','no raw write on receiving accounts','pass',
    NOT has_table_privilege('authenticated','public.payment_receiving_accounts','INSERT')
    AND NOT has_table_privilege('authenticated','public.payment_receiving_accounts','UPDATE')
    AND NOT has_table_privilege('authenticated','public.payment_receiving_accounts','DELETE'));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','no raw write on wallets or ledger','pass',
    NOT has_table_privilege('authenticated','public.wallets','UPDATE')
    AND NOT has_table_privilege('authenticated','public.wallet_transactions','INSERT')
    AND NOT has_table_privilege('authenticated','public.ledger_postings','INSERT')
    AND NOT has_table_privilege('authenticated','public.ledger_journals','INSERT'));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','no raw write on payouts / settlements / payables','pass',
    NOT has_table_privilege('authenticated','public.payout_orders','UPDATE')
    AND NOT has_table_privilege('authenticated','public.merchant_settlement_requests','UPDATE')
    AND NOT has_table_privilege('authenticated','public.merchant_payables','UPDATE'));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','no raw write on provider events','pass',
    NOT has_table_privilege('authenticated','public.payment_provider_events','UPDATE'));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','no raw write on dormant liabilities','pass',
    NOT has_table_privilege('authenticated','public.dormant_closed_account_liabilities','UPDATE')
    AND NOT has_table_privilege('authenticated','public.dormant_closed_account_liabilities','DELETE'));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','no raw write on finance policies','pass',
    NOT has_table_privilege('authenticated','public.finance_policies','UPDATE'));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','no raw write on feature flags','pass',
    NOT has_table_privilege('authenticated','public.feature_flags','UPDATE')
    AND NOT has_table_privilege('authenticated','public.feature_flags','INSERT'));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','no raw write on audit logs','pass',
    NOT has_table_privilege('authenticated','public.audit_logs','UPDATE')
    AND NOT has_table_privilege('authenticated','public.audit_logs','INSERT')
    AND NOT has_table_privilege('authenticated','public.audit_logs','DELETE'));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','staff lifecycle table unreachable from a browser','pass',
    NOT has_table_privilege('authenticated','public.staff_lifecycle_requests','SELECT')
    AND NOT has_table_privilege('authenticated','public.staff_lifecycle_requests','INSERT'));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','anon holds no DML on finance tables','pass',
    NOT has_table_privilege('anon','public.payment_receiving_accounts','INSERT')
    AND NOT has_table_privilege('anon','public.payment_intents','UPDATE')
    AND NOT has_table_privilege('anon','public.topup_requests','INSERT')
    AND NOT has_table_privilege('anon','public.app_settings','UPDATE')
    AND NOT has_table_privilege('anon','public.driver_cashout_requests','INSERT')
    AND NOT has_table_privilege('anon','public.payment_refund_requests','INSERT'));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','anon can execute no admin_* function','pass',
    NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
                WHERE ns.nspname='public' AND p.proname LIKE 'admin\_%'
                  AND has_function_privilege('anon',p.oid,'EXECUTE')));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','G2/G3 internals unreachable by humans','pass',
    NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
                WHERE ns.nspname='public' AND p.proname LIKE '\_g2i\_%'
                  AND (has_function_privilege('anon',p.oid,'EXECUTE')
                    OR has_function_privilege('authenticated',p.oid,'EXECUTE'))));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','no write policy survives on governance tables','pass',
    NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                AND tablename IN ('admin_users','user_roles','approval_requests')
                AND cmd <> 'SELECT'));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','receiving accounts expose a read-only policy only','pass',
    NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                AND tablename='payment_receiving_accounts' AND cmd <> 'SELECT'));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','capability registry is not writable outside god','pass',
    NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                AND tablename='admin_capability_grants' AND cmd <> 'SELECT'
                AND qual NOT ILIKE '%god_admin%'));

  -- =============== C · RECEIVING ACCOUNT SEAM (PHASE H) ===================
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','operations holds no receiving-account capability','pass',
    public.admin_capability_mode('finance.receiving_account.manage',ops) IS NULL
    AND public.admin_capability_mode('finance.receiving_account.route',ops) IS NULL);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','finance may manage, routing is approval-bound','pass',
    public.admin_capability_mode('finance.receiving_account.manage',fin)='allow'
    AND public.admin_capability_mode('finance.receiving_account.route',fin)='approval_required');
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','god routing is approval-bound too (no bypass)','pass',
    public.admin_capability_mode('finance.receiving_account.route',god)='approval_required');
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','anon cannot execute receiving-account actions','pass',
    NOT has_function_privilege('anon','public.admin_receiving_account_create(text,text,text,text,text,uuid)','EXECUTE')
    AND NOT has_function_privilege('anon','public.admin_receiving_account_replace_routing(uuid,text,text,uuid)','EXECUTE'));

  PERFORM set_config('request.jwt.claims', public._as_user_claims(ops), true);
  ok:=false; BEGIN PERFORM public.admin_receiving_account_create('orange_money','qa','+224600000001',NULL,NULL,NULL);
    EXCEPTION WHEN OTHERS THEN ok:=true; err:=SQLERRM; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','operations cannot create a receiving account','pass',
    ok AND err ILIKE '%capability_denied%');
  ok:=false; BEGIN PERFORM public.admin_receiving_account_replace_routing(gen_random_uuid(),'+224600000002','qa',NULL);
    EXCEPTION WHEN OTHERS THEN ok:=true; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','operations cannot change payment routing','pass', ok);

  PERFORM set_config('request.jwt.claims', public._as_user_claims(plain), true);
  ok:=false; BEGIN PERFORM public.admin_receiving_account_create('orange_money','qa','+224600000003',NULL,NULL,NULL);
    EXCEPTION WHEN OTHERS THEN ok:=true; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','a customer cannot create a receiving account','pass', ok);

  PERFORM set_config('request.jwt.claims', public._as_user_claims(susp_fin), true);
  ok:=false; BEGIN PERFORM public.admin_receiving_account_create('orange_money','qa','+224600000004',NULL,NULL,NULL);
    EXCEPTION WHEN OTHERS THEN ok:=true; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','suspended finance cannot create a receiving account','pass', ok);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(tmp_fin), true);
  ok:=false; BEGIN PERFORM public.admin_receiving_account_create('orange_money','qa','+224600000005',NULL,NULL,NULL);
    EXCEPTION WHEN OTHERS THEN ok:=true; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','temp-password finance cannot create a receiving account','pass', ok);

  PERFORM set_config('request.jwt.claims', public._as_user_claims(fin), true);
  ok:=false; BEGIN PERFORM public.admin_receiving_account_create('orange_money','qa','12345',NULL,NULL,NULL);
    EXCEPTION WHEN OTHERS THEN ok:=true; err:=SQLERRM; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','a malformed routing number is refused','pass',
    ok AND err ILIKE '%invalid_receiving_phone%');
  ok:=false; BEGIN PERFORM public.admin_receiving_account_create('orange_money','  ','+224600000006',NULL,NULL,NULL);
    EXCEPTION WHEN OTHERS THEN ok:=true; err:=SQLERRM; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','a blank label is refused','pass', ok AND err ILIKE '%label_required%');

  acc_unused := public.admin_receiving_account_create('orange_money','QA G6 unused','+224600000007','qa','qa_g6_fixture',NULL);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','finance creates an account, always inactive','pass',
    EXISTS (SELECT 1 FROM public.payment_receiving_accounts WHERE id=acc_unused AND is_active=false AND version=1));
  ok:=false; BEGIN PERFORM public.admin_receiving_account_set_active(acc_unused,true,'   ');
    EXCEPTION WHEN OTHERS THEN ok:=true; err:=SQLERRM; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','activation without a reason is refused','pass',
    ok AND err ILIKE '%reason_required%');
  PERFORM public.admin_receiving_account_set_active(acc_unused,true,'qa g6 activation');
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','activation is an explicit, motivated act','pass',
    (SELECT is_active FROM public.payment_receiving_accounts WHERE id=acc_unused));
  PERFORM public.admin_receiving_account_update_metadata(acc_unused,'QA G6 renamed','qa','qa_g6_fixture',NULL);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','metadata edit never touches routing or activation','pass',
    (SELECT label='QA G6 renamed' AND phone_e164='+224600000007' AND is_active
       FROM public.payment_receiving_accounts WHERE id=acc_unused));
  ok:=false; BEGIN PERFORM public.admin_receiving_account_replace_routing(acc_unused,'+224600000008','qa g6',NULL);
    EXCEPTION WHEN OTHERS THEN ok:=true; err:=SQLERRM; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','routing change without approval is refused','pass',
    ok AND (err ILIKE '%approval%'));
  ok:=false; BEGIN PERFORM public.admin_receiving_account_replace_routing(acc_unused,'+224600000007','qa g6',NULL);
    EXCEPTION WHEN OTHERS THEN ok:=true; err:=SQLERRM; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','a no-op routing change is refused','pass', ok);

  -- account already bound to financial history
  acc_used := public.admin_receiving_account_create('orange_money','QA G6 used','+224600000010','qa','qa_g6_fixture',NULL);
  SELECT phone_e164 INTO old_phone FROM public.payment_receiving_accounts WHERE id=acc_used;
  PERFORM set_config('request.jwt.claims','',true);
  INSERT INTO public.topup_requests (id, reference, client_user_id, amount_gnf, confirmation_code,
                                     provider, environment, receiving_account_id, status)
  VALUES (topup,'QAG6-'||substr(topup::text,1,8), plain, 1000, 'QAG6CODE','orange_money','sandbox',acc_used,'pending');

  PERFORM set_config('request.jwt.claims', public._as_user_claims(fin), true);
  ap := public.admin_request_approval('finance.receiving_account.route','payment_receiving_account',acc_used::text,
        jsonb_build_object('phone_e164','+224600000011'),'payments',60);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','finance can request a routing approval','pass', ap IS NOT NULL);
  ok:=false; BEGIN PERFORM public.admin_review_approval(ap,'approved','self'); EXCEPTION WHEN OTHERS THEN ok:=true; err:=SQLERRM; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','the requester cannot approve their own routing change','pass', ok);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(ops), true);
  ok:=false; BEGIN PERFORM public.admin_review_approval(ap,'approved','ops'); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','operations cannot approve a finance routing change','pass', ok);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(susp_god), true);
  ok:=false; BEGIN PERFORM public.admin_review_approval(ap,'approved','susp'); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','a suspended god cannot approve','pass', ok);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(tmp_god), true);
  ok:=false; BEGIN PERFORM public.admin_review_approval(ap,'approved','tmp'); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','a temp-password god cannot approve','pass', ok);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(god), true);
  PERFORM public.admin_review_approval(ap,'approved','qa g6');
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','a second god can approve the exact intent','pass',
    EXISTS (SELECT 1 FROM public.approval_requests WHERE id=ap AND status='approved'));

  PERFORM set_config('request.jwt.claims', public._as_user_claims(fin), true);
  ok:=false; BEGIN PERFORM public.admin_receiving_account_replace_routing(acc_used,'+224600000099','qa g6',ap);
    EXCEPTION WHEN OTHERS THEN ok:=true; err:=SQLERRM; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','an approval does not cover a different number','pass', ok);
  ok:=false; BEGIN PERFORM public.admin_receiving_account_replace_routing(acc_unused,'+224600000011','qa g6',ap);
    EXCEPTION WHEN OTHERS THEN ok:=true; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','an approval does not cover a different account','pass', ok);

  acc_succ := public.admin_receiving_account_replace_routing(acc_used,'+224600000011','qa g6 routing',ap);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','an exact approval executes the routing change once','pass',
    acc_succ IS NOT NULL AND acc_succ <> acc_used);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','a used account is superseded, never overwritten','pass',
    (SELECT phone_e164=old_phone AND retired_at IS NOT NULL AND superseded_by=acc_succ AND is_active=false
       FROM public.payment_receiving_accounts WHERE id=acc_used));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','the successor row carries the new routing and version','pass',
    (SELECT phone_e164='+224600000011' AND version=2 FROM public.payment_receiving_accounts WHERE id=acc_succ));
  SELECT r.phone_e164 INTO hist_phone FROM public.topup_requests t
    JOIN public.payment_receiving_accounts r ON r.id=t.receiving_account_id WHERE t.id=topup;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','financial history keeps its original routing meaning','pass',
    hist_phone = old_phone);
  ok:=false; BEGIN PERFORM public.admin_receiving_account_replace_routing(acc_used,'+224600000011','replay',ap);
    EXCEPTION WHEN OTHERS THEN ok:=true; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','a consumed routing approval cannot be replayed','pass', ok);
  ok:=false; BEGIN PERFORM public.admin_receiving_account_set_active(acc_used,true,'reactivate retired');
    EXCEPTION WHEN OTHERS THEN ok:=true; err:=SQLERRM; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','a retired account cannot be reactivated','pass',
    ok AND err ILIKE '%retired%');
  ok:=false; BEGIN UPDATE public.payment_receiving_accounts SET phone_e164='+224600000777' WHERE id=acc_succ;
    EXCEPTION WHEN OTHERS THEN ok:=true; err:=SQLERRM; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','a direct table write from a session is refused','pass',
    ok AND err ILIKE '%governed_rpc_required%');
  ok:=false; BEGIN DELETE FROM public.payment_receiving_accounts WHERE id=acc_succ;
    EXCEPTION WHEN OTHERS THEN ok:=true; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','a direct delete from a session is refused','pass', ok);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','routing changes leave complete audit provenance','pass',
    EXISTS (SELECT 1 FROM public.audit_logs WHERE action='receiving_account.route'
              AND target_id=acc_used::text AND actor_user_id=fin));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','receiving-account audit carries no credential','pass',
    NOT EXISTS (SELECT 1 FROM public.audit_logs WHERE action LIKE 'receiving_account.%'
                AND (to_jsonb(audit_logs)::text ILIKE '%password%' OR to_jsonb(audit_logs)::text ILIKE '%secret%'
                  OR to_jsonb(audit_logs)::text ILIKE '%api_key%')));

  -- =================== D · APPROVAL LAW (generic) =========================
  PERFORM set_config('request.jwt.claims', public._as_user_claims(fin), true);
  ap2 := public.admin_request_approval('finance.wallet.credit','wallet',plain::text,
         jsonb_build_object('amount_gnf',1000),'wallet',60);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','an approval binds requester, capability and target','pass',
    EXISTS (SELECT 1 FROM public.approval_requests WHERE id=ap2 AND requested_by=fin
              AND capability='finance.wallet.credit' AND target_id=plain::text AND status='pending'));
  PERFORM set_config('request.jwt.claims', public._as_user_claims(fin), true);
  ok:=false; BEGIN PERFORM public.admin_review_approval(ap2,'approved','self'); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','self-approval is refused on money','pass', ok);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(plain), true);
  ok:=false; BEGIN PERFORM public.admin_review_approval(ap2,'approved','customer'); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','a customer cannot approve','pass', ok);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(legacy), true);
  ok:=false; BEGIN PERFORM public.admin_review_approval(ap2,'approved','legacy'); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','a legacy admin cannot approve','pass', ok);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(god), true);
  PERFORM public.admin_review_approval(ap2,'rejected','qa g6');
  PERFORM set_config('request.jwt.claims', public._as_user_claims(fin), true);
  ok:=false; BEGIN PERFORM public.admin_credit_wallet(plain,1000,'qa g6',ap2); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','a rejected approval never executes','pass', ok);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(god), true);
  ok:=false; BEGIN PERFORM public.admin_review_approval(ap2,'approved','flip'); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','a decided approval cannot be flipped','pass', ok);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','approvals carry an intent hash, expiry and single use','pass',
    EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='approval_requests' AND column_name='intent_hash')
    AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='approval_requests' AND column_name='expires_at')
    AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='approval_requests' AND column_name='consumed_at'));

  -- =============== E · OPS ATTACKS FINANCE / FINANCE ATTACKS OPS ==========
  PERFORM set_config('request.jwt.claims', public._as_user_claims(ops), true);
  ok:=false; BEGIN PERFORM public.admin_credit_wallet(plain,1000,'qa g6',NULL); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','operations cannot credit a wallet','pass', ok);
  ok:=false; BEGIN PERFORM public.admin_reject_om_event(gen_random_uuid(),'qa'); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','operations cannot touch a provider event','pass', ok);
  ok:=false; BEGIN PERFORM public.finance_command_overview(); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','operations cannot open the finance command centre','pass', ok);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','operations holds no monetary capability at all','pass',
    public.admin_capability_mode('finance.wallet.credit',ops) IS NULL
    AND public.admin_capability_mode('finance.wallet.adjust',ops) IS NULL
    AND public.admin_capability_mode('finance.refund.approve',ops) IS NULL
    AND public.admin_capability_mode('finance.payout.confirm',ops) IS NULL
    AND public.admin_capability_mode('finance.treasury.move',ops) IS NULL
    AND public.admin_capability_mode('finance.policy.change',ops) IS NULL
    AND public.admin_capability_mode('finance.flags.payment',ops) IS NULL);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','operations may read financial facts, never act','pass',
    public.admin_capability_mode('finance.wallet.read',ops)='read'
    AND NOT coalesce(public.admin_capability('finance.wallet.read',ops),false));

  PERFORM set_config('request.jwt.claims', public._as_user_claims(fin), true);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','finance holds no operational mutation capability','pass',
    coalesce(public.admin_capability_mode('ops.drivers.manage',fin),'read')='read'
    AND coalesce(public.admin_capability_mode('ops.orders.manage',fin),'read')='read'
    AND public.admin_capability_mode('ops.maps.manage',fin) IS NULL
    AND public.admin_capability_mode('ops.liveops.view',fin) IS NULL);
  ok:=false; BEGIN PERFORM public.ops_command_overview(); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','finance cannot open the operations command centre','pass', ok);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','neither class holds governance capability','pass',
    public.admin_capability_mode('governance.staff.manage',fin) IS NULL
    AND public.admin_capability_mode('governance.staff.manage',ops) IS NULL
    AND public.admin_capability_mode('governance.flags.manage',fin) IS NULL
    AND public.admin_capability_mode('governance.flags.manage',ops) IS NULL
    AND public.admin_capability_mode('governance.settings.manage',fin) IS NULL
    AND public.admin_capability_mode('governance.settings.manage',ops) IS NULL);

  -- ==================== F · GOVERNANCE / STAFF ============================
  PERFORM set_config('request.jwt.claims', public._as_user_claims(ops), true);
  ok:=false; BEGIN PERFORM public.admin_staff_role_grant(plain,'finance_admin','qa',NULL); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','operations cannot grant a staff role','pass', ok);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(fin), true);
  ok:=false; BEGIN PERFORM public.admin_staff_role_grant(plain,'finance_admin','qa',NULL); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','finance cannot grant a staff role','pass', ok);
  ok:=false; BEGIN INSERT INTO public.admin_capability_grants (capability,admin_role,mode)
      VALUES ('qa.g6.escalation','finance_admin','allow'); EXCEPTION WHEN OTHERS THEN ok:=true; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','a browser session cannot write the capability registry','pass',
    ok AND NOT EXISTS (SELECT 1 FROM public.admin_capability_grants WHERE capability='qa.g6.escalation'));
  PERFORM set_config('request.jwt.claims', public._as_user_claims(ops), true);
  ok:=false; BEGIN INSERT INTO public.admin_users (user_id,admin_role,status) VALUES (plain,'god_admin','active');
    EXCEPTION WHEN OTHERS THEN ok:=true; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','operations cannot self-provision a god account','pass',
    ok AND NOT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id=plain));
  ok:=false; BEGIN INSERT INTO public.user_roles (user_id,role) VALUES (ops,'god_admin');
    EXCEPTION WHEN OTHERS THEN ok:=true; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','operations cannot grant itself a god role row','pass',
    ok AND public.admin_role_canonical(ops)='operations_admin');
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','staff governance stays god-only','pass',
    public.admin_capability_mode('governance.staff.manage',god)='approval_required');

  -- ==================== G · AUDIT / PROVENANCE ============================
  PERFORM set_config('request.jwt.claims', public._as_user_claims(ops), true);
  ok:=false; BEGIN UPDATE public.audit_logs SET action='tampered' WHERE id IN (SELECT id FROM public.audit_logs LIMIT 1);
    EXCEPTION WHEN OTHERS THEN ok:=true; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','operations cannot rewrite the audit trail','pass', ok);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(fin), true);
  ok:=false; BEGIN DELETE FROM public.audit_logs WHERE id IN (SELECT id FROM public.audit_logs LIMIT 1);
    EXCEPTION WHEN OTHERS THEN ok:=true; END;
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','finance cannot delete audit evidence','pass', ok);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','denied attempts fabricate no success record','pass',
    NOT EXISTS (SELECT 1 FROM public.audit_logs WHERE actor_user_id=ops
                  AND action LIKE 'receiving_account.%'));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','successful governed mutations record a canonical actor','pass',
    EXISTS (SELECT 1 FROM public.audit_logs WHERE action='receiving_account.create'
              AND actor_user_id=fin AND target_id=acc_used::text));

  -- ==================== H · FINANCIAL INVARIANTS ==========================
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','dormant liabilities carry an immutability guard','pass',
    EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
            WHERE c.relname='dormant_closed_account_liabilities' AND NOT t.tgisinternal));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','no human role can write a ledger posting','pass',
    NOT has_table_privilege('authenticated','public.ledger_postings','INSERT')
    AND NOT has_table_privilege('authenticated','public.ledger_postings','UPDATE')
    AND NOT has_table_privilege('anon','public.ledger_postings','INSERT'));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','wallet balances are never directly writable','pass',
    NOT has_table_privilege('authenticated','public.wallets','UPDATE')
    AND NOT has_table_privilege('anon','public.wallets','UPDATE'));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','every money capability stays approval-bound for finance','pass',
    (SELECT count(*) FROM public.admin_capability_grants
      WHERE admin_role='finance_admin' AND mode='allow'
        AND capability IN ('finance.wallet.credit','finance.wallet.adjust','finance.treasury.move',
                           'finance.payout.confirm','finance.refund.approve','finance.policy.change',
                           'finance.dispute.resolve','finance.flags.payment',
                           'finance.receiving_account.route')) = 0);

  -- ==================== I · NODE 5 IDENTITY SEPARATION ====================
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','governance never writes the professional lane','pass',
    NOT EXISTS (SELECT 1 FROM public.driver_profiles WHERE user_id = ANY(ids))
    AND NOT EXISTS (SELECT 1 FROM public.merchant_stores WHERE owner_user_id = ANY(ids)));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','a customer account is intrinsic and unaffected by staff status','pass',
    EXISTS (SELECT 1 FROM public.profiles WHERE user_id=ops));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','staff authority derives from admin_users, never from a lane','pass',
    public.admin_role_canonical(drv_ops)='operations_admin' AND public.admin_role_canonical(plain) IS NULL);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','active-account law gates every canonical resolution','pass',
    public.admin_role_canonical(susp_ops) IS NULL AND public.admin_role_canonical(susp_fin) IS NULL);

  -- ==================== J · DRIFT / RESIDUE ===============================
  PERFORM set_config('request.jwt.claims','',true);
  DELETE FROM public.topup_requests WHERE id=topup;
  UPDATE public.payment_receiving_accounts SET superseded_by=NULL WHERE id=acc_used;
  DELETE FROM public.payment_receiving_accounts WHERE id IN (acc_unused,acc_used,acc_succ);
  DELETE FROM public.approval_requests WHERE requested_by = ANY(ids) OR reviewed_by = ANY(ids);
  DELETE FROM public.audit_logs WHERE actor_user_id = ANY(ids);
  DELETE FROM public.admin_users WHERE user_id = ANY(ids);
  DELETE FROM public.user_roles WHERE user_id = ANY(ids);
  DELETE FROM public.wallets WHERE owner_user_id = ANY(ids);
  DELETE FROM public.profiles WHERE user_id = ANY(ids);
  DELETE FROM auth.users WHERE id = ANY(ids);

  SELECT count(*) INTO grants_after FROM public.admin_capability_grants;
  SELECT count(*) INTO ledger_after FROM public.ledger_postings;
  SELECT md5(coalesce(string_agg(key||coalesce(enabled::text,''),',' ORDER BY key),'')) INTO flags_after FROM public.feature_flags;
  SELECT md5(coalesce(string_agg(id::text||to_jsonb(t)::text,',' ORDER BY id),'')) INTO policies_after FROM public.finance_policies t;
  SELECT md5(coalesce(string_agg(user_id::text||admin_role::text||status::text||must_change_password::text,',' ORDER BY user_id),''))
    INTO ops_fp_after FROM public.admin_users WHERE coalesce(notes,'') NOT LIKE 'qa_g6%';
  SELECT md5(coalesce(string_agg(id::text||balance_gnf||held_gnf||status::text,',' ORDER BY id),''))
    INTO wallets_after FROM public.wallets;
  SELECT md5(coalesce(string_agg(id::text||coalesce(processing_status,''),',' ORDER BY id),'')) INTO evt_after FROM public.payment_provider_events;

  n:=n+1; res:=res||jsonb_build_object('id',n,'name','capability registry unchanged by the attack run','pass', grants_before=grants_after);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','ledger unchanged','pass', ledger_before=ledger_after);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','feature flags unchanged','pass', flags_before=flags_after);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','finance policies and economics unchanged','pass', policies_before=policies_after);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','real staff accounts fingerprint unchanged','pass', ops_fp_before=ops_fp_after);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','wallet balances unchanged','pass', wallets_before=wallets_after);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','provider events unchanged','pass', evt_before=evt_after);
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','zero fixture auth users remain','pass',
    NOT EXISTS (SELECT 1 FROM auth.users WHERE id = ANY(ids)));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','zero fixture staff rows remain','pass',
    NOT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = ANY(ids))
    AND NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = ANY(ids)));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','zero fixture approvals remain','pass',
    NOT EXISTS (SELECT 1 FROM public.approval_requests WHERE requested_by = ANY(ids)));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','zero fixture receiving accounts remain','pass',
    NOT EXISTS (SELECT 1 FROM public.payment_receiving_accounts WHERE admin_notes='qa_g6_fixture'));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','zero fixture top-ups remain','pass',
    NOT EXISTS (SELECT 1 FROM public.topup_requests WHERE id=topup));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','zero fixture lifecycle rows remain','pass',
    NOT EXISTS (SELECT 1 FROM public.staff_lifecycle_requests WHERE target_user_id = ANY(ids)));
  n:=n+1; res:=res||jsonb_build_object('id',n,'name','audit trail returns to its pre-run size','pass',
    (SELECT count(*) FROM public.audit_logs) = audit_before);

  RETURN jsonb_build_object(
    'total', jsonb_array_length(res),
    'passed', (SELECT count(*) FROM jsonb_array_elements(res) x WHERE (x->>'pass')::boolean),
    'failures', (SELECT coalesce(jsonb_agg(x),'[]'::jsonb) FROM jsonb_array_elements(res) x WHERE NOT (x->>'pass')::boolean),
    'results', res);
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims','',true);
  DELETE FROM public.topup_requests WHERE id=topup;
  UPDATE public.payment_receiving_accounts SET superseded_by=NULL WHERE admin_notes='qa_g6_fixture';
  DELETE FROM public.payment_receiving_accounts WHERE admin_notes='qa_g6_fixture';
  DELETE FROM public.approval_requests WHERE requested_by = ANY(ids) OR reviewed_by = ANY(ids);
  DELETE FROM public.audit_logs WHERE actor_user_id = ANY(ids);
  DELETE FROM public.admin_users WHERE user_id = ANY(ids);
  DELETE FROM public.user_roles WHERE user_id = ANY(ids);
  DELETE FROM public.wallets WHERE owner_user_id = ANY(ids);
  DELETE FROM public.profiles WHERE user_id = ANY(ids);
  DELETE FROM auth.users WHERE id = ANY(ids);
  RAISE;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public._qa_g6_admin_architecture_lock() FROM PUBLIC, anon, authenticated;