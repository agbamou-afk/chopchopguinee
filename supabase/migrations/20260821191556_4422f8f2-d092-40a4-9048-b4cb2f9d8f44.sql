
DO $mig$
DECLARE v_src text; v_new text;
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid='public._qa_node5_identity_a13()'::regprocedure;
  v_new := replace(v_src,
    'WHERE user_id = ANY(ids) OR driver_user_id = ANY(ids);',
    'WHERE driver_user_id = ANY(ids) OR party_user_id = ANY(ids);');
  IF v_new = v_src THEN RAISE EXCEPTION 'A13_PATCH_NO_MATCH'; END IF;
  EXECUTE format(
    'CREATE OR REPLACE FUNCTION public._qa_node5_identity_a13() RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER SET search_path TO ''public'' SET statement_timeout TO ''300s'' AS %L',
    v_new);
END $mig$;
REVOKE ALL ON FUNCTION public._qa_node5_identity_a13() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node5_identity_a13() TO service_role;
