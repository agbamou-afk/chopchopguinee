-- ============================================================
-- R11 ADDENDUM: canonical finance identity bridge for Marché orders.
-- Legacy 'marche' finance identity (cash_order_runtime, chop_pay_order_runtime,
-- payment_intents, merchant_payables) is keyed to marketplace_offers.id.
-- Canonical R3 marche_orders.id is a DIFFERENT identity space. We therefore
-- never key finance lookups on marche_orders.id; we bridge ONLY through an
-- exact, identity-verified source_offer_id.
-- ============================================================

CREATE OR REPLACE FUNCTION public._marche_order_finance_bridge(p_order public.marche_orders)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE v_off public.marketplace_offers;
BEGIN
  IF p_order.source_offer_id IS NULL THEN
    RETURN jsonb_build_object('bridged', false, 'finance_source_id', NULL,
      'reason','NO_SOURCE_OFFER');
  END IF;

  SELECT * INTO v_off FROM public.marketplace_offers WHERE id = p_order.source_offer_id;
  IF v_off.id IS NULL THEN
    RETURN jsonb_build_object('bridged', false, 'finance_source_id', NULL,
      'reason','SOURCE_OFFER_NOT_FOUND');
  END IF;

  -- Exact identity or nothing.
  IF v_off.buyer_user_id IS DISTINCT FROM p_order.buyer_user_id
     OR v_off.merchant_user_id IS DISTINCT FROM p_order.merchant_user_id
     OR (v_off.merchant_store_id IS NOT NULL
         AND v_off.merchant_store_id IS DISTINCT FROM p_order.merchant_store_id) THEN
    RETURN jsonb_build_object('bridged', false, 'finance_source_id', NULL,
      'reason','SOURCE_OFFER_IDENTITY_MISMATCH');
  END IF;

  RETURN jsonb_build_object('bridged', true, 'finance_source_id', v_off.id, 'reason', NULL);
END $fn$;
REVOKE ALL ON FUNCTION public._marche_order_finance_bridge(public.marche_orders) FROM PUBLIC, anon, authenticated;

-- ---------- tender: never invented, never inherited ----------
DROP FUNCTION IF EXISTS public._marche_order_tender(uuid, uuid);

CREATE OR REPLACE FUNCTION public._marche_order_tender(p_order public.marche_orders)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_bridge jsonb := public._marche_order_finance_bridge(p_order);
  v_src uuid; v_cp record; v_cash record; v_pi record;
BEGIN
  IF NOT (v_bridge->>'bridged')::boolean THEN
    RETURN jsonb_build_object(
      'payment_method','unknown', 'payment_connected', false,
      'tender_kind','unknown', 'tender_state', NULL, 'evidence_source', NULL,
      'label','Mode non renseigné', 'recorded', false,
      'reason', v_bridge->>'reason');
  END IF;
  v_src := (v_bridge->>'finance_source_id')::uuid;

  SELECT * INTO v_cp FROM public.chop_pay_order_runtime
   WHERE source_module = 'marche' AND source_id = v_src
   ORDER BY created_at DESC LIMIT 1;
  IF v_cp.source_id IS NOT NULL THEN
    RETURN jsonb_build_object('payment_method','chop_pay','payment_connected', true,
      'tender_kind','chop_pay','tender_state', v_cp.state,
      'evidence_source','chop_pay_order_runtime','label','Chop Pay','recorded', true,
      'finance_source_id', v_src, 'reason', NULL);
  END IF;

  SELECT * INTO v_cash FROM public.cash_order_runtime
   WHERE source_module = 'marche' AND source_id = v_src
   ORDER BY created_at DESC LIMIT 1;
  IF v_cash.source_id IS NOT NULL THEN
    RETURN jsonb_build_object('payment_method','cash','payment_connected', true,
      'tender_kind','cash','tender_state', v_cash.state,
      'evidence_source','cash_order_runtime','label','Espèces','recorded', true,
      'finance_source_id', v_src, 'reason', NULL);
  END IF;

  SELECT * INTO v_pi FROM public.payment_intents
   WHERE source_module = 'marche' AND source_id = v_src
   ORDER BY created_at DESC LIMIT 1;
  IF v_pi.id IS NOT NULL THEN
    RETURN jsonb_build_object('payment_method','payment_intent','payment_connected', true,
      'tender_kind','payment_intent','tender_state', v_pi.state::text,
      'evidence_source','payment_intents',
      'label','Paiement ' || COALESCE(v_pi.provider::text,'—'),'recorded', true,
      'finance_source_id', v_src, 'reason', NULL);
  END IF;

  -- Bridge exists but no payment rail was ever initiated. We say so; we never guess.
  RETURN jsonb_build_object('payment_method','unknown','payment_connected', false,
    'tender_kind','unknown','tender_state', NULL,'evidence_source', NULL,
    'label','Mode non renseigné','recorded', false,
    'finance_source_id', v_src, 'reason','PAYMENT_RAIL_NOT_INITIATED');
