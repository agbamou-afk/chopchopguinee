-- ============================================================
-- NODE 4 · MARCHÉ R11 — MERCHANT OPERATIONS + SETTLEMENT
-- Read-model only. No new tables, no new money mutation paths.
-- One finance truth: merchant_payables + payout_settlement_allocations
-- + payout_orders + payout_provider_evidence, verbatim.
-- ============================================================

-- ---------- A. TENDER TRUTH (fail-closed, never invented) ----------
CREATE OR REPLACE FUNCTION public._marche_order_tender(p_order_id uuid, p_offer_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_cp record; v_cash record; v_pi record;
BEGIN
  SELECT * INTO v_cp FROM public.chop_pay_order_runtime
   WHERE source_module = 'marche' AND source_id IN (p_order_id, p_offer_id)
   ORDER BY (source_id = p_order_id) DESC LIMIT 1;
  IF v_cp.source_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'tender_kind','chop_pay',
      'tender_state', v_cp.state,
      'evidence_source','chop_pay_order_runtime',
      'label','Chop Pay',
      'recorded', true);
  END IF;

  SELECT * INTO v_cash FROM public.cash_order_runtime
   WHERE source_module = 'marche' AND source_id IN (p_order_id, p_offer_id)
   ORDER BY (source_id = p_order_id) DESC LIMIT 1;
  IF v_cash.source_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'tender_kind','cash',
      'tender_state', v_cash.state,
      'evidence_source','cash_order_runtime',
      'label','Espèces',
      'recorded', true);
  END IF;

  SELECT * INTO v_pi FROM public.payment_intents
   WHERE source_module = 'marche' AND source_id = p_order_id
   ORDER BY created_at DESC LIMIT 1;
  IF v_pi.id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'tender_kind','payment_intent',
      'tender_state', v_pi.state::text,
      'evidence_source','payment_intents',
      'label','Paiement ' || COALESCE(v_pi.provider::text,'—'),
      'recorded', true);
  END IF;

  -- No canonical tender record exists. We say so; we never guess.
  RETURN jsonb_build_object(
    'tender_kind','none',
    'tender_state', NULL,
    'evidence_source', NULL,
    'label','Paiement non enregistré',
    'recorded', false);
END $$;

REVOKE ALL ON FUNCTION public._marche_order_tender(uuid,uuid) FROM PUBLIC, anon, authenticated;

-- ---------- B. MONEY / SETTLEMENT TRUTH ----------
CREATE OR REPLACE FUNCTION public._marche_order_money(p_order public.marche_orders)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  p public.merchant_payables;
  v_alloc bigint := 0;
  v_state text;
  v_outstanding bigint := 0;
BEGIN
  SELECT * INTO p FROM public.merchant_payables
   WHERE source_module = 'marche' AND source_id = p_order.id
     AND merchant_store_id = p_order.merchant_store_id;

  IF p.id IS NULL THEN
    RETURN jsonb_build_object(
      'merchandise_subtotal_gnf', p_order.merchandise_subtotal_gnf,
      'merchant_fee_gnf', p_order.merchant_fee_gnf,
      'merchant_payable_gnf', p_order.merchant_payable_gnf,
      'payable_present', false,
      'payable_state', NULL,
      'payable_amount_gnf', NULL,
      'funded_gnf', 0,
      'settled_gnf', 0,
      'allocated_gnf', 0,
      'outstanding_gnf', NULL,
      'settlement_state','not_yet_payable',
      'settlement_label','Pas encore exigible',
      'settled', false);
  END IF;

  SELECT COALESCE(sum(a.amount_gnf),0) INTO v_alloc
    FROM public.payout_settlement_allocations a
   WHERE a.merchant_payable_id = p.id;

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
    'payable_present', true,
    'payable_id', p.id,
    'payable_state', p.state,
    'payable_amount_gnf', p.amount_gnf,
    'funding_source', p.funding_source,
    'funded_gnf', p.funded_gnf,
    'settled_gnf', p.settled_gnf,
    'allocated_gnf', v_alloc,
    'outstanding_gnf', v_outstanding,
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
    'settled', (p.amount_gnf > 0 AND p.settled_gnf >= p.amount_gnf));
END $$;

REVOKE ALL ON FUNCTION public._marche_order_money(public.marche_orders) FROM PUBLIC, anon, authenticated;

-- ---------- C. SERVER-DERIVED ALLOWED ACTIONS (mirror of R5 law) ----------
CREATE OR REPLACE FUNCTION public._marche_merchant_allowed_actions(p_order public.marche_orders)
RETURNS text[]
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE a text[] := ARRAY[]::text[]; st text := p_order.fulfillment_state;
BEGIN
  IF p_order.status <> 'committed' THEN RETURN a; END IF;

  IF st = 'committed' THEN a := a || 'accept';
  ELSIF st = 'accepted' THEN a := a || 'prepare';
  ELSIF st = 'preparing' THEN a := a || 'ready';
  END IF;

  IF st IN ('committed','accepted','preparing','ready') AND p_order.mission_id IS NULL THEN
    a := a || 'reject';
  END IF;

  IF st = 'ready' AND p_order.mission_id IS NULL
     AND NULLIF(btrim(COALESCE(p_order.delivery_address,'')),'') IS NOT NULL THEN
    a := a || 'request_dispatch';
  END IF;

  RETURN a;
END $$;

REVOKE ALL ON FUNCTION public._marche_merchant_allowed_actions(public.marche_orders) FROM PUBLIC, anon, authenticated;

-- ---------- D. AUTHORITY ----------
CREATE OR REPLACE FUNCTION public._marche_merchant_ops_authorized(p_order public.marche_orders, p_caller uuid)
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE s public.merchant_stores;
BEGIN
  IF public._finance_privileged(p_caller) THEN RETURN true; END IF;
  IF p_caller IS NULL THEN RETURN false; END IF;
  SELECT * INTO s FROM public.merchant_stores WHERE id = p_order.merchant_store_id;
  RETURN p_order.merchant_user_id = p_caller OR s.owner_user_id = p_caller;
