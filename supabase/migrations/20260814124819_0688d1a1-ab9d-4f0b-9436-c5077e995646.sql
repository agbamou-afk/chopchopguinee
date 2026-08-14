DELETE FROM public._qa_s13_results WHERE part IN (4,5,6,7);
INSERT INTO public._qa_s13_results(part, result) VALUES
 (4, public._qa_s13_run4()),
 (5, public._qa_s13_run5()),
 (6, public._qa_s13_run6()),
 (7, public._qa_s13_run7());