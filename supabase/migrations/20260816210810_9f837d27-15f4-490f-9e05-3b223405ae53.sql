-- ============================================================
-- NODE 4 — MARCHÉ R4 : ORDER COMMITMENT + ECONOMICS (part 1)
-- Reuses the canonical Slice 13 finance-policy spine:
--   finance_policies / finance_policy_at / finance_policy_snapshot /
--   admin_set_finance_policy / finance_policy_predecessor.
-- No new money tables, no new wallet/hold/capture/ledger architecture.
-- ============================================================

-- ---------- 1. Policy field: merchant platform fee (bps) ----------
ALTER TABLE public.finance_policies
  ADD COLUMN IF NOT EXISTS merchant_platform_fee_bps integer;

COMMENT ON COLUMN public.finance_policies.merchant_platform_fee_bps IS
  'Marche R4: platform fee charged to the merchant, in basis points of the merchandise subtotal. Effective-dated, admin-editable, never hardcoded in code.';

-- ---------- 2. admin_set_finance_policy gains the new field ----------
DROP FUNCTION IF EXISTS public.admin_set_finance_policy(
  text,integer,bigint,text,integer,bigint,bigint,bigint,bigint,boolean,timestamptz,text,text,
  integer,text,integer,integer,text,text,integer,bigint,bigint,bigint,bigint,numeric,integer,bigint);

