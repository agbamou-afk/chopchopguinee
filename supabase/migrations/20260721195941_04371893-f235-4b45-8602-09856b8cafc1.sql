
ALTER TYPE public.payment_state ADD VALUE IF NOT EXISTS 'proof_submitted';
ALTER TYPE public.payment_state ADD VALUE IF NOT EXISTS 'in_review';
ALTER TYPE public.payment_state ADD VALUE IF NOT EXISTS 'authorized';
ALTER TYPE public.payment_state ADD VALUE IF NOT EXISTS 'needs_review';

ALTER TABLE public.payment_intents
  ADD COLUMN IF NOT EXISTS expires_at timestamptz,
  ADD COLUMN IF NOT EXISTS authorized_at timestamptz,
  ADD COLUMN IF NOT EXISTS rejected_at timestamptz,
  ADD COLUMN IF NOT EXISTS rejection_reason text,
  ADD COLUMN IF NOT EXISTS ledger_release_tx_id uuid REFERENCES public.wallet_transactions(id),
  ADD COLUMN IF NOT EXISTS checkout_session_id uuid,
  ADD COLUMN IF NOT EXISTS payer_phone text,
  ADD COLUMN IF NOT EXISTS provider_event_id uuid REFERENCES public.payment_provider_events(id);

CREATE INDEX IF NOT EXISTS idx_payment_intents_session
  ON public.payment_intents(checkout_session_id)
  WHERE checkout_session_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_payment_intents_expires
  ON public.payment_intents(expires_at)
  WHERE expires_at IS NOT NULL;

INSERT INTO public.feature_flags(key, enabled, description) VALUES
  ('om_checkout_enabled', false,
   'Master gate for the Orange Money checkout rail. When off, legacy wallet-hold path is used for rides and existing payment intents for repas/marche.'),
  ('om_provider_mode', false,
   'OM provider integration mode. enabled=false means manual operator verification (default at launch). enabled=true means automated provider webhooks are trusted.'),
  ('om_ride_checkout_enabled', false,
   'When on, ride booking authorizes via Orange Money checkout instead of wallet_hold.'),
  ('om_repas_checkout_enabled', false,
   'When on, Repas orders route customer payment through the OM checkout rail.'),
  ('om_marche_checkout_enabled', false,
   'When on, accepted Marché offers route buyer payment through the OM checkout rail.')
ON CONFLICT (key) DO NOTHING;
