-- ============================================================
-- SLICE 1 — LEDGER PRIMITIVES / POLICY SCHEMA
-- ============================================================

-- ---------- D. Policy schema corrections ----------
ALTER TABLE public.finance_policies
  ADD COLUMN IF NOT EXISTS transaction_fee_bps integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS fee_basis text NOT NULL DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS cash_funding_mode text NOT NULL DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS cash_funding_pct_bps integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS cash_funding_max_gnf bigint,
  ADD COLUMN IF NOT EXISTS cancel_before_dispatch_bps integer NOT NULL DEFAULT 500,
  ADD COLUMN IF NOT EXISTS cancel_after_dispatch_bps integer NOT NULL DEFAULT 1000,
  ADD COLUMN IF NOT EXISTS max_declared_value_gnf bigint;

ALTER TABLE public.finance_policies
  DROP CONSTRAINT IF EXISTS finance_policies_fee_basis_chk,
  DROP CONSTRAINT IF EXISTS finance_policies_fee_bps_chk,
  DROP CONSTRAINT IF EXISTS finance_policies_cashfund_mode_chk,
  DROP CONSTRAINT IF EXISTS finance_policies_cashfund_pct_chk,
  DROP CONSTRAINT IF EXISTS finance_policies_cancel_chk;

ALTER TABLE public.finance_policies
  ADD CONSTRAINT finance_policies_fee_basis_chk CHECK (fee_basis IN ('none','fare','merchandise_subtotal','declared_value','order_total')),
  ADD CONSTRAINT finance_policies_fee_bps_chk CHECK (transaction_fee_bps >= 0 AND transaction_fee_bps <= 2000),
  ADD CONSTRAINT finance_policies_cashfund_mode_chk CHECK (cash_funding_mode IN ('none','merchandise_subtotal')),
  ADD CONSTRAINT finance_policies_cashfund_pct_chk CHECK (cash_funding_pct_bps >= 0 AND cash_funding_pct_bps <= 10000),
  ADD CONSTRAINT finance_policies_cancel_chk CHECK (
    cancel_before_dispatch_bps >= 0 AND cancel_before_dispatch_bps <= 5000
    AND cancel_after_dispatch_bps >= 0 AND cancel_after_dispatch_bps <= 5000);

-- New effective-dated rows (append-only; history is never rewritten)
INSERT INTO public.finance_policies
  (mission_type, commission_bps, fixed_commission_gnf, min_driver_balance_gnf,
   collateral_mode, collateral_pct_bps, collateral_min_gnf, collateral_max_gnf,
   require_collateral_before_offer, transaction_fee_bps, fee_basis,
   cash_funding_mode, cash_funding_pct_bps, cash_funding_max_gnf,
   cancel_before_dispatch_bps, cancel_after_dispatch_bps, max_declared_value_gnf,
   effective_from, note)
VALUES
  ('ride',     1000, 0, 5000, 'none',       0,    0, NULL,    false,   0, 'none',                 'none',                 0, NULL,      500, 1000, NULL,   now(), 'Slice 1 policy freeze: 10% commission, cash/Chop Pay, no fee, 5/10% cancellation'),
  ('bonbonna', 1000, 0, 5000, 'none',       0,    0, NULL,    false,   0, 'none',                 'none',                 0, NULL,      500, 1000, NULL,   now(), 'Slice 1 policy freeze: 10% commission, cash/Chop Pay, no fee, 5/10% cancellation'),
  ('repas',       0, 0, 5000, 'percentage', 5000, 0, 500000,  false, 100, 'merchandise_subtotal', 'merchandise_subtotal', 10000, 500000, 500, 1000, NULL,  now(), 'Slice 1 policy freeze: Chop Pay collateral 50%; CASH order funding 100% of subtotal (unrestricted funds only); 1% fee'),
  ('marche',      0, 0, 5000, 'percentage', 5000, 0, 1000000, false, 100, 'merchandise_subtotal', 'merchandise_subtotal', 10000, 1000000, 500, 1000, NULL, now(), 'Slice 1 policy freeze: Chop Pay collateral 50%; CASH order funding 100% of subtotal (unrestricted funds only); 1% fee'),
  ('envoyer',     0, 0, 5000, 'percentage', 7500, 0, 375000,  false, 100, 'declared_value',       'none',                 0, NULL,      500, 1000, 500000, now(), 'Slice 1 policy freeze: courier collateral 75% of accepted declared value, declared value capped at 500 000 GNF; 1% fee');

-- ---------- A. Restricted promotional balance ----------
CREATE TABLE IF NOT EXISTS public.driver_starter_credit_policies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  amount_gnf bigint NOT NULL DEFAULT 25000 CHECK (amount_gnf >= 0 AND amount_gnf <= 1000000),
  enabled boolean NOT NULL DEFAULT true,
  effective_from timestamptz NOT NULL DEFAULT now(),
  note text,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.driver_starter_credit_policies TO authenticated;
GRANT ALL ON public.driver_starter_credit_policies TO service_role;
ALTER TABLE public.driver_starter_credit_policies ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated read starter credit policy" ON public.driver_starter_credit_policies;
CREATE POLICY "Authenticated read starter credit policy"
  ON public.driver_starter_credit_policies FOR SELECT TO authenticated USING (true);
DROP TRIGGER IF EXISTS trg_dscp_updated_at ON public.driver_starter_credit_policies;
CREATE TRIGGER trg_dscp_updated_at BEFORE UPDATE ON public.driver_starter_credit_policies
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

INSERT INTO public.driver_starter_credit_policies (amount_gnf, enabled, note)
SELECT 25000, true, 'Launch default: 25 000 GNF restricted CHOPCHOP starting credit for newly approved drivers'
WHERE NOT EXISTS (SELECT 1 FROM public.driver_starter_credit_policies);

