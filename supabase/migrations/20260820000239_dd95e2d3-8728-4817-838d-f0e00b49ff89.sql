DELETE FROM public._qa_board_run2;
DO $$
DECLARE f record; j jsonb;
BEGIN
  FOR f IN
    SELECT n.nspname||'.'||quote_ident(p.proname) AS fn, p.proname AS nm
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.pronargs = 0
       AND p.prorettype = 'jsonb'::regtype
       AND (p.proname LIKE '\_qa\_node%' OR p.proname LIKE '\_qa\_s13\_suite%' OR p.proname LIKE '\_qa\_slice%')
       AND p.proname NOT LIKE '%\_fxcore'
     ORDER BY 1
  LOOP
    BEGIN
      EXECUTE format('SELECT %s()', f.fn) INTO j;
      INSERT INTO public._qa_board_run2(suite, total, failed, err)
      VALUES (f.nm, (j->>'total')::int, (j->>'failed')::int, NULL);
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO public._qa_board_run2(suite, total, failed, err) VALUES (f.nm, NULL, NULL, SQLERRM);
    END;
  END LOOP;
END $$;