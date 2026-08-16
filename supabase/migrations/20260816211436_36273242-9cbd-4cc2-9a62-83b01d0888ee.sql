DELETE FROM public._qa_s13_results WHERE part IN (32, 34);
DO $$
BEGIN
  PERFORM public._qa_node4_marche_r4();
  PERFORM public._qa_node4_marche_r3();
  PERFORM public._qa_node4_marche_r35();
END $$;