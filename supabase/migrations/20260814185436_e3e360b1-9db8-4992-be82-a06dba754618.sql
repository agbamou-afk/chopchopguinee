INSERT INTO public._qa_s13_results(part, result)
SELECT 981, jsonb_build_object('labels', jsonb_path_query_array(v->'results','$[*].label'))
FROM (SELECT public._qa_node3_repas_r8_discovery() AS v) s;