-- ============================================================
-- R5.A — Repas pricing values on the existing effective-dated policy
-- ============================================================
ALTER TABLE public.finance_policies
  ADD COLUMN IF NOT EXISTS delivery_flat_fee_gnf    bigint,
  ADD COLUMN IF NOT EXISTS delivery_max_distance_km numeric(6,2),
  ADD COLUMN IF NOT EXISTS pickup_platform_fee_bps  integer,
  ADD COLUMN IF NOT EXISTS courier_payout_gnf       bigint;

COMMENT ON COLUMN public.finance_policies.delivery_flat_fee_gnf IS
  'R5: flat customer delivery price inside the configured max distance. NULL = not configured (fail closed).';
COMMENT ON COLUMN public.finance_policies.delivery_max_distance_km IS
  'R5: maximum delivery distance from the merchant. NULL = no distance limit enforced.';
COMMENT ON COLUMN public.finance_policies.pickup_platform_fee_bps IS
  'R5: pickup platform fee rate. NULL inherits transaction_fee_bps (R4.5 behaviour).';
COMMENT ON COLUMN public.finance_policies.courier_payout_gnf IS
  'R5: courier compensation for a delivery, independent of what the customer pays.';

-- Seed: initial field-test values only. NOT product law; admin-editable.
INSERT INTO public.finance_policies (
  mission_type, commission_bps, fixed_commission_gnf, min_driver_balance_gnf,
  collateral_mode, collateral_pct_bps, collateral_fixed_gnf, collateral_min_gnf,
  collateral_max_gnf, collateral_basis, require_collateral_before_offer,
  transaction_fee_bps, fee_basis, cash_funding_mode, cash_funding_pct_bps,
  cash_funding_max_gnf, cancel_before_dispatch_bps, cancel_after_dispatch_bps,
  cancel_basis, effective_from, enabled, note,
  delivery_flat_fee_gnf, delivery_max_distance_km, pickup_platform_fee_bps, courier_payout_gnf)
SELECT
  p.mission_type, p.commission_bps, p.fixed_commission_gnf, p.min_driver_balance_gnf,
  p.collateral_mode, p.collateral_pct_bps, p.collateral_fixed_gnf, p.collateral_min_gnf,
  p.collateral_max_gnf, p.collateral_basis, p.require_collateral_before_offer,
  p.transaction_fee_bps, p.fee_basis, p.cash_funding_mode, p.cash_funding_pct_bps,
  p.cash_funding_max_gnf, p.cancel_before_dispatch_bps, p.cancel_after_dispatch_bps,
  p.cancel_basis, now(), true,
  'R5 seed: initial Repas pricing control-plane values for field testing (admin-editable)',
  20000, 10.00, NULL, 15000
FROM public.finance_policy_current('repas') p
WHERE NOT EXISTS (
  SELECT 1 FROM public.finance_policies f
   WHERE f.mission_type = 'repas' AND f.delivery_flat_fee_gnf IS NOT NULL);

-- ============================================================
-- R5.F — promotion overlay (small, disciplined)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.repas_pricing_promotions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  reason text NOT NULL,
  fulfillment_scope text NOT NULL DEFAULT 'delivery',
  delivery_fee_override_gnf bigint,
  delivery_discount_gnf bigint,
  enabled boolean NOT NULL DEFAULT true,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  disabled_at timestamptz,
  disabled_by uuid,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT repas_promo_scope_ck CHECK (fulfillment_scope IN ('delivery','pickup','both')),
  CONSTRAINT repas_promo_window_ck CHECK (ends_at > starts_at),
  CONSTRAINT repas_promo_shape_ck CHECK (num_nonnulls(delivery_fee_override_gnf, delivery_discount_gnf) = 1),
  CONSTRAINT repas_promo_nonneg_ck CHECK (COALESCE(delivery_fee_override_gnf,0) >= 0
                                      AND COALESCE(delivery_discount_gnf,0) >= 0),
  CONSTRAINT repas_promo_name_ck CHECK (length(btrim(name)) >= 3),
  CONSTRAINT repas_promo_reason_ck CHECK (length(btrim(reason)) >= 5)
);

