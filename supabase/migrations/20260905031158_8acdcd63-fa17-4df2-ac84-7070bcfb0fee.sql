CREATE OR REPLACE FUNCTION public._qa_g3_staff_lifecycle()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  res jsonb := '[]'::jsonb;
  godA uuid := gen_random_uuid(); godB uuid := gen_random_uuid();
  opsMgr uuid := gen_random_uuid(); finMgr uuid := gen_random_uuid();
  t1 uuid := gen_random_uuid();  -- created ops staff
  t2 uuid := gen_random_uuid();  -- created finance staff
  ids uuid[]; ap uuid; v jsonb; ok boolean; err text; n int;
  rid1 uuid; rid2 uuid; rid uuid;
  e1 text; e2 text; k text;
  fp_before text; fp_after text;
  real_ops uuid[] := ARRAY['a9e4f3b0-7be9-4338-b96e-5e9752afab0c'::uuid,
                           'dfb6a0f8-7fc7-47e3-8f15-d8540fa8f473'::uuid];

  FUNCTION_PLACEHOLDER boolean;
BEGIN
  ids := ARRAY[godA,godB,opsMgr,finMgr,t1,t2];
  e1 := 'qa.g3.ops.'||replace(t1::text,'-','')||'@chopchop.test';
  e2 := 'qa.g3.fin.'||replace(t2::text,'-','')||'@chopchop.test';

  SELECT md5(string_agg(x,'|' ORDER BY x)) INTO fp_before FROM (
    SELECT a.user_id::text||':'||a.admin_role::text||':'||a.status::text||':'||
           a.must_change_password::text||':'||coalesce(a.changed_password_at::text,'-')||':'||
           coalesce((SELECT string_agg(r.role::text,',' ORDER BY r.role::text)
                       FROM public.user_roles r WHERE r.user_id=a.user_id),'-') AS x
      FROM public.admin_users a WHERE a.user_id = ANY(real_ops)) s;

  -- fixtures -------------------------------------------------------------
  INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data)
  SELECT u, '00000000-0000-0000-0000-000000000000','authenticated','authenticated',
         'qa.g3.'||u::text||'@chopchop.test','', now(), now(), now(), '{}'::jsonb,'{}'::jsonb
  FROM unnest(ids) u;
  INSERT INTO public.profiles (user_id, full_name)
  SELECT u,'QA G3 fixture' FROM unnest(ids) u ON CONFLICT (user_id) DO NOTHING;
  INSERT INTO public.admin_users (user_id, admin_role, status, notes) VALUES
    (godA,'god_admin','active','qa_g3_fixture'),
    (godB,'god_admin','active','qa_g3_fixture'),
    (opsMgr,'ops_admin','active','qa_g3_fixture'),
    (finMgr,'finance_admin','active','qa_g3_fixture');

  -- helper: approval minted by godA, approved by godB -----------------------
  -- T1 : create Operations with exact approved intent
  PERFORM set_config('request.jwt.claims', public._as_user_claims(godA), true);
  ap := public.admin_request_approval('governance.staff.manage','staff_email',e1,
        jsonb_build_object('action','CREATE','admin_role','operations_admin','must_change_password',true),
        'admins', 60);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(godB), true);
  PERFORM public.admin_review_approval(ap,'approved','qa');
  PERFORM set_config('request.jwt.claims','',true);

  k := 'qa-g3-create-ops-'||replace(t1::text,'-','');
  v := public.admin_staff_lifecycle_begin_as(godA,'CREATE',k,e1,'operations_admin',true,ap,NULL,'qa');
  rid1 := (v->>'request_id')::uuid;
  PERFORM public.admin_staff_record_auth_as(rid1, t1);
  v := public.admin_staff_finalize_create_as(rid1,'qa.ops','QA Ops','+224600000001');
  res := res || jsonb_build_object('id',1,'name','create Operations with approved intent succeeds',
    'pass', v->>'result'='CREATED' AND public.admin_role_canonical(t1)='operations_admin');

  -- T2 : create Finance
  PERFORM set_config('request.jwt.claims', public._as_user_claims(godA), true);
  ap := public.admin_request_approval('governance.staff.manage','staff_email',e2,
        jsonb_build_object('action','CREATE','admin_role','finance_admin','must_change_password',true),
        'admins',60);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(godB), true);
  PERFORM public.admin_review_approval(ap,'approved','qa');
  PERFORM set_config('request.jwt.claims','',true);
  k := 'qa-g3-create-fin-'||replace(t2::text,'-','');
  v := public.admin_staff_lifecycle_begin_as(godA,'CREATE',k,e2,'finance_admin',true,ap,NULL,'qa');
  rid2 := (v->>'request_id')::uuid;
  PERFORM public.admin_staff_record_auth_as(rid2, t2);
  v := public.admin_staff_finalize_create_as(rid2,'qa.fin','QA Fin',NULL);
  res := res || jsonb_build_object('id',2,'name','create Finance with approved intent succeeds',
    'pass', v->>'result'='CREATED' AND public.admin_role_canonical(t2)='finance_admin');

  -- T3 : same key + same intent is idempotent
  k := 'qa-g3-create-ops-'||replace(t1::text,'-','');
  v := public.admin_staff_lifecycle_begin_as(godA,'CREATE',k,e1,'operations_admin',true,NULL,NULL,'qa');
  SELECT count(*) INTO n FROM public.admin_users WHERE user_id=t1;
  res := res || jsonb_build_object('id',3,'name','same idempotency key + same intent replays, no duplicate',
    'pass', v->>'result'='ALREADY_COMPLETED' AND n=1);

  -- T4 : same key + different intent denied
  ok := false; err := NULL;
  BEGIN
    PERFORM public.admin_staff_lifecycle_begin_as(godA,'CREATE',k,e1,'finance_admin',true,NULL,NULL,'qa');
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; ok := SQLERRM ILIKE '%IDEMPOTENCY_INTENT_MISMATCH%'; END;
  res := res || jsonb_build_object('id',4,'name','same key + different intent denied','pass',ok,'err',err);

  -- T5 : finalize refuses without an auth identity (no second auth user can appear)
  PERFORM set_config('request.jwt.claims', public._as_user_claims(godA), true);
  ap := public.admin_request_approval('governance.staff.manage','staff_email','qa.g3.dup@chopchop.test',
        jsonb_build_object('action','CREATE','admin_role','operations_admin','must_change_password',true),'admins',60);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(godB), true);
  PERFORM public.admin_review_approval(ap,'approved','qa');
  PERFORM set_config('request.jwt.claims','',true);
  rid := (public.admin_staff_lifecycle_begin_as(godA,'CREATE','qa-g3-dup-'||replace(godA::text,'-',''),
          'qa.g3.dup@chopchop.test','operations_admin',true,ap,NULL,'qa')->>'request_id')::uuid;
  ok := false; err := NULL;
  BEGIN PERFORM public.admin_staff_finalize_create_as(rid,'x','x',NULL);
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; ok := SQLERRM ILIKE '%AUTH_NOT_PROVISIONED%'; END;
  res := res || jsonb_build_object('id',5,'name','no staff authority without a provisioned auth identity','pass',ok,'err',err);

  -- T6 : partial-finalisation retry resumes on the SAME auth user
  PERFORM public.admin_staff_record_auth_as(rid, t1);   -- simulated resume onto existing identity
  PERFORM public.admin_staff_record_auth_as(rid, gen_random_uuid());  -- must not overwrite
  SELECT auth_user_id = t1 INTO ok FROM public.staff_lifecycle_requests WHERE id=rid;
  res := res || jsonb_build_object('id',6,'name','retry resumes the recorded auth identity, never a second one','pass',coalesce(ok,false));

  -- T7 : no plaintext password material anywhere in lifecycle/audit rows
  SELECT count(*) INTO n FROM public.staff_lifecycle_requests s
   WHERE s.requester_id IN (godA,godB)
     AND (s::text ILIKE '%Welcome%' OR s::text ILIKE '%password":"%');
  SELECT n + count(*) INTO n FROM public.audit_logs a
   WHERE a.actor_user_id IN (godA,godB)
     AND (coalesce(a.after::text,'') ILIKE '%Welcome%'
       OR coalesce(a.after::text,'') ~* '"(password|temporary_password|temp_password)"\s*:\s*"');
  res := res || jsonb_build_object('id',7,'name','no plaintext password in lifecycle or audit payloads','pass', n=0,'hits',n);

  -- T8 : new staff must change password and has zero effective capability
  res := res || jsonb_build_object('id',8,'name','temp-password staff has no effective capability',
    'pass', public.admin_staff_readiness(t1)='temp_password_required'
        AND public.admin_capability_mode('ops.drivers.manage', t1) IS NULL
        AND NOT coalesce(public.admin_capability('ops.drivers.manage', t1),false)
        AND public.admin_role_canonical(t1)='operations_admin');

  -- T9 : first-password completion restores authority
  PERFORM set_config('request.jwt.claims', public._as_user_claims(t1), true);
  PERFORM public.admin_clear_must_change_password();
  PERFORM set_config('request.jwt.claims','',true);
  res := res || jsonb_build_object('id',9,'name','first password completion clears readiness and enables capability',
    'pass', public.admin_staff_readiness(t1)='ready'
        AND coalesce(public.admin_capability('ops.drivers.manage', t1),false));

  -- T10 : audit records FIRST_PASSWORD_COMPLETED provenance
  SELECT count(*) INTO n FROM public.audit_logs
   WHERE actor_user_id=t1 AND action='staff.lifecycle.FIRST_PASSWORD_COMPLETED';
  res := res || jsonb_build_object('id',10,'name','first-password completion is audited','pass', n=1);

  -- T11 : Operations and Finance cannot run staff lifecycle
  ok := true;
  BEGIN PERFORM public.admin_staff_lifecycle_begin_as(opsMgr,'DEACTIVATE','qa-g3-ops-attempt-'||replace(t1::text,'-',''),
          t1::text,NULL,false,NULL,t1,'qa'); ok := false;
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%capability_denied%'; END;
  IF ok THEN
    BEGIN PERFORM public.admin_staff_lifecycle_begin_as(finMgr,'DEACTIVATE','qa-g3-fin-attempt-'||replace(t1::text,'-',''),
            t1::text,NULL,false,NULL,t1,'qa'); ok := false;
    EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%capability_denied%'; END;
  END IF;
  res := res || jsonb_build_object('id',11,'name','Operations/Finance cannot manage staff','pass',ok);

  -- T12 : self lifecycle denied
  ok := false; err := NULL;
  BEGIN PERFORM public.admin_staff_lifecycle_begin_as(godA,'DEACTIVATE','qa-g3-self-'||replace(godA::text,'-',''),
          godA::text,NULL,false,NULL,godA,'qa');
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; ok := SQLERRM ILIKE '%SELF_LIFECYCLE_FORBIDDEN%'; END;
  res := res || jsonb_build_object('id',12,'name','self-deactivation denied','pass',ok,'err',err);

  -- T13/T14 : deactivate removes BOTH authority sources, immediately
  PERFORM set_config('request.jwt.claims', public._as_user_claims(godA), true);
  ap := public.admin_request_approval('governance.staff.manage','staff_user',t1::text,
        jsonb_build_object('action','DEACTIVATE','admin_role',NULL,'must_change_password',false),'admins',60);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(godB), true);
  PERFORM public.admin_review_approval(ap,'approved','qa');
  PERFORM set_config('request.jwt.claims','',true);
  rid := (public.admin_staff_lifecycle_begin_as(godA,'DEACTIVATE','qa-g3-deact-'||replace(t1::text,'-',''),
          t1::text,NULL,false,ap,t1,'qa')->>'request_id')::uuid;
  v := public.admin_staff_finalize_deactivate_as(rid);
  SELECT count(*) INTO n FROM public.user_roles WHERE user_id=t1
     AND role::text IN ('operations_admin','finance_admin','support_admin');
  res := res || jsonb_build_object('id',13,'name','deactivation clears admin_users + user_roles authority',
    'pass', n=0 AND public.admin_role_canonical(t1) IS NULL
        AND EXISTS (SELECT 1 FROM public.admin_users WHERE user_id=t1 AND status='suspended'));
  res := res || jsonb_build_object('id',14,'name','deactivated staff denied capability immediately',
    'pass', public.admin_capability_mode('ops.drivers.manage', t1) IS NULL
        AND NOT coalesce(public.admin_capability('ops.drivers.manage', t1),false));

  -- T15 : reactivation restores exactly one chosen class + forced readiness reset
  PERFORM set_config('request.jwt.claims', public._as_user_claims(godA), true);
  ap := public.admin_request_approval('governance.staff.manage','staff_user',t1::text,
        jsonb_build_object('action','REACTIVATE','admin_role','finance_admin','must_change_password',true),'admins',60);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(godB), true);
  PERFORM public.admin_review_approval(ap,'approved','qa');
  PERFORM set_config('request.jwt.claims','',true);
  rid := (public.admin_staff_lifecycle_begin_as(godA,'REACTIVATE','qa-g3-react-'||replace(t1::text,'-',''),
          t1::text,'finance_admin',true,ap,t1,'qa')->>'request_id')::uuid;
  v := public.admin_staff_finalize_authority_as(rid);
  SELECT count(*) INTO n FROM public.user_roles WHERE user_id=t1
     AND role::text IN ('operations_admin','finance_admin','support_admin');
  res := res || jsonb_build_object('id',15,'name','reactivation installs exactly one class and forces readiness reset',
    'pass', public.admin_role_canonical(t1)='finance_admin' AND n=1
        AND public.admin_staff_readiness(t1)='temp_password_required'
        AND NOT coalesce(public.admin_capability('finance.topup.manage', t1),false));

  -- clear readiness so the class-change proof is about authority, not readiness
  PERFORM set_config('request.jwt.claims', public._as_user_claims(t1), true);
  PERFORM public.admin_clear_must_change_password();
  PERFORM set_config('request.jwt.claims','',true);

  -- T16 : role change Finance -> Operations
  PERFORM set_config('request.jwt.claims', public._as_user_claims(godA), true);
  ap := public.admin_request_approval('governance.staff.manage','staff_user',t1::text,
        jsonb_build_object('action','ROLE_CHANGE','admin_role','operations_admin','must_change_password',true),'admins',60);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(godB), true);
  PERFORM public.admin_review_approval(ap,'approved','qa');
  PERFORM set_config('request.jwt.claims','',true);
  rid := (public.admin_staff_lifecycle_begin_as(godA,'ROLE_CHANGE','qa-g3-rc1-'||replace(t1::text,'-',''),
          t1::text,'operations_admin',true,ap,t1,'qa')->>'request_id')::uuid;
  PERFORM public.admin_staff_finalize_authority_as(rid);
  ok := public.admin_role_canonical(t1)='operations_admin'
        AND NOT coalesce(public.admin_capability('finance.topup.manage', t1),false);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(t1), true);
  PERFORM public.admin_clear_must_change_password();
  PERFORM set_config('request.jwt.claims','',true);
  ok := ok AND coalesce(public.admin_capability('ops.drivers.manage', t1),false)
           AND NOT coalesce(public.admin_capability('finance.topup.manage', t1),false);
  res := res || jsonb_build_object('id',16,'name','Finance -> Operations swaps authority atomically','pass',ok);

  -- T17 : role change Operations -> Finance (inverse proof on t2's peer)
  PERFORM set_config('request.jwt.claims', public._as_user_claims(godA), true);
  ap := public.admin_request_approval('governance.staff.manage','staff_user',t1::text,
        jsonb_build_object('action','ROLE_CHANGE','admin_role','finance_admin','must_change_password',true),'admins',60);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(godB), true);
  PERFORM public.admin_review_approval(ap,'approved','qa');
  PERFORM set_config('request.jwt.claims','',true);
  rid := (public.admin_staff_lifecycle_begin_as(godA,'ROLE_CHANGE','qa-g3-rc2-'||replace(t1::text,'-',''),
          t1::text,'finance_admin',true,ap,t1,'qa')->>'request_id')::uuid;
  PERFORM public.admin_staff_finalize_authority_as(rid);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(t1), true);
  PERFORM public.admin_clear_must_change_password();
  PERFORM set_config('request.jwt.claims','',true);
  SELECT count(*) INTO n FROM public.user_roles WHERE user_id=t1
     AND role::text IN ('operations_admin','finance_admin','support_admin');
  res := res || jsonb_build_object('id',17,'name','Operations -> Finance inverse proof, no dual class',
    'pass', public.admin_role_canonical(t1)='finance_admin' AND n=1
        AND coalesce(public.admin_capability('finance.topup.manage', t1),false)
        AND NOT coalesce(public.admin_capability('ops.drivers.manage', t1),false));

  -- T18 : God cannot be assigned through G3
  ok := false; err := NULL;
  BEGIN PERFORM public.admin_staff_lifecycle_begin_as(godA,'ROLE_CHANGE','qa-g3-god-'||replace(t2::text,'-',''),
          t2::text,'god_admin',true,NULL,t2,'qa');
  EXCEPTION WHEN OTHERS THEN err := SQLERRM; ok := SQLERRM ILIKE '%ROLE_FORBIDDEN%'; END;
  res := res || jsonb_build_object('id',18,'name','no G3 path can assign God Admin','pass',ok,'err',err);

  -- T19 : God target is out of reach of every G3 action
  ok := true;
  FOREACH k IN ARRAY ARRAY['DEACTIVATE','ROLE_CHANGE','ACCESS_RESET'] LOOP
    BEGIN
      PERFORM public.admin_staff_lifecycle_begin_as(godA,k,'qa-g3-godt-'||k||'-'||replace(godB::text,'-',''),
              godB::text, CASE WHEN k='ROLE_CHANGE' THEN 'operations_admin' END, true, NULL, godB,'qa');
      ok := false;
    EXCEPTION WHEN OTHERS THEN ok := ok AND SQLERRM ILIKE '%GOD_TARGET_FORBIDDEN%'; END;
  END LOOP;
  res := res || jsonb_build_object('id',19,'name','God target rejected for deactivate/role-change/reset','pass',ok);

  -- T20 : access reset forces readiness and denies capability immediately
  PERFORM set_config('request.jwt.claims', public._as_user_claims(godA), true);
  ap := public.admin_request_approval('governance.staff.manage','staff_user',t2::text,
        jsonb_build_object('action','ACCESS_RESET','admin_role',NULL,'must_change_password',true),'admins',60);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(godB), true);
  PERFORM public.admin_review_approval(ap,'approved','qa');
  PERFORM set_config('request.jwt.claims','',true);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(t2), true);
  PERFORM public.admin_clear_must_change_password();
  PERFORM set_config('request.jwt.claims','',true);
  rid := (public.admin_staff_lifecycle_begin_as(godA,'ACCESS_RESET','qa-g3-reset-'||replace(t2::text,'-',''),
          t2::text,NULL,true,ap,t2,'qa')->>'request_id')::uuid;
  PERFORM public.admin_staff_finalize_authority_as(rid);
  res := res || jsonb_build_object('id',20,'name','access reset forces temp password and denies capability at once',
    'pass', public.admin_staff_readiness(t2)='temp_password_required'
        AND NOT coalesce(public.admin_capability('finance.topup.manage', t2),false)
        AND public.admin_role_canonical(t2)='finance_admin');

  -- T21 : approval mismatch and replay refused
  PERFORM set_config('request.jwt.claims', public._as_user_claims(godA), true);
  ap := public.admin_request_approval('governance.staff.manage','staff_user',t2::text,
        jsonb_build_object('action','DEACTIVATE','admin_role',NULL,'must_change_password',false),'admins',60);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(godB), true);
  PERFORM public.admin_review_approval(ap,'approved','qa');
  PERFORM set_config('request.jwt.claims','',true);
  ok := false;
  BEGIN  -- wrong target for this approval
    PERFORM public.admin_staff_lifecycle_begin_as(godA,'DEACTIVATE','qa-g3-mismatch-'||replace(t2::text,'-',''),
            t1::text,NULL,false,ap,t1,'qa');
  EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%approval_target_mismatch%'; END;
  IF ok THEN
    PERFORM public.admin_staff_lifecycle_begin_as(godA,'DEACTIVATE','qa-g3-consume-'||replace(t2::text,'-',''),
            t2::text,NULL,false,ap,t2,'qa');
    ok := false;
    BEGIN  -- replay of a consumed approval
      PERFORM public.admin_staff_lifecycle_begin_as(godA,'DEACTIVATE','qa-g3-replay-'||replace(t2::text,'-',''),
              t2::text,NULL,false,ap,t2,'qa');
    EXCEPTION WHEN OTHERS THEN ok := SQLERRM ILIKE '%consumed%'; END;
  END IF;
  res := res || jsonb_build_object('id',21,'name','approval target mismatch and replay refused','pass',ok);

  -- T22 : lifecycle provenance complete for every completed action
  SELECT count(*) INTO n FROM public.staff_lifecycle_requests s
   WHERE s.requester_id = godA AND s.state='completed'
     AND NOT EXISTS (
       SELECT 1 FROM public.audit_logs a
        WHERE a.action = 'staff.lifecycle.'||s.action
          AND a.after->>'lifecycle_request_id' = s.id::text
          AND a.after ? 'idempotency_key' AND a.actor_user_id = s.requester_id);
  res := res || jsonb_build_object('id',22,'name','every completed lifecycle action has full audit provenance',
    'pass', n=0,'missing',n);

  -- T23 : the two real Operations Admin accounts are untouched
  SELECT md5(string_agg(x,'|' ORDER BY x)) INTO fp_after FROM (
    SELECT a.user_id::text||':'||a.admin_role::text||':'||a.status::text||':'||
           a.must_change_password::text||':'||coalesce(a.changed_password_at::text,'-')||':'||
           coalesce((SELECT string_agg(r.role::text,',' ORDER BY r.role::text)
                       FROM public.user_roles r WHERE r.user_id=a.user_id),'-') AS x
      FROM public.admin_users a WHERE a.user_id = ANY(real_ops)) s;
  res := res || jsonb_build_object('id',23,'name','pre-existing real Operations Admin accounts unchanged',
    'pass', fp_before = fp_after,'fingerprint',fp_after);

  -- cleanup ---------------------------------------------------------------
  PERFORM set_config('chopchop.g3_lifecycle','on',true);
  DELETE FROM public.staff_lifecycle_requests WHERE requester_id = ANY(ids) OR target_user_id = ANY(ids);
  PERFORM set_config('chopchop.g3_lifecycle','off',true);
  DELETE FROM public.audit_logs WHERE actor_user_id = ANY(ids) OR target_id = ANY(SELECT u::text FROM unnest(ids) u);
  DELETE FROM public.approval_requests WHERE requested_by = ANY(ids);
  DELETE FROM public.user_roles WHERE user_id = ANY(ids);
  DELETE FROM public.admin_users WHERE user_id = ANY(ids);
  DELETE FROM public.profiles WHERE user_id = ANY(ids);
  DELETE FROM auth.users WHERE id = ANY(ids);

  SELECT (SELECT count(*) FROM public.staff_lifecycle_requests WHERE requester_id = ANY(ids))
       + (SELECT count(*) FROM public.admin_users WHERE user_id = ANY(ids))
       + (SELECT count(*) FROM public.user_roles WHERE user_id = ANY(ids))
       + (SELECT count(*) FROM public.approval_requests WHERE requested_by = ANY(ids))
       + (SELECT count(*) FROM auth.users WHERE id = ANY(ids)) INTO n;
  res := res || jsonb_build_object('id',24,'name','zero fixture residue','pass', n=0,'residue',n);

  RETURN jsonb_build_object(
    'suite','g3_staff_lifecycle',
    'total', jsonb_array_length(res),
    'failures', (SELECT count(*) FROM jsonb_array_elements(res) e WHERE (e->>'pass')::boolean IS NOT TRUE),
    'checks', res);
END;
$$;
REVOKE ALL ON FUNCTION public._qa_g3_staff_lifecycle() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_g3_staff_lifecycle() TO service_role;