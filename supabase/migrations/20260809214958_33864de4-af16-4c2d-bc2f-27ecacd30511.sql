-- =====================================================================
-- Slice 2 final hardening: predecessor chaining, reason enforcement,
-- null-safe merchant settlement, resolved Envoyer claim exposure,
-- single audited feature-flag write path.
-- =====================================================================

-- 1. Canonical predecessor resolver -----------------------------------
CREATE OR REPLACE FUNCTION public.finance_policy_predecessor(
  p_mission_type text,
  p_effective_from timestamptz
) RETURNS public.finance_policies
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT * FROM public.finance_policies
   WHERE mission_type = p_mission_type
     AND enabled = true
     AND effective_from < COALESCE(p_effective_from, now())
   ORDER BY effective_from DESC, created_at DESC
   LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.finance_policy_predecessor(text, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.finance_policy_predecessor(text, timestamptz) TO authenticated, service_role;

-- 2. admin_set_finance_policy: chain from the immediate predecessor ----
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
  p_claims_exposure_max_gnf bigint DEFAULT NULL
) RETURNS public.finance_policies
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_before public.finance_policies;
  v_new public.finance_policies;
  v_latest timestamptz;
  v_commission integer; v_fixed bigint; v_minbal bigint;
  v_mode text; v_pct integer; v_colfixed bigint; v_colmin bigint; v_colmax bigint;
  v_colbasis text; v_fee integer; v_feebasis text;
  v_cb integer; v_ca integer; v_cbasis text;
  v_cfmode text; v_cfpct integer; v_cfmax bigint;
  v_require boolean;
  v_exposure_bps integer; v_max_declared bigint; v_claims_max bigint;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.is_god_admin(v_caller) THEN
    RAISE EXCEPTION 'Only a God Admin can change finance policy';
  END IF;
  IF p_mission_type NOT IN ('ride','bonbonna','repas','marche','envoyer') THEN
    RAISE EXCEPTION 'Unknown mission type %', p_mission_type;
  END IF;
  IF length(btrim(COALESCE(p_note,''))) < 5 THEN
    RAISE EXCEPTION 'REASON_REQUIRED' USING DETAIL = 'A human-entered reason of at least 5 characters is mandatory';
  END IF;
  IF p_effective_from < now() - interval '1 minute' THEN
    RAISE EXCEPTION 'BACKDATING_REJECTED'
      USING DETAIL = 'Effective date cannot be in the past; policy history is immutable';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('finance_policy:' || p_mission_type));

  SELECT max(effective_from) INTO v_latest
    FROM public.finance_policies WHERE mission_type = p_mission_type;
  IF v_latest IS NOT NULL AND p_effective_from <= v_latest THEN
    RAISE EXCEPTION 'EFFECTIVE_FROM_NOT_MONOTONIC'
      USING DETAIL = format('A policy already exists at or after %s for %s', v_latest, p_mission_type);
  END IF;

  -- CHAINING FIX: inherit from the row immediately preceding the NEW effective
  -- time, which may itself be a scheduled (not yet active) policy.
  SELECT * INTO v_before FROM public.finance_policy_predecessor(p_mission_type, p_effective_from);

  v_commission := COALESCE(p_commission_bps, v_before.commission_bps, 0);
  v_fixed      := COALESCE(p_fixed_commission_gnf, v_before.fixed_commission_gnf, 0);
  v_minbal     := COALESCE(p_min_driver_balance_gnf, v_before.min_driver_balance_gnf, 0);
  v_mode       := COALESCE(p_collateral_mode, v_before.collateral_mode, 'none');
  v_pct        := COALESCE(p_collateral_pct_bps, v_before.collateral_pct_bps, 0);
  v_colfixed   := COALESCE(p_collateral_fixed_gnf, v_before.collateral_fixed_gnf, 0);
  v_colmin     := COALESCE(p_collateral_min_gnf, v_before.collateral_min_gnf, 0);
  v_colmax     := COALESCE(p_collateral_max_gnf, v_before.collateral_max_gnf);
  v_colbasis   := COALESCE(p_collateral_basis, v_before.collateral_basis, 'none');
  v_fee        := COALESCE(p_transaction_fee_bps, v_before.transaction_fee_bps, 0);
  v_feebasis   := COALESCE(p_fee_basis, v_before.fee_basis, 'none');
  v_cb         := COALESCE(p_cancel_before_dispatch_bps, v_before.cancel_before_dispatch_bps, 500);
  v_ca         := COALESCE(p_cancel_after_dispatch_bps, v_before.cancel_after_dispatch_bps, 1000);
  v_cbasis     := COALESCE(p_cancel_basis, v_before.cancel_basis, 'none');
  v_cfmode     := COALESCE(p_cash_funding_mode, v_before.cash_funding_mode, 'none');
  v_cfpct      := COALESCE(p_cash_funding_pct_bps, v_before.cash_funding_pct_bps, 0);
  v_cfmax      := COALESCE(p_cash_funding_max_gnf, v_before.cash_funding_max_gnf);
  v_require    := COALESCE(p_require_collateral_before_offer, v_before.require_collateral_before_offer, false);

  IF v_colbasis NOT IN ('none','fare','merchandise_subtotal','declared_value') THEN
    RAISE EXCEPTION 'Invalid collateral basis';
  END IF;
  IF v_cbasis NOT IN ('none','fare','merchandise_plus_delivery','delivery_fee') THEN
    RAISE EXCEPTION 'Invalid cancellation basis';
  END IF;
  IF v_feebasis NOT IN ('none','fare','merchandise_subtotal','declared_value','delivery_fee','order_total','transfer_amount') THEN
    RAISE EXCEPTION 'Invalid fee basis';
  END IF;
  IF v_mode <> 'none' AND v_colbasis = 'none' THEN RAISE EXCEPTION 'COLLATERAL_BASIS_REQUIRED'; END IF;
  IF v_fee > 0 AND v_feebasis = 'none' THEN RAISE EXCEPTION 'FEE_BASIS_REQUIRED'; END IF;
  IF GREATEST(v_cb, v_ca) > 0 AND v_cbasis = 'none' THEN RAISE EXCEPTION 'CANCEL_BASIS_REQUIRED'; END IF;
  IF v_commission < 0 OR v_commission > 10000 THEN RAISE EXCEPTION 'COMMISSION_BPS_OUT_OF_RANGE'; END IF;
  IF v_pct < 0 OR v_pct > 10000 THEN RAISE EXCEPTION 'COLLATERAL_BPS_OUT_OF_RANGE'; END IF;

  -- Claims exposure: platform share is the remainder of the declared value.
  v_exposure_bps := 10000 - v_pct;
  v_max_declared := COALESCE(p_max_declared_value_gnf, v_before.max_declared_value_gnf);

  IF p_mission_type = 'envoyer' THEN
    IF v_max_declared IS NULL OR v_max_declared <= 0 THEN
      RAISE EXCEPTION 'MAX_DECLARED_VALUE_REQUIRED';
    END IF;
    -- Persist the derived maximum whenever the God Admin does not set a lower cap.
    v_claims_max := COALESCE(
      p_claims_exposure_max_gnf,
      CASE WHEN p_collateral_pct_bps IS NULL AND p_max_declared_value_gnf IS NULL
           THEN v_before.claims_exposure_max_gnf ELSE NULL END,
      (v_max_declared * v_exposure_bps) / 10000
    );
    IF v_claims_max > (v_max_declared * v_exposure_bps) / 10000 THEN
      RAISE EXCEPTION 'CLAIMS_EXPOSURE_EXCEEDS_REMAINDER'
        USING DETAIL = format('Collateral %s bps leaves at most %s GNF of platform exposure at a %s GNF cap',
                              v_pct, (v_max_declared * v_exposure_bps) / 10000, v_max_declared);
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
    (p_mission_type, v_commission, v_fixed, v_minbal,
     v_mode, v_pct, v_colfixed, v_colmin, v_colmax, v_require,
     v_colbasis, v_fee, v_feebasis, v_cb, v_ca, v_cbasis,
     v_cfmode, v_cfpct, v_cfmax,
     v_max_declared, v_claims_max, p_effective_from, p_note, v_caller)
  RETURNING * INTO v_new;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, before, after, note)
  VALUES (v_caller, 'pricing', 'finance_policy_set', 'finance_policy', p_mission_type,
          to_jsonb(v_before), to_jsonb(v_new), p_note);

  RETURN v_new;
