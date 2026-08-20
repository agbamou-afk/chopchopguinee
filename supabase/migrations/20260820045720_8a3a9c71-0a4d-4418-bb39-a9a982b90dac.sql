-- Restore correct grants: no PUBLIC execute on QA functions.
DO $g$
DECLARE f record;
BEGIN
  FOR f IN
    SELECT oid::regprocedure::text AS sig FROM pg_proc
     WHERE pronamespace = 'public'::regnamespace AND proname LIKE '\_qa\_%'
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', f.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO postgres, service_role', f.sig);
  END LOOP;
END $g$;

-- Run the frozen Marché board and persist the outcome.
DO $run$
DECLARE
  v_suites text[] := ARRAY['_qa_node4_marche_r1','_qa_node4_marche_r15','_qa_node4_marche_r2',
    '_qa_node4_marche_r3','_qa_node4_marche_r35','_qa_node4_marche_r4','_qa_node4_marche_r5',
    '_qa_node4_marche_r6','_qa_node4_marche_r65','_qa_node4_marche_r7','_qa_node4_marche_r8',
    '_qa_node4_marche_r9','_qa_node4_marche_r10','_qa_node4_marche_r11'];
  s text; v_out jsonb; v_arr jsonb; v_fail jsonb; v_total int;
BEGIN
  DELETE FROM public._qa_s13_results WHERE part = 411;
  FOREACH s IN ARRAY v_suites LOOP
    BEGIN
      EXECUTE format('SELECT public.%I()', s) INTO v_out;
      v_arr := CASE
        WHEN jsonb_typeof(v_out) = 'array' THEN v_out
        WHEN jsonb_typeof(v_out->'results') = 'array' THEN v_out->'results'
        ELSE NULL END;
      IF v_arr IS NULL THEN
        INSERT INTO public._qa_s13_results(part, result)
        VALUES (411, jsonb_build_object('suite', s, 'summary', v_out));
      ELSE
        SELECT count(*), COALESCE(jsonb_agg(x) FILTER (WHERE (x->>'ok')::boolean IS NOT TRUE), '[]'::jsonb)
          INTO v_total, v_fail FROM jsonb_array_elements(v_arr) x;
        INSERT INTO public._qa_s13_results(part, result)
        VALUES (411, jsonb_build_object('suite', s, 'total', v_total,
          'failed', jsonb_array_length(v_fail), 'failures', v_fail));
      END IF;
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO public._qa_s13_results(part, result)
      VALUES (411, jsonb_build_object('suite', s, 'error', SQLERRM));
    END;
  END LOOP;
END $run$;
