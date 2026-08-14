DO $mig$
DECLARE v_i int; v_res jsonb; v_rows jsonb; v_total int; v_failed int;
BEGIN
  FOR v_i IN 4..7 LOOP
    EXECUTE format('SELECT public._qa_s13_run%s()', v_i) INTO v_res;
    v_rows := CASE WHEN jsonb_typeof(v_res) = 'array' THEN v_res
                   WHEN jsonb_typeof(v_res->'results') = 'array' THEN v_res->'results'
                   ELSE '[]'::jsonb END;
    IF jsonb_array_length(v_rows) > 0 THEN
      SELECT count(*)::int, count(*) FILTER (WHERE (e->>'ok')::boolean IS NOT TRUE)::int
        INTO v_total, v_failed FROM jsonb_array_elements(v_rows) e;
    ELSE
      v_total := COALESCE((v_res->>'total')::int, 0);
      v_failed := COALESCE((v_res->>'failed')::int, 0);
    END IF;
    INSERT INTO public._qa_s13_results(part, result) VALUES (v_i, v_rows);
    INSERT INTO public._qa_s13_results(part, result)
      VALUES (v_i, jsonb_build_object('part', v_i, 'total', v_total, 'failed', v_failed,
                                      'passed', v_total - v_failed));
    RAISE NOTICE 'part % total % failed %', v_i, v_total, v_failed;
  END LOOP;
END
$mig$;