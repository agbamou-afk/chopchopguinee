-- 1) Fail-closed guard on admin_anonymize_user
CREATE OR REPLACE FUNCTION public.admin_anonymize_user(_target uuid, _reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _caller uuid := auth.uid();
  _role text := COALESCE(
    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    current_user::text);
  v_core jsonb;
  v_err text;
  v_state text;
BEGIN
  IF _caller IS NULL THEN
    -- Unauthenticated / null-auth callers are forbidden. The only permitted
    -- null-caller path is the platform service role (admin-delete-user edge fn).
    IF _role IS DISTINCT FROM 'service_role' THEN
      RAISE EXCEPTION 'forbidden' USING ERRCODE='42501';
    END IF;
  ELSIF NOT (public.has_admin_role(_caller,'god_admin'::admin_role)
             OR public.has_admin_role(_caller,'super_admin'::admin_role)) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE='42501';
  END IF;

  BEGIN
    v_core := public._anonymize_user_core(_target, 'admin_anonymized');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT, v_state = RETURNED_SQLSTATE;
    RETURN jsonb_build_object('ok',false,'mode','anonymized','sqlstate',v_state,'detail',v_err);
  END;

  BEGIN
    INSERT INTO public.account_deletion_requests(user_id, requested_by, request_type, status, reason, processed_by, processed_at)
    VALUES (_target,_caller,'admin_anonymize','processed',_reason,_caller, now());
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT, v_state = RETURNED_SQLSTATE;
    v_core := v_core || jsonb_build_object('audit_warning',jsonb_build_object('sqlstate',v_state,'error',v_err));
  END;

  RETURN jsonb_build_object('ok', true, 'mode', 'anonymized', 'steps', v_core->'steps');
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_anonymize_user(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_anonymize_user(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_anonymize_user(uuid, text) TO authenticated, service_role;

-- 2) Internal primitive: service_role only
REVOKE ALL ON FUNCTION public._anonymize_user_core(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._anonymize_user_core(uuid, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public._anonymize_user_core(uuid, text) TO service_role;

-- 3) admin_auth_user_exists: same null-auth pattern (unguarded existence oracle)
CREATE OR REPLACE FUNCTION public.admin_auth_user_exists(_target uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _caller uuid := auth.uid();
  _role text := COALESCE(
    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    current_user::text);
  v_exists boolean;
BEGIN
  IF _caller IS NULL THEN
    IF _role IS DISTINCT FROM 'service_role' THEN
      RAISE EXCEPTION 'forbidden' USING ERRCODE='42501';
    END IF;
  ELSIF NOT (public.has_admin_role(_caller,'god_admin'::admin_role)
             OR public.has_admin_role(_caller,'super_admin'::admin_role)) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE='42501';
  END IF;
  SELECT EXISTS(SELECT 1 FROM auth.users WHERE id = _target) INTO v_exists;
  RETURN v_exists;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_auth_user_exists(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_auth_user_exists(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_auth_user_exists(uuid) TO authenticated, service_role;

-- 4) Grant tightening only (body already rejects null callers)
REVOKE ALL ON FUNCTION public.admin_pre_purge_test_user(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_pre_purge_test_user(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.admin_pre_purge_test_user(uuid) TO authenticated, service_role;

-- 5) Part 7 security regression assertions (S7.1 - S7.4), injected in-place
DO $do$
DECLARE
  src text;
  inj text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO src
    FROM pg_proc WHERE proname = '_qa_s13_run7' AND pronamespace = 'public'::regnamespace;

  inj := $inj$
    r := r || public._qa_s13_ok('S7.1 anon and sandbox_exec cannot execute admin_anonymize_user while the authenticated admin path keeps it',
      NOT has_function_privilege('anon','public.admin_anonymize_user(uuid,text)','EXECUTE')
      AND NOT has_function_privilege('sandbox_exec','public.admin_anonymize_user(uuid,text)','EXECUTE')
      AND has_function_privilege('authenticated','public.admin_anonymize_user(uuid,text)','EXECUTE'), NULL);

    PERFORM set_config('request.jwt.claims','',true);
    BEGIN
      v_probe := public.admin_anonymize_user(v_c2, 'qa s13 p7 null caller');
      r := r || public._qa_s13_ok('S7.2 an unauthenticated caller is refused by admin_anonymize_user', false, 'no exception raised');
    EXCEPTION WHEN OTHERS THEN
      r := r || public._qa_s13_ok('S7.2 an unauthenticated caller is refused by admin_anonymize_user', SQLSTATE = '42501', SQLSTATE);
    END;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_c1), true);
    BEGIN
      v_probe := public.admin_anonymize_user(v_c2, 'qa s13 p7 non admin');
      r := r || public._qa_s13_ok('S7.3 a signed-in non-admin is refused by admin_anonymize_user', false, 'no exception raised');
    EXCEPTION WHEN OTHERS THEN
      r := r || public._qa_s13_ok('S7.3 a signed-in non-admin is refused by admin_anonymize_user', SQLSTATE = '42501', SQLSTATE);
    END;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_god), true);
    v_probe := public.admin_anonymize_user(v_c2, 'qa s13 p7 god admin');
    r := r || public._qa_s13_ok('S7.4 a signed-in God Admin can still anonymize an account',
      COALESCE((v_probe->>'ok')::boolean, false), v_probe::text);
    PERFORM set_config('request.jwt.claims','',true);

    RAISE EXCEPTION 'QA_S13_ROLLBACK';$inj$;

  src := replace(src, '    RAISE EXCEPTION ''QA_S13_ROLLBACK'';', inj);
  EXECUTE src;
END
$do$;