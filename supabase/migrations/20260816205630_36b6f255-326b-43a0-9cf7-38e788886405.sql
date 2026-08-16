DELETE FROM public._qa_s13_results WHERE part BETWEEN 900 AND 999;
DO $board$
DECLARE n text; i int := 900;
BEGIN
  FOREACH n IN ARRAY ARRAY[
    '_qa_node0_course','_qa_node1_bonbonna_full','_qa_node2_taxi_full','_qa_node3_repas_r1_r4',
    '_qa_node3_repas_pickup','_qa_node3_repas_r5','_qa_node3_repas_r5_runtime','_qa_node3_repas_r6_custody',
    '_qa_node3_repas_r7_tracking_receipt','_qa_node3_repas_r8_discovery_truth','_qa_node3_repas_r8_core',
    '_qa_node3_repas_r8_channel','_qa_node3_repas_r8_discovery','_qa_node3_repas_r8_extra',
    '_qa_node3_repas_r9_recovery_flows','_qa_node3_repas_r10_operations','_qa_node3_repas_r11_conakry_hardening',
    '_qa_s13_run1','_qa_s13_run2','_qa_s13_run3','_qa_s13_run4','_qa_s13_run5','_qa_s13_run6','_qa_s13_run7',
    '_qa_node4_marche_r1','_qa_node4_marche_r15','_qa_node4_marche_r2','_qa_node4_marche_r3','_qa_node4_marche_r35'
  ] LOOP
    EXECUTE format(
      'INSERT INTO public._qa_s13_results(part, result) SELECT %s, jsonb_build_object(''suite'', %L, ''out'', (SELECT jsonb_agg(to_jsonb(t)) FROM public.%I() t))',
      i, n, n);
    i := i + 1;
  END LOOP;
END $board$;