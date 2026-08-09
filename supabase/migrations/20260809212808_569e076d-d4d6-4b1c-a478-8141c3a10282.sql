-- =========================================================
-- SLICE 2 — FINANCE POLICY + CONTROL PLANE
-- Canonical authority: docs/product/chop-pay-canonical-operating-policy.md
-- No feature flag is activated by this migration.
-- =========================================================

-- ---------- A. APPEND-ONLY / EFFECTIVE-DATED HARDENING ----------

ALTER TABLE public.finance_policies
  ADD COLUMN IF NOT EXISTS claims_exposure_max_gnf bigint;

CREATE OR REPLACE FUNCTION public._policy_row_immutable()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  RAISE EXCEPTION 'POLICY_ROW_IMMUTABLE'
    USING DETAIL = format('%s rows are append-only; create a new effective-dated row instead', TG_TABLE_NAME);
  RETURN NULL;
END; $$;

DROP TRIGGER IF EXISTS finance_policies_immutable ON public.finance_policies;
CREATE TRIGGER finance_policies_immutable
  BEFORE UPDATE OR DELETE ON public.finance_policies
  FOR EACH ROW EXECUTE FUNCTION public._policy_row_immutable();

DROP TRIGGER IF EXISTS starter_credit_policies_immutable ON public.driver_starter_credit_policies;
CREATE TRIGGER starter_credit_policies_immutable
  BEFORE UPDATE OR DELETE ON public.driver_starter_credit_policies
  FOR EACH ROW EXECUTE FUNCTION public._policy_row_immutable();

CREATE UNIQUE INDEX IF NOT EXISTS finance_policies_type_effective_uniq
  ON public.finance_policies (mission_type, effective_from);
CREATE UNIQUE INDEX IF NOT EXISTS starter_credit_policies_effective_uniq
  ON public.driver_starter_credit_policies (effective_from);

-- as-of resolution
CREATE OR REPLACE FUNCTION public.finance_policy_at(p_mission_type text, p_as_of timestamptz DEFAULT now())
RETURNS public.finance_policies
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT * FROM public.finance_policies
   WHERE mission_type = p_mission_type
     AND enabled = true
     AND effective_from <= COALESCE(p_as_of, now())
   ORDER BY effective_from DESC, created_at DESC
   LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.finance_policy_current(p_mission_type text)
RETURNS public.finance_policies
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT * FROM public.finance_policy_at(p_mission_type, now()); $$;

CREATE OR REPLACE FUNCTION public.starter_credit_policy_at(p_as_of timestamptz DEFAULT now())
RETURNS public.driver_starter_credit_policies
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT * FROM public.driver_starter_credit_policies
   WHERE enabled = true AND effective_from <= COALESCE(p_as_of, now())
   ORDER BY effective_from DESC, created_at DESC
   LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.starter_credit_policy_current()
RETURNS public.driver_starter_credit_policies
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT * FROM public.starter_credit_policy_at(now()); $$;

-- ---------- F. PAYOUT / SETTLEMENT / PROVIDER FEE POLICY ----------

CREATE TABLE IF NOT EXISTS public.driver_payout_policies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  min_request_gnf bigint NOT NULL DEFAULT 10000,
  max_request_gnf bigint NOT NULL DEFAULT 500000,
  daily_limit_gnf bigint NOT NULL DEFAULT 250000,
  one_pending_request_only boolean NOT NULL DEFAULT true,
  registered_om_phone_only boolean NOT NULL DEFAULT true,
  processing_estimate_min_minutes integer NOT NULL DEFAULT 1,
  processing_estimate_max_minutes integer NOT NULL DEFAULT 5,
  cancel_window_seconds integer NOT NULL DEFAULT 60,
  provider_fee_passthrough boolean NOT NULL DEFAULT true,
  block_on_dispute_or_freeze boolean NOT NULL DEFAULT true,
  restricted_funds_withdrawable boolean NOT NULL DEFAULT false,
  effective_from timestamptz NOT NULL DEFAULT now(),
  enabled boolean NOT NULL DEFAULT true,
  note text,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT driver_payout_policies_sane CHECK (
    min_request_gnf >= 0
    AND max_request_gnf >= min_request_gnf
    AND daily_limit_gnf >= min_request_gnf
    AND processing_estimate_max_minutes >= processing_estimate_min_minutes
    AND cancel_window_seconds >= 0
    AND restricted_funds_withdrawable = false
  )
);
GRANT SELECT ON public.driver_payout_policies TO authenticated;
GRANT ALL ON public.driver_payout_policies TO service_role;
ALTER TABLE public.driver_payout_policies ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated read payout policy" ON public.driver_payout_policies FOR SELECT TO authenticated USING (true);

CREATE UNIQUE INDEX IF NOT EXISTS driver_payout_policies_effective_uniq
  ON public.driver_payout_policies (effective_from);
DROP TRIGGER IF EXISTS driver_payout_policies_immutable ON public.driver_payout_policies;
CREATE TRIGGER driver_payout_policies_immutable
  BEFORE UPDATE OR DELETE ON public.driver_payout_policies
  FOR EACH ROW EXECUTE FUNCTION public._policy_row_immutable();