END; $$;

-- 3. Starter credit: chain from predecessor + mandatory reason --------
CREATE OR REPLACE FUNCTION public.admin_set_starter_credit_policy(
  p_amount_gnf bigint,
  p_enabled boolean DEFAULT true,
  p_effective_from timestamptz DEFAULT now(),
  p_note text DEFAULT NULL
) RETURNS public.driver_starter_credit_policies
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
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
  IF length(btrim(COALESCE(p_note,''))) < 5 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  IF p_effective_from < now() - interval '1 minute' THEN RAISE EXCEPTION 'BACKDATING_REJECTED'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext('starter_credit_policy'));
  SELECT max(effective_from) INTO v_latest FROM public.driver_starter_credit_policies;
  IF v_latest IS NOT NULL AND p_effective_from <= v_latest THEN
    RAISE EXCEPTION 'EFFECTIVE_FROM_NOT_MONOTONIC';
  END IF;

  SELECT * INTO v_before FROM public.driver_starter_credit_policies
   WHERE effective_from < p_effective_from
   ORDER BY effective_from DESC, created_at DESC LIMIT 1;

  IF COALESCE(p_amount_gnf, v_before.amount_gnf) IS NULL
     OR COALESCE(p_amount_gnf, v_before.amount_gnf) < 0 THEN
    RAISE EXCEPTION 'INVALID_AMOUNT';
  END IF;

  INSERT INTO public.driver_starter_credit_policies (amount_gnf, enabled, effective_from, note, created_by)
  VALUES (COALESCE(p_amount_gnf, v_before.amount_gnf),
          COALESCE(p_enabled, v_before.enabled, true), p_effective_from, p_note, v_caller)
  RETURNING * INTO v_new;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, before, after, note)
  VALUES (v_caller, 'wallet', 'starter_credit_policy_set', 'starter_credit_policy', v_new.id::text,
          to_jsonb(v_before), to_jsonb(v_new), p_note);
  RETURN v_new;
