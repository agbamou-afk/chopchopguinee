
-- ============================================================
-- account_bans table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.account_bans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NULL,
  email text NULL,
  email_lc text NULL,
  phone_e164 text NULL,
  reason text NOT NULL,
  status text NOT NULL DEFAULT 'active',
  banned_by uuid NOT NULL,
  banned_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NULL,
  lifted_by uuid NULL,
  lifted_at timestamptz NULL,
  lift_reason text NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.account_bans TO authenticated;
GRANT ALL ON public.account_bans TO service_role;

ALTER TABLE public.account_bans ENABLE ROW LEVEL SECURITY;

-- Only admins can directly read the table; banning is done through RPC.
DROP POLICY IF EXISTS "Admins can view bans" ON public.account_bans;
CREATE POLICY "Admins can view bans" ON public.account_bans
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.admin_users au
    WHERE au.user_id = auth.uid() AND au.status = 'active'
  ));

CREATE INDEX IF NOT EXISTS idx_account_bans_email_lc ON public.account_bans (email_lc) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_account_bans_phone ON public.account_bans (phone_e164) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_account_bans_user_id ON public.account_bans (user_id) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_account_bans_status ON public.account_bans (status);

-- updated_at trigger reusing existing helper
DROP TRIGGER IF EXISTS trg_account_bans_updated_at ON public.account_bans;
CREATE TRIGGER trg_account_bans_updated_at
  BEFORE UPDATE ON public.account_bans
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============================================================
-- Helpers
-- ============================================================
CREATE OR REPLACE FUNCTION public._is_god_admin(_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE user_id = _user
      AND status = 'active'
      AND admin_role IN ('god_admin','super_admin')
  );
$$;

CREATE OR REPLACE FUNCTION public.is_user_banned(_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.account_bans
    WHERE user_id = _user
      AND status = 'active'
      AND (expires_at IS NULL OR expires_at > now())
  );
$$;
GRANT EXECUTE ON FUNCTION public.is_user_banned(uuid) TO authenticated, anon;

-- Anon-callable signup preflight. Returns minimal info; no enumeration leakage.
CREATE OR REPLACE FUNCTION public.check_signup_allowed(_email text, _phone text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  blocked boolean := false;
BEGIN
  IF _email IS NOT NULL AND length(trim(_email)) > 0 THEN
    IF EXISTS (
      SELECT 1 FROM public.account_bans
      WHERE status = 'active'
        AND (expires_at IS NULL OR expires_at > now())
        AND email_lc = lower(trim(_email))
    ) THEN blocked := true; END IF;
  END IF;
  IF NOT blocked AND _phone IS NOT NULL AND length(trim(_phone)) > 0 THEN
    IF EXISTS (
      SELECT 1 FROM public.account_bans
      WHERE status = 'active'
        AND (expires_at IS NULL OR expires_at > now())
        AND phone_e164 = trim(_phone)
    ) THEN blocked := true; END IF;
  END IF;
  RETURN jsonb_build_object('allowed', NOT blocked);
END;
$$;
GRANT EXECUTE ON FUNCTION public.check_signup_allowed(text, text) TO anon, authenticated;

-- ============================================================
-- admin_ban_user
-- ============================================================
CREATE OR REPLACE FUNCTION public.admin_ban_user(
  _target uuid,
  _reason text,
  _expires_at timestamptz DEFAULT NULL
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  caller uuid := auth.uid();
  prof RECORD;
  email_snap text;
  phone_snap text;
  ban_id uuid;
BEGIN
  IF caller IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'unauthenticated');
  END IF;
  IF NOT public._is_god_admin(caller) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF _target IS NULL OR _target = caller THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_target');
  END IF;
  IF _reason IS NULL OR length(trim(_reason)) < 3 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'reason_required');
  END IF;

  SELECT user_id, email, phone INTO prof FROM public.profiles WHERE user_id = _target;
  email_snap := COALESCE(prof.email, (SELECT email FROM auth.users WHERE id = _target));
  phone_snap := COALESCE(prof.phone, (SELECT phone FROM auth.users WHERE id = _target));

  INSERT INTO public.account_bans (
    user_id, email, email_lc, phone_e164, reason, banned_by, expires_at
  ) VALUES (
    _target,
    email_snap,
    CASE WHEN email_snap IS NOT NULL THEN lower(email_snap) ELSE NULL END,
    phone_snap,
    trim(_reason),
    caller,
    _expires_at
  ) RETURNING id INTO ban_id;

  UPDATE public.profiles
     SET account_status = 'banned', updated_at = now()
   WHERE user_id = _target;

  -- Suspend driver profile if any
  BEGIN
    UPDATE public.driver_profiles
       SET status = 'suspended', updated_at = now()
     WHERE user_id = _target;
  EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END;

  -- Audit log
  BEGIN
    INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
    VALUES (caller, 'users', 'user.ban', 'user', _target,
            jsonb_build_object('reason', trim(_reason), 'expires_at', _expires_at, 'ban_id', ban_id));
  EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END;

  RETURN jsonb_build_object('ok', true, 'ban_id', ban_id);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_ban_user(uuid, text, timestamptz) TO authenticated;

-- ============================================================
-- admin_unban_user
-- ============================================================
CREATE OR REPLACE FUNCTION public.admin_unban_user(
  _target uuid,
  _lift_reason text
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  caller uuid := auth.uid();
  lifted_count int := 0;
BEGIN
  IF caller IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'unauthenticated');
  END IF;
  IF NOT public._is_god_admin(caller) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;
  IF _target IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_target');
  END IF;

  UPDATE public.account_bans
     SET status = 'lifted',
         lifted_by = caller,
         lifted_at = now(),
         lift_reason = COALESCE(trim(_lift_reason), 'unbanned'),
         updated_at = now()
   WHERE user_id = _target AND status = 'active';
  GET DIAGNOSTICS lifted_count = ROW_COUNT;

  UPDATE public.profiles
     SET account_status = 'active', updated_at = now()
   WHERE user_id = _target AND account_status = 'banned';

  BEGIN
    INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
    VALUES (caller, 'users', 'user.unban', 'user', _target,
            jsonb_build_object('lift_reason', _lift_reason, 'lifted_count', lifted_count));
  EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END;

  RETURN jsonb_build_object('ok', true, 'lifted', lifted_count);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_unban_user(uuid, text) TO authenticated;
