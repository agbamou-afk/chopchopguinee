DO $mig$
DECLARE src text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO src
    FROM pg_proc WHERE oid='public._qa_node4_marche_r9_backlink()'::regprocedure;
  src := replace(src, 'state=''delivering''', 'state=''heading_to_dropoff''');
  EXECUTE src;
END $mig$;