END $fn$;
REVOKE ALL ON FUNCTION public._marche_order_tender(public.marche_orders) FROM PUBLIC, anon, authenticated;

-- ---------- money: payable resolved only through verified finance identity ----------
CREATE OR REPLACE FUNCTION public._marche_order_money(p_order public.marche_orders)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_bridge jsonb := public._marche_order_finance_bridge(p_order);
  v_src uuid; p public.merchant_payables;
  v_alloc bigint := 0; v_state text; v_outstanding bigint := 0;
BEGIN
  IF (v_bridge->>'bridged')::boolean THEN
    v_src := (v_bridge->>'finance_source_id')::uuid;
    SELECT * INTO p FROM public.merchant_payables
     WHERE source_module = 'marche' AND source_id = v_src
       AND merchant_store_id = p_order.merchant_store_id;
  END IF;

  IF p.id IS NULL THEN
    RETURN jsonb_build_object(
      'merchandise_subtotal_gnf', p_order.merchandise_subtotal_gnf,
      'merchant_fee_gnf', p_order.merchant_fee_gnf,
      'merchant_payable_gnf', p_order.merchant_payable_gnf,
      'payable_present', false, 'payable_source_id', v_src,
      'payment_connected', COALESCE((v_bridge->>'bridged')::boolean, false),
      'payable_state', NULL, 'payable_amount_gnf', NULL,
      'funded_gnf', 0, 'settled_gnf', 0, 'allocated_gnf', 0, 'outstanding_gnf', NULL,
      'settlement_state','not_yet_payable',
      'settlement_label','Pas encore exigible',
      'reason', COALESCE(v_bridge->>'reason','PAYABLE_NOT_CREATED'),
      'settled', false);
  END IF;

  SELECT COALESCE(sum(a.amount_gnf),0) INTO v_alloc
    FROM public.payout_settlement_allocations a WHERE a.merchant_payable_id = p.id;

  v_outstanding := GREATEST(p.amount_gnf - p.settled_gnf, 0);

  v_state := CASE
    WHEN p.state = 'reversed' THEN 'reversed'
    WHEN p.state = 'disputed' THEN 'disputed'
    WHEN p.amount_gnf > 0 AND p.settled_gnf >= p.amount_gnf THEN 'settled'
    WHEN p.settled_gnf > 0 THEN 'partially_settled'
    WHEN p.state = 'settlement_held' THEN 'settlement_held'
    WHEN p.state = 'pending_funding' THEN 'pending_funding'
    WHEN p.state IN ('funded','due') THEN 'funded_or_due'
    ELSE 'unknown'
  END;

  RETURN jsonb_build_object(
    'merchandise_subtotal_gnf', p_order.merchandise_subtotal_gnf,
    'merchant_fee_gnf', p_order.merchant_fee_gnf,
    'merchant_payable_gnf', p_order.merchant_payable_gnf,
    'payable_present', true, 'payable_id', p.id, 'payable_source_id', v_src,
    'payment_connected', true,
    'payable_state', p.state, 'payable_amount_gnf', p.amount_gnf,
    'funding_source', p.funding_source,
    'funded_gnf', p.funded_gnf, 'settled_gnf', p.settled_gnf,
    'allocated_gnf', v_alloc, 'outstanding_gnf', v_outstanding,
    'settlement_state', v_state,
    'settlement_label', CASE v_state
      WHEN 'reversed' THEN 'Annulé / remboursé'
      WHEN 'disputed' THEN 'En litige'
      WHEN 'settled' THEN 'Réglé'
      WHEN 'partially_settled' THEN 'Partiellement réglé'
      WHEN 'settlement_held' THEN 'Réservé pour règlement'
      WHEN 'pending_funding' THEN 'En attente de financement'
      WHEN 'funded_or_due' THEN 'À régler'
      ELSE 'État non déterminé' END,
    'reason', NULL,
    'settled', (p.amount_gnf > 0 AND p.settled_gnf >= p.amount_gnf));
