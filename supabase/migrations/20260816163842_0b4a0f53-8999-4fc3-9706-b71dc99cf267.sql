DELETE FROM public._qa_s13_results WHERE part BETWEEN 900 AND 940;
INSERT INTO public._qa_s13_results(part, result)
SELECT 900, to_jsonb(t) FROM public._qa_node0_course() t;
INSERT INTO public._qa_s13_results(part, result)
SELECT 901, to_jsonb(t) FROM public._qa_node1_bonbonna_full() t;
INSERT INTO public._qa_s13_results(part, result)
SELECT 902, to_jsonb(t) FROM public._qa_node2_taxi_full() t;
INSERT INTO public._qa_s13_results(part, result)
SELECT 903, to_jsonb(t) FROM public._qa_node3_repas_r1_r4() t;
INSERT INTO public._qa_s13_results(part, result)
SELECT 904, to_jsonb(t) FROM public._qa_node3_repas_pickup() t;
INSERT INTO public._qa_s13_results(part, result)
SELECT 905, to_jsonb(t) FROM public._qa_node3_repas_r5_runtime() t;
INSERT INTO public._qa_s13_results(part, result)
SELECT 906, to_jsonb(t) FROM public._qa_node3_repas_r6_custody() t;
INSERT INTO public._qa_s13_results(part, result)
SELECT 907, to_jsonb(t) FROM public._qa_node3_repas_r7_tracking_receipt() t;
INSERT INTO public._qa_s13_results(part, result)
SELECT 908, to_jsonb(t) FROM public._qa_node3_repas_r8_discovery_truth() t;
INSERT INTO public._qa_s13_results(part, result)
SELECT 909, to_jsonb(t) FROM public._qa_node3_repas_r9_recovery_flows() t;
INSERT INTO public._qa_s13_results(part, result)
SELECT 910, to_jsonb(t) FROM public._qa_node3_repas_r10_operations() t;
INSERT INTO public._qa_s13_results(part, result)
SELECT 911, to_jsonb(t) FROM public._qa_node3_repas_r11_conakry_hardening() t;