-- =====================================================================
-- R11 ADDENDUM 2 — courier assignment truth, fail-closed settlement law,
-- evidence-gated receipts, deterministic payable identity bridge.
-- =====================================================================

-- 1. Deterministic payable identity: order-id payable first, then EXACT source offer.
CREATE OR REPLACE FUNCTION public._marche_order_payable_ref(p_order public.marche_orders)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE v_p public.merchant_payables; v_bridge jsonb;
BEGIN
  SELECT * INTO v_p FROM public.merchant_payables
   WHERE source_module = 'marche' AND source_id = p_order.id
     AND merchant_store_id = p_order.merchant_store_id;
  IF v_p.id IS NOT NULL THEN
    RETURN jsonb_build_object('payable_id', v_p.id, 'payable_source_id', p_order.id,
      'payable_identity', 'order_id', 'reason', NULL);
  END IF;

  v_bridge := public._marche_order_finance_bridge(p_order);
  IF NOT COALESCE((v_bridge->>'bridged')::boolean, false) THEN
    RETURN jsonb_build_object('payable_id', NULL, 'payable_source_id', NULL,
      'payable_identity', 'none', 'reason', v_bridge->>'reason');
  END IF;

  SELECT * INTO v_p FROM public.merchant_payables
   WHERE source_module = 'marche'
     AND source_id = (v_bridge->>'finance_source_id')::uuid
     AND merchant_store_id = p_order.merchant_store_id;
  IF v_p.id IS NULL THEN
    RETURN jsonb_build_object('payable_id', NULL,
      'payable_source_id', (v_bridge->>'finance_source_id')::uuid,
      'payable_identity', 'none', 'reason', 'PAYABLE_NOT_CREATED');
  END IF;

  RETURN jsonb_build_object('payable_id', v_p.id,
    'payable_source_id', v_p.source_id, 'payable_identity', 'source_offer', 'reason', NULL);
END $fn$;

REVOKE ALL ON FUNCTION public._marche_order_payable_ref(public.marche_orders)
  FROM PUBLIC, anon, authenticated;

-- 2. Merchant money: fail-closed settlement truth.
CREATE OR REPLACE FUNCTION public._marche_order_money(p_order public.marche_orders)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_ref jsonb := public._marche_order_payable_ref(p_order);
  v_bridge jsonb := public._marche_order_finance_bridge(p_order);
  p public.merchant_payables;
  v_alloc bigint := 0; v_proven bigint := 0; v_state text; v_outstanding bigint;
