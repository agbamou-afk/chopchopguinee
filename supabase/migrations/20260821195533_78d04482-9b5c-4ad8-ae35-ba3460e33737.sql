DO $mig$
DECLARE src text; def text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO def
    FROM pg_proc WHERE oid = 'public._qa_node5_identity_a14()'::regprocedure;
  def := replace(def, '  r := r || public._qa_s14_noop() IS NULL;' || E'\n', '');
  IF position('_qa_s14_noop' in def) > 0 THEN
    RAISE EXCEPTION 'stray line not removed';
  END IF;
  EXECUTE def;
END
$mig$;

REVOKE ALL ON FUNCTION public._qa_node5_identity_a14() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node5_identity_a14() TO service_role;