CREATE FUNCTION public.admin_set_finance_policy(
  p_mission_type text,
  p_commission_bps integer DEFAULT NULL::integer,
  p_min_driver_balance_gnf bigint DEFAULT NULL::bigint,
  p_collateral_mode text DEFAULT NULL::text,
  p_collateral_pct_bps integer DEFAULT NULL::integer,
  p_collateral_fixed_gnf bigint DEFAULT NULL::bigint,
  p_collateral_min_gnf bigint DEFAULT NULL::bigint,
  p_collateral_max_gnf bigint DEFAULT NULL::bigint,
  p_fixed_commission_gnf bigint DEFAULT NULL::bigint,
  p_require_collateral_before_offer boolean DEFAULT NULL::boolean,
  p_effective_from timestamp with time zone DEFAULT now(),
  p_note text DEFAULT NULL::text,
  p_collateral_basis text DEFAULT NULL::text,
  p_transaction_fee_bps integer DEFAULT NULL::integer,
  p_fee_basis text DEFAULT NULL::text,
  p_cancel_before_dispatch_bps integer DEFAULT NULL::integer,
  p_cancel_after_dispatch_bps integer DEFAULT NULL::integer,
  p_cancel_basis text DEFAULT NULL::text,
  p_cash_funding_mode text DEFAULT NULL::text,
  p_cash_funding_pct_bps integer DEFAULT NULL::integer,
  p_cash_funding_max_gnf bigint DEFAULT NULL::bigint,
  p_max_declared_value_gnf bigint DEFAULT NULL::bigint,
  p_claims_exposure_max_gnf bigint DEFAULT NULL::bigint,
  p_delivery_flat_fee_gnf bigint DEFAULT NULL::bigint,
  p_delivery_max_distance_km numeric DEFAULT NULL::numeric,
  p_pickup_platform_fee_bps integer DEFAULT NULL::integer,
  p_courier_payout_gnf bigint DEFAULT NULL::bigint,
  p_merchant_platform_fee_bps integer DEFAULT NULL::integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_caller uuid := auth.uid();
  v_before public.finance_policies;
  v_new public.finance_policies;
  v_latest timestamptz;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.is_god_admin(v_caller) THEN
    RAISE EXCEPTION 'Only a God Admin can change finance policy';
  END IF;
  IF p_mission_type NOT IN ('ride','bonbonna','taxi','repas','marche','envoyer') THEN
    RAISE EXCEPTION 'Unknown mission type %', p_mission_type;
  END IF;
  IF length(btrim(COALESCE(p_note,''))) < 5 THEN
    RAISE EXCEPTION 'REASON_REQUIRED'
      USING DETAIL = 'A human-entered reason of at least 5 characters is mandatory';
  END IF;
  IF p_effective_from < now() - interval '1 minute' THEN
    RAISE EXCEPTION 'BACKDATING_REJECTED'
      USING DETAIL = 'Effective date cannot be in the past; policy history is immutable';
  END IF;

  -- R5 fail-closed bounds
  IF p_delivery_flat_fee_gnf IS NOT NULL AND p_delivery_flat_fee_gnf < 0 THEN
    RAISE EXCEPTION 'INVALID_DELIVERY_FLAT_FEE'; END IF;
  IF p_courier_payout_gnf IS NOT NULL AND p_courier_payout_gnf < 0 THEN
    RAISE EXCEPTION 'INVALID_COURIER_PAYOUT'; END IF;
  IF p_delivery_max_distance_km IS NOT NULL AND p_delivery_max_distance_km <= 0 THEN
    RAISE EXCEPTION 'INVALID_DELIVERY_MAX_DISTANCE'; END IF;
  IF p_pickup_platform_fee_bps IS NOT NULL
     AND (p_pickup_platform_fee_bps < 0 OR p_pickup_platform_fee_bps > 10000) THEN
    RAISE EXCEPTION 'INVALID_PICKUP_FEE_BPS'; END IF;
  IF p_transaction_fee_bps IS NOT NULL
     AND (p_transaction_fee_bps < 0 OR p_transaction_fee_bps > 10000) THEN
    RAISE EXCEPTION 'INVALID_TRANSACTION_FEE_BPS'; END IF;
  IF p_commission_bps IS NOT NULL AND (p_commission_bps < 0 OR p_commission_bps > 10000) THEN
    RAISE EXCEPTION 'INVALID_COMMISSION_BPS'; END IF;
  -- R4 fail-closed bound
  IF p_merchant_platform_fee_bps IS NOT NULL
     AND (p_merchant_platform_fee_bps < 0 OR p_merchant_platform_fee_bps > 10000) THEN
    RAISE EXCEPTION 'INVALID_MERCHANT_PLATFORM_FEE_BPS'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext('finance_policy:' || p_mission_type));

  SELECT max(effective_from) INTO v_latest
    FROM public.finance_policies WHERE mission_type = p_mission_type;
  IF v_latest IS NOT NULL AND p_effective_from <= v_latest THEN
    RAISE EXCEPTION 'EFFECTIVE_FROM_NOT_MONOTONIC'
      USING DETAIL = format('A policy already exists at or after %s for %s', v_latest, p_mission_type);
  END IF;

  SELECT * INTO v_before FROM public.finance_policy_predecessor(p_mission_type, p_effective_from);

  INSERT INTO public.finance_policies (
    mission_type, commission_bps, fixed_commission_gnf, min_driver_balance_gnf,
    collateral_mode, collateral_pct_bps, collateral_fixed_gnf, collateral_min_gnf,
    collateral_max_gnf, collateral_basis, require_collateral_before_offer,
    transaction_fee_bps, fee_basis, cash_funding_mode, cash_funding_pct_bps,
    cash_funding_max_gnf, cancel_before_dispatch_bps, cancel_after_dispatch_bps,
    cancel_basis, max_declared_value_gnf, claims_exposure_max_gnf,
    delivery_flat_fee_gnf, delivery_max_distance_km, pickup_platform_fee_bps, courier_payout_gnf,
    merchant_platform_fee_bps,
    effective_from, enabled, note, created_by)
  VALUES (
    p_mission_type,
    COALESCE(p_commission_bps, v_before.commission_bps, 0),
    COALESCE(p_fixed_commission_gnf, v_before.fixed_commission_gnf, 0),
    COALESCE(p_min_driver_balance_gnf, v_before.min_driver_balance_gnf, 0),
    COALESCE(p_collateral_mode, v_before.collateral_mode, 'none'),
    COALESCE(p_collateral_pct_bps, v_before.collateral_pct_bps, 0),
    COALESCE(p_collateral_fixed_gnf, v_before.collateral_fixed_gnf, 0),
    COALESCE(p_collateral_min_gnf, v_before.collateral_min_gnf, 0),
    COALESCE(p_collateral_max_gnf, v_before.collateral_max_gnf),
    COALESCE(p_collateral_basis, v_before.collateral_basis, 'none'),
    COALESCE(p_require_collateral_before_offer, v_before.require_collateral_before_offer, false),
    COALESCE(p_transaction_fee_bps, v_before.transaction_fee_bps, 0),
    COALESCE(p_fee_basis, v_before.fee_basis, 'none'),
    COALESCE(p_cash_funding_mode, v_before.cash_funding_mode, 'none'),
    COALESCE(p_cash_funding_pct_bps, v_before.cash_funding_pct_bps, 0),
    COALESCE(p_cash_funding_max_gnf, v_before.cash_funding_max_gnf),
    COALESCE(p_cancel_before_dispatch_bps, v_before.cancel_before_dispatch_bps, 0),
    COALESCE(p_cancel_after_dispatch_bps, v_before.cancel_after_dispatch_bps, 0),
    COALESCE(p_cancel_basis, v_before.cancel_basis, 'none'),
    COALESCE(p_max_declared_value_gnf, v_before.max_declared_value_gnf),
    COALESCE(p_claims_exposure_max_gnf, v_before.claims_exposure_max_gnf),
    COALESCE(p_delivery_flat_fee_gnf, v_before.delivery_flat_fee_gnf),
    COALESCE(p_delivery_max_distance_km, v_before.delivery_max_distance_km),
    COALESCE(p_pickup_platform_fee_bps, v_before.pickup_platform_fee_bps),
    COALESCE(p_courier_payout_gnf, v_before.courier_payout_gnf),
    COALESCE(p_merchant_platform_fee_bps, v_before.merchant_platform_fee_bps),
    p_effective_from, true, btrim(p_note), v_caller)
  RETURNING * INTO v_new;

  INSERT INTO public.audit_logs(actor_user_id, module, action, target_type, target_id,
                                before, after, note)
  VALUES (v_caller, 'pricing', 'finance_policy.set', 'finance_policies', v_new.id::text,
          to_jsonb(v_before), to_jsonb(v_new), btrim(p_note));

  RETURN jsonb_build_object('ok', true, 'policy_id', v_new.id,
                            'mission_type', p_mission_type,
                            'effective_from', v_new.effective_from);