BEGIN
  IF (v_ref->>'payable_id') IS NOT NULL THEN
    SELECT * INTO p FROM public.merchant_payables WHERE id = (v_ref->>'payable_id')::uuid;
  END IF;

  IF p.id IS NULL THEN
    RETURN jsonb_build_object(
      'merchandise_subtotal_gnf', p_order.merchandise_subtotal_gnf,
      'merchant_fee_gnf', p_order.merchant_fee_gnf,
      'merchant_payable_gnf', p_order.merchant_payable_gnf,
      'payable_present', false,
      'payable_identity', v_ref->>'payable_identity',
      'payable_source_id', v_ref->>'payable_source_id',
      'payment_connected', COALESCE((v_bridge->>'bridged')::boolean, false),
      'payable_state', NULL, 'payable_amount_gnf', NULL,
      'funded_gnf', 0, 'settled_gnf', 0, 'allocated_gnf', 0,
      'proven_settled_gnf', 0, 'outstanding_gnf', NULL,
      'settlement_state','not_yet_payable',
      'settlement_label','Pas encore exigible',
      'reason', COALESCE(v_ref->>'reason', v_bridge->>'reason','PAYABLE_NOT_CREATED'),
      'settled', false);
  END IF;

  SELECT COALESCE(sum(a.amount_gnf),0) INTO v_alloc
    FROM public.payout_settlement_allocations a WHERE a.merchant_payable_id = p.id;

  SELECT COALESCE(sum(a.amount_gnf),0) INTO v_proven
    FROM public.payout_settlement_allocations a
    JOIN public.payout_orders po ON po.id = a.payout_order_id
   WHERE a.merchant_payable_id = p.id
     AND po.status = 'settled'
     AND EXISTS (SELECT 1 FROM public.payout_provider_evidence e
                  WHERE e.payout_order_id = po.id AND e.reconciliation_state = 'reconciled');

  v_state := CASE
    WHEN p.state = 'reversed' THEN 'reversed'
    WHEN p.state = 'disputed' THEN 'disputed'
    -- Counters that are not backed by allocation + reconciled evidence are never money truth.
    WHEN (p.settled_gnf > 0 OR p.state = 'settled')
         AND (p.settled_gnf <> v_alloc OR v_proven < p.settled_gnf) THEN 'verification_required'
    WHEN p.amount_gnf > 0 AND v_proven >= p.amount_gnf THEN 'settled'
    WHEN v_proven > 0 THEN 'partially_settled'
    WHEN p.state = 'settlement_held' THEN 'settlement_held'
    WHEN p.state = 'pending_funding' THEN 'pending_funding'
    WHEN p.state IN ('funded','due') THEN 'funded_or_due'
    ELSE 'unknown'
  END;

  v_outstanding := GREATEST(p.amount_gnf - LEAST(v_proven, p.settled_gnf), 0);

  RETURN jsonb_build_object(
    'merchandise_subtotal_gnf', p_order.merchandise_subtotal_gnf,
    'merchant_fee_gnf', p_order.merchant_fee_gnf,
    'merchant_payable_gnf', p_order.merchant_payable_gnf,
    'payable_present', true, 'payable_id', p.id,
    'payable_identity', v_ref->>'payable_identity',
    'payable_source_id', v_ref->>'payable_source_id',
    'payment_connected', true,
    'payable_state', p.state, 'payable_amount_gnf', p.amount_gnf,
    'funding_source', p.funding_source,
    'funded_gnf', p.funded_gnf, 'settled_gnf', p.settled_gnf,
    'allocated_gnf', v_alloc, 'proven_settled_gnf', v_proven,
    'outstanding_gnf', v_outstanding,
    'settlement_state', v_state,
    'settlement_label', CASE v_state
      WHEN 'reversed' THEN 'Annulé / remboursé'
      WHEN 'disputed' THEN 'En litige'
      WHEN 'verification_required' THEN 'Vérification du règlement'
      WHEN 'settled' THEN 'Réglé'
      WHEN 'partially_settled' THEN 'Partiellement réglé'
      WHEN 'settlement_held' THEN 'Réservé pour règlement'
      WHEN 'pending_funding' THEN 'En attente de financement'
      WHEN 'funded_or_due' THEN 'À régler'
      ELSE 'État non déterminé' END,
    'reason', CASE WHEN v_state = 'verification_required'
                   THEN 'SETTLEMENT_NOT_EVIDENCE_BACKED' ELSE NULL END,
    'settled', (v_state = 'settled'));
END $fn$;

REVOKE ALL ON FUNCTION public._marche_order_money(public.marche_orders)
  FROM PUBLIC, anon, authenticated;

-- 3. Merchant operations read model: courier assignment = linked mission WITH a courier.
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
    'dispatch_requested', (o.mission_id IS NOT NULL),
    'courier_assigned', EXISTS (SELECT 1 FROM public.missions m
                                 WHERE m.id = o.mission_id AND m.courier_id IS NOT NULL),
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

