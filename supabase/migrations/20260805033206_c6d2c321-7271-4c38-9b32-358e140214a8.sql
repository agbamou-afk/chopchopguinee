-- =====================================================================
-- Chop Pay: finance policy + driver commission/collateral engine
-- =====================================================================

CREATE TABLE public.finance_policies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  mission_type text NOT NULL,
  commission_bps integer NOT NULL DEFAULT 1000,
  fixed_commission_gnf bigint NOT NULL DEFAULT 0,
  min_driver_balance_gnf bigint NOT NULL DEFAULT 0,
  collateral_mode text NOT NULL DEFAULT 'none',
  collateral_pct_bps integer NOT NULL DEFAULT 0,
  collateral_fixed_gnf bigint NOT NULL DEFAULT 0,
  collateral_min_gnf bigint NOT NULL DEFAULT 0,
  collateral_max_gnf bigint,
  require_collateral_before_offer boolean NOT NULL DEFAULT false,
  effective_from timestamptz NOT NULL DEFAULT now(),
  enabled boolean NOT NULL DEFAULT true,
  note text,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT finance_policies_mission_type_chk
    CHECK (mission_type IN ('ride','bonbonna','repas','marche','envoyer')),
  CONSTRAINT finance_policies_commission_chk CHECK (commission_bps BETWEEN 0 AND 5000),
  CONSTRAINT finance_policies_fixed_chk CHECK (fixed_commission_gnf >= 0),
  CONSTRAINT finance_policies_minbal_chk CHECK (min_driver_balance_gnf >= 0),
  CONSTRAINT finance_policies_mode_chk CHECK (collateral_mode IN ('none','fixed','percentage')),
  CONSTRAINT finance_policies_pct_chk CHECK (collateral_pct_bps BETWEEN 0 AND 10000),
  CONSTRAINT finance_policies_colmin_chk CHECK (collateral_min_gnf >= 0),
  CONSTRAINT finance_policies_colmax_chk CHECK (collateral_max_gnf IS NULL OR collateral_max_gnf >= collateral_min_gnf)
);

CREATE INDEX idx_finance_policies_lookup
  ON public.finance_policies (mission_type, effective_from DESC);

GRANT SELECT ON public.finance_policies TO authenticated;
GRANT ALL ON public.finance_policies TO service_role;
ALTER TABLE public.finance_policies ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated can read finance policies"
  ON public.finance_policies FOR SELECT TO authenticated USING (true);

CREATE TRIGGER trg_finance_policies_updated_at
  BEFORE UPDATE ON public.finance_policies
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Seed launch defaults ------------------------------------------------
INSERT INTO public.finance_policies
  (mission_type, commission_bps, min_driver_balance_gnf, collateral_mode,
   collateral_pct_bps, collateral_min_gnf, collateral_max_gnf,
   require_collateral_before_offer, note)
VALUES
  ('ride',     1000, 5000,  'none',       0,     0,     NULL, false,
   'Cash ride launch model: 10% commission from driver operating balance.'),
  ('bonbonna', 1000, 5000,  'none',       0,     0,     NULL, false,
   'Bonbonna cash ride: 10% commission from driver operating balance.'),
  ('repas',    1000, 5000,  'percentage', 10000, 0,     500000, false,
   'Repas: collateral equal to entrusted order value, capped at 500k GNF.'),
  ('marche',   1000, 5000,  'percentage', 10000, 0,     1000000, false,
   'Marche: collateral equal to entrusted merchandise value, capped at 1M GNF.'),
  ('envoyer',  1000, 5000,  'percentage', 5000,  0,     500000, false,
   'Envoyer: 50% of declared package value as collateral, capped at 500k GNF.');

-- =====================================================================
-- Mission financial holds (commission reserve + collateral)
-- =====================================================================

