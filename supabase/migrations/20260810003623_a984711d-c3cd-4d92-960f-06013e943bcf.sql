CREATE TABLE public._qa_s4_results (
  id bigserial PRIMARY KEY,
  line text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public._qa_s4_results ENABLE ROW LEVEL SECURITY;
GRANT ALL ON public._qa_s4_results TO service_role;
GRANT SELECT, INSERT ON public._qa_s4_results TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public._qa_s4_results_id_seq TO authenticated, service_role;