CREATE TABLE IF NOT EXISTS public.merchant_settlement_policies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  configured boolean NOT NULL DEFAULT false,
  min_settlement_gnf bigint,
  max_settlement_gnf bigint,
  cadence text,
  fee_bps integer,
  fee_fixed_gnf bigint,
  fee_passthrough boolean,
  requires_evidence_reconciliation boolean NOT NULL DEFAULT true,
  effective_from timestamptz NOT NULL DEFAULT now(),
  enabled boolean NOT NULL DEFAULT true,
  note text,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT merchant_settlement_policies_sane CHECK (
    (cadence IS NULL OR cadence IN ('daily','weekly','biweekly','monthly','on_demand'))
    AND (fee_bps IS NULL OR (fee_bps >= 0 AND fee_bps <= 10000))
    AND (min_settlement_gnf IS NULL OR min_settlement_gnf >= 0)
    AND (max_settlement_gnf IS NULL OR min_settlement_gnf IS NULL OR max_settlement_gnf >= min_settlement_gnf)
    AND requires_evidence_reconciliation = true
  )
);
GRANT SELECT ON public.merchant_settlement_policies TO authenticated;
GRANT ALL ON public.merchant_settlement_policies TO service_role;
ALTER TABLE public.merchant_settlement_policies ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated read settlement policy" ON public.merchant_settlement_policies FOR SELECT TO authenticated USING (true);

CREATE UNIQUE INDEX IF NOT EXISTS merchant_settlement_policies_effective_uniq
  ON public.merchant_settlement_policies (effective_from);
DROP TRIGGER IF EXISTS merchant_settlement_policies_immutable ON public.merchant_settlement_policies;
CREATE TRIGGER merchant_settlement_policies_immutable
  BEFORE UPDATE OR DELETE ON public.merchant_settlement_policies
  FOR EACH ROW EXECUTE FUNCTION public._policy_row_immutable();

CREATE TABLE IF NOT EXISTS public.provider_fee_schedules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider text NOT NULL DEFAULT 'orange_money',
  fee_bps integer NOT NULL DEFAULT 0,
  fee_fixed_gnf bigint NOT NULL DEFAULT 0,
  min_fee_gnf bigint NOT NULL DEFAULT 0,
  max_fee_gnf bigint,
  passthrough_to_recipient boolean NOT NULL DEFAULT true,
  effective_from timestamptz NOT NULL DEFAULT now(),
  enabled boolean NOT NULL DEFAULT true,
  note text,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT provider_fee_schedules_sane CHECK (
    fee_bps >= 0 AND fee_bps <= 10000 AND fee_fixed_gnf >= 0 AND min_fee_gnf >= 0
    AND (max_fee_gnf IS NULL OR max_fee_gnf >= min_fee_gnf)
  )
);
GRANT SELECT ON public.provider_fee_schedules TO authenticated;
GRANT ALL ON public.provider_fee_schedules TO service_role;
ALTER TABLE public.provider_fee_schedules ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Authenticated read provider fees" ON public.provider_fee_schedules FOR SELECT TO authenticated USING (true);

CREATE UNIQUE INDEX IF NOT EXISTS provider_fee_schedules_effective_uniq
  ON public.provider_fee_schedules (provider, effective_from);
DROP TRIGGER IF EXISTS provider_fee_schedules_immutable ON public.provider_fee_schedules;
CREATE TRIGGER provider_fee_schedules_immutable
  BEFORE UPDATE OR DELETE ON public.provider_fee_schedules
  FOR EACH ROW EXECUTE FUNCTION public._policy_row_immutable();

CREATE OR REPLACE FUNCTION public.driver_payout_policy_at(p_as_of timestamptz DEFAULT now())
RETURNS public.driver_payout_policies
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT * FROM public.driver_payout_policies
   WHERE enabled = true AND effective_from <= COALESCE(p_as_of, now())
   ORDER BY effective_from DESC, created_at DESC LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.merchant_settlement_policy_at(p_as_of timestamptz DEFAULT now())
RETURNS public.merchant_settlement_policies
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT * FROM public.merchant_settlement_policies
   WHERE enabled = true AND effective_from <= COALESCE(p_as_of, now())
   ORDER BY effective_from DESC, created_at DESC LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.provider_fee_schedule_at(p_provider text DEFAULT 'orange_money', p_as_of timestamptz DEFAULT now())
RETURNS public.provider_fee_schedules
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT * FROM public.provider_fee_schedules
   WHERE provider = COALESCE(p_provider,'orange_money')
     AND enabled = true AND effective_from <= COALESCE(p_as_of, now())
   ORDER BY effective_from DESC, created_at DESC LIMIT 1;
$$;

-- Seed canonical launch rows (documented, activation still OFF)
INSERT INTO public.driver_payout_policies (note)
SELECT 'Slice 2 canonical launch defaults (driver_cashout_enabled = OFF)'
WHERE NOT EXISTS (SELECT 1 FROM public.driver_payout_policies);

INSERT INTO public.merchant_settlement_policies (configured, note)
SELECT false, 'Slice 2 placeholder — merchant settlement not yet configured'
WHERE NOT EXISTS (SELECT 1 FROM public.merchant_settlement_policies);

INSERT INTO public.provider_fee_schedules (provider, fee_bps, fee_fixed_gnf, note)
SELECT 'orange_money', 0, 0, 'Slice 2 placeholder — real OM fee schedule not yet contracted'
WHERE NOT EXISTS (SELECT 1 FROM public.provider_fee_schedules WHERE provider = 'orange_money');

