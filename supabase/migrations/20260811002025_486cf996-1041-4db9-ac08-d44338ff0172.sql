-- ============================================================
-- SLICE 6 — Envoyer declared-value & claims engine (schema)
-- ============================================================

-- 1) Shipment-level declared value / tender / attestation / frozen snapshot
ALTER TABLE public.package_deliveries
  ADD COLUMN IF NOT EXISTS declared_value_gnf bigint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS tender text,
  ADD COLUMN IF NOT EXISTS value_attested_at timestamptz,
  ADD COLUMN IF NOT EXISTS value_attested_by uuid,
  ADD COLUMN IF NOT EXISTS value_attestation_statement text,
  ADD COLUMN IF NOT EXISTS value_attestation_version text,
  ADD COLUMN IF NOT EXISTS finance_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS claim_state text NOT NULL DEFAULT 'none';

DO $$ BEGIN
  ALTER TABLE public.package_deliveries
    ADD CONSTRAINT pd_declared_value_chk CHECK (declared_value_gnf >= 0);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE public.package_deliveries
    ADD CONSTRAINT pd_tender_chk CHECK (tender IS NULL OR tender IN ('cash','chop_pay'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE public.package_deliveries
    ADD CONSTRAINT pd_claim_state_chk
    CHECK (claim_state IN ('none','open','resolved','reconciliation_required'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 2) Private shipment evidence register (photos live in a private bucket)
CREATE TABLE IF NOT EXISTS public.package_evidence_photos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  quote_id uuid NOT NULL,
  package_id uuid REFERENCES public.package_deliveries(id) ON DELETE CASCADE,
  owner_user_id uuid NOT NULL,
  storage_bucket text NOT NULL DEFAULT 'package-evidence',
  storage_path text NOT NULL UNIQUE,
  kind text NOT NULL DEFAULT 'item',
  byte_size integer,
  content_type text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pep_kind_chk CHECK (kind IN ('item','packaging','label','condition'))
);

CREATE INDEX IF NOT EXISTS idx_pep_quote ON public.package_evidence_photos(quote_id);
CREATE INDEX IF NOT EXISTS idx_pep_package ON public.package_evidence_photos(package_id);

GRANT SELECT ON public.package_evidence_photos TO authenticated;
GRANT ALL ON public.package_evidence_photos TO service_role;

ALTER TABLE public.package_evidence_photos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pep_owner_read ON public.package_evidence_photos;
CREATE POLICY pep_owner_read ON public.package_evidence_photos
  FOR SELECT TO authenticated
  USING (owner_user_id = auth.uid());

DROP POLICY IF EXISTS pep_courier_read ON public.package_evidence_photos;
CREATE POLICY pep_courier_read ON public.package_evidence_photos
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.package_deliveries pd
      JOIN public.missions m ON m.id = pd.mission_id
     WHERE pd.id = package_evidence_photos.package_id
       AND m.courier_id = auth.uid()
  ));

DROP POLICY IF EXISTS pep_admin_read ON public.package_evidence_photos;
CREATE POLICY pep_admin_read ON public.package_evidence_photos
  FOR SELECT TO authenticated
  USING (public.is_any_admin(auth.uid()));

-- 3) Envoyer financial runtime (frozen economics)
CREATE TABLE IF NOT EXISTS public.package_runtime (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_key text NOT NULL UNIQUE,
  source_module text NOT NULL DEFAULT 'package',
  package_id uuid NOT NULL UNIQUE REFERENCES public.package_deliveries(id) ON DELETE CASCADE,
  mission_id uuid,
  mission_type text NOT NULL DEFAULT 'envoyer',
  customer_user_id uuid NOT NULL,
  driver_user_id uuid,
  tender text NOT NULL,
  declared_value_gnf bigint NOT NULL,
  delivery_fee_gnf bigint NOT NULL,
  platform_fee_gnf bigint NOT NULL DEFAULT 0,
  collateral_gnf bigint NOT NULL DEFAULT 0,
  claims_exposure_gnf bigint NOT NULL DEFAULT 0,
  customer_hold_gnf bigint NOT NULL DEFAULT 0,
  cash_due_gnf bigint NOT NULL DEFAULT 0,
  driver_earning_gnf bigint NOT NULL DEFAULT 0,
  platform_revenue_gnf bigint NOT NULL DEFAULT 0,
  claim_paid_gnf bigint NOT NULL DEFAULT 0,
  state text NOT NULL DEFAULT 'authorized',
  claim_state text NOT NULL DEFAULT 'none',
  policy_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  accepted_at timestamptz,
  picked_up_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  claim_opened_at timestamptz,
  resolved_at timestamptz,
  is_sandbox boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pr_tender_chk CHECK (tender IN ('cash','chop_pay')),
  CONSTRAINT pr_declared_chk CHECK (declared_value_gnf > 0),
  CONSTRAINT pr_delivery_chk CHECK (delivery_fee_gnf > 0),
  CONSTRAINT pr_amounts_chk CHECK (
    platform_fee_gnf >= 0 AND collateral_gnf >= 0 AND claims_exposure_gnf >= 0
    AND customer_hold_gnf >= 0 AND cash_due_gnf >= 0 AND claim_paid_gnf >= 0),
  CONSTRAINT pr_state_chk CHECK (state IN (
    'authorized','accepted','picked_up','completed','cancelled',
    'claim_open','resolved','reconciliation_required')),
  CONSTRAINT pr_claim_state_chk CHECK (claim_state IN (
    'none','open','upheld','denied','reconciliation_required'))
);

