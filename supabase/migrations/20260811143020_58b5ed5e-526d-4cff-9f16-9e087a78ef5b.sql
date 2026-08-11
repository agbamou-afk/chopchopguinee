CREATE TABLE IF NOT EXISTS public._qa_s10_results (id text primary key, ok boolean, detail text);
GRANT SELECT ON public._qa_s10_results TO service_role;
DELETE FROM public._qa_s10_results;
INSERT INTO public._qa_s10_results (id, ok, detail) SELECT * FROM public._qa_s10_run();