END; $fn$;

REVOKE ALL ON FUNCTION public.admin_set_finance_policy(
  text,integer,bigint,text,integer,bigint,bigint,bigint,bigint,boolean,timestamptz,text,text,
  integer,text,integer,integer,text,text,integer,bigint,bigint,bigint,bigint,numeric,integer,bigint,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_finance_policy(
  text,integer,bigint,text,integer,bigint,bigint,bigint,bigint,boolean,timestamptz,text,text,
  integer,text,integer,integer,text,text,integer,bigint,bigint,bigint,bigint,numeric,integer,bigint,integer)
  TO authenticated, service_role;

-- ---------- 3. Canonical snapshot exposes the merchant fee rate ----------
CREATE OR REPLACE FUNCTION public.finance_policy_snapshot(
  p_mission_type text,
  p_as_of timestamp with time zone DEFAULT now(),
  p_payment_mode text DEFAULT 'chop_pay'::text,
  p_fare_gnf bigint DEFAULT 0,
  p_merchandise_subtotal_gnf bigint DEFAULT 0,
  p_delivery_fee_gnf bigint DEFAULT 0,
  p_declared_value_gnf bigint DEFAULT 0,
  p_is_sandbox boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  p public.finance_policies;
  s public.driver_starter_credit_policies;
  po public.driver_payout_policies;
  pf public.provider_fee_schedules;
  v_as_of timestamptz := COALESCE(p_as_of, now());
  v_exposure_bps integer;
  v_claims_max bigint;
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
    v_claims_max := COALESCE(
      p.claims_exposure_max_gnf,
      (COALESCE(p.max_declared_value_gnf,0) * v_exposure_bps) / 10000
    );
    v_claim_envelope := LEAST(
      v_claims_max,
      (LEAST(COALESCE(p_declared_value_gnf,0), COALESCE(p.max_declared_value_gnf, p_declared_value_gnf)) * v_exposure_bps) / 10000
    );
  ELSE
    v_claims_max := NULL;
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
    'merchant_platform_fee_bps', p.merchant_platform_fee_bps,
    'merchant_platform_fee_basis',
      CASE WHEN p.merchant_platform_fee_bps IS NULL THEN NULL ELSE 'merchandise_subtotal' END,
    'collateral_mode', p.collateral_mode,
    'collateral_pct_bps', p.collateral_pct_bps,
    'collateral_basis', p.collateral_basis,
    'collateral_min_gnf', p.collateral_min_gnf,
    'collateral_max_gnf', p.collateral_max_gnf,
    'collateral_fixed_gnf', p.collateral_fixed_gnf,
    'cash_funding_mode', p.cash_funding_mode,
    'cash_funding_basis', CASE WHEN COALESCE(p.cash_funding_mode,'none') = 'none'
                               THEN 'none' ELSE p.cash_funding_mode END,
    'cash_funding_pct_bps', p.cash_funding_pct_bps,
    'cash_funding_max_gnf', p.cash_funding_max_gnf,
    'cancel_before_dispatch_bps', p.cancel_before_dispatch_bps,
    'cancel_after_dispatch_bps', p.cancel_after_dispatch_bps,
    'cancel_basis', p.cancel_basis,
    'claims_exposure_pct_bps', CASE WHEN p_mission_type = 'envoyer' THEN v_exposure_bps ELSE NULL END,
    'claims_exposure_max_gnf', v_claims_max,
    'claims_exposure_max_source', CASE WHEN p_mission_type <> 'envoyer' THEN NULL
                                       WHEN p.claims_exposure_max_gnf IS NULL THEN 'derived'
                                       ELSE 'policy' END,
    'claim_envelope_gnf', v_claim_envelope,
    'starter_credit_policy_id', s.id,
    'starter_credit_amount_gnf', s.amount_gnf,
    'payout_policy_id', po.id,
    'provider_fee_schedule_id', pf.id
  ));
