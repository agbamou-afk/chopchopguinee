
DO $mig$
DECLARE v_src text; v_new text;
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid='public._qa_s13_run2()'::regprocedure;
  v_new := replace(v_src,
    'UPDATE public.profiles SET phone = ''622000111'' WHERE user_id = v_d2;',
$q$BEGIN
      UPDATE public.profiles SET phone = '622000111' WHERE user_id = v_d2;
      v_err := 'NO_ERROR';
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('A9.4b canonical phone uniqueness refuses duplicate identity at write time',
      v_err <> 'NO_ERROR', v_err);
    UPDATE public.profiles SET phone = '622000112' WHERE user_id = v_d2;$q$);
  IF v_new = v_src THEN RAISE EXCEPTION 'S13_PATCH_NO_MATCH'; END IF;
  EXECUTE format(
    'CREATE OR REPLACE FUNCTION public._qa_s13_run2() RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path TO ''public'' SET statement_timeout TO ''300s'' AS %L',
    v_new);
END $mig$;
REVOKE ALL ON FUNCTION public._qa_s13_run2() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_s13_run2() TO service_role;
