GRANT EXECUTE ON FUNCTION public._qa_node4_marche_r8_core() TO PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public._qa_node4_marche_r8_j() TO PUBLIC, anon, authenticated, service_role;
ALTER FUNCTION public._qa_node4_marche_r8_core() SET search_path TO 'public';
ALTER FUNCTION public._qa_node4_marche_r8_j() SET search_path TO 'public';
ALTER FUNCTION public._qa_node4_marche_r8() SET search_path TO 'public';