CREATE INDEX IF NOT EXISTS idx_pr_driver ON public.package_runtime(driver_user_id, state);
CREATE INDEX IF NOT EXISTS idx_pr_customer ON public.package_runtime(customer_user_id, state);
CREATE INDEX IF NOT EXISTS idx_pr_claims ON public.package_runtime(claim_state)
  WHERE claim_state <> 'none';

GRANT SELECT ON public.package_runtime TO authenticated;
GRANT ALL ON public.package_runtime TO service_role;

ALTER TABLE public.package_runtime ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pr_party_read ON public.package_runtime;
CREATE POLICY pr_party_read ON public.package_runtime
  FOR SELECT TO authenticated
  USING (customer_user_id = auth.uid() OR driver_user_id = auth.uid());

DROP POLICY IF EXISTS pr_admin_read ON public.package_runtime;
CREATE POLICY pr_admin_read ON public.package_runtime
  FOR SELECT TO authenticated
  USING (public.is_god_admin(auth.uid())
         OR public.has_admin_role(auth.uid(), 'finance_admin'::public.admin_role));

-- 4) Frozen economics are immutable after authorisation (DEF-FIN-S5-001 discipline)
CREATE OR REPLACE FUNCTION public._package_runtime_immutable()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.declared_value_gnf IS DISTINCT FROM OLD.declared_value_gnf
     OR NEW.delivery_fee_gnf IS DISTINCT FROM OLD.delivery_fee_gnf
     OR NEW.platform_fee_gnf IS DISTINCT FROM OLD.platform_fee_gnf
     OR NEW.collateral_gnf IS DISTINCT FROM OLD.collateral_gnf
     OR NEW.claims_exposure_gnf IS DISTINCT FROM OLD.claims_exposure_gnf
     OR NEW.customer_hold_gnf IS DISTINCT FROM OLD.customer_hold_gnf
     OR NEW.tender IS DISTINCT FROM OLD.tender
     OR NEW.package_id IS DISTINCT FROM OLD.package_id
     OR NEW.order_key IS DISTINCT FROM OLD.order_key
     OR NEW.policy_snapshot IS DISTINCT FROM OLD.policy_snapshot THEN
    RAISE EXCEPTION 'PACKAGE_FINANCE_SNAPSHOT_IMMUTABLE'
      USING DETAIL = 'Frozen Envoyer economics cannot be re-derived after authorisation';
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_package_runtime_immutable ON public.package_runtime;
CREATE TRIGGER trg_package_runtime_immutable
  BEFORE UPDATE ON public.package_runtime
  FOR EACH ROW EXECUTE FUNCTION public._package_runtime_immutable();

DROP TRIGGER IF EXISTS trg_pep_updated_at ON public.package_evidence_photos;
CREATE TRIGGER trg_pep_updated_at
  BEFORE UPDATE ON public.package_evidence_photos
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- 5) Slice 6 activation flags — both OFF
INSERT INTO public.feature_flags(key, enabled, description)
VALUES ('envoyer_declared_value_enabled', false,
        'Envoyer declared-value / collateral / claims runtime (Slice 6)')
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.feature_flags(key, enabled, description)
VALUES ('envoyer_claims_enabled', false, 'Envoyer claim opening and investigated resolution')
ON CONFLICT (key) DO NOTHING;