-- ---------- Delegation switch (God Admin owns it) ----------
INSERT INTO public.app_settings (key, value, description)
VALUES ('finance_delegation',
        jsonb_build_object('provider_fee_to_finance_admin', false),
        'God Admin delegation switches for operational finance configuration')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.admin_set_finance_delegation(p_provider_fee_to_finance_admin boolean, p_note text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_caller uuid := auth.uid(); v_before jsonb; v_after jsonb;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.is_god_admin(v_caller) THEN RAISE EXCEPTION 'Only a God Admin can change finance delegation'; END IF;
  SELECT value INTO v_before FROM public.app_settings WHERE key = 'finance_delegation';
  v_after := COALESCE(v_before,'{}'::jsonb) || jsonb_build_object('provider_fee_to_finance_admin', COALESCE(p_provider_fee_to_finance_admin,false));
  UPDATE public.app_settings SET value = v_after, updated_at = now(), updated_by = v_caller WHERE key = 'finance_delegation';
  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, before, after, note)
  VALUES (v_caller,'pricing','finance_delegation_set','app_setting','finance_delegation', v_before, v_after, p_note);
  RETURN v_after;
END; $$;

-- ---------- B/C. GOD ADMIN POLICY WRITER (hardened) ----------

CREATE OR REPLACE FUNCTION public.admin_set_finance_policy(
  p_mission_type text,
  p_commission_bps integer,
  p_min_driver_balance_gnf bigint DEFAULT 0,
  p_collateral_mode text DEFAULT 'none',
  p_collateral_pct_bps integer DEFAULT 0,
  p_collateral_fixed_gnf bigint DEFAULT 0,
  p_collateral_min_gnf bigint DEFAULT 0,
  p_collateral_max_gnf bigint DEFAULT NULL,
  p_fixed_commission_gnf bigint DEFAULT 0,
  p_require_collateral_before_offer boolean DEFAULT false,
  p_effective_from timestamptz DEFAULT now(),
  p_note text DEFAULT NULL,
  p_collateral_basis text DEFAULT NULL,
  p_transaction_fee_bps integer DEFAULT NULL,
  p_fee_basis text DEFAULT NULL,
  p_cancel_before_dispatch_bps integer DEFAULT NULL,
  p_cancel_after_dispatch_bps integer DEFAULT NULL,
  p_cancel_basis text DEFAULT NULL,
  p_cash_funding_mode text DEFAULT NULL,
  p_cash_funding_pct_bps integer DEFAULT NULL,
  p_cash_funding_max_gnf bigint DEFAULT NULL,
  p_max_declared_value_gnf bigint DEFAULT NULL,
  p_claims_exposure_max_gnf bigint DEFAULT NULL
)
RETURNS public.finance_policies
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_before public.finance_policies;
  v_new public.finance_policies;
  v_latest timestamptz;
  v_collateral_bps integer;
  v_exposure_bps integer;
  v_max_declared bigint;
  v_claims_max bigint;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.is_god_admin(v_caller) THEN
    RAISE EXCEPTION 'Only a God Admin can change finance policy';
  END IF;
  IF p_mission_type NOT IN ('ride','bonbonna','repas','marche','envoyer') THEN
    RAISE EXCEPTION 'Unknown mission type %', p_mission_type;
  END IF;
  IF p_effective_from < now() - interval '1 minute' THEN
    RAISE EXCEPTION 'BACKDATING_REJECTED'
      USING DETAIL = 'Effective date cannot be in the past; policy history is immutable';
  END IF;

  -- serialize concurrent saves for the same service so resolution stays unambiguous
  PERFORM pg_advisory_xact_lock(hashtext('finance_policy:' || p_mission_type));

  SELECT max(effective_from) INTO v_latest
    FROM public.finance_policies WHERE mission_type = p_mission_type;
  IF v_latest IS NOT NULL AND p_effective_from <= v_latest THEN
    RAISE EXCEPTION 'EFFECTIVE_FROM_NOT_MONOTONIC'
      USING DETAIL = format('A policy already exists at or after %s for %s', v_latest, p_mission_type);
  END IF;

  SELECT * INTO v_before FROM public.finance_policy_current(p_mission_type);

  IF p_collateral_basis IS NOT NULL
     AND p_collateral_basis NOT IN ('none','fare','merchandise_subtotal','declared_value') THEN
    RAISE EXCEPTION 'Invalid collateral basis';
  END IF;
  IF p_cancel_basis IS NOT NULL
     AND p_cancel_basis NOT IN ('none','fare','merchandise_plus_delivery','delivery_fee') THEN
    RAISE EXCEPTION 'Invalid cancellation basis';
  END IF;
  IF p_fee_basis IS NOT NULL
     AND p_fee_basis NOT IN ('none','fare','merchandise_subtotal','declared_value','delivery_fee','order_total','transfer_amount') THEN
    RAISE EXCEPTION 'Invalid fee basis';
  END IF;
  IF p_collateral_mode <> 'none' AND COALESCE(p_collateral_basis, v_before.collateral_basis, 'none') = 'none' THEN
    RAISE EXCEPTION 'COLLATERAL_BASIS_REQUIRED';
  END IF;
  IF COALESCE(p_transaction_fee_bps, v_before.transaction_fee_bps, 0) > 0
     AND COALESCE(p_fee_basis, v_before.fee_basis, 'none') = 'none' THEN
    RAISE EXCEPTION 'FEE_BASIS_REQUIRED';
  END IF;
  IF GREATEST(COALESCE(p_cancel_before_dispatch_bps, v_before.cancel_before_dispatch_bps, 0),
              COALESCE(p_cancel_after_dispatch_bps, v_before.cancel_after_dispatch_bps, 0)) > 0
     AND COALESCE(p_cancel_basis, v_before.cancel_basis, 'none') = 'none' THEN
    RAISE EXCEPTION 'CANCEL_BASIS_REQUIRED';
  END IF;
  IF COALESCE(p_commission_bps,0) < 0 OR COALESCE(p_commission_bps,0) > 10000 THEN
    RAISE EXCEPTION 'COMMISSION_BPS_OUT_OF_RANGE';
  END IF;
  IF COALESCE(p_collateral_pct_bps,0) < 0 OR COALESCE(p_collateral_pct_bps,0) > 10000 THEN
    RAISE EXCEPTION 'COLLATERAL_BPS_OUT_OF_RANGE';
  END IF;

  -- E. claims exposure: platform share is the remainder of the declared value
  v_collateral_bps := COALESCE(p_collateral_pct_bps, 0);
  v_exposure_bps := 10000 - v_collateral_bps;
  v_max_declared := COALESCE(p_max_declared_value_gnf, v_before.max_declared_value_gnf);
  v_claims_max := COALESCE(p_claims_exposure_max_gnf, v_before.claims_exposure_max_gnf);

  IF p_mission_type = 'envoyer' THEN
    IF v_max_declared IS NULL OR v_max_declared <= 0 THEN
      RAISE EXCEPTION 'MAX_DECLARED_VALUE_REQUIRED';
    END IF;
    IF v_claims_max IS NULL THEN
      v_claims_max := (v_max_declared * v_exposure_bps) / 10000;
    END IF;
    IF v_claims_max > (v_max_declared * v_exposure_bps) / 10000 THEN
      RAISE EXCEPTION 'CLAIMS_EXPOSURE_EXCEEDS_REMAINDER'
        USING DETAIL = format('Collateral %s bps leaves at most %s GNF of platform exposure at a %s GNF cap',
                              v_collateral_bps, (v_max_declared * v_exposure_bps) / 10000, v_max_declared);
    END IF;
  ELSE
    v_claims_max := NULL;
  END IF;

  INSERT INTO public.finance_policies
    (mission_type, commission_bps, fixed_commission_gnf, min_driver_balance_gnf,
     collateral_mode, collateral_pct_bps, collateral_fixed_gnf,
     collateral_min_gnf, collateral_max_gnf, require_collateral_before_offer,
     collateral_basis, transaction_fee_bps, fee_basis,
     cancel_before_dispatch_bps, cancel_after_dispatch_bps, cancel_basis,
     cash_funding_mode, cash_funding_pct_bps, cash_funding_max_gnf,
     max_declared_value_gnf, claims_exposure_max_gnf, effective_from, note, created_by)
  VALUES
    (p_mission_type, p_commission_bps, p_fixed_commission_gnf, p_min_driver_balance_gnf,
     p_collateral_mode, p_collateral_pct_bps, p_collateral_fixed_gnf,
     p_collateral_min_gnf, p_collateral_max_gnf, p_require_collateral_before_offer,
     COALESCE(p_collateral_basis, v_before.collateral_basis, 'none'),
     COALESCE(p_transaction_fee_bps, v_before.transaction_fee_bps, 0),
     COALESCE(p_fee_basis, v_before.fee_basis, 'none'),
     COALESCE(p_cancel_before_dispatch_bps, v_before.cancel_before_dispatch_bps, 500),
     COALESCE(p_cancel_after_dispatch_bps, v_before.cancel_after_dispatch_bps, 1000),
     COALESCE(p_cancel_basis, v_before.cancel_basis, 'none'),
     COALESCE(p_cash_funding_mode, v_before.cash_funding_mode, 'none'),
     COALESCE(p_cash_funding_pct_bps, v_before.cash_funding_pct_bps, 0),
     COALESCE(p_cash_funding_max_gnf, v_before.cash_funding_max_gnf),
     v_max_declared, v_claims_max,
     p_effective_from, p_note, v_caller)
  RETURNING * INTO v_new;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, before, after, note)
  VALUES (v_caller, 'pricing', 'finance_policy_set', 'finance_policy', p_mission_type,
          to_jsonb(v_before), to_jsonb(v_new), p_note);

  RETURN v_new;