GRANT SELECT ON public.repas_pricing_promotions TO authenticated;
GRANT ALL    ON public.repas_pricing_promotions TO service_role;
ALTER TABLE public.repas_pricing_promotions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Signed-in users can read Repas promotions" ON public.repas_pricing_promotions;
CREATE POLICY "Signed-in users can read Repas promotions"
  ON public.repas_pricing_promotions FOR SELECT TO authenticated USING (true);

DROP TRIGGER IF EXISTS trg_repas_promotions_updated_at ON public.repas_pricing_promotions;
CREATE TRIGGER trg_repas_promotions_updated_at
  BEFORE UPDATE ON public.repas_pricing_promotions
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE INDEX IF NOT EXISTS idx_repas_promo_window
  ON public.repas_pricing_promotions (enabled, starts_at, ends_at);

-- ============================================================
-- Distance truth (server-side straight-line; documented limitation)
-- ============================================================
CREATE OR REPLACE FUNCTION public.repas_delivery_distance_km(
  p_restaurant_id uuid, p_lat double precision, p_lng double precision)
RETURNS numeric
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rlat double precision; v_rlng double precision; v_m double precision;
BEGIN
  SELECT latitude, longitude INTO v_rlat, v_rlng
    FROM public.food_restaurants WHERE id = p_restaurant_id;
  IF v_rlat IS NULL OR v_rlng IS NULL OR p_lat IS NULL OR p_lng IS NULL THEN
    RETURN NULL;  -- unknown, never silently "0"
  END IF;
  v_m := 6371000 * 2 * asin(sqrt(
      power(sin(radians(p_lat - v_rlat)/2), 2) +
      cos(radians(v_rlat)) * cos(radians(p_lat)) *
      power(sin(radians(p_lng - v_rlng)/2), 2)));
  RETURN round((v_m / 1000)::numeric, 3);
END; $$;
REVOKE ALL ON FUNCTION public.repas_delivery_distance_km(uuid, double precision, double precision) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.repas_delivery_distance_km(uuid, double precision, double precision) TO authenticated, service_role;

-- ============================================================
-- Effective Repas pricing = base policy + optional promotion overlay
-- ============================================================
CREATE OR REPLACE FUNCTION public.repas_pricing_effective(
  p_fulfillment text DEFAULT 'delivery', p_at timestamptz DEFAULT now())
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_p public.finance_policies;
  v_pr public.repas_pricing_promotions;
  v_pickup boolean; v_base bigint; v_customer bigint; v_disc bigint := 0;
  v_fee_bps integer;
BEGIN
  IF COALESCE(p_fulfillment,'') NOT IN ('pickup','delivery') THEN
    RAISE EXCEPTION 'INVALID_FULFILLMENT';
  END IF;
  v_pickup := (p_fulfillment = 'pickup');

  SELECT * INTO v_p FROM public.finance_policy_at('repas', COALESCE(p_at, now()));
  IF v_p.id IS NULL THEN RAISE EXCEPTION 'NO_ACTIVE_POLICY' USING DETAIL = 'repas'; END IF;

  v_fee_bps := CASE WHEN v_pickup
                    THEN COALESCE(v_p.pickup_platform_fee_bps, v_p.transaction_fee_bps)
                    ELSE v_p.transaction_fee_bps END;

  IF v_pickup THEN
    v_base := 0; v_customer := 0;
  ELSE
    IF v_p.delivery_flat_fee_gnf IS NULL OR v_p.courier_payout_gnf IS NULL THEN
      RAISE EXCEPTION 'REPAS_PRICING_NOT_CONFIGURED'
        USING DETAIL = 'delivery_flat_fee_gnf / courier_payout_gnf missing on the effective repas policy';
    END IF;
    v_base := GREATEST(v_p.delivery_flat_fee_gnf, 0);
    v_customer := v_base;
  END IF;

  SELECT * INTO v_pr FROM public.repas_pricing_promotions
   WHERE enabled
     AND starts_at <= COALESCE(p_at, now())
     AND ends_at   >  COALESCE(p_at, now())
     AND (fulfillment_scope = 'both' OR fulfillment_scope = p_fulfillment)
   ORDER BY starts_at DESC, created_at DESC LIMIT 1;

  IF v_pr.id IS NOT NULL AND NOT v_pickup THEN
    v_customer := CASE
      WHEN v_pr.delivery_fee_override_gnf IS NOT NULL THEN LEAST(v_pr.delivery_fee_override_gnf, v_base)
      ELSE GREATEST(v_base - COALESCE(v_pr.delivery_discount_gnf,0), 0) END;
    v_disc := GREATEST(v_base - v_customer, 0);
  END IF;

  RETURN jsonb_build_object(
    'fulfillment', p_fulfillment,
    'resolved_at', COALESCE(p_at, now()),
    'policy_id', v_p.id,
    'policy_effective_from', v_p.effective_from,
    'base_delivery_fee_gnf', v_base,
    'customer_delivery_fee_gnf', v_customer,
    'promo_discount_gnf', v_disc,
    'promotion_id', CASE WHEN v_disc > 0 THEN v_pr.id END,
    'promotion_name', CASE WHEN v_disc > 0 THEN v_pr.name END,
    'delivery_max_distance_km', v_p.delivery_max_distance_km,
    'platform_fee_bps', v_fee_bps,
    'fee_basis', v_p.fee_basis,
    'courier_payout_gnf', CASE WHEN v_pickup THEN 0 ELSE GREATEST(v_p.courier_payout_gnf,0) END);
