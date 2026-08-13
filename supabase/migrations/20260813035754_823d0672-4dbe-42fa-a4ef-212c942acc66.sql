SELECT jsonb_build_object(
  'total', (public._qa_node1_bonbonna_full())->>'total',
  'failed', (public._qa_node1_bonbonna_full())->>'failed'
) AS node1;