DO $$
BEGIN
  PERFORM public._qa_node4_marche_r1();
  PERFORM public._qa_node4_marche_r15();
  PERFORM public._qa_node4_marche_r2();
END $$;