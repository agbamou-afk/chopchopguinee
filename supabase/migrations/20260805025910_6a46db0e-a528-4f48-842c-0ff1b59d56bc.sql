-- 1. Recovery profiles ------------------------------------------------------
CREATE TABLE public.account_recovery_profiles (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  birthdate_hash text NOT NULL,
  question_1_id text NOT NULL,
  answer_1_hash text NOT NULL,
  question_2_id text NOT NULL,
  answer_2_hash text NOT NULL,
  question_3_id text NOT NULL,
  answer_3_hash text NOT NULL,
  recovery_key_hash text NOT NULL,
  recovery_key_version integer NOT NULL DEFAULT 1,
  setup_completed_at timestamptz,
  rotated_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT ALL ON public.account_recovery_profiles TO service_role;
ALTER TABLE public.account_recovery_profiles ENABLE ROW LEVEL SECURITY;
-- Deliberately NO policy for anon/authenticated: hashes are server-only.

-- 2. Recovery challenges -----------------------------------------------------
CREATE TABLE public.account_recovery_challenges (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  is_decoy boolean NOT NULL DEFAULT false,
  identifier_hash text NOT NULL,
  asked_question_ids text[] NOT NULL DEFAULT '{}',
  attempts integer NOT NULL DEFAULT 0,
  max_attempts integer NOT NULL DEFAULT 5,
  expires_at timestamptz NOT NULL,
  verified_at timestamptz,
  consumed_at timestamptz,
  reset_token_hash text,
  reset_token_expires_at timestamptz,
  reset_used_at timestamptz,
  ip_hash text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_arc_identifier ON public.account_recovery_challenges (identifier_hash, created_at DESC);
CREATE INDEX idx_arc_user ON public.account_recovery_challenges (user_id, created_at DESC);

GRANT ALL ON public.account_recovery_challenges TO service_role;
ALTER TABLE public.account_recovery_challenges ENABLE ROW LEVEL SECURITY;

-- 3. Lockout / cooldown counters ---------------------------------------------
CREATE TABLE public.account_recovery_lockouts (
  key_hash text PRIMARY KEY,
  exhausted_count integer NOT NULL DEFAULT 0,
  window_started_at timestamptz NOT NULL DEFAULT now(),
  cooldown_until timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT ALL ON public.account_recovery_lockouts TO service_role;
ALTER TABLE public.account_recovery_lockouts ENABLE ROW LEVEL SECURITY;

-- 4. Signed-in status summary (no secrets) -----------------------------------
CREATE OR REPLACE FUNCTION public.my_account_recovery_status()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (
      SELECT jsonb_build_object(
        'configured', p.setup_completed_at IS NOT NULL,
        'recovery_key_version', p.recovery_key_version,
        'setup_completed_at', p.setup_completed_at,
        'rotated_at', p.rotated_at,
        'question_ids', jsonb_build_array(p.question_1_id, p.question_2_id, p.question_3_id)
      )
      FROM public.account_recovery_profiles p
      WHERE p.user_id = auth.uid()
    ),
    jsonb_build_object('configured', false, 'question_ids', '[]'::jsonb)
  )
  WHERE auth.uid() IS NOT NULL;
$$;

REVOKE ALL ON FUNCTION public.my_account_recovery_status() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.my_account_recovery_status() TO authenticated;

-- 5. updated_at triggers ------------------------------------------------------
CREATE TRIGGER trg_arp_updated_at
BEFORE UPDATE ON public.account_recovery_profiles
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();