DELETE FROM public._qa_s13_results WHERE part = 941;
INSERT INTO public._qa_s13_results(part, result)
SELECT 941, to_jsonb(t) FROM public._qa_node4_marche_r1() t;