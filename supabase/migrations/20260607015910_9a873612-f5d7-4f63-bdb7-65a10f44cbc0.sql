
-- =====================================================================
-- Account Control System — Freeze, notifications, hardening
-- =====================================================================

-- 1. account_freezes table
CREATE TABLE IF NOT EXISTS public.account_freezes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reason text NOT NULL CHECK (length(trim(reason)) >= 3),
  freeze_type text NOT NULL DEFAULT 'admin_review'
    CHECK (freeze_type IN ('admin_review','payment_review','security_review','dispute','document_review')),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','lifted')),
  frozen_by uuid NOT NULL,
  frozen_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz,
  lifted_by uuid,
  lifted_at timestamptz,
  lift_reason text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.account_freezes TO authenticated;
GRANT ALL ON public.account_freezes TO service_role;

ALTER TABLE public.account_freezes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins view freezes" ON public.account_freezes
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.admin_users au
    WHERE au.user_id = auth.uid() AND au.status = 'active'
  ));

CREATE POLICY "Users view own freeze" ON public.account_freezes
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_account_freezes_user_active
  ON public.account_freezes(user_id) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_account_freezes_status ON public.account_freezes(status);

CREATE TRIGGER trg_account_freezes_updated_at
  BEFORE UPDATE ON public.account_freezes
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- 2. Helpers
CREATE OR REPLACE FUNCTION public._is_ops_or_god_admin(_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE user_id = _user AND status = 'active'
      AND admin_role IN ('god_admin','super_admin','operations_admin')
  );
$$;

CREATE OR REPLACE FUNCTION public.is_user_frozen(_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.account_freezes
    WHERE user_id = _user
      AND status = 'active'
      AND (expires_at IS NULL OR expires_at > now())
  );
