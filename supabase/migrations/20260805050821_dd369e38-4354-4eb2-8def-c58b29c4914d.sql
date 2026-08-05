-- ============ 1. Generalise mission_financial_holds into the canonical hold ============
ALTER TABLE public.mission_financial_holds
  ALTER COLUMN driver_user_id DROP NOT NULL,
  ADD COLUMN party_type public.party_type NOT NULL DEFAULT 'driver',
  ADD COLUMN party_user_id uuid,
  ADD COLUMN merchant_store_id uuid,
  ADD COLUMN customer_gnf bigint NOT NULL DEFAULT 0,
  ADD COLUMN platform_gnf bigint NOT NULL DEFAULT 0,
  ADD COLUMN released_gnf bigint NOT NULL DEFAULT 0,
  ADD COLUMN journal_key text,
  ADD COLUMN evidence_ref text;

UPDATE public.mission_financial_holds SET party_user_id = driver_user_id WHERE party_user_id IS NULL;

ALTER TABLE public.mission_financial_holds
  DROP CONSTRAINT IF EXISTS mfh_source_split_chk,
  DROP CONSTRAINT IF EXISTS mfh_kind_chk,
  DROP CONSTRAINT IF EXISTS mfh_state_chk;

ALTER TABLE public.mission_financial_holds
  ADD CONSTRAINT mfh_source_split_chk CHECK (
    unrestricted_gnf >= 0 AND promo_gnf >= 0 AND customer_gnf >= 0 AND platform_gnf >= 0
    AND (unrestricted_gnf + promo_gnf + customer_gnf + platform_gnf) = amount_gnf),
  ADD CONSTRAINT mfh_kind_chk CHECK (kind = ANY (ARRAY[
    'commission','collateral','platform_fee','cash_funding',
    'customer_payment','cashout','merchant_settlement','claims_reserve'])),
  ADD CONSTRAINT mfh_state_chk CHECK (state = ANY (ARRAY[
    'held','partially_captured','captured','released','frozen','reversed'])),
  ADD CONSTRAINT mfh_released_chk CHECK (released_gnf >= 0 AND captured_gnf + released_gnf <= amount_gnf),
  ADD CONSTRAINT mfh_party_chk CHECK (party_user_id IS NOT NULL OR merchant_store_id IS NOT NULL);

CREATE INDEX IF NOT EXISTS idx_mfh_party ON public.mission_financial_holds (party_user_id, state);
CREATE INDEX IF NOT EXISTS idx_mfh_store ON public.mission_financial_holds (merchant_store_id) WHERE merchant_store_id IS NOT NULL;

DROP POLICY IF EXISTS "Drivers read their own mission holds" ON public.mission_financial_holds;
CREATE POLICY "Parties read their own holds"
  ON public.mission_financial_holds FOR SELECT TO authenticated
  USING (
    driver_user_id = auth.uid()
    OR party_user_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.merchant_stores ms
                WHERE ms.id = mission_financial_holds.merchant_store_id
                  AND ms.owner_user_id = auth.uid())
  );

-- ============ 2. Merchant payables ============
CREATE TABLE public.merchant_payables (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payable_key       text NOT NULL UNIQUE,
  source_module     text NOT NULL,
  source_id         uuid NOT NULL,
  merchant_store_id uuid NOT NULL,
  merchant_user_id  uuid,
  mission_type      text,
  subtotal_gnf      bigint NOT NULL CHECK (subtotal_gnf >= 0),
  deduction_gnf     bigint NOT NULL DEFAULT 0 CHECK (deduction_gnf >= 0),
  amount_gnf        bigint NOT NULL CHECK (amount_gnf >= 0),
  funded_gnf        bigint NOT NULL DEFAULT 0 CHECK (funded_gnf >= 0),
  settled_gnf       bigint NOT NULL DEFAULT 0 CHECK (settled_gnf >= 0),
  state             text NOT NULL DEFAULT 'pending_funding'
                    CHECK (state IN ('pending_funding','funded','due','settlement_held','settled','reversed','disputed')),
  funding_source    text NOT NULL DEFAULT 'unknown'
                    CHECK (funding_source IN ('unknown','customer_choppay','driver_cash_funding','platform')),
  policy_snapshot   jsonb NOT NULL DEFAULT '{}'::jsonb,
  evidence_ref      text,
  reason            text,
  is_sandbox        boolean NOT NULL DEFAULT false,
  resolved_by       uuid,
  resolved_at       timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT merchant_payables_unique_source UNIQUE (source_module, source_id, merchant_store_id),
  CONSTRAINT merchant_payables_amounts_chk CHECK (settled_gnf <= amount_gnf AND funded_gnf <= amount_gnf)
);

GRANT SELECT ON public.merchant_payables TO authenticated;
GRANT ALL ON public.merchant_payables TO service_role;
ALTER TABLE public.merchant_payables ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Merchants read their own payables"
  ON public.merchant_payables FOR SELECT TO authenticated
  USING (
    merchant_user_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.merchant_stores ms
                WHERE ms.id = merchant_payables.merchant_store_id
                  AND ms.owner_user_id = auth.uid())
  );
CREATE POLICY "Finance and god admins read all payables"
  ON public.merchant_payables FOR SELECT TO authenticated
  USING (public.is_god_admin(auth.uid())
         OR public.has_admin_role(auth.uid(), 'finance_admin'::admin_role)
         OR public.has_admin_role(auth.uid(), 'operations_admin'::admin_role));

