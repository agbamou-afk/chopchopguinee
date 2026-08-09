DO $$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef('public._qa_s3b_run()'::regprocedure) INTO d;
  d := replace(d, 'PERFORM public.ride_set_phase(q3,''arrived'');',
    'PERFORM set_config(''request.jwt.claims'', public._as_user_claims(dv1), true); PERFORM public.ride_set_phase(q3,''arrived'');');
  EXECUTE d;
END $$;