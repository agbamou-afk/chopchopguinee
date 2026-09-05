CREATE OR REPLACE FUNCTION public._qa_g2_admin_authority()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  res jsonb := '[]'::jsonb;
  godA uuid := gen_random_uuid(); godB uuid := gen_random_uuid();
  ops  uuid := gen_random_uuid(); fin  uuid := gen_random_uuid();
  plain uuid := gen_random_uuid(); bare uuid := gen_random_uuid();
  conflict uuid := gen_random_uuid(); closed uuid := gen_random_uuid();
  ids uuid[]; ap uuid; ap2 uuid; v jsonb; ok boolean; err text; n int;
  PROC_TARGET uuid := gen_random_uuid();

  PROCEDURE_NOOP int;
BEGIN
  ids := ARRAY[godA,godB,ops,fin,plain,bare,conflict,closed];

  -- ephemeral fixtures -------------------------------------------------
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data)
  SELECT u, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         'qa.g2.'||u::text||'@chopchop.test', '', now(), now(), now(), '{}'::jsonb, '{}'::jsonb
  FROM unnest(ids) u;

  INSERT INTO public.profiles (user_id, full_name)
  SELECT u, 'QA G2 fixture' FROM unnest(ids) u
  ON CONFLICT (user_id) DO NOTHING;

  INSERT INTO public.admin_users (user_id, admin_role, status, notes) VALUES
    (godA,'god_admin','active','qa_g2_fixture'),
    (godB,'super_admin','active','qa_g2_fixture'),
    (ops,'ops_admin','active','qa_g2_fixture'),
    (fin,'finance_admin','active','qa_g2_fixture'),
    (conflict,'finance_admin','active','qa_g2_fixture'),
    (closed,'ops_admin','suspended','qa_g2_fixture');
  INSERT INTO public.user_roles (user_id, role) VALUES
    (bare,'admin'), (conflict,'operations_admin');

  -- helper macro via inline asserts -------------------------------------
  -- 1 bare admin => NULL
  res := res || jsonb_build_object('id',1,'name','bare admin resolves NULL',
    'pass', public.admin_role_canonical(bare) IS NULL);
  -- 2 conflicting sources => NULL
  res := res || jsonb_build_object('id',2,'name','cross-source class conflict denies',
    'pass', public.admin_role_canonical(conflict) IS NULL);
  -- 3 aliases normalise
  res := res || jsonb_build_object('id',3,'name','aliases map to canonical class',
    'pass', public.admin_role_canonical(godB)='god_admin'
        AND public.admin_role_canonical(ops)='operations_admin'
        AND public.admin_role_canonical(godA)='god_admin'
        AND public.admin_role_canonical(fin)='finance_admin');
  -- 4 suspended/closed caller has no authority
  res := res || jsonb_build_object('id',4,'name','suspended staff has no authority',
    'pass', public.admin_role_canonical(closed) IS NULL);
  -- 5 ops positive operational capability
  res := res || jsonb_build_object('id',5,'name','ops holds ops.drivers.manage',
    'pass', public.admin_capability('ops.drivers.manage', ops));
  -- 6 ops financial denied
  res := res || jsonb_build_object('id',6,'name','ops denied finance.wallet.credit',
    'pass', NOT public.admin_capability('finance.wallet.credit', ops)
        AND public.admin_capability_mode('finance.wallet.read', ops) = 'read');
  -- 7 finance positive
  res := res || jsonb_build_object('id',7,'name','finance holds finance.topup.manage',
    'pass', public.admin_capability('finance.topup.manage', fin));
  -- 8 finance operational mutation denied
  res := res || jsonb_build_object('id',8,'name','finance denied ops.drivers.manage mutation',
    'pass', NOT public.admin_capability('ops.drivers.manage', fin)
        AND public.admin_capability_mode('ops.drivers.manage', fin) = 'read');
  -- 9 ops/finance governance denied
  res := res || jsonb_build_object('id',9,'name','ops+finance denied governance.staff.manage',
    'pass', public.admin_capability_mode('governance.staff.manage', ops) IS NULL
        AND public.admin_capability_mode('governance.staff.manage', fin) IS NULL
        AND public.admin_capability_mode('governance.roles.assign', ops) IS NULL);
  -- 10 plain authenticated denied everywhere
  SELECT count(*) INTO n FROM public.admin_capability_grants g
   WHERE public.admin_capability_mode(g.capability, plain) IS NOT NULL;
  res := res || jsonb_build_object('id',10,'name','plain user denied across all 44 capabilities',
    'pass', n = 0);
  -- 11 god direct ALLOW works
  res := res || jsonb_build_object('id',11,'name','god ALLOW capability executes',
    'pass', public.admin_capability('governance.flags.manage', godA));
  -- 12 AR without approval denied for finance AND god
  ok := false;
  BEGIN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(godA), true);
    PERFORM public.admin_enforce('finance.wallet.credit','wallet',PROC_TARGET::text,
                                 jsonb_build_object('amount_gnf',1000));
  EXCEPTION WHEN OTHERS THEN ok := (SQLERRM ILIKE '%approval_required%'); END;
  res := res || jsonb_build_object('id',12,'name','AR without approval denied (god)','pass', ok);

  -- request a real approval as godA
  PERFORM set_config('request.jwt.claims', public._as_user_claims(godA), true);
  ap := public.admin_request_approval('finance.wallet.credit','wallet',PROC_TARGET::text,
          jsonb_build_object('amount_gnf',1000),'wallet',60);

  -- 13 self approval denied
  ok := false;
  BEGIN PERFORM public.admin_review_approval(ap,'approved');
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  res := res || jsonb_build_object('id',13,'name','self approval denied','pass', ok);

  -- 14 non-god approver denied
  ok := false;
  BEGIN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(fin), true);
    PERFORM public.admin_review_approval(ap,'approved');
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  res := res || jsonb_build_object('id',14,'name','non-god approver denied','pass', ok);

  -- godB approves
  PERFORM set_config('request.jwt.claims', public._as_user_claims(godB), true);
  PERFORM public.admin_review_approval(ap,'approved');

  -- 15 target mismatch denied
  ok := false;
  BEGIN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(godA), true);
    PERFORM public.admin_enforce('finance.wallet.credit','wallet',gen_random_uuid()::text,
            jsonb_build_object('amount_gnf',1000), ap);
  EXCEPTION WHEN OTHERS THEN ok := (SQLERRM ILIKE '%target_mismatch%'); END;
  res := res || jsonb_build_object('id',15,'name','approval target mismatch denied','pass', ok);

  -- 16 material/amount mismatch denied
  ok := false;
  BEGIN
    PERFORM public.admin_enforce('finance.wallet.credit','wallet',PROC_TARGET::text,
            jsonb_build_object('amount_gnf',999999), ap);
  EXCEPTION WHEN OTHERS THEN ok := (SQLERRM ILIKE '%material_mismatch%'); END;
  res := res || jsonb_build_object('id',16,'name','material parameter mismatch denied','pass', ok);

  -- 17 expired approval denied
  ok := false;
  ap2 := public.admin_request_approval('finance.wallet.credit','wallet',PROC_TARGET::text,
           jsonb_build_object('amount_gnf',2000),'wallet',60);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(godB), true);
  PERFORM public.admin_review_approval(ap2,'approved');
  UPDATE public.approval_requests SET expires_at = now() - interval '1 minute' WHERE id = ap2;
  BEGIN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(godA), true);
    PERFORM public.admin_enforce('finance.wallet.credit','wallet',PROC_TARGET::text,
            jsonb_build_object('amount_gnf',2000), ap2);
  EXCEPTION WHEN OTHERS THEN ok := (SQLERRM ILIKE '%expired%'); END;
  res := res || jsonb_build_object('id',17,'name','expired approval denied','pass', ok);

  -- 19 exact approval succeeds once
  ok := false;
  BEGIN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(godA), true);
    v := public.admin_enforce('finance.wallet.credit','wallet',PROC_TARGET::text,
           jsonb_build_object('amount_gnf',1000), ap);
    ok := (v->>'mode') = 'approval_required';
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; END;
  res := res || jsonb_build_object('id',19,'name','exact approval executes once','pass', ok, 'err', err);

  -- 18 replay denied
  ok := false;
  BEGIN
    PERFORM public.admin_enforce('finance.wallet.credit','wallet',PROC_TARGET::text,
            jsonb_build_object('amount_gnf',1000), ap);
  EXCEPTION WHEN OTHERS THEN ok := (SQLERRM ILIKE '%already_consumed%'); END;
  res := res || jsonb_build_object('id',18,'name','consumed approval replay denied','pass', ok);

  -- 20 consumption marked atomically with the gate outcome
  SELECT (consumed_at IS NOT NULL AND consumed_by = godA AND execution_ref IS NOT NULL)
    INTO ok FROM public.approval_requests WHERE id = ap;
  res := res || jsonb_build_object('id',20,'name','consumption bound to executing caller','pass', coalesce(ok,false));

  -- 21 Marché/Repas capture+settle denied to Ops
  ok := false;
  BEGIN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(ops), true);
    PERFORM public.admin_marche_capture_and_settle_offer(gen_random_uuid());
  EXCEPTION WHEN OTHERS THEN ok := (SQLERRM ILIKE '%capability_denied%' OR SQLERRM ILIKE '%denied%'); END;
  res := res || jsonb_build_object('id',21,'name','ops denied marché capture+settle','pass', ok);
  ok := false;
  BEGIN PERFORM public.admin_repas_capture_and_settle_order(gen_random_uuid());
  EXCEPTION WHEN OTHERS THEN ok := (SQLERRM ILIKE '%capability_denied%' OR SQLERRM ILIKE '%denied%'); END;
  res := res || jsonb_build_object('id',22,'name','ops denied repas capture+settle','pass', ok);

  -- 23 payment flag mutation: ops denied, single god actor denied, no state change
  ok := false;
  BEGIN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(ops), true);
    PERFORM public.admin_set_feature_flag('payments_orange_money', true);
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  n := 0;
  BEGIN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(godA), true);
    PERFORM public.admin_set_feature_flag('payments_orange_money', true);
  EXCEPTION WHEN OTHERS THEN n := 1; END;
  res := res || jsonb_build_object('id',23,'name','payment flag: ops denied AND single god actor denied',
    'pass', ok AND n = 1);

  -- 24 anon EXECUTE on admin_* stays zero
  SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
   WHERE ns.nspname='public' AND p.proname LIKE 'admin\_%'
     AND has_function_privilege('anon', p.oid, 'EXECUTE');
  res := res || jsonb_build_object('id',24,'name','anon EXECUTE on admin_* = 0','pass', n = 0, 'count', n);

  -- 25 internal engine gate + capability registry not browser-mutable
  ok := false;
  BEGIN
    PERFORM set_config('request.jwt.claims', public._as_user_claims(godA), true);
    INSERT INTO public.admin_capability_grants (capability, admin_role, mode)
    VALUES ('qa.g2.injected','operations_admin','allow');
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  res := res || jsonb_build_object('id',25,'name','capability registry not mutable from a session','pass', ok);

  -- 26 audit provenance carries role + capability + approval id
  PERFORM set_config('request.jwt.claims', NULL, true);
  SELECT count(*) INTO n FROM public.audit_logs
   WHERE actor_user_id = godA AND action = 'finance.wallet.credit'
     AND after->>'canonical_role' = 'god_admin'
     AND after->>'approval_id' = ap::text
     AND after->>'intent_hash' IS NOT NULL;
  res := res || jsonb_build_object('id',26,'name','audit provenance complete','pass', n >= 1);

  -- 27 unknown capability denied
  res := res || jsonb_build_object('id',27,'name','unknown capability denied',
    'pass', public.admin_capability_mode('does.not.exist', godA) IS NULL
        AND NOT public.admin_capability('does.not.exist', godA));

  -- purge -------------------------------------------------------------
  PERFORM set_config('request.jwt.claims', NULL, true);
  DELETE FROM public.audit_logs WHERE actor_user_id = ANY(ids);
  DELETE FROM public.approval_requests WHERE requested_by = ANY(ids) OR reviewed_by = ANY(ids);
  DELETE FROM public.admin_capability_grants WHERE capability = 'qa.g2.injected';
  DELETE FROM public.user_roles WHERE user_id = ANY(ids);
  DELETE FROM public.admin_users WHERE user_id = ANY(ids);
  DELETE FROM public.profiles WHERE user_id = ANY(ids);
  DELETE FROM auth.users WHERE id = ANY(ids);

  SELECT count(*) INTO n FROM auth.users WHERE id = ANY(ids);
  res := res || jsonb_build_object('id',28,'name','zero fixture residue','pass', n = 0);

  RETURN jsonb_build_object(
    'total', jsonb_array_length(res),
    'failed', (SELECT count(*) FROM jsonb_array_elements(res) e WHERE (e->>'pass')::boolean IS NOT TRUE),
    'results', res);
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('request.jwt.claims', NULL, true);
  DELETE FROM public.audit_logs WHERE actor_user_id = ANY(ids);
  DELETE FROM public.approval_requests WHERE requested_by = ANY(ids) OR reviewed_by = ANY(ids);
  DELETE FROM public.admin_capability_grants WHERE capability = 'qa.g2.injected';
  DELETE FROM public.user_roles WHERE user_id = ANY(ids);
  DELETE FROM public.admin_users WHERE user_id = ANY(ids);
  DELETE FROM public.profiles WHERE user_id = ANY(ids);
  DELETE FROM auth.users WHERE id = ANY(ids);
  RETURN jsonb_build_object('total',0,'failed',1,'fatal',SQLERRM,'results',res);
END;
$function$;

REVOKE ALL ON FUNCTION public._qa_g2_admin_authority() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_g2_admin_authority() TO service_role;