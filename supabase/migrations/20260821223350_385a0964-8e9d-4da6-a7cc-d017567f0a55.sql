-- ============================================================
-- NODE 5 · FINAL FINANCE-LAW REMEDIATION
-- Dormant closed-account liability.
-- Law: a closed account with a positive balance becomes a dormant
-- closed-account liability. The balance remains owed to the original
-- canonical UUID until a lawful, evidenced payout/recovery rail settles it.
-- Closure removes access and present authority; it does not extinguish debt.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.dormant_closed_account_liabilities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  wallet_id uuid NOT NULL REFERENCES public.wallets(id) ON DELETE RESTRICT,
  party_type public.party_type NOT NULL,
  amount_gnf bigint NOT NULL CHECK (amount_gnf > 0),
  currency text NOT NULL DEFAULT 'GNF',
  state text NOT NULL DEFAULT 'dormant' CHECK (state IN ('dormant','settled')),
  classification_reason text,
  classified_at timestamptz NOT NULL DEFAULT now(),
  settlement_evidence_ref text,
  settled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT dcal_wallet_unique UNIQUE (wallet_id),
  CONSTRAINT dcal_settled_requires_evidence CHECK (
    state = 'dormant'
    OR (settlement_evidence_ref IS NOT NULL AND settled_at IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS dcal_user_idx  ON public.dormant_closed_account_liabilities(user_id);
CREATE INDEX IF NOT EXISTS dcal_state_idx ON public.dormant_closed_account_liabilities(state);

-- Staff read only. No customer/anon surface: this is finance provenance.
GRANT SELECT ON public.dormant_closed_account_liabilities TO authenticated;
GRANT ALL    ON public.dormant_closed_account_liabilities TO service_role;

ALTER TABLE public.dormant_closed_account_liabilities ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS dcal_staff_read ON public.dormant_closed_account_liabilities;
CREATE POLICY dcal_staff_read ON public.dormant_closed_account_liabilities
  FOR SELECT TO authenticated
  USING (public._is_ops_or_god_admin(auth.uid())
         OR public.has_role(auth.uid(), 'finance_admin'));

-- ---------- immutability + fail-closed settlement gate ----------
CREATE OR REPLACE FUNCTION public._dcal_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_rail boolean;
BEGIN
  IF NEW.user_id IS DISTINCT FROM OLD.user_id
     OR NEW.wallet_id IS DISTINCT FROM OLD.wallet_id
     OR NEW.amount_gnf IS DISTINCT FROM OLD.amount_gnf
     OR NEW.currency IS DISTINCT FROM OLD.currency
     OR NEW.classified_at IS DISTINCT FROM OLD.classified_at THEN
    RAISE EXCEPTION 'DORMANT_LIABILITY_IMMUTABLE' USING ERRCODE='P0001';
  END IF;

  IF OLD.state = 'settled' AND NEW.state <> 'settled' THEN
    RAISE EXCEPTION 'DORMANT_LIABILITY_SETTLEMENT_IRREVERSIBLE' USING ERRCODE='P0001';
  END IF;

  IF NEW.state = 'settled' AND OLD.state = 'dormant' THEN
    SELECT COALESCE(bool_or(enabled), false) INTO v_rail
      FROM public.feature_flags
     WHERE key = 'dormant_liability_settlement_enabled';
    IF v_rail IS NOT TRUE THEN
      RAISE EXCEPTION 'NO_LAWFUL_SETTLEMENT_RAIL' USING ERRCODE='P0001';
    END IF;
    IF COALESCE(NEW.settlement_evidence_ref,'') = '' THEN
      RAISE EXCEPTION 'SETTLEMENT_EVIDENCE_REQUIRED' USING ERRCODE='P0001';
    END IF;
    NEW.settled_at := COALESCE(NEW.settled_at, now());
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_dcal_guard ON public.dormant_closed_account_liabilities;
CREATE TRIGGER trg_dcal_guard
  BEFORE UPDATE ON public.dormant_closed_account_liabilities
  FOR EACH ROW EXECUTE FUNCTION public._dcal_guard();

-- The settlement rail is documented but NOT active.
INSERT INTO public.feature_flags(key, enabled, description)
VALUES ('dormant_liability_settlement_enabled', false,
        'Lawful, evidenced payout/recovery rail for dormant closed-account liabilities. OFF: no settlement path exists yet.')
ON CONFLICT (key) DO NOTHING;

-- ---------- classification primitive (internal only) ----------
CREATE OR REPLACE FUNCTION public._dormant_liability_classify(_user uuid, _reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_n int := 0; v_total bigint := 0; w record;
BEGIN
  IF _user IS NULL THEN RAISE EXCEPTION 'TARGET_REQUIRED'; END IF;

  FOR w IN
    SELECT id, party_type, balance_gnf, held_gnf, currency, status
      FROM public.wallets
     WHERE owner_user_id = _user AND COALESCE(balance_gnf,0) > 0
     FOR UPDATE
  LOOP
    -- funds are preserved exactly where they are; only classified + immobilised
    INSERT INTO public.dormant_closed_account_liabilities
      (user_id, wallet_id, party_type, amount_gnf, currency, classification_reason)
    VALUES (_user, w.id, w.party_type, w.balance_gnf, COALESCE(w.currency,'GNF'),
            COALESCE(_reason,'account_closure'))
    ON CONFLICT (wallet_id) DO NOTHING;

    UPDATE public.wallets
       SET status = 'frozen'::public.wallet_status, updated_at = now()
     WHERE id = w.id AND status <> 'frozen'::public.wallet_status;

    v_n := v_n + 1;
    v_total := v_total + w.balance_gnf;
  END LOOP;

  RETURN jsonb_build_object('wallets_classified', v_n, 'amount_gnf', v_total);
END $$;

REVOKE ALL ON FUNCTION public._dormant_liability_classify(uuid,text) FROM PUBLIC, anon, authenticated;

-- ---------- staff read surface ----------
CREATE OR REPLACE FUNCTION public.admin_dormant_liabilities()
RETURNS TABLE(user_id uuid, wallet_id uuid, party_type public.party_type,
              amount_gnf bigint, currency text, state text,
              classified_at timestamptz, settled_at timestamptz)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_caller uuid := auth.uid();
BEGIN
  IF v_caller IS NULL OR NOT (public._is_ops_or_god_admin(v_caller)
        OR public.has_role(v_caller,'finance_admin')) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED' USING ERRCODE='42501';
  END IF;
  RETURN QUERY
    SELECT d.user_id, d.wallet_id, d.party_type, d.amount_gnf, d.currency,
           d.state, d.classified_at, d.settled_at
      FROM public.dormant_closed_account_liabilities d
     ORDER BY d.classified_at DESC;
END $$;

REVOKE ALL ON FUNCTION public.admin_dormant_liabilities() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_dormant_liabilities() TO authenticated;

-- ---------- closure blockers: positive balance no longer gates identity ----------
CREATE OR REPLACE FUNCTION public._account_closure_blockers(_user uuid, _mode text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  b jsonb := '[]'::jsonb;
  v_lane text;
  v_pb jsonb;
BEGIN
  IF _user IS NULL THEN RAISE EXCEPTION 'TARGET_REQUIRED'; END IF;

  -- A positive residual balance is preserved as dormant closed-account
  -- liability at closure; it no longer blocks identity closure.
  -- A NEGATIVE balance is money owed TO the platform and still blocks.
  IF EXISTS (SELECT 1 FROM public.wallets
              WHERE owner_user_id = _user AND COALESCE(balance_gnf,0) < 0)
    THEN b := b || '"WALLET_BALANCE_NEGATIVE"'::jsonb; END IF;

  IF EXISTS (SELECT 1 FROM public.wallets
              WHERE owner_user_id = _user AND COALESCE(held_gnf,0) > 0)
    THEN b := b || '"WALLET_FUNDS_HELD"'::jsonb; END IF;

  IF EXISTS (SELECT 1 FROM public.mission_financial_holds
              WHERE (driver_user_id = _user OR party_user_id = _user)
                AND state IN ('held','partially_captured','frozen'))
    THEN b := b || '"OPEN_FINANCIAL_HOLD"'::jsonb; END IF;

  IF EXISTS (SELECT 1 FROM public.customer_cancellation_debts
              WHERE customer_user_id = _user AND state = 'outstanding')
    THEN b := b || '"CUSTOMER_CANCELLATION_DEBT"'::jsonb; END IF;

  IF EXISTS (SELECT 1 FROM public.topup_requests
              WHERE (client_user_id = _user OR agent_user_id = _user)
                AND status IN ('pending','matched','needs_review'))
    THEN b := b || '"PENDING_TOPUP"'::jsonb; END IF;

  IF EXISTS (SELECT 1 FROM public.driver_profiles
              WHERE user_id = _user AND COALESCE(cash_debt_gnf,0) > 0)
    THEN b := b || '"DRIVER_CASH_DEBT_OUTSTANDING"'::jsonb; END IF;

  IF EXISTS (SELECT 1 FROM public.driver_cashout_requests
              WHERE driver_user_id = _user AND status IN ('pending','approved'))
    THEN b := b || '"DRIVER_CASHOUT_IN_FLIGHT"'::jsonb; END IF;

  IF EXISTS (SELECT 1 FROM public.merchant_payables
              WHERE merchant_user_id = _user
                AND state IN ('pending_funding','funded','due','settlement_held','disputed'))
    THEN b := b || '"MERCHANT_UNSETTLED_PAYABLE"'::jsonb; END IF;

  IF EXISTS (SELECT 1 FROM public.merchant_settlement_requests
              WHERE merchant_user_id = _user AND status IN ('requested','pending_review'))
    THEN b := b || '"MERCHANT_SETTLEMENT_IN_FLIGHT"'::jsonb; END IF;

  IF EXISTS (SELECT 1 FROM public.rides
              WHERE (client_id = _user OR driver_id = _user)
                AND status IN ('pending','in_progress'))
    THEN b := b || '"ACTIVE_RIDE"'::jsonb; END IF;

  IF EXISTS (SELECT 1 FROM public.missions
              WHERE (courier_id = _user OR customer_id = _user OR merchant_id = _user)
                AND state NOT IN ('delivered','failed'))
    THEN b := b || '"ACTIVE_MISSION"'::jsonb; END IF;

  IF EXISTS (SELECT 1 FROM public.food_orders
              WHERE user_id = _user AND state NOT IN ('completed','cancelled'))
    THEN b := b || '"ACTIVE_FOOD_ORDER"'::jsonb; END IF;

  IF EXISTS (SELECT 1 FROM public.marche_orders
              WHERE (buyer_user_id = _user OR merchant_user_id = _user)
                AND status = 'committed'
                AND fulfillment_state NOT IN ('delivered','rejected','cancelled'))
    THEN b := b || '"ACTIVE_MARCHE_ORDER"'::jsonb; END IF;

  IF EXISTS (SELECT 1 FROM public.package_deliveries
              WHERE sender_user_id = _user
                AND COALESCE(package_status,'') NOT IN ('delivered','cancelled','failed'))
    THEN b := b || '"ACTIVE_PACKAGE_DELIVERY"'::jsonb; END IF;

  IF EXISTS (SELECT 1 FROM public.account_freezes
              WHERE user_id = _user AND status = 'active')
    THEN b := b || '"ACCOUNT_FREEZE_ACTIVE"'::jsonb; END IF;

  IF EXISTS (SELECT 1 FROM public.support_issues
              WHERE (reporter_user_id = _user OR related_driver_id = _user
                     OR related_customer_id = _user)
                AND status NOT IN ('resolved','cancelled'))
    THEN b := b || '"OPEN_SUPPORT_ISSUE"'::jsonb; END IF;

  SELECT professional_type INTO v_lane
    FROM public.professional_identities
   WHERE user_id = _user AND claim_state = 'active';
  IF v_lane IS NOT NULL THEN
    v_pb := public.professional_offboard_blockers(_user);
    b := b || COALESCE(v_pb->'blockers','[]'::jsonb);
  END IF;

  IF _mode = 'self' AND EXISTS (SELECT 1 FROM public.admin_users
                                 WHERE user_id = _user AND status = 'active')
    THEN b := b || '"GOVERNANCE_AUTHORITY_ACTIVE"'::jsonb; END IF;

  SELECT COALESCE(jsonb_agg(DISTINCT x ORDER BY x),'[]'::jsonb) INTO b
    FROM jsonb_array_elements_text(b) x;

  RETURN jsonb_build_object(
    'user_id', _user,
    'mode', _mode,
    'lane', COALESCE(v_lane,'none'),
    'blockers', b,
    'eligible', (jsonb_array_length(b) = 0));
END;
$$;
