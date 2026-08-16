DELETE FROM public._qa_s13_results WHERE part BETWEEN 9102 AND 9117;
INSERT INTO public._qa_s13_results(part, result) SELECT 9102, public._qa_node1_bonbonna_full();
INSERT INTO public._qa_s13_results(part, result) SELECT 9103, public._qa_node2_taxi_full();
INSERT INTO public._qa_s13_results(part, result) SELECT 9104, public._qa_node3_repas_r1_r4();
INSERT INTO public._qa_s13_results(part, result) SELECT 9105, public._qa_node3_repas_pickup();
INSERT INTO public._qa_s13_results(part, result)
SELECT 9106, coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) FROM public._qa_node3_repas_r5() t;
INSERT INTO public._qa_s13_results(part, result) SELECT 9107, public._qa_node3_repas_r5_runtime();
INSERT INTO public._qa_s13_results(part, result) SELECT 9108, public._qa_node3_repas_r6_custody();
INSERT INTO public._qa_s13_results(part, result) SELECT 9109, public._qa_node3_repas_r7_tracking_receipt();
INSERT INTO public._qa_s13_results(part, result) SELECT 9110, public._qa_node3_repas_r8_discovery_truth();
INSERT INTO public._qa_s13_results(part, result) SELECT 9111, public._qa_node3_repas_r8_core();
INSERT INTO public._qa_s13_results(part, result) SELECT 9112, public._qa_node3_repas_r8_channel();
INSERT INTO public._qa_s13_results(part, result) SELECT 9113, public._qa_node3_repas_r8_discovery();
INSERT INTO public._qa_s13_results(part, result) SELECT 9114, public._qa_node3_repas_r8_extra();
INSERT INTO public._qa_s13_results(part, result) SELECT 9115, public._qa_node3_repas_r9_recovery_flows();
INSERT INTO public._qa_s13_results(part, result) SELECT 9116, public._qa_node3_repas_r10_operations();
INSERT INTO public._qa_s13_results(part, result) SELECT 9117, public._qa_node3_repas_r11_conakry_hardening();