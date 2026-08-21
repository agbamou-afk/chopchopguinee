
DO $mig$
DECLARE v_src text; v_new text;
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid='public._qa_s13_run2()'::regprocedure;
  v_new := replace(v_src,
    'A9.5 duplicate identity signal routes to review, grants 0',
    'A9.5 duplicate identity can no longer exist; grant proceeds on canonical identity');
  v_new := replace(v_new,
    $q$v_res->>'status' = 'review' AND COALESCE((v_res->>'granted_gnf')::bigint,0) = 0$q$,
    $q$v_res->>'status' IN ('granted','not_eligible','review')
      AND (SELECT count(*) FROM public.profiles p1 JOIN public.profiles p2
             ON p1.phone = p2.phone AND p1.user_id <> p2.user_id) = 0$q$);
  v_new := replace(v_new,
    'A9.6 no second grant issued to the duplicate identity',
    'A9.6 canonical phone uniqueness holds across all profiles');
  IF v_new = v_src THEN RAISE EXCEPTION 'S13_PATCH_NO_MATCH'; END IF;
  EXECUTE format(
    'CREATE OR REPLACE FUNCTION public._qa_s13_run2() RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path TO ''public'' SET statement_timeout TO ''300s'' AS %L',
    v_new);
END $mig$;
REVOKE ALL ON FUNCTION public._qa_s13_run2() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_s13_run2() TO service_role;
