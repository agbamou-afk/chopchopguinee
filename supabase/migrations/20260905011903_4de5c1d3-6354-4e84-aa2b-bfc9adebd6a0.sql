-- ============================================================
-- G2 · Admin capability enforcement
-- ============================================================

-- 1. Canonical staff role resolution (reconciles the two legacy role systems)
CREATE OR REPLACE FUNCTION public.admin_role_canonical(_uid uuid DEFAULT auth.uid())
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN _uid IS NULL THEN NULL
    WHEN public.auth_uid_active() IS NULL AND _uid = auth.uid() THEN NULL
    WHEN EXISTS (SELECT 1 FROM public.user_roles ur
                 WHERE ur.user_id = _uid AND ur.role IN ('god_admin','admin'))
      OR EXISTS (SELECT 1 FROM public.admin_users au
                 WHERE au.user_id = _uid AND au.status = 'active'
                   AND au.admin_role IN ('god_admin','super_admin'))
      THEN 'god_admin'
    WHEN EXISTS (SELECT 1 FROM public.user_roles ur
                 WHERE ur.user_id = _uid AND ur.role = 'finance_admin')
      OR EXISTS (SELECT 1 FROM public.admin_users au
                 WHERE au.user_id = _uid AND au.status = 'active'
                   AND au.admin_role = 'finance_admin')
      THEN 'finance_admin'
    WHEN EXISTS (SELECT 1 FROM public.user_roles ur
                 WHERE ur.user_id = _uid AND ur.role = 'operations_admin')
      OR EXISTS (SELECT 1 FROM public.admin_users au
                 WHERE au.user_id = _uid AND au.status = 'active'
                   AND au.admin_role IN ('ops_admin','operations_admin','support_admin'))
      THEN 'operations_admin'
    ELSE NULL
  END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_role_canonical(uuid) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.admin_role_canonical(uuid) FROM anon, PUBLIC;

-- 2. Capability registry (the constitution, in data)
CREATE TABLE IF NOT EXISTS public.admin_capability_grants (
  capability text NOT NULL,
  admin_role text NOT NULL CHECK (admin_role IN ('god_admin','operations_admin','finance_admin')),
  mode text NOT NULL DEFAULT 'allow' CHECK (mode IN ('allow','approval_required')),
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (capability, admin_role)
);

GRANT SELECT ON public.admin_capability_grants TO authenticated;
GRANT ALL ON public.admin_capability_grants TO service_role;

ALTER TABLE public.admin_capability_grants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "staff read capability grants" ON public.admin_capability_grants;
CREATE POLICY "staff read capability grants"
ON public.admin_capability_grants FOR SELECT TO authenticated
USING (public.admin_role_canonical(auth.uid()) IS NOT NULL);

DROP POLICY IF EXISTS "god admin manages capability grants" ON public.admin_capability_grants;
CREATE POLICY "god admin manages capability grants"
ON public.admin_capability_grants FOR ALL TO authenticated
USING (public.admin_role_canonical(auth.uid()) = 'god_admin')
WITH CHECK (public.admin_role_canonical(auth.uid()) = 'god_admin');

DROP TRIGGER IF EXISTS trg_admin_capability_grants_updated ON public.admin_capability_grants;
CREATE TRIGGER trg_admin_capability_grants_updated
BEFORE UPDATE ON public.admin_capability_grants
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

INSERT INTO public.admin_capability_grants (capability, admin_role, mode, note) VALUES
  ('ops.users.manage','operations_admin','allow','Comptes clients, support, litiges opérationnels'),
  ('ops.drivers.manage','operations_admin','allow','Approbation et suivi chauffeurs'),
  ('ops.merchants.manage','operations_admin','allow','Onboarding et suivi marchands'),
  ('ops.orders.manage','operations_admin','allow','Courses, missions, commandes'),
  ('ops.support.manage','operations_admin','allow','File support et risque'),
  ('ops.maps.manage','operations_admin','allow','Zones, lieux, doublons, routage'),
  ('ops.pricing.propose','operations_admin','approval_required','Grille tarifaire: proposition seulement'),
  ('ops.flags.propose','operations_admin','approval_required','Flags non financiers: proposition seulement'),
  ('finance.wallet.credit','finance_admin','allow','Crédits wallet via RPC canoniques'),
  ('finance.payouts.manage','finance_admin','allow','Retraits, règlements, réconciliation'),
  ('finance.treasury.read','finance_admin','allow','Trésorerie et exceptions en lecture'),
  ('finance.treasury.move','finance_admin','approval_required','Mouvement trésorerie: quatre yeux'),
  ('finance.policy.change','finance_admin','approval_required','Politique finance/payout/settlement'),
  ('finance.flags.payment','finance_admin','approval_required','Flags des rails de paiement'),
  ('governance.staff.manage','god_admin','approval_required','Création/désactivation/rôle du personnel'),
  ('governance.account.close','god_admin','approval_required','Clôture ou anonymisation de compte'),
  ('governance.flags.manage','god_admin','allow','Flags produits'),
  ('governance.audit.read_all','god_admin','allow','Journal complet')
