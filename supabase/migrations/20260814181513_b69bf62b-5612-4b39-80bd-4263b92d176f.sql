DO $mig$
DECLARE
  v_def text;
  v_old text := '  r := r || public._qa_node3_repas_r7_semantics();
  PERFORM set_config(''request.jwt.claims'', ''''::text, true);
  RETURN r;';
  v_new text := '  r := r || public._qa_node3_repas_r7_semantics();
  PERFORM set_config(''request.jwt.claims'', ''''::text, true);
  r := r || public._qa_node3_repas_r7_readtruth();
  PERFORM set_config(''request.jwt.claims'', ''''::text, true);
  RETURN r;';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = '_qa_node3_repas_r7_ext';
  IF v_def IS NULL THEN RAISE EXCEPTION 'R7_EXT_MISSING'; END IF;
  IF position(v_old in v_def) = 0 THEN RAISE EXCEPTION 'R7_EXT_TAIL_NOT_FOUND'; END IF;
  IF position('_qa_node3_repas_r7_readtruth' in v_def) > 0 THEN RETURN; END IF;
  EXECUTE replace(v_def, v_old, v_new);
END
$mig$;