DO $$
DECLARE f text; v jsonb; agg jsonb := '[]'::jsonb;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    '_qa_node0_course','_qa_node1_bonbonna_full','_qa_node2_taxi_full',
    '_qa_node3_repas_r1_r4','_qa_node3_repas_pickup','_qa_node3_repas_r5',
    '_qa_node3_repas_r5_runtime','_qa_node3_repas_r6_custody',
    '_qa_node3_repas_r7_tracking_receipt','_qa_node3_repas_r8_discovery',
    '_qa_node3_repas_r9_recovery_flows','_qa_node3_repas_r10_operations',
    '_qa_node3_repas_r11_conakry_hardening','_qa_node4_marche_r1',
    '_qa_s13_run1','_qa_s13_run2','_qa_s13_run3','_qa_s13_run4','_qa_s13_run5','_qa_s13_run6','_qa_s13_run7'
  ] LOOP
    EXECUTE format('SELECT to_jsonb(public.%I())', f) INTO v;
    agg := agg || jsonb_build_object('suite', f, 'total', v->'total', 'passed', v->'passed',
                                     'failed', v->'failed', 'failures', v->'failures');
  END LOOP;
  INSERT INTO public._qa_s13_results(part, result) VALUES (9950, agg);
END $$;