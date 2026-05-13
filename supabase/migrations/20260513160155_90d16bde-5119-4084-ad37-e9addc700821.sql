
DO $$ BEGIN
  CREATE TYPE public.ai_assistant_kind AS ENUM ('admin','support','marche','fraud');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.ai_request_status AS ENUM ('ok','error','rate_limited','blocked');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.ai_request_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  assistant public.ai_assistant_kind NOT NULL,
  action text NOT NULL,
  model text NOT NULL,
  provider text NOT NULL,
  prompt_summary text,
  input jsonb NOT NULL DEFAULT '{}'::jsonb,
  output jsonb,
  tokens_input integer,
  tokens_output integer,
  latency_ms integer,
  status public.ai_request_status NOT NULL DEFAULT 'ok',
  error_message text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ai_request_log_user_idx ON public.ai_request_log (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ai_request_log_assistant_idx ON public.ai_request_log (assistant, created_at DESC);

ALTER TABLE public.ai_request_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins read ai_request_log" ON public.ai_request_log;
CREATE POLICY "Admins read ai_request_log"
  ON public.ai_request_log FOR SELECT TO authenticated
  USING (public.is_any_admin(auth.uid()));

CREATE TABLE IF NOT EXISTS public.ai_rate_limits (
  user_id uuid NOT NULL,
  window_start timestamptz NOT NULL,
  window_kind text NOT NULL CHECK (window_kind IN ('minute','hour')),
  count integer NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, window_kind, window_start)
);

CREATE INDEX IF NOT EXISTS ai_rate_limits_window_idx
  ON public.ai_rate_limits (window_start);

ALTER TABLE public.ai_rate_limits ENABLE ROW LEVEL SECURITY;
-- No policies → only service-role bypass can read/write