CREATE TABLE IF NOT EXISTS public.driver_promo_credits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_user_id uuid NOT NULL,
  policy_id uuid REFERENCES public.driver_starter_credit_policies(id),
  identity_key text,
  grant_key text NOT NULL,
  granted_gnf bigint NOT NULL CHECK (granted_gnf >= 0),
  consumed_gnf bigint NOT NULL DEFAULT 0 CHECK (consumed_gnf >= 0),
  reversed_gnf bigint NOT NULL DEFAULT 0 CHECK (reversed_gnf >= 0),
  state text NOT NULL DEFAULT 'active' CHECK (state IN ('active','exhausted','reversed')),
  grant_tx_id uuid,
  reason text,
  granted_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (consumed_gnf + reversed_gnf <= granted_gnf)
);
CREATE UNIQUE INDEX IF NOT EXISTS driver_promo_credits_grant_key ON public.driver_promo_credits (grant_key);
CREATE UNIQUE INDEX IF NOT EXISTS driver_promo_credits_one_active
  ON public.driver_promo_credits (driver_user_id) WHERE state <> 'reversed';
CREATE UNIQUE INDEX IF NOT EXISTS driver_promo_credits_one_identity
  ON public.driver_promo_credits (identity_key) WHERE identity_key IS NOT NULL AND state <> 'reversed';

GRANT SELECT ON public.driver_promo_credits TO authenticated;
GRANT ALL ON public.driver_promo_credits TO service_role;
ALTER TABLE public.driver_promo_credits ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Drivers read own promo credit" ON public.driver_promo_credits;
CREATE POLICY "Drivers read own promo credit"
  ON public.driver_promo_credits FOR SELECT TO authenticated
  USING (driver_user_id = auth.uid());
DROP POLICY IF EXISTS "Finance and god admins read promo credits" ON public.driver_promo_credits;
CREATE POLICY "Finance and god admins read promo credits"
  ON public.driver_promo_credits FOR SELECT TO authenticated
  USING (public.has_admin_role(auth.uid(), 'finance_admin'::admin_role) OR public.is_god_admin(auth.uid()));
DROP TRIGGER IF EXISTS trg_dpc_updated_at ON public.driver_promo_credits;
CREATE TRIGGER trg_dpc_updated_at BEFORE UPDATE ON public.driver_promo_credits
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ---------- C. Source-attributed holds ----------
ALTER TABLE public.mission_financial_holds
  ADD COLUMN IF NOT EXISTS unrestricted_gnf bigint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS promo_gnf bigint NOT NULL DEFAULT 0;

UPDATE public.mission_financial_holds
   SET unrestricted_gnf = amount_gnf
 WHERE unrestricted_gnf = 0 AND promo_gnf = 0 AND amount_gnf > 0;

ALTER TABLE public.mission_financial_holds DROP CONSTRAINT IF EXISTS mfh_source_split_chk;
ALTER TABLE public.mission_financial_holds
  ADD CONSTRAINT mfh_source_split_chk
  CHECK (unrestricted_gnf >= 0 AND promo_gnf >= 0 AND unrestricted_gnf + promo_gnf = amount_gnf);

ALTER TABLE public.mission_financial_holds DROP CONSTRAINT IF EXISTS mfh_kind_chk;
ALTER TABLE public.mission_financial_holds
  ADD CONSTRAINT mfh_kind_chk CHECK (kind IN ('commission','collateral','platform_fee','cash_funding'));

-- ---------- Policy accessor ----------
CREATE OR REPLACE FUNCTION public.starter_credit_policy_current()
RETURNS public.driver_starter_credit_policies
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT * FROM public.driver_starter_credit_policies
   WHERE enabled = true AND effective_from <= now()
   ORDER BY effective_from DESC, created_at DESC
   LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_starter_credit_policy(
  p_amount_gnf bigint,
  p_enabled boolean DEFAULT true,
  p_effective_from timestamptz DEFAULT now(),
  p_note text DEFAULT NULL)
RETURNS public.driver_starter_credit_policies
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_before public.driver_starter_credit_policies;
  v_new public.driver_starter_credit_policies;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.is_god_admin(v_caller) THEN
    RAISE EXCEPTION 'Only a God Admin can change the starter credit policy';
  END IF;
  IF p_effective_from < now() - interval '1 minute' THEN
    RAISE EXCEPTION 'Effective date cannot be in the past';
  END IF;

  SELECT * INTO v_before FROM public.starter_credit_policy_current();

  INSERT INTO public.driver_starter_credit_policies (amount_gnf, enabled, effective_from, note, created_by)
  VALUES (p_amount_gnf, COALESCE(p_enabled, true), p_effective_from, p_note, v_caller)
  RETURNING * INTO v_new;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, before, after, note)
  VALUES (v_caller, 'wallet', 'starter_credit_policy_set', 'starter_credit_policy', v_new.id::text,
          to_jsonb(v_before), to_jsonb(v_new), p_note);

  RETURN v_new;
END;
$$;

