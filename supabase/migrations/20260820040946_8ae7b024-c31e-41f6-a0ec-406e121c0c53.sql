DO $$
DECLARE r jsonb; fn text; tot int := 0; fail int := 0; det jsonb := '[]'::jsonb;
BEGIN
  DELETE FROM public._qa_s13_results WHERE part = 4104;
  FOR fn IN SELECT p.proname FROM pg_proc p
      WHERE p.pronamespace='public'::regnamespace
        AND p.pronargs = 0
        AND (p.proname LIKE '\_qa\_node%' OR p.proname LIKE '\_qa\_s13%')
        AND p.proname NOT LIKE '%fxcore' AND p.proname NOT LIKE '%\_core'
        AND p.proname NOT IN ('_qa_node4_probe')
      ORDER BY 1
  LOOP
    BEGIN
      EXECUTE format('SELECT public.%I()', fn) INTO r;
      tot := tot + COALESCE((r->>'total')::int, (r->>'passed')::int, 0);
      fail := fail + COALESCE((r->>'failed')::int, 0);
      det := det || jsonb_build_object('fn', fn, 'passed', r->>'passed', 'failed', r->>'failed', 'total', r->>'total');
    EXCEPTION WHEN OTHERS THEN
      fail := fail + 1;
      det := det || jsonb_build_object('fn', fn, 'error', SQLERRM);
    END;
  END LOOP;
  INSERT INTO public._qa_s13_results(part, result)
  VALUES (4104, jsonb_build_object('total', tot, 'failed', fail, 'detail', det));
END $$;