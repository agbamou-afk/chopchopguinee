SELECT jsonb_agg(e) AS failures
FROM jsonb_array_elements((public._qa_node1_bonbonna_full())->'results') e
WHERE (e->>'ok')::boolean IS NOT TRUE;