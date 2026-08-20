DELETE FROM public._qa_s13_results WHERE part=411;
DO $do$
DECLARE p record; res jsonb;
BEGIN
  FOR p IN SELECT oid::regprocedure::text sig, proname FROM pg_proc
           WHERE proname ~ '^_qa_node4_marche_r[0-9]+$' AND pronargs=0 ORDER BY proname
  LOOP
    EXECUTE format('SELECT %s', p.sig) INTO res;
    INSERT INTO public._qa_s13_results(part, result)
      VALUES (900, jsonb_build_object('suite', p.proname, 'r', res));
  END LOOP;
END $do$;