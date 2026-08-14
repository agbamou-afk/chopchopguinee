INSERT INTO public._qa_s13_results(part, result)
SELECT 980, jsonb_build_object(
  'total', v->>'total',
  'failed', v->>'failed',
  'failures', (SELECT jsonb_agg(e) FROM jsonb_array_elements(v->'results') e WHERE (e->>'ok')::boolean IS NOT TRUE)
) FROM (SELECT public._qa_node3_repas_r8_discovery() AS v) s;