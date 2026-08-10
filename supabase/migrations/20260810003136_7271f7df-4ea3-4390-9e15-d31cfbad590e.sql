-- ============================================================
-- SLICE 4 — REPAS / MARCHE CASH-ORDER ENGINE
-- Canonical authority: docs/product/chop-pay-canonical-operating-policy.md
-- ============================================================

-- ------------------------------------------------------------
-- 1. INTERNAL VARIANTS OF PRIVILEGED HELPERS (no behaviour change)
--    Public wrappers keep their existing authorization checks.
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public._merchant_payable_create_internal(
  p_source_module text, p_source_id uuid, p_merchant_store_id uuid,
  p_subtotal_gnf bigint, p_deduction_gnf bigint DEFAULT 0,
  p_mission_type text DEFAULT NULL, p_snapshot jsonb DEFAULT '{}'::jsonb,
  p_is_sandbox boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_owner uuid; v_amount bigint; v_row public.merchant_payables;
BEGIN
  v_amount := GREATEST(COALESCE(p_subtotal_gnf,0) - GREATEST(COALESCE(p_deduction_gnf,0),0), 0);
  SELECT owner_user_id INTO v_owner FROM public.merchant_stores WHERE id = p_merchant_store_id;

  INSERT INTO public.merchant_payables
    (payable_key, source_module, source_id, merchant_store_id, merchant_user_id, mission_type,
     subtotal_gnf, deduction_gnf, amount_gnf, policy_snapshot, is_sandbox)
  VALUES (format('payable:%s:%s:%s', p_source_module, p_source_id, p_merchant_store_id),
          p_source_module, p_source_id, p_merchant_store_id, v_owner, p_mission_type,
          GREATEST(COALESCE(p_subtotal_gnf,0),0), GREATEST(COALESCE(p_deduction_gnf,0),0),
          v_amount, p_snapshot, p_is_sandbox)
  ON CONFLICT (source_module, source_id, merchant_store_id) DO NOTHING
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    SELECT * INTO v_row FROM public.merchant_payables
     WHERE source_module = p_source_module AND source_id = p_source_id
       AND merchant_store_id = p_merchant_store_id;
    RETURN jsonb_build_object('status','already_exists','payable_id',v_row.id,'amount_gnf',v_row.amount_gnf);
  END IF;
  RETURN jsonb_build_object('status','created','payable_id',v_row.id,'amount_gnf',v_row.amount_gnf,
                            'note','Obligation recorded; no value moves until it is funded');
END; $$;

CREATE OR REPLACE FUNCTION public.merchant_payable_create(
  p_source_module text, p_source_id uuid, p_merchant_store_id uuid,
  p_subtotal_gnf bigint, p_deduction_gnf bigint DEFAULT 0,
  p_mission_type text DEFAULT NULL, p_snapshot jsonb DEFAULT '{}'::jsonb,
  p_is_sandbox boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public._finance_privileged(auth.uid()) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  RETURN public._merchant_payable_create_internal(p_source_module, p_source_id, p_merchant_store_id,
    p_subtotal_gnf, p_deduction_gnf, p_mission_type, p_snapshot, p_is_sandbox);
END; $$;

CREATE OR REPLACE FUNCTION public._merchant_payable_fund_internal(
  p_source_module text, p_source_id uuid, p_merchant_store_id uuid,
  p_funding_source text, p_actor uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_p public.merchant_payables; v_h public.mission_financial_holds;
  v_amount bigint; v_from text;
BEGIN
  IF p_funding_source = 'customer_choppay' THEN
    RAISE EXCEPTION 'CUSTOMER_CHOPPAY_FUNDED_AT_CAPTURE'
      USING DETAIL = 'Customer Chop Pay orders are funded atomically by chop_pay_customer_capture';
  END IF;
  IF p_funding_source NOT IN ('driver_cash_funding','platform') THEN
    RAISE EXCEPTION 'Invalid funding source';
  END IF;

  SELECT * INTO v_p FROM public.merchant_payables
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND merchant_store_id = p_merchant_store_id FOR UPDATE;
  IF v_p.id IS NULL THEN RAISE EXCEPTION 'Payable not found'; END IF;
  IF v_p.funded_gnf >= v_p.amount_gnf OR v_p.state <> 'pending_funding' THEN
    RETURN jsonb_build_object('status','already_funded','payable_id',v_p.id,
                              'funded_gnf',v_p.funded_gnf,'funding_source',v_p.funding_source);
  END IF;
  v_amount := v_p.amount_gnf - v_p.funded_gnf;

  IF p_funding_source = 'driver_cash_funding' THEN
    SELECT * INTO v_h FROM public.mission_financial_holds
     WHERE source_module = p_source_module AND source_id = p_source_id
       AND kind = 'cash_funding' AND state IN ('held','partially_captured') FOR UPDATE;
    IF v_h.id IS NULL THEN RAISE EXCEPTION 'CASH_FUNDING_HOLD_MISSING'; END IF;
    IF (v_h.amount_gnf - v_h.captured_gnf - v_h.released_gnf) < v_amount THEN
      RAISE EXCEPTION 'CASH_FUNDING_INSUFFICIENT';
    END IF;
    IF v_h.promo_gnf > 0 THEN
      RAISE EXCEPTION 'RESTRICTED_FUNDS_CANNOT_FUND_MERCHANDISE';
    END IF;
    v_from := 'L_HOLD_CASH_FUNDING';
    UPDATE public.mission_financial_holds
       SET captured_gnf = captured_gnf + v_amount,
           captured_unrestricted_gnf = captured_unrestricted_gnf + v_amount,
           state = CASE WHEN captured_gnf + v_amount >= amount_gnf THEN 'captured' ELSE 'partially_captured' END
     WHERE id = v_h.id;
    UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - v_amount,0),
                              balance_gnf = balance_gnf - v_amount, updated_at = now()
     WHERE owner_user_id = v_h.driver_user_id AND party_type = 'driver';
  ELSE
    v_from := 'EQ_PLATFORM';
  END IF;

  IF v_p.merchant_user_id IS NOT NULL THEN
    INSERT INTO public.wallets (owner_user_id, party_type) VALUES (v_p.merchant_user_id,'merchant')
    ON CONFLICT (owner_user_id, party_type) DO NOTHING;
    UPDATE public.wallets SET balance_gnf = balance_gnf + v_amount, updated_at = now()
     WHERE owner_user_id = v_p.merchant_user_id AND party_type = 'merchant';
  END IF;

  PERFORM public._ledger_post(
    format('payable-fund:%s:%s:%s', p_source_module, p_source_id, p_merchant_store_id),
    p_source_module, p_source_id, 'merchant_payable_funded',
    jsonb_build_array(
      jsonb_build_object('account',v_from,'amount_gnf',v_amount,'memo','funding source consumed'),
      jsonb_build_object('account','L_MERCHANT_PAYABLE','amount_gnf',-v_amount,
                         'party_type','merchant','party_user_id',v_p.merchant_user_id,
                         'merchant_store_id',p_merchant_store_id,'memo','merchant payable funded')),
    v_p.mission_type, p_actor, v_p.policy_snapshot, v_p.is_sandbox);

  UPDATE public.merchant_payables
     SET funded_gnf = funded_gnf + v_amount, funding_source = p_funding_source,
         state = 'funded', updated_at = now()
   WHERE id = v_p.id;

  RETURN jsonb_build_object('status','funded','payable_id',v_p.id,'funded_gnf',v_amount,
                            'funding_source',p_funding_source,'preparation_authorized',true);
END; $$;

CREATE OR REPLACE FUNCTION public.merchant_payable_fund(
  p_source_module text, p_source_id uuid, p_merchant_store_id uuid, p_funding_source text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public._finance_privileged(auth.uid()) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  RETURN public._merchant_payable_fund_internal(p_source_module, p_source_id,
                                                p_merchant_store_id, p_funding_source, auth.uid());
END; $$;

CREATE OR REPLACE FUNCTION public._driver_mission_hold_release_internal(
  p_source_module text, p_source_id uuid, p_kind text DEFAULT NULL,
  p_reason text DEFAULT NULL, p_actor uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_h public.mission_financial_holds;
  v_released bigint := 0; v_wallet_id uuid; v_open bigint; v_u bigint; v_p bigint;
BEGIN
  FOR v_h IN
    SELECT * FROM public.mission_financial_holds
     WHERE source_module = p_source_module AND source_id = p_source_id
       AND (p_kind IS NULL OR kind = p_kind)
       AND state IN ('held','partially_captured','frozen')
     ORDER BY created_at FOR UPDATE
  LOOP
    v_open := v_h.amount_gnf - v_h.captured_gnf - v_h.released_gnf;
    CONTINUE WHEN v_open <= 0;

    v_p := LEAST(v_open, GREATEST(v_h.promo_gnf - LEAST(v_h.captured_gnf, v_h.promo_gnf), 0));
    v_u := v_open - v_p;

    SELECT id INTO v_wallet_id FROM public.wallets
     WHERE owner_user_id = v_h.driver_user_id AND party_type = 'driver' FOR UPDATE;

    UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - v_open, 0), updated_at = now()
     WHERE id = v_wallet_id;
    UPDATE public.wallet_transactions SET status = 'cancelled', completed_at = now()
     WHERE id = v_h.hold_tx_id AND status = 'pending';

    PERFORM public._ledger_post(
      format('mfh-release:%s:%s:%s', p_source_module, p_source_id, v_h.kind),
      p_source_module, p_source_id, 'release_' || v_h.kind,
      jsonb_build_array(
        jsonb_build_object('account', public._hold_account(v_h.kind), 'amount_gnf', v_open,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','release hold'),
        jsonb_build_object('account','L_DRIVER_PROMO','amount_gnf',-v_p,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','restored to restricted credit'),
        jsonb_build_object('account','L_DRIVER_UNRESTRICTED','amount_gnf',-v_u,
                           'party_type','driver','party_user_id',v_h.driver_user_id,'memo','restored to unrestricted')),
      v_h.mission_type, p_actor, v_h.policy_snapshot, v_h.is_sandbox, p_reason);

    UPDATE public.mission_financial_holds
       SET state = 'released', released_gnf = released_gnf + v_open,
           reason = COALESCE(p_reason, reason), resolved_at = now(), resolved_by = p_actor
     WHERE id = v_h.id;

    v_released := v_released + v_open;
  END LOOP;

  RETURN jsonb_build_object('status', 'released', 'released_gnf', v_released);
END; $$;

CREATE OR REPLACE FUNCTION public.driver_mission_hold_release(
  p_source_module text, p_source_id uuid, p_kind text DEFAULT NULL, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF (auth.uid() IS NOT NULL) AND NOT public._finance_privileged(auth.uid()) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  RETURN public._driver_mission_hold_release_internal(p_source_module, p_source_id,
                                                      p_kind, p_reason, auth.uid());
END; $$;

CREATE OR REPLACE FUNCTION public._customer_cancellation_debt_create_internal(
  p_source_module text, p_source_id uuid, p_customer uuid, p_mission_type text, p_stage text,
  p_fare_gnf bigint DEFAULT 0, p_merchandise_subtotal_gnf bigint DEFAULT 0,
  p_delivery_fee_gnf bigint DEFAULT 0, p_preparation_started boolean DEFAULT false,
  p_responsible_party text DEFAULT 'customer', p_is_sandbox boolean DEFAULT false,
  p_policy_snapshot jsonb DEFAULT NULL, p_actor uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_req jsonb; v_snap jsonb; v_basis_kind text;
  v_bps int; v_basis bigint; v_amount bigint;
  v_row public.customer_cancellation_debts;
BEGIN
  IF p_stage NOT IN ('before_dispatch','after_dispatch') THEN RAISE EXCEPTION 'Invalid stage'; END IF;
  IF p_responsible_party NOT IN ('customer','provider','platform','merchant','driver') THEN
    RAISE EXCEPTION 'Invalid responsible party';
  END IF;

  IF p_mission_type IN ('repas','marche') AND COALESCE(p_preparation_started,false)
     AND p_responsible_party = 'customer' THEN
    RAISE EXCEPTION 'REPAS_CANCELLATION_LOCKED'
      USING DETAIL = 'Customer cancellation is prohibited once preparation has started';
  END IF;

  IF p_responsible_party <> 'customer' THEN
    RETURN jsonb_build_object('status','exempt','amount_gnf',0,
      'exempt_reason', format('not_customer_caused:%s', p_responsible_party));
  END IF;

  IF p_policy_snapshot IS NOT NULL AND p_policy_snapshot <> '{}'::jsonb THEN
    v_snap := p_policy_snapshot;
  ELSE
    v_req := public.finance_mission_requirement_v2(p_mission_type,0,0,0,0,'cash');
    v_snap := COALESCE(v_req->'policy_snapshot','{}'::jsonb);
  END IF;
  v_basis_kind := COALESCE(v_snap->>'cancel_basis','none');

  v_basis := CASE v_basis_kind
    WHEN 'fare' THEN GREATEST(COALESCE(p_fare_gnf,0),0)
    WHEN 'merchandise_plus_delivery' THEN GREATEST(COALESCE(p_merchandise_subtotal_gnf,0),0)
                                        + GREATEST(COALESCE(p_delivery_fee_gnf,0),0)
    WHEN 'delivery_fee' THEN GREATEST(COALESCE(p_delivery_fee_gnf,0),0)
    ELSE GREATEST(COALESCE(p_fare_gnf,0),0) END;

  v_bps := CASE p_stage
    WHEN 'before_dispatch' THEN COALESCE((v_snap->>'cancel_before_dispatch_bps')::int, 0)
    ELSE COALESCE((v_snap->>'cancel_after_dispatch_bps')::int, 0) END;
  v_amount := (v_basis * v_bps) / 10000;

  INSERT INTO public.customer_cancellation_debts
    (debt_key, customer_user_id, source_module, source_id, mission_type, stage,
     basis_gnf, applied_bps, amount_gnf, state, exempt_reason, policy_snapshot, is_sandbox)
  VALUES (format('cancel:%s:%s', p_source_module, p_source_id), p_customer, p_source_module,
          p_source_id, p_mission_type, p_stage, v_basis, v_bps, v_amount,
          CASE WHEN v_amount > 0 THEN 'outstanding' ELSE 'exempt' END,
          CASE WHEN v_amount > 0 THEN NULL ELSE 'zero_fee_policy' END,
          v_snap || jsonb_build_object('cancel_basis_kind', v_basis_kind,
                                       'preparation_started', COALESCE(p_preparation_started,false)),
          p_is_sandbox)
  ON CONFLICT (source_module, source_id) DO NOTHING
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN RETURN jsonb_build_object('status','already_exists'); END IF;

  IF v_amount > 0 THEN
    PERFORM public._ledger_post(v_row.debt_key, p_source_module, p_source_id, 'cancellation_fee_charged',
      jsonb_build_array(
        jsonb_build_object('account','A_CUSTOMER_DEBT','amount_gnf',v_amount,
                           'party_type','client','party_user_id',p_customer,'memo','cancellation fee receivable'),
        jsonb_build_object('account','R_CANCELLATION_FEE','amount_gnf',-v_amount,'memo','cancellation fee revenue')),
      p_mission_type, p_actor, v_snap, p_is_sandbox);
  END IF;

  RETURN jsonb_build_object('status', CASE WHEN v_amount > 0 THEN 'charged' ELSE 'exempt' END,
                            'debt_id',v_row.id,'basis_kind',v_basis_kind,'basis_gnf',v_basis,
                            'amount_gnf',v_amount,'applied_bps',v_bps);
END; $$;

CREATE OR REPLACE FUNCTION public.customer_cancellation_debt_create(
  p_source_module text, p_source_id uuid, p_customer uuid, p_mission_type text, p_stage text,
  p_fare_gnf bigint DEFAULT 0, p_merchandise_subtotal_gnf bigint DEFAULT 0,
  p_delivery_fee_gnf bigint DEFAULT 0, p_preparation_started boolean DEFAULT false,
  p_responsible_party text DEFAULT 'customer', p_is_sandbox boolean DEFAULT false,
  p_policy_snapshot jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public._finance_privileged(auth.uid()) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  RETURN public._customer_cancellation_debt_create_internal(p_source_module, p_source_id, p_customer,
    p_mission_type, p_stage, p_fare_gnf, p_merchandise_subtotal_gnf, p_delivery_fee_gnf,
    p_preparation_started, p_responsible_party, p_is_sandbox, p_policy_snapshot, auth.uid());
END; $$;

-- ------------------------------------------------------------
-- 2. RUNTIME TABLE
-- ------------------------------------------------------------

CREATE TABLE public.cash_order_runtime (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_key text NOT NULL UNIQUE,
  source_module text NOT NULL CHECK (source_module IN ('repas','marche')),
  source_id uuid NOT NULL,
  mission_type text NOT NULL CHECK (mission_type IN ('repas','marche')),
  mission_id uuid,
  customer_user_id uuid NOT NULL,
  driver_user_id uuid NOT NULL,
  merchant_store_id uuid,
  merchant_user_id uuid,
  merchandise_subtotal_gnf bigint NOT NULL CHECK (merchandise_subtotal_gnf >= 0),
  delivery_fee_gnf bigint NOT NULL DEFAULT 0 CHECK (delivery_fee_gnf >= 0),
  platform_fee_gnf bigint NOT NULL DEFAULT 0 CHECK (platform_fee_gnf >= 0),
  cash_due_gnf bigint NOT NULL CHECK (cash_due_gnf >= 0),
  policy_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  state text NOT NULL DEFAULT 'accepted'
    CHECK (state IN ('accepted','merchant_accepted','preparing','completed',
                     'cancelled','merchant_rejected','disputed','dispute_resolved')),
  funded_at timestamptz,
  prep_locked_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  disputed_at timestamptz,
  dispute_reason text,
  dispute_opened_by uuid,
  dispute_resolution jsonb,
  resolved_by uuid,
  resolved_at timestamptz,
  cash_collected_gnf bigint,
  cash_principal_recovery_gnf bigint,
  cash_delivery_earning_gnf bigint,
  cash_fee_recovery_gnf bigint,
  is_sandbox boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (source_module, source_id)
);

GRANT SELECT ON public.cash_order_runtime TO authenticated;
GRANT ALL ON public.cash_order_runtime TO service_role;

ALTER TABLE public.cash_order_runtime ENABLE ROW LEVEL SECURITY;

CREATE POLICY "cash_order_runtime_participant_select"
ON public.cash_order_runtime FOR SELECT TO authenticated
USING (
  auth.uid() = customer_user_id
  OR auth.uid() = driver_user_id
  OR auth.uid() = merchant_user_id
  OR public._finance_privileged(auth.uid())
);

CREATE INDEX idx_cash_order_runtime_driver ON public.cash_order_runtime (driver_user_id, state);
CREATE INDEX idx_cash_order_runtime_merchant ON public.cash_order_runtime (merchant_user_id, state);
CREATE INDEX idx_cash_order_runtime_customer ON public.cash_order_runtime (customer_user_id, state);

CREATE TRIGGER trg_cash_order_runtime_updated
BEFORE UPDATE ON public.cash_order_runtime
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Accepted economics are immutable: a later policy change can never move them.
CREATE OR REPLACE FUNCTION public._cash_order_runtime_immutable()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF NEW.merchandise_subtotal_gnf IS DISTINCT FROM OLD.merchandise_subtotal_gnf
     OR NEW.delivery_fee_gnf IS DISTINCT FROM OLD.delivery_fee_gnf
     OR NEW.platform_fee_gnf IS DISTINCT FROM OLD.platform_fee_gnf
     OR NEW.cash_due_gnf IS DISTINCT FROM OLD.cash_due_gnf
     OR NEW.policy_snapshot IS DISTINCT FROM OLD.policy_snapshot
     OR NEW.driver_user_id IS DISTINCT FROM OLD.driver_user_id
     OR NEW.customer_user_id IS DISTINCT FROM OLD.customer_user_id
     OR NEW.merchant_store_id IS DISTINCT FROM OLD.merchant_store_id
     OR NEW.source_module IS DISTINCT FROM OLD.source_module
     OR NEW.source_id IS DISTINCT FROM OLD.source_id THEN
    RAISE EXCEPTION 'CASH_ORDER_SNAPSHOT_IMMUTABLE';
  END IF;
  RETURN NEW;
END; $$;

CREATE TRIGGER trg_cash_order_runtime_immutable
BEFORE UPDATE ON public.cash_order_runtime
FOR EACH ROW EXECUTE FUNCTION public._cash_order_runtime_immutable();

-- ------------------------------------------------------------
-- 3. FACTS RESOLVER (internal)
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public._cash_order_facts(p_source_module text, p_source_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_customer uuid; v_store uuid; v_owner uuid; v_sub bigint := 0;
  v_is_cash boolean := false; v_mixed boolean := false; v_pstate text;
  v_mission public.missions; v_del bigint := 0;
BEGIN
  IF p_source_module = 'repas' THEN
    SELECT fo.user_id, r.merchant_store_id, COALESCE(r.owner_user_id, ms.owner_user_id),
           fo.subtotal_gnf, (fo.payment_method::text = 'cash'),
           (fo.payment_method::text <> 'cash' OR fo.captured_intent_id IS NOT NULL),
           fo.state::text
      INTO v_customer, v_store, v_owner, v_sub, v_is_cash, v_mixed, v_pstate
      FROM public.food_orders fo
      JOIN public.food_restaurants r ON r.id = fo.restaurant_id
      LEFT JOIN public.merchant_stores ms ON ms.id = r.merchant_store_id
     WHERE fo.id = p_source_id;

    SELECT * INTO v_mission FROM public.missions
     WHERE ref_food_order_id = p_source_id ORDER BY created_at DESC LIMIT 1;

  ELSIF p_source_module = 'marche' THEN
    SELECT mo.buyer_user_id, mo.merchant_store_id, mo.merchant_user_id,
           COALESCE(mo.counter_amount_gnf, mo.offer_amount_gnf),
           COALESCE(mo.metadata->>'payment_method','cash') = 'cash',
           (mo.payment_intent_id IS NOT NULL),
           mo.status
      INTO v_customer, v_store, v_owner, v_sub, v_is_cash, v_mixed, v_pstate
      FROM public.marketplace_offers mo
     WHERE mo.id = p_source_id;

    SELECT * INTO v_mission FROM public.missions
     WHERE ref_market_order_id = p_source_id ORDER BY created_at DESC LIMIT 1;
  ELSE
    RAISE EXCEPTION 'UNSUPPORTED_CASH_ORDER_MODULE';
  END IF;

  IF v_customer IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;

  v_del := GREATEST(COALESCE(v_mission.estimated_earning_gnf, 0), 0);

  RETURN jsonb_build_object(
    'source_module', p_source_module, 'source_id', p_source_id,
    'mission_type', p_source_module,
    'customer_user_id', v_customer,
    'merchant_store_id', v_store, 'merchant_user_id', v_owner,
    'merchandise_subtotal_gnf', GREATEST(COALESCE(v_sub,0),0),
    'delivery_fee_gnf', v_del,
    'is_cash', COALESCE(v_is_cash,false),
    'mixed_tender', COALESCE(v_mixed,false),
    'product_state', v_pstate,
    'mission_id', v_mission.id,
    'mission_state', v_mission.state::text,
    'courier_id', v_mission.courier_id,
    'pickup_confirmed', v_mission.pickup_confirmed_at IS NOT NULL);
END; $$;

CREATE OR REPLACE FUNCTION public._cash_order_economics(p_facts jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_req jsonb; v_sub bigint; v_del bigint; v_fee bigint; v_fund bigint;
BEGIN
  v_sub := (p_facts->>'merchandise_subtotal_gnf')::bigint;
  v_del := (p_facts->>'delivery_fee_gnf')::bigint;
  v_req := public.finance_mission_requirement_v2(p_facts->>'mission_type', 0, v_sub, v_del, 0, 'cash');
  v_fee  := COALESCE((v_req->>'platform_fee_gnf')::bigint, 0);
  v_fund := COALESCE((v_req->>'cash_funding_gnf')::bigint, 0);
  RETURN v_req || jsonb_build_object(
    'merchandise_subtotal_gnf', v_sub,
    'delivery_fee_gnf', v_del,
    'platform_fee_gnf', v_fee,
    'cash_funding_gnf', v_fund,
    'cash_due_gnf', v_sub + v_del + v_fee);
END; $$;

-- ------------------------------------------------------------
-- 4. PLATFORM FEE CAPTURE (internal, idempotent)
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public._cash_order_capture_platform_fee(
  p_source_module text, p_source_id uuid, p_actor uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_h public.mission_financial_holds; v_capture bigint;
  v_cp bigint := 0; v_cu bigint := 0;
  v_dw public.wallets; v_master public.wallets;
BEGIN
  SELECT * INTO v_h FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id AND kind = 'platform_fee'
   FOR UPDATE;
  IF v_h.id IS NULL THEN RETURN jsonb_build_object('status','no_hold','captured_gnf',0); END IF;
  IF v_h.state <> 'held' THEN
    RETURN jsonb_build_object('status','already_resolved','captured_gnf',v_h.captured_gnf);
  END IF;

  v_capture := GREATEST(v_h.amount_gnf - v_h.captured_gnf - v_h.released_gnf, 0);
  IF v_capture = 0 THEN
    UPDATE public.mission_financial_holds SET state = 'captured', resolved_at = now() WHERE id = v_h.id;
    RETURN jsonb_build_object('status','zero_fee','captured_gnf',0);
  END IF;

  v_cp := LEAST(v_h.promo_gnf, v_capture);
  v_cu := v_capture - v_cp;

  SELECT * INTO v_dw FROM public.wallets
   WHERE owner_user_id = v_h.driver_user_id AND party_type = 'driver' FOR UPDATE;
  SELECT * INTO v_master FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;

  UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - v_capture, 0),
                            balance_gnf = balance_gnf - v_capture, updated_at = now()
   WHERE id = v_dw.id;
  IF v_master.id IS NOT NULL THEN
    UPDATE public.wallets SET balance_gnf = balance_gnf + v_capture, updated_at = now()
     WHERE id = v_master.id;
  END IF;
  IF v_cp > 0 THEN PERFORM public._promo_consume(v_h.driver_user_id, v_cp); END IF;

  INSERT INTO public.wallet_transactions
    (reference, type, status, amount_gnf, from_wallet_id, to_wallet_id, related_user_id,
     related_entity, description, metadata, completed_at)
  VALUES
    (format('mfh-capture:%s:%s:platform_fee', p_source_module, p_source_id), 'capture', 'completed',
     v_capture, v_dw.id, v_master.id, v_h.driver_user_id,
     p_source_module || ':' || p_source_id::text, 'Frais de transaction CHOPCHOP',
     jsonb_build_object('mission_type', v_h.mission_type, 'reserved_gnf', v_h.amount_gnf,
                        'captured_gnf', v_capture, 'promo_consumed_gnf', v_cp,
                        'unrestricted_consumed_gnf', v_cu, 'is_sandbox', v_h.is_sandbox), now());

  UPDATE public.wallet_transactions SET status = 'completed', completed_at = now()
   WHERE id = v_h.hold_tx_id AND status = 'pending';

  PERFORM public._ledger_post(
    format('mfh-capture:%s:%s:platform_fee', p_source_module, p_source_id),
    p_source_module, p_source_id, 'capture_platform_fee',
    jsonb_build_array(
      jsonb_build_object('account','L_HOLD_PLATFORM_FEE','amount_gnf',v_capture,
                         'party_type','driver','party_user_id',v_h.driver_user_id,'memo','consume platform fee hold'),
      jsonb_build_object('account','R_TRANSACTION_FEE','amount_gnf',-v_capture,'memo','non-ride transaction fee revenue')),
    v_h.mission_type, p_actor, v_h.policy_snapshot, v_h.is_sandbox);

  UPDATE public.mission_financial_holds
     SET captured_gnf = captured_gnf + v_capture,
         captured_promo_gnf = captured_promo_gnf + v_cp,
         captured_unrestricted_gnf = captured_unrestricted_gnf + v_cu,
         state = 'captured', resolved_at = now(), resolved_by = p_actor
   WHERE id = v_h.id;

  RETURN jsonb_build_object('status','captured','captured_gnf',v_capture,
                            'promo_gnf',v_cp,'unrestricted_gnf',v_cu);
END; $$;

-- ------------------------------------------------------------
-- 5. PUBLIC RUNTIME ENTRYPOINTS
-- ------------------------------------------------------------

-- 5.1 Courier preview (read-only)
CREATE OR REPLACE FUNCTION public.cash_order_quote(p_source_module text, p_source_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_caller uuid := auth.uid(); v_f jsonb; v_e jsonb; v_elig jsonb;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  v_f := public._cash_order_facts(p_source_module, p_source_id);

  IF v_caller <> (v_f->>'customer_user_id')::uuid
     AND v_caller IS DISTINCT FROM (v_f->>'merchant_user_id')::uuid
     AND v_caller IS DISTINCT FROM (v_f->>'courier_id')::uuid
     AND NOT public._finance_privileged(v_caller) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  v_e := public._cash_order_economics(v_f);
  v_elig := CASE WHEN v_caller IS NOT DISTINCT FROM (v_f->>'courier_id')::uuid
                 THEN public.driver_financial_eligibility(v_f->>'mission_type',
                        (v_f->>'merchandise_subtotal_gnf')::bigint, v_caller)
                 ELSE NULL END;

  RETURN jsonb_build_object('facts', v_f, 'economics', v_e, 'eligibility', v_elig,
                            'flag_enabled', public._finance_flag('cash_order_funding_enabled'));
END; $$;

-- 5.2 Courier acceptance
CREATE OR REPLACE FUNCTION public.cash_order_accept(p_source_module text, p_source_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_caller uuid := auth.uid(); v_f jsonb; v_e jsonb; v_row public.cash_order_runtime;
  v_key text; v_hold jsonb; v_sub bigint; v_del bigint; v_fee bigint; v_snap jsonb;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public._finance_flag('cash_order_funding_enabled') THEN
    RAISE EXCEPTION 'CASH_ORDER_FUNDING_DISABLED';
  END IF;

  v_key := format('%s:%s', p_source_module, p_source_id);
  PERFORM pg_advisory_xact_lock(hashtextextended(v_key, 0));

  SELECT * INTO v_row FROM public.cash_order_runtime WHERE order_key = v_key FOR UPDATE;
  IF v_row.id IS NOT NULL THEN
    RETURN jsonb_build_object('status','already_accepted','runtime_id',v_row.id,
                              'driver_user_id',v_row.driver_user_id,'state',v_row.state);
  END IF;

  v_f := public._cash_order_facts(p_source_module, p_source_id);
  IF NOT (v_f->>'is_cash')::boolean THEN RAISE EXCEPTION 'NOT_A_CASH_ORDER'; END IF;
  IF (v_f->>'mixed_tender')::boolean THEN RAISE EXCEPTION 'MIXED_TENDER_NOT_SUPPORTED'; END IF;
  IF (v_f->>'courier_id') IS NULL THEN RAISE EXCEPTION 'NO_ASSIGNED_COURIER'; END IF;
  IF v_caller <> (v_f->>'courier_id')::uuid THEN RAISE EXCEPTION 'NOT_ASSIGNED_DRIVER'; END IF;
  IF (v_f->>'mission_state') <> 'assigned' THEN RAISE EXCEPTION 'STALE_OFFER'; END IF;
  IF (v_f->>'merchant_store_id') IS NULL THEN RAISE EXCEPTION 'MERCHANT_STORE_MISSING'; END IF;

  v_e := public._cash_order_economics(v_f);
  v_sub := (v_e->>'merchandise_subtotal_gnf')::bigint;
  v_del := (v_e->>'delivery_fee_gnf')::bigint;
  v_fee := (v_e->>'platform_fee_gnf')::bigint;
  v_snap := COALESCE(v_e->'policy_snapshot','{}'::jsonb);

  IF v_sub <= 0 THEN RAISE EXCEPTION 'INVALID_MERCHANDISE_SUBTOTAL'; END IF;
  IF COALESCE((v_e->>'cash_funding_gnf')::bigint,0) <> v_sub THEN
    RAISE EXCEPTION 'CASH_FUNDING_POLICY_MISMATCH'
      USING DETAIL = format('funding=%s subtotal=%s', v_e->>'cash_funding_gnf', v_sub);
  END IF;

  -- Atomic eligibility recheck happens inside driver_mission_hold_place:
  -- cash_funding is unrestricted-only, platform_fee may use promo.
  v_hold := public.driver_mission_hold_place(
    v_f->>'mission_type', p_source_module, p_source_id, 0, v_caller, false,
    ARRAY['cash_funding','platform_fee'], 0, v_sub, v_del, 0, 'cash');

  PERFORM public._merchant_payable_create_internal(
    p_source_module, p_source_id, (v_f->>'merchant_store_id')::uuid,
    v_sub, 0, v_f->>'mission_type', v_snap, false);

  INSERT INTO public.cash_order_runtime
    (order_key, source_module, source_id, mission_type, mission_id, customer_user_id,
     driver_user_id, merchant_store_id, merchant_user_id, merchandise_subtotal_gnf,
     delivery_fee_gnf, platform_fee_gnf, cash_due_gnf, policy_snapshot, state)
  VALUES (v_key, p_source_module, p_source_id, v_f->>'mission_type',
          (v_f->>'mission_id')::uuid, (v_f->>'customer_user_id')::uuid, v_caller,
          (v_f->>'merchant_store_id')::uuid, (v_f->>'merchant_user_id')::uuid,
          v_sub, v_del, v_fee, v_sub + v_del + v_fee, v_snap, 'accepted')
  RETURNING * INTO v_row;

  RETURN jsonb_build_object('status','accepted','runtime_id',v_row.id,
    'merchandise_subtotal_gnf',v_sub,'delivery_fee_gnf',v_del,'platform_fee_gnf',v_fee,
    'cash_due_gnf',v_row.cash_due_gnf,'hold',v_hold);
END; $$;

-- 5.3 Merchant acceptance (funds the payable exactly once)
CREATE OR REPLACE FUNCTION public.cash_order_merchant_accept(p_source_module text, p_source_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_caller uuid := auth.uid(); v_row public.cash_order_runtime; v_fund jsonb;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_row FROM public.cash_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id FOR UPDATE;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'CASH_ORDER_NOT_ACCEPTED'; END IF;
  IF v_caller IS DISTINCT FROM v_row.merchant_user_id AND NOT public._finance_privileged(v_caller) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF v_row.state IN ('merchant_accepted','preparing','completed') THEN
    RETURN jsonb_build_object('status','already_accepted','state',v_row.state);
  END IF;
  IF v_row.state <> 'accepted' THEN
    RAISE EXCEPTION 'INVALID_STATE' USING DETAIL = v_row.state;
  END IF;

  v_fund := public._merchant_payable_fund_internal(
    p_source_module, p_source_id, v_row.merchant_store_id, 'driver_cash_funding', v_caller);

  UPDATE public.cash_order_runtime
     SET state = 'merchant_accepted', funded_at = now()
   WHERE id = v_row.id;

  IF p_source_module = 'repas' THEN
    UPDATE public.food_orders SET state = 'confirmed'
     WHERE id = p_source_id AND state = 'placed';
  END IF;

  RETURN jsonb_build_object('status','merchant_accepted','funding',v_fund,
                            'merchant_credited_gnf', v_row.merchandise_subtotal_gnf);
END; $$;

-- 5.4 Merchant rejection before preparation
CREATE OR REPLACE FUNCTION public.cash_order_merchant_reject(
  p_source_module text, p_source_id uuid, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_caller uuid := auth.uid(); v_row public.cash_order_runtime; v_rel jsonb;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_row FROM public.cash_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id FOR UPDATE;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'CASH_ORDER_NOT_ACCEPTED'; END IF;
  IF v_caller IS DISTINCT FROM v_row.merchant_user_id AND NOT public._finance_privileged(v_caller) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF v_row.state = 'merchant_rejected' THEN
    RETURN jsonb_build_object('status','already_rejected');
  END IF;
  IF v_row.state <> 'accepted' THEN
    RAISE EXCEPTION 'MERCHANT_REJECTION_AFTER_FUNDING'
      USING DETAIL = 'Use the dispute path once funding or preparation has started';
  END IF;

  v_rel := public._driver_mission_hold_release_internal(
    p_source_module, p_source_id, NULL,
    COALESCE(p_reason, 'merchant_rejected_before_preparation'), v_caller);

  UPDATE public.merchant_payables
     SET state = 'cancelled', reason = COALESCE(p_reason,'merchant_rejected'), updated_at = now()
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND state = 'pending_funding' AND funded_gnf = 0;

  UPDATE public.cash_order_runtime
     SET state = 'merchant_rejected', cancelled_at = now(),
         dispute_reason = COALESCE(p_reason, dispute_reason)
   WHERE id = v_row.id;

  IF p_source_module = 'repas' THEN
    UPDATE public.food_orders SET state = 'cancelled'
     WHERE id = p_source_id AND state IN ('placed','confirmed');
  END IF;

  RETURN jsonb_build_object('status','merchant_rejected','release',v_rel,
                            'customer_debt_created', false, 'platform_fee_revenue_gnf', 0);
END; $$;

-- 5.5 Preparation lock
CREATE OR REPLACE FUNCTION public.cash_order_merchant_prepare(p_source_module text, p_source_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_caller uuid := auth.uid(); v_row public.cash_order_runtime; v_funded bigint; v_amount bigint;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_row FROM public.cash_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id FOR UPDATE;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'CASH_ORDER_NOT_ACCEPTED'; END IF;
  IF v_caller IS DISTINCT FROM v_row.merchant_user_id AND NOT public._finance_privileged(v_caller) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF v_row.state IN ('preparing','completed') THEN
    RETURN jsonb_build_object('status','already_preparing','state',v_row.state,
                              'prep_locked_at',v_row.prep_locked_at);
  END IF;
  IF v_row.state <> 'merchant_accepted' THEN
    RAISE EXCEPTION 'PREPARATION_REQUIRES_FUNDED_ORDER' USING DETAIL = v_row.state;
  END IF;

  SELECT funded_gnf, amount_gnf INTO v_funded, v_amount FROM public.merchant_payables
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND merchant_store_id = v_row.merchant_store_id;
  IF COALESCE(v_funded,0) < COALESCE(v_amount,0) OR COALESCE(v_amount,0) = 0 THEN
    RAISE EXCEPTION 'MERCHANDISE_FUNDING_NOT_SECURED';
  END IF;

  UPDATE public.cash_order_runtime SET state = 'preparing', prep_locked_at = now() WHERE id = v_row.id;

  IF p_source_module = 'repas' THEN
    UPDATE public.food_orders SET state = 'preparing'
     WHERE id = p_source_id AND state IN ('placed','confirmed');
  END IF;

  RETURN jsonb_build_object('status','preparing','customer_cancellation_locked',true);
END; $$;

-- 5.6 Cash completion
CREATE OR REPLACE FUNCTION public.cash_order_complete_cash(p_source_module text, p_source_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_caller uuid := auth.uid(); v_row public.cash_order_runtime; v_f jsonb; v_fee jsonb;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_row FROM public.cash_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id FOR UPDATE;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'CASH_ORDER_NOT_ACCEPTED'; END IF;
  IF v_caller <> v_row.driver_user_id AND NOT public._finance_privileged(v_caller) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF v_row.state = 'completed' THEN
    RETURN jsonb_build_object('status','already_completed','cash_due_gnf',v_row.cash_due_gnf);
  END IF;
  IF v_row.state = 'disputed' THEN RAISE EXCEPTION 'ORDER_IN_DISPUTE'; END IF;
  IF v_row.state NOT IN ('preparing','merchant_accepted') THEN
    RAISE EXCEPTION 'INVALID_STATE' USING DETAIL = v_row.state;
  END IF;
  IF p_source_module = 'repas' AND v_row.state <> 'preparing' THEN
    RAISE EXCEPTION 'PREPARATION_REQUIRED_BEFORE_DELIVERY';
  END IF;

  v_f := public._cash_order_facts(p_source_module, p_source_id);
  IF NOT COALESCE((v_f->>'pickup_confirmed')::boolean, false) THEN
    RAISE EXCEPTION 'CUSTODY_NOT_ESTABLISHED' USING DETAIL = 'pickup must be confirmed first';
  END IF;
  IF COALESCE(v_f->>'mission_state','') NOT IN ('picked_up','heading_to_dropoff','arrived_dropoff','delivered') THEN
    RAISE EXCEPTION 'INVALID_MISSION_STATE' USING DETAIL = COALESCE(v_f->>'mission_state','none');
  END IF;

  -- Physical cash: no wallet credit is created for the courier.
  -- The 150 000 principal is a return of an advance; the delivery fee is physical cash.
  v_fee := public._cash_order_capture_platform_fee(p_source_module, p_source_id, v_caller);

  UPDATE public.cash_order_runtime
     SET state = 'completed', completed_at = now(),
         cash_collected_gnf = v_row.cash_due_gnf,
         cash_principal_recovery_gnf = v_row.merchandise_subtotal_gnf,
         cash_delivery_earning_gnf = v_row.delivery_fee_gnf,
         cash_fee_recovery_gnf = v_row.platform_fee_gnf
   WHERE id = v_row.id;

  IF p_source_module = 'repas' THEN
    UPDATE public.food_orders SET state = 'completed', completed_at = now()
     WHERE id = p_source_id AND state <> 'completed';
  END IF;

  RETURN jsonb_build_object('status','completed',
    'cash_due_gnf', v_row.cash_due_gnf,
    'merchandise_subtotal_gnf', v_row.merchandise_subtotal_gnf,
    'delivery_fee_gnf', v_row.delivery_fee_gnf,
    'platform_fee_gnf', v_row.platform_fee_gnf,
    'driver_wallet_credit_gnf', 0,
    'principal_recovery_is_income', false,
    'fee_capture', v_fee);
END; $$;

-- 5.7 Customer cancellation (pre-funding only)
CREATE OR REPLACE FUNCTION public.cash_order_customer_cancel(
  p_source_module text, p_source_id uuid, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_caller uuid := auth.uid(); v_row public.cash_order_runtime; v_f jsonb; v_e jsonb;
  v_debt jsonb; v_rel jsonb; v_stage text; v_snap jsonb; v_sub bigint; v_del bigint;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(format('%s:%s', p_source_module, p_source_id), 0));

  v_f := public._cash_order_facts(p_source_module, p_source_id);
  IF v_caller <> (v_f->>'customer_user_id')::uuid THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF NOT (v_f->>'is_cash')::boolean THEN RAISE EXCEPTION 'NOT_A_CASH_ORDER'; END IF;

  SELECT * INTO v_row FROM public.cash_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id FOR UPDATE;

  IF v_row.id IS NULL THEN
    -- No courier accepted yet: pre-dispatch cancellation against current policy.
    v_e := public._cash_order_economics(v_f);
    v_stage := 'before_dispatch';
    v_snap := COALESCE(v_e->'policy_snapshot','{}'::jsonb);
    v_sub := (v_e->>'merchandise_subtotal_gnf')::bigint;
    v_del := (v_e->>'delivery_fee_gnf')::bigint;
  ELSE
    IF v_row.state = 'cancelled' THEN
      RETURN jsonb_build_object('status','already_cancelled');
    END IF;
    IF v_row.state IN ('preparing','completed','disputed','dispute_resolved') THEN
      RAISE EXCEPTION 'CASH_ORDER_PREPARATION_LOCKED'
        USING DETAIL = 'Preparation has started; open a dispute instead';
    END IF;
    IF v_row.state = 'merchant_accepted' THEN
      RAISE EXCEPTION 'CASH_ORDER_ALREADY_FUNDED'
        USING DETAIL = 'Merchandise funding is secured; open a dispute instead';
    END IF;
    v_stage := 'after_dispatch';
    v_snap := v_row.policy_snapshot;
    v_sub := v_row.merchandise_subtotal_gnf;
    v_del := v_row.delivery_fee_gnf;
  END IF;

  v_debt := public._customer_cancellation_debt_create_internal(
    p_source_module, p_source_id, v_caller, v_f->>'mission_type', v_stage,
    0, v_sub, v_del, false, 'customer', false, v_snap, v_caller);

  IF v_row.id IS NOT NULL THEN
    v_rel := public._driver_mission_hold_release_internal(
      p_source_module, p_source_id, NULL,
      COALESCE(p_reason,'customer_cancelled'), v_caller);
    UPDATE public.merchant_payables
       SET state = 'cancelled', updated_at = now()
     WHERE source_module = p_source_module AND source_id = p_source_id
       AND state = 'pending_funding' AND funded_gnf = 0;
    UPDATE public.cash_order_runtime
       SET state = 'cancelled', cancelled_at = now() WHERE id = v_row.id;
  END IF;

  IF p_source_module = 'repas' THEN
    UPDATE public.food_orders SET state = 'cancelled'
     WHERE id = p_source_id AND state IN ('placed','confirmed');
  END IF;

  RETURN jsonb_build_object('status','cancelled','stage',v_stage,'debt',v_debt,'release',v_rel);
END; $$;

-- 5.8 Dispute (post-preparation failures)
CREATE OR REPLACE FUNCTION public.cash_order_dispute_open(
  p_source_module text, p_source_id uuid, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_caller uuid := auth.uid(); v_row public.cash_order_runtime;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_row FROM public.cash_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id FOR UPDATE;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'CASH_ORDER_NOT_ACCEPTED'; END IF;
  IF v_caller NOT IN (v_row.customer_user_id, v_row.driver_user_id)
     AND v_caller IS DISTINCT FROM v_row.merchant_user_id
     AND NOT public._finance_privileged(v_caller) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF v_row.state IN ('disputed','dispute_resolved') THEN
    RETURN jsonb_build_object('status','already_disputed','state',v_row.state);
  END IF;
  IF v_row.state NOT IN ('merchant_accepted','preparing','completed') THEN
    RAISE EXCEPTION 'DISPUTE_REQUIRES_FUNDED_ORDER' USING DETAIL = v_row.state;
  END IF;

  UPDATE public.cash_order_runtime
     SET state = 'disputed', disputed_at = now(),
         dispute_reason = p_reason, dispute_opened_by = v_caller
   WHERE id = v_row.id;

  RETURN jsonb_build_object('status','disputed',
    'economic_state','frozen',
    'note','Holds, merchant payable and fees are frozen until an authorized resolution');
END; $$;

-- 5.9 Authorized dispute resolution (Finance / God only)
CREATE OR REPLACE FUNCTION public.admin_cash_order_dispute_resolve(
  p_source_module text, p_source_id uuid, p_outcome text, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_caller uuid := auth.uid(); v_row public.cash_order_runtime; v_res jsonb;
BEGIN
  IF NOT public._finance_privileged(v_caller) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_outcome NOT IN ('complete_as_delivered','release_driver_funding','close_no_value') THEN
    RAISE EXCEPTION 'INVALID_DISPUTE_OUTCOME';
  END IF;

  SELECT * INTO v_row FROM public.cash_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id FOR UPDATE;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'CASH_ORDER_NOT_ACCEPTED'; END IF;
  IF v_row.state = 'dispute_resolved' THEN
    RETURN jsonb_build_object('status','already_resolved','resolution',v_row.dispute_resolution);
  END IF;
  IF v_row.state <> 'disputed' THEN RAISE EXCEPTION 'NOT_IN_DISPUTE' USING DETAIL = v_row.state; END IF;

  IF p_outcome = 'complete_as_delivered' THEN
    v_res := public._cash_order_capture_platform_fee(p_source_module, p_source_id, v_caller);
  ELSIF p_outcome = 'release_driver_funding' THEN
    v_res := public._driver_mission_hold_release_internal(
      p_source_module, p_source_id, NULL, COALESCE(p_reason,'dispute_resolution'), v_caller);
  ELSE
    v_res := jsonb_build_object('status','closed_no_value');
  END IF;

  UPDATE public.cash_order_runtime
     SET state = 'dispute_resolved', resolved_by = v_caller, resolved_at = now(),
         dispute_resolution = jsonb_build_object('outcome',p_outcome,'reason',p_reason,'result',v_res)
   WHERE id = v_row.id;

  INSERT INTO public.audit_logs (actor_user_id, action, entity_type, entity_id, metadata)
  VALUES (v_caller, 'cash_order_dispute_resolved', 'cash_order_runtime', v_row.id,
          jsonb_build_object('outcome',p_outcome,'reason',p_reason,'result',v_res));

  RETURN jsonb_build_object('status','resolved','outcome',p_outcome,'result',v_res);
END; $$;

-- ------------------------------------------------------------
-- 6. LEAST-PRIVILEGE GRANTS
-- ------------------------------------------------------------

REVOKE ALL ON FUNCTION public._merchant_payable_create_internal(text,uuid,uuid,bigint,bigint,text,jsonb,boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._merchant_payable_fund_internal(text,uuid,uuid,text,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._driver_mission_hold_release_internal(text,uuid,text,text,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._customer_cancellation_debt_create_internal(text,uuid,uuid,text,text,bigint,bigint,bigint,boolean,text,boolean,jsonb,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._cash_order_capture_platform_fee(text,uuid,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._cash_order_facts(text,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._cash_order_economics(jsonb) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public._merchant_payable_create_internal(text,uuid,uuid,bigint,bigint,text,jsonb,boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public._merchant_payable_fund_internal(text,uuid,uuid,text,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._driver_mission_hold_release_internal(text,uuid,text,text,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._customer_cancellation_debt_create_internal(text,uuid,uuid,text,text,bigint,bigint,bigint,boolean,text,boolean,jsonb,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._cash_order_capture_platform_fee(text,uuid,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._cash_order_facts(text,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._cash_order_economics(jsonb) TO service_role;

REVOKE ALL ON FUNCTION public.cash_order_quote(text,uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cash_order_accept(text,uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cash_order_merchant_accept(text,uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cash_order_merchant_reject(text,uuid,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cash_order_merchant_prepare(text,uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cash_order_complete_cash(text,uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cash_order_customer_cancel(text,uuid,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cash_order_dispute_open(text,uuid,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_cash_order_dispute_resolve(text,uuid,text,text) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.cash_order_quote(text,uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cash_order_accept(text,uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cash_order_merchant_accept(text,uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cash_order_merchant_reject(text,uuid,text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cash_order_merchant_prepare(text,uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cash_order_complete_cash(text,uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cash_order_customer_cancel(text,uuid,text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cash_order_dispute_open(text,uuid,text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_cash_order_dispute_resolve(text,uuid,text,text) TO authenticated, service_role;

COMMENT ON TABLE public.cash_order_runtime IS
  'Slice 4: frozen Snapshot v2 economics and money state machine for cash Repas/Marche orders.';