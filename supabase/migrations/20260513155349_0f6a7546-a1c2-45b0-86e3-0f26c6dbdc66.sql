
DO $$ BEGIN
  CREATE TYPE public.notification_channel AS ENUM ('email','sms','whatsapp','push','inapp');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.notification_status AS ENUM ('pending','sent','failed','suppressed','skipped');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.notification_priority AS ENUM ('critical','high','normal','low');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.notification_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  channel public.notification_channel NOT NULL,
  template text NOT NULL,
  status public.notification_status NOT NULL DEFAULT 'pending',
  priority public.notification_priority NOT NULL DEFAULT 'normal',
  recipient text,
  external_id text,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  error_message text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS notification_log_user_id_idx ON public.notification_log (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS notification_log_status_idx ON public.notification_log (status, created_at DESC);
CREATE INDEX IF NOT EXISTS notification_log_template_idx ON public.notification_log (template, created_at DESC);

ALTER TABLE public.notification_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins read notification_log" ON public.notification_log;
CREATE POLICY "Admins read notification_log"
  ON public.notification_log FOR SELECT
  TO authenticated
  USING (public.is_any_admin(auth.uid()));

CREATE OR REPLACE TRIGGER notification_log_set_updated
  BEFORE UPDATE ON public.notification_log
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
