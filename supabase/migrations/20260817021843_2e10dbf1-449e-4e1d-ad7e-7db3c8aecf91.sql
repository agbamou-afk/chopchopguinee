
DO $do$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO d FROM pg_proc WHERE oid =
    'public._qa_node4_marche_r7_fxcore()'::regprocedure;
  d := replace(d, 'SECURITY DEFINER', '');
  EXECUTE d;

  SELECT pg_get_functiondef(oid) INTO d FROM pg_proc WHERE oid =
    'public._qa_node4_marche_r7()'::regprocedure;
  d := replace(d, 'SECURITY DEFINER', '');
  EXECUTE d;
END $do$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r7() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._qa_node4_marche_r7_fxcore() FROM PUBLIC, anon, authenticated;
