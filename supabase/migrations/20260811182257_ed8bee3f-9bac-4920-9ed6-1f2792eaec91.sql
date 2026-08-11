CREATE TABLE IF NOT EXISTS public._qa_patch_buffer (
  id integer PRIMARY KEY,
  body text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public._qa_patch_buffer TO service_role;
GRANT SELECT, INSERT, DELETE ON public._qa_patch_buffer TO sandbox_exec;
ALTER TABLE public._qa_patch_buffer ENABLE ROW LEVEL SECURITY;