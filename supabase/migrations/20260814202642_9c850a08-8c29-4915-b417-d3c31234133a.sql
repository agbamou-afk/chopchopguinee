DELETE FROM public._qa_s13_results WHERE part = 1010;
INSERT INTO public._qa_s13_results(part, result)
VALUES (1010, public._qa_node3_repas_r10_operations());