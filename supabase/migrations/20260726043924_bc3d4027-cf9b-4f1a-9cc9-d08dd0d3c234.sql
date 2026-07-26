
-- Sandbox isolation columns
ALTER TABLE public.payment_intents
  ADD COLUMN IF NOT EXISTS is_sandbox boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS environment text NOT NULL DEFAULT 'production',
  ADD COLUMN IF NOT EXISTS test_run_id uuid NULL;

ALTER TABLE public.payment_provider_events
  ADD COLUMN IF NOT EXISTS is_sandbox boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS environment text NOT NULL DEFAULT 'production',
  ADD COLUMN IF NOT EXISTS test_run_id uuid NULL;

ALTER TABLE public.payment_reconciliation_events
  ADD COLUMN IF NOT EXISTS is_sandbox boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS environment text NOT NULL DEFAULT 'production',
  ADD COLUMN IF NOT EXISTS test_run_id uuid NULL;

CREATE INDEX IF NOT EXISTS idx_payment_intents_sandbox
  ON public.payment_intents (is_sandbox, state, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_payment_provider_events_sandbox
  ON public.payment_provider_events (is_sandbox, created_at DESC);

-- Feature flag seeds (idempotent)
INSERT INTO public.feature_flags (key, enabled, description)
VALUES
  ('om_sandbox_enabled', false,
   'Master sandbox switch for the OM checkout rail. When true (staging only), sandbox test references (OM-SBX-*) are accepted and sandbox intents are visibly isolated from real financial totals.'),
  ('om_environment', false,
   'Environment declaration for the OM checkout rail. enabled=false means production (default). enabled=true means this deployment is a sandbox/staging environment where sandbox-tagged payments are allowed.')
ON CONFLICT (key) DO NOTHING;
