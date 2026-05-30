
-- 1. Backfill admin_users from user_roles admin-like entries
INSERT INTO public.admin_users (user_id, admin_role, status, notes)
SELECT DISTINCT ON (ur.user_id)
  ur.user_id,
  CASE ur.role::text
    WHEN 'god_admin' THEN 'god_admin'::public.admin_role
    WHEN 'admin' THEN 'super_admin'::public.admin_role
    WHEN 'operations_admin' THEN 'operations_admin'::public.admin_role
    WHEN 'finance_admin' THEN 'finance_admin'::public.admin_role
  END,
  'active'::public.admin_user_status,
  'backfilled from user_roles'
FROM public.user_roles ur
WHERE ur.role::text IN ('god_admin','admin','operations_admin','finance_admin')
  AND NOT EXISTS (SELECT 1 FROM public.admin_users a WHERE a.user_id = ur.user_id)
ORDER BY ur.user_id,
  CASE ur.role::text
    WHEN 'god_admin' THEN 1
    WHEN 'admin' THEN 2
    WHEN 'finance_admin' THEN 3
    WHEN 'operations_admin' THEN 4
    ELSE 5 END;

-- 2. Rewrite helper functions to consult admin_users only
CREATE OR REPLACE FUNCTION public.is_any_admin(_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE user_id = _user_id AND status = 'active'
  );
$$;

CREATE OR REPLACE FUNCTION public.has_app_role(_user_id uuid, _role text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE user_id = _user_id
      AND status = 'active'
      AND (
        admin_role::text = _role
        OR (_role = 'admin' AND admin_role::text IN ('super_admin','god_admin'))
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.can_manage_wallet(_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE user_id = _user_id
      AND status = 'active'
      AND admin_role::text IN ('god_admin','super_admin','finance_admin')
  );
$$;

CREATE OR REPLACE FUNCTION public.can_manage_operations(_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE user_id = _user_id
      AND status = 'active'
      AND admin_role::text IN ('god_admin','super_admin','operations_admin','ops_admin')
  );
$$;

CREATE OR REPLACE FUNCTION public.can_access_admin(_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE user_id = _user_id AND status = 'active'
  );
$$;

-- 3. Tighten topup_requests admin policies (finance/god/super only)
DROP POLICY IF EXISTS "Admins manage topups" ON public.topup_requests;
DROP POLICY IF EXISTS "Admins view all topups" ON public.topup_requests;

CREATE POLICY "Finance admins read topups"
  ON public.topup_requests FOR SELECT TO authenticated
  USING (public.can_manage_wallet(auth.uid()));

CREATE POLICY "Finance admins insert topups"
  ON public.topup_requests FOR INSERT TO authenticated
  WITH CHECK (public.can_manage_wallet(auth.uid()));

CREATE POLICY "Finance admins update topups"
  ON public.topup_requests FOR UPDATE TO authenticated
  USING (public.can_manage_wallet(auth.uid()))
  WITH CHECK (public.can_manage_wallet(auth.uid()));

CREATE POLICY "Finance admins delete topups"
  ON public.topup_requests FOR DELETE TO authenticated
  USING (public.can_manage_wallet(auth.uid()));

-- 4. Tighten realtime messages SELECT — remove NULL topic branch
DROP POLICY IF EXISTS "Authenticated can read own topic messages" ON realtime.messages;

CREATE POLICY "Authenticated can read own topic messages"
  ON realtime.messages FOR SELECT TO authenticated
  USING (
    realtime.topic() = (auth.uid())::text
    OR realtime.topic() = ('user:' || (auth.uid())::text)
    OR realtime.topic() LIKE ('private:' || (auth.uid())::text || ':%')
  );