-- ---------- Restricted balance derivation ----------
CREATE OR REPLACE FUNCTION public.driver_promo_balance(p_driver uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_remaining bigint := 0;
  v_held bigint := 0;
BEGIN
  SELECT COALESCE(SUM(granted_gnf - consumed_gnf - reversed_gnf), 0)
    INTO v_remaining
    FROM public.driver_promo_credits
   WHERE driver_user_id = p_driver AND state = 'active';

  SELECT COALESCE(SUM(promo_gnf), 0) INTO v_held
    FROM public.mission_financial_holds
   WHERE driver_user_id = p_driver AND state IN ('held','frozen');

  RETURN jsonb_build_object(
    'promo_remaining_gnf', v_remaining,
    'promo_held_gnf', v_held,
    'promo_available_gnf', GREATEST(v_remaining - v_held, 0));
END;
$$;

-- Consume promotional credit FIFO (internal helper)
CREATE OR REPLACE FUNCTION public._promo_consume(p_driver uuid, p_amount bigint)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_left bigint := GREATEST(COALESCE(p_amount, 0), 0);
  v_row public.driver_promo_credits;
  v_take bigint;
BEGIN
  FOR v_row IN
    SELECT * FROM public.driver_promo_credits
     WHERE driver_user_id = p_driver AND state = 'active'
       AND granted_gnf - consumed_gnf - reversed_gnf > 0
     ORDER BY created_at
     FOR UPDATE
  LOOP
    EXIT WHEN v_left <= 0;
    v_take := LEAST(v_left, v_row.granted_gnf - v_row.consumed_gnf - v_row.reversed_gnf);
    UPDATE public.driver_promo_credits
       SET consumed_gnf = consumed_gnf + v_take,
           state = CASE WHEN consumed_gnf + v_take + reversed_gnf >= granted_gnf
                        THEN 'exhausted' ELSE 'active' END,
           updated_at = now()
     WHERE id = v_row.id;
    v_left := v_left - v_take;
  END LOOP;
  RETURN GREATEST(COALESCE(p_amount, 0), 0) - v_left;
END;
$$;

-- Funding waterfall: returns {unrestricted_gnf, promo_gnf}
CREATE OR REPLACE FUNCTION public.driver_funding_allocate(
  p_driver uuid, p_amount bigint, p_kind text)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_w public.wallets;
  v_promo jsonb;
  v_promo_avail bigint;
  v_unrestricted bigint;
  v_amount bigint := GREATEST(COALESCE(p_amount, 0), 0);
  v_p bigint := 0;
  v_u bigint := 0;
BEGIN
  SELECT * INTO v_w FROM public.wallets
   WHERE owner_user_id = p_driver AND party_type = 'driver';

  v_promo := public.driver_promo_balance(p_driver);
  v_promo_avail := (v_promo->>'promo_available_gnf')::bigint;
  v_unrestricted := GREATEST(COALESCE(v_w.balance_gnf, 0) - COALESCE(v_w.held_gnf, 0) - v_promo_avail, 0);

  IF v_amount = 0 THEN
    RETURN jsonb_build_object('unrestricted_gnf', 0, 'promo_gnf', 0, 'ok', true);
  END IF;

  IF p_kind = 'cash_funding' THEN
    -- Restricted promotional credit may NEVER fund merchandise principal.
    IF v_unrestricted < v_amount THEN
      RETURN jsonb_build_object('unrestricted_gnf', 0, 'promo_gnf', 0, 'ok', false,
                                'reason', 'CASH_FUNDING_REQUIRES_UNRESTRICTED');
    END IF;
    RETURN jsonb_build_object('unrestricted_gnf', v_amount, 'promo_gnf', 0, 'ok', true);

  ELSIF p_kind IN ('commission','platform_fee') THEN
    -- Promotional credit first for CHOPCHOP commission and fees.
    v_p := LEAST(v_promo_avail, v_amount);
    v_u := v_amount - v_p;

  ELSE -- collateral: proportional, traceable allocation
    IF v_promo_avail + v_unrestricted > 0 THEN
      v_p := LEAST(v_promo_avail, (v_amount * v_promo_avail) / (v_promo_avail + v_unrestricted));
    END IF;
    v_u := v_amount - v_p;
    IF v_u > v_unrestricted THEN
      v_p := LEAST(v_promo_avail, v_amount - v_unrestricted);
      v_u := v_amount - v_p;
    END IF;
  END IF;

  IF v_u > v_unrestricted OR v_p > v_promo_avail THEN
    RETURN jsonb_build_object('unrestricted_gnf', 0, 'promo_gnf', 0, 'ok', false,
                              'reason', 'INSUFFICIENT_DRIVER_BALANCE');
  END IF;

  RETURN jsonb_build_object('unrestricted_gnf', v_u, 'promo_gnf', v_p, 'ok', true);
END;
$$;

-- ---------- B. Idempotent starter grant ----------
CREATE OR REPLACE FUNCTION public.driver_starter_credit_grant(p_driver uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_driver uuid := COALESCE(p_driver, auth.uid());
  v_is_admin boolean;
  v_policy public.driver_starter_credit_policies;
  v_dp public.driver_profiles;
  v_flag boolean;
  v_identity text;
  v_key text;
  v_wallet public.wallets;
  v_master public.wallets;
  v_tx public.wallet_transactions;
  v_row public.driver_promo_credits;
  v_dupes int;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  v_is_admin := public.is_god_admin(v_caller)
                OR public.has_admin_role(v_caller, 'finance_admin'::admin_role);
  IF v_driver <> v_caller AND NOT v_is_admin THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  SELECT enabled INTO v_flag FROM public.feature_flags WHERE key = 'driver_starter_credit_enabled';
  IF NOT COALESCE(v_flag, false) THEN
    RETURN jsonb_build_object('status', 'disabled', 'granted_gnf', 0);
  END IF;

  SELECT * INTO v_policy FROM public.starter_credit_policy_current();
  IF v_policy.id IS NULL OR v_policy.amount_gnf <= 0 THEN
    RETURN jsonb_build_object('status', 'no_policy', 'granted_gnf', 0);
  END IF;

  -- Eligibility: approved driver, identity/vehicle evidence present, not banned/frozen.
  SELECT * INTO v_dp FROM public.driver_profiles WHERE user_id = v_driver;
  IF v_dp.user_id IS NULL OR v_dp.status <> 'approved' THEN
    RETURN jsonb_build_object('status', 'not_eligible', 'reason', 'driver_not_approved', 'granted_gnf', 0);
  END IF;
  IF v_dp.id_doc_url IS NULL OR v_dp.vehicle_photo_url IS NULL THEN
    RETURN jsonb_build_object('status', 'not_eligible', 'reason', 'identity_or_vehicle_incomplete', 'granted_gnf', 0);
  END IF;
  IF public.is_user_banned(v_driver) OR public.is_user_frozen(v_driver) THEN
    RETURN jsonb_build_object('status', 'not_eligible', 'reason', 'account_restricted', 'granted_gnf', 0);
  END IF;

  -- Identity linkage: normalized phone. Duplicates route to review, never auto-grant.
  SELECT public._normalize_guinea_phone(phone) INTO v_identity
    FROM public.profiles WHERE user_id = v_driver;

  IF v_identity IS NOT NULL THEN
    SELECT count(*) INTO v_dupes FROM public.profiles
     WHERE public._normalize_guinea_phone(phone) = v_identity AND user_id <> v_driver;
    IF v_dupes > 0 THEN
      INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
      VALUES (v_caller, 'wallet', 'starter_credit_denied', 'driver', v_driver::text,
              jsonb_build_object('reason', 'duplicate_identity', 'identity_key', v_identity),
              'Duplicate identity signal — routed to review');
      RETURN jsonb_build_object('status', 'needs_review', 'reason', 'duplicate_identity', 'granted_gnf', 0);
    END IF;
  END IF;

  v_key := 'starter:' || v_driver::text || ':' || v_policy.id::text;

  SELECT * INTO v_row FROM public.driver_promo_credits
   WHERE driver_user_id = v_driver AND state <> 'reversed' LIMIT 1;
  IF v_row.id IS NOT NULL THEN
    RETURN jsonb_build_object('status', 'already_granted', 'granted_gnf', v_row.granted_gnf,
                              'credit_id', v_row.id);
  END IF;

  -- Wallets
  INSERT INTO public.wallets (owner_user_id, party_type) VALUES (v_driver, 'driver')
  ON CONFLICT (owner_user_id, party_type) DO NOTHING;
  SELECT * INTO v_wallet FROM public.wallets
   WHERE owner_user_id = v_driver AND party_type = 'driver' FOR UPDATE;
  IF v_wallet.status <> 'active' THEN
    RETURN jsonb_build_object('status', 'not_eligible', 'reason', 'wallet_not_active', 'granted_gnf', 0);
  END IF;
  SELECT * INTO v_master FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;

  INSERT INTO public.driver_promo_credits
    (driver_user_id, policy_id, identity_key, grant_key, granted_gnf, granted_by, reason)
  VALUES (v_driver, v_policy.id, v_identity, v_key, v_policy.amount_gnf, v_caller,
          'Bonus de démarrage CHOPCHOP')
  ON CONFLICT (grant_key) DO NOTHING
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    RETURN jsonb_build_object('status', 'already_granted', 'granted_gnf', 0);
  END IF;

  -- Promotional expense: master -> driver restricted credit. Not customer cash-in,
  -- not driver earnings. Master wallet may go negative (allowed by constraint).
  UPDATE public.wallets SET balance_gnf = balance_gnf + v_policy.amount_gnf, updated_at = now()
   WHERE id = v_wallet.id;
  IF v_master.id IS NOT NULL THEN
    UPDATE public.wallets SET balance_gnf = balance_gnf - v_policy.amount_gnf, updated_at = now()
     WHERE id = v_master.id;
  END IF;

  INSERT INTO public.wallet_transactions
    (reference, type, status, amount_gnf, from_wallet_id, to_wallet_id,
     related_user_id, related_entity, description, metadata, completed_at)
  VALUES (v_key, 'adjustment', 'completed', v_policy.amount_gnf, v_master.id, v_wallet.id,
          v_driver, 'promo:starter_credit', 'Bonus de démarrage CHOPCHOP (restreint)',
          jsonb_build_object('source_module', 'promo', 'restricted', true,
                             'accounting', 'promotional_expense',
                             'policy_id', v_policy.id, 'credit_id', v_row.id), now())
  RETURNING * INTO v_tx;

  UPDATE public.driver_promo_credits SET grant_tx_id = v_tx.id, updated_at = now()
   WHERE id = v_row.id;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (v_caller, 'wallet', 'starter_credit_granted', 'driver', v_driver::text,
          jsonb_build_object('amount_gnf', v_policy.amount_gnf, 'policy_id', v_policy.id,
                             'credit_id', v_row.id),
          'Restricted starting credit — not withdrawable, not transferable');

  RETURN jsonb_build_object('status', 'granted', 'granted_gnf', v_policy.amount_gnf,
                            'credit_id', v_row.id);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_reverse_starter_credit(
  p_driver uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_row public.driver_promo_credits;
  v_open int;
  v_reversible bigint;
  v_wallet public.wallets;
  v_master public.wallets;
  v_take bigint;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.is_god_admin(v_caller) THEN
    RAISE EXCEPTION 'Only a God Admin can reverse a promotional credit';
  END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) < 5 THEN
    RAISE EXCEPTION 'A documented reason is required';
  END IF;

  SELECT * INTO v_row FROM public.driver_promo_credits
   WHERE driver_user_id = p_driver AND state <> 'reversed' FOR UPDATE;
  IF v_row.id IS NULL THEN
    RETURN jsonb_build_object('status', 'nothing_to_reverse');
  END IF;

  SELECT count(*) INTO v_open FROM public.mission_financial_holds
   WHERE driver_user_id = p_driver AND state IN ('held','frozen') AND promo_gnf > 0;
  IF v_open > 0 THEN
    RETURN jsonb_build_object('status', 'blocked', 'reason', 'outstanding_promo_holds',
                              'open_holds', v_open);
  END IF;

  v_reversible := v_row.granted_gnf - v_row.consumed_gnf - v_row.reversed_gnf;

  SELECT * INTO v_wallet FROM public.wallets
   WHERE owner_user_id = p_driver AND party_type = 'driver' FOR UPDATE;
  SELECT * INTO v_master FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;

  -- Never negative, never confiscates unrelated earnings beyond the unused grant.
  v_take := LEAST(v_reversible, GREATEST(COALESCE(v_wallet.balance_gnf,0) - COALESCE(v_wallet.held_gnf,0), 0));

  IF v_take > 0 THEN
    UPDATE public.wallets SET balance_gnf = balance_gnf - v_take, updated_at = now()
     WHERE id = v_wallet.id;
    IF v_master.id IS NOT NULL THEN
      UPDATE public.wallets SET balance_gnf = balance_gnf + v_take, updated_at = now()
       WHERE id = v_master.id;
    END IF;
    INSERT INTO public.wallet_transactions
      (reference, type, status, amount_gnf, from_wallet_id, to_wallet_id, related_user_id,
       related_entity, description, metadata, completed_at)
    VALUES ('promo-reversal:' || v_row.id::text, 'adjustment', 'completed', v_take,
            v_wallet.id, v_master.id, p_driver, 'promo:starter_credit',
            'Annulation auditée du bonus de démarrage',
            jsonb_build_object('source_module','promo','reason',p_reason,'credit_id',v_row.id), now());
  END IF;

  UPDATE public.driver_promo_credits
     SET reversed_gnf = reversed_gnf + v_take, state = 'reversed',
         reason = p_reason, updated_at = now()
   WHERE id = v_row.id;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, before, after, note)
  VALUES (v_caller, 'wallet', 'starter_credit_reversed', 'driver', p_driver::text,
          to_jsonb(v_row), jsonb_build_object('reversed_gnf', v_take), p_reason);

  RETURN jsonb_build_object('status', 'reversed', 'reversed_gnf', v_take,
                            'consumed_gnf', v_row.consumed_gnf);
END;
$$;

-- ---------- Balance summary with restricted breakdown ----------
CREATE OR REPLACE FUNCTION public.driver_balance_summary(p_driver uuid DEFAULT NULL::uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_target uuid := COALESCE(p_driver, auth.uid());
  v_w public.wallets;
  v_collateral bigint := 0;
  v_commission bigint := 0;
  v_fee bigint := 0;
  v_cash bigint := 0;
  v_promo jsonb;
  v_available bigint;
  v_promo_avail bigint;
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
         COALESCE(SUM(amount_gnf) FILTER (WHERE kind = 'commission'), 0),
         COALESCE(SUM(amount_gnf) FILTER (WHERE kind = 'platform_fee'), 0),
         COALESCE(SUM(amount_gnf) FILTER (WHERE kind = 'cash_funding'), 0)
    INTO v_collateral, v_commission, v_fee, v_cash
    FROM public.mission_financial_holds
   WHERE driver_user_id = v_target AND state IN ('held','frozen');

  v_promo := public.driver_promo_balance(v_target);
  v_promo_avail := (v_promo->>'promo_available_gnf')::bigint;
  v_available := GREATEST(COALESCE(v_w.balance_gnf, 0) - COALESCE(v_w.held_gnf, 0), 0);

  RETURN jsonb_build_object(
    'wallet_id', v_w.id,
    'balance_gnf', COALESCE(v_w.balance_gnf, 0),
    'held_gnf', COALESCE(v_w.held_gnf, 0),
    'available_gnf', v_available,
    'promo_remaining_gnf', (v_promo->>'promo_remaining_gnf')::bigint,
    'promo_held_gnf', (v_promo->>'promo_held_gnf')::bigint,
    'promo_available_gnf', v_promo_avail,
    'unrestricted_available_gnf', GREATEST(v_available - v_promo_avail, 0),
    'withdrawable_gnf', GREATEST(v_available - v_promo_avail, 0),
    'collateral_held_gnf', v_collateral,
    'commission_held_gnf', v_commission,
    'platform_fee_held_gnf', v_fee,
    'cash_funding_held_gnf', v_cash,
    'status', COALESCE(v_w.status::text, 'active'));
END;
$$;

-- ---------- Requirement with fee / cash funding / cancellation ----------
CREATE OR REPLACE FUNCTION public.finance_mission_requirement(
  p_mission_type text, p_value_gnf bigint DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_p public.finance_policies;
  v_commission bigint := 0;
  v_collateral bigint := 0;
  v_fee bigint := 0;
  v_cash bigint := 0;
  v_value bigint := GREATEST(COALESCE(p_value_gnf, 0), 0);
  v_capped boolean := false;
BEGIN
  SELECT * INTO v_p FROM public.finance_policy_current(p_mission_type);
  IF v_p.id IS NULL THEN
    RETURN jsonb_build_object(
      'policy_id', NULL, 'mission_type', p_mission_type,
      'commission_gnf', 0, 'collateral_gnf', 0, 'platform_fee_gnf', 0,
      'cash_funding_gnf', 0, 'min_balance_gnf', 0, 'required_hold_gnf', 0,
      'required_available_gnf', 0, 'has_policy', false);
  END IF;

  IF v_p.max_declared_value_gnf IS NOT NULL AND v_value > v_p.max_declared_value_gnf THEN
    v_capped := true;
  END IF;

  v_commission := (v_value * v_p.commission_bps) / 10000 + v_p.fixed_commission_gnf;
  v_fee := CASE WHEN v_p.fee_basis = 'none' THEN 0
                ELSE (v_value * v_p.transaction_fee_bps) / 10000 END;

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

  IF v_p.cash_funding_mode = 'merchandise_subtotal' THEN
    v_cash := (v_value * v_p.cash_funding_pct_bps) / 10000;
    IF v_p.cash_funding_max_gnf IS NOT NULL THEN
      v_cash := LEAST(v_cash, v_p.cash_funding_max_gnf);
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'policy_id', v_p.id,
    'mission_type', p_mission_type,
    'basis_value_gnf', v_value,
    'commission_gnf', v_commission,
    'collateral_gnf', v_collateral,
    'platform_fee_gnf', v_fee,
    'cash_funding_gnf', v_cash,
    'fee_basis', v_p.fee_basis,
    'transaction_fee_bps', v_p.transaction_fee_bps,
    'cancel_before_dispatch_bps', v_p.cancel_before_dispatch_bps,
    'cancel_after_dispatch_bps', v_p.cancel_after_dispatch_bps,
    'max_declared_value_gnf', v_p.max_declared_value_gnf,
    'declared_value_exceeds_cap', v_capped,
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
      'transaction_fee_bps', v_p.transaction_fee_bps,
      'fee_basis', v_p.fee_basis,
      'cash_funding_mode', v_p.cash_funding_mode,
      'cash_funding_pct_bps', v_p.cash_funding_pct_bps,
      'cancel_before_dispatch_bps', v_p.cancel_before_dispatch_bps,
      'cancel_after_dispatch_bps', v_p.cancel_after_dispatch_bps,
      'max_declared_value_gnf', v_p.max_declared_value_gnf,
      'min_driver_balance_gnf', v_p.min_driver_balance_gnf,
      'effective_from', v_p.effective_from));
END;
$$;

-- ---------- Source-attributed hold placement ----------
CREATE OR REPLACE FUNCTION public.driver_mission_hold_place(
  p_mission_type text, p_source_module text, p_source_id uuid,
  p_value_gnf bigint DEFAULT 0, p_driver uuid DEFAULT NULL::uuid,
  p_is_sandbox boolean DEFAULT false, p_kinds text[] DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_driver uuid := COALESCE(p_driver, auth.uid());
  v_req jsonb;
  v_wallet public.wallets;
  v_avail bigint;
  v_total bigint := 0;
  v_existing int;
  v_kind text;
  v_amount bigint;
  v_alloc jsonb;
  v_tx public.wallet_transactions;
  v_ids jsonb := '[]'::jsonb;
  v_kinds text[] := COALESCE(p_kinds, ARRAY['commission','collateral']);
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF v_driver <> v_caller AND NOT public.is_god_admin(v_caller)
     AND NOT public.has_admin_role(v_caller, 'finance_admin'::admin_role) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  SELECT count(*) INTO v_existing FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id;
  IF v_existing > 0 THEN
    RETURN jsonb_build_object('status', 'already_held', 'source_id', p_source_id);
  END IF;

  v_req := public.finance_mission_requirement(p_mission_type, p_value_gnf);

  INSERT INTO public.wallets (owner_user_id, party_type) VALUES (v_driver, 'driver')
  ON CONFLICT (owner_user_id, party_type) DO NOTHING;
  SELECT * INTO v_wallet FROM public.wallets
   WHERE owner_user_id = v_driver AND party_type = 'driver' FOR UPDATE;
  IF v_wallet.status <> 'active' THEN RAISE EXCEPTION 'Wallet not active'; END IF;

  v_avail := GREATEST(v_wallet.balance_gnf - v_wallet.held_gnf, 0);
  IF v_avail < (v_req->>'required_available_gnf')::bigint THEN
    RAISE EXCEPTION 'INSUFFICIENT_DRIVER_BALANCE'
      USING DETAIL = format('required=%s available=%s',
        (v_req->>'required_available_gnf'), v_avail);
  END IF;

  FOREACH v_kind IN ARRAY v_kinds LOOP
    v_amount := CASE v_kind
      WHEN 'commission'   THEN (v_req->>'commission_gnf')::bigint
      WHEN 'collateral'   THEN (v_req->>'collateral_gnf')::bigint
      WHEN 'platform_fee' THEN (v_req->>'platform_fee_gnf')::bigint
      WHEN 'cash_funding' THEN (v_req->>'cash_funding_gnf')::bigint
      ELSE 0 END;
    CONTINUE WHEN COALESCE(v_amount, 0) <= 0;

    v_alloc := public.driver_funding_allocate(v_driver, v_amount, v_kind);
    IF NOT (v_alloc->>'ok')::boolean THEN
      RAISE EXCEPTION '%', COALESCE(v_alloc->>'reason', 'INSUFFICIENT_DRIVER_BALANCE');
    END IF;

    INSERT INTO public.wallet_transactions
      (reference, type, status, amount_gnf, from_wallet_id, related_user_id,
       related_entity, description, metadata)
    VALUES
      (format('mfh:%s:%s:%s', p_source_module, p_source_id, v_kind),
       'hold', 'pending', v_amount, v_wallet.id, v_driver,
       p_source_module || ':' || p_source_id::text,
       CASE v_kind
         WHEN 'commission'   THEN 'Réserve de commission mission'
         WHEN 'collateral'   THEN 'Caution mission'
         WHEN 'platform_fee' THEN 'Frais de service CHOPCHOP'
         ELSE 'Avance marchandise (commande espèces)' END,
       jsonb_build_object('mission_type', p_mission_type, 'kind', v_kind,
                          'is_sandbox', p_is_sandbox,
                          'unrestricted_gnf', (v_alloc->>'unrestricted_gnf')::bigint,
                          'promo_gnf', (v_alloc->>'promo_gnf')::bigint))
    RETURNING * INTO v_tx;

    UPDATE public.wallets SET held_gnf = held_gnf + v_amount, updated_at = now()
     WHERE id = v_wallet.id;

    INSERT INTO public.mission_financial_holds
      (driver_user_id, mission_type, source_module, source_id, kind,
       amount_gnf, unrestricted_gnf, promo_gnf, hold_tx_id, policy_id,
       policy_snapshot, basis_value_gnf, is_sandbox)
    VALUES
      (v_driver, p_mission_type, p_source_module, p_source_id, v_kind,
       v_amount, (v_alloc->>'unrestricted_gnf')::bigint, (v_alloc->>'promo_gnf')::bigint,
       v_tx.id, (v_req->>'policy_id')::uuid,
       COALESCE(v_req->'policy_snapshot', '{}'::jsonb),
       GREATEST(COALESCE(p_value_gnf, 0), 0), p_is_sandbox);

    v_total := v_total + v_amount;
    v_ids := v_ids || jsonb_build_object('kind', v_kind, 'amount_gnf', v_amount,
                                         'unrestricted_gnf', (v_alloc->>'unrestricted_gnf')::bigint,
                                         'promo_gnf', (v_alloc->>'promo_gnf')::bigint);
  END LOOP;

  RETURN jsonb_build_object('status', 'held', 'total_gnf', v_total, 'holds', v_ids);
END;
$$;

-- ---------- Capture consumes the recorded source allocation ----------
CREATE OR REPLACE FUNCTION public.driver_mission_commission_capture(
  p_source_module text, p_source_id uuid, p_final_value_gnf bigint)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_h public.mission_financial_holds;
  v_snap jsonb;
  v_due bigint;
  v_capture bigint;
  v_promo_part bigint := 0;
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
    RETURN jsonb_build_object('status', 'already_resolved', 'captured_gnf', v_h.captured_gnf);
  END IF;

  v_snap := v_h.policy_snapshot;
  v_due := (GREATEST(COALESCE(p_final_value_gnf, 0), 0)
            * COALESCE((v_snap->>'commission_bps')::int, 0)) / 10000
           + COALESCE((v_snap->>'fixed_commission_gnf')::bigint, 0);
  v_capture := LEAST(v_due, v_h.amount_gnf);

  IF v_h.amount_gnf > 0 AND v_h.promo_gnf > 0 THEN
    v_promo_part := LEAST(v_h.promo_gnf, (v_capture * v_h.promo_gnf) / v_h.amount_gnf);
  END IF;

  SELECT * INTO v_driver_wallet FROM public.wallets
   WHERE owner_user_id = v_h.driver_user_id AND party_type = 'driver' FOR UPDATE;
  SELECT * INTO v_master FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;

  UPDATE public.wallets
     SET held_gnf = GREATEST(held_gnf - v_h.amount_gnf, 0), updated_at = now()
   WHERE id = v_driver_wallet.id;

  IF v_capture > 0 THEN
    UPDATE public.wallets SET balance_gnf = balance_gnf - v_capture, updated_at = now()
     WHERE id = v_driver_wallet.id;
    IF v_master.id IS NOT NULL THEN
      UPDATE public.wallets SET balance_gnf = balance_gnf + v_capture, updated_at = now()
       WHERE id = v_master.id;
    END IF;
    IF v_promo_part > 0 THEN
      PERFORM public._promo_consume(v_h.driver_user_id, v_promo_part);
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
                        'promo_consumed_gnf', v_promo_part,
                        'unrestricted_consumed_gnf', v_capture - v_promo_part,
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
                            'promo_consumed_gnf', v_promo_part,
                            'released_excess_gnf', v_h.amount_gnf - v_capture);
END;
$$;

-- Collateral resolve: consume promotional part of the capture, release the rest
CREATE OR REPLACE FUNCTION public.driver_collateral_resolve(
  p_source_module text, p_source_id uuid, p_capture_gnf bigint, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_h public.mission_financial_holds;
  v_capture bigint;
  v_promo_part bigint := 0;
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
    RETURN jsonb_build_object('status', 'already_resolved', 'captured_gnf', v_h.captured_gnf);
  END IF;

  v_capture := LEAST(GREATEST(COALESCE(p_capture_gnf, 0), 0), v_h.amount_gnf);
  IF v_h.amount_gnf > 0 AND v_h.promo_gnf > 0 THEN
    v_promo_part := LEAST(v_h.promo_gnf, (v_capture * v_h.promo_gnf) / v_h.amount_gnf);
  END IF;

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
    IF v_promo_part > 0 THEN
      PERFORM public._promo_consume(v_h.driver_user_id, v_promo_part);
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
                        'promo_consumed_gnf', v_promo_part,
                        'unrestricted_consumed_gnf', v_capture - v_promo_part,
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
          jsonb_build_object('held_gnf', v_h.amount_gnf, 'promo_gnf', v_h.promo_gnf),
          jsonb_build_object('captured_gnf', v_capture, 'promo_consumed_gnf', v_promo_part),
          p_reason);

  RETURN jsonb_build_object('status', 'resolved', 'captured_gnf', v_capture,
                            'promo_consumed_gnf', v_promo_part,
                            'released_gnf', v_h.amount_gnf - v_capture);
END;
$$;

-- ---------- Cash-out excludes restricted promotional funds ----------
CREATE OR REPLACE FUNCTION public.driver_cashout_create_request(
  p_amount_gnf bigint, p_payout_phone text, p_driver_note text DEFAULT NULL::text)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_wallet public.wallets;
  v_pending_total bigint;
  v_available bigint;
  v_promo_avail bigint;
  v_id uuid;
  v_phone text := trim(coalesce(p_payout_phone,''));
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF p_amount_gnf IS NULL OR p_amount_gnf <= 0 THEN RAISE EXCEPTION 'invalid_amount'; END IF;
  IF p_amount_gnf % 5000 <> 0 THEN RAISE EXCEPTION 'amount_must_be_multiple_of_5000'; END IF;
  IF length(v_phone) < 8 THEN RAISE EXCEPTION 'invalid_payout_phone'; END IF;

  SELECT * INTO v_wallet FROM public.wallets
   WHERE owner_user_id = v_uid AND party_type = 'driver' FOR UPDATE;
  IF v_wallet.id IS NULL THEN RAISE EXCEPTION 'driver_wallet_not_found'; END IF;

  v_promo_avail := (public.driver_promo_balance(v_uid)->>'promo_available_gnf')::bigint;
  -- Restricted promotional credit is never withdrawable.
  v_available := GREATEST(0, v_wallet.balance_gnf - v_wallet.held_gnf - v_promo_avail);

  SELECT COALESCE(SUM(amount_gnf), 0) INTO v_pending_total
    FROM public.driver_cashout_requests
   WHERE driver_user_id = v_uid AND status IN ('pending','approved');

  IF (v_pending_total + p_amount_gnf) > v_available THEN
    RAISE EXCEPTION 'insufficient_available_balance';
  END IF;

  INSERT INTO public.driver_cashout_requests
    (driver_user_id, wallet_id, amount_gnf, payout_phone, driver_note)
  VALUES (v_uid, v_wallet.id, p_amount_gnf, v_phone,
          NULLIF(trim(coalesce(p_driver_note,'')),''))
  RETURNING id INTO v_id;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
  VALUES (v_uid, 'wallet', 'driver_cashout_requested', 'driver_cashout_request', v_id::text,
          jsonb_build_object('amount_gnf', p_amount_gnf, 'payout_phone', v_phone,
                             'promo_excluded_gnf', v_promo_avail));
  RETURN v_id;
END;
$$;

-- ---------- Treasury separation ----------
CREATE OR REPLACE FUNCTION public.admin_promotional_credit_treasury()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_outstanding bigint := 0;
  v_consumed bigint := 0;
  v_reversed bigint := 0;
  v_granted bigint := 0;
  v_driver_total bigint := 0;
  v_grants int := 0;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT (public.is_god_admin(v_caller)
          OR public.has_admin_role(v_caller, 'finance_admin'::admin_role)) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  SELECT COALESCE(SUM(granted_gnf),0), COALESCE(SUM(consumed_gnf),0),
         COALESCE(SUM(reversed_gnf),0), count(*),
         COALESCE(SUM(granted_gnf - consumed_gnf - reversed_gnf) FILTER (WHERE state = 'active'), 0)
    INTO v_granted, v_consumed, v_reversed, v_grants, v_outstanding
    FROM public.driver_promo_credits;

  SELECT COALESCE(SUM(balance_gnf), 0) INTO v_driver_total
    FROM public.wallets WHERE party_type = 'driver';

  RETURN jsonb_build_object(
    'grants_count', v_grants,
    'granted_total_gnf', v_granted,
    'consumed_total_gnf', v_consumed,
    'reversed_total_gnf', v_reversed,
    'outstanding_promotional_credit_gnf', v_outstanding,
    'driver_wallet_total_gnf', v_driver_total,
    'unrestricted_driver_liability_gnf', GREATEST(v_driver_total - v_outstanding, 0),
    'note', 'Outstanding promotional credit is a platform-funded restricted expense, never revenue.');
END;
$$;

-- ---------- Grants ----------
REVOKE ALL ON FUNCTION public._promo_consume(uuid, bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.driver_funding_allocate(uuid, bigint, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.driver_promo_balance(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.starter_credit_policy_current() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_set_starter_credit_policy(bigint, boolean, timestamptz, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.driver_starter_credit_grant(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_reverse_starter_credit(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_promotional_credit_treasury() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.driver_mission_hold_place(text, text, uuid, bigint, uuid, boolean, text[]) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.driver_promo_balance(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.driver_funding_allocate(uuid, bigint, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.starter_credit_policy_current() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_starter_credit_policy(bigint, boolean, timestamptz, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.driver_starter_credit_grant(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reverse_starter_credit(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_promotional_credit_treasury() TO authenticated;
GRANT EXECUTE ON FUNCTION public.driver_mission_hold_place(text, text, uuid, bigint, uuid, boolean, text[]) TO authenticated;

-- ---------- Granular flags, all OFF ----------
INSERT INTO public.feature_flags (key, enabled, description) VALUES
  ('driver_starter_credit_enabled', false, 'Grant the restricted 25 000 GNF CHOPCHOP starting credit to newly approved drivers'),
  ('cash_order_funding_enabled', false, 'Repas/Marché cash-order courier merchandise funding (unrestricted funds only)'),
  ('chop_pay_checkout_enabled', false, 'Chop Pay as a customer checkout rail'),
  ('chop_pay_p2p_enabled', false, 'Chop Pay person-to-person transfers'),
  ('driver_cashout_enabled', false, 'Driver cash-out / payout infrastructure'),
  ('merchant_om_settlement_enabled', false, 'Outbound Orange Money merchant settlement')
ON CONFLICT (key) DO NOTHING;