DO $$
DECLARE r jsonb; p int; fails int; total int;
BEGIN
  FOR p IN 4..7 LOOP
    EXECUTE format('SELECT public._qa_s13_run%s()', p) INTO r;
    INSERT INTO public._qa_s13_results(part, result) VALUES (p, r);
    IF jsonb_typeof(r) = 'array' THEN
      SELECT count(*) FILTER (WHERE (x->>'ok')::boolean IS NOT TRUE), count(*)
        INTO fails, total FROM jsonb_array_elements(r) x;
    ELSE
      fails := COALESCE((r->>'failed')::int, 0);
      total := COALESCE((r->>'total')::int, 0);
    END IF;
    RAISE NOTICE 'S13 part % => total % failed %', p, total, fails;
    IF fails > 0 THEN RAISE EXCEPTION 'S13 part % FAILED (% of %)', p, fails, total; END IF;
  END LOOP;
END $$;