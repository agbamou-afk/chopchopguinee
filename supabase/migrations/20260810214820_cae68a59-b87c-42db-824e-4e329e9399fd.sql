-- =====================================================================
-- SLICE 5 — REPAS / MARCHÉ CHOP PAY ENGINE
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.chop_pay_order_runtime (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_key text NOT NULL UNIQUE,
  source_module text NOT NULL CHECK (source_module IN ('repas','marche')),
  source_id uuid NOT NULL,
  mission_type text NOT NULL CHECK (mission_type IN ('repas','marche')),
  mission_id uuid,
  customer_user_id uuid NOT NULL,
  driver_user_id uuid,
  merchant_store_id uuid,
  merchant_user_id uuid,
  merchandise_subtotal_gnf bigint NOT NULL CHECK (merchandise_subtotal_gnf >= 0),
  delivery_fee_gnf bigint NOT NULL DEFAULT 0 CHECK (delivery_fee_gnf >= 0),
  platform_fee_gnf bigint NOT NULL DEFAULT 0 CHECK (platform_fee_gnf >= 0),
  order_total_gnf bigint NOT NULL CHECK (order_total_gnf >= 0),
  collateral_gnf bigint NOT NULL DEFAULT 0 CHECK (collateral_gnf >= 0),
  policy_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  state text NOT NULL DEFAULT 'authorized' CHECK (state IN
    ('authorized','accepted','merchant_accepted','preparing','completed',
     'cancelled','merchant_rejected','disputed','dispute_resolved')),
  authorized_at timestamptz NOT NULL DEFAULT now(),
  accepted_at timestamptz,
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
  merchant_credited_gnf bigint NOT NULL DEFAULT 0,
  driver_earning_gnf bigint NOT NULL DEFAULT 0,
  platform_revenue_gnf bigint NOT NULL DEFAULT 0,
  cancellation_charge_gnf bigint NOT NULL DEFAULT 0,
  customer_refunded_gnf bigint NOT NULL DEFAULT 0,
  is_sandbox boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (source_module, source_id)
);

GRANT SELECT ON public.chop_pay_order_runtime TO authenticated;
GRANT ALL ON public.chop_pay_order_runtime TO service_role;
ALTER TABLE public.chop_pay_order_runtime ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS chop_pay_runtime_participant_select ON public.chop_pay_order_runtime;
CREATE POLICY chop_pay_runtime_participant_select
  ON public.chop_pay_order_runtime FOR SELECT TO authenticated
  USING (auth.uid() = customer_user_id
      OR auth.uid() = driver_user_id
      OR auth.uid() = merchant_user_id
      OR public._finance_privileged(auth.uid()));

CREATE INDEX IF NOT EXISTS idx_cpr_customer ON public.chop_pay_order_runtime (customer_user_id, state);
CREATE INDEX IF NOT EXISTS idx_cpr_driver ON public.chop_pay_order_runtime (driver_user_id, state);
CREATE INDEX IF NOT EXISTS idx_cpr_merchant ON public.chop_pay_order_runtime (merchant_user_id, state);
CREATE INDEX IF NOT EXISTS idx_cpr_mission ON public.chop_pay_order_runtime (mission_id);

CREATE OR REPLACE FUNCTION public._chop_pay_runtime_immutable()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF NEW.merchandise_subtotal_gnf IS DISTINCT FROM OLD.merchandise_subtotal_gnf
     OR NEW.delivery_fee_gnf IS DISTINCT FROM OLD.delivery_fee_gnf
     OR NEW.platform_fee_gnf IS DISTINCT FROM OLD.platform_fee_gnf
     OR NEW.order_total_gnf IS DISTINCT FROM OLD.order_total_gnf
     OR NEW.policy_snapshot IS DISTINCT FROM OLD.policy_snapshot
     OR NEW.customer_user_id IS DISTINCT FROM OLD.customer_user_id
     OR NEW.merchant_store_id IS DISTINCT FROM OLD.merchant_store_id
     OR NEW.source_module IS DISTINCT FROM OLD.source_module
     OR NEW.source_id IS DISTINCT FROM OLD.source_id
     OR (OLD.driver_user_id IS NOT NULL AND NEW.driver_user_id IS DISTINCT FROM OLD.driver_user_id)
  THEN
    RAISE EXCEPTION 'CHOP_PAY_SNAPSHOT_IMMUTABLE';
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_cpr_immutable ON public.chop_pay_order_runtime;
CREATE TRIGGER trg_cpr_immutable BEFORE UPDATE ON public.chop_pay_order_runtime
  FOR EACH ROW EXECUTE FUNCTION public._chop_pay_runtime_immutable();
DROP TRIGGER IF EXISTS trg_cpr_updated ON public.chop_pay_order_runtime;
CREATE TRIGGER trg_cpr_updated BEFORE UPDATE ON public.chop_pay_order_runtime
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- ---------------------------------------------------------------- facts
CREATE OR REPLACE FUNCTION public._chop_pay_facts(p_source_module text, p_source_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_customer uuid; v_store uuid; v_owner uuid; v_sub bigint := 0;
  v_is_cp boolean := false; v_mixed boolean := false; v_pstate text;
  v_mission public.missions; v_del bigint := 0; v_tender text;
BEGIN
  IF p_source_module = 'repas' THEN
    SELECT fo.user_id, r.merchant_store_id, COALESCE(r.owner_user_id, ms.owner_user_id),
           fo.subtotal_gnf, (fo.payment_method::text = 'choppay'),
           (fo.captured_intent_id IS NOT NULL),
           fo.state::text, fo.payment_method::text
      INTO v_customer, v_store, v_owner, v_sub, v_is_cp, v_mixed, v_pstate, v_tender
      FROM public.food_orders fo
      JOIN public.food_restaurants r ON r.id = fo.restaurant_id
      LEFT JOIN public.merchant_stores ms ON ms.id = r.merchant_store_id
     WHERE fo.id = p_source_id;
    SELECT * INTO v_mission FROM public.missions
     WHERE ref_food_order_id = p_source_id ORDER BY created_at DESC LIMIT 1;
  ELSIF p_source_module = 'marche' THEN
    SELECT mo.buyer_user_id, mo.merchant_store_id, mo.merchant_user_id,
           COALESCE(mo.counter_amount_gnf, mo.offer_amount_gnf),
           (mo.metadata->>'payment_method') = 'choppay',
           (mo.payment_intent_id IS NOT NULL),
           mo.status, mo.metadata->>'payment_method'
      INTO v_customer, v_store, v_owner, v_sub, v_is_cp, v_mixed, v_pstate, v_tender
      FROM public.marketplace_offers mo WHERE mo.id = p_source_id;
    SELECT * INTO v_mission FROM public.missions
     WHERE ref_market_order_id = p_source_id ORDER BY created_at DESC LIMIT 1;
  ELSE
    RAISE EXCEPTION 'UNSUPPORTED_CHOP_PAY_MODULE';
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
    'tender', v_tender,
    'is_chop_pay', COALESCE(v_is_cp,false),
    'mixed_tender', COALESCE(v_mixed,false),
    'product_state', v_pstate,
    'mission_id', v_mission.id,
    'mission_state', v_mission.state::text,
    'courier_id', v_mission.courier_id,
    'pickup_confirmed', v_mission.pickup_confirmed_at IS NOT NULL);
END; $$;