END $fn$;
REVOKE ALL ON FUNCTION public._marche_order_money(public.marche_orders) FROM PUBLIC, anon, authenticated;

-- ---------- consumers ----------
CREATE OR REPLACE FUNCTION public.marche_merchant_order_ops(p_order_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE caller uuid := auth.uid(); o public.marche_orders; v_items jsonb;
BEGIN
  SELECT * INTO o FROM public.marche_orders WHERE id = p_order_id;
  IF o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  IF NOT public._marche_merchant_ops_authorized(o, caller) THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', i.id, 'listing_id', i.listing_id, 'title', i.title_snapshot,
           'category', i.category_snapshot,
           'qty', i.qty, 'unit_price_gnf', i.unit_price_gnf,
           'line_total_gnf', i.line_total_gnf) ORDER BY i.created_at), '[]'::jsonb)
    INTO v_items FROM public.marche_order_items i WHERE i.order_id = o.id;

  RETURN jsonb_build_object(
    'order_id', o.id,
    'status', o.status,
    'fulfillment_state', o.fulfillment_state,
    'ops_bucket', public._marche_order_ops_bucket(o),
    'allowed_actions', to_jsonb(public._marche_merchant_allowed_actions(o)),
    'courier_assigned', (o.mission_id IS NOT NULL),
    'item_count', o.item_count,
    'line_count', o.line_count,
    'items', v_items,
    'delivery_address', o.delivery_address,
    'created_at', o.created_at,
    'accepted_at', o.accepted_at,
    'ready_at', o.ready_at,
    'delivered_at', o.delivered_at,
    'rejected_at', o.rejected_at,
    'cancelled_at', o.cancelled_at,
    'tender', public._marche_order_tender(o),
    'money', public._marche_order_money(o));
END $fn$;

CREATE OR REPLACE FUNCTION public.marche_order_settlement_receipt(p_order_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  caller uuid := auth.uid(); o public.marche_orders; p public.merchant_payables;
  v_allocs jsonb; v_money jsonb; v_bridge jsonb;
BEGIN
  SELECT * INTO o FROM public.marche_orders WHERE id = p_order_id;
  IF o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  IF NOT public._marche_merchant_ops_authorized(o, caller) THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;

  v_money := public._marche_order_money(o);
  v_bridge := public._marche_order_finance_bridge(o);

  IF (v_bridge->>'bridged')::boolean THEN
    SELECT * INTO p FROM public.merchant_payables
     WHERE source_module='marche' AND source_id=(v_bridge->>'finance_source_id')::uuid
       AND merchant_store_id=o.merchant_store_id;
  END IF;

  IF p.id IS NULL THEN
    RETURN jsonb_build_object('order_id', o.id, 'receipt_available', false,
      'settled', false, 'money', v_money,
      'message','Aucune créance marchande n''existe encore pour cette commande.');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'allocation_id', a.id,
      'amount_gnf', a.amount_gnf,
      'allocated_at', a.created_at,
      'payout_order_id', po.id,
      'payout_status', po.status,
      'provider', po.provider,
      'destination_msisdn', po.destination_msisdn,
      'settled_at', po.settled_at,
      'provider_reference', ev.provider_reference,
      'provider_status', ev.provider_status,
      'evidence_state', ev.reconciliation_state,
      'transferred_at', ev.transferred_at,
      'evidence_backed', (ev.id IS NOT NULL AND ev.reconciliation_state = 'reconciled')
    ) ORDER BY a.created_at), '[]'::jsonb)
   INTO v_allocs
   FROM public.payout_settlement_allocations a
   JOIN public.payout_orders po ON po.id = a.payout_order_id
   LEFT JOIN LATERAL (
     SELECT e.* FROM public.payout_provider_evidence e
      WHERE e.payout_order_id = po.id
      ORDER BY (e.reconciliation_state = 'reconciled') DESC, e.created_at DESC LIMIT 1) ev ON true
   WHERE a.merchant_payable_id = p.id;

  RETURN jsonb_build_object(
    'order_id', o.id,
    'payable_id', p.id,
    'receipt_available', jsonb_array_length(v_allocs) > 0,
    'settled', (v_money->>'settled')::boolean,
    'money', v_money,
    'allocations', v_allocs);
END $fn$;

