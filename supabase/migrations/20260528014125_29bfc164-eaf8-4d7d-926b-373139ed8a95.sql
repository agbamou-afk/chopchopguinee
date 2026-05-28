-- ============================================================
-- user_legal_consents (append-only)
-- ============================================================
CREATE TABLE public.user_legal_consents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  terms_version text NOT NULL,
  privacy_version text NOT NULL,
  accepted_terms boolean NOT NULL DEFAULT true,
  accepted_privacy boolean NOT NULL DEFAULT true,
  accepted_at timestamptz NOT NULL DEFAULT now(),
  ip_address text,
  user_agent text,
  source text NOT NULL DEFAULT 'signup',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_user_legal_consents_user_accepted
  ON public.user_legal_consents (user_id, accepted_at DESC);

GRANT SELECT, INSERT ON public.user_legal_consents TO authenticated;
GRANT ALL ON public.user_legal_consents TO service_role;

ALTER TABLE public.user_legal_consents ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users insert own legal consent"
  ON public.user_legal_consents
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users read own legal consent"
  ON public.user_legal_consents
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Admins read all legal consents"
  ON public.user_legal_consents
  FOR SELECT
  TO authenticated
  USING (is_any_admin(auth.uid()));

-- ============================================================
-- user_preferences
-- ============================================================
CREATE TABLE public.user_preferences (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE,
  allow_urban_insights boolean NOT NULL DEFAULT true,
  allow_marketing_notifications boolean NOT NULL DEFAULT false,
  allow_personalized_offers boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE ON public.user_preferences TO authenticated;
GRANT ALL ON public.user_preferences TO service_role;

ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users read own preferences"
  ON public.user_preferences
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Users insert own preferences"
  ON public.user_preferences
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users update own preferences"
  ON public.user_preferences
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins read all preferences"
  ON public.user_preferences
  FOR SELECT
  TO authenticated
  USING (is_any_admin(auth.uid()));

CREATE TRIGGER trg_user_preferences_updated_at
  BEFORE UPDATE ON public.user_preferences
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();
