DELETE FROM public._qa_s13_results WHERE part >= 900;
INSERT INTO public._qa_s13_results(part, result) VALUES
 (900, public._qa_node4_marche_r1()),
 (901, public._qa_node0_course()),
 (902, public._qa_node1_bonbonna_full()),
 (903, public._qa_node2_taxi_full()),
 (904, public._qa_node3_repas_r1_r4()),
 (905, public._qa_node3_repas_pickup()),
 (906, public._qa_node3_repas_r5_runtime()),
 (907, public._qa_node3_repas_r6_custody()),
 (908, public._qa_node3_repas_r7_tracking_receipt()),
 (909, public._qa_node3_repas_r8_discovery()),
 (910, public._qa_node3_repas_r9_recovery_flows()),
 (911, public._qa_node3_repas_r10_operations()),
 (912, public._qa_node3_repas_r11_conakry_hardening()),
 (913, public._qa_s13_run1()),
 (914, public._qa_s13_run2()),
 (915, public._qa_s13_run3()),
 (916, public._qa_s13_run4()),
 (917, public._qa_s13_run5()),
 (918, public._qa_s13_run6()),
 (919, public._qa_s13_run7());
INSERT INTO public._qa_s13_results(part, result)
SELECT 920, jsonb_build_object('total', count(*), 'failed', count(*) FILTER (WHERE NOT ok))
FROM public._qa_node3_repas_r5();