DELETE FROM public._qa_s13_results WHERE part IN (415, 410);
INSERT INTO public._qa_s13_results(part, result) VALUES (415, public._qa_node4_marche_r15());
INSERT INTO public._qa_s13_results(part, result) VALUES (410, public._qa_node4_marche_r1());