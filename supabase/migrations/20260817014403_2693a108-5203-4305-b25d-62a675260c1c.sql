DELETE FROM public._qa_board_run2 WHERE suite IN ('_qa_node3_repas_r5','_qa_node4_marche_r5');
DO $$
DECLARE v jsonb; t int; f int;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE NOT ok) INTO t,f FROM public._qa_node3_repas_r5();
  INSERT INTO public._qa_board_run2(suite,total,failed,err) VALUES ('_qa_node3_repas_r5',t,f,NULL);

  v := public._qa_node4_marche_r5();
  SELECT count(*), count(*) FILTER (WHERE COALESCE((e->>'ok')::boolean, (e->>'pass')::boolean, false) IS NOT TRUE)
    INTO t,f FROM jsonb_array_elements(v) e;
  INSERT INTO public._qa_board_run2(suite,total,failed,err) VALUES ('_qa_node4_marche_r5',t,f,NULL);
END $$;