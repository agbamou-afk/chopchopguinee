DELETE FROM public._qa_s13_results WHERE part = 9101;
INSERT INTO public._qa_s13_results(part, result) SELECT 9101, public._qa_node0_course();