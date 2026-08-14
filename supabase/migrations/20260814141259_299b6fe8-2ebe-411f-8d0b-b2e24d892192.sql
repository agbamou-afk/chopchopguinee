DO $do$
DECLARE v_def text; v_new text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node3_repas_r7_ext';
  v_new := replace(v_def, 'v_t->''mission''::text)', '(v_t->''mission'')::text)');
  v_new := replace(v_new, 'v_rc->''custody_timeline''::text LIKE', '(v_rc->''custody_timeline'')::text LIKE');
  v_new := replace(v_new, 'AND v_rc->''custody_timeline''::text LIKE', 'AND (v_rc->''custody_timeline'')::text LIKE');
  IF v_new = v_def THEN RAISE EXCEPTION 'no anchor'; END IF;
  EXECUTE v_new;
  EXECUTE 'REVOKE ALL ON FUNCTION public._qa_node3_repas_r7_ext() FROM PUBLIC, anon, authenticated';
END
$do$;