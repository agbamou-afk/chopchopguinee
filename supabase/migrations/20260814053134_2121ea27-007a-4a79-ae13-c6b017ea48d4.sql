DELETE FROM public._qa_s13_results WHERE part = 351;
INSERT INTO public._qa_s13_results(part, result)
VALUES (351, public._qa_node3_repas_r5_runtime());