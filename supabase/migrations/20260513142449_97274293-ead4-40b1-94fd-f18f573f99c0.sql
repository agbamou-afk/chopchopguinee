
-- 1. Admin role tier enum
DO $$ BEGIN
  CREATE TYPE public.admin_role AS ENUM ('super_admin', 'ops_admin', 'finance_admin');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
  CREATE TYPE public.admin_user_status AS ENUM ('active', 'suspended');
EXCEPTION WHEN duplicate_object THEN null; END $$;

DO $$ BEGIN
  CREATE TYPE public.approval_status AS ENUM ('pending', 'approved', 'rejected', 'cancelled');
EXCEPTION WHEN duplicate_object THEN null; END $$;

-- 2. admin_users
CREATE TABLE IF NOT EXISTS public.admin_users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE,
  admin_role public.admin_role NOT NULL,
  status public.admin_user_status NOT NULL DEFAULT 'active',
  created_by uuid,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.admin_users ENABLE ROW LEVEL SECURITY;

-- 3. Helper functions
CREATE OR REPLACE FUNCTION public.has_admin_role(_user_id uuid, _role public.admin_role)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE user_id = _user_id AND admin_role = _role AND status = 'active'
  );
$$;

CREATE OR REPLACE FUNCTION public.is_admin(_user_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_users
    WHERE user_id = _user_id AND status = 'active'
  );
$$;

CREATE OR REPLACE FUNCTION public.current_admin_role(_user_id uuid)
RETURNS public.admin_role
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT admin_role FROM public.admin_users
  WHERE user_id = _user_id AND status = 'active'
  LIMIT 1;
$$;

-- 4. RLS for admin_users
DROP POLICY IF EXISTS "Admins read admin_users" ON public.admin_users;
CREATE POLICY "Admins read admin_users" ON public.admin_users
  FOR SELECT TO authenticated
  USING (public.is_admin(auth.uid()));

DROP POLICY IF EXISTS "Super admins manage admin_users" ON public.admin_users;
CREATE POLICY "Super admins manage admin_users" ON public.admin_users
  FOR ALL TO authenticated
  USING (public.has_admin_role(auth.uid(), 'super_admin'))
  WITH CHECK (public.has_admin_role(auth.uid(), 'super_admin'));

-- 5. audit_logs
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_user_id uuid,
  actor_role public.admin_role,
  module text NOT NULL,
  action text NOT NULL,
  target_type text,
  target_id text,
  before jsonb,
  after jsonb,
  ip text,
  user_agent text,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_audit_logs_module ON public.audit_logs(module);
