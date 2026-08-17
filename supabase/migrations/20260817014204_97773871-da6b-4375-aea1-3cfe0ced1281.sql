TRUNCATE public._qa_board_run2;
DO $$
DECLARE s text; v jsonb;
  suites text[] := ARRAY[
    '_qa_node0_course','_qa_node1_bonbonna_full','_qa_node2_taxi_full',
    '_qa_node3_repas_pickup','_qa_node3_repas_r1_r4','_qa_node3_repas_r5',
    '_qa_node3_repas_r5_runtime','_qa_node3_repas_r6_custody',
    '_qa_node3_repas_r7_tracking_receipt','_qa_node3_repas_r8_discovery_truth',
    '_qa_node3_repas_r9_recovery_flows','_qa_node3_repas_r10_operations',
    '_qa_node3_repas_r11_conakry_hardening',
    '_qa_s13_run1','_qa_s13_run2','_qa_s13_run3','_qa_s13_run4','_qa_s13_run5','_qa_s13_run6','_qa_s13_run7',
    '_qa_node4_marche_r1','_qa_node4_marche_r15','_qa_node4_marche_r2','_qa_node4_marche_r3',
    '_qa_node4_marche_r35','_qa_node4_marche_r4','_qa_node4_marche_r5','_qa_node4_marche_r6',
    '_qa_node4_marche_r65'];
BEGIN
  FOREACH s IN ARRAY suites LOOP
    BEGIN
      EXECUTE format('SELECT public.%I()', s) INTO v;
      INSERT INTO public._qa_board_run2(suite,total,failed,err)
      VALUES (s, COALESCE((v->>'total')::int,(v->>'total_assertions')::int),
                 COALESCE((v->>'failed')::int,(v->>'failures')::int), NULL);
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO public._qa_board_run2(suite,total,failed,err) VALUES (s,NULL,NULL,SQLERRM);
    END;
  END LOOP;
END $$;