CREATE TABLE public.mission_financial_holds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_user_id uuid NOT NULL,
  mission_type text NOT NULL,
  source_module text NOT NULL,
  source_id uuid NOT NULL,
  kind text NOT NULL,
  amount_gnf bigint NOT NULL,
  captured_gnf bigint NOT NULL DEFAULT 0,
  state text NOT NULL DEFAULT 'held',
  hold_tx_id uuid,
  resolution_tx_id uuid,
  policy_id uuid,
  policy_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  basis_value_gnf bigint NOT NULL DEFAULT 0,
  is_sandbox boolean NOT NULL DEFAULT false,
  reason text,
  resolved_by uuid,
  resolved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT mfh_kind_chk CHECK (kind IN ('commission','collateral')),
  CONSTRAINT mfh_state_chk CHECK (state IN ('held','released','captured','frozen')),
  CONSTRAINT mfh_amount_chk CHECK (amount_gnf >= 0),
  CONSTRAINT mfh_captured_chk CHECK (captured_gnf >= 0 AND captured_gnf <= amount_gnf),
  CONSTRAINT mfh_unique_source UNIQUE (source_module, source_id, kind)
);

CREATE INDEX idx_mfh_driver ON public.mission_financial_holds (driver_user_id, state);

GRANT SELECT ON public.mission_financial_holds TO authenticated;
GRANT ALL ON public.mission_financial_holds TO service_role;
ALTER TABLE public.mission_financial_holds ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Drivers read their own mission holds"
  ON public.mission_financial_holds FOR SELECT TO authenticated
  USING (driver_user_id = auth.uid());

CREATE POLICY "Finance and god admins read all mission holds"
  ON public.mission_financial_holds FOR SELECT TO authenticated
  USING (public.has_admin_role(auth.uid(), 'finance_admin'::admin_role)
         OR public.is_god_admin(auth.uid()));

CREATE TRIGGER trg_mfh_updated_at
  BEFORE UPDATE ON public.mission_financial_holds
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- =====================================================================
-- Policy resolution + requirement calculator
-- =====================================================================

CREATE OR REPLACE FUNCTION public.finance_policy_current(p_mission_type text)
RETURNS public.finance_policies
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT * FROM public.finance_policies
   WHERE mission_type = p_mission_type
     AND enabled = true
     AND effective_from <= now()
   ORDER BY effective_from DESC, created_at DESC
   LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.finance_mission_requirement(
  p_mission_type text,
  p_value_gnf bigint DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_p public.finance_policies;
  v_commission bigint := 0;
  v_collateral bigint := 0;
  v_value bigint := GREATEST(COALESCE(p_value_gnf, 0), 0);
BEGIN
  SELECT * INTO v_p FROM public.finance_policy_current(p_mission_type);
  IF v_p.id IS NULL THEN
    RETURN jsonb_build_object(
      'policy_id', NULL, 'mission_type', p_mission_type,
      'commission_gnf', 0, 'collateral_gnf', 0,
      'min_balance_gnf', 0, 'required_hold_gnf', 0,
      'required_available_gnf', 0, 'has_policy', false);
  END IF;

  v_commission := (v_value * v_p.commission_bps) / 10000 + v_p.fixed_commission_gnf;

  IF v_p.collateral_mode = 'fixed' THEN
    v_collateral := v_p.collateral_fixed_gnf;
  ELSIF v_p.collateral_mode = 'percentage' THEN
    v_collateral := (v_value * v_p.collateral_pct_bps) / 10000;
  END IF;

  IF v_collateral > 0 OR v_p.collateral_mode <> 'none' THEN
    v_collateral := GREATEST(v_collateral, v_p.collateral_min_gnf);
    IF v_p.collateral_max_gnf IS NOT NULL THEN
      v_collateral := LEAST(v_collateral, v_p.collateral_max_gnf);
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'policy_id', v_p.id,
    'mission_type', p_mission_type,
    'basis_value_gnf', v_value,
    'commission_gnf', v_commission,
    'collateral_gnf', v_collateral,
    'min_balance_gnf', v_p.min_driver_balance_gnf,
    'required_hold_gnf', v_commission + v_collateral,
    'required_available_gnf', GREATEST(v_commission + v_collateral, v_p.min_driver_balance_gnf),
    'require_collateral_before_offer', v_p.require_collateral_before_offer,
    'has_policy', true,
    'policy_snapshot', jsonb_build_object(
      'policy_id', v_p.id,
      'commission_bps', v_p.commission_bps,
      'fixed_commission_gnf', v_p.fixed_commission_gnf,
      'collateral_mode', v_p.collateral_mode,
      'collateral_pct_bps', v_p.collateral_pct_bps,
      'collateral_min_gnf', v_p.collateral_min_gnf,
      'collateral_max_gnf', v_p.collateral_max_gnf,
      'min_driver_balance_gnf', v_p.min_driver_balance_gnf,
      'effective_from', v_p.effective_from
    ));
