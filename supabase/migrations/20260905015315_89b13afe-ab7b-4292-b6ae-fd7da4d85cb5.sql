-- G2.B — Full constitutional capability registry (44 capabilities x 3 classes).

ALTER TABLE public.admin_capability_grants
  ADD COLUMN IF NOT EXISTS constitutional boolean NOT NULL DEFAULT true;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='admin_capability_grants_pk_cap_role') THEN
    BEGIN
      ALTER TABLE public.admin_capability_grants
        ADD CONSTRAINT admin_capability_grants_pk_cap_role UNIQUE (capability, admin_role);
    EXCEPTION WHEN duplicate_table OR unique_violation THEN NULL;
    END;
  END IF;
END $$;

ALTER TABLE public.admin_capability_grants DROP CONSTRAINT IF EXISTS admin_capability_grants_mode_ck;
ALTER TABLE public.admin_capability_grants DROP CONSTRAINT IF EXISTS admin_capability_grants_mode_check;
ALTER TABLE public.admin_capability_grants
  ADD CONSTRAINT admin_capability_grants_mode_ck
  CHECK (mode IN ('allow','approval_required','read'));
ALTER TABLE public.admin_capability_grants DROP CONSTRAINT IF EXISTS admin_capability_grants_role_ck;
ALTER TABLE public.admin_capability_grants DROP CONSTRAINT IF EXISTS admin_capability_grants_admin_role_check;
ALTER TABLE public.admin_capability_grants
  ADD CONSTRAINT admin_capability_grants_role_ck
  CHECK (admin_role IN ('god_admin','operations_admin','finance_admin'));

-- Canonical matrix. Absence of a (capability, role) row = DENY.
DELETE FROM public.admin_capability_grants;
INSERT INTO public.admin_capability_grants (capability, admin_role, mode, note) VALUES
 ('ops.users.manage','operations_admin','allow','G2 constitution'),
 ('ops.users.manage','finance_admin','read','G2 constitution'),
 ('ops.users.manage','god_admin','allow','G2 constitution'),
 ('ops.drivers.manage','operations_admin','allow','G2 constitution'),
 ('ops.drivers.manage','finance_admin','read','G2 constitution'),
 ('ops.drivers.manage','god_admin','allow','G2 constitution'),
 ('ops.merchants.manage','operations_admin','allow','G2 constitution'),
 ('ops.merchants.manage','finance_admin','read','G2 constitution'),
 ('ops.merchants.manage','god_admin','allow','G2 constitution'),
 ('ops.orders.manage','operations_admin','allow','G2 constitution'),
 ('ops.orders.manage','finance_admin','read','G2 constitution'),
 ('ops.orders.manage','god_admin','allow','G2 constitution'),
 ('ops.support.manage','operations_admin','allow','G2 constitution'),
 ('ops.support.manage','finance_admin','read','G2 constitution'),
 ('ops.support.manage','god_admin','allow','G2 constitution'),
 ('ops.risk.manage','operations_admin','allow','G2 constitution'),
 ('ops.risk.manage','finance_admin','read','G2 constitution'),
 ('ops.risk.manage','god_admin','allow','G2 constitution'),
 ('ops.liveops.view','operations_admin','allow','G2 constitution'),
 ('ops.liveops.view','finance_admin','read','G2 constitution'),
 ('ops.liveops.view','god_admin','allow','G2 constitution'),
 ('ops.maps.manage','operations_admin','allow','G2 constitution'),
 ('ops.maps.manage','finance_admin','read','G2 constitution'),
 ('ops.maps.manage','god_admin','allow','G2 constitution'),
 ('ops.reports.view','operations_admin','allow','G2 constitution'),
 ('ops.reports.view','finance_admin','read','G2 constitution'),
 ('ops.reports.view','god_admin','allow','G2 constitution'),
 ('ops.flags.propose','operations_admin','allow','G2 constitution'),
 ('ops.flags.propose','god_admin','allow','G2 constitution'),
 ('ops.pricing.propose','operations_admin','allow','G2 constitution'),
 ('ops.pricing.propose','god_admin','allow','G2 constitution'),
 ('ops.audit.view_own_domain','operations_admin','allow','G2 constitution'),
 ('ops.audit.view_own_domain','finance_admin','read','G2 constitution'),
 ('ops.audit.view_own_domain','god_admin','allow','G2 constitution'),
 ('ops.onboarding.decide','operations_admin','allow','G2 constitution'),
 ('ops.onboarding.decide','god_admin','allow','G2 constitution'),
 ('ops.analytics.view','operations_admin','allow','G2 constitution'),
 ('ops.analytics.view','finance_admin','read','G2 constitution'),
 ('ops.analytics.view','god_admin','allow','G2 constitution'),
 ('ops.notifications.send','operations_admin','allow','G2 constitution'),
 ('ops.notifications.send','god_admin','allow','G2 constitution'),
 ('ops.notifications.broadcast','operations_admin','approval_required','G2 constitution'),
 ('ops.notifications.broadcast','god_admin','approval_required','G2 constitution'),
 ('finance.wallet.read','operations_admin','read','G2 constitution'),
 ('finance.wallet.read','finance_admin','allow','G2 constitution'),
 ('finance.wallet.read','god_admin','allow','G2 constitution'),
 ('finance.wallet.credit','finance_admin','approval_required','G2 constitution'),
 ('finance.wallet.credit','god_admin','approval_required','G2 constitution'),
 ('finance.wallet.adjust','finance_admin','approval_required','G2 constitution'),
 ('finance.wallet.adjust','god_admin','approval_required','G2 constitution'),
 ('finance.topup.manage','finance_admin','allow','G2 constitution'),
 ('finance.topup.manage','god_admin','allow','G2 constitution'),
 ('finance.payouts.manage','finance_admin','allow','G2 constitution'),
 ('finance.payouts.manage','god_admin','allow','G2 constitution'),
 ('finance.payout.confirm','finance_admin','approval_required','G2 constitution'),
 ('finance.payout.confirm','god_admin','approval_required','G2 constitution'),
 ('finance.reconciliation.approve','finance_admin','allow','G2 constitution'),
 ('finance.reconciliation.approve','god_admin','allow','G2 constitution'),
 ('finance.refund.approve','finance_admin','approval_required','G2 constitution'),
 ('finance.refund.approve','god_admin','approval_required','G2 constitution'),
 ('finance.treasury.read','finance_admin','allow','G2 constitution'),
 ('finance.treasury.read','god_admin','allow','G2 constitution'),
 ('finance.treasury.move','finance_admin','approval_required','G2 constitution'),
 ('finance.treasury.move','god_admin','approval_required','G2 constitution'),
 ('finance.policy.change','finance_admin','approval_required','G2 constitution'),
 ('finance.policy.change','god_admin','approval_required','G2 constitution'),
 ('finance.flags.payment','finance_admin','approval_required','G2 constitution'),
 ('finance.flags.payment','god_admin','approval_required','G2 constitution'),
 ('finance.audit.view_financial','operations_admin','read','G2 constitution'),
 ('finance.audit.view_financial','finance_admin','allow','G2 constitution'),
 ('finance.audit.view_financial','god_admin','allow','G2 constitution'),
 ('finance.dispute.resolve','finance_admin','approval_required','G2 constitution'),
 ('finance.dispute.resolve','god_admin','approval_required','G2 constitution'),
 ('finance.dormant.review','operations_admin','read','G2 constitution'),
 ('finance.dormant.review','finance_admin','allow','G2 constitution'),
 ('finance.dormant.review','god_admin','allow','G2 constitution'),
 ('governance.staff.manage','god_admin','approval_required','G2 constitution'),
 ('governance.roles.assign','god_admin','approval_required','G2 constitution'),
 ('governance.flags.manage','god_admin','allow','G2 constitution'),
 ('governance.pricing.change','god_admin','approval_required','G2 constitution'),
 ('governance.account.ban','operations_admin','allow','G2 constitution'),
 ('governance.account.ban','god_admin','allow','G2 constitution'),
 ('governance.account.freeze','operations_admin','allow','G2 constitution'),
 ('governance.account.freeze','finance_admin','approval_required','G2 constitution'),
 ('governance.account.freeze','god_admin','allow','G2 constitution'),
 ('governance.account.close','god_admin','approval_required','G2 constitution'),
 ('governance.account.anonymize','god_admin','approval_required','G2 constitution'),
 ('governance.professional.offboard','god_admin','approval_required','G2 constitution'),
 ('governance.audit.read_all','god_admin','allow','G2 constitution'),
 ('governance.settings.manage','god_admin','allow','G2 constitution'),
 ('governance.capability.resolve','operations_admin','allow','G2 constitution'),
 ('governance.capability.resolve','finance_admin','allow','G2 constitution'),
 ('governance.capability.resolve','god_admin','allow','G2 constitution'),
 ('governance.sandbox.run','god_admin','allow','G2 constitution');