END; $$;

-- Starter bonus writer: God Admin only, monotonic, audited
CREATE OR REPLACE FUNCTION public.admin_set_starter_credit_policy(
  p_amount_gnf bigint,
  p_enabled boolean DEFAULT true,
  p_effective_from timestamptz DEFAULT now(),
  p_note text DEFAULT NULL
)
RETURNS public.driver_starter_credit_policies
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_before public.driver_starter_credit_policies;
  v_new public.driver_starter_credit_policies;
  v_latest timestamptz;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.is_god_admin(v_caller) THEN
    RAISE EXCEPTION 'Only a God Admin can change the starter credit policy';
  END IF;
  IF p_effective_from < now() - interval '1 minute' THEN
    RAISE EXCEPTION 'BACKDATING_REJECTED';
  END IF;
  IF p_amount_gnf IS NULL OR p_amount_gnf < 0 THEN RAISE EXCEPTION 'INVALID_AMOUNT'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext('starter_credit_policy'));
  SELECT max(effective_from) INTO v_latest FROM public.driver_starter_credit_policies;
  IF v_latest IS NOT NULL AND p_effective_from <= v_latest THEN
    RAISE EXCEPTION 'EFFECTIVE_FROM_NOT_MONOTONIC';
  END IF;

  SELECT * INTO v_before FROM public.starter_credit_policy_current();

  INSERT INTO public.driver_starter_credit_policies (amount_gnf, enabled, effective_from, note, created_by)
  VALUES (p_amount_gnf, COALESCE(p_enabled, true), p_effective_from, p_note, v_caller)
  RETURNING * INTO v_new;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, before, after, note)
  VALUES (v_caller, 'wallet', 'starter_credit_policy_set', 'starter_credit_policy', v_new.id::text,
          to_jsonb(v_before), to_jsonb(v_new), p_note);
  RETURN v_new;