END; $fn$;

-- ---------- 4. Seed: Marche merchant platform fee = 100 bps (1%) ----------
-- Exact carry-forward of the effective marche policy; only the new field is set,
-- so no Slice 13 marche economics change.
INSERT INTO public.finance_policies (
  mission_type, commission_bps, fixed_commission_gnf, min_driver_balance_gnf,
  collateral_mode, collateral_pct_bps, collateral_fixed_gnf, collateral_min_gnf,
  collateral_max_gnf, collateral_basis, require_collateral_before_offer,
  transaction_fee_bps, fee_basis, cash_funding_mode, cash_funding_pct_bps,
  cash_funding_max_gnf, cancel_before_dispatch_bps, cancel_after_dispatch_bps,
  cancel_basis, max_declared_value_gnf, claims_exposure_max_gnf,
  delivery_flat_fee_gnf, delivery_max_distance_km, pickup_platform_fee_bps, courier_payout_gnf,
  merchant_platform_fee_bps, effective_from, enabled, note)
SELECT
  p.mission_type, p.commission_bps, p.fixed_commission_gnf, p.min_driver_balance_gnf,
  p.collateral_mode, p.collateral_pct_bps, p.collateral_fixed_gnf, p.collateral_min_gnf,
  p.collateral_max_gnf, p.collateral_basis, p.require_collateral_before_offer,
  p.transaction_fee_bps, p.fee_basis, p.cash_funding_mode, p.cash_funding_pct_bps,
  p.cash_funding_max_gnf, p.cancel_before_dispatch_bps, p.cancel_after_dispatch_bps,
  p.cancel_basis, p.max_declared_value_gnf, p.claims_exposure_max_gnf,
  p.delivery_flat_fee_gnf, p.delivery_max_distance_km, p.pickup_platform_fee_bps, p.courier_payout_gnf,
  100, now(), true,
  'Node 4 Marche R4: initial merchant platform fee 100 bps (1%) of merchandise subtotal; effective-dated and God-Admin editable. All other marche values carried forward unchanged.'
