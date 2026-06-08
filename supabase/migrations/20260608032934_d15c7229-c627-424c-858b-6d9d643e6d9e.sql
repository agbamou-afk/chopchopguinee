
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS last_profile_confirmed_at timestamptz;

-- Backfill: treat all existing accounts as freshly confirmed at account creation,
-- so we don't immediately spam every returning user with the confirmation prompt.
UPDATE public.profiles
  SET last_profile_confirmed_at = COALESCE(last_profile_confirmed_at, created_at)
  WHERE last_profile_confirmed_at IS NULL;
