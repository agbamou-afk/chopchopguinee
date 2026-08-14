DO $$
DECLARE v jsonb;
BEGIN
  v := public._qa_node4_marche_r1();
  INSERT INTO public._qa_s13_results(part, result) VALUES (9943, v);
END $$;