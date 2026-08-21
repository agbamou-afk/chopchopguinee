DO $do$
DECLARE fn text; res jsonb; acc jsonb := '[]'::jsonb;
  names text[] := ARRAY[
    '_qa_node0_course','_qa_node1_bonbonna','_qa_node1_bonbonna_sweeper','_qa_node1_bonbonna_matrix',
    '_qa_node1_bonbonna_full','_qa_node2_taxi_full',
    '_qa_s13_run1','_qa_s13_run2','_qa_s13_run3','_qa_s13_run4','_qa_s13_run5','_qa_s13_run6','_qa_s13_run7',
    '_qa_node3_repas_r1_r4','_qa_node3_repas_pickup','_qa_node3_repas_r5','_qa_node3_repas_r5_runtime',
    '_qa_node3_repas_r6_custody','_qa_node3_repas_r7_tracking_receipt','_qa_node3_repas_r8_discovery',
    '_qa_node3_repas_r8_channel','_qa_node3_repas_r8_core','_qa_node3_repas_r8_extra',
    '_qa_node3_repas_r8_discovery_truth','_qa_node3_repas_r9_recovery_flows',
    '_qa_node3_repas_r10_operations','_qa_node3_repas_r11_conakry_hardening'];
BEGIN
  FOREACH fn IN ARRAY names LOOP
    EXECUTE format('SELECT to_jsonb(t) FROM public.%I() t', fn) INTO res;
    acc := acc || jsonb_build_object('suite', fn, 'total', res->'total', 'failed', res->'failed',
                                     'failures', COALESCE(res->'failures','[]'::jsonb));
  END LOOP;
  INSERT INTO public._qa_s13_results(part, result) VALUES (940, jsonb_build_object('board', acc));
END $do$;