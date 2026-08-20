DO $run$
BEGIN
  DELETE FROM public._qa_s13_results WHERE part IN (9101, 9108);
  INSERT INTO public._qa_s13_results(part, result) VALUES (9101, public._qa_node4_marche_r1());
  INSERT INTO public._qa_s13_results(part, result) VALUES (9108, public._qa_node4_marche_r8());
END $run$;