DELETE FROM public._qa_s13_results WHERE part BETWEEN 2000 AND 2099;
INSERT INTO public._qa_s13_results(part, result) VALUES
 (2011, public._qa_node3_repas_r11_conakry_hardening()),
 (2010, public._qa_node3_repas_r10_operations()),
 (2009, public._qa_node3_repas_r9_recovery_flows()),
 (2008, public._qa_node3_repas_r8_discovery_truth()),
 (2007, public._qa_node3_repas_r7_tracking_receipt()),
 (2006, public._qa_node3_repas_r6_custody()),
 (2004, public._qa_node3_repas_r5_runtime()),
 (2003, public._qa_node3_repas_pickup()),
 (2002, public._qa_node3_repas_r1_r4()),
 (2020, public._qa_node0_course()),
 (2021, public._qa_node1_bonbonna_full()),
 (2022, public._qa_node2_taxi_full()),
 (2031, public._qa_s13_run1()),
 (2032, public._qa_s13_run2()),
 (2033, public._qa_s13_run3()),
 (2034, public._qa_s13_run4()),
 (2035, public._qa_s13_run5()),
 (2036, public._qa_s13_run6()),
 (2037, public._qa_s13_run7());

INSERT INTO public._qa_s13_results(part, result)
SELECT 2005, jsonb_build_object(
  'suite','node3_repas_r5_static',
  'total', count(*),
  'failed', count(*) FILTER (WHERE NOT ok),
  'fails', coalesce(jsonb_agg(name) FILTER (WHERE NOT ok), '[]'::jsonb))
FROM public._qa_node3_repas_r5();