END $$;

REVOKE ALL ON FUNCTION public._marche_merchant_ops_authorized(public.marche_orders, uuid) FROM PUBLIC, anon, authenticated;

-- ---------- E. OPERATIONS BUCKET ----------
CREATE OR REPLACE FUNCTION public._marche_order_ops_bucket(p_order public.marche_orders)
RETURNS text
LANGUAGE sql IMMUTABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT CASE
    WHEN p_order.status <> 'committed'
      OR p_order.fulfillment_state IN ('rejected','cancelled') THEN 'cancelled'
    WHEN p_order.fulfillment_state = 'delivered' THEN 'completed'
    WHEN p_order.fulfillment_state = 'committed' THEN 'action_required'
    WHEN p_order.fulfillment_state IN ('accepted','preparing') THEN 'preparing'
    ELSE 'in_delivery'
  END
$$;

REVOKE ALL ON FUNCTION public._marche_order_ops_bucket(public.marche_orders) FROM PUBLIC, anon, authenticated;

-- ---------- F. ORDER-LEVEL OPERATIONS READ MODEL ----------
CREATE OR REPLACE FUNCTION public.marche_merchant_order_ops(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE caller uuid := auth.uid(); o public.marche_orders; v_items jsonb;
BEGIN
  SELECT * INTO o FROM public.marche_orders WHERE id = p_order_id;
  IF o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  IF NOT public._marche_merchant_ops_authorized(o, caller) THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', i.id, 'listing_id', i.listing_id, 'title', i.title,
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
    'tender', public._marche_order_tender(o.id, o.source_offer_id),
    'money', public._marche_order_money(o));
END $$;

