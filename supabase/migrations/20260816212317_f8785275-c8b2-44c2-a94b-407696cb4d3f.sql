DO $$
BEGIN
  PERFORM public._qa_node0_course();
  PERFORM public._qa_node1_bonbonna_full();
  PERFORM public._qa_node2_taxi_full();
  PERFORM public._qa_node3_repas_r1_r4();
  PERFORM public._qa_node3_repas_pickup();
  PERFORM public._qa_node3_repas_r5();
  PERFORM public._qa_node3_repas_r5_runtime();
  PERFORM public._qa_node3_repas_r6_custody();
  PERFORM public._qa_node3_repas_r7_tracking_receipt();
END $$;