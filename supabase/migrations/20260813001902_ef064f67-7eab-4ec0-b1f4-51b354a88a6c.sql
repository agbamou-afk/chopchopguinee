DO $$
DECLARE r jsonb;
BEGIN
  SELECT jsonb_agg(to_jsonb(t)) INTO r FROM public._qa_node0_course() t;
  INSERT INTO public._qa_s13_results(part, result) VALUES (100, r);
  INSERT INTO public._qa_s13_results(part, result) VALUES (1, to_jsonb(public._qa_s13_run1()));
  INSERT INTO public._qa_s13_results(part, result) VALUES (2, to_jsonb(public._qa_s13_run2()));
  INSERT INTO public._qa_s13_results(part, result) VALUES (3, to_jsonb(public._qa_s13_run3()));
  INSERT INTO public._qa_s13_results(part, result) VALUES (4, to_jsonb(public._qa_s13_run4()));
  INSERT INTO public._qa_s13_results(part, result) VALUES (5, to_jsonb(public._qa_s13_run5()));
  INSERT INTO public._qa_s13_results(part, result) VALUES (6, to_jsonb(public._qa_s13_run6()));
  INSERT INTO public._qa_s13_results(part, result) VALUES (7, to_jsonb(public._qa_s13_run7()));
END $$;