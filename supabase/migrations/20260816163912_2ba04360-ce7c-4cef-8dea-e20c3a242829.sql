DELETE FROM public._qa_s13_results WHERE part BETWEEN 951 AND 957;
INSERT INTO public._qa_s13_results(part, result) SELECT 951, to_jsonb(t) FROM public._qa_s13_run1() t;
INSERT INTO public._qa_s13_results(part, result) SELECT 952, to_jsonb(t) FROM public._qa_s13_run2() t;
INSERT INTO public._qa_s13_results(part, result) SELECT 953, to_jsonb(t) FROM public._qa_s13_run3() t;
INSERT INTO public._qa_s13_results(part, result) SELECT 954, to_jsonb(t) FROM public._qa_s13_run4() t;
INSERT INTO public._qa_s13_results(part, result) SELECT 955, to_jsonb(t) FROM public._qa_s13_run5() t;
INSERT INTO public._qa_s13_results(part, result) SELECT 956, to_jsonb(t) FROM public._qa_s13_run6() t;
INSERT INTO public._qa_s13_results(part, result) SELECT 957, to_jsonb(t) FROM public._qa_s13_run7() t;