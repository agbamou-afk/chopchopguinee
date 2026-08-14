DELETE FROM public._qa_s13_results WHERE part BETWEEN 900 AND 999;
INSERT INTO public._qa_s13_results(part, result) VALUES
 (900, public._qa_node0_course()),
 (901, public._qa_node1_bonbonna_full()),
 (902, public._qa_node2_taxi_full()),
 (903, public._qa_node3_repas_r1_r4()),
 (904, public._qa_node3_repas_pickup()),
 (905, (SELECT jsonb_agg(to_jsonb(x)) FROM public._qa_node3_repas_r5() x)),
 (906, public._qa_node3_repas_r5_runtime()),
 (907, public._qa_node3_repas_r7_tracking_receipt()),
 (908, public._qa_node3_repas_r6_custody()),
 (911, public._qa_s13_run1()),
 (912, public._qa_s13_run2()),
 (913, public._qa_s13_run3()),
 (914, public._qa_s13_run4()),
 (915, public._qa_s13_run5()),
 (916, public._qa_s13_run6()),
 (917, public._qa_s13_run7());