REVOKE ALL ON FUNCTION public.marche_merchant_order_ops(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_merchant_order_ops(uuid) TO authenticated;

-- 4. Receipt: evidence-gated availability + sanitized provider detail.
CREATE OR REPLACE FUNCTION public.marche_order_settlement_receipt(p_order_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  caller uuid := auth.uid(); o public.marche_orders; p public.merchant_payables;
  v_allocs jsonb; v_money jsonb; v_ref jsonb; v_backed int := 0;
BEGIN
  SELECT * INTO o FROM public.marche_orders WHERE id = p_order_id;
  IF o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  IF NOT public._marche_merchant_ops_authorized(o, caller) THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;

  v_money := public._marche_order_money(o);
  v_ref := public._marche_order_payable_ref(o);

  IF (v_ref->>'payable_id') IS NOT NULL THEN
    SELECT * INTO p FROM public.merchant_payables WHERE id = (v_ref->>'payable_id')::uuid;
  END IF;

  IF p.id IS NULL THEN
    RETURN jsonb_build_object('order_id', o.id, 'receipt_available', false,
      'provider_verified', false, 'settled', false, 'money', v_money,
      'allocations', '[]'::jsonb,
      'message','Aucune créance marchande n''existe encore pour cette commande.');
  END IF;

  SELECT COALESCE(jsonb_agg(x.j ORDER BY x.created_at), '[]'::jsonb),
         COALESCE(count(*) FILTER (WHERE x.backed), 0)
    INTO v_allocs, v_backed
  FROM (
    SELECT a.created_at,
           (ev.id IS NOT NULL AND ev.reconciliation_state = 'reconciled'
             AND po.status = 'settled') AS backed,
           jsonb_build_object(
             'allocation_id', a.id,
             'amount_gnf', a.amount_gnf,
             'allocated_at', a.created_at,
             'payout_order_id', po.id,
             'payout_status', po.status,
             'evidence_state', ev.reconciliation_state,
             'evidence_backed', (ev.id IS NOT NULL AND ev.reconciliation_state = 'reconciled'
                                  AND po.status = 'settled'),
             'provider', CASE WHEN ev.reconciliation_state = 'reconciled'
                                AND po.status = 'settled' THEN po.provider END,
             'destination_msisdn', CASE WHEN ev.reconciliation_state = 'reconciled'
                                AND po.status = 'settled' THEN po.destination_msisdn END,
             'settled_at', CASE WHEN ev.reconciliation_state = 'reconciled'
                                AND po.status = 'settled' THEN po.settled_at END,
             'provider_reference', CASE WHEN ev.reconciliation_state = 'reconciled'
                                AND po.status = 'settled' THEN ev.provider_reference END,
             'provider_status', CASE WHEN ev.reconciliation_state = 'reconciled'
                                AND po.status = 'settled' THEN ev.provider_status END,
             'transferred_at', CASE WHEN ev.reconciliation_state = 'reconciled'
                                AND po.status = 'settled' THEN ev.transferred_at END) AS j
      FROM public.payout_settlement_allocations a
      JOIN public.payout_orders po ON po.id = a.payout_order_id
      LEFT JOIN LATERAL (
        SELECT e.* FROM public.payout_provider_evidence e
         WHERE e.payout_order_id = po.id
         ORDER BY (e.reconciliation_state = 'reconciled') DESC, e.created_at DESC LIMIT 1) ev ON true
     WHERE a.merchant_payable_id = p.id
  ) x;

  RETURN jsonb_build_object(
    'order_id', o.id,
    'payable_id', p.id,
    'payable_identity', v_ref->>'payable_identity',
    'receipt_available', (v_backed > 0),
    'provider_verified', (v_backed > 0),
    'settled', COALESCE((v_money->>'settled')::boolean, false),
    'money', v_money,
    'allocations', v_allocs,
    'message', CASE WHEN v_backed = 0
      THEN 'Règlement non encore prouvé par une preuve de paiement vérifiée.' END);
END $fn$;

REVOKE ALL ON FUNCTION public.marche_order_settlement_receipt(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_order_settlement_receipt(uuid) TO authenticated;

-- 5. Finance audit: payable identity aware, array_append everywhere.
CREATE OR REPLACE FUNCTION public.marche_finance_order_audit(p_order_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  caller uuid := auth.uid();
  o public.marche_orders; p public.merchant_payables; v_bridge jsonb; v_ref jsonb;
  v_alloc bigint := 0; v_proven bigint := 0; v_unproven bigint := 0;
  v_codes text[] := ARRAY[]::text[];
BEGIN
  IF NOT public._finance_privileged(caller) THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  SELECT * INTO o FROM public.marche_orders WHERE id = p_order_id;
  IF o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;

  v_bridge := public._marche_order_finance_bridge(o);
  v_ref := public._marche_order_payable_ref(o);
  IF (v_ref->>'payable_id') IS NOT NULL THEN
    SELECT * INTO p FROM public.merchant_payables WHERE id = (v_ref->>'payable_id')::uuid;
  END IF;

  IF p.id IS NULL THEN
    IF o.fulfillment_state = 'delivered' THEN
      IF COALESCE((v_bridge->>'bridged')::boolean, false) THEN
        v_codes := array_append(v_codes, 'PAYABLE_MISSING_AFTER_DELIVERY');
      ELSE
        v_codes := array_append(v_codes, 'DELIVERED_WITHOUT_PAYMENT_RAIL');
      END IF;
    END IF;
  ELSE
    SELECT COALESCE(sum(a.amount_gnf),0) INTO v_alloc
      FROM public.payout_settlement_allocations a WHERE a.merchant_payable_id = p.id;

    SELECT COALESCE(sum(a.amount_gnf),0) INTO v_proven
      FROM public.payout_settlement_allocations a
      JOIN public.payout_orders po ON po.id = a.payout_order_id
     WHERE a.merchant_payable_id = p.id AND po.status = 'settled'
       AND EXISTS (SELECT 1 FROM public.payout_provider_evidence e
                    WHERE e.payout_order_id = po.id AND e.reconciliation_state = 'reconciled');
    v_unproven := GREATEST(v_alloc - v_proven, 0);

    IF o.merchant_payable_gnf IS NOT NULL AND p.amount_gnf <> o.merchant_payable_gnf THEN
      v_codes := array_append(v_codes, 'ORDER_PAYABLE_AMOUNT_MISMATCH');
    END IF;
    IF p.settled_gnf <> v_alloc THEN
      v_codes := array_append(v_codes, 'ALLOCATION_COVERAGE_MISMATCH');
    END IF;
    IF p.settled_gnf > 0 AND v_alloc = 0 THEN
      v_codes := array_append(v_codes, 'PAYABLE_SETTLED_WITHOUT_ALLOCATION');
    END IF;
    IF p.settled_gnf > p.funded_gnf AND p.funding_source <> 'platform' THEN
      v_codes := array_append(v_codes, 'SETTLED_EXCEEDS_FUNDED');
    END IF;
    IF p.state = 'settled' AND p.settled_gnf < p.amount_gnf THEN
      v_codes := array_append(v_codes, 'SETTLED_STATE_WITHOUT_FULL_SETTLEMENT');
    END IF;
    IF v_unproven > 0 OR (p.settled_gnf > 0 AND v_proven < p.settled_gnf) THEN
      v_codes := array_append(v_codes, 'SETTLEMENT_WITHOUT_RECONCILED_EVIDENCE');
    END IF;
    IF EXISTS (SELECT 1 FROM public.payout_settlement_allocations a
                JOIN public.payout_orders po ON po.id = a.payout_order_id
               WHERE a.merchant_payable_id = p.id
                 AND po.status IN ('needs_review','mismatch','rejected')) THEN
      v_codes := array_append(v_codes, 'PAYOUT_ORDER_NEEDS_REVIEW');
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'order_id', o.id,
    'merchant_store_id', o.merchant_store_id,
    'fulfillment_state', o.fulfillment_state,
    'frozen_merchant_payable_gnf', o.merchant_payable_gnf,
    'frozen_merchant_fee_gnf', o.merchant_fee_gnf,
    'finance_bridge', v_bridge,
    'payable_identity', v_ref->>'payable_identity',
    'payable_present', (p.id IS NOT NULL),
    'payable_id', p.id,
    'payable_state', p.state,
    'payable_amount_gnf', p.amount_gnf,
    'funded_gnf', p.funded_gnf,
    'settled_gnf', p.settled_gnf,
    'allocated_gnf', v_alloc,
    'proven_settled_gnf', v_proven,
    'unproven_settled_gnf', v_unproven,
    'tender', public._marche_order_tender(o),
    'mismatch_codes', to_jsonb(v_codes),
    'clean', (array_length(v_codes,1) IS NULL));
END $fn$;

REVOKE ALL ON FUNCTION public.marche_finance_order_audit(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_finance_order_audit(uuid) TO authenticated;