CREATE OR REPLACE FUNCTION public._qa_g4_operations_command_center()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  res jsonb := '[]'::jsonb;
  god uuid := gen_random_uuid(); ops uuid := gen_random_uuid();
  fin uuid := gen_random_uuid(); plain uuid := gen_random_uuid();
  susp uuid := gen_random_uuid(); tmp uuid := gen_random_uuid();
  ids uuid[]; ok boolean; err text; v jsonb; n int;
  flags_before text; flags_after text; grants_before int; grants_after int;
  ledger_before bigint; ledger_after bigint;
BEGIN
  ids := ARRAY[god, ops, fin, plain, susp, tmp];
  SELECT md5(string_agg(key || '=' || enabled::text, ',' ORDER BY key)) INTO flags_before FROM public.feature_flags;
  SELECT count(*) INTO grants_before FROM public.admin_capability_grants;
  SELECT count(*) INTO ledger_before FROM public.ledger_postings;

  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data)
  SELECT u, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         'qa.g4.'||u::text||'@chopchop.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb
  FROM unnest(ids) u;
  INSERT INTO public.profiles (user_id, full_name)
  SELECT u, 'QA G4 fixture' FROM unnest(ids) u ON CONFLICT (user_id) DO NOTHING;
  INSERT INTO public.admin_users (user_id, admin_role, status, notes, must_change_password) VALUES
    (god ,'god_admin'     ,'active'   ,'qa_g4_fixture', false),
    (ops ,'ops_admin'     ,'active'   ,'qa_g4_fixture', false),
    (fin ,'finance_admin' ,'active'   ,'qa_g4_fixture', false),
    (susp,'ops_admin'     ,'suspended','qa_g4_fixture', false),
    (tmp ,'ops_admin'     ,'active'   ,'qa_g4_fixture', true);

  -- 1 · capability posture -------------------------------------------------
  res := res || jsonb_build_object('id',1,'name','ops holds ops.liveops.view (ALLOW)','pass',
    public.admin_capability_mode('ops.liveops.view', ops) = 'allow');
  res := res || jsonb_build_object('id',2,'name','finance sees liveops READ only','pass',
    public.admin_capability_mode('ops.liveops.view', fin) = 'read'
    AND NOT coalesce(public.admin_capability('ops.liveops.view', fin), false));
  res := res || jsonb_build_object('id',3,'name','customer holds no operational capability','pass',
    public.admin_capability_mode('ops.liveops.view', plain) IS NULL
    AND public.admin_role_canonical(plain) IS NULL);
  res := res || jsonb_build_object('id',4,'name','suspended ops staff has no authority','pass',
    public.admin_role_canonical(susp) IS NULL
    AND public.admin_capability_mode('ops.liveops.view', susp) IS NULL);
  res := res || jsonb_build_object('id',5,'name','temp-password ops staff has zero effective capability','pass',
    public.admin_staff_readiness(tmp) = 'temp_password_required'
    AND public.admin_capability_mode('ops.liveops.view', tmp) IS NULL
    AND public.admin_capability_mode('ops.drivers.manage', tmp) IS NULL);

  -- 2 · the read model ------------------------------------------------------
  PERFORM set_config('request.jwt.claims', public._as_user_claims(ops), true);
  v := public.ops_command_overview();
  res := res || jsonb_build_object('id',6,'name','ops reads the command-center model','pass',
    v ? 'snapshot' AND v ? 'attention' AND (v->>'role') = 'operations_admin');
  res := res || jsonb_build_object('id',7,'name','snapshot carries canonical operational counts','pass',
    (v->'snapshot') ? 'rides_active' AND (v->'snapshot') ? 'missions_active'
    AND (v->'snapshot') ? 'repas_active' AND (v->'snapshot') ? 'marche_active'
    AND (v->'snapshot') ? 'envoyer_active' AND (v->'snapshot') ? 'support_open'
    AND jsonb_typeof(v->'attention') = 'array');
  res := res || jsonb_build_object('id',8,'name','read model exposes no PII columns','pass',
    NOT (v::text ILIKE '%sender_phone%' OR v::text ILIKE '%recipient_phone%' OR v::text ILIKE '%full_name%'));

  PERFORM set_config('request.jwt.claims', public._as_user_claims(god), true);
  ok := false; BEGIN v := public.ops_command_overview(); ok := v ? 'snapshot'; EXCEPTION WHEN OTHERS THEN ok := false; END;
  res := res || jsonb_build_object('id',9,'name','god keeps command-center access','pass', ok);

  PERFORM set_config('request.jwt.claims', public._as_user_claims(plain), true);
  ok := false; err := NULL;
  BEGIN PERFORM public.ops_command_overview();
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; ok := SQLERRM ILIKE '%capability_denied%'; END;
  res := res || jsonb_build_object('id',10,'name','customer denied the command center','pass', ok, 'err', err);

  PERFORM set_config('request.jwt.claims', public._as_user_claims(susp), true);
  ok := false; BEGIN PERFORM public.ops_command_overview();
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%capability_denied%'; END;
  res := res || jsonb_build_object('id',11,'name','suspended ops denied the command center','pass', ok);

  PERFORM set_config('request.jwt.claims', public._as_user_claims(tmp), true);
  ok := false; BEGIN PERFORM public.ops_command_overview();
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%capability_denied%'; END;
  res := res || jsonb_build_object('id',12,'name','not-ready ops staff denied the command center','pass', ok);

  PERFORM set_config('request.jwt.claims', '', true);
  ok := false; BEGIN PERFORM public.ops_command_overview();
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%capability_denied%'; END;
  res := res || jsonb_build_object('id',13,'name','signed-out caller denied the command center','pass', ok);
  SELECT count(*) INTO n FROM information_schema.role_routine_grants
   WHERE routine_schema='public' AND routine_name='ops_command_overview' AND grantee IN ('anon','PUBLIC');
  res := res || jsonb_build_object('id',14,'name','no anon EXECUTE on the read model','pass', n = 0, 'grants', n);

  -- 3 · lawful operational authority ----------------------------------------
  PERFORM set_config('request.jwt.claims', public._as_user_claims(ops), true);
  ok := false; err := NULL;
  BEGIN PERFORM public.admin_enforce('ops.drivers.manage','driver', ops::text, '{}'::jsonb); ok := true;
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  res := res || jsonb_build_object('id',15,'name','ops may act on drivers','pass', ok, 'err', err);
  ok := false; err := NULL;
  BEGIN PERFORM public.admin_enforce('ops.merchants.manage','store', ops::text, '{}'::jsonb); ok := true;
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  res := res || jsonb_build_object('id',16,'name','ops may act on merchants','pass', ok, 'err', err);
  ok := false; err := NULL;
  BEGIN PERFORM public.admin_enforce('ops.orders.manage','order', ops::text, '{}'::jsonb); ok := true;
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  res := res || jsonb_build_object('id',17,'name','ops may intervene on orders/missions','pass', ok, 'err', err);
  ok := false; err := NULL;
  BEGIN PERFORM public.admin_enforce('ops.maps.manage','place', ops::text, '{}'::jsonb); ok := true;
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  res := res || jsonb_build_object('id',18,'name','ops may correct maps/places','pass', ok, 'err', err);

  -- 4 · finance separation ---------------------------------------------------
  res := res || jsonb_build_object('id',19,'name','ops reads finance facts, never mutates','pass',
    public.admin_capability_mode('finance.wallet.read', ops) = 'read'
    AND NOT coalesce(public.admin_capability('finance.wallet.read', ops), false)
    AND public.admin_capability_mode('finance.wallet.credit', ops) IS NULL
    AND public.admin_capability_mode('finance.wallet.adjust', ops) IS NULL);

  ok := false; err := NULL;
  BEGIN PERFORM public.admin_enforce('finance.wallet.credit','wallet', ops::text, jsonb_build_object('amount_gnf',1000));
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; ok := SQLERRM ILIKE '%denied%'; END;
  res := res || jsonb_build_object('id',20,'name','ops cannot credit a wallet','pass', ok, 'err', err);
  ok := false; BEGIN PERFORM public.admin_enforce('finance.wallet.adjust','wallet', ops::text, jsonb_build_object('amount_gnf',-1000));
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%denied%'; END;
  res := res || jsonb_build_object('id',21,'name','ops cannot debit / adjust a wallet','pass', ok);
  ok := false; BEGIN PERFORM public.admin_enforce('finance.payout.confirm','payout', ops::text, '{}'::jsonb);
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%denied%'; END;
  res := res || jsonb_build_object('id',22,'name','ops cannot execute a payout','pass', ok);
  ok := false; BEGIN PERFORM public.admin_enforce('finance.reconciliation.approve','recon', ops::text, '{}'::jsonb);
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%denied%'; END;
  res := res || jsonb_build_object('id',23,'name','ops cannot approve reconciliation','pass', ok);
  ok := false; BEGIN PERFORM public.admin_enforce('finance.policy.change','policy', ops::text, '{}'::jsonb);
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%denied%'; END;
  res := res || jsonb_build_object('id',24,'name','ops cannot change finance policy','pass', ok);
  ok := false; BEGIN PERFORM public.admin_enforce('finance.flags.payment','flag','payments_enabled', '{}'::jsonb);
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%denied%'; END;
  res := res || jsonb_build_object('id',25,'name','ops cannot activate a payment rail','pass', ok);
  ok := false; BEGIN PERFORM public.admin_enforce('finance.treasury.move','treasury', ops::text, '{}'::jsonb);
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%denied%'; END;
  res := res || jsonb_build_object('id',26,'name','ops cannot move treasury','pass', ok);

  -- representative real finance RPCs, called directly (UI bypass attempt)
  ok := false; err := NULL;
  BEGIN PERFORM public.admin_manual_om_credit(gen_random_uuid(), gen_random_uuid());
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; ok := SQLERRM ILIKE '%denied%'; END;
  res := res || jsonb_build_object('id',27,'name','direct admin_manual_om_credit denied for ops','pass', ok, 'err', err);
  ok := false; BEGIN PERFORM public.admin_adjust_agent_float(plain, 5000, 'qa g4');
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%denied%'; END;
  res := res || jsonb_build_object('id',28,'name','direct admin_adjust_agent_float denied for ops','pass', ok);
  ok := false; BEGIN PERFORM public.admin_set_finance_policy('ride', 100);
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%denied%'; END;
  res := res || jsonb_build_object('id',29,'name','direct admin_set_finance_policy denied for ops','pass', ok);
  ok := false; BEGIN PERFORM public.admin_reverse_starter_credit(plain, 'qa g4');
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%denied%'; END;
  res := res || jsonb_build_object('id',30,'name','direct admin_reverse_starter_credit denied for ops','pass', ok);

  -- 5 · governance separation ------------------------------------------------
  ok := false; BEGIN PERFORM public.admin_enforce('governance.staff.manage','staff', plain::text, '{}'::jsonb);
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%denied%'; END;
  res := res || jsonb_build_object('id',31,'name','ops cannot create or manage staff','pass', ok);
  ok := false; err := NULL;
  BEGIN PERFORM public.admin_staff_role_grant(plain, 'operations_admin', 'qa g4');
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; ok := SQLERRM ILIKE '%denied%'; END;
  res := res || jsonb_build_object('id',32,'name','ops cannot role-change staff','pass', ok, 'err', err);
  ok := false; BEGIN PERFORM public.admin_enforce('governance.settings.manage','settings','app', '{}'::jsonb);
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%denied%'; END;
  res := res || jsonb_build_object('id',33,'name','ops cannot change platform settings','pass', ok);
  ok := false; err := NULL;
  BEGIN INSERT INTO public.admin_capability_grants(capability, admin_role, mode)
        VALUES ('finance.wallet.credit','operations_admin','allow');
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; ok := true; END;
  res := res || jsonb_build_object('id',34,'name','ops cannot mutate the capability registry','pass', ok, 'err', err);
  ok := false; err := NULL;
  BEGIN PERFORM public.admin_staff_roster();
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; ok := true; END;
  res := res || jsonb_build_object('id',35,'name','ops cannot read the staff roster','pass', ok, 'err', err);

  -- 6 · residue / drift ------------------------------------------------------
  PERFORM set_config('request.jwt.claims', '', true);
  DELETE FROM public.admin_users WHERE user_id = ANY(ids);
  DELETE FROM public.user_roles WHERE user_id = ANY(ids);
  DELETE FROM public.profiles WHERE user_id = ANY(ids);
  DELETE FROM auth.users WHERE id = ANY(ids);

  SELECT count(*) INTO n FROM public.admin_users WHERE notes = 'qa_g4_fixture';
  res := res || jsonb_build_object('id',36,'name','zero fixture authority residue','pass', n = 0, 'residue', n);
  SELECT count(*) INTO n FROM auth.users WHERE email LIKE 'qa.g4.%@chopchop.test';
  res := res || jsonb_build_object('id',37,'name','zero fixture identity residue','pass', n = 0, 'residue', n);

  SELECT count(*) INTO ledger_after FROM public.ledger_postings;
  res := res || jsonb_build_object('id',38,'name','no ledger mutation from G4 QA','pass', ledger_after = ledger_before);
  SELECT md5(string_agg(key || '=' || enabled::text, ',' ORDER BY key)) INTO flags_after FROM public.feature_flags;
  res := res || jsonb_build_object('id',39,'name','no feature-flag drift','pass', flags_after IS NOT DISTINCT FROM flags_before);
  SELECT count(*) INTO grants_after FROM public.admin_capability_grants;
  res := res || jsonb_build_object('id',40,'name','capability registry unchanged','pass', grants_after = grants_before);

  RETURN jsonb_build_object(
    'suite','G4 operations command center',
    'total', jsonb_array_length(res),
    'failures', (SELECT count(*) FROM jsonb_array_elements(res) e WHERE (e->>'pass')::boolean IS NOT TRUE),
    'checks', res);
END;
$function$;

REVOKE ALL ON FUNCTION public._qa_g4_operations_command_center() FROM PUBLIC, anon, authenticated;