CREATE OR REPLACE FUNCTION public._chop_pay_is_chop_pay(p_source_module text, p_source_id uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_f jsonb;
BEGIN
  IF p_source_module IS NULL OR p_source_id IS NULL THEN RETURN false; END IF;
  BEGIN v_f := public._chop_pay_facts(p_source_module, p_source_id);
  EXCEPTION WHEN OTHERS THEN RETURN false; END;
  RETURN COALESCE((v_f->>'is_chop_pay')::boolean, false);
END; $$;

CREATE OR REPLACE FUNCTION public._chop_pay_economics(p_facts jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_req jsonb; v_snap jsonb; v_sub bigint; v_del bigint; v_fee bigint; v_col bigint;
BEGIN
  v_sub := (p_facts->>'merchandise_subtotal_gnf')::bigint;
  v_del := (p_facts->>'delivery_fee_gnf')::bigint;
  v_req := public.finance_mission_requirement_v2(p_facts->>'mission_type', 0, v_sub, v_del, 0, 'choppay');
  v_fee := COALESCE((v_req->>'platform_fee_gnf')::bigint, 0);
  v_col := COALESCE((v_req->>'collateral_gnf')::bigint, 0);
  IF COALESCE((v_req->>'cash_funding_gnf')::bigint,0) <> 0 THEN
    RAISE EXCEPTION 'CHOP_PAY_MUST_NOT_FUND_CASH';
  END IF;
  IF COALESCE((v_req->>'commission_gnf')::bigint,0) <> 0 THEN
    RAISE EXCEPTION 'CHOP_PAY_NO_DELIVERY_COMMISSION';
  END IF;
  v_snap := public.finance_policy_snapshot(p_facts->>'mission_type', now(), 'chop_pay', 0, v_sub, v_del, 0, false);
  RETURN jsonb_build_object(
    'merchandise_subtotal_gnf', v_sub,
    'delivery_fee_gnf', v_del,
    'platform_fee_gnf', v_fee,
    'collateral_gnf', v_col,
    'order_total_gnf', v_sub + v_del + v_fee,
    'requirement', v_req,
    'policy_snapshot', v_snap);
END; $$;

-- --------------------------------------------------- customer hold core
CREATE OR REPLACE FUNCTION public._chop_pay_customer_hold_internal(
  p_source_module text, p_source_id uuid, p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_f jsonb; v_e jsonb; v_row public.chop_pay_order_runtime; v_key text;
  v_sub bigint; v_del bigint; v_fee bigint; v_total bigint; v_snap jsonb;
  v_w public.wallets; v_avail bigint; v_tx public.wallet_transactions; v_customer uuid;
BEGIN
  IF NOT public._finance_flag('chop_pay_checkout_enabled') THEN
    RAISE EXCEPTION 'CHOP_PAY_CHECKOUT_DISABLED';
  END IF;
  v_key := format('%s:%s', p_source_module, p_source_id);
  PERFORM pg_advisory_xact_lock(hashtextextended('choppay:'||v_key, 0));

  SELECT * INTO v_row FROM public.chop_pay_order_runtime WHERE order_key = v_key FOR UPDATE;
  IF v_row.id IS NOT NULL THEN
    RETURN jsonb_build_object('status','already_authorized','runtime_id',v_row.id,
                              'state',v_row.state,'order_total_gnf',v_row.order_total_gnf);
  END IF;

  v_f := public._chop_pay_facts(p_source_module, p_source_id);
  IF NOT (v_f->>'is_chop_pay')::boolean THEN RAISE EXCEPTION 'CHOP_PAY_TENDER_REQUIRED'; END IF;
  IF (v_f->>'mixed_tender')::boolean THEN RAISE EXCEPTION 'MIXED_TENDER_NOT_SUPPORTED'; END IF;
  IF (v_f->>'merchant_store_id') IS NULL THEN RAISE EXCEPTION 'MERCHANT_STORE_MISSING'; END IF;
  IF (v_f->>'mission_id') IS NULL THEN
    RAISE EXCEPTION 'CHOP_PAY_DELIVERY_NOT_READY'
      USING DETAIL = 'delivery mission must exist so the delivery fee is part of the hold';
  END IF;
  v_customer := (v_f->>'customer_user_id')::uuid;

  v_e := public._chop_pay_economics(v_f);
  v_sub := (v_e->>'merchandise_subtotal_gnf')::bigint;
  v_del := (v_e->>'delivery_fee_gnf')::bigint;
  v_fee := (v_e->>'platform_fee_gnf')::bigint;
  v_total := (v_e->>'order_total_gnf')::bigint;
  v_snap := v_e->'policy_snapshot';
  IF v_sub <= 0 THEN RAISE EXCEPTION 'INVALID_MERCHANDISE_SUBTOTAL'; END IF;

  INSERT INTO public.wallets (owner_user_id, party_type) VALUES (v_customer,'client')
  ON CONFLICT (owner_user_id, party_type) DO NOTHING;
  SELECT * INTO v_w FROM public.wallets
   WHERE owner_user_id = v_customer AND party_type = 'client' FOR UPDATE;
  IF v_w.status <> 'active' THEN RAISE EXCEPTION 'WALLET_NOT_ACTIVE'; END IF;
  v_avail := GREATEST(v_w.balance_gnf - v_w.held_gnf, 0);
  IF v_avail < v_total THEN
    RAISE EXCEPTION 'INSUFFICIENT_CHOP_PAY_BALANCE'
      USING DETAIL = format('required=%s available=%s', v_total, v_avail);
  END IF;

  INSERT INTO public.wallet_transactions
    (reference, type, status, amount_gnf, from_wallet_id, related_user_id,
     related_entity, description, metadata)
  VALUES (format('cph:%s:%s:customer_payment', p_source_module, p_source_id),
     'hold','pending', v_total, v_w.id, v_customer,
     p_source_module || ':' || p_source_id::text,
     'Réservation Chop Pay (commande complète)',
     jsonb_build_object('mission_type', v_f->>'mission_type','kind','customer_payment',
                        'merchandise_gnf',v_sub,'delivery_gnf',v_del,'platform_fee_gnf',v_fee))
  RETURNING * INTO v_tx;

  UPDATE public.wallets SET held_gnf = held_gnf + v_total, updated_at = now() WHERE id = v_w.id;

  INSERT INTO public.mission_financial_holds
    (driver_user_id, party_type, party_user_id, mission_type, source_module, source_id, kind,
     amount_gnf, customer_gnf, hold_tx_id, policy_snapshot, basis_value_gnf, is_sandbox, journal_key)
  VALUES (NULL, 'client', v_customer, v_f->>'mission_type', p_source_module, p_source_id,
     'customer_payment', v_total, v_total, v_tx.id, v_snap, v_sub, false,
     format('cph:%s:%s:customer_payment', p_source_module, p_source_id));

  PERFORM public._ledger_post(
    format('cph:%s:%s:customer_payment', p_source_module, p_source_id),
    p_source_module, p_source_id, 'hold_customer_payment',
    jsonb_build_array(
      jsonb_build_object('account','L_CUSTOMER_CHOPPAY','amount_gnf',v_total,
                         'party_type','client','party_user_id',v_customer,'memo','customer chop pay reserved'),
      jsonb_build_object('account','L_CUSTOMER_HOLD','amount_gnf',-v_total,
                         'party_type','client','party_user_id',v_customer,'memo','full order hold')),
    v_f->>'mission_type', p_actor, v_snap, false);

  INSERT INTO public.chop_pay_order_runtime
    (order_key, source_module, source_id, mission_type, mission_id, customer_user_id,
     merchant_store_id, merchant_user_id, merchandise_subtotal_gnf, delivery_fee_gnf,
     platform_fee_gnf, order_total_gnf, policy_snapshot, state)
  VALUES (v_key, p_source_module, p_source_id, v_f->>'mission_type',
          (v_f->>'mission_id')::uuid, v_customer,
          (v_f->>'merchant_store_id')::uuid, (v_f->>'merchant_user_id')::uuid,
          v_sub, v_del, v_fee, v_total, v_snap, 'authorized')
  RETURNING * INTO v_row;

  RETURN jsonb_build_object('status','authorized','runtime_id',v_row.id,
    'merchandise_subtotal_gnf',v_sub,'delivery_fee_gnf',v_del,'platform_fee_gnf',v_fee,
    'order_total_gnf',v_total,'held_gnf',v_total);
END; $$;

-- capture a slice of the customer hold to a recipient
CREATE OR REPLACE FUNCTION public._chop_pay_customer_capture_internal(
  p_source_module text, p_source_id uuid, p_amount bigint, p_purpose text, p_actor uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_h public.mission_financial_holds; v_open bigint; v_cw public.wallets;
  v_row public.chop_pay_order_runtime; v_target uuid; v_target_wallet public.wallets;
  v_key text; v_account text; v_desc text; v_ttype public.party_type;
BEGIN
  IF p_purpose NOT IN ('merchandise','delivery','platform_fee','cancellation_fee') THEN
    RAISE EXCEPTION 'INVALID_CAPTURE_PURPOSE';
  END IF;
  IF COALESCE(p_amount,0) <= 0 THEN
    RETURN jsonb_build_object('status','zero','captured_gnf',0);
  END IF;

  SELECT * INTO v_row FROM public.chop_pay_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'CHOP_PAY_NOT_AUTHORIZED'; END IF;

  v_key := format('cph-capture:%s:%s:%s', p_source_module, p_source_id, p_purpose);
  IF EXISTS (SELECT 1 FROM public.ledger_journals WHERE journal_key = v_key) THEN
    RETURN jsonb_build_object('status','already_captured','captured_gnf',0);
  END IF;

  SELECT * INTO v_h FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND kind = 'customer_payment' FOR UPDATE;
  IF v_h.id IS NULL THEN RAISE EXCEPTION 'CHOP_PAY_HOLD_MISSING'; END IF;
  v_open := v_h.amount_gnf - v_h.captured_gnf - v_h.released_gnf;
  IF v_open < p_amount THEN
    RAISE EXCEPTION 'CHOP_PAY_HOLD_INSUFFICIENT'
      USING DETAIL = format('open=%s requested=%s', v_open, p_amount);
  END IF;

  SELECT * INTO v_cw FROM public.wallets
   WHERE owner_user_id = v_row.customer_user_id AND party_type = 'client' FOR UPDATE;
  UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - p_amount,0),
                            balance_gnf = balance_gnf - p_amount, updated_at = now()
   WHERE id = v_cw.id;

  IF p_purpose = 'merchandise' THEN
    v_target := v_row.merchant_user_id; v_ttype := 'merchant';
    v_account := 'L_MERCHANT_PAYABLE'; v_desc := 'Règlement marchandise Chop Pay';
  ELSIF p_purpose = 'delivery' THEN
    v_target := v_row.driver_user_id; v_ttype := 'driver';
    v_account := 'L_DRIVER_UNRESTRICTED'; v_desc := 'Gain de livraison Chop Pay';
  ELSIF p_purpose = 'platform_fee' THEN
    v_target := NULL; v_ttype := NULL;
    v_account := 'R_TRANSACTION_FEE'; v_desc := 'Frais de transaction CHOPCHOP';
  ELSE
    v_target := NULL; v_ttype := NULL;
    v_account := 'R_CANCELLATION_FEE'; v_desc := 'Frais d''annulation Chop Pay';
  END IF;

  IF v_target IS NOT NULL THEN
    INSERT INTO public.wallets (owner_user_id, party_type) VALUES (v_target, v_ttype)
    ON CONFLICT (owner_user_id, party_type) DO NOTHING;
    UPDATE public.wallets SET balance_gnf = balance_gnf + p_amount, updated_at = now()
     WHERE owner_user_id = v_target AND party_type = v_ttype
     RETURNING * INTO v_target_wallet;
  ELSE
    SELECT * INTO v_target_wallet FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;
    IF v_target_wallet.id IS NOT NULL THEN
      UPDATE public.wallets SET balance_gnf = balance_gnf + p_amount, updated_at = now()
       WHERE id = v_target_wallet.id;
    END IF;
  END IF;

  INSERT INTO public.wallet_transactions
    (reference, type, status, amount_gnf, from_wallet_id, to_wallet_id, related_user_id,
     related_entity, description, metadata, completed_at)
  VALUES (v_key, 'capture','completed', p_amount, v_cw.id, v_target_wallet.id,
     v_row.customer_user_id, p_source_module || ':' || p_source_id::text, v_desc,
     jsonb_build_object('purpose',p_purpose,'mission_type',v_row.mission_type,
                        'tender','chop_pay','is_sandbox',v_row.is_sandbox), now());

  PERFORM public._ledger_post(v_key, p_source_module, p_source_id, 'capture_customer_'||p_purpose,
    jsonb_build_array(
      jsonb_build_object('account','L_CUSTOMER_HOLD','amount_gnf',p_amount,
                         'party_type','client','party_user_id',v_row.customer_user_id,
                         'memo','consume customer hold'),
      jsonb_build_object('account',v_account,'amount_gnf',-p_amount,
                         'party_type', v_ttype, 'party_user_id', v_target,
                         'merchant_store_id', CASE WHEN p_purpose='merchandise' THEN v_row.merchant_store_id END,
                         'memo', v_desc)),
    v_row.mission_type, p_actor, v_row.policy_snapshot, v_row.is_sandbox);

  UPDATE public.mission_financial_holds
     SET captured_gnf = captured_gnf + p_amount,
         state = CASE WHEN captured_gnf + p_amount + released_gnf >= amount_gnf
                      THEN 'captured' ELSE 'partially_captured' END,
         resolved_at = CASE WHEN captured_gnf + p_amount + released_gnf >= amount_gnf
                            THEN now() ELSE resolved_at END
   WHERE id = v_h.id;

  UPDATE public.wallet_transactions SET status = 'completed', completed_at = now()
   WHERE id = v_h.hold_tx_id AND status = 'pending'
     AND (SELECT captured_gnf + released_gnf >= amount_gnf
            FROM public.mission_financial_holds WHERE id = v_h.id);

  RETURN jsonb_build_object('status','captured','captured_gnf',p_amount,'purpose',p_purpose);
END; $$;

CREATE OR REPLACE FUNCTION public._chop_pay_customer_release_internal(
  p_source_module text, p_source_id uuid, p_reason text DEFAULT NULL, p_actor uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_h public.mission_financial_holds; v_open bigint; v_cw public.wallets;
  v_row public.chop_pay_order_runtime;
BEGIN
  SELECT * INTO v_row FROM public.chop_pay_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'CHOP_PAY_NOT_AUTHORIZED'; END IF;

  SELECT * INTO v_h FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND kind = 'customer_payment' FOR UPDATE;
  IF v_h.id IS NULL THEN RETURN jsonb_build_object('status','no_hold','released_gnf',0); END IF;
  v_open := v_h.amount_gnf - v_h.captured_gnf - v_h.released_gnf;
  IF v_open <= 0 THEN RETURN jsonb_build_object('status','already_resolved','released_gnf',0); END IF;

  SELECT * INTO v_cw FROM public.wallets
   WHERE owner_user_id = v_row.customer_user_id AND party_type = 'client' FOR UPDATE;
  UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - v_open, 0), updated_at = now()
   WHERE id = v_cw.id;
  UPDATE public.wallet_transactions SET status = 'cancelled', completed_at = now()
   WHERE id = v_h.hold_tx_id AND status = 'pending';

  PERFORM public._ledger_post(
    format('cph-release:%s:%s:customer_payment', p_source_module, p_source_id),
    p_source_module, p_source_id, 'release_customer_payment',
    jsonb_build_array(
      jsonb_build_object('account','L_CUSTOMER_HOLD','amount_gnf',v_open,
                         'party_type','client','party_user_id',v_row.customer_user_id,'memo','release customer hold'),
      jsonb_build_object('account','L_CUSTOMER_CHOPPAY','amount_gnf',-v_open,
                         'party_type','client','party_user_id',v_row.customer_user_id,'memo','restored to chop pay balance')),
    v_row.mission_type, p_actor, v_row.policy_snapshot, v_row.is_sandbox, p_reason);

  UPDATE public.mission_financial_holds
     SET released_gnf = released_gnf + v_open,
         state = CASE WHEN captured_gnf > 0 THEN 'captured' ELSE 'released' END,
         reason = COALESCE(p_reason, reason), resolved_at = now(), resolved_by = p_actor
   WHERE id = v_h.id;

  RETURN jsonb_build_object('status','released','released_gnf',v_open);
END; $$;

-- reverse an already-captured merchandise payment back to the customer
CREATE OR REPLACE FUNCTION public._chop_pay_merchant_capture_reverse_internal(
  p_source_module text, p_source_id uuid, p_reason text, p_actor uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row public.chop_pay_order_runtime; v_p public.merchant_payables;
  v_amount bigint; v_mw public.wallets; v_cw public.wallets; v_key text;
BEGIN
  SELECT * INTO v_row FROM public.chop_pay_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'CHOP_PAY_NOT_AUTHORIZED'; END IF;

  SELECT * INTO v_p FROM public.merchant_payables
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND merchant_store_id = v_row.merchant_store_id FOR UPDATE;
  IF v_p.id IS NULL THEN RETURN jsonb_build_object('status','no_payable','reversed_gnf',0); END IF;
  IF v_p.state = 'reversed' THEN RETURN jsonb_build_object('status','already_reversed','reversed_gnf',0); END IF;
  IF v_p.funded_gnf = 0 THEN
    UPDATE public.merchant_payables
       SET state='reversed', reason=COALESCE(p_reason,reason), resolved_at=now(),
           resolved_by=p_actor, updated_at=now()
     WHERE id = v_p.id;
    RETURN jsonb_build_object('status','not_funded','reversed_gnf',0);
  END IF;
  IF v_p.funding_source <> 'customer_choppay' THEN
    RETURN jsonb_build_object('status','reconciliation_required','reversed_gnf',0,
                              'detail','funding source is not customer chop pay');
  END IF;
  IF v_p.settled_gnf > 0 OR v_p.state IN ('settled','settlement_held') THEN
    RETURN jsonb_build_object('status','reconciliation_required','reversed_gnf',0,
                              'detail','payable already settled externally');
  END IF;

  v_amount := v_p.funded_gnf;
  SELECT * INTO v_mw FROM public.wallets
   WHERE owner_user_id = v_p.merchant_user_id AND party_type = 'merchant' FOR UPDATE;
  IF v_mw.id IS NULL OR (v_mw.balance_gnf - v_mw.held_gnf) < v_amount THEN
    RETURN jsonb_build_object('status','reconciliation_required','reversed_gnf',0,
                              'detail','insufficient recoverable merchant liability');
  END IF;
  SELECT * INTO v_cw FROM public.wallets
   WHERE owner_user_id = v_row.customer_user_id AND party_type = 'client' FOR UPDATE;
  IF v_cw.id IS NULL THEN
    RETURN jsonb_build_object('status','reconciliation_required','reversed_gnf',0,
                              'detail','customer wallet missing');
  END IF;

  UPDATE public.wallets SET balance_gnf = balance_gnf - v_amount, updated_at = now() WHERE id = v_mw.id;
  UPDATE public.wallets SET balance_gnf = balance_gnf + v_amount, updated_at = now() WHERE id = v_cw.id;

  v_key := format('cph-payable-reverse:%s:%s:%s', p_source_module, p_source_id, v_row.merchant_store_id);
  INSERT INTO public.wallet_transactions
    (reference, type, status, amount_gnf, from_wallet_id, to_wallet_id, related_user_id,
     related_entity, description, metadata, completed_at)
  VALUES (v_key, 'adjustment','completed', v_amount, v_mw.id, v_cw.id, v_p.merchant_user_id,
     p_source_module || ':' || p_source_id::text, 'Reprise du règlement marchandise Chop Pay',
     jsonb_build_object('reason',p_reason,'movement','chop_pay_merchant_reversal',
                        'is_sandbox',v_row.is_sandbox), now());

  PERFORM public._ledger_post(v_key, p_source_module, p_source_id, 'chop_pay_merchant_capture_reversed',
    jsonb_build_array(
      jsonb_build_object('account','L_MERCHANT_PAYABLE','amount_gnf',v_amount,
                         'party_type','merchant','party_user_id',v_p.merchant_user_id,
                         'merchant_store_id',v_row.merchant_store_id,'memo','reverse merchant liability'),
      jsonb_build_object('account','L_CUSTOMER_CHOPPAY','amount_gnf',-v_amount,
                         'party_type','client','party_user_id',v_row.customer_user_id,
                         'memo','refund merchandise to customer chop pay')),
    v_row.mission_type, p_actor, v_row.policy_snapshot, v_row.is_sandbox, p_reason);

  UPDATE public.merchant_payables
     SET funded_gnf = 0, state='reversed', reason=COALESCE(p_reason,reason),
         resolved_at=now(), resolved_by=p_actor, updated_at=now()
   WHERE id = v_p.id;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (p_actor,'finance','chop_pay_merchant_capture_reversed','merchant_payables', v_p.id::text,
          jsonb_build_object('reversed_gnf',v_amount,'merchant_user_id',v_p.merchant_user_id,
                             'customer_user_id',v_row.customer_user_id), p_reason);

  RETURN jsonb_build_object('status','reversed','reversed_gnf',v_amount);
END; $$;

CREATE OR REPLACE FUNCTION public._chop_pay_deactivate_source(
  p_source_module text, p_source_id uuid, p_mission_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM set_config('chopchop.cash_engine','1',true);
  IF p_source_module = 'repas' THEN
    UPDATE public.food_orders SET state = 'cancelled'
     WHERE id = p_source_id AND state IN ('placed','confirmed','preparing','ready');
  ELSE
    UPDATE public.marketplace_offers SET fulfillment_status = 'cancelled', updated_at = now()
     WHERE id = p_source_id;
  END IF;
  PERFORM set_config('chopchop.cash_engine','0',true);
  UPDATE public.missions SET state = 'failed'
   WHERE id = p_mission_id AND state NOT IN ('delivered','failed');
END; $$;

-- --------------------------------------------- driver acceptance (claim)
CREATE OR REPLACE FUNCTION public._chop_pay_accept_internal(
  p_source_module text, p_source_id uuid, p_driver uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_row public.chop_pay_order_runtime; v_f jsonb; v_hold jsonb; v_col bigint;
BEGIN
  IF p_driver IS NULL THEN RAISE EXCEPTION 'NO_DRIVER'; END IF;
  IF NOT public._finance_flag('chop_pay_checkout_enabled') THEN
    RAISE EXCEPTION 'CHOP_PAY_CHECKOUT_DISABLED';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(format('choppay:%s:%s',p_source_module,p_source_id), 0));

  SELECT * INTO v_row FROM public.chop_pay_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id FOR UPDATE;
  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'CHOP_PAY_NOT_AUTHORIZED'
      USING DETAIL = 'customer full-order hold must be secured before dispatch';
  END IF;
  IF v_row.driver_user_id IS NOT NULL THEN
    RETURN jsonb_build_object('status','already_accepted','runtime_id',v_row.id,
                              'driver_user_id',v_row.driver_user_id,'state',v_row.state);
  END IF;
  IF v_row.state <> 'authorized' THEN RAISE EXCEPTION 'INVALID_STATE' USING DETAIL = v_row.state; END IF;

  v_f := public._chop_pay_facts(p_source_module, p_source_id);
  IF NOT (v_f->>'is_chop_pay')::boolean THEN RAISE EXCEPTION 'CHOP_PAY_TENDER_REQUIRED'; END IF;
  IF (v_f->>'courier_id') IS NULL THEN RAISE EXCEPTION 'NO_ASSIGNED_COURIER'; END IF;
  IF p_driver <> (v_f->>'courier_id')::uuid THEN RAISE EXCEPTION 'NOT_ASSIGNED_DRIVER'; END IF;
  IF (v_f->>'mission_state') <> 'assigned' THEN RAISE EXCEPTION 'STALE_OFFER'; END IF;

  -- Collateral basis is the merchandise subtotal only (frozen at authorization).
  v_hold := public.driver_mission_hold_place(
    v_row.mission_type, p_source_module, p_source_id, 0, p_driver, false,
    ARRAY['collateral'], 0, v_row.merchandise_subtotal_gnf, v_row.delivery_fee_gnf, 0, 'choppay');
  SELECT COALESCE(SUM(amount_gnf),0) INTO v_col FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id AND kind = 'collateral';

  PERFORM public._merchant_payable_create_internal(
    p_source_module, p_source_id, v_row.merchant_store_id,
    v_row.merchandise_subtotal_gnf, 0, v_row.mission_type, v_row.policy_snapshot, false);

  UPDATE public.chop_pay_order_runtime
     SET driver_user_id = p_driver, state = 'accepted', accepted_at = now(),
         collateral_gnf = v_col, mission_id = COALESCE(mission_id,(v_f->>'mission_id')::uuid)
   WHERE id = v_row.id;

  RETURN jsonb_build_object('status','accepted','runtime_id',v_row.id,
    'collateral_gnf',v_col,'order_total_gnf',v_row.order_total_gnf,'hold',v_hold);
END; $$;

-- ------------------------------------------------------ completion core
CREATE OR REPLACE FUNCTION public._chop_pay_complete_internal(
  p_source_module text, p_source_id uuid, p_actor uuid, p_from_dispute boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row public.chop_pay_order_runtime; v_f jsonb; v_p public.merchant_payables;
  v_del jsonb; v_fee jsonb; v_rel jsonb; v_tail jsonb;
BEGIN
  SELECT * INTO v_row FROM public.chop_pay_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id FOR UPDATE;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'CHOP_PAY_NOT_AUTHORIZED'; END IF;
  IF v_row.state = 'completed' THEN
    RETURN jsonb_build_object('status','already_completed','order_total_gnf',v_row.order_total_gnf);
  END IF;
  IF v_row.state = 'disputed' AND NOT p_from_dispute THEN RAISE EXCEPTION 'ORDER_IN_DISPUTE'; END IF;
  IF NOT (v_row.state IN ('preparing','merchant_accepted')
          OR (p_from_dispute AND v_row.state = 'disputed')) THEN
    RAISE EXCEPTION 'INVALID_STATE' USING DETAIL = v_row.state;
  END IF;
  IF p_source_module = 'repas' AND NOT p_from_dispute AND v_row.state <> 'preparing' THEN
    RAISE EXCEPTION 'PREPARATION_REQUIRED_BEFORE_DELIVERY';
  END IF;

  SELECT * INTO v_p FROM public.merchant_payables
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND merchant_store_id = v_row.merchant_store_id;
  IF v_p.id IS NULL OR v_p.funded_gnf < v_p.amount_gnf OR v_p.amount_gnf = 0 THEN
    RAISE EXCEPTION 'MERCHANDISE_FUNDING_NOT_SECURED';
  END IF;

  v_f := public._chop_pay_facts(p_source_module, p_source_id);
  IF NOT COALESCE((v_f->>'pickup_confirmed')::boolean,false) THEN
    RAISE EXCEPTION 'CUSTODY_NOT_ESTABLISHED';
  END IF;
  IF COALESCE(v_f->>'mission_state','') NOT IN ('picked_up','heading_to_dropoff','arrived_dropoff','delivered') THEN
    RAISE EXCEPTION 'INVALID_MISSION_STATE' USING DETAIL = COALESCE(v_f->>'mission_state','none');
  END IF;

  v_del := public._chop_pay_customer_capture_internal(
    p_source_module, p_source_id, v_row.delivery_fee_gnf, 'delivery', p_actor);
  v_fee := public._chop_pay_customer_capture_internal(
    p_source_module, p_source_id, v_row.platform_fee_gnf, 'platform_fee', p_actor);
  -- collateral returns to its original funding buckets; never income
  v_rel := public._driver_mission_hold_release_internal(
    p_source_module, p_source_id, 'collateral', 'chop_pay_completion', p_actor);
  -- nothing may stay encumbered
  v_tail := public._chop_pay_customer_release_internal(
    p_source_module, p_source_id, 'chop_pay_completion_residual', p_actor);

  UPDATE public.chop_pay_order_runtime
     SET state='completed', completed_at = now(),
         driver_earning_gnf = v_row.delivery_fee_gnf,
         platform_revenue_gnf = v_row.platform_fee_gnf,
         merchant_credited_gnf = v_row.merchandise_subtotal_gnf
   WHERE id = v_row.id;

  PERFORM set_config('chopchop.cash_engine','1',true);
  IF p_source_module = 'repas' THEN
    UPDATE public.food_orders SET state='completed', completed_at = now()
     WHERE id = p_source_id AND state <> 'completed';
  ELSE
    UPDATE public.marketplace_offers
       SET fulfillment_status='delivered', fulfilled_at = COALESCE(fulfilled_at, now()),
           completed_at = COALESCE(completed_at, now()), updated_at = now()
     WHERE id = p_source_id;
  END IF;
  PERFORM set_config('chopchop.cash_engine','0',true);

  UPDATE public.missions
     SET state='delivered', dropoff_confirmed_at = COALESCE(dropoff_confirmed_at, now()),
         dropoff_confirmed_by = COALESCE(dropoff_confirmed_by, p_actor)
   WHERE id = v_row.mission_id AND state <> 'delivered';

  RETURN jsonb_build_object('status','completed',
    'customer_captured_gnf', v_row.order_total_gnf,
    'merchant_credited_gnf', v_row.merchandise_subtotal_gnf,
    'driver_earning_gnf', v_row.delivery_fee_gnf,
    'platform_revenue_gnf', v_row.platform_fee_gnf,
    'collateral_release', v_rel, 'delivery_capture', v_del,
    'fee_capture', v_fee, 'residual_release', v_tail,
    'commission_gnf', 0, 'driver_merchandise_advance_gnf', 0);
END; $$;

-- ------------------------------------------------- participant surfaces
CREATE OR REPLACE FUNCTION public.chop_pay_authorize_order(p_source_module text, p_source_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_caller uuid := auth.uid(); v_f jsonb;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  v_f := public._chop_pay_facts(p_source_module, p_source_id);
  IF v_caller <> (v_f->>'customer_user_id')::uuid THEN RAISE EXCEPTION 'Not authorized'; END IF;
  RETURN public._chop_pay_customer_hold_internal(p_source_module, p_source_id, v_caller);
END; $$;

CREATE OR REPLACE FUNCTION public.chop_pay_quote(p_source_module text, p_source_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_caller uuid := auth.uid(); v_f jsonb; v_e jsonb;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  v_f := public._chop_pay_facts(p_source_module, p_source_id);
  IF v_caller NOT IN ((v_f->>'customer_user_id')::uuid)
     AND v_caller IS DISTINCT FROM (v_f->>'merchant_user_id')::uuid
     AND v_caller IS DISTINCT FROM (v_f->>'courier_id')::uuid
     AND NOT public._finance_privileged(v_caller) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF NOT (v_f->>'is_chop_pay')::boolean THEN
    RETURN jsonb_build_object('is_chop_pay', false, 'tender', v_f->>'tender');
  END IF;
  v_e := public._chop_pay_economics(v_f);
  RETURN v_e || jsonb_build_object('is_chop_pay', true,
    'flag_enabled', public._finance_flag('chop_pay_checkout_enabled'));
END; $$;

CREATE OR REPLACE FUNCTION public.chop_pay_merchant_accept(p_source_module text, p_source_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_caller uuid := auth.uid(); v_row public.chop_pay_order_runtime;
        v_p public.merchant_payables; v_cap jsonb;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_row FROM public.chop_pay_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id FOR UPDATE;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'CHOP_PAY_NOT_AUTHORIZED'; END IF;
  IF v_caller IS DISTINCT FROM v_row.merchant_user_id AND NOT public._finance_privileged(v_caller) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF v_row.state IN ('merchant_accepted','preparing','completed') THEN
    RETURN jsonb_build_object('status','already_accepted','state',v_row.state);
  END IF;
  IF v_row.state <> 'accepted' THEN RAISE EXCEPTION 'INVALID_STATE' USING DETAIL = v_row.state; END IF;

  SELECT * INTO v_p FROM public.merchant_payables
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND merchant_store_id = v_row.merchant_store_id FOR UPDATE;
  IF v_p.id IS NULL THEN RAISE EXCEPTION 'Payable not found'; END IF;
  IF v_p.amount_gnf <> v_row.merchandise_subtotal_gnf THEN
    RAISE EXCEPTION 'MERCHANT_CAPTURE_AMOUNT_MISMATCH';
  END IF;

  IF v_p.funded_gnf < v_p.amount_gnf AND v_p.state = 'pending_funding' THEN
    v_cap := public._chop_pay_customer_capture_internal(
      p_source_module, p_source_id, v_p.amount_gnf - v_p.funded_gnf, 'merchandise', v_caller);
    UPDATE public.merchant_payables
       SET funded_gnf = v_p.amount_gnf, funding_source = 'customer_choppay',
           state = 'funded', updated_at = now()
     WHERE id = v_p.id;
  ELSE
    v_cap := jsonb_build_object('status','already_captured','captured_gnf',0);
  END IF;

  UPDATE public.chop_pay_order_runtime
     SET state='merchant_accepted', funded_at = now(),
         merchant_credited_gnf = v_row.merchandise_subtotal_gnf
   WHERE id = v_row.id;

  PERFORM set_config('chopchop.cash_engine','1',true);
  IF p_source_module = 'repas' THEN
    UPDATE public.food_orders SET state='confirmed' WHERE id = p_source_id AND state = 'placed';
  END IF;
  PERFORM set_config('chopchop.cash_engine','0',true);

  RETURN jsonb_build_object('status','merchant_accepted','capture',v_cap,
    'merchant_credited_gnf', v_row.merchandise_subtotal_gnf,
    'payable_id', v_p.id, 'settlement_state','pending');
END; $$;

CREATE OR REPLACE FUNCTION public.chop_pay_merchant_prepare(p_source_module text, p_source_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_caller uuid := auth.uid(); v_row public.chop_pay_order_runtime;
        v_funded bigint; v_amount bigint; v_col bigint;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_row FROM public.chop_pay_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id FOR UPDATE;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'CHOP_PAY_NOT_AUTHORIZED'; END IF;
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

  SELECT COALESCE(SUM(amount_gnf - captured_gnf - released_gnf),0) INTO v_col
    FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND kind = 'collateral' AND state IN ('held','partially_captured');
  IF v_row.collateral_gnf > 0 AND v_col < v_row.collateral_gnf THEN
    RAISE EXCEPTION 'DRIVER_COLLATERAL_NOT_SECURED';
  END IF;

  UPDATE public.chop_pay_order_runtime SET state='preparing', prep_locked_at = now() WHERE id = v_row.id;

  PERFORM set_config('chopchop.cash_engine','1',true);
  IF p_source_module = 'repas' THEN
    UPDATE public.food_orders SET state='preparing' WHERE id = p_source_id AND state IN ('placed','confirmed');
  END IF;
  PERFORM set_config('chopchop.cash_engine','0',true);

  RETURN jsonb_build_object('status','preparing','customer_cancellation_locked',true);
END; $$;

CREATE OR REPLACE FUNCTION public.chop_pay_merchant_reject(
  p_source_module text, p_source_id uuid, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_caller uuid := auth.uid(); v_row public.chop_pay_order_runtime;
        v_rel jsonb; v_ref jsonb;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_row FROM public.chop_pay_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id FOR UPDATE;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'CHOP_PAY_NOT_AUTHORIZED'; END IF;
  IF v_caller IS DISTINCT FROM v_row.merchant_user_id AND NOT public._finance_privileged(v_caller) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF v_row.state = 'merchant_rejected' THEN RETURN jsonb_build_object('status','already_rejected'); END IF;
  IF v_row.state NOT IN ('authorized','accepted') THEN
    RAISE EXCEPTION 'MERCHANT_REJECTION_AFTER_FUNDING'
      USING DETAIL = 'Use the dispute path once funding or preparation has started';
  END IF;

  v_rel := public._driver_mission_hold_release_internal(
    p_source_module, p_source_id, NULL, COALESCE(p_reason,'merchant_rejected_before_preparation'), v_caller);
  v_ref := public._chop_pay_customer_release_internal(
    p_source_module, p_source_id, COALESCE(p_reason,'merchant_rejected'), v_caller);

  UPDATE public.merchant_payables
     SET state='reversed', reason=COALESCE(p_reason,'merchant_rejected'), updated_at = now()
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND state = 'pending_funding' AND funded_gnf = 0;

  UPDATE public.chop_pay_order_runtime
     SET state='merchant_rejected', cancelled_at = now(),
         customer_refunded_gnf = COALESCE((v_ref->>'released_gnf')::bigint,0),
         dispute_reason = COALESCE(p_reason, dispute_reason)
   WHERE id = v_row.id;

  PERFORM public._chop_pay_deactivate_source(p_source_module, p_source_id, v_row.mission_id);

  RETURN jsonb_build_object('status','merchant_rejected','collateral_release',v_rel,
    'customer_refund',v_ref,'platform_fee_revenue_gnf',0,'driver_earning_gnf',0);
END; $$;

CREATE OR REPLACE FUNCTION public._chop_pay_cancel_internal(
  p_source_module text, p_source_id uuid, p_responsible_party text, p_reason text, p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_row public.chop_pay_order_runtime; v_snap jsonb; v_stage text; v_bps int;
  v_basis bigint; v_charge bigint := 0; v_open bigint; v_rev jsonb;
  v_col jsonb; v_ref jsonb; v_chg jsonb := jsonb_build_object('status','none','captured_gnf',0);
  v_basis_kind text;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(format('choppay:%s:%s',p_source_module,p_source_id), 0));
  SELECT * INTO v_row FROM public.chop_pay_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id FOR UPDATE;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'CHOP_PAY_NOT_AUTHORIZED'; END IF;
  IF v_row.state IN ('cancelled','merchant_rejected') THEN
    RETURN jsonb_build_object('status','already_cancelled');
  END IF;
  IF v_row.state IN ('preparing','completed','disputed','dispute_resolved') THEN
    RAISE EXCEPTION 'CHOP_PAY_PREPARATION_LOCKED'
      USING DETAIL = 'Preparation has started; open a dispute instead';
  END IF;

  v_snap := v_row.policy_snapshot;
  v_stage := CASE WHEN v_row.state = 'authorized' THEN 'before_dispatch' ELSE 'after_dispatch' END;
  v_basis_kind := COALESCE(v_snap->>'cancel_basis','none');
  v_basis := CASE v_basis_kind
    WHEN 'merchandise_plus_delivery' THEN v_row.merchandise_subtotal_gnf + v_row.delivery_fee_gnf
    WHEN 'delivery_fee' THEN v_row.delivery_fee_gnf
    WHEN 'merchandise_subtotal' THEN v_row.merchandise_subtotal_gnf
    ELSE 0 END;
  v_bps := CASE v_stage
    WHEN 'before_dispatch' THEN COALESCE((v_snap->>'cancel_before_dispatch_bps')::int,0)
    ELSE COALESCE((v_snap->>'cancel_after_dispatch_bps')::int,0) END;

  IF p_responsible_party = 'customer' AND public._finance_flag('cancellation_policy_enabled') THEN
    v_charge := (v_basis * v_bps) / 10000;
  ELSE
    v_charge := 0;
  END IF;

  -- Reverse an already-captured merchandise payment before resolving the hold.
  IF v_row.state = 'merchant_accepted' THEN
    v_rev := public._chop_pay_merchant_capture_reverse_internal(
      p_source_module, p_source_id, COALESCE(p_reason,'chop_pay_cancelled'), p_actor);
    IF v_rev->>'status' = 'reconciliation_required' THEN
      RAISE EXCEPTION 'FINANCE_RECONCILIATION_REQUIRED'
        USING DETAIL = COALESCE(v_rev->>'detail','merchant liability not recoverable');
    END IF;
  END IF;

  SELECT GREATEST(amount_gnf - captured_gnf - released_gnf, 0) INTO v_open
    FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id AND kind = 'customer_payment';
  v_charge := LEAST(COALESCE(v_charge,0), COALESCE(v_open,0));

  IF v_charge > 0 THEN
    v_chg := public._chop_pay_customer_capture_internal(
      p_source_module, p_source_id, v_charge, 'cancellation_fee', p_actor);
  END IF;

  v_col := public._driver_mission_hold_release_internal(
    p_source_module, p_source_id, NULL, COALESCE(p_reason,'chop_pay_cancelled'), p_actor);
  v_ref := public._chop_pay_customer_release_internal(
    p_source_module, p_source_id, COALESCE(p_reason,'chop_pay_cancelled'), p_actor);

  UPDATE public.merchant_payables
     SET state='reversed', reason=COALESCE(p_reason,'chop_pay_cancelled'), updated_at = now()
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND state = 'pending_funding' AND funded_gnf = 0;

  UPDATE public.chop_pay_order_runtime
     SET state='cancelled', cancelled_at = now(),
         cancellation_charge_gnf = v_charge,
         merchant_credited_gnf = CASE WHEN v_rev->>'status' = 'reversed' THEN 0 ELSE merchant_credited_gnf END,
         customer_refunded_gnf = COALESCE((v_ref->>'released_gnf')::bigint,0)
                                 + COALESCE((v_rev->>'reversed_gnf')::bigint,0)
   WHERE id = v_row.id;

  PERFORM public._chop_pay_deactivate_source(p_source_module, p_source_id, v_row.mission_id);

  RETURN jsonb_build_object('status','cancelled','stage',v_stage,
    'responsible_party',p_responsible_party,
    'cancel_basis_kind',v_basis_kind,'basis_gnf',v_basis,'applied_bps',v_bps,
    'cancellation_charge_gnf',v_charge,'charge_capture',v_chg,
    'merchant_reversal',v_rev,'collateral_release',v_col,'customer_refund',v_ref,
    'cash_debt_created', false);
END; $$;

CREATE OR REPLACE FUNCTION public.chop_pay_customer_cancel(
  p_source_module text, p_source_id uuid, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_caller uuid := auth.uid(); v_row public.chop_pay_order_runtime;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_row FROM public.chop_pay_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'CHOP_PAY_NOT_AUTHORIZED'; END IF;
  IF v_caller <> v_row.customer_user_id THEN RAISE EXCEPTION 'Not authorized'; END IF;
  RETURN public._chop_pay_cancel_internal(p_source_module, p_source_id, 'customer', p_reason, v_caller);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_chop_pay_cancel(
  p_source_module text, p_source_id uuid, p_responsible_party text, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_caller uuid := auth.uid();
BEGIN
  IF NOT public._finance_privileged(v_caller) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_responsible_party NOT IN ('customer','merchant','driver','platform') THEN
    RAISE EXCEPTION 'Invalid responsible party';
  END IF;
  RETURN public._chop_pay_cancel_internal(p_source_module, p_source_id, p_responsible_party, p_reason, v_caller);
END; $$;

CREATE OR REPLACE FUNCTION public.chop_pay_dispute_open(
  p_source_module text, p_source_id uuid, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_caller uuid := auth.uid(); v_row public.chop_pay_order_runtime;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_row FROM public.chop_pay_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id FOR UPDATE;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'CHOP_PAY_NOT_AUTHORIZED'; END IF;
  IF v_caller NOT IN (v_row.customer_user_id, COALESCE(v_row.driver_user_id, v_caller))
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
  UPDATE public.chop_pay_order_runtime
     SET state='disputed', disputed_at = now(), dispute_reason = p_reason, dispute_opened_by = v_caller
   WHERE id = v_row.id;
  RETURN jsonb_build_object('status','disputed','economic_state','frozen');
END; $$;

CREATE OR REPLACE FUNCTION public.admin_chop_pay_dispute_resolve(
  p_source_module text, p_source_id uuid, p_outcome text, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_caller uuid := auth.uid(); v_row public.chop_pay_order_runtime;
  v_res jsonb; v_rev jsonb; v_col jsonb; v_ref jsonb; v_final text;
BEGIN
  IF NOT public._finance_privileged(v_caller) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_outcome NOT IN ('complete_as_delivered','refund_customer','close_no_value') THEN
    RAISE EXCEPTION 'INVALID_DISPUTE_OUTCOME';
  END IF;

  SELECT * INTO v_row FROM public.chop_pay_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id FOR UPDATE;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'CHOP_PAY_NOT_AUTHORIZED'; END IF;
  IF v_row.dispute_resolution IS NOT NULL THEN
    RETURN jsonb_build_object('status','already_resolved','resolution',v_row.dispute_resolution);
  END IF;
  IF v_row.state <> 'disputed' THEN RAISE EXCEPTION 'NOT_IN_DISPUTE' USING DETAIL = v_row.state; END IF;

  IF p_outcome = 'complete_as_delivered' THEN
    v_res := public._chop_pay_complete_internal(p_source_module, p_source_id, v_caller, true);
    v_final := 'completed';

  ELSIF p_outcome = 'refund_customer' THEN
    v_rev := public._chop_pay_merchant_capture_reverse_internal(
      p_source_module, p_source_id, COALESCE(p_reason,'dispute_refund_customer'), v_caller);
    IF v_rev->>'status' = 'reconciliation_required' THEN
      RAISE EXCEPTION 'FINANCE_RECONCILIATION_REQUIRED'
        USING DETAIL = COALESCE(v_rev->>'detail','merchant liability not recoverable');
    END IF;
    v_col := public._driver_mission_hold_release_internal(
      p_source_module, p_source_id, NULL, COALESCE(p_reason,'dispute_resolution'), v_caller);
    v_ref := public._chop_pay_customer_release_internal(
      p_source_module, p_source_id, COALESCE(p_reason,'dispute_refund_customer'), v_caller);
    v_res := jsonb_build_object('merchant_reversal',v_rev,'collateral_release',v_col,
                                'customer_refund',v_ref,'platform_fee_captured_gnf',0);
    v_final := 'dispute_resolved';
    PERFORM public._chop_pay_deactivate_source(p_source_module, p_source_id, v_row.mission_id);

  ELSE
    v_col := public._driver_mission_hold_release_internal(
      p_source_module, p_source_id, NULL, COALESCE(p_reason,'dispute_close_no_value'), v_caller);
    v_ref := public._chop_pay_customer_release_internal(
      p_source_module, p_source_id, COALESCE(p_reason,'dispute_close_no_value'), v_caller);
    v_res := jsonb_build_object('status','closed_no_value','collateral_release',v_col,
      'customer_hold_release',v_ref,'merchant_principal_change_gnf',0,
      'platform_fee_captured_gnf',0,'driver_earning_gnf',0);
    v_final := 'dispute_resolved';
  END IF;

  UPDATE public.chop_pay_order_runtime
     SET state = v_final, resolved_by = v_caller, resolved_at = now(),
         dispute_resolution = jsonb_build_object('outcome',p_outcome,'reason',p_reason,'result',v_res)
   WHERE id = v_row.id;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (v_caller,'finance','chop_pay_dispute_resolved','chop_pay_order_runtime', v_row.id::text,
          jsonb_build_object('outcome',p_outcome,'result',v_res,'final_state',v_final), p_reason);

  RETURN jsonb_build_object('status','resolved','outcome',p_outcome,'final_state',v_final,'result',v_res);
END; $$;

-- ------------------------------------------ direct-state bypass guard
CREATE OR REPLACE FUNCTION public._chop_pay_block_direct_state()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NEW.state IS DISTINCT FROM OLD.state
     AND COALESCE(current_setting('chopchop.cash_engine', true), '0') <> '1'
     AND (
       NEW.payment_method::text = 'choppay'
       OR EXISTS (SELECT 1 FROM public.chop_pay_order_runtime
                   WHERE source_module = 'repas' AND source_id = NEW.id)
     ) THEN
    RAISE EXCEPTION 'CHOP_PAY_STATE_ENGINE_ONLY'
      USING DETAIL = 'Chop Pay orders must transition through the Chop Pay engine';
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_chop_pay_block_direct_state ON public.food_orders;
CREATE TRIGGER trg_chop_pay_block_direct_state BEFORE UPDATE ON public.food_orders
  FOR EACH ROW EXECUTE FUNCTION public._chop_pay_block_direct_state();

-- --------------------------------- canonical mission lifecycle wiring
CREATE OR REPLACE FUNCTION public.mission_claim(_mission_id uuid)
RETURNS missions LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  _uid uuid := auth.uid();
  _m   public.missions;
  _cs  jsonb;
  _tender text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO _m FROM public.missions WHERE id = _mission_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mission_not_found'; END IF;
  IF _m.courier_id IS NOT NULL THEN RAISE EXCEPTION 'mission_already_claimed'; END IF;
  IF NOT public.driver_has_capability(_uid, public.mission_required_capability(_m.type)) THEN
    RAISE EXCEPTION 'capability_missing';
  END IF;

  IF _m.type = 'marketplace_delivery' AND _m.ref_market_order_id IS NOT NULL THEN
    SELECT mo.metadata->>'payment_method' INTO _tender
      FROM public.marketplace_offers mo WHERE mo.id = _m.ref_market_order_id;
    IF _tender IS NULL OR _tender NOT IN ('cash','choppay') THEN
      RAISE EXCEPTION 'MARCHE_TENDER_REQUIRED'
        USING DETAIL = 'explicit payment method required before courier assignment';
    END IF;
  END IF;

  UPDATE public.missions SET courier_id = _uid WHERE id = _mission_id RETURNING * INTO _m;

  _cs := public._mission_cash_source(_m);
  IF _cs IS NOT NULL THEN
    IF public._cash_order_is_cash(_cs->>'module', (_cs->>'source_id')::uuid) THEN
      PERFORM public._cash_order_accept_internal(_cs->>'module', (_cs->>'source_id')::uuid, _uid);
    ELSIF public._chop_pay_is_chop_pay(_cs->>'module', (_cs->>'source_id')::uuid) THEN
      PERFORM public._chop_pay_accept_internal(_cs->>'module', (_cs->>'source_id')::uuid, _uid);
    END IF;
  END IF;

  UPDATE public.missions SET state = 'heading_to_pickup'
   WHERE id = _mission_id RETURNING * INTO _m;
  RETURN _m;
END; $$;

CREATE OR REPLACE FUNCTION public.mission_confirm_dropoff(_mission_id uuid)
RETURNS missions LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE _uid uuid := auth.uid(); _m public.missions;
        _rt public.cash_order_runtime; _cp public.chop_pay_order_runtime;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO _m FROM public.missions WHERE id = _mission_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mission_not_found'; END IF;
  IF _m.courier_id IS DISTINCT FROM _uid AND NOT public.is_any_admin(_uid) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT * INTO _rt FROM public.cash_order_runtime WHERE mission_id = _mission_id;
  SELECT * INTO _cp FROM public.chop_pay_order_runtime WHERE mission_id = _mission_id;

  UPDATE public.missions
     SET state='delivered', dropoff_confirmed_at=now(), dropoff_confirmed_by=_uid
   WHERE id = _mission_id RETURNING * INTO _m;

  IF _rt.id IS NOT NULL THEN
    PERFORM public._cash_order_complete_internal(_rt.source_module, _rt.source_id, _uid, false);
  ELSIF _cp.id IS NOT NULL THEN
    PERFORM public._chop_pay_complete_internal(_cp.source_module, _cp.source_id, _uid, false);
  ELSE
    BEGIN
      PERFORM public.wallet_credit_mission_earning(_mission_id, 'mission_confirm_dropoff');
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO public.mission_events(mission_id, kind, payload)
      VALUES (_mission_id, 'courier_earning_failed', jsonb_build_object('error', SQLERRM));
    END;
  END IF;
  RETURN _m;
END; $$;

-- ------------------------------------------------- privilege boundaries
REVOKE ALL ON FUNCTION public._chop_pay_customer_hold_internal(text,uuid,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._chop_pay_customer_capture_internal(text,uuid,bigint,text,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._chop_pay_customer_release_internal(text,uuid,text,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._chop_pay_merchant_capture_reverse_internal(text,uuid,text,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._chop_pay_accept_internal(text,uuid,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._chop_pay_complete_internal(text,uuid,uuid,boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._chop_pay_cancel_internal(text,uuid,text,text,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._chop_pay_deactivate_source(text,uuid,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._chop_pay_facts(text,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._chop_pay_economics(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._chop_pay_is_chop_pay(text,uuid) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public._chop_pay_customer_hold_internal(text,uuid,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._chop_pay_customer_capture_internal(text,uuid,bigint,text,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._chop_pay_customer_release_internal(text,uuid,text,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._chop_pay_merchant_capture_reverse_internal(text,uuid,text,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._chop_pay_accept_internal(text,uuid,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._chop_pay_complete_internal(text,uuid,uuid,boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public._chop_pay_cancel_internal(text,uuid,text,text,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._chop_pay_deactivate_source(text,uuid,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._chop_pay_facts(text,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._chop_pay_economics(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public._chop_pay_is_chop_pay(text,uuid) TO service_role;

REVOKE ALL ON FUNCTION public.chop_pay_authorize_order(text,uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.chop_pay_quote(text,uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.chop_pay_merchant_accept(text,uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.chop_pay_merchant_prepare(text,uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.chop_pay_merchant_reject(text,uuid,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.chop_pay_customer_cancel(text,uuid,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.chop_pay_dispute_open(text,uuid,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_chop_pay_dispute_resolve(text,uuid,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_chop_pay_cancel(text,uuid,text,text) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.chop_pay_authorize_order(text,uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.chop_pay_quote(text,uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.chop_pay_merchant_accept(text,uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.chop_pay_merchant_prepare(text,uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.chop_pay_merchant_reject(text,uuid,text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.chop_pay_customer_cancel(text,uuid,text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.chop_pay_dispute_open(text,uuid,text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_chop_pay_dispute_resolve(text,uuid,text,text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_chop_pay_cancel(text,uuid,text,text) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public._chop_pay_runtime_immutable() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._chop_pay_block_direct_state() FROM PUBLIC, anon, authenticated;