$$;
REVOKE ALL ON FUNCTION public.is_user_frozen(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_user_frozen(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.current_freeze(_user uuid DEFAULT NULL)
RETURNS TABLE (
  id uuid, user_id uuid, reason text, freeze_type text,
  frozen_at timestamptz, expires_at timestamptz
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT f.id, f.user_id, f.reason, f.freeze_type, f.frozen_at, f.expires_at
  FROM public.account_freezes f
  WHERE f.user_id = COALESCE(_user, auth.uid())
    AND f.status = 'active'
    AND (f.expires_at IS NULL OR f.expires_at > now())
    -- Only allow self-read or admin
    AND (
      f.user_id = auth.uid()
      OR EXISTS (SELECT 1 FROM public.admin_users a WHERE a.user_id = auth.uid() AND a.status='active')
    )
  ORDER BY f.frozen_at DESC
  LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.current_freeze(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.current_freeze(uuid) TO authenticated, service_role;

-- 3. Notification helper (best effort)
CREATE OR REPLACE FUNCTION public._notify_account_event(
  _user uuid, _template text, _title text, _body text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  BEGIN
    INSERT INTO public.notification_log (user_id, channel, template, status, priority, payload)
    VALUES (_user, 'inapp', _template, 'pending', 'high',
            jsonb_build_object('title', _title, 'body', _body));
  EXCEPTION WHEN OTHERS THEN
    -- never let notification failure abort the calling action
    RAISE WARNING 'notification insert failed: %', SQLERRM;
  END;
END $$;
REVOKE ALL ON FUNCTION public._notify_account_event(uuid,text,text,text) FROM PUBLIC;

-- 4. admin_freeze_user
CREATE OR REPLACE FUNCTION public.admin_freeze_user(
  _target uuid, _reason text,
  _freeze_type text DEFAULT 'admin_review',
  _expires_at timestamptz DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  caller uuid := auth.uid();
  freeze_id uuid;
BEGIN
  IF caller IS NULL THEN RETURN jsonb_build_object('ok',false,'error','unauthenticated'); END IF;
  IF NOT public._is_ops_or_god_admin(caller) THEN
    RETURN jsonb_build_object('ok',false,'error','forbidden');
  END IF;
  IF _target IS NULL OR _target = caller THEN
    RETURN jsonb_build_object('ok',false,'error','invalid_target');
  END IF;
  IF _reason IS NULL OR length(trim(_reason)) < 3 THEN
    RETURN jsonb_build_object('ok',false,'error','reason_required');
  END IF;
  IF _freeze_type NOT IN ('admin_review','payment_review','security_review','dispute','document_review') THEN
    RETURN jsonb_build_object('ok',false,'error','invalid_freeze_type');
  END IF;

  -- Close any existing active freeze (idempotent)
  UPDATE public.account_freezes
     SET status='lifted', lifted_by=caller, lifted_at=now(),
         lift_reason=COALESCE(lift_reason,'remplacé par nouveau gel'), updated_at=now()
   WHERE user_id = _target AND status='active';

  INSERT INTO public.account_freezes (user_id, reason, freeze_type, frozen_by, expires_at)
  VALUES (_target, trim(_reason), _freeze_type, caller, _expires_at)
  RETURNING id INTO freeze_id;

  -- Set profile status to frozen if not banned/deleted
  UPDATE public.profiles
     SET account_status = 'frozen', updated_at = now()
   WHERE user_id = _target AND account_status NOT IN ('banned','deleted');

  -- Force driver offline
  BEGIN
    UPDATE public.driver_profiles SET status='suspended', updated_at=now()
     WHERE user_id = _target AND status = 'active';
  EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END;

  -- Audit
  BEGIN
    INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
    VALUES (caller, 'users', 'user.freeze', 'user', _target::text,
            jsonb_build_object('reason', trim(_reason), 'freeze_type', _freeze_type,
                               'expires_at', _expires_at, 'freeze_id', freeze_id));
  EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END;

  PERFORM public._notify_account_event(
    _target, 'account_frozen', 'Compte temporairement gelé',
    'Votre compte CHOPCHOP est temporairement gelé : ' || trim(_reason) ||
    '. Contactez le support si vous avez des questions.'
  );

  RETURN jsonb_build_object('ok', true, 'freeze_id', freeze_id);
END $$;
REVOKE ALL ON FUNCTION public.admin_freeze_user(uuid,text,text,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_freeze_user(uuid,text,text,timestamptz) TO authenticated, service_role;

-- 5. admin_unfreeze_user
CREATE OR REPLACE FUNCTION public.admin_unfreeze_user(
  _target uuid DEFAULT NULL,
  _freeze_id uuid DEFAULT NULL,
  _lift_reason text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  caller uuid := auth.uid();
  resolved_target uuid;
  lifted_count int;
BEGIN
  IF caller IS NULL THEN RETURN jsonb_build_object('ok',false,'error','unauthenticated'); END IF;
  IF NOT public._is_ops_or_god_admin(caller) THEN
    RETURN jsonb_build_object('ok',false,'error','forbidden');
  END IF;
  IF _lift_reason IS NULL OR length(trim(_lift_reason)) < 3 THEN
    RETURN jsonb_build_object('ok',false,'error','reason_required');
  END IF;
  IF _target IS NULL AND _freeze_id IS NULL THEN
    RETURN jsonb_build_object('ok',false,'error','missing_target');
  END IF;

  IF _freeze_id IS NOT NULL THEN
    SELECT user_id INTO resolved_target FROM public.account_freezes WHERE id = _freeze_id;
  ELSE
    resolved_target := _target;
  END IF;
  IF resolved_target IS NULL THEN
    RETURN jsonb_build_object('ok',false,'error','not_found');
  END IF;

  UPDATE public.account_freezes
     SET status='lifted', lifted_by=caller, lifted_at=now(),
         lift_reason=trim(_lift_reason), updated_at=now()
   WHERE user_id = resolved_target AND status='active';
  GET DIAGNOSTICS lifted_count = ROW_COUNT;

  -- Only restore active if no ban and no other active freeze remains
  IF NOT EXISTS (
    SELECT 1 FROM public.account_bans WHERE user_id = resolved_target AND status='active'
  ) AND NOT public.is_user_frozen(resolved_target) THEN
    UPDATE public.profiles SET account_status='active', updated_at=now()
     WHERE user_id = resolved_target AND account_status = 'frozen';
  END IF;

  BEGIN
    INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
    VALUES (caller, 'users', 'user.unfreeze', 'user', resolved_target::text,
            jsonb_build_object('lift_reason', trim(_lift_reason), 'lifted_count', lifted_count));
  EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END;

  PERFORM public._notify_account_event(
    resolved_target, 'account_unfrozen', 'Compte réactivé',
    'Votre compte CHOPCHOP a été réactivé.'
  );

  RETURN jsonb_build_object('ok', true, 'lifted_count', lifted_count);
END $$;
REVOKE ALL ON FUNCTION public.admin_unfreeze_user(uuid,uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_unfreeze_user(uuid,uuid,text) TO authenticated, service_role;

-- 6. Add notifications to existing ban/unban (replace bodies preserving signature)
CREATE OR REPLACE FUNCTION public.admin_ban_user(_target uuid, _reason text, _expires_at timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  caller uuid := auth.uid();
  prof RECORD; email_snap text; phone_snap text; ban_id uuid;
BEGIN
  IF caller IS NULL THEN RETURN jsonb_build_object('ok',false,'error','unauthenticated'); END IF;
  IF NOT public._is_god_admin(caller) THEN RETURN jsonb_build_object('ok',false,'error','forbidden'); END IF;
  IF _target IS NULL OR _target = caller THEN RETURN jsonb_build_object('ok',false,'error','invalid_target'); END IF;
  IF _reason IS NULL OR length(trim(_reason)) < 3 THEN RETURN jsonb_build_object('ok',false,'error','reason_required'); END IF;

  SELECT user_id, email, phone INTO prof FROM public.profiles WHERE user_id = _target;
  email_snap := COALESCE(prof.email, (SELECT email FROM auth.users WHERE id = _target));
  phone_snap := COALESCE(prof.phone, (SELECT phone FROM auth.users WHERE id = _target));

  INSERT INTO public.account_bans (user_id, email, email_lc, phone_e164, reason, banned_by, expires_at)
  VALUES (_target, email_snap,
          CASE WHEN email_snap IS NOT NULL THEN lower(email_snap) ELSE NULL END,
          phone_snap, trim(_reason), caller, _expires_at)
  RETURNING id INTO ban_id;

  UPDATE public.profiles SET account_status='banned', updated_at=now() WHERE user_id = _target;

  BEGIN
    UPDATE public.driver_profiles SET status='suspended', updated_at=now() WHERE user_id = _target;
  EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END;

  -- Also lift any active freeze (ban supersedes)
  UPDATE public.account_freezes
     SET status='lifted', lifted_by=caller, lifted_at=now(),
         lift_reason='compte banni', updated_at=now()
   WHERE user_id = _target AND status='active';

  BEGIN
    INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
    VALUES (caller, 'users', 'user.ban', 'user', _target::text,
            jsonb_build_object('reason', trim(_reason), 'expires_at', _expires_at, 'ban_id', ban_id));
  EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END;

  PERFORM public._notify_account_event(
    _target, 'account_banned', 'Compte suspendu',
    'Votre compte CHOPCHOP a été suspendu. Contactez le support si vous pensez qu''il s''agit d''une erreur.'
  );

  RETURN jsonb_build_object('ok', true, 'ban_id', ban_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_unban_user(_target uuid DEFAULT NULL, _ban_id uuid DEFAULT NULL, _lift_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  caller uuid := auth.uid();
  resolved uuid; lifted_count int;
BEGIN
  IF caller IS NULL THEN RETURN jsonb_build_object('ok',false,'error','unauthenticated'); END IF;
  IF NOT public._is_god_admin(caller) THEN RETURN jsonb_build_object('ok',false,'error','forbidden'); END IF;
  IF _lift_reason IS NULL OR length(trim(_lift_reason)) < 3 THEN
    RETURN jsonb_build_object('ok',false,'error','reason_required');
  END IF;
  IF _ban_id IS NOT NULL THEN
    SELECT user_id INTO resolved FROM public.account_bans WHERE id = _ban_id;
  ELSE
    resolved := _target;
  END IF;
  IF resolved IS NULL THEN RETURN jsonb_build_object('ok',false,'error','missing_target'); END IF;

  UPDATE public.account_bans
     SET status='lifted', lifted_by=caller, lifted_at=now(),
         lift_reason=trim(_lift_reason), updated_at=now()
   WHERE user_id = resolved AND status='active';
  GET DIAGNOSTICS lifted_count = ROW_COUNT;

  UPDATE public.profiles SET account_status='active', updated_at=now()
   WHERE user_id = resolved AND account_status='banned';

  BEGIN
    INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
    VALUES (caller, 'users', 'user.unban', 'user', resolved::text,
            jsonb_build_object('lift_reason', trim(_lift_reason), 'lifted_count', lifted_count));
  EXCEPTION WHEN undefined_column OR undefined_table THEN NULL; END;

  PERFORM public._notify_account_event(
    resolved, 'account_unbanned', 'Compte réactivé',
    'Votre compte CHOPCHOP a été réactivé.'
  );

  RETURN jsonb_build_object('ok', true, 'lifted_count', lifted_count);
END $$;

REVOKE ALL ON FUNCTION public.admin_ban_user(uuid,text,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_ban_user(uuid,text,timestamptz) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_unban_user(uuid,uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_unban_user(uuid,uuid,text) TO authenticated, service_role;

-- 7. Freeze enforcement triggers (defense in depth)
CREATE OR REPLACE FUNCTION public._block_if_frozen()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  acting uuid := auth.uid();
BEGIN
  IF acting IS NOT NULL AND public.is_user_frozen(acting) THEN
    RAISE EXCEPTION 'frozen_account: compte gelé — action non autorisée'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_block_frozen_rides ON public.rides;
CREATE TRIGGER trg_block_frozen_rides
  BEFORE INSERT ON public.rides
  FOR EACH ROW EXECUTE FUNCTION public._block_if_frozen();

DROP TRIGGER IF EXISTS trg_block_frozen_food_orders ON public.food_orders;
CREATE TRIGGER trg_block_frozen_food_orders
  BEFORE INSERT ON public.food_orders
  FOR EACH ROW EXECUTE FUNCTION public._block_if_frozen();

DROP TRIGGER IF EXISTS trg_block_frozen_topups ON public.topup_requests;
CREATE TRIGGER trg_block_frozen_topups
  BEFORE INSERT ON public.topup_requests
  FOR EACH ROW EXECUTE FUNCTION public._block_if_frozen();

DROP TRIGGER IF EXISTS trg_block_frozen_listings ON public.marketplace_listings;
CREATE TRIGGER trg_block_frozen_listings
  BEFORE INSERT OR UPDATE ON public.marketplace_listings
  FOR EACH ROW EXECUTE FUNCTION public._block_if_frozen();
