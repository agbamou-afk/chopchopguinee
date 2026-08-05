DO $mig$
DECLARE src text; newsrc text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO src FROM pg_proc WHERE proname = '_qa_s1c_inner';
  newsrc := replace(src, E'    PERFORM set_config(''role'',''authenticated'', true);\n', '');
  IF newsrc = src THEN RAISE EXCEPTION 'role lines not found'; END IF;
  EXECUTE newsrc;
END $mig$;