DROP TABLE IF EXISTS public._qa_board_run;
CREATE TABLE public._qa_board_run(suite text primary key, result jsonb, err text);
DO $do$
DECLARE s text; v jsonb;
BEGIN
  FOREACH s IN ARRAY ARRAY[
    '_qa_node0_course','_qa_node1_bonbonna_full','_qa_node2_taxi_full',
    '_qa_node3_repas_r1_r4','_qa_node3_repas_r5','_qa_node3_repas_r5_runtime',
    '_qa_node3_repas_r6_custody','_qa_node3_repas_r7_tracking_receipt','_qa_node3_repas_r7_semantics',
    '_qa_node3_repas_r7_readtruth','_qa_node3_repas_r7_ext','_qa_node3_repas_r8_discovery',
    '_qa_node3_repas_r8_discovery_truth','_qa_node3_repas_r8_channel','_qa_node3_repas_r8_extra',
    '_qa_node3_repas_r9_recovery_flows','_qa_node3_repas_r10_operations',
    '_qa_node3_repas_r11_conakry_hardening','_qa_node3_repas_pickup',
    '_qa_s13_run1','_qa_s13_run2','_qa_s13_run3','_qa_s13_run4','_qa_s13_run5','_qa_s13_run6','_qa_s13_run7',
    '_qa_node4_marche_r1','_qa_node4_marche_r15','_qa_node4_marche_r2','_qa_node4_marche_r3',
    '_qa_node4_marche_r35','_qa_node4_marche_r4','_qa_node4_marche_r5','_qa_node4_marche_r6'
  ] LOOP
    BEGIN
      EXECUTE format('SELECT to_jsonb(public.%I())', s) INTO v;
      INSERT INTO public._qa_board_run(suite,result,err) VALUES (s, v, NULL);
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO public._qa_board_run(suite,result,err) VALUES (s, NULL, SQLERRM);
    END;
  END LOOP;
END $do$;
SELECT suite, err, (result->>'passed') passed, (result->>'failed') failed, result->'failures' failures
FROM public._qa_board_run WHERE err IS NOT NULL OR (result->>'failed')::int > 0;