END; $$;

-- Payout policy writer
CREATE OR REPLACE FUNCTION public.admin_set_payout_policy(
  p_min_request_gnf bigint,
  p_max_request_gnf bigint,
  p_daily_limit_gnf bigint,
  p_cancel_window_seconds integer DEFAULT 60,
  p_processing_estimate_min_minutes integer DEFAULT 1,
  p_processing_estimate_max_minutes integer DEFAULT 5,
  p_provider_fee_passthrough boolean DEFAULT true,
  p_effective_from timestamptz DEFAULT now(),
  p_note text DEFAULT NULL
)
RETURNS public.driver_payout_policies
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_before public.driver_payout_policies;
  v_new public.driver_payout_policies;
  v_latest timestamptz;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.is_god_admin(v_caller) THEN
    RAISE EXCEPTION 'Only a God Admin can change payout policy';
  END IF;
  IF p_effective_from < now() - interval '1 minute' THEN RAISE EXCEPTION 'BACKDATING_REJECTED'; END IF;
  IF p_daily_limit_gnf < p_min_request_gnf THEN RAISE EXCEPTION 'DAILY_LIMIT_BELOW_MINIMUM'; END IF;
  IF p_max_request_gnf < p_min_request_gnf THEN RAISE EXCEPTION 'MAX_BELOW_MINIMUM'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext('driver_payout_policy'));
  SELECT max(effective_from) INTO v_latest FROM public.driver_payout_policies;
  IF v_latest IS NOT NULL AND p_effective_from <= v_latest THEN
    RAISE EXCEPTION 'EFFECTIVE_FROM_NOT_MONOTONIC';
  END IF;

  SELECT * INTO v_before FROM public.driver_payout_policy_at(now());

  INSERT INTO public.driver_payout_policies
    (min_request_gnf, max_request_gnf, daily_limit_gnf, cancel_window_seconds,
     processing_estimate_min_minutes, processing_estimate_max_minutes,
     provider_fee_passthrough, effective_from, note, created_by)
  VALUES
    (p_min_request_gnf, p_max_request_gnf, p_daily_limit_gnf, p_cancel_window_seconds,
     p_processing_estimate_min_minutes, p_processing_estimate_max_minutes,
     COALESCE(p_provider_fee_passthrough, true), p_effective_from, p_note, v_caller)
  RETURNING * INTO v_new;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, before, after, note)
  VALUES (v_caller,'wallet','payout_policy_set','driver_payout_policy', v_new.id::text,
          to_jsonb(v_before), to_jsonb(v_new), p_note);
  RETURN v_new;
END; $$;

-- Merchant settlement policy writer
CREATE OR REPLACE FUNCTION public.admin_set_merchant_settlement_policy(
  p_configured boolean,
  p_min_settlement_gnf bigint DEFAULT NULL,
  p_max_settlement_gnf bigint DEFAULT NULL,
  p_cadence text DEFAULT NULL,
  p_fee_bps integer DEFAULT NULL,
  p_fee_fixed_gnf bigint DEFAULT NULL,
  p_fee_passthrough boolean DEFAULT NULL,
  p_effective_from timestamptz DEFAULT now(),
  p_note text DEFAULT NULL
)
RETURNS public.merchant_settlement_policies
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_before public.merchant_settlement_policies;
  v_new public.merchant_settlement_policies;
  v_latest timestamptz;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.is_god_admin(v_caller) THEN
    RAISE EXCEPTION 'Only a God Admin can change merchant settlement policy';
  END IF;
  IF p_effective_from < now() - interval '1 minute' THEN RAISE EXCEPTION 'BACKDATING_REJECTED'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext('merchant_settlement_policy'));
  SELECT max(effective_from) INTO v_latest FROM public.merchant_settlement_policies;
  IF v_latest IS NOT NULL AND p_effective_from <= v_latest THEN
    RAISE EXCEPTION 'EFFECTIVE_FROM_NOT_MONOTONIC';
  END IF;

  SELECT * INTO v_before FROM public.merchant_settlement_policy_at(now());

  INSERT INTO public.merchant_settlement_policies
    (configured, min_settlement_gnf, max_settlement_gnf, cadence, fee_bps, fee_fixed_gnf,
     fee_passthrough, effective_from, note, created_by)
  VALUES
    (COALESCE(p_configured,false), p_min_settlement_gnf, p_max_settlement_gnf, p_cadence,
     p_fee_bps, p_fee_fixed_gnf, p_fee_passthrough, p_effective_from, p_note, v_caller)
  RETURNING * INTO v_new;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, before, after, note)
  VALUES (v_caller,'wallet','merchant_settlement_policy_set','merchant_settlement_policy', v_new.id::text,
          to_jsonb(v_before), to_jsonb(v_new), p_note);
  RETURN v_new;
