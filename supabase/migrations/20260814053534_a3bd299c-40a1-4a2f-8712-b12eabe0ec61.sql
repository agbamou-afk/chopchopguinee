DELETE FROM public._qa_s13_results WHERE part BETWEEN 300 AND 399;
INSERT INTO public._qa_s13_results(part, result)
SELECT 352, jsonb_build_object('part','node3_repas_r5_static',
  'total', count(*), 'failed', count(*) FILTER (WHERE NOT ok),
  'results', jsonb_agg(jsonb_build_object('label', section||' '||name, 'ok', ok, 'detail', detail)))
FROM public._qa_node3_repas_r5();
INSERT INTO public._qa_s13_results(part, result) VALUES
 (353, public._qa_node3_repas_pickup()),
 (354, public._qa_node3_repas_r1_r4()),
 (355, public._qa_node0_course()),
 (356, public._qa_node1_bonbonna_full()),
 (357, public._qa_node1_bonbonna()),
 (358, public._qa_node1_bonbonna_matrix()),
 (359, public._qa_node1_bonbonna_sweeper()),
 (360, public._qa_node2_taxi_full()),
 (361, public._qa_s13_run1()),
 (362, public._qa_s13_run2()),
 (363, public._qa_s13_run3()),
 (364, public._qa_s13_run4()),
 (365, public._qa_s13_run5()),
 (366, public._qa_s13_run6()),
 (367, public._qa_s13_run7()),
 (351, public._qa_node3_repas_r5_runtime());