REVOKE ALL ON FUNCTION public.marche_merchant_order_ops(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_merchant_order_ops(uuid) TO authenticated, service_role;

-- ---------- G. MERCHANT COCKPIT ----------
CREATE OR REPLACE FUNCTION public.marche_merchant_orders_cockpit(
  p_store_id uuid DEFAULT NULL,
  p_bucket text DEFAULT NULL,
  p_limit int DEFAULT 40,
  p_offset int DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  caller uuid := auth.uid();
  v_priv boolean := public._finance_privileged(caller);
  v_limit int := LEAST(GREATEST(COALESCE(p_limit,40),1),100);
  v_offset int := GREATEST(COALESCE(p_offset,0),0);
  v_counts jsonb;
  v_items jsonb;
BEGIN
  IF caller IS NULL AND NOT v_priv THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF p_bucket IS NOT NULL AND p_bucket NOT IN
     ('action_required','preparing','in_delivery','completed','cancelled') THEN
    RAISE EXCEPTION 'UNKNOWN_BUCKET' USING DETAIL = p_bucket;
  END IF;

  CREATE TEMP TABLE IF NOT EXISTS _marche_ops_scope(order_id uuid) ON COMMIT DROP;

  WITH scoped AS (
    SELECT o.* FROM public.marche_orders o
     WHERE (p_store_id IS NULL OR o.merchant_store_id = p_store_id)
       AND public._marche_merchant_ops_authorized(o, caller)
  )
  SELECT jsonb_object_agg(b, n) INTO v_counts FROM (
    SELECT public._marche_order_ops_bucket(s.*) AS b, count(*) AS n
      FROM scoped s GROUP BY 1) q(b,n);

  WITH scoped AS (
    SELECT o.* FROM public.marche_orders o
     WHERE (p_store_id IS NULL OR o.merchant_store_id = p_store_id)
       AND public._marche_merchant_ops_authorized(o, caller)
  ), filtered AS (
    SELECT s.* FROM scoped s
     WHERE p_bucket IS NULL OR public._marche_order_ops_bucket(s.*) = p_bucket
     ORDER BY s.created_at DESC, s.id DESC
     LIMIT v_limit OFFSET v_offset
  )
  SELECT COALESCE(jsonb_agg(public.marche_merchant_order_ops(f.id)
                            ORDER BY f.created_at DESC, f.id DESC), '[]'::jsonb)
    INTO v_items FROM filtered f;

  RETURN jsonb_build_object(
    'counts', COALESCE(v_counts, '{}'::jsonb),
    'bucket', p_bucket,
    'items', COALESCE(v_items, '[]'::jsonb));
END $$;

REVOKE ALL ON FUNCTION public.marche_merchant_orders_cockpit(uuid,text,int,int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_merchant_orders_cockpit(uuid,text,int,int) TO authenticated, service_role;

-- ---------- H. PER-ORDER SETTLEMENT RECEIPT (evidence-backed only) ----------
CREATE OR REPLACE FUNCTION public.marche_order_settlement_receipt(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  caller uuid := auth.uid();
  o public.marche_orders; p public.merchant_payables; v_allocs jsonb; v_money jsonb;
BEGIN
  SELECT * INTO o FROM public.marche_orders WHERE id = p_order_id;
  IF o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  IF NOT public._marche_merchant_ops_authorized(o, caller) THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;

  v_money := public._marche_order_money(o);

  SELECT * INTO p FROM public.merchant_payables
   WHERE source_module='marche' AND source_id=o.id AND merchant_store_id=o.merchant_store_id;

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
      'evidence_state', ev.state,
      'transferred_at', ev.transferred_at,
      'evidence_backed', (ev.id IS NOT NULL AND ev.state = 'reconciled')
    ) ORDER BY a.created_at), '[]'::jsonb)
   INTO v_allocs
   FROM public.payout_settlement_allocations a
   JOIN public.payout_orders po ON po.id = a.payout_order_id
   LEFT JOIN LATERAL (
     SELECT e.* FROM public.payout_provider_evidence e
      WHERE e.payout_order_id = po.id
      ORDER BY (e.state = 'reconciled') DESC, e.created_at DESC LIMIT 1) ev ON true
   WHERE a.merchant_payable_id = p.id;

  RETURN jsonb_build_object(
    'order_id', o.id,
    'payable_id', p.id,
    'receipt_available', jsonb_array_length(v_allocs) > 0,
    'settled', (v_money->>'settled')::boolean,
    'money', v_money,
    'allocations', v_allocs);
END $$;

REVOKE ALL ON FUNCTION public.marche_order_settlement_receipt(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_order_settlement_receipt(uuid) TO authenticated, service_role;

-- ---------- I. FINANCE AUDIT ----------
CREATE OR REPLACE FUNCTION public.marche_finance_order_audit(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  caller uuid := auth.uid();
  o public.marche_orders; p public.merchant_payables;
  v_alloc bigint := 0; v_unproven bigint := 0; v_codes text[] := ARRAY[]::text[];
BEGIN
  IF NOT public._finance_privileged(caller) THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  SELECT * INTO o FROM public.marche_orders WHERE id = p_order_id;
  IF o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;

  SELECT * INTO p FROM public.merchant_payables
   WHERE source_module='marche' AND source_id=o.id AND merchant_store_id=o.merchant_store_id;

  IF p.id IS NULL THEN
    IF o.fulfillment_state = 'delivered' THEN v_codes := v_codes || 'PAYABLE_MISSING_AFTER_DELIVERY'; END IF;
  ELSE
    SELECT COALESCE(sum(a.amount_gnf),0) INTO v_alloc
      FROM public.payout_settlement_allocations a WHERE a.merchant_payable_id = p.id;

    IF o.merchant_payable_gnf IS NOT NULL AND p.amount_gnf <> o.merchant_payable_gnf THEN
      v_codes := v_codes || 'ORDER_PAYABLE_AMOUNT_MISMATCH';
    END IF;
    IF p.settled_gnf <> v_alloc THEN v_codes := v_codes || 'ALLOCATION_COVERAGE_MISMATCH'; END IF;
    IF p.settled_gnf > p.funded_gnf AND p.funding_source <> 'platform' THEN
      v_codes := v_codes || 'SETTLED_EXCEEDS_FUNDED';
    END IF;
    IF p.state = 'settled' AND p.settled_gnf < p.amount_gnf THEN
      v_codes := v_codes || 'SETTLED_STATE_WITHOUT_FULL_SETTLEMENT';
    END IF;

    SELECT COALESCE(sum(a.amount_gnf),0) INTO v_unproven
      FROM public.payout_settlement_allocations a
      JOIN public.payout_orders po ON po.id = a.payout_order_id
     WHERE a.merchant_payable_id = p.id
       AND NOT EXISTS (SELECT 1 FROM public.payout_provider_evidence e
                        WHERE e.payout_order_id = po.id AND e.state = 'reconciled');
    IF v_unproven > 0 THEN v_codes := v_codes || 'SETTLEMENT_WITHOUT_RECONCILED_EVIDENCE'; END IF;

    IF EXISTS (SELECT 1 FROM public.payout_settlement_allocations a
                JOIN public.payout_orders po ON po.id = a.payout_order_id
               WHERE a.merchant_payable_id = p.id
                 AND po.status IN ('needs_review','mismatch','rejected')) THEN
      v_codes := v_codes || 'PAYOUT_ORDER_NEEDS_REVIEW';
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'order_id', o.id,
    'merchant_store_id', o.merchant_store_id,
    'fulfillment_state', o.fulfillment_state,
    'frozen_merchant_payable_gnf', o.merchant_payable_gnf,
    'frozen_merchant_fee_gnf', o.merchant_fee_gnf,
    'payable_present', (p.id IS NOT NULL),
    'payable_state', p.state,
    'payable_amount_gnf', p.amount_gnf,
    'funded_gnf', p.funded_gnf,
    'settled_gnf', p.settled_gnf,
    'allocated_gnf', v_alloc,
    'unproven_settled_gnf', v_unproven,
    'tender', public._marche_order_tender(o.id, o.source_offer_id),
    'mismatch_codes', to_jsonb(v_codes),
    'clean', (array_length(v_codes,1) IS NULL));
END $$;

REVOKE ALL ON FUNCTION public.marche_finance_order_audit(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_finance_order_audit(uuid) TO authenticated, service_role;

-- ---------- J. QA HARNESS ----------
CREATE OR REPLACE FUNCTION public._qa_node4_marche_r11()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  r jsonb := '[]'::jsonb;
  v_buy uuid; v_merch uuid; v_merch2 uuid; v_adm uuid; v_drv uuid;
  v_store uuid; v_store2 uuid; l_a uuid;
  v_res jsonb; v_o1 uuid; v_ops jsonb; v_ck jsonb; v_rc jsonb; v_au jsonb;
  v_err text; v_n int; v_pay uuid; v_po uuid; v_ev uuid;
  v_w0 bigint; v_w1 bigint; v_wt0 bigint; v_wt1 bigint; v_lj0 bigint; v_lj1 bigint;
  v_pi0 bigint; v_pi1 bigint; v_mp0 bigint; v_mp1 bigint; v_ss0 bigint; v_ss1 bigint;
  v_reserved0 bigint; v_reserved1 bigint; v_flags0 jsonb; v_flags1 jsonb;
BEGIN
  SELECT count(*) INTO v_w0 FROM public.wallets;
  SELECT count(*) INTO v_wt0 FROM public.wallet_transactions;
  SELECT count(*) INTO v_lj0 FROM public.ledger_journals;
  SELECT count(*) INTO v_pi0 FROM public.payment_intents;
  SELECT count(*) INTO v_mp0 FROM public.merchant_payables;
  SELECT count(*) INTO v_ss0 FROM public.merchant_settlement_requests;
  SELECT COALESCE(sum(quantity_reserved),0) INTO v_reserved0 FROM public.marketplace_listings;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;

  -- ===== A. STRUCTURAL =====
  r := r || public._qa_s13_ok('N4R11.A1 order ops RPC exists and is definer',
        EXISTS (SELECT 1 FROM pg_proc WHERE proname='marche_merchant_order_ops' AND prosecdef), NULL);
  r := r || public._qa_s13_ok('N4R11.A2 cockpit RPC exists and is definer',
        EXISTS (SELECT 1 FROM pg_proc WHERE proname='marche_merchant_orders_cockpit' AND prosecdef), NULL);
  r := r || public._qa_s13_ok('N4R11.A3 settlement receipt RPC exists and is definer',
        EXISTS (SELECT 1 FROM pg_proc WHERE proname='marche_order_settlement_receipt' AND prosecdef), NULL);
  r := r || public._qa_s13_ok('N4R11.A4 finance audit RPC exists and is definer',
        EXISTS (SELECT 1 FROM pg_proc WHERE proname='marche_finance_order_audit' AND prosecdef), NULL);
  r := r || public._qa_s13_ok('N4R11.A5 every R11 definer pins search_path',
        NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname IN
          ('marche_merchant_order_ops','marche_merchant_orders_cockpit','marche_order_settlement_receipt',
           'marche_finance_order_audit','_marche_order_tender','_marche_order_money',
           '_marche_merchant_allowed_actions','_marche_merchant_ops_authorized','_marche_order_ops_bucket')
          AND NOT (COALESCE(array_to_string(proconfig,','),'') LIKE '%search_path=public%')), NULL);
  r := r || public._qa_s13_ok('N4R11.A6 anon cannot execute any R11 RPC',
        NOT has_function_privilege('anon','public.marche_merchant_order_ops(uuid)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_merchant_orders_cockpit(uuid,text,integer,integer)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_order_settlement_receipt(uuid)','EXECUTE')
    AND NOT has_function_privilege('anon','public.marche_finance_order_audit(uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R11.A7 R11 internals are not client-callable',
        NOT has_function_privilege('authenticated','public._marche_order_money(public.marche_orders)','EXECUTE')
    AND NOT has_function_privilege('authenticated','public._marche_order_tender(uuid,uuid)','EXECUTE')
    AND NOT has_function_privilege('authenticated','public._marche_merchant_allowed_actions(public.marche_orders)','EXECUTE')
    AND NOT has_function_privilege('authenticated','public._marche_merchant_ops_authorized(public.marche_orders,uuid)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R11.A8 finance tables stay RPC-only for clients',
        NOT has_table_privilege('authenticated','public.merchant_payables','SELECT')
    AND NOT has_table_privilege('authenticated','public.payout_settlement_allocations','SELECT')
    AND NOT has_table_privilege('anon','public.merchant_payables','SELECT'), NULL);
  r := r || public._qa_s13_ok('N4R11.A9 R11 created no parallel finance table',
        (SELECT count(*) FROM information_schema.tables WHERE table_schema='public'
          AND (table_name LIKE 'marche_payable%' OR table_name LIKE 'marche_settlement%'
               OR table_name LIKE 'marche_payout%')) = 0, NULL);
  r := r || public._qa_s13_ok('N4R11.A10 read models perform no writes',
        NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname IN
          ('marche_merchant_order_ops','marche_order_settlement_receipt','marche_finance_order_audit',
           '_marche_order_money','_marche_order_tender')
          AND provolatile = 'v'), NULL);
  r := r || public._qa_s13_ok('N4R11.A11 read models never invent a tender',
        (SELECT prosrc FROM pg_proc WHERE proname='_marche_order_tender') LIKE '%Paiement non enregistré%', NULL);
  r := r || public._qa_s13_ok('N4R11.A12 money model reads only canonical payables',
        (SELECT prosrc FROM pg_proc WHERE proname='_marche_order_money') LIKE '%public.merchant_payables%'
    AND (SELECT prosrc FROM pg_proc WHERE proname='_marche_order_money') LIKE '%payout_settlement_allocations%', NULL);
  r := r || public._qa_s13_ok('N4R11.A13 anon still cannot execute has_role (P15.5 preserved)',
        NOT has_function_privilege('anon','public.has_role(uuid,app_role)','EXECUTE'), NULL);

  BEGIN
    -- ===== FIXTURES =====
    v_buy := gen_random_uuid(); v_merch := gen_random_uuid(); v_merch2 := gen_random_uuid();
    v_adm := gen_random_uuid(); v_drv := gen_random_uuid();
    PERFORM public._qa_s13_user(v_buy,'n411b');
    PERFORM public._qa_s13_user(v_merch,'n411m');
    PERFORM public._qa_s13_user(v_merch2,'n411m2');
    PERFORM public._qa_s13_user(v_adm,'n411a');
    PERFORM public._qa_s13_driver(v_drv,'n411d',0);
    PERFORM public._qa_s13_admin(v_adm);

    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status, latitude, longitude, address_label)
      VALUES (v_merch,'qa-n411-a-'||substr(v_merch::text,1,8),'QA N411 Store A','active','approved',9.5370,-13.6785,'QA Madina')
      RETURNING id INTO v_store;
    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status, latitude, longitude)
      VALUES (v_merch2,'qa-n411-b-'||substr(v_merch2::text,1,8),'QA N411 Store B','active','approved',9.5380,-13.6700)
      RETURNING id INTO v_store2;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    l_a := public.marche_listing_create(jsonb_build_object('store_id',v_store,'title','QA N411 Riz',
      'category','Alimentation','price_gnf',10000,'quantity_in_stock',10,'publish',true));

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_res := public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n411-main-0001',
      'delivery_address','QA Kaloum, Conakry',
      'dropoff_lat', 9.5550, 'dropoff_lng', -13.6785,
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_a, 'qty', 2))));
    v_o1 := (v_res->>'id')::uuid;

    -- ===== B. AUTHORITY =====
    v_err := NULL;
    BEGIN PERFORM public.marche_merchant_order_ops(v_o1);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R11.B1 buyer cannot read merchant operations', v_err='NOT_AUTHORIZED', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch2), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_merchant_order_ops(v_o1);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R11.B2 another store owner cannot read it', v_err='NOT_AUTHORIZED', v_err);

    v_ck := public.marche_merchant_orders_cockpit(NULL,NULL,40,0);
    r := r || public._qa_s13_ok('N4R11.B3 cockpit is store-scoped, foreign orders invisible',
          NOT (v_ck->'items' @> jsonb_build_array(jsonb_build_object('order_id', v_o1))), NULL);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_merchant_order_ops(v_o1);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R11.B4 a courier cannot read merchant money', v_err='NOT_AUTHORIZED', v_err);

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_adm), true);
    v_err := NULL;
    BEGIN PERFORM public.marche_finance_order_audit(v_o1);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R11.B5 a plain admin is not finance-privileged',
          v_err='NOT_AUTHORIZED', v_err);

    -- ===== C. OPERATIONS TRUTH =====
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_ops := public.marche_merchant_order_ops(v_o1);
    r := r || public._qa_s13_ok('N4R11.C1 committed order is action_required',
          v_ops->>'ops_bucket' = 'action_required', v_ops->>'ops_bucket');
    r := r || public._qa_s13_ok('N4R11.C2 committed order allows accept + reject only',
          (v_ops->'allowed_actions') @> '["accept","reject"]'::jsonb
      AND jsonb_array_length(v_ops->'allowed_actions') = 2, v_ops->>'allowed_actions');
    r := r || public._qa_s13_ok('N4R11.C3 ops exposes canonical order items',
          jsonb_array_length(v_ops->'items') = 1, NULL);
    r := r || public._qa_s13_ok('N4R11.C4 no courier is claimed before dispatch',
          (v_ops->>'courier_assigned')::boolean = false, NULL);

    PERFORM public.marche_merchant_transition(v_o1,'accept',NULL);
    v_ops := public.marche_merchant_order_ops(v_o1);
    r := r || public._qa_s13_ok('N4R11.C5 accepted order allows prepare + reject',
          (v_ops->'allowed_actions') @> '["prepare","reject"]'::jsonb
      AND jsonb_array_length(v_ops->'allowed_actions') = 2, v_ops->>'allowed_actions');
    r := r || public._qa_s13_ok('N4R11.C6 accepted order sits in preparing bucket',
          v_ops->>'ops_bucket' = 'preparing', v_ops->>'ops_bucket');

    PERFORM public.marche_merchant_transition(v_o1,'prepare',NULL);
    v_ops := public.marche_merchant_order_ops(v_o1);
    r := r || public._qa_s13_ok('N4R11.C7 preparing order allows ready + reject',
          (v_ops->'allowed_actions') @> '["ready","reject"]'::jsonb
      AND jsonb_array_length(v_ops->'allowed_actions') = 2, v_ops->>'allowed_actions');

    PERFORM public.marche_merchant_transition(v_o1,'ready',NULL);
    v_ops := public.marche_merchant_order_ops(v_o1);
    r := r || public._qa_s13_ok('N4R11.C8 ready order offers dispatch',
          (v_ops->'allowed_actions') @> '["request_dispatch"]'::jsonb, v_ops->>'allowed_actions');

    PERFORM public.marche_dispatch_request(v_o1);
    v_ops := public.marche_merchant_order_ops(v_o1);
    r := r || public._qa_s13_ok('N4R11.C9 dispatched order can no longer be rejected or re-dispatched',
          NOT ((v_ops->'allowed_actions') @> '["reject"]'::jsonb)
      AND NOT ((v_ops->'allowed_actions') @> '["request_dispatch"]'::jsonb), v_ops->>'allowed_actions');
    r := r || public._qa_s13_ok('N4R11.C10 dispatched order is in_delivery',
          v_ops->>'ops_bucket' = 'in_delivery', v_ops->>'ops_bucket');
    r := r || public._qa_s13_ok('N4R11.C11 courier presence is server truth',
          (v_ops->>'courier_assigned')::boolean = true, NULL);

    -- ===== D. TENDER TRUTH =====
    r := r || public._qa_s13_ok('N4R11.D1 no invented tender when nothing was recorded',
          v_ops->'tender'->>'tender_kind' = 'none'
      AND (v_ops->'tender'->>'recorded')::boolean = false, v_ops->'tender'->>'tender_kind');
    r := r || public._qa_s13_ok('N4R11.D2 unrecorded tender is stated honestly in French',
          v_ops->'tender'->>'label' = 'Paiement non enregistré', NULL);
    r := r || public._qa_s13_ok('N4R11.D3 tender carries no evidence source when absent',
          (v_ops->'tender'->'evidence_source') = 'null'::jsonb, NULL);

    -- ===== E. MONEY TRUTH (no payable yet) =====
    r := r || public._qa_s13_ok('N4R11.E1 absent payable is not_yet_payable',
          v_ops->'money'->>'settlement_state' = 'not_yet_payable', v_ops->'money'->>'settlement_state');
    r := r || public._qa_s13_ok('N4R11.E2 absent payable never claims settled',
          (v_ops->'money'->>'settled')::boolean = false, NULL);
    r := r || public._qa_s13_ok('N4R11.E3 money mirrors frozen R4 economics verbatim',
          (v_ops->'money'->>'merchant_payable_gnf')::bigint =
            (SELECT merchant_payable_gnf FROM public.marche_orders WHERE id=v_o1)
      AND (v_ops->'money'->>'merchant_fee_gnf')::bigint =
            (SELECT merchant_fee_gnf FROM public.marche_orders WHERE id=v_o1), NULL);
    v_rc := public.marche_order_settlement_receipt(v_o1);
    r := r || public._qa_s13_ok('N4R11.E4 no receipt exists without a payable',
          (v_rc->>'receipt_available')::boolean = false
      AND (v_rc->>'settled')::boolean = false, NULL);

    -- ===== F. MONEY TRUTH (canonical payable, unfunded then settled) =====
    INSERT INTO public.merchant_payables(payable_key, source_module, source_id, merchant_store_id,
        merchant_user_id, mission_type, subtotal_gnf, deduction_gnf, amount_gnf,
        funded_gnf, settled_gnf, state, funding_source)
      VALUES ('qa-n411-'||v_o1::text, 'marche', v_o1, v_store, v_merch, 'marketplace_delivery',
        (SELECT merchandise_subtotal_gnf FROM public.marche_orders WHERE id=v_o1),
        (SELECT merchant_fee_gnf FROM public.marche_orders WHERE id=v_o1),
        (SELECT merchant_payable_gnf FROM public.marche_orders WHERE id=v_o1),
        0, 0, 'pending_funding', 'unknown')
      RETURNING id INTO v_pay;

    v_ops := public.marche_merchant_order_ops(v_o1);
    r := r || public._qa_s13_ok('N4R11.F1 unfunded payable reads pending_funding',
          v_ops->'money'->>'settlement_state' = 'pending_funding', v_ops->'money'->>'settlement_state');
    r := r || public._qa_s13_ok('N4R11.F2 outstanding equals the full payable while unsettled',
          (v_ops->'money'->>'outstanding_gnf')::bigint = (v_ops->'money'->>'payable_amount_gnf')::bigint, NULL);

    UPDATE public.merchant_payables
       SET state='due', funded_gnf=amount_gnf WHERE id=v_pay;
    v_ops := public.marche_merchant_order_ops(v_o1);
    r := r || public._qa_s13_ok('N4R11.F3 funded payable reads funded_or_due',
          v_ops->'money'->>'settlement_state' = 'funded_or_due', v_ops->'money'->>'settlement_state');
    r := r || public._qa_s13_ok('N4R11.F4 funded is not settled',
          (v_ops->'money'->>'settled')::boolean = false, NULL);

    UPDATE public.merchant_payables SET settled_gnf = 1 WHERE id=v_pay;
    v_ops := public.marche_merchant_order_ops(v_o1);
    r := r || public._qa_s13_ok('N4R11.F5 partial settlement is stated as partial',
          v_ops->'money'->>'settlement_state' = 'partially_settled', v_ops->'money'->>'settlement_state');

    UPDATE public.merchant_payables SET settled_gnf = amount_gnf, state='settled' WHERE id=v_pay;
    v_ops := public.marche_merchant_order_ops(v_o1);
    r := r || public._qa_s13_ok('N4R11.F6 full settlement reads settled',
          v_ops->'money'->>'settlement_state' = 'settled'
      AND (v_ops->'money'->>'settled')::boolean = true, v_ops->'money'->>'settlement_state');
    r := r || public._qa_s13_ok('N4R11.F7 settled outstanding is zero',
          (v_ops->'money'->>'outstanding_gnf')::bigint = 0, NULL);

    UPDATE public.merchant_payables SET state='reversed' WHERE id=v_pay;
    v_ops := public.marche_merchant_order_ops(v_o1);
    r := r || public._qa_s13_ok('N4R11.F8 reversed payable overrides settled display',
          v_ops->'money'->>'settlement_state' = 'reversed', v_ops->'money'->>'settlement_state');
    UPDATE public.merchant_payables SET state='settled' WHERE id=v_pay;

    -- ===== G. RECEIPT / EVIDENCE LAW =====
    v_rc := public.marche_order_settlement_receipt(v_o1);
    r := r || public._qa_s13_ok('N4R11.G1 settled payable without allocation yields no receipt',
          (v_rc->>'receipt_available')::boolean = false, NULL);

    INSERT INTO public.payout_orders(party_type, source_kind, merchant_store_id, destination_msisdn,
        provider, environment, requested_principal_gnf, provider_fee_gnf, fee_borne_by,
        merchant_liability_debit_gnf, recipient_net_gnf, expected_provider_transfer_gnf,
        reservation_gnf, settled_gnf, status)
      VALUES ('merchant','merchant_settlement', v_store, '+224620000000','orange_money','sandbox',
        (SELECT amount_gnf FROM public.merchant_payables WHERE id=v_pay), 0, 'platform',
        (SELECT amount_gnf FROM public.merchant_payables WHERE id=v_pay),
        (SELECT amount_gnf FROM public.merchant_payables WHERE id=v_pay),
        (SELECT amount_gnf FROM public.merchant_payables WHERE id=v_pay),
        0, (SELECT amount_gnf FROM public.merchant_payables WHERE id=v_pay), 'settled')
      RETURNING id INTO v_po;
    INSERT INTO public.payout_settlement_allocations(payout_order_id, merchant_payable_id, amount_gnf)
      VALUES (v_po, v_pay, (SELECT amount_gnf FROM public.merchant_payables WHERE id=v_pay));

    v_rc := public.marche_order_settlement_receipt(v_o1);
    r := r || public._qa_s13_ok('N4R11.G2 allocation produces a receipt',
          (v_rc->>'receipt_available')::boolean = true
      AND jsonb_array_length(v_rc->'allocations') = 1, NULL);
    r := r || public._qa_s13_ok('N4R11.G3 allocation without reconciled evidence is not evidence_backed',
          (v_rc->'allocations'->0->>'evidence_backed')::boolean = false, NULL);
    r := r || public._qa_s13_ok('N4R11.G4 receipt never fabricates a provider reference',
          (v_rc->'allocations'->0->'provider_reference') = 'null'::jsonb, NULL);

    INSERT INTO public.payout_provider_evidence(payout_order_id, provider, provider_reference,
        recipient_msisdn, amount_gnf, provider_status, environment, state)
      VALUES (v_po,'orange_money','QA-N411-REF-0001','+224620000000',
        (SELECT amount_gnf FROM public.merchant_payables WHERE id=v_pay),'SUCCESS','sandbox','reconciled')
      RETURNING id INTO v_ev;

    v_rc := public.marche_order_settlement_receipt(v_o1);
    r := r || public._qa_s13_ok('N4R11.G5 reconciled evidence makes the allocation evidence_backed',
          (v_rc->'allocations'->0->>'evidence_backed')::boolean = true, NULL);
    r := r || public._qa_s13_ok('N4R11.G6 receipt shows the real provider reference',
          v_rc->'allocations'->0->>'provider_reference' = 'QA-N411-REF-0001', NULL);

    -- ===== H. FINANCE AUDIT =====
    PERFORM set_config('request.jwt.claims','', true);
    v_au := public.marche_finance_order_audit(v_o1);
    r := r || public._qa_s13_ok('N4R11.H1 consistent order audits clean',
          (v_au->>'clean')::boolean = true, v_au->>'mismatch_codes');

    UPDATE public.merchant_payables SET amount_gnf = amount_gnf + 500 WHERE id=v_pay;
    v_au := public.marche_finance_order_audit(v_o1);
    r := r || public._qa_s13_ok('N4R11.H2 payable/order divergence is flagged',
          (v_au->'mismatch_codes') @> '["ORDER_PAYABLE_AMOUNT_MISMATCH"]'::jsonb, v_au->>'mismatch_codes');
    r := r || public._qa_s13_ok('N4R11.H3 a settled state below the payable is flagged',
          (v_au->'mismatch_codes') @> '["SETTLED_STATE_WITHOUT_FULL_SETTLEMENT"]'::jsonb, v_au->>'mismatch_codes');
    UPDATE public.merchant_payables SET amount_gnf = amount_gnf - 500 WHERE id=v_pay;

    UPDATE public.merchant_payables SET settled_gnf = settled_gnf - 1 WHERE id=v_pay;
    v_au := public.marche_finance_order_audit(v_o1);
    r := r || public._qa_s13_ok('N4R11.H4 allocation coverage divergence is flagged',
          (v_au->'mismatch_codes') @> '["ALLOCATION_COVERAGE_MISMATCH"]'::jsonb, v_au->>'mismatch_codes');
    UPDATE public.merchant_payables SET settled_gnf = amount_gnf WHERE id=v_pay;

    UPDATE public.payout_provider_evidence SET state='mismatch' WHERE id=v_ev;
    v_au := public.marche_finance_order_audit(v_o1);
    r := r || public._qa_s13_ok('N4R11.H5 settlement without reconciled evidence is flagged',
          (v_au->'mismatch_codes') @> '["SETTLEMENT_WITHOUT_RECONCILED_EVIDENCE"]'::jsonb, v_au->>'mismatch_codes');
    UPDATE public.payout_provider_evidence SET state='reconciled' WHERE id=v_ev;

    UPDATE public.payout_orders SET status='needs_review' WHERE id=v_po;
    v_au := public.marche_finance_order_audit(v_o1);
    r := r || public._qa_s13_ok('N4R11.H6 a payout needing review is flagged',
          (v_au->'mismatch_codes') @> '["PAYOUT_ORDER_NEEDS_REVIEW"]'::jsonb, v_au->>'mismatch_codes');
    UPDATE public.payout_orders SET status='settled' WHERE id=v_po;

    -- ===== I. COCKPIT =====
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_ck := public.marche_merchant_orders_cockpit(v_store,NULL,40,0);
    r := r || public._qa_s13_ok('N4R11.I1 cockpit returns the merchant own order',
          jsonb_array_length(v_ck->'items') = 1
      AND v_ck->'items'->0->>'order_id' = v_o1::text, NULL);
    r := r || public._qa_s13_ok('N4R11.I2 cockpit counts the in_delivery bucket',
          (v_ck->'counts'->>'in_delivery')::int = 1, v_ck->>'counts');
    v_ck := public.marche_merchant_orders_cockpit(v_store,'action_required',40,0);
    r := r || public._qa_s13_ok('N4R11.I3 bucket filtering excludes non-matching orders',
          jsonb_array_length(v_ck->'items') = 0, NULL);
    v_err := NULL;
    BEGIN PERFORM public.marche_merchant_orders_cockpit(v_store,'not_a_bucket',10,0);
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R11.I4 an unknown bucket is refused', v_err='UNKNOWN_BUCKET', v_err);
    v_ck := public.marche_merchant_orders_cockpit(v_store2,NULL,40,0);
    r := r || public._qa_s13_ok('N4R11.I5 cockpit refuses to leak a foreign store',
          jsonb_array_length(v_ck->'items') = 0, NULL);

    -- ===== J. NO MUTATION =====
    v_ops := public.marche_merchant_order_ops(v_o1);
    r := r || public._qa_s13_ok('N4R11.J1 reading operations does not move the lifecycle',
          v_ops->>'fulfillment_state' =
            (SELECT fulfillment_state FROM public.marche_orders WHERE id=v_o1), NULL);
    SELECT count(*) INTO v_n FROM public.marche_fulfillment_transitions WHERE order_id=v_o1;
    PERFORM public.marche_merchant_order_ops(v_o1);
    PERFORM public.marche_order_settlement_receipt(v_o1);
    r := r || public._qa_s13_ok('N4R11.J2 read models append no transition',
          (SELECT count(*) FROM public.marche_fulfillment_transitions WHERE order_id=v_o1) = v_n, NULL);

  EXCEPTION WHEN OTHERS THEN
    r := r || public._qa_s13_ok('N4R11.X fixture run raised', false, SQLERRM);
  END;

  -- ===== CLEANUP =====
  PERFORM set_config('request.jwt.claims','', true);
  DELETE FROM public.payout_provider_evidence WHERE payout_order_id = v_po;
  DELETE FROM public.payout_settlement_allocations WHERE merchant_payable_id = v_pay;
  DELETE FROM public.payout_orders WHERE id = v_po;
  DELETE FROM public.merchant_payables WHERE id = v_pay;
  DELETE FROM public.marche_fulfillment_transitions WHERE order_id = v_o1;
  DELETE FROM public.marche_fulfillment_observations WHERE order_id = v_o1;
  DELETE FROM public.marche_fulfillment_events WHERE order_id = v_o1;
  DELETE FROM public.marche_fulfillment_profiles WHERE order_id = v_o1;
  DELETE FROM public.marche_order_items WHERE order_id = v_o1;
  UPDATE public.marche_orders SET mission_id = NULL WHERE id = v_o1;
  DELETE FROM public.mission_events WHERE mission_id IN
    (SELECT id FROM public.missions WHERE ref_market_order_id = v_o1);
  DELETE FROM public.missions WHERE ref_market_order_id = v_o1;
  DELETE FROM public.marche_orders WHERE id = v_o1;
  DELETE FROM public.marketplace_listings WHERE store_id IN (v_store, v_store2);
  DELETE FROM public.merchant_stores WHERE id IN (v_store, v_store2);
  DELETE FROM public.user_roles WHERE user_id IN (v_buy,v_merch,v_merch2,v_adm,v_drv);
  DELETE FROM public.admin_users WHERE user_id = v_adm;
  DELETE FROM public.driver_profiles WHERE user_id = v_drv;
  DELETE FROM public.wallet_transactions WHERE from_wallet_id IN
      (SELECT id FROM public.wallets WHERE owner_user_id IN (v_buy,v_merch,v_merch2,v_adm,v_drv))
     OR to_wallet_id IN
      (SELECT id FROM public.wallets WHERE owner_user_id IN (v_buy,v_merch,v_merch2,v_adm,v_drv));
  DELETE FROM public.wallets WHERE owner_user_id IN (v_buy,v_merch,v_merch2,v_adm,v_drv);
  DELETE FROM auth.users WHERE id IN (v_buy,v_merch,v_merch2,v_adm,v_drv);

  -- ===== S. SYSTEMIC =====
  SELECT count(*) INTO v_w1 FROM public.wallets;
  SELECT count(*) INTO v_wt1 FROM public.wallet_transactions;
  SELECT count(*) INTO v_lj1 FROM public.ledger_journals;
  SELECT count(*) INTO v_pi1 FROM public.payment_intents;
  SELECT count(*) INTO v_mp1 FROM public.merchant_payables;
  SELECT count(*) INTO v_ss1 FROM public.merchant_settlement_requests;
  SELECT COALESCE(sum(quantity_reserved),0) INTO v_reserved1 FROM public.marketplace_listings;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;

  r := r || public._qa_s13_ok('N4R11.S1 zero wallet / ledger / payment drift',
        v_w1=v_w0 AND v_wt1=v_wt0 AND v_lj1=v_lj0 AND v_pi1=v_pi0,
        format('%s/%s/%s/%s', v_w1-v_w0, v_wt1-v_wt0, v_lj1-v_lj0, v_pi1-v_pi0));
  r := r || public._qa_s13_ok('N4R11.S2 zero payable / settlement drift',
        v_mp1=v_mp0 AND v_ss1=v_ss0, format('%s/%s', v_mp1-v_mp0, v_ss1-v_ss0));
  r := r || public._qa_s13_ok('N4R11.S3 reserved stock returns to baseline',
        v_reserved1=v_reserved0, format('%s->%s', v_reserved0, v_reserved1));
  r := r || public._qa_s13_ok('N4R11.S4 feature flags byte-identical', v_flags1=v_flags0, NULL);
  SELECT count(*) INTO v_n FROM public.marche_orders WHERE client_request_id LIKE 'qa-n411-%';
  r := r || public._qa_s13_ok('N4R11.S5 zero order fixture residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.merchant_stores WHERE slug LIKE 'qa-n411-%';
  r := r || public._qa_s13_ok('N4R11.S6 zero store fixture residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marketplace_listings WHERE title LIKE 'QA N411%';
  r := r || public._qa_s13_ok('N4R11.S7 zero listing fixture residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.payout_provider_evidence WHERE provider_reference LIKE 'QA-N411-%';
  r := r || public._qa_s13_ok('N4R11.S8 zero payout evidence residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM auth.users WHERE id IN (v_buy,v_merch,v_merch2,v_adm,v_drv);
  r := r || public._qa_s13_ok('N4R11.S9 zero auth fixture residue', v_n=0, v_n::text);
  SELECT count(*) INTO v_n FROM public.payout_settlement_allocations a
    LEFT JOIN public.merchant_payables p ON p.id=a.merchant_payable_id WHERE p.id IS NULL;
  r := r || public._qa_s13_ok('N4R11.S10 zero orphan settlement allocation', v_n=0, v_n::text);

  RETURN r;
END $$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r11() FROM PUBLIC, anon, authenticated;
