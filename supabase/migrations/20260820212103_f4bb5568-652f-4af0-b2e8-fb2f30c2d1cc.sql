INSERT INTO public._qa_s13_results(part, result)
SELECT 601, jsonb_build_object('fn','_qa_node4_marche_r14') || (public._qa_node4_marche_r14() - 'results')
UNION ALL SELECT 602, jsonb_build_object('fn','_qa_node4_marche_r13') || (public._qa_node4_marche_r13() - 'results')
UNION ALL SELECT 603, jsonb_build_object('fn','_qa_node4_marche_r1')  || (public._qa_node4_marche_r1()  - 'results')
UNION ALL SELECT 604, jsonb_build_object('fn','_qa_node0_course')     || (public._qa_node0_course()     - 'results');