CREATE INDEX IF NOT EXISTS idx_audit_logs_actor ON public.audit_logs(actor_user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created ON public.audit_logs(created_at DESC);

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Super admins read all audit logs" ON public.audit_logs;
CREATE POLICY "Super admins read all audit logs" ON public.audit_logs
  FOR SELECT TO authenticated
  USING (public.has_admin_role(auth.uid(), 'super_admin'));

DROP POLICY IF EXISTS "Ops admins read ops audit logs" ON public.audit_logs;
CREATE POLICY "Ops admins read ops audit logs" ON public.audit_logs
  FOR SELECT TO authenticated
  USING (
    public.has_admin_role(auth.uid(), 'ops_admin')
    AND module IN ('users','drivers','merchants','orders','repas','marche','support','live_ops','notifications','promotions','risk')
  );

DROP POLICY IF EXISTS "Finance admins read finance audit logs" ON public.audit_logs;
CREATE POLICY "Finance admins read finance audit logs" ON public.audit_logs
  FOR SELECT TO authenticated
  USING (
    public.has_admin_role(auth.uid(), 'finance_admin')
    AND module IN ('wallet','vendors','pricing','reports','risk')
  );

-- log function
CREATE OR REPLACE FUNCTION public.log_admin_action(
  _module text,
  _action text,
  _target_type text DEFAULT NULL,
  _target_id text DEFAULT NULL,
  _before jsonb DEFAULT NULL,
  _after jsonb DEFAULT NULL,
  _note text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_role public.admin_role;
BEGIN
  v_role := public.current_admin_role(auth.uid());
  INSERT INTO public.audit_logs(actor_user_id, actor_role, module, action, target_type, target_id, before, after, note)
  VALUES (auth.uid(), v_role, _module, _action, _target_type, _target_id, _before, _after, _note)
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- 6. approval_requests
CREATE TABLE IF NOT EXISTS public.approval_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  requested_by uuid NOT NULL,
  requested_role public.admin_role,
  module text NOT NULL,
  action text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  status public.approval_status NOT NULL DEFAULT 'pending',
  reviewed_by uuid,
  review_note text,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_approval_status ON public.approval_requests(status);

ALTER TABLE public.approval_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins create approval requests" ON public.approval_requests;
CREATE POLICY "Admins create approval requests" ON public.approval_requests
  FOR INSERT TO authenticated
  WITH CHECK (public.is_admin(auth.uid()) AND auth.uid() = requested_by);

DROP POLICY IF EXISTS "Admins read approval requests" ON public.approval_requests;
CREATE POLICY "Admins read approval requests" ON public.approval_requests
  FOR SELECT TO authenticated
  USING (public.is_admin(auth.uid()) AND (auth.uid() = requested_by OR public.has_admin_role(auth.uid(), 'super_admin')));

DROP POLICY IF EXISTS "Super admins review approvals" ON public.approval_requests;
CREATE POLICY "Super admins review approvals" ON public.approval_requests
  FOR UPDATE TO authenticated
  USING (public.has_admin_role(auth.uid(), 'super_admin'))
  WITH CHECK (public.has_admin_role(auth.uid(), 'super_admin'));

-- 7. feature_flags
CREATE TABLE IF NOT EXISTS public.feature_flags (
  key text PRIMARY KEY,
  enabled boolean NOT NULL DEFAULT false,
  description text,
  updated_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.feature_flags ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone read feature flags" ON public.feature_flags;
CREATE POLICY "Anyone read feature flags" ON public.feature_flags
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "Super admins write flags" ON public.feature_flags;
CREATE POLICY "Super admins write flags" ON public.feature_flags
  FOR ALL TO authenticated
  USING (public.has_admin_role(auth.uid(), 'super_admin'))
  WITH CHECK (public.has_admin_role(auth.uid(), 'super_admin'));

INSERT INTO public.feature_flags(key, enabled, description) VALUES
  ('moto', true, 'Moto ride-hailing service'),
  ('toktok', true, 'TokTok ride-hailing service'),
  ('repas', true, 'Repas food ordering'),
  ('marche', true, 'Marché marketplace'),
  ('scanner', true, 'QR scanner'),
  ('wallet', true, 'Wallet & P2P transfers'),
  ('agent_topup', true, 'Agent cash-in top-ups'),
  ('orange_money', false, 'Orange Money integration (placeholder)'),
  ('driver_mode', true, 'Driver mode toggle'),
  ('merchant_portal', false, 'Merchant self-serve portal'),
  ('marketplace_chat', true, 'Marché buyer/seller chat'),
  ('boosted_listings', false, 'Boosted/featured marketplace listings')
ON CONFLICT (key) DO NOTHING;

-- 8. zones
CREATE TABLE IF NOT EXISTS public.zones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  country text NOT NULL DEFAULT 'GN',
  city text,
  commune text,
  neighborhood text,
  kind text NOT NULL DEFAULT 'service',
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.zones ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone read zones" ON public.zones;
CREATE POLICY "Anyone read zones" ON public.zones
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "Super admins manage zones" ON public.zones;
CREATE POLICY "Super admins manage zones" ON public.zones
  FOR ALL TO authenticated
  USING (public.has_admin_role(auth.uid(), 'super_admin'))
  WITH CHECK (public.has_admin_role(auth.uid(), 'super_admin'));

-- 9. Bootstrap: anyone in user_roles 'admin' becomes super_admin
INSERT INTO public.admin_users(user_id, admin_role, status, notes)
SELECT user_id, 'super_admin'::public.admin_role, 'active'::public.admin_user_status, 'Bootstrapped from legacy admin role'
FROM public.user_roles
WHERE role = 'admin'
ON CONFLICT (user_id) DO NOTHING;

-- 10. updated_at triggers
DROP TRIGGER IF EXISTS trg_admin_users_updated ON public.admin_users;
CREATE TRIGGER trg_admin_users_updated BEFORE UPDATE ON public.admin_users
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS trg_zones_updated ON public.zones;
CREATE TRIGGER trg_zones_updated BEFORE UPDATE ON public.zones
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
