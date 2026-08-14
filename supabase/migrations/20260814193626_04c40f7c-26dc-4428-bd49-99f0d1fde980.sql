INSERT INTO public._qa_s13_results(part, result)
SELECT 900, jsonb_build_object(
  'node0', public._qa_node0_course(),
  'node1', public._qa_node1_bonbonna_full(),
  'node2', public._qa_node2_taxi_full(),
  'r1_r4', public._qa_node3_repas_r1_r4(),
  'pickup', public._qa_node3_repas_pickup(),
  'r5', public._qa_node3_repas_r5(),
  'r5_runtime', public._qa_node3_repas_r5_runtime(),
  'r6', public._qa_node3_repas_r6_custody(),
  'r7', public._qa_node3_repas_r7_tracking_receipt(),
  'r8', public._qa_node3_repas_r8_discovery_truth()
);