END; $$;

-- Provider fee schedule: God Admin, or Finance Admin only when explicitly delegated
CREATE OR REPLACE FUNCTION public.admin_set_provider_fee_schedule(
  p_provider text,
  p_fee_bps integer,
  p_fee_fixed_gnf bigint DEFAULT 0,
  p_min_fee_gnf bigint DEFAULT 0,
  p_max_fee_gnf bigint DEFAULT NULL,
  p_passthrough_to_recipient boolean DEFAULT true,
  p_effective_from timestamptz DEFAULT now(),
  p_note text DEFAULT NULL
)
RETURNS public.provider_fee_schedules
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_god boolean;
  v_delegated boolean;
  v_finance boolean;
  v_before public.provider_fee_schedules;
  v_new public.provider_fee_schedules;
  v_latest timestamptz;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  v_god := public.is_god_admin(v_caller);
  v_finance := public.has_role(v_caller, 'finance_admin');
  SELECT COALESCE((value->>'provider_fee_to_finance_admin')::boolean,false) INTO v_delegated
    FROM public.app_settings WHERE key = 'finance_delegation';
  IF NOT (v_god OR (v_finance AND COALESCE(v_delegated,false))) THEN
    RAISE EXCEPTION 'PROVIDER_FEE_WRITE_DENIED'
      USING DETAIL = 'God Admin, or Finance Admin with explicit delegation, only';
  END IF;
  IF p_effective_from < now() - interval '1 minute' THEN RAISE EXCEPTION 'BACKDATING_REJECTED'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext('provider_fee:' || COALESCE(p_provider,'orange_money')));
  SELECT max(effective_from) INTO v_latest FROM public.provider_fee_schedules
   WHERE provider = COALESCE(p_provider,'orange_money');
  IF v_latest IS NOT NULL AND p_effective_from <= v_latest THEN
    RAISE EXCEPTION 'EFFECTIVE_FROM_NOT_MONOTONIC';
  END IF;

  SELECT * INTO v_before FROM public.provider_fee_schedule_at(COALESCE(p_provider,'orange_money'), now());

  INSERT INTO public.provider_fee_schedules
    (provider, fee_bps, fee_fixed_gnf, min_fee_gnf, max_fee_gnf, passthrough_to_recipient,
     effective_from, note, created_by)
  VALUES
    (COALESCE(p_provider,'orange_money'), p_fee_bps, COALESCE(p_fee_fixed_gnf,0),
     COALESCE(p_min_fee_gnf,0), p_max_fee_gnf, COALESCE(p_passthrough_to_recipient,true),
     p_effective_from, p_note, v_caller)
  RETURNING * INTO v_new;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, before, after, note)
  VALUES (v_caller,'wallet','provider_fee_schedule_set','provider_fee_schedule', v_new.id::text,
          to_jsonb(v_before), to_jsonb(v_new), p_note);
  RETURN v_new;
END; $$;

-- ---------- G. FEATURE FLAG CONTROL PLANE ----------

INSERT INTO public.feature_flags (key, enabled, description) VALUES
  ('chop_pay_balance_enabled', false, 'Affichage du solde Chop Pay côté client'),
  ('chop_pay_ecosystem_spend_enabled', false, 'Dépense Chop Pay dans l''écosystème CHOPCHOP'),
  ('merchant_wallet_enabled', false, 'Portefeuille marchand (passif CHOPCHOP)'),
  ('om_payout_reconciliation_enabled', false, 'Réconciliation des paiements sortants Orange Money'),
  ('non_ride_transaction_fee_enabled', false, 'Frais de transaction hors course (1%)'),
  ('cancellation_policy_enabled', false, 'Frais d''annulation client'),
  ('envoyer_claims_enabled', false, 'Réserve de sinistres Envoyer (enquête, pas assurance)')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.admin_set_feature_flag(p_key text, p_enabled boolean, p_note text DEFAULT NULL)
RETURNS public.feature_flags
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_before public.feature_flags;
  v_new public.feature_flags;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.is_god_admin(v_caller) THEN
    RAISE EXCEPTION 'Only a God Admin can change feature flags';
  END IF;
  SELECT * INTO v_before FROM public.feature_flags WHERE key = p_key;
  IF v_before.key IS NULL THEN RAISE EXCEPTION 'UNKNOWN_FLAG %', p_key; END IF;

  UPDATE public.feature_flags
     SET enabled = COALESCE(p_enabled,false), updated_at = now(), updated_by = v_caller
   WHERE key = p_key
  RETURNING * INTO v_new;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, before, after, note)
  VALUES (v_caller,'flags','feature_flag_set','feature_flag', p_key,
          to_jsonb(v_before), to_jsonb(v_new), p_note);
  RETURN v_new;
END; $$;

