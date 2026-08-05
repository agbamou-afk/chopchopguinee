DO $mig$
DECLARE src text; newsrc text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO src FROM pg_proc WHERE proname = '_qa_s1c_inner';
  newsrc := replace(src,
    E'  r := public.driver_mission_commission_capture(''ride'', s1, 100000);',
    E'  PERFORM set_config(''request.jwt.claims'', '''', true);\n  r := public.driver_mission_commission_capture(''ride'', s1, 100000);');
  IF newsrc = src THEN RAISE EXCEPTION 'anchor not found'; END IF;
  EXECUTE newsrc;
END $mig$;