FROM public.finance_policy_at('marche', now()) p
WHERE p.id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.finance_policies f
     WHERE f.mission_type = 'marche' AND f.merchant_platform_fee_bps IS NOT NULL);

-- ---------- 5. Frozen economics on the canonical R3 order ----------
ALTER TABLE public.marche_orders
  ADD COLUMN IF NOT EXISTS merchant_payable_gnf bigint,
  ADD COLUMN IF NOT EXISTS merchant_platform_fee_bps integer,
  ADD COLUMN IF NOT EXISTS fee_policy_effective_from timestamptz,
  ADD COLUMN IF NOT EXISTS economics_snapshot jsonb,
  ADD COLUMN IF NOT EXISTS economics_resolved_at timestamptz,
  ADD COLUMN IF NOT EXISTS delivery_pricing_state text NOT NULL DEFAULT 'unresolved';

COMMENT ON COLUMN public.marche_orders.merchant_fee_gnf IS
  'R4: merchant platform fee frozen at commitment (floor(subtotal * bps / 10000), clamped to [0, subtotal]).';
COMMENT ON COLUMN public.marche_orders.merchant_payable_gnf IS
  'R4: merchandise-only merchant payable = merchandise_subtotal_gnf - merchant_fee_gnf. Customer delivery is never netted here.';
COMMENT ON COLUMN public.marche_orders.delivery_charge_gnf IS
  'R4: customer delivery economics are a separate axis; stays NULL until a canonical Marche delivery policy exists.';

ALTER TABLE public.marche_orders
  DROP CONSTRAINT IF EXISTS marche_orders_delivery_state_chk,
  DROP CONSTRAINT IF EXISTS marche_orders_economics_complete_chk,
  DROP CONSTRAINT IF EXISTS marche_orders_fee_bounds_chk,
  DROP CONSTRAINT IF EXISTS marche_orders_payable_identity_chk;

ALTER TABLE public.marche_orders
  ADD CONSTRAINT marche_orders_delivery_state_chk CHECK (
    delivery_pricing_state IN ('unresolved','resolved','not_applicable')
    AND (delivery_pricing_state <> 'unresolved' OR delivery_charge_gnf IS NULL)
    AND (delivery_charge_gnf IS NULL OR delivery_charge_gnf >= 0)),
  ADD CONSTRAINT marche_orders_economics_complete_chk CHECK (
    num_nulls(merchant_fee_gnf, merchant_payable_gnf, merchant_platform_fee_bps,
              fee_policy_id, fee_policy_effective_from, economics_snapshot,
              economics_resolved_at) IN (0, 7)),
  ADD CONSTRAINT marche_orders_fee_bounds_chk CHECK (
    merchant_fee_gnf IS NULL
    OR (merchant_fee_gnf >= 0
        AND merchant_fee_gnf <= merchandise_subtotal_gnf
        AND merchant_platform_fee_bps BETWEEN 0 AND 10000)),
  ADD CONSTRAINT marche_orders_payable_identity_chk CHECK (
    merchant_payable_gnf IS NULL
    OR (merchant_payable_gnf >= 0
        AND merchant_payable_gnf = merchandise_subtotal_gnf - merchant_fee_gnf));

