DO $do$
DECLARE v_def text; v_new text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node3_repas_r7_ext';
  v_new := replace(v_def, '(v_rc->''custody_timeline'')::text LIKE ''%restaurant_handoff%''',
                          '(v_rc->''custody_timeline'')::text LIKE ''%restaurant_to_courier%''');
  v_new := replace(v_new, 'AND (v_rc->''custody_timeline'')::text LIKE ''%customer_delivery%''',
                          'AND (v_rc->''custody_timeline'')::text LIKE ''%courier_to_customer%''');
  IF v_new = v_def THEN RAISE EXCEPTION 'no anchor'; END IF;
  EXECUTE v_new;
  EXECUTE 'REVOKE ALL ON FUNCTION public._qa_node3_repas_r7_ext() FROM PUBLIC, anon, authenticated';
END
$do$;