CREATE TABLE public._qa_s2x_out (id serial primary key, txt text, created_at timestamptz default now());
GRANT SELECT ON public._qa_s2x_out TO service_role;
ALTER TABLE public._qa_s2x_out ENABLE ROW LEVEL SECURITY;
INSERT INTO public._qa_s2x_out (txt) SELECT public._qa_s2x_run();