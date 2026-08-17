DELETE FROM public._qa_board_run2;
DO $$
DECLARE r jsonb;
BEGIN
  r := public._qa_node4_marche_r8();
  INSERT INTO public._qa_board_run2(suite,total,failed,err)
  VALUES ('_qa_node4_marche_r8', (r->>'total')::int, (r->>'failed')::int, left((r->'failures')::text, 6000));
EXCEPTION WHEN OTHERS THEN
  INSERT INTO public._qa_board_run2(suite,total,failed,err) VALUES ('_qa_node4_marche_r8',NULL,NULL,SQLERRM);
END $$;