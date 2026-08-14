DO $$
DECLARE v jsonb;
BEGIN
  v := public._qa_node4_marche_r1();
  RAISE NOTICE 'NODE4_R1 %', v;
  INSERT INTO public._qa_s13_results(part, result) VALUES (9941, v);
END $$;