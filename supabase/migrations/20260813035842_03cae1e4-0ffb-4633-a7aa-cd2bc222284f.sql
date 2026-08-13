WITH x AS (SELECT public._qa_node1_bonbonna_full() j)
SELECT j->>'total' total, j->>'failed' failed,
 (SELECT jsonb_agg(e) FROM jsonb_array_elements(j->'results') e WHERE (e->>'ok')::boolean IS NOT TRUE) fails
FROM x;