END; $$;

-- 4. Payout policy: chain from predecessor + mandatory reason ---------
CREATE OR REPLACE FUNCTION public.admin_set_payout_policy(
  p_min_request_gnf bigint,
  p_max_request_gnf bigint,
  p_daily_limit_gnf bigint,
  p_cancel_window_seconds integer DEFAULT NULL,
  p_processing_estimate_min_minutes integer DEFAULT NULL,
  p_processing_estimate_max_minutes integer DEFAULT NULL,
  p_provider_fee_passthrough boolean DEFAULT NULL,
  p_effective_from timestamptz DEFAULT now(),
  p_note text DEFAULT NULL
) RETURNS public.driver_payout_policies
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_before public.driver_payout_policies;
  v_new public.driver_payout_policies;
  v_latest timestamptz;
  v_min bigint; v_max bigint; v_daily bigint;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.is_god_admin(v_caller) THEN
    RAISE EXCEPTION 'Only a God Admin can change payout policy';
  END IF;
  IF length(btrim(COALESCE(p_note,''))) < 5 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  IF p_effective_from < now() - interval '1 minute' THEN RAISE EXCEPTION 'BACKDATING_REJECTED'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext('driver_payout_policy'));
  SELECT max(effective_from) INTO v_latest FROM public.driver_payout_policies;
  IF v_latest IS NOT NULL AND p_effective_from <= v_latest THEN
    RAISE EXCEPTION 'EFFECTIVE_FROM_NOT_MONOTONIC';
  END IF;

  SELECT * INTO v_before FROM public.driver_payout_policies
   WHERE effective_from < p_effective_from
   ORDER BY effective_from DESC, created_at DESC LIMIT 1;

  v_min   := COALESCE(p_min_request_gnf, v_before.min_request_gnf);
  v_max   := COALESCE(p_max_request_gnf, v_before.max_request_gnf);
  v_daily := COALESCE(p_daily_limit_gnf, v_before.daily_limit_gnf);
  IF v_min IS NULL OR v_max IS NULL OR v_daily IS NULL THEN RAISE EXCEPTION 'PAYOUT_LIMITS_REQUIRED'; END IF;
  IF v_daily < v_min THEN RAISE EXCEPTION 'DAILY_LIMIT_BELOW_MINIMUM'; END IF;
  IF v_max < v_min THEN RAISE EXCEPTION 'MAX_BELOW_MINIMUM'; END IF;

  INSERT INTO public.driver_payout_policies
    (min_request_gnf, max_request_gnf, daily_limit_gnf, cancel_window_seconds,
     processing_estimate_min_minutes, processing_estimate_max_minutes,
     provider_fee_passthrough, effective_from, note, created_by)
  VALUES
    (v_min, v_max, v_daily,
     COALESCE(p_cancel_window_seconds, v_before.cancel_window_seconds, 60),
     COALESCE(p_processing_estimate_min_minutes, v_before.processing_estimate_min_minutes, 1),
     COALESCE(p_processing_estimate_max_minutes, v_before.processing_estimate_max_minutes, 5),
     COALESCE(p_provider_fee_passthrough, v_before.provider_fee_passthrough, true),
     p_effective_from, p_note, v_caller)
  RETURNING * INTO v_new;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, before, after, note)
  VALUES (v_caller,'wallet','payout_policy_set','driver_payout_policy', v_new.id::text,
          to_jsonb(v_before), to_jsonb(v_new), p_note);
  RETURN v_new;