-- Resolution primitives.
CREATE OR REPLACE FUNCTION public.admin_capability_mode(_capability text, _uid uuid DEFAULT auth.uid())
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_role text := public.admin_role_canonical(_uid); v_mode text;
BEGIN
  IF v_role IS NULL OR _capability IS NULL THEN RETURN NULL; END IF;
  SELECT g.mode INTO v_mode FROM public.admin_capability_grants g
   WHERE g.capability = _capability AND g.admin_role = v_role;
  RETURN v_mode;   -- NULL = unknown capability or denied class
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_capability(_capability text, _uid uuid DEFAULT auth.uid())
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$ SELECT public.admin_capability_mode(_capability, _uid) = 'allow'; $function$;

CREATE OR REPLACE FUNCTION public.admin_capability_read(_capability text, _uid uuid DEFAULT auth.uid())
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT public.admin_capability_mode(_capability, _uid) IN ('allow','approval_required','read');
$function$;

CREATE OR REPLACE FUNCTION public.admin_require_capability(_capability text)
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_mode text := public.admin_capability_mode(_capability, auth.uid());
BEGIN
  IF v_mode = 'allow' THEN RETURN; END IF;
  IF v_mode = 'approval_required' THEN
    RAISE EXCEPTION 'approval_required: %', _capability USING ERRCODE = '42501';
  END IF;
  RAISE EXCEPTION 'capability_denied: %', _capability USING ERRCODE = '42501';
END;
$function$;

-- Registry is governance authority: not mutable from a browser session.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.admin_capability_grants FROM authenticated, anon;
GRANT SELECT ON public.admin_capability_grants TO authenticated;
GRANT ALL ON public.admin_capability_grants TO service_role;
ALTER TABLE public.admin_capability_grants ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "capability grants readable by staff" ON public.admin_capability_grants;
DROP POLICY IF EXISTS "admin_capability_grants_read" ON public.admin_capability_grants;
DROP POLICY IF EXISTS "admin_capability_grants_write" ON public.admin_capability_grants;
CREATE POLICY "admin_capability_grants_read" ON public.admin_capability_grants
  FOR SELECT TO authenticated USING (public.admin_role_canonical(auth.uid()) IS NOT NULL);

REVOKE EXECUTE ON FUNCTION public.admin_capability_read(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_capability_read(text, uuid) TO authenticated, service_role;