END;
$$;

-- =====================================================================
-- Driver operating balance summary + eligibility
-- =====================================================================

CREATE OR REPLACE FUNCTION public.driver_balance_summary(p_driver uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_target uuid := COALESCE(p_driver, auth.uid());
  v_w public.wallets;
  v_collateral bigint := 0;
  v_commission bigint := 0;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF v_target <> v_caller
     AND NOT public.has_admin_role(v_caller, 'finance_admin'::admin_role)
     AND NOT public.is_god_admin(v_caller) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  SELECT * INTO v_w FROM public.wallets
   WHERE owner_user_id = v_target AND party_type = 'driver';

  SELECT COALESCE(SUM(amount_gnf) FILTER (WHERE kind = 'collateral'), 0),
         COALESCE(SUM(amount_gnf) FILTER (WHERE kind = 'commission'), 0)
    INTO v_collateral, v_commission
    FROM public.mission_financial_holds
   WHERE driver_user_id = v_target AND state IN ('held','frozen');

  RETURN jsonb_build_object(
    'wallet_id', v_w.id,
    'balance_gnf', COALESCE(v_w.balance_gnf, 0),
    'held_gnf', COALESCE(v_w.held_gnf, 0),
    'available_gnf', GREATEST(COALESCE(v_w.balance_gnf, 0) - COALESCE(v_w.held_gnf, 0), 0),
    'collateral_held_gnf', v_collateral,
    'commission_held_gnf', v_commission,
    'status', COALESCE(v_w.status::text, 'active')
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.driver_financial_eligibility(
  p_mission_type text,
  p_value_gnf bigint DEFAULT 0,
  p_driver uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_req jsonb;
  v_sum jsonb;
  v_avail bigint;
  v_need bigint;
BEGIN
  v_req := public.finance_mission_requirement(p_mission_type, p_value_gnf);
  v_sum := public.driver_balance_summary(p_driver);
  v_avail := (v_sum->>'available_gnf')::bigint;
  v_need := (v_req->>'required_available_gnf')::bigint;
  RETURN jsonb_build_object(
    'eligible', v_avail >= v_need,
    'available_gnf', v_avail,
    'required_gnf', v_need,
    'shortfall_gnf', GREATEST(v_need - v_avail, 0),
    'requirement', v_req,
    'balance', v_sum
  );
END;
$$;

-- =====================================================================
-- Hold placement / release / capture (idempotent, server-authoritative)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.driver_mission_hold_place(
  p_mission_type text,
  p_source_module text,
  p_source_id uuid,
  p_value_gnf bigint DEFAULT 0,
  p_driver uuid DEFAULT NULL,
  p_is_sandbox boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_driver uuid := COALESCE(p_driver, auth.uid());
  v_req jsonb;
  v_wallet public.wallets;
  v_avail bigint;
  v_total bigint;
  v_existing int;
  v_kind text;
  v_amount bigint;
  v_tx public.wallet_transactions;
  v_ids jsonb := '[]'::jsonb;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF v_driver <> v_caller AND NOT public.is_god_admin(v_caller)
     AND NOT public.has_admin_role(v_caller, 'finance_admin'::admin_role) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  -- Idempotency: existing holds for this mission win.
  SELECT count(*) INTO v_existing FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id;
  IF v_existing > 0 THEN
    RETURN jsonb_build_object('status', 'already_held', 'source_id', p_source_id);
  END IF;

  v_req := public.finance_mission_requirement(p_mission_type, p_value_gnf);

  SELECT * INTO v_wallet FROM public.wallets
   WHERE owner_user_id = v_driver AND party_type = 'driver' FOR UPDATE;
  IF v_wallet.id IS NULL THEN
    INSERT INTO public.wallets (owner_user_id, party_type)
    VALUES (v_driver, 'driver')
    ON CONFLICT (owner_user_id, party_type) DO NOTHING;
    SELECT * INTO v_wallet FROM public.wallets
     WHERE owner_user_id = v_driver AND party_type = 'driver' FOR UPDATE;
  END IF;
  IF v_wallet.status <> 'active' THEN RAISE EXCEPTION 'Wallet not active'; END IF;

  v_avail := GREATEST(v_wallet.balance_gnf - v_wallet.held_gnf, 0);
  v_total := (v_req->>'required_hold_gnf')::bigint;

  IF v_avail < (v_req->>'required_available_gnf')::bigint THEN
    RAISE EXCEPTION 'INSUFFICIENT_DRIVER_BALANCE'
      USING DETAIL = format('required=%s available=%s',
        (v_req->>'required_available_gnf'), v_avail);
  END IF;

  FOREACH v_kind IN ARRAY ARRAY['commission','collateral'] LOOP
    v_amount := (v_req->>(v_kind || '_gnf'))::bigint;
    CONTINUE WHEN COALESCE(v_amount, 0) <= 0;

    INSERT INTO public.wallet_transactions
      (reference, type, status, amount_gnf, from_wallet_id, related_user_id,
       related_entity, description, metadata)
    VALUES
      (format('mfh:%s:%s:%s', p_source_module, p_source_id, v_kind),
       'hold', 'pending', v_amount, v_wallet.id, v_driver,
       p_source_module || ':' || p_source_id::text,
       CASE WHEN v_kind = 'commission'
            THEN 'Réserve de commission mission'
            ELSE 'Caution mission' END,
       jsonb_build_object('mission_type', p_mission_type, 'kind', v_kind,
                          'is_sandbox', p_is_sandbox))
    RETURNING * INTO v_tx;

    UPDATE public.wallets SET held_gnf = held_gnf + v_amount, updated_at = now()
     WHERE id = v_wallet.id;

    INSERT INTO public.mission_financial_holds
      (driver_user_id, mission_type, source_module, source_id, kind,
       amount_gnf, hold_tx_id, policy_id, policy_snapshot,
       basis_value_gnf, is_sandbox)
    VALUES
      (v_driver, p_mission_type, p_source_module, p_source_id, v_kind,
       v_amount, v_tx.id, (v_req->>'policy_id')::uuid,
       COALESCE(v_req->'policy_snapshot', '{}'::jsonb),
       GREATEST(COALESCE(p_value_gnf, 0), 0), p_is_sandbox);

    v_ids := v_ids || jsonb_build_object('kind', v_kind, 'amount_gnf', v_amount);
  END LOOP;

  RETURN jsonb_build_object('status', 'held', 'total_gnf', v_total, 'holds', v_ids);
END;
$$;

CREATE OR REPLACE FUNCTION public.driver_mission_hold_release(
  p_source_module text,
  p_source_id uuid,
  p_kind text DEFAULT NULL,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_h public.mission_financial_holds;
  v_released bigint := 0;
  v_wallet_id uuid;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  FOR v_h IN
    SELECT * FROM public.mission_financial_holds
     WHERE source_module = p_source_module AND source_id = p_source_id
       AND (p_kind IS NULL OR kind = p_kind)
       AND state = 'held'
     FOR UPDATE
  LOOP
    IF v_h.driver_user_id <> v_caller
       AND NOT public.is_god_admin(v_caller)
       AND NOT public.has_admin_role(v_caller, 'finance_admin'::admin_role)
       AND NOT public.has_admin_role(v_caller, 'operations_admin'::admin_role) THEN
      RAISE EXCEPTION 'Not authorized';
    END IF;

    SELECT id INTO v_wallet_id FROM public.wallets
     WHERE owner_user_id = v_h.driver_user_id AND party_type = 'driver' FOR UPDATE;

    UPDATE public.wallets
       SET held_gnf = GREATEST(held_gnf - (v_h.amount_gnf - v_h.captured_gnf), 0),
           updated_at = now()
     WHERE id = v_wallet_id;

    UPDATE public.wallet_transactions
       SET status = 'cancelled', completed_at = now()
     WHERE id = v_h.hold_tx_id AND status = 'pending';

    UPDATE public.mission_financial_holds
       SET state = 'released', reason = COALESCE(p_reason, reason),
           resolved_at = now(), resolved_by = v_caller
     WHERE id = v_h.id;

    v_released := v_released + (v_h.amount_gnf - v_h.captured_gnf);
  END LOOP;

  RETURN jsonb_build_object('status', 'released', 'released_gnf', v_released);
END;
$$;

CREATE OR REPLACE FUNCTION public.driver_mission_commission_capture(
  p_source_module text,
  p_source_id uuid,
  p_final_value_gnf bigint
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_h public.mission_financial_holds;
  v_snap jsonb;
  v_due bigint;
  v_capture bigint;
  v_driver_wallet public.wallets;
  v_master public.wallets;
  v_tx public.wallet_transactions;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_h FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND kind = 'commission' FOR UPDATE;

  IF v_h.id IS NULL THEN
    RETURN jsonb_build_object('status', 'no_hold', 'captured_gnf', 0);
  END IF;
  IF v_h.state <> 'held' THEN
    RETURN jsonb_build_object('status', 'already_resolved',
                              'captured_gnf', v_h.captured_gnf);
  END IF;

  v_snap := v_h.policy_snapshot;
  v_due := (GREATEST(COALESCE(p_final_value_gnf, 0), 0)
            * COALESCE((v_snap->>'commission_bps')::int, 0)) / 10000
           + COALESCE((v_snap->>'fixed_commission_gnf')::bigint, 0);
  v_capture := LEAST(v_due, v_h.amount_gnf);

  SELECT * INTO v_driver_wallet FROM public.wallets
   WHERE owner_user_id = v_h.driver_user_id AND party_type = 'driver' FOR UPDATE;
  SELECT * INTO v_master FROM public.wallets
   WHERE party_type = 'master' FOR UPDATE LIMIT 1;

  -- Release the full reserve first, then move the captured part.
  UPDATE public.wallets
     SET held_gnf = GREATEST(held_gnf - v_h.amount_gnf, 0), updated_at = now()
   WHERE id = v_driver_wallet.id;

  IF v_capture > 0 THEN
    UPDATE public.wallets
       SET balance_gnf = balance_gnf - v_capture, updated_at = now()
     WHERE id = v_driver_wallet.id;
    IF v_master.id IS NOT NULL THEN
      UPDATE public.wallets
         SET balance_gnf = balance_gnf + v_capture, updated_at = now()
       WHERE id = v_master.id;
    END IF;
  END IF;

  INSERT INTO public.wallet_transactions
    (reference, type, status, amount_gnf, from_wallet_id, to_wallet_id,
     related_user_id, related_entity, description, metadata, completed_at)
  VALUES
    (format('mfh-capture:%s:%s', p_source_module, p_source_id),
     'commission', 'completed', v_capture, v_driver_wallet.id, v_master.id,
     v_h.driver_user_id, p_source_module || ':' || p_source_id::text,
     'Commission CHOPCHOP',
     jsonb_build_object('mission_type', v_h.mission_type,
                        'final_value_gnf', p_final_value_gnf,
                        'reserved_gnf', v_h.amount_gnf,
                        'released_excess_gnf', v_h.amount_gnf - v_capture,
                        'is_sandbox', v_h.is_sandbox),
     now())
  RETURNING * INTO v_tx;

  UPDATE public.wallet_transactions SET status = 'completed', completed_at = now()
   WHERE id = v_h.hold_tx_id AND status = 'pending';

  UPDATE public.mission_financial_holds
     SET state = 'captured', captured_gnf = v_capture,
         resolution_tx_id = v_tx.id, resolved_at = now(), resolved_by = v_caller
   WHERE id = v_h.id;

  RETURN jsonb_build_object('status', 'captured', 'captured_gnf', v_capture,
                            'released_excess_gnf', v_h.amount_gnf - v_capture);
END;
$$;

CREATE OR REPLACE FUNCTION public.driver_mission_hold_freeze(
  p_source_module text,
  p_source_id uuid,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_n int;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT (public.is_god_admin(v_caller)
          OR public.has_admin_role(v_caller, 'finance_admin'::admin_role)
          OR public.has_admin_role(v_caller, 'operations_admin'::admin_role)
          OR public.has_admin_role(v_caller, 'support_admin'::admin_role)) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  UPDATE public.mission_financial_holds
     SET state = 'frozen', reason = p_reason, updated_at = now()
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND state = 'held';
  GET DIAGNOSTICS v_n = ROW_COUNT;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, note)
  VALUES (v_caller, 'wallet', 'mission_hold_freeze', 'mission',
          p_source_module || ':' || p_source_id::text, p_reason);

  RETURN jsonb_build_object('status', 'frozen', 'holds', v_n);
END;
$$;

CREATE OR REPLACE FUNCTION public.driver_collateral_resolve(
  p_source_module text,
  p_source_id uuid,
  p_capture_gnf bigint,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_h public.mission_financial_holds;
  v_capture bigint;
  v_dw public.wallets;
  v_master public.wallets;
  v_tx public.wallet_transactions;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT (public.is_god_admin(v_caller)
          OR public.has_admin_role(v_caller, 'finance_admin'::admin_role)) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) < 5 THEN
    RAISE EXCEPTION 'A documented reason is required';
  END IF;

  SELECT * INTO v_h FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND kind = 'collateral' FOR UPDATE;
  IF v_h.id IS NULL THEN RAISE EXCEPTION 'Collateral hold not found'; END IF;
  IF v_h.state NOT IN ('held','frozen') THEN
    RETURN jsonb_build_object('status', 'already_resolved',
                              'captured_gnf', v_h.captured_gnf);
  END IF;

  v_capture := LEAST(GREATEST(COALESCE(p_capture_gnf, 0), 0), v_h.amount_gnf);

  SELECT * INTO v_dw FROM public.wallets
   WHERE owner_user_id = v_h.driver_user_id AND party_type = 'driver' FOR UPDATE;
  SELECT * INTO v_master FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;

  UPDATE public.wallets
     SET held_gnf = GREATEST(held_gnf - v_h.amount_gnf, 0), updated_at = now()
   WHERE id = v_dw.id;

  IF v_capture > 0 THEN
    UPDATE public.wallets SET balance_gnf = balance_gnf - v_capture, updated_at = now()
     WHERE id = v_dw.id;
    IF v_master.id IS NOT NULL THEN
      UPDATE public.wallets SET balance_gnf = balance_gnf + v_capture, updated_at = now()
       WHERE id = v_master.id;
    END IF;
  END IF;

  INSERT INTO public.wallet_transactions
    (reference, type, status, amount_gnf, from_wallet_id, to_wallet_id,
     related_user_id, related_entity, description, metadata, completed_at)
  VALUES
    (format('mfh-collateral:%s:%s', p_source_module, p_source_id),
     'adjustment', 'completed', v_capture, v_dw.id, v_master.id,
     v_h.driver_user_id, p_source_module || ':' || p_source_id::text,
     'Résolution de caution mission',
     jsonb_build_object('reason', p_reason, 'held_gnf', v_h.amount_gnf,
                        'is_sandbox', v_h.is_sandbox), now())
  RETURNING * INTO v_tx;

  UPDATE public.wallet_transactions SET status = 'completed', completed_at = now()
   WHERE id = v_h.hold_tx_id AND status = 'pending';

  UPDATE public.mission_financial_holds
     SET state = CASE WHEN v_capture > 0 THEN 'captured' ELSE 'released' END,
         captured_gnf = v_capture, resolution_tx_id = v_tx.id,
         reason = p_reason, resolved_at = now(), resolved_by = v_caller
   WHERE id = v_h.id;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id,
                                 before, after, note)
  VALUES (v_caller, 'wallet', 'collateral_resolve', 'mission',
          p_source_module || ':' || p_source_id::text,
          jsonb_build_object('held_gnf', v_h.amount_gnf),
          jsonb_build_object('captured_gnf', v_capture), p_reason);

  RETURN jsonb_build_object('status', 'resolved', 'captured_gnf', v_capture,
                            'released_gnf', v_h.amount_gnf - v_capture);
END;
$$;

-- =====================================================================
-- God Admin policy editor (audited)
-- =====================================================================

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
  p_note text DEFAULT NULL
)
RETURNS public.finance_policies
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_before public.finance_policies;
  v_new public.finance_policies;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.is_god_admin(v_caller) THEN
    RAISE EXCEPTION 'Only a God Admin can change finance policy';
  END IF;
  IF p_effective_from < now() - interval '1 minute' THEN
    RAISE EXCEPTION 'Effective date cannot be in the past';
  END IF;

  SELECT * INTO v_before FROM public.finance_policy_current(p_mission_type);

  INSERT INTO public.finance_policies
    (mission_type, commission_bps, fixed_commission_gnf, min_driver_balance_gnf,
     collateral_mode, collateral_pct_bps, collateral_fixed_gnf,
     collateral_min_gnf, collateral_max_gnf, require_collateral_before_offer,
     effective_from, note, created_by)
  VALUES
    (p_mission_type, p_commission_bps, p_fixed_commission_gnf, p_min_driver_balance_gnf,
     p_collateral_mode, p_collateral_pct_bps, p_collateral_fixed_gnf,
     p_collateral_min_gnf, p_collateral_max_gnf, p_require_collateral_before_offer,
     p_effective_from, p_note, v_caller)
  RETURNING * INTO v_new;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id,
                                 before, after, note)
  VALUES (v_caller, 'pricing', 'finance_policy_set', 'finance_policy', p_mission_type,
          to_jsonb(v_before), to_jsonb(v_new), p_note);

  RETURN v_new;
END;
$$;

-- =====================================================================
-- Flags
-- =====================================================================

INSERT INTO public.feature_flags (key, enabled, description) VALUES
  ('chop_pay_enabled', false,
   'Public Chop Pay surface (balance, top-up, transfers, history). Internal ledger is unaffected when off.'),
  ('om_topup_enabled', true,
   'Orange Money retained as a manual cash-in / top-up rail for Chop Pay and driver operating balances.'),
  ('om_direct_checkout_enabled', false,
   'ARCHIVED: Orange Money as a direct customer checkout method for rides, Repas, Marche and Envoyer. Off = cash + Chop Pay launch model.'),
  ('driver_balance_gate_enabled', false,
   'When on, drivers must hold sufficient operating balance (commission reserve + collateral) to receive and accept missions.')
ON CONFLICT (key) DO NOTHING;