END; $$;

-- 5. Merchant settlement: null-safe, cadence-validated ----------------
CREATE OR REPLACE FUNCTION public.admin_set_merchant_settlement_policy(
  p_configured boolean DEFAULT NULL,
  p_min_settlement_gnf bigint DEFAULT NULL,
  p_max_settlement_gnf bigint DEFAULT NULL,
  p_cadence text DEFAULT NULL,
  p_fee_bps integer DEFAULT NULL,
  p_fee_fixed_gnf bigint DEFAULT NULL,
  p_fee_passthrough boolean DEFAULT NULL,
  p_effective_from timestamptz DEFAULT now(),
  p_note text DEFAULT NULL
) RETURNS public.merchant_settlement_policies
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_before public.merchant_settlement_policies;
  v_new public.merchant_settlement_policies;
  v_latest timestamptz;
  v_conf boolean; v_cad text; v_min bigint; v_max bigint;
  v_fee integer; v_feefix bigint; v_pass boolean;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.is_god_admin(v_caller) THEN
    RAISE EXCEPTION 'Only a God Admin can change merchant settlement policy';
  END IF;
  IF length(btrim(COALESCE(p_note,''))) < 5 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  IF p_effective_from < now() - interval '1 minute' THEN RAISE EXCEPTION 'BACKDATING_REJECTED'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext('merchant_settlement_policy'));
  SELECT max(effective_from) INTO v_latest FROM public.merchant_settlement_policies;
  IF v_latest IS NOT NULL AND p_effective_from <= v_latest THEN
    RAISE EXCEPTION 'EFFECTIVE_FROM_NOT_MONOTONIC';
  END IF;

  SELECT * INTO v_before FROM public.merchant_settlement_policies
   WHERE effective_from < p_effective_from
   ORDER BY effective_from DESC, created_at DESC LIMIT 1;

  v_conf   := COALESCE(p_configured, v_before.configured, false);
  -- NULL means "inherit"; the caller clears a value by passing configured=false
  -- with explicit nulls on a fresh unconfigured row.
  v_cad    := CASE WHEN v_conf THEN COALESCE(p_cadence, v_before.cadence) ELSE p_cadence END;
  v_min    := CASE WHEN v_conf THEN COALESCE(p_min_settlement_gnf, v_before.min_settlement_gnf) ELSE p_min_settlement_gnf END;
  v_max    := CASE WHEN v_conf THEN COALESCE(p_max_settlement_gnf, v_before.max_settlement_gnf) ELSE p_max_settlement_gnf END;
  v_fee    := CASE WHEN v_conf THEN COALESCE(p_fee_bps, v_before.fee_bps) ELSE p_fee_bps END;
  v_feefix := CASE WHEN v_conf THEN COALESCE(p_fee_fixed_gnf, v_before.fee_fixed_gnf) ELSE p_fee_fixed_gnf END;
  v_pass   := CASE WHEN v_conf THEN COALESCE(p_fee_passthrough, v_before.fee_passthrough) ELSE p_fee_passthrough END;

  IF v_cad IS NOT NULL AND v_cad NOT IN ('daily','weekly','biweekly','monthly','on_demand') THEN
    RAISE EXCEPTION 'INVALID_SETTLEMENT_CADENCE'
      USING DETAIL = 'Allowed: daily, weekly, biweekly, monthly, on_demand (or unset)';
  END IF;
  IF v_conf THEN
    IF v_cad IS NULL THEN RAISE EXCEPTION 'SETTLEMENT_CADENCE_REQUIRED'; END IF;
    IF v_min IS NULL THEN RAISE EXCEPTION 'SETTLEMENT_MINIMUM_REQUIRED'; END IF;
  END IF;

  INSERT INTO public.merchant_settlement_policies
    (configured, min_settlement_gnf, max_settlement_gnf, cadence, fee_bps, fee_fixed_gnf,
     fee_passthrough, effective_from, note, created_by)
  VALUES
    (v_conf, v_min, v_max, v_cad, v_fee, v_feefix, v_pass, p_effective_from, p_note, v_caller)
  RETURNING * INTO v_new;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, before, after, note)
  VALUES (v_caller,'wallet','merchant_settlement_policy_set','merchant_settlement_policy', v_new.id::text,
          to_jsonb(v_before), to_jsonb(v_new), p_note);
  RETURN v_new;
