
DO $mig$
DECLARE d text; o text; n text;
BEGIN
  d := pg_get_functiondef('public._qa_node5_identity_final_remediation()'::regprocedure);

  o := $a$  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_god), true);
  r := r || public._qa_s13_ok('N5FR.G6$a$;
  n := $a$  r := r || public._qa_s13_ok('N5FR.D1G the global request gate exists and is bound to the API role',
        to_regprocedure('public.pgrst_pre_request()') IS NOT NULL
        AND EXISTS (SELECT 1 FROM pg_db_role_setting s JOIN pg_roles rr ON rr.oid=s.setrole
                     WHERE rr.rolname='authenticator'
                       AND array_to_string(s.setconfig,',') LIKE '%pgrst.db_pre_request=public.pgrst_pre_request%'), NULL);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_d), true);
  BEGIN
    PERFORM public.pgrst_pre_request();
    r := r || public._qa_s13_ok('N5FR.D2G the global request gate refuses a closed caller', false, 'no refusal');
  EXCEPTION WHEN OTHERS THEN
    v_txt := SQLERRM;
    r := r || public._qa_s13_ok('N5FR.D2G the global request gate refuses a closed caller',
          v_txt LIKE '%ACCOUNT_CLOSED%', v_txt);
  END;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_liv), true);
  BEGIN
    PERFORM public.pgrst_pre_request();
    r := r || public._qa_s13_ok('N5FR.D3G the global request gate passes a live caller', true, NULL);
  EXCEPTION WHEN OTHERS THEN
    r := r || public._qa_s13_ok('N5FR.D3G the global request gate passes a live caller', false, SQLERRM);
  END;
  PERFORM set_config('request.jwt.claims', '', true);
  BEGIN
    PERFORM public.pgrst_pre_request();
    r := r || public._qa_s13_ok('N5FR.D4G the global request gate never blocks signed-out traffic', true, NULL);
  EXCEPTION WHEN OTHERS THEN
    r := r || public._qa_s13_ok('N5FR.D4G the global request gate never blocks signed-out traffic', false, SQLERRM);
  END;

  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_god), true);
  r := r || public._qa_s13_ok('N5FR.G6$a$;
  IF position(o in d) = 0 THEN RAISE EXCEPTION 'G6 anchor missing'; END IF;
  d := replace(d, o, n);
  EXECUTE d;
END $mig$;
