DELETE FROM public._qa_board_run2;
DO $$
DECLARE f record; j jsonb; arr jsonb; t int; fl int;
BEGIN
  FOR f IN
    SELECT n.nspname||'.'||quote_ident(p.proname) AS fn, p.proname AS nm
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.pronargs = 0
       AND p.prorettype = 'jsonb'::regtype
       AND p.proname LIKE '\_qa\_node%'
       AND p.proname NOT LIKE '%\_fxcore'
       AND p.proname <> '_qa_node4_probe'
     ORDER BY 1
  LOOP
    BEGIN
      EXECUTE format('SELECT %s()', f.fn) INTO j;
      arr := CASE WHEN jsonb_typeof(j)='array' THEN j ELSE COALESCE(j->'results', j->'failures', '[]'::jsonb) END;
      SELECT count(*), count(*) FILTER (WHERE (x->>'ok')::boolean IS FALSE) INTO t, fl
        FROM jsonb_array_elements(arr) x;
      IF jsonb_typeof(j) = 'object' AND (j ? 'total') THEN
        t := (j->>'total')::int;
        fl := COALESCE((j->>'failed')::int, fl);
      END IF;
      INSERT INTO public._qa_board_run2(suite, total, failed, err)
      VALUES (f.nm, t, fl,
        (SELECT string_agg(x->>'label', ' | ') FROM jsonb_array_elements(arr) x WHERE (x->>'ok')::boolean IS FALSE));
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO public._qa_board_run2(suite, total, failed, err) VALUES (f.nm, NULL, NULL, 'ABORT: '||SQLERRM);
    END;
  END LOOP;
END $$;