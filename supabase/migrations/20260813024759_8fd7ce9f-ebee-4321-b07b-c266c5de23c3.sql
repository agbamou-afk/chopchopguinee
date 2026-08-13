DELETE FROM public._qa_s13_results WHERE part = 101;
INSERT INTO public._qa_s13_results(part, result)
SELECT 101, public._qa_node1_bonbonna();