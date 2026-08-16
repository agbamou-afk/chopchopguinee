SELECT jsonb_build_object(
 'r1_r4', (SELECT jsonb_agg(e) FROM jsonb_array_elements(coalesce(to_jsonb(public._qa_node3_repas_r1_r4())->'failures', to_jsonb(public._qa_node3_repas_r1_r4())->'results')) e WHERE (e->>'ok')::boolean IS NOT TRUE),
 'custody', (SELECT jsonb_agg(e) FROM jsonb_array_elements(coalesce(to_jsonb(public._qa_node3_repas_r6_custody())->'failures', to_jsonb(public._qa_node3_repas_r6_custody())->'results')) e WHERE (e->>'ok')::boolean IS NOT TRUE),
 'tracking', (SELECT jsonb_agg(e) FROM jsonb_array_elements(coalesce(to_jsonb(public._qa_node3_repas_r7_tracking_receipt())->'failures', to_jsonb(public._qa_node3_repas_r7_tracking_receipt())->'results')) e WHERE (e->>'ok')::boolean IS NOT TRUE)
) AS d;