END; $$;

-- 6. Provider fee schedule: predecessor + mandatory reason ------------
CREATE OR REPLACE FUNCTION public.admin_set_provider_fee_schedule(
  p_provider text,
  p_fee_bps integer,
  p_fee_fixed_gnf bigint DEFAULT NULL,
  p_min_fee_gnf bigint DEFAULT NULL,
  p_max_fee_gnf bigint DEFAULT NULL,
  p_passthrough_to_recipient boolean DEFAULT NULL,
  p_effective_from timestamptz DEFAULT now(),
  p_note text DEFAULT NULL
) RETURNS public.provider_fee_schedules
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_god boolean; v_delegated boolean; v_finance boolean;
  v_before public.provider_fee_schedules;
  v_new public.provider_fee_schedules;
  v_latest timestamptz;
  v_provider text := COALESCE(p_provider,'orange_money');
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
  IF length(btrim(COALESCE(p_note,''))) < 5 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  IF p_effective_from < now() - interval '1 minute' THEN RAISE EXCEPTION 'BACKDATING_REJECTED'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext('provider_fee:' || v_provider));
  SELECT max(effective_from) INTO v_latest FROM public.provider_fee_schedules WHERE provider = v_provider;
  IF v_latest IS NOT NULL AND p_effective_from <= v_latest THEN
    RAISE EXCEPTION 'EFFECTIVE_FROM_NOT_MONOTONIC';
  END IF;

  SELECT * INTO v_before FROM public.provider_fee_schedules
   WHERE provider = v_provider AND effective_from < p_effective_from
   ORDER BY effective_from DESC, created_at DESC LIMIT 1;

  INSERT INTO public.provider_fee_schedules
    (provider, fee_bps, fee_fixed_gnf, min_fee_gnf, max_fee_gnf, passthrough_to_recipient,
     effective_from, note, created_by)
  VALUES
    (v_provider,
     COALESCE(p_fee_bps, v_before.fee_bps, 0),
     COALESCE(p_fee_fixed_gnf, v_before.fee_fixed_gnf, 0),
     COALESCE(p_min_fee_gnf, v_before.min_fee_gnf, 0),
     COALESCE(p_max_fee_gnf, v_before.max_fee_gnf),
     COALESCE(p_passthrough_to_recipient, v_before.passthrough_to_recipient, true),
     p_effective_from, p_note, v_caller)
  RETURNING * INTO v_new;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, before, after, note)
  VALUES (v_caller,'wallet','provider_fee_schedule_set','provider_fee_schedule', v_new.id::text,
          to_jsonb(v_before), to_jsonb(v_new), p_note);
  RETURN v_new;
END; $$;

-- 7. Feature flags: one audited write path ----------------------------
DROP POLICY IF EXISTS "God admins write flags" ON public.feature_flags;
REVOKE INSERT, UPDATE, DELETE ON public.feature_flags FROM anon, authenticated;
GRANT SELECT ON public.feature_flags TO anon, authenticated;
GRANT ALL ON public.feature_flags TO service_role;

CREATE OR REPLACE FUNCTION public.admin_set_feature_flag(
  p_key text, p_enabled boolean, p_note text DEFAULT NULL
) RETURNS public.feature_flags
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_before public.feature_flags;
  v_new public.feature_flags;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.is_god_admin(v_caller) THEN
    RAISE EXCEPTION 'Only a God Admin can change feature flags';
  END IF;
  IF length(btrim(COALESCE(p_note,''))) < 5 THEN
    RAISE EXCEPTION 'REASON_REQUIRED' USING DETAIL = 'A human-entered reason is mandatory for flag changes';
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