CREATE TRIGGER trg_merchant_payables_updated_at
  BEFORE UPDATE ON public.merchant_payables
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============ 3. Customer cancellation debts ============
CREATE TABLE public.customer_cancellation_debts (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  debt_key          text NOT NULL UNIQUE,
  customer_user_id  uuid NOT NULL,
  source_module     text NOT NULL,
  source_id         uuid NOT NULL,
  mission_type      text NOT NULL,
  stage             text NOT NULL CHECK (stage IN ('before_dispatch','after_dispatch')),
  basis_gnf         bigint NOT NULL CHECK (basis_gnf >= 0),
  applied_bps       integer NOT NULL CHECK (applied_bps >= 0 AND applied_bps <= 5000),
  amount_gnf        bigint NOT NULL CHECK (amount_gnf >= 0),
  paid_gnf          bigint NOT NULL DEFAULT 0 CHECK (paid_gnf >= 0),
  waived_gnf        bigint NOT NULL DEFAULT 0 CHECK (waived_gnf >= 0),
  state             text NOT NULL DEFAULT 'outstanding'
                    CHECK (state IN ('outstanding','paid','waived','reversed','exempt')),
  exempt_reason     text,
  policy_snapshot   jsonb NOT NULL DEFAULT '{}'::jsonb,
  is_sandbox        boolean NOT NULL DEFAULT false,
  resolved_by       uuid,
  resolved_at       timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ccd_unique_source UNIQUE (source_module, source_id),
  CONSTRAINT ccd_amounts_chk CHECK (paid_gnf + waived_gnf <= amount_gnf)
);

GRANT SELECT ON public.customer_cancellation_debts TO authenticated;
GRANT ALL ON public.customer_cancellation_debts TO service_role;
ALTER TABLE public.customer_cancellation_debts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Customers read their own cancellation debts"
  ON public.customer_cancellation_debts FOR SELECT TO authenticated
  USING (customer_user_id = auth.uid());
CREATE POLICY "Finance ops and god admins read all cancellation debts"
  ON public.customer_cancellation_debts FOR SELECT TO authenticated
  USING (public.is_god_admin(auth.uid())
         OR public.has_admin_role(auth.uid(), 'finance_admin'::admin_role)
         OR public.has_admin_role(auth.uid(), 'operations_admin'::admin_role));

CREATE TRIGGER trg_ccd_updated_at
  BEFORE UPDATE ON public.customer_cancellation_debts
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE INDEX idx_ccd_outstanding ON public.customer_cancellation_debts (customer_user_id)
  WHERE state = 'outstanding';

-- ============ 4. Claims reserve ============
CREATE TABLE public.claims_reserves (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  claim_key         text NOT NULL UNIQUE,
  source_module     text NOT NULL,
  source_id         uuid NOT NULL,
  mission_type      text,
  customer_user_id  uuid,
  driver_user_id    uuid,
  declared_value_gnf bigint NOT NULL DEFAULT 0 CHECK (declared_value_gnf >= 0),
  authorized_gnf    bigint NOT NULL CHECK (authorized_gnf >= 0),
  paid_gnf          bigint NOT NULL DEFAULT 0 CHECK (paid_gnf >= 0),
  released_gnf      bigint NOT NULL DEFAULT 0 CHECK (released_gnf >= 0),
  state             text NOT NULL DEFAULT 'allocated'
                    CHECK (state IN ('allocated','approved','paid','denied','released','reversed')),
  evidence_ref      text NOT NULL,
  reason            text NOT NULL,
  authorized_by     uuid NOT NULL,
  resolved_by       uuid,
  resolved_at       timestamptz,
  is_sandbox        boolean NOT NULL DEFAULT false,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT claims_reserves_unique_source UNIQUE (source_module, source_id),
  CONSTRAINT claims_reserves_amounts_chk CHECK (paid_gnf + released_gnf <= authorized_gnf)
);

GRANT SELECT ON public.claims_reserves TO authenticated;
GRANT ALL ON public.claims_reserves TO service_role;
ALTER TABLE public.claims_reserves ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Parties read their own claims"
  ON public.claims_reserves FOR SELECT TO authenticated
  USING (customer_user_id = auth.uid() OR driver_user_id = auth.uid());
CREATE POLICY "Finance and god admins read all claims"
  ON public.claims_reserves FOR SELECT TO authenticated
  USING (public.is_god_admin(auth.uid())
         OR public.has_admin_role(auth.uid(), 'finance_admin'::admin_role));

CREATE TRIGGER trg_claims_reserves_updated_at
  BEFORE UPDATE ON public.claims_reserves
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ============ 5. Policy schema: distinct fee / cancellation bases ============
ALTER TABLE public.finance_policies
  DROP CONSTRAINT IF EXISTS finance_policies_fee_basis_chk;
ALTER TABLE public.finance_policies
  ADD CONSTRAINT finance_policies_fee_basis_chk CHECK (fee_basis = ANY (ARRAY[
    'none','fare','merchandise_subtotal','declared_value','delivery_fee','order_total','transfer_amount']));

ALTER TABLE public.finance_policies
  ADD COLUMN IF NOT EXISTS cancel_basis text NOT NULL DEFAULT 'none';
ALTER TABLE public.finance_policies
  DROP CONSTRAINT IF EXISTS finance_policies_cancel_basis_chk;
ALTER TABLE public.finance_policies
  ADD CONSTRAINT finance_policies_cancel_basis_chk CHECK (cancel_basis = ANY (ARRAY[
    'none','fare','merchandise_plus_delivery','delivery_fee']));

ALTER TABLE public.finance_policies
  DROP CONSTRAINT IF EXISTS finance_policies_colbasis_chk;
ALTER TABLE public.finance_policies
  ADD COLUMN IF NOT EXISTS collateral_basis text NOT NULL DEFAULT 'none';
ALTER TABLE public.finance_policies
  ADD CONSTRAINT finance_policies_colbasis_chk CHECK (collateral_basis = ANY (ARRAY[
    'none','fare','merchandise_subtotal','declared_value']));