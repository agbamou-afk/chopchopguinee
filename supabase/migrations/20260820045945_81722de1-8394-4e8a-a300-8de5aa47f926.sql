DO $run$
DECLARE
  v_suites text[] := ARRAY['_qa_node0_course','_qa_node1_bonbonna_full','_qa_node2_taxi_full',
    '_qa_node3_repas_r1_r4','_qa_node3_repas_pickup','_qa_node3_repas_r5','_qa_node3_repas_r5_runtime',
    '_qa_node3_repas_r6_custody','_qa_node3_repas_r7_tracking_receipt','_qa_node3_repas_r8_discovery',
    '_qa_node3_repas_r9_recovery_flows','_qa_node3_repas_r10_operations','_qa_node3_repas_r11_conakry_hardening',
    '_qa_s13_run1','_qa_s13_run2','_qa_s13_run3','_qa_s13_run4','_qa_s13_run5','_qa_s13_run6','_qa_s13_run7'];
  s text; v_out jsonb; v_arr jsonb; v_fail jsonb; v_total int;
BEGIN
  DELETE FROM public._qa_s13_results WHERE part = 412;
  FOREACH s IN ARRAY v_suites LOOP
    BEGIN
      EXECUTE format('SELECT public.%I()', s) INTO v_out;
      v_arr := CASE
        WHEN jsonb_typeof(v_out) = 'array' THEN v_out
        WHEN jsonb_typeof(v_out->'results') = 'array' THEN v_out->'results'
        ELSE NULL END;
      IF v_arr IS NULL THEN
        INSERT INTO public._qa_s13_results(part, result)
        VALUES (412, jsonb_build_object('suite', s, 'summary', v_out));
      ELSE
        SELECT count(*), COALESCE(jsonb_agg(x) FILTER (WHERE (x->>'ok')::boolean IS NOT TRUE), '[]'::jsonb)
          INTO v_total, v_fail FROM jsonb_array_elements(v_arr) x;
        INSERT INTO public._qa_s13_results(part, result)
        VALUES (412, jsonb_build_object('suite', s, 'total', v_total,
          'failed', jsonb_array_length(v_fail), 'failures', v_fail));
      END IF;
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO public._qa_s13_results(part, result)
      VALUES (412, jsonb_build_object('suite', s, 'error', SQLERRM));
    END;
  END LOOP;
END $run$;