ON CONFLICT (capability, admin_role) DO NOTHING;

-- 3. Capability check. God Admin holds every capability implicitly.
CREATE OR REPLACE FUNCTION public.admin_capability(_capability text, _uid uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text := public.admin_role_canonical(_uid);
BEGIN
  IF v_role IS NULL THEN RETURN false; END IF;
  IF v_role = 'god_admin' THEN RETURN true; END IF;
  RETURN EXISTS (
    SELECT 1 FROM public.admin_capability_grants g
    WHERE g.capability = _capability AND g.admin_role = v_role
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_capability(text, uuid) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.admin_capability(text, uuid) FROM anon, PUBLIC;

CREATE OR REPLACE FUNCTION public.admin_require_capability(_capability text)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.admin_capability(_capability) THEN
    RAISE EXCEPTION 'insufficient_privilege: %', _capability USING ERRCODE = '42501';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_require_capability(text) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.admin_require_capability(text) FROM anon, PUBLIC;

-- 4. Server-side four-eyes gate (cannot be skipped from the browser)
CREATE OR REPLACE FUNCTION public.admin_capability_mode(_capability text, _uid uuid DEFAULT auth.uid())
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text := public.admin_role_canonical(_uid);
  v_mode text;
BEGIN
  IF v_role IS NULL THEN RETURN 'deny'; END IF;
  SELECT g.mode INTO v_mode FROM public.admin_capability_grants g
   WHERE g.capability = _capability AND g.admin_role = v_role;
  IF v_mode IS NOT NULL THEN RETURN v_mode; END IF;
  IF v_role = 'god_admin' THEN
    SELECT g.mode INTO v_mode FROM public.admin_capability_grants g
     WHERE g.capability = _capability AND g.admin_role = 'god_admin';
    RETURN COALESCE(v_mode, 'allow');
  END IF;
  RETURN 'deny';
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_capability_mode(text, uuid) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.admin_capability_mode(text, uuid) FROM anon, PUBLIC;

CREATE OR REPLACE FUNCTION public.admin_four_eyes_gate(_capability text, _approval_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_req public.approval_requests;
BEGIN
  PERFORM public.admin_require_capability(_capability);
  IF public.admin_capability_mode(_capability) <> 'approval_required' THEN
    RETURN; -- direct execution allowed for this role
  END IF;
  IF _approval_id IS NULL THEN
    RAISE EXCEPTION 'approval_required: %', _capability USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_req FROM public.approval_requests WHERE id = _approval_id;
  IF v_req.id IS NULL THEN
    RAISE EXCEPTION 'approval_not_found' USING ERRCODE = '42501';
  END IF;
  IF v_req.action IS DISTINCT FROM _capability THEN
    RAISE EXCEPTION 'approval_action_mismatch' USING ERRCODE = '42501';
  END IF;
  IF v_req.status::text <> 'approved' THEN
    RAISE EXCEPTION 'approval_not_approved' USING ERRCODE = '42501';
  END IF;
  IF v_req.requested_by <> v_caller THEN
    RAISE EXCEPTION 'approval_requester_mismatch' USING ERRCODE = '42501';
  END IF;
  IF v_req.reviewed_by IS NULL OR v_req.reviewed_by = v_req.requested_by THEN
    RAISE EXCEPTION 'four_eyes_violation' USING ERRCODE = '42501';
  END IF;
  IF public.admin_role_canonical(v_req.reviewed_by) <> 'god_admin' THEN
    RAISE EXCEPTION 'approver_not_god_admin' USING ERRCODE = '42501';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_four_eyes_gate(text, uuid) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.admin_four_eyes_gate(text, uuid) FROM anon, PUBLIC;

-- 5. Close the missing guard on the test-delete logger
CREATE OR REPLACE FUNCTION public.admin_log_test_delete(_target uuid, _caller uuid, _reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF public.admin_role_canonical(auth.uid()) IS NULL THEN
    RAISE EXCEPTION 'insufficient_privilege' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.account_deletion_requests(user_id, requested_by, request_type, status, reason, processed_by)
  VALUES (_target, COALESCE(auth.uid(), _caller), 'admin_test_delete', 'processed', _reason, COALESCE(auth.uid(), _caller));
END;
$$;

-- 6. Remove anonymous EXECUTE from every admin_* RPC
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname LIKE 'admin\_%'
      AND has_function_privilege('anon', p.oid, 'EXECUTE')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', r.sig);
  END LOOP;
END $$;