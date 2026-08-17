TRUNCATE public._qa_r65_trace;
DELETE FROM public._qa_board_run2 WHERE suite = '_qa_node4_marche_r65';
DO $$
DECLARE v jsonb;
BEGIN
  v := public._qa_node4_marche_r65();
  INSERT INTO public._qa_r65_trace(ok,label,detail)
  SELECT (e->>'ok')::boolean, e->>'label', e->>'detail'
    FROM jsonb_array_elements(COALESCE(v->'results', v->'failures','[]'::jsonb)) e;
  INSERT INTO public._qa_board_run2(suite,total,failed,err)
  VALUES ('_qa_node4_marche_r65', (v->>'total')::int, (v->>'failed')::int,
          left(COALESCE(v->'failures','[]'::jsonb)::text, 6000));
EXCEPTION WHEN OTHERS THEN
  INSERT INTO public._qa_board_run2(suite,total,failed,err)
  VALUES ('_qa_node4_marche_r65', -1, -1, SQLERRM);
END $$;