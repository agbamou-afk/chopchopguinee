CREATE TABLE IF NOT EXISTS public._qa_s4_results (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ran_at timestamptz NOT NULL DEFAULT now(),
  report jsonb NOT NULL
);
GRANT ALL ON public._qa_s4_results TO service_role;
ALTER TABLE public._qa_s4_results ENABLE ROW LEVEL SECURITY;

INSERT INTO public._qa_s4_results (report) SELECT public._qa_s4_run();