-- ---------- 6. Deterministic rounding law: FLOOR, clamped ----------
CREATE OR REPLACE FUNCTION public.marche_merchant_fee_gnf(p_subtotal_gnf bigint, p_bps integer)
RETURNS bigint
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $fn$
  -- Rounding law: FLOOR of (subtotal * bps) / 10000, then clamped to [0, subtotal].
  SELECT LEAST(
           GREATEST((GREATEST(COALESCE(p_subtotal_gnf,0),0) * GREATEST(COALESCE(p_bps,0),0)) / 10000, 0),
           GREATEST(COALESCE(p_subtotal_gnf,0),0));
$fn$;

REVOKE ALL ON FUNCTION public.marche_merchant_fee_gnf(bigint,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_merchant_fee_gnf(bigint,integer) TO service_role;

-- ---------- 7. Order guard: economics are server-owned and immutable ----------
CREATE OR REPLACE FUNCTION public.marche_order_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $fn$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF COALESCE(current_setting('marche.rpc', true),'') = '1' THEN RETURN OLD; END IF;
    RAISE EXCEPTION 'ORDER_IMMUTABLE';
  END IF;

  IF NEW.buyer_user_id IS DISTINCT FROM OLD.buyer_user_id
     OR NEW.merchant_store_id IS DISTINCT FROM OLD.merchant_store_id
     OR NEW.merchant_user_id IS DISTINCT FROM OLD.merchant_user_id
     OR NEW.merchandise_subtotal_gnf IS DISTINCT FROM OLD.merchandise_subtotal_gnf
     OR NEW.item_count IS DISTINCT FROM OLD.item_count
     OR NEW.line_count IS DISTINCT FROM OLD.line_count
     OR NEW.source_offer_id IS DISTINCT FROM OLD.source_offer_id
     OR NEW.client_request_id IS DISTINCT FROM OLD.client_request_id
     OR NEW.request_fingerprint IS DISTINCT FROM OLD.request_fingerprint
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
     OR NEW.delivery_address IS DISTINCT FROM OLD.delivery_address
     OR NEW.dropoff_lat IS DISTINCT FROM OLD.dropoff_lat
     OR NEW.dropoff_lng IS DISTINCT FROM OLD.dropoff_lng THEN
    RAISE EXCEPTION 'ORDER_IMMUTABLE';
  END IF;

  -- R4: economics are frozen at commitment. A later policy edit, an admin, a
  -- merchant or a buyer can never rewrite the money truth of a committed order.
  IF NEW.merchant_fee_gnf IS DISTINCT FROM OLD.merchant_fee_gnf
     OR NEW.merchant_payable_gnf IS DISTINCT FROM OLD.merchant_payable_gnf
     OR NEW.merchant_platform_fee_bps IS DISTINCT FROM OLD.merchant_platform_fee_bps
     OR NEW.fee_policy_id IS DISTINCT FROM OLD.fee_policy_id
     OR NEW.fee_policy_effective_from IS DISTINCT FROM OLD.fee_policy_effective_from
     OR NEW.economics_snapshot IS DISTINCT FROM OLD.economics_snapshot
     OR NEW.economics_resolved_at IS DISTINCT FROM OLD.economics_resolved_at
     OR NEW.delivery_charge_gnf IS DISTINCT FROM OLD.delivery_charge_gnf
     OR NEW.delivery_pricing_state IS DISTINCT FROM OLD.delivery_pricing_state THEN
    RAISE EXCEPTION 'ECONOMICS_IMMUTABLE';
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF OLD.status <> 'committed' THEN RAISE EXCEPTION 'ORDER_TERMINAL'; END IF;
    IF NEW.status NOT IN ('cancelled','expired') THEN RAISE EXCEPTION 'ILLEGAL_ORDER_TRANSITION'; END IF;
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END $fn$;