-- 8. Snapshot v2: resolved claims exposure + explicit cash funding basis
CREATE OR REPLACE FUNCTION public.finance_policy_snapshot(
  p_mission_type text,
  p_as_of timestamptz DEFAULT now(),
  p_payment_mode text DEFAULT 'chop_pay',
  p_fare_gnf bigint DEFAULT 0,
  p_merchandise_subtotal_gnf bigint DEFAULT 0,
  p_delivery_fee_gnf bigint DEFAULT 0,
  p_declared_value_gnf bigint DEFAULT 0,
  p_is_sandbox boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
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
    -- Resolved even when the legacy policy row predates the column.
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
END; $$;

-- 9. Validator: envelope must fit inside the resolved exposure cap ----
CREATE OR REPLACE FUNCTION public.finance_policy_snapshot_validate(p_snapshot jsonb)
RETURNS boolean
LANGUAGE plpgsql IMMUTABLE SET search_path TO 'public' AS $$
DECLARE
  v_type text := p_snapshot->>'mission_type';
  v_coll int := COALESCE((p_snapshot->>'collateral_pct_bps')::int, 0);
  v_expo int := COALESCE((p_snapshot->>'claims_exposure_pct_bps')::int, 0);
  v_ver int := COALESCE((p_snapshot->>'version')::int, 0);
  v_max bigint; v_env bigint;
BEGIN
  IF p_snapshot IS NULL OR p_snapshot->>'schema' IS DISTINCT FROM 'chopchop.finance.policy_snapshot' THEN
    RAISE EXCEPTION 'SNAPSHOT_SCHEMA_INVALID';
  END IF;
  IF v_ver NOT IN (1,2) THEN RAISE EXCEPTION 'SNAPSHOT_VERSION_UNSUPPORTED'; END IF;
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
  IF COALESCE((p_snapshot->>'cash_funding_pct_bps')::int,0) > 0
     AND COALESCE(p_snapshot->>'cash_funding_basis', p_snapshot->>'cash_funding_mode', 'none') = 'none' THEN
    RAISE EXCEPTION 'SNAPSHOT_CASH_FUNDING_BASIS_AMBIGUOUS';
  END IF;
  IF v_coll + v_expo > 10000 THEN
    RAISE EXCEPTION 'SNAPSHOT_COVERAGE_EXCEEDS_100_PCT';
  END IF;
  IF v_type = 'envoyer' THEN
    IF COALESCE((p_snapshot->>'declared_value_gnf')::bigint,0)
       > COALESCE((p_snapshot->>'max_declared_value_gnf')::bigint, 0) THEN
      RAISE EXCEPTION 'SNAPSHOT_DECLARED_VALUE_ABOVE_CAP';
    END IF;
    IF v_ver >= 2 THEN
      v_max := (p_snapshot->>'claims_exposure_max_gnf')::bigint;
      v_env := (p_snapshot->>'claim_envelope_gnf')::bigint;
      IF v_max IS NULL THEN RAISE EXCEPTION 'SNAPSHOT_CLAIMS_EXPOSURE_MISSING'; END IF;
      IF v_env IS NOT NULL AND v_env > v_max THEN
        RAISE EXCEPTION 'SNAPSHOT_CLAIM_ENVELOPE_EXCEEDS_MAX';
      END IF;
    END IF;
  END IF;
  RETURN true;
END; $$;

REVOKE ALL ON FUNCTION public.admin_set_finance_policy(text,integer,bigint,text,integer,bigint,bigint,bigint,bigint,boolean,timestamptz,text,text,integer,text,integer,integer,text,text,integer,bigint,bigint,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_finance_policy(text,integer,bigint,text,integer,bigint,bigint,bigint,bigint,boolean,timestamptz,text,text,integer,text,integer,integer,text,text,integer,bigint,bigint,bigint) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_set_starter_credit_policy(bigint,boolean,timestamptz,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_starter_credit_policy(bigint,boolean,timestamptz,text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_set_payout_policy(bigint,bigint,bigint,integer,integer,integer,boolean,timestamptz,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_payout_policy(bigint,bigint,bigint,integer,integer,integer,boolean,timestamptz,text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_set_merchant_settlement_policy(boolean,bigint,bigint,text,integer,bigint,boolean,timestamptz,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_merchant_settlement_policy(boolean,bigint,bigint,text,integer,bigint,boolean,timestamptz,text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_set_provider_fee_schedule(text,integer,bigint,bigint,bigint,boolean,timestamptz,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_provider_fee_schedule(text,integer,bigint,bigint,bigint,boolean,timestamptz,text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_set_feature_flag(text,boolean,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_feature_flag(text,boolean,text) TO authenticated, service_role;