END; $$;
REVOKE ALL ON FUNCTION public.repas_pricing_effective(text, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.repas_pricing_effective(text, timestamptz) TO authenticated, service_role;

-- ============================================================
-- R5.G — admin control plane: base policy (extend canonical RPC)
-- ============================================================
DROP FUNCTION IF EXISTS public.admin_set_finance_policy(
  text, integer, bigint, text, integer, bigint, bigint, bigint, bigint, boolean,
  timestamptz, text, text, integer, text, integer, integer, text, text, integer,
  bigint, bigint, bigint);

CREATE OR REPLACE FUNCTION public.admin_set_finance_policy(
  p_mission_type text,
  p_commission_bps integer DEFAULT NULL,
  p_min_driver_balance_gnf bigint DEFAULT NULL,
  p_collateral_mode text DEFAULT NULL,
  p_collateral_pct_bps integer DEFAULT NULL,
  p_collateral_fixed_gnf bigint DEFAULT NULL,
  p_collateral_min_gnf bigint DEFAULT NULL,
  p_collateral_max_gnf bigint DEFAULT NULL,
  p_fixed_commission_gnf bigint DEFAULT NULL,
  p_require_collateral_before_offer boolean DEFAULT NULL,
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
  p_claims_exposure_max_gnf bigint DEFAULT NULL,
  p_delivery_flat_fee_gnf bigint DEFAULT NULL,
  p_delivery_max_distance_km numeric DEFAULT NULL,
  p_pickup_platform_fee_bps integer DEFAULT NULL,
  p_courier_payout_gnf bigint DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
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
    p_effective_from, true, btrim(p_note), v_caller)
  RETURNING * INTO v_new;

  INSERT INTO public.audit_logs(actor_user_id, module, action, target_type, target_id,
                                before, after, note)
  VALUES (v_caller, 'pricing', 'finance_policy.set', 'finance_policies', v_new.id::text,
          to_jsonb(v_before), to_jsonb(v_new), btrim(p_note));

  RETURN jsonb_build_object('ok', true, 'policy_id', v_new.id,
                            'mission_type', p_mission_type,
                            'effective_from', v_new.effective_from);
END; $$;
REVOKE ALL ON FUNCTION public.admin_set_finance_policy(
  text, integer, bigint, text, integer, bigint, bigint, bigint, bigint, boolean,
  timestamptz, text, text, integer, text, integer, integer, text, text, integer,
  bigint, bigint, bigint, bigint, numeric, integer, bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_finance_policy(
  text, integer, bigint, text, integer, bigint, bigint, bigint, bigint, boolean,
  timestamptz, text, text, integer, text, integer, integer, text, text, integer,
  bigint, bigint, bigint, bigint, numeric, integer, bigint) TO authenticated, service_role;

-- ============================================================
-- R5.G — admin control plane: promotions
-- ============================================================
CREATE OR REPLACE FUNCTION public.admin_set_repas_promotion(
  p_name text, p_reason text, p_starts_at timestamptz, p_ends_at timestamptz,
  p_fulfillment_scope text DEFAULT 'delivery',
  p_delivery_fee_override_gnf bigint DEFAULT NULL,
  p_delivery_discount_gnf bigint DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_caller uuid := auth.uid(); v_row public.repas_pricing_promotions; v_clash int;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.is_god_admin(v_caller) THEN
    RAISE EXCEPTION 'Only a God Admin can change Repas promotions';
  END IF;
  IF length(btrim(COALESCE(p_reason,''))) < 5 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  IF length(btrim(COALESCE(p_name,''))) < 3 THEN RAISE EXCEPTION 'NAME_REQUIRED'; END IF;
  IF p_ends_at <= p_starts_at THEN RAISE EXCEPTION 'INVALID_PROMO_WINDOW'; END IF;
  IF p_ends_at <= now() THEN RAISE EXCEPTION 'PROMO_ALREADY_EXPIRED'; END IF;
  IF num_nonnulls(p_delivery_fee_override_gnf, p_delivery_discount_gnf) <> 1 THEN
    RAISE EXCEPTION 'PROMO_SHAPE_INVALID'
      USING DETAIL = 'provide exactly one of override or discount';
  END IF;
  IF COALESCE(p_delivery_fee_override_gnf, 0) < 0 OR COALESCE(p_delivery_discount_gnf, 0) < 0 THEN
    RAISE EXCEPTION 'PROMO_NEGATIVE_AMOUNT'; END IF;
  IF COALESCE(p_fulfillment_scope,'') NOT IN ('delivery','pickup','both') THEN
    RAISE EXCEPTION 'INVALID_FULFILLMENT_SCOPE'; END IF;

  SELECT count(*) INTO v_clash FROM public.repas_pricing_promotions
   WHERE enabled AND ends_at > p_starts_at AND starts_at < p_ends_at
     AND (fulfillment_scope = 'both' OR p_fulfillment_scope = 'both'
          OR fulfillment_scope = p_fulfillment_scope);
  IF v_clash > 0 THEN
    RAISE EXCEPTION 'PROMO_WINDOW_OVERLAP'
      USING DETAIL = 'an enabled promotion already covers part of this window/scope';
  END IF;

  INSERT INTO public.repas_pricing_promotions(
      name, reason, fulfillment_scope, delivery_fee_override_gnf, delivery_discount_gnf,
      starts_at, ends_at, created_by)
  VALUES (btrim(p_name), btrim(p_reason), p_fulfillment_scope,
          p_delivery_fee_override_gnf, p_delivery_discount_gnf,
          p_starts_at, p_ends_at, v_caller)
  RETURNING * INTO v_row;

  INSERT INTO public.audit_logs(actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (v_caller, 'pricing', 'repas_promotion.create', 'repas_pricing_promotions',
          v_row.id::text, to_jsonb(v_row), btrim(p_reason));

  RETURN jsonb_build_object('ok', true, 'promotion_id', v_row.id);
END; $$;
REVOKE ALL ON FUNCTION public.admin_set_repas_promotion(text, text, timestamptz, timestamptz, text, bigint, bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_repas_promotion(text, text, timestamptz, timestamptz, text, bigint, bigint) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.admin_disable_repas_promotion(p_id uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_caller uuid := auth.uid(); v_before public.repas_pricing_promotions; v_after public.repas_pricing_promotions;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.is_god_admin(v_caller) THEN
    RAISE EXCEPTION 'Only a God Admin can change Repas promotions';
  END IF;
  IF length(btrim(COALESCE(p_reason,''))) < 5 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  SELECT * INTO v_before FROM public.repas_pricing_promotions WHERE id = p_id FOR UPDATE;
  IF v_before.id IS NULL THEN RAISE EXCEPTION 'PROMOTION_NOT_FOUND'; END IF;

  UPDATE public.repas_pricing_promotions
     SET enabled = false, disabled_at = now(), disabled_by = v_caller
   WHERE id = p_id RETURNING * INTO v_after;

  INSERT INTO public.audit_logs(actor_user_id, module, action, target_type, target_id,
                                before, after, note)
  VALUES (v_caller, 'pricing', 'repas_promotion.disable', 'repas_pricing_promotions',
          p_id::text, to_jsonb(v_before), to_jsonb(v_after), btrim(p_reason));

  RETURN jsonb_build_object('ok', true, 'promotion_id', p_id);
END; $$;
REVOKE ALL ON FUNCTION public.admin_disable_repas_promotion(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_disable_repas_promotion(uuid, text) TO authenticated, service_role;