-- Direct table writes are no longer a supported path: RPC only.
DROP POLICY IF EXISTS "Super admins write flags" ON public.feature_flags;
CREATE POLICY "God admins write flags" ON public.feature_flags
  FOR ALL TO authenticated
  USING (public.is_god_admin(auth.uid()))
  WITH CHECK (public.is_god_admin(auth.uid()));

-- ---------- H. CANONICAL POLICY SNAPSHOT (v2) ----------

CREATE OR REPLACE FUNCTION public.finance_policy_snapshot(
  p_mission_type text,
  p_as_of timestamptz DEFAULT now(),
  p_payment_mode text DEFAULT 'chop_pay',
  p_fare_gnf bigint DEFAULT 0,
  p_merchandise_subtotal_gnf bigint DEFAULT 0,
  p_delivery_fee_gnf bigint DEFAULT 0,
  p_declared_value_gnf bigint DEFAULT 0,
  p_is_sandbox boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  p public.finance_policies;
  s public.driver_starter_credit_policies;
  po public.driver_payout_policies;
  pf public.provider_fee_schedules;
  v_as_of timestamptz := COALESCE(p_as_of, now());
  v_exposure_bps integer;
  v_claim_envelope bigint;
BEGIN
  SELECT * INTO p FROM public.finance_policy_at(p_mission_type, v_as_of);
  IF p.id IS NULL THEN
    RAISE EXCEPTION 'NO_ACTIVE_POLICY' USING DETAIL = format('%s at %s', p_mission_type, v_as_of);
  END IF;
  IF COALESCE(p_payment_mode,'') NOT IN ('cash','chop_pay') THEN
    RAISE EXCEPTION 'INVALID_PAYMENT_MODE';
  END IF;

  SELECT * INTO s FROM public.starter_credit_policy_at(v_as_of);
  SELECT * INTO po FROM public.driver_payout_policy_at(v_as_of);
  SELECT * INTO pf FROM public.provider_fee_schedule_at('orange_money', v_as_of);

  v_exposure_bps := 10000 - COALESCE(p.collateral_pct_bps,0);
  IF p_mission_type = 'envoyer' THEN
    v_claim_envelope := LEAST(
      COALESCE(p.claims_exposure_max_gnf, (COALESCE(p.max_declared_value_gnf,0) * v_exposure_bps) / 10000),
      (LEAST(COALESCE(p_declared_value_gnf,0), COALESCE(p.max_declared_value_gnf, p_declared_value_gnf)) * v_exposure_bps) / 10000
    );
  ELSE
    v_claim_envelope := NULL;
  END IF;

  RETURN jsonb_strip_nulls(jsonb_build_object(
    'schema', 'chopchop.finance.policy_snapshot',
    'version', 2,
    'policy_id', p.id,
    'mission_type', p.mission_type,
    'resolved_as_of', v_as_of,
    'accepted_at', v_as_of,
    'effective_from', p.effective_from,
    'policy_effective_from', p.effective_from,
    'payment_mode', p_payment_mode,
    'is_sandbox', COALESCE(p_is_sandbox,false),
    'fare_gnf', COALESCE(p_fare_gnf,0),
    'merchandise_subtotal_gnf', COALESCE(p_merchandise_subtotal_gnf,0),
    'delivery_fee_gnf', COALESCE(p_delivery_fee_gnf,0),
    'declared_value_gnf', COALESCE(p_declared_value_gnf,0),
    'max_declared_value_gnf', p.max_declared_value_gnf,
    'commission_bps', p.commission_bps,
    'commission_basis', CASE WHEN p.commission_bps > 0 THEN 'fare' ELSE 'none' END,
    'fixed_commission_gnf', p.fixed_commission_gnf,
    'min_driver_balance_gnf', p.min_driver_balance_gnf,
    'transaction_fee_bps', p.transaction_fee_bps,
    'fee_basis', p.fee_basis,
    'collateral_mode', p.collateral_mode,
    'collateral_pct_bps', p.collateral_pct_bps,
    'collateral_basis', p.collateral_basis,
    'collateral_min_gnf', p.collateral_min_gnf,
    'collateral_max_gnf', p.collateral_max_gnf,
    'collateral_fixed_gnf', p.collateral_fixed_gnf,
    'cash_funding_mode', p.cash_funding_mode,
    'cash_funding_pct_bps', p.cash_funding_pct_bps,
    'cash_funding_max_gnf', p.cash_funding_max_gnf,
    'cancel_before_dispatch_bps', p.cancel_before_dispatch_bps,
    'cancel_after_dispatch_bps', p.cancel_after_dispatch_bps,
    'cancel_basis', p.cancel_basis,
    'claims_exposure_pct_bps', CASE WHEN p_mission_type = 'envoyer' THEN v_exposure_bps ELSE NULL END,
    'claims_exposure_max_gnf', CASE WHEN p_mission_type = 'envoyer' THEN p.claims_exposure_max_gnf ELSE NULL END,
    'claim_envelope_gnf', v_claim_envelope,
    'starter_credit_policy_id', s.id,
    'starter_credit_amount_gnf', s.amount_gnf,
    'payout_policy_id', po.id,
    'provider_fee_schedule_id', pf.id
  ));
END; $$;

CREATE OR REPLACE FUNCTION public.finance_policy_snapshot_validate(p_snapshot jsonb)
RETURNS boolean
LANGUAGE plpgsql IMMUTABLE SET search_path = public
AS $$
DECLARE
  v_type text := p_snapshot->>'mission_type';
  v_coll int := COALESCE((p_snapshot->>'collateral_pct_bps')::int, 0);
  v_expo int := COALESCE((p_snapshot->>'claims_exposure_pct_bps')::int, 0);
BEGIN
  IF p_snapshot IS NULL OR p_snapshot->>'schema' IS DISTINCT FROM 'chopchop.finance.policy_snapshot' THEN
    RAISE EXCEPTION 'SNAPSHOT_SCHEMA_INVALID';
  END IF;
  IF COALESCE((p_snapshot->>'version')::int,0) NOT IN (1,2) THEN
    RAISE EXCEPTION 'SNAPSHOT_VERSION_UNSUPPORTED';
  END IF;
  IF p_snapshot->>'policy_id' IS NULL OR v_type IS NULL OR p_snapshot->>'effective_from' IS NULL THEN
    RAISE EXCEPTION 'SNAPSHOT_MISSING_POLICY_REFERENCE';
  END IF;
  IF v_type NOT IN ('ride','bonbonna','repas','marche','envoyer') THEN
    RAISE EXCEPTION 'SNAPSHOT_MISSION_TYPE_INVALID';
  END IF;
  IF COALESCE(p_snapshot->>'payment_mode','') NOT IN ('cash','chop_pay') THEN
    RAISE EXCEPTION 'SNAPSHOT_PAYMENT_MODE_INVALID';
  END IF;
  IF COALESCE((p_snapshot->>'transaction_fee_bps')::int,0) > 0
     AND COALESCE(p_snapshot->>'fee_basis','none') = 'none' THEN
    RAISE EXCEPTION 'SNAPSHOT_FEE_BASIS_AMBIGUOUS';
  END IF;
  IF COALESCE(p_snapshot->>'collateral_mode','none') <> 'none'
     AND COALESCE(p_snapshot->>'collateral_basis','none') = 'none' THEN
    RAISE EXCEPTION 'SNAPSHOT_COLLATERAL_BASIS_AMBIGUOUS';
  END IF;
  IF GREATEST(COALESCE((p_snapshot->>'cancel_before_dispatch_bps')::int,0),
              COALESCE((p_snapshot->>'cancel_after_dispatch_bps')::int,0)) > 0
     AND COALESCE(p_snapshot->>'cancel_basis','none') = 'none' THEN
    RAISE EXCEPTION 'SNAPSHOT_CANCEL_BASIS_AMBIGUOUS';
  END IF;
  IF v_coll + v_expo > 10000 THEN
    RAISE EXCEPTION 'SNAPSHOT_COVERAGE_EXCEEDS_100_PCT';
  END IF;
  IF v_type = 'envoyer' THEN
    IF COALESCE((p_snapshot->>'declared_value_gnf')::bigint,0)
       > COALESCE((p_snapshot->>'max_declared_value_gnf')::bigint, 0) THEN
      RAISE EXCEPTION 'SNAPSHOT_DECLARED_VALUE_ABOVE_CAP';
    END IF;
  END IF;
  RETURN true;
END; $$;

-- ---------- GRANTS ----------
REVOKE ALL ON FUNCTION public.admin_set_finance_policy(text,integer,bigint,text,integer,bigint,bigint,bigint,bigint,boolean,timestamptz,text,text,integer,text,integer,integer,text,text,integer,bigint,bigint,bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_finance_policy(text,integer,bigint,text,integer,bigint,bigint,bigint,bigint,boolean,timestamptz,text,text,integer,text,integer,integer,text,text,integer,bigint,bigint,bigint) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.admin_set_starter_credit_policy(bigint,boolean,timestamptz,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_starter_credit_policy(bigint,boolean,timestamptz,text) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.admin_set_payout_policy(bigint,bigint,bigint,integer,integer,integer,boolean,timestamptz,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_payout_policy(bigint,bigint,bigint,integer,integer,integer,boolean,timestamptz,text) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.admin_set_merchant_settlement_policy(boolean,bigint,bigint,text,integer,bigint,boolean,timestamptz,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_merchant_settlement_policy(boolean,bigint,bigint,text,integer,bigint,boolean,timestamptz,text) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.admin_set_provider_fee_schedule(text,integer,bigint,bigint,bigint,boolean,timestamptz,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_provider_fee_schedule(text,integer,bigint,bigint,bigint,boolean,timestamptz,text) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.admin_set_feature_flag(text,boolean,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_feature_flag(text,boolean,text) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.admin_set_finance_delegation(boolean,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_finance_delegation(boolean,text) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.finance_policy_at(text,timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finance_policy_at(text,timestamptz) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.starter_credit_policy_at(timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.starter_credit_policy_at(timestamptz) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.driver_payout_policy_at(timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.driver_payout_policy_at(timestamptz) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.merchant_settlement_policy_at(timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.merchant_settlement_policy_at(timestamptz) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.provider_fee_schedule_at(text,timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.provider_fee_schedule_at(text,timestamptz) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.finance_policy_snapshot(text,timestamptz,text,bigint,bigint,bigint,bigint,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finance_policy_snapshot(text,timestamptz,text,bigint,bigint,bigint,bigint,boolean) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.finance_policy_snapshot_validate(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finance_policy_snapshot_validate(jsonb) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public._policy_row_immutable() FROM PUBLIC, anon, authenticated;