CREATE OR REPLACE FUNCTION public.marche_finance_order_audit(p_order_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  caller uuid := auth.uid();
  o public.marche_orders; p public.merchant_payables; v_bridge jsonb; v_src uuid;
  v_alloc bigint := 0; v_unproven bigint := 0; v_codes text[] := ARRAY[]::text[];
BEGIN
  IF NOT public._finance_privileged(caller) THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  SELECT * INTO o FROM public.marche_orders WHERE id = p_order_id;
  IF o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;

  v_bridge := public._marche_order_finance_bridge(o);
  IF (v_bridge->>'bridged')::boolean THEN
    v_src := (v_bridge->>'finance_source_id')::uuid;
    SELECT * INTO p FROM public.merchant_payables
     WHERE source_module='marche' AND source_id=v_src AND merchant_store_id=o.merchant_store_id;
  END IF;

  -- A payable keyed to the canonical order id is NOT canonical finance identity.
  IF EXISTS (SELECT 1 FROM public.merchant_payables
              WHERE source_module='marche' AND source_id=o.id) THEN
    v_codes := v_codes || 'PAYABLE_KEYED_TO_ORDER_ID_NOT_CANONICAL'::text;
  END IF;

  IF p.id IS NULL THEN
    IF o.fulfillment_state = 'delivered' THEN
      IF (v_bridge->>'bridged')::boolean THEN
        v_codes := v_codes || 'PAYABLE_MISSING_AFTER_DELIVERY'::text;
      ELSE
        v_codes := v_codes || 'DELIVERED_WITHOUT_PAYMENT_RAIL'::text;
      END IF;
    END IF;
  ELSE
    SELECT COALESCE(sum(a.amount_gnf),0) INTO v_alloc
      FROM public.payout_settlement_allocations a WHERE a.merchant_payable_id = p.id;

    IF o.merchant_payable_gnf IS NOT NULL AND p.amount_gnf <> o.merchant_payable_gnf THEN
      v_codes := v_codes || 'ORDER_PAYABLE_AMOUNT_MISMATCH'::text;
    END IF;
    IF p.settled_gnf <> v_alloc THEN
      v_codes := v_codes || 'ALLOCATION_COVERAGE_MISMATCH'::text;
    END IF;
    IF p.settled_gnf > p.funded_gnf AND p.funding_source <> 'platform' THEN
      v_codes := v_codes || 'SETTLED_EXCEEDS_FUNDED'::text;
    END IF;
    IF p.state = 'settled' AND p.settled_gnf < p.amount_gnf THEN
      v_codes := v_codes || 'SETTLED_STATE_WITHOUT_FULL_SETTLEMENT'::text;
    END IF;

    SELECT COALESCE(sum(a.amount_gnf),0) INTO v_unproven
      FROM public.payout_settlement_allocations a
      JOIN public.payout_orders po ON po.id = a.payout_order_id
     WHERE a.merchant_payable_id = p.id
       AND NOT EXISTS (SELECT 1 FROM public.payout_provider_evidence e
                        WHERE e.payout_order_id = po.id AND e.reconciliation_state = 'reconciled');
    IF v_unproven > 0 THEN
      v_codes := v_codes || 'SETTLEMENT_WITHOUT_RECONCILED_EVIDENCE'::text;
    END IF;

    IF EXISTS (SELECT 1 FROM public.payout_settlement_allocations a
                JOIN public.payout_orders po ON po.id = a.payout_order_id
               WHERE a.merchant_payable_id = p.id
                 AND po.status IN ('needs_review','mismatch','rejected')) THEN
      v_codes := v_codes || 'PAYOUT_ORDER_NEEDS_REVIEW'::text;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'order_id', o.id,
    'merchant_store_id', o.merchant_store_id,
    'fulfillment_state', o.fulfillment_state,
    'frozen_merchant_payable_gnf', o.merchant_payable_gnf,
    'frozen_merchant_fee_gnf', o.merchant_fee_gnf,
    'finance_bridge', v_bridge,
    'payable_present', (p.id IS NOT NULL),
    'payable_state', p.state,
    'payable_amount_gnf', p.amount_gnf,
    'funded_gnf', p.funded_gnf,
    'settled_gnf', p.settled_gnf,
    'allocated_gnf', v_alloc,
    'unproven_settled_gnf', v_unproven,
    'tender', public._marche_order_tender(o),
    'mismatch_codes', to_jsonb(v_codes),
    'clean', (array_length(v_codes,1) IS NULL));
END $fn$;
