-- ============================================================
-- NODE 4 — MARCHÉ R4 (part 2): commitment economics + visibility + QA
-- ============================================================

-- ---------- 1. Sanitized order payload, scoped by viewer ----------
CREATE OR REPLACE FUNCTION public.marche_order_json(o public.marche_orders)
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
  SELECT jsonb_build_object(
    'id', o.id,
    'buyer_user_id', o.buyer_user_id,
    'merchant_store_id', o.merchant_store_id,
    'merchant_user_id', o.merchant_user_id,
    'status', o.status,
    'merchandise_subtotal_gnf', o.merchandise_subtotal_gnf,
    'item_count', o.item_count,
    'line_count', o.line_count,
    'source_offer_id', o.source_offer_id,
    'client_request_id', o.client_request_id,
    'delivery_address', o.delivery_address,
    'dropoff_lat', o.dropoff_lat,
    'dropoff_lng', o.dropoff_lng,
    'delivery_charge_gnf', o.delivery_charge_gnf,
    'delivery_pricing_state', o.delivery_pricing_state,
    'reservation_expires_at', o.reservation_expires_at,
    'cancelled_at', o.cancelled_at,
    'cancel_reason', o.cancel_reason,
    'created_at', o.created_at,
    'updated_at', o.updated_at,
    'items', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', i.id, 'listing_id', i.listing_id, 'store_id', i.store_id_snapshot,
        'title', i.title_snapshot, 'qty', i.qty,
        'unit_price_gnf', i.unit_price_gnf, 'line_total_gnf', i.line_total_gnf,
        'source_offer_id', i.source_offer_id) ORDER BY i.created_at, i.id)
      FROM public.marche_order_items i WHERE i.order_id = o.id), '[]'::jsonb)
  )
  -- Merchant economics are internal truth: only the merchant or an admin sees them.
  || CASE WHEN auth.uid() IS NOT NULL
            AND (o.merchant_user_id = auth.uid() OR public.is_any_admin(auth.uid()))
          THEN jsonb_build_object(
                 'merchant_fee_gnf', o.merchant_fee_gnf,
                 'merchant_payable_gnf', o.merchant_payable_gnf,
                 'merchant_platform_fee_bps', o.merchant_platform_fee_bps,
                 'fee_policy_id', o.fee_policy_id,
                 'fee_policy_effective_from', o.fee_policy_effective_from,
                 'economics_resolved_at', o.economics_resolved_at,
                 'economics_snapshot', o.economics_snapshot)
          ELSE '{}'::jsonb END;
$fn$;

-- ---------- 2. Commitment freezes economics ----------
CREATE OR REPLACE FUNCTION public.marche_order_commit(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  caller uuid := auth.uid();
  v_req text;
  v_items jsonb;
  v_it jsonb;
  v_ids uuid[] := '{}';
  v_fp text;
  v_norm jsonb := '[]'::jsonb;
  v_lines_json jsonb := '[]'::jsonb;
  v_existing public.marche_orders;
  v_order_id uuid;
  l public.marketplace_listings;
  t public.v_marche_listing_truth%ROWTYPE;
  o public.marketplace_offers;
  v_store uuid; v_seller uuid;
  v_qty int; v_unit bigint; v_avail int;
  v_subtotal bigint := 0; v_items_n int := 0; v_lines int := 0;
  v_offer uuid; v_single_offer uuid; v_offer_count int := 0;
  v_addr text; v_lat double precision; v_lng double precision;
  pol public.finance_policies;
  v_now timestamptz := now();
  v_bps int; v_fee bigint; v_payable bigint; v_econ jsonb;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;

  IF p_payload ? 'merchandise_subtotal_gnf' OR p_payload ? 'total_gnf' OR p_payload ? 'subtotal_gnf' THEN
    RAISE EXCEPTION 'CLIENT_PRICE_NOT_ALLOWED';
  END IF;
  -- R4: no client authority over economics or policy.
  IF p_payload ? 'merchant_fee_gnf' OR p_payload ? 'merchant_payable_gnf'
     OR p_payload ? 'merchant_platform_fee_bps' OR p_payload ? 'fee_policy_id'
     OR p_payload ? 'delivery_charge_gnf' OR p_payload ? 'economics_snapshot' THEN
    RAISE EXCEPTION 'CLIENT_ECONOMICS_NOT_ALLOWED';
  END IF;

  v_req := NULLIF(btrim(COALESCE(p_payload->>'client_request_id','')), '');
  IF v_req IS NULL OR length(v_req) < 8 OR length(v_req) > 128 THEN RAISE EXCEPTION 'CLIENT_REQUEST_ID_REQUIRED'; END IF;

  v_items := p_payload->'items';
  IF v_items IS NULL OR jsonb_typeof(v_items) <> 'array' OR jsonb_array_length(v_items) = 0 THEN
    RAISE EXCEPTION 'EMPTY_BASKET';
  END IF;
  IF jsonb_array_length(v_items) > 20 THEN RAISE EXCEPTION 'BASKET_TOO_LARGE'; END IF;

  v_addr := NULLIF(btrim(COALESCE(p_payload->>'delivery_address','')), '');
  v_lat := NULLIF(p_payload->>'dropoff_lat','')::double precision;
  v_lng := NULLIF(p_payload->>'dropoff_lng','')::double precision;

  FOR v_it IN SELECT * FROM jsonb_array_elements(v_items) LOOP
    IF v_it ? 'unit_price_gnf' OR v_it ? 'line_total_gnf' OR v_it ? 'price_gnf' THEN
      RAISE EXCEPTION 'CLIENT_PRICE_NOT_ALLOWED';
    END IF;
    IF NULLIF(v_it->>'listing_id','') IS NULL THEN RAISE EXCEPTION 'LISTING_REQUIRED'; END IF;
    v_qty := COALESCE((v_it->>'qty')::int, 0);
    IF v_qty <= 0 OR v_qty > 100 THEN RAISE EXCEPTION 'INVALID_QUANTITY'; END IF;
    IF (v_it->>'listing_id')::uuid = ANY(v_ids) THEN RAISE EXCEPTION 'DUPLICATE_LINE'; END IF;
    v_ids := v_ids || (v_it->>'listing_id')::uuid;
  END LOOP;

  SELECT jsonb_agg(jsonb_build_object(
           'listing_id', x->>'listing_id', 'qty', (x->>'qty')::int,
           'offer_id', COALESCE(x->>'offer_id','')) ORDER BY x->>'listing_id')
    INTO v_norm FROM jsonb_array_elements(v_items) x;

  v_fp := md5(v_norm::text || '|' || COALESCE(v_addr,'') || '|' || COALESCE(v_lat::text,'') || '|' || COALESCE(v_lng::text,''));

  SELECT * INTO v_existing FROM public.marche_orders
   WHERE buyer_user_id = caller AND client_request_id = v_req;
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.request_fingerprint <> v_fp THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT'; END IF;
    -- Replay returns the frozen order untouched; it never re-snapshots a newer policy.
    RETURN public.marche_order_json(v_existing);
  END IF;

  -- deterministic row locking (oversell protection)
  PERFORM 1 FROM public.marketplace_listings WHERE id = ANY(v_ids) ORDER BY id FOR UPDATE;

  v_order_id := gen_random_uuid();

  FOR v_it IN SELECT * FROM jsonb_array_elements(v_norm) LOOP
    SELECT * INTO l FROM public.marketplace_listings WHERE id = (v_it->>'listing_id')::uuid;
    IF l.id IS NULL THEN RAISE EXCEPTION 'LISTING_NOT_FOUND'; END IF;
    SELECT * INTO t FROM public.v_marche_listing_truth WHERE listing_id = l.id;
    IF NOT t.is_orderable THEN RAISE EXCEPTION '%', t.refusal_reason; END IF;
    IF l.seller_id = caller THEN RAISE EXCEPTION 'SELF_PURCHASE_NOT_ALLOWED'; END IF;

    IF v_store IS NULL THEN v_store := l.store_id; v_seller := l.seller_id;
    ELSIF v_store <> l.store_id THEN RAISE EXCEPTION 'SINGLE_STORE_ONLY';
    END IF;

    v_qty := (v_it->>'qty')::int;
    v_offer := NULLIF(v_it->>'offer_id','')::uuid;

    IF l.pricing_mode = 'fixed' THEN
      IF v_offer IS NOT NULL THEN RAISE EXCEPTION 'OFFER_NOT_APPLICABLE'; END IF;
      v_unit := l.price_gnf;
      IF COALESCE(v_unit,0) <= 0 THEN RAISE EXCEPTION 'INVALID_PRICE'; END IF;
    ELSIF l.pricing_mode = 'negotiable' THEN
      IF v_offer IS NULL THEN RAISE EXCEPTION 'OFFER_REQUIRED'; END IF;
      SELECT * INTO o FROM public.marketplace_offers WHERE id = v_offer;
      IF o.id IS NULL THEN RAISE EXCEPTION 'OFFER_NOT_FOUND'; END IF;
      IF o.buyer_user_id <> caller OR o.listing_id <> l.id OR o.merchant_store_id IS DISTINCT FROM l.store_id THEN
        RAISE EXCEPTION 'OFFER_NOT_FOR_THIS_BUYER';
      END IF;
      IF o.status <> 'accepted' OR o.agreed_amount_gnf IS NULL OR public.marche_offer_is_expired(o) THEN
        RAISE EXCEPTION 'OFFER_NOT_AGREED';
      END IF;
      v_unit := o.agreed_amount_gnf;
      v_offer_count := v_offer_count + 1;
      v_single_offer := o.id;
    ELSIF l.pricing_mode = 'quote' THEN
      RAISE EXCEPTION 'QUOTE_NOT_ORDERABLE';
    ELSE
      RAISE EXCEPTION 'UNSUPPORTED_PRICING_MODE';
    END IF;

    IF l.quantity_in_stock IS NOT NULL THEN
      v_avail := l.quantity_in_stock - COALESCE(l.quantity_reserved,0);
      IF v_avail <= 0 THEN RAISE EXCEPTION 'OUT_OF_STOCK'; END IF;
      IF v_qty > v_avail THEN RAISE EXCEPTION 'INSUFFICIENT_STOCK'; END IF;
      PERFORM set_config('marche.rpc','1', true);
      UPDATE public.marketplace_listings
         SET quantity_reserved = COALESCE(quantity_reserved,0) + v_qty
       WHERE id = l.id;
      PERFORM set_config('marche.rpc','', true);
    END IF;

    v_lines_json := v_lines_json || jsonb_build_array(jsonb_build_object(
      'listing_id', l.id, 'store_id', l.store_id, 'title', l.title,
      'qty', v_qty, 'unit', v_unit, 'total', v_unit * v_qty, 'offer_id', v_offer,
      'category', NULLIF(btrim(COALESCE(l.category,'')),'')));

    v_subtotal := v_subtotal + (v_unit * v_qty);
    v_items_n := v_items_n + v_qty;
    v_lines := v_lines + 1;
  END LOOP;

  -- ---- R4 economics: canonical Slice 13 finance policy, frozen at commitment ----
  SELECT * INTO pol FROM public.finance_policy_at('marche', v_now);
  IF pol.id IS NULL THEN RAISE EXCEPTION 'NO_ACTIVE_POLICY'; END IF;
  v_bps := pol.merchant_platform_fee_bps;
  IF v_bps IS NULL THEN RAISE EXCEPTION 'MERCHANT_FEE_POLICY_MISSING'; END IF;
  IF v_bps < 0 OR v_bps > 10000 THEN RAISE EXCEPTION 'INVALID_MERCHANT_PLATFORM_FEE_BPS'; END IF;

  v_fee := public.marche_merchant_fee_gnf(v_subtotal, v_bps);
  v_payable := v_subtotal - v_fee;
  IF v_fee < 0 OR v_fee > v_subtotal OR v_payable < 0 THEN RAISE EXCEPTION 'ECONOMICS_INVARIANT_VIOLATION'; END IF;

  v_econ := jsonb_build_object(
    'schema', 'chopchop.marche.order_economics',
    'version', 1,
    'resolved_at', v_now,
    'policy_id', pol.id,
    'policy_mission_type', pol.mission_type,
    'policy_effective_from', pol.effective_from,
    'merchant_platform_fee_bps', v_bps,
    'merchant_platform_fee_basis', 'merchandise_subtotal',
    'rounding', 'floor_gnf_clamped_to_subtotal',
    'merchandise_subtotal_gnf', v_subtotal,
    'merchant_platform_fee_gnf', v_fee,
    'merchant_payable_gnf', v_payable,
    'delivery_pricing_state', 'unresolved',
    'customer_delivery_charge_gnf', NULL,
    'policy_snapshot', public.finance_policy_snapshot('marche', v_now, 'chop_pay', 0, v_subtotal));

  INSERT INTO public.marche_orders(id, buyer_user_id, merchant_store_id, merchant_user_id,
    status, merchandise_subtotal_gnf, item_count, line_count, source_offer_id,
    client_request_id, request_fingerprint, delivery_address, dropoff_lat, dropoff_lng,
    merchant_fee_gnf, merchant_payable_gnf, merchant_platform_fee_bps,
    fee_policy_id, fee_policy_effective_from, economics_snapshot, economics_resolved_at,
    delivery_charge_gnf, delivery_pricing_state)
  VALUES (v_order_id, caller, v_store, v_seller, 'committed', v_subtotal, v_items_n, v_lines,
    CASE WHEN v_offer_count = 1 THEN v_single_offer ELSE NULL END,
    v_req, v_fp, v_addr, v_lat, v_lng,
    v_fee, v_payable, v_bps, pol.id, pol.effective_from, v_econ, v_now,
    NULL, 'unresolved')
  RETURNING * INTO v_existing;

  INSERT INTO public.marche_order_items(order_id, listing_id, store_id_snapshot, title_snapshot,
    qty, unit_price_gnf, line_total_gnf, source_offer_id, category_snapshot)
  SELECT v_order_id, (x->>'listing_id')::uuid, (x->>'store_id')::uuid, x->>'title',
         (x->>'qty')::int, (x->>'unit')::bigint, (x->>'total')::bigint,
         NULLIF(x->>'offer_id','')::uuid, NULLIF(x->>'category','')
    FROM jsonb_array_elements(v_lines_json) x;

  -- R3.5 measurement substrate: immutable basket profile + exactly-once ORDER_COMMITTED.
  PERFORM public.marche_fulfillment_profile_create(v_order_id);
  PERFORM public.marche_fulfillment_event_append(
    v_order_id, 'ORDER_COMMITTED', v_existing.created_at,
    'marche_order_commit', v_order_id::text, 'commit', 'system');

  RETURN public.marche_order_json(v_existing);
END $fn$;

-- ---------- 3. Amend (not extend) frozen R3 / R3.5 assertions ----------
DO $do$
DECLARE s text; s2 text; n int;
BEGIN
  -- R3
  SELECT prosrc INTO s FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='_qa_node4_marche_r3';
  s2 := s;
  s2 := replace(s2,
    $a$  r := r || public._qa_s13_ok('N4R3.A25 order guard forbids finance columns in R3',
        (SELECT prosrc FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='marche_order_guard')
          LIKE '%FINANCE_NOT_IN_R3%', NULL);$a$,
    $a$  r := r || public._qa_s13_ok('N4R3.A25 order guard freezes economics after commitment (R4)',
        (SELECT prosrc FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='marche_order_guard')
          LIKE '%ECONOMICS_IMMUTABLE%', NULL);$a$);
  s2 := replace(s2,
    $a$    r := r || public._qa_s13_ok('N4R3.B1g no finance is attached in R3',
          v_res->>'merchant_fee_gnf' IS NULL AND v_res->>'delivery_charge_gnf' IS NULL
      AND v_res->>'fee_policy_id' IS NULL, NULL);$a$,
    $a$    r := r || public._qa_s13_ok('N4R3.B1g buyer payload hides merchant economics; delivery unresolved (R4)',
          v_res->>'merchant_fee_gnf' IS NULL AND v_res->>'delivery_charge_gnf' IS NULL
      AND v_res->>'delivery_pricing_state' = 'unresolved', v_res->>'delivery_pricing_state');$a$);
  s2 := replace(s2,
    $a$    SELECT count(*) INTO v_n FROM public.marche_orders
     WHERE merchant_fee_gnf IS NOT NULL OR delivery_charge_gnf IS NOT NULL OR fee_policy_id IS NOT NULL;
    r := r || public._qa_s13_ok('N4R3.B15 no order carries fee or delivery money in R3', v_n = 0, v_n::text);$a$,
    $a$    SELECT count(*) INTO v_n FROM public.marche_orders WHERE delivery_charge_gnf IS NOT NULL;
    r := r || public._qa_s13_ok('N4R3.B15 customer delivery money stays unresolved (R4)', v_n = 0, v_n::text);$a$);
  s2 := replace(s2,
    $a$    r := r || public._qa_s13_ok('N4R3.B15c commit never consumes finance policy',
          v_src NOT LIKE '%finance_policies%' AND v_src NOT LIKE '%transaction_fee_bps%', NULL);$a$,
    $a$    r := r || public._qa_s13_ok('N4R3.B15c commit consumes only the canonical finance policy resolver (R4)',
          v_src LIKE '%finance_policy_at%' AND v_src NOT LIKE '%transaction_fee_bps%'
      AND v_src NOT LIKE '%merchant_payables%', NULL);$a$);
  IF s2 = s THEN RAISE EXCEPTION 'R3_QA_AMENDMENT_NO_MATCH'; END IF;
  EXECUTE 'CREATE OR REPLACE FUNCTION public._qa_node4_marche_r3() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''public'' AS $qa$'||s2||'$qa$';

  -- R3.5
  SELECT prosrc INTO s FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='_qa_node4_marche_r35';
  s2 := s;
  s2 := replace(s2,
    $a$  r := r || public._qa_s13_ok('N4R35.C30 R3.5 introduces no fee/settlement call',
        v_src NOT LIKE '%transaction_fee_bps%' AND v_src NOT LIKE '%finance_policies%'
    AND v_src NOT LIKE '%payment_intent%', NULL);$a$,
    $a$  r := r || public._qa_s13_ok('N4R35.C30 measurement still triggers no settlement or payment rail',
        v_src NOT LIKE '%transaction_fee_bps%' AND v_src NOT LIKE '%merchant_payables%'
    AND v_src NOT LIKE '%payment_intent%' AND v_src NOT LIKE '%wallet%'
    AND v_src NOT LIKE '%ledger%', NULL);$a$);
  s2 := replace(s2,
    $a$    r := r || public._qa_s13_ok('N4R35.D22 R3 money fields remain NULL after R3.5 wiring',
          v_ord.merchant_fee_gnf IS NULL AND v_ord.delivery_charge_gnf IS NULL
      AND v_ord.fee_policy_id IS NULL, NULL);$a$,
    $a$    r := r || public._qa_s13_ok('N4R35.D22 R4 economics frozen, customer delivery still unresolved',
          v_ord.merchant_fee_gnf IS NOT NULL AND v_ord.fee_policy_id IS NOT NULL
      AND v_ord.merchant_payable_gnf = v_ord.merchandise_subtotal_gnf - v_ord.merchant_fee_gnf
      AND v_ord.delivery_charge_gnf IS NULL, NULL);$a$);
  s2 := replace(s2,
    $a$    r := r || public._qa_s13_ok('N4R35.N3 all fixture orders still carry NULL money fields',
          (SELECT count(*) FROM public.marche_orders
            WHERE buyer_user_id = v_buy
              AND (merchant_fee_gnf IS NOT NULL OR delivery_charge_gnf IS NOT NULL
                OR fee_policy_id IS NOT NULL)) = 0, NULL);$a$,
    $a$    r := r || public._qa_s13_ok('N4R35.N3 every fixture order carries coherent R4 economics and no delivery money',
          (SELECT count(*) FROM public.marche_orders
            WHERE buyer_user_id = v_buy
              AND (merchant_fee_gnf IS NULL OR fee_policy_id IS NULL
                OR delivery_charge_gnf IS NOT NULL
                OR merchant_payable_gnf <> merchandise_subtotal_gnf - merchant_fee_gnf)) = 0, NULL);$a$);
  IF s2 = s THEN RAISE EXCEPTION 'R35_QA_AMENDMENT_NO_MATCH'; END IF;
  EXECUTE 'CREATE OR REPLACE FUNCTION public._qa_node4_marche_r35() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''public'' AS $qa$'||s2||'$qa$';
END $do$;

-- ---------- 4. R4 certification suite ----------
CREATE OR REPLACE FUNCTION public._qa_node4_marche_r4()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $qa$
DECLARE
  r jsonb := '[]'::jsonb;
  v_buy uuid; v_merch uuid; v_adm uuid; v_store uuid;
  l_a uuid; l_b uuid; l_odd uuid;
  v_res jsonb; v_res2 jsonb; v_err text; v_n int; v_key text;
  v_o1 uuid; v_o2 uuid; v_ord public.marche_orders; v_ord2 public.marche_orders;
  v_pol public.finance_policies; v_src text;
  v_fee1 bigint; v_pay1 bigint; v_bps1 int; v_polid1 uuid;
  v_w0 bigint; v_w1 bigint; v_wt0 bigint; v_wt1 bigint; v_lj0 bigint; v_lj1 bigint;
  v_lp0 bigint; v_lp1 bigint; v_pi0 bigint; v_pi1 bigint; v_ms0 bigint; v_ms1 bigint;
  v_mp0 bigint; v_mp1 bigint; v_fpc0 bigint; v_fpc1 bigint;
  v_flags0 jsonb; v_flags1 jsonb;
  v_total0 bigint; v_total1 bigint; v_none0 bigint; v_none1 bigint;
  v_demo0 bigint; v_demo1 bigint; v_res0 bigint; v_res1 bigint;
BEGIN
  SELECT jsonb_object_agg(key, enabled) INTO v_flags0 FROM public.feature_flags;
  SELECT count(*) INTO v_w0 FROM public.wallets;
  SELECT count(*) INTO v_wt0 FROM public.wallet_transactions;
  SELECT count(*) INTO v_lj0 FROM public.ledger_journals;
  SELECT count(*) INTO v_lp0 FROM public.ledger_postings;
  SELECT count(*) INTO v_pi0 FROM public.payment_intents;
  SELECT count(*) INTO v_ms0 FROM public.missions;
  SELECT count(*) INTO v_mp0 FROM public.merchant_payables;
  SELECT count(*) INTO v_fpc0 FROM public.finance_policies;
  SELECT count(*) INTO v_total0 FROM public.marketplace_listings;
  SELECT count(*) INTO v_none0 FROM public.marketplace_listings WHERE store_id IS NULL;
  SELECT count(*) INTO v_demo0 FROM public.v_marche_listing_truth WHERE is_demo;
  SELECT COALESCE(sum(quantity_reserved),0) INTO v_res0 FROM public.marketplace_listings;

  -- ============ A. STRUCTURAL / NO DUPLICATE MONEY ARCHITECTURE ============
  r := r || public._qa_s13_ok('N4R4.A1 merchant fee lives in the canonical finance policy table',
        EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
                 AND table_name='finance_policies' AND column_name='merchant_platform_fee_bps'), NULL);
  r := r || public._qa_s13_ok('N4R4.A2 no parallel marche finance policy table was invented',
        to_regclass('public.marche_finance_policies') IS NULL
    AND to_regclass('public.marche_fees') IS NULL
    AND to_regclass('public.marche_payments') IS NULL
    AND to_regclass('public.marche_wallets') IS NULL
    AND to_regclass('public.marche_ledger') IS NULL
    AND to_regclass('public.marche_settlements') IS NULL, NULL);
  r := r || public._qa_s13_ok('N4R4.A3 economics columns exist on the canonical R3 order',
        (SELECT count(*) FROM information_schema.columns WHERE table_schema='public'
          AND table_name='marche_orders'
          AND column_name IN ('merchant_fee_gnf','merchant_payable_gnf','merchant_platform_fee_bps',
                              'fee_policy_id','fee_policy_effective_from','economics_snapshot',
                              'economics_resolved_at','delivery_pricing_state')) = 8, NULL);
  r := r || public._qa_s13_ok('N4R4.A4 only one canonical marche order table exists',
        to_regclass('public.marche_orders') IS NOT NULL
    AND (SELECT count(*) FROM information_schema.tables WHERE table_schema='public'
          AND table_name LIKE 'marche%order%') = 2, NULL);
  r := r || public._qa_s13_ok('N4R4.A5 payable identity is enforced by constraint',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conname='marche_orders_payable_identity_chk'), NULL);
  r := r || public._qa_s13_ok('N4R4.A6 fee bounds are enforced by constraint',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conname='marche_orders_fee_bounds_chk'), NULL);
  r := r || public._qa_s13_ok('N4R4.A7 economics are all-or-nothing by constraint',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conname='marche_orders_economics_complete_chk'), NULL);
  r := r || public._qa_s13_ok('N4R4.A8 delivery pricing state is constrained and honest',
        EXISTS (SELECT 1 FROM pg_constraint WHERE conname='marche_orders_delivery_state_chk'), NULL);
  r := r || public._qa_s13_ok('N4R4.A9 rounding law is a pinned immutable function',
        EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace
                 AND proname='marche_merchant_fee_gnf' AND provolatile='i'
                 AND array_to_string(proconfig,',') LIKE '%search_path=public%'), NULL);
  r := r || public._qa_s13_ok('N4R4.A10 clients cannot execute the rounding law directly',
        NOT has_function_privilege('anon','public.marche_merchant_fee_gnf(bigint,integer)','EXECUTE')
    AND NOT has_function_privilege('authenticated','public.marche_merchant_fee_gnf(bigint,integer)','EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R4.A11 no direct client write access to finance policy',
        NOT has_table_privilege('anon','public.finance_policies','INSERT')
    AND NOT has_table_privilege('anon','public.finance_policies','UPDATE')
    AND NOT has_table_privilege('authenticated','public.finance_policies','INSERT')
    AND NOT has_table_privilege('authenticated','public.finance_policies','UPDATE'), NULL);
  r := r || public._qa_s13_ok('N4R4.A12 no direct client write access to order economics',
        NOT has_table_privilege('authenticated','public.marche_orders','UPDATE')
    AND NOT has_table_privilege('authenticated','public.marche_orders','INSERT')
    AND NOT has_table_privilege('anon','public.marche_orders','SELECT'), NULL);
  r := r || public._qa_s13_ok('N4R4.A13 order guard forbids post-commitment economics edits',
        (SELECT prosrc FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='marche_order_guard')
          LIKE '%ECONOMICS_IMMUTABLE%', NULL);
  r := r || public._qa_s13_ok('N4R4.A14 policy editing stays on the god-admin finance surface',
        (SELECT prosrc FROM pg_proc WHERE pronamespace='public'::regnamespace
          AND proname='admin_set_finance_policy') LIKE '%is_god_admin%'
    AND NOT has_function_privilege('anon',
          (SELECT p.oid FROM pg_proc p WHERE p.pronamespace='public'::regnamespace
            AND p.proname='admin_set_finance_policy'),'EXECUTE'), NULL);
  r := r || public._qa_s13_ok('N4R4.A15 has_role remains not executable by anon',
        NOT has_function_privilege('anon','public.has_role(uuid,app_role)','EXECUTE'), NULL);
  v_src := (SELECT prosrc FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='marche_order_commit');
  r := r || public._qa_s13_ok('N4R4.A16 commit reuses the canonical policy resolver',
        v_src LIKE '%finance_policy_at%' AND v_src LIKE '%finance_policy_snapshot%', NULL);
  r := r || public._qa_s13_ok('N4R4.A17 commit moves no money and starts no lifecycle',
        v_src NOT LIKE '%payment_intent%' AND v_src NOT LIKE '%wallet%'
    AND v_src NOT LIKE '%ledger%' AND v_src NOT LIKE '%merchant_payable%'
    AND v_src NOT LIKE '%missions%', NULL);
  r := r || public._qa_s13_ok('N4R4.A18 all R4 definer functions pin search_path',
        (SELECT count(*) FROM pg_proc WHERE pronamespace='public'::regnamespace
          AND proname IN ('marche_order_commit','marche_order_json','marche_merchant_fee_gnf',
                          'admin_set_finance_policy','finance_policy_snapshot')
          AND array_to_string(proconfig,',') NOT LIKE '%search_path%') = 0, NULL);

  -- ============ B. POLICY TRUTH ============
  SELECT * INTO v_pol FROM public.finance_policy_at('marche', now());
  r := r || public._qa_s13_ok('N4R4.B1 an effective marche policy exists', v_pol.id IS NOT NULL, NULL);
  r := r || public._qa_s13_ok('N4R4.B2 default effective merchant fee is exactly 100 bps (1%)',
        v_pol.merchant_platform_fee_bps = 100, v_pol.merchant_platform_fee_bps::text);
  r := r || public._qa_s13_ok('N4R4.B3 the fee is effective-dated, not hardcoded',
        v_pol.effective_from IS NOT NULL, v_pol.effective_from::text);
  r := r || public._qa_s13_ok('N4R4.B4 canonical snapshot exposes the merchant fee rate and basis',
        (public.finance_policy_snapshot('marche', now(), 'chop_pay', 0, 100000)->>'merchant_platform_fee_bps')::int = 100
    AND public.finance_policy_snapshot('marche', now(), 'chop_pay', 0, 100000)->>'merchant_platform_fee_basis'
        = 'merchandise_subtotal', NULL);

  -- ============ C. ROUNDING LAW ============
  r := r || public._qa_s13_ok('N4R4.C1 floor rounding on a non-divisible subtotal',
        public.marche_merchant_fee_gnf(123456, 100) = 1234, public.marche_merchant_fee_gnf(123456,100)::text);
  r := r || public._qa_s13_ok('N4R4.C2 floor rounding never rounds up',
        public.marche_merchant_fee_gnf(199, 100) = 1
    AND public.marche_merchant_fee_gnf(99, 100) = 0, NULL);
  r := r || public._qa_s13_ok('N4R4.C3 zero rate produces zero fee',
        public.marche_merchant_fee_gnf(500000, 0) = 0, NULL);
  r := r || public._qa_s13_ok('N4R4.C4 fee can never exceed the subtotal',
        public.marche_merchant_fee_gnf(1000, 10000) = 1000, NULL);
  r := r || public._qa_s13_ok('N4R4.C5 exact division is exact',
        public.marche_merchant_fee_gnf(100000, 100) = 1000, NULL);
  r := r || public._qa_s13_ok('N4R4.C6 rounding is deterministic across calls',
        public.marche_merchant_fee_gnf(123457, 250) = public.marche_merchant_fee_gnf(123457, 250)
    AND public.marche_merchant_fee_gnf(123457, 250) = 3086, public.marche_merchant_fee_gnf(123457,250)::text);

  -- ============ D. RUNTIME ============
  BEGIN
    v_buy := gen_random_uuid(); v_merch := gen_random_uuid(); v_adm := gen_random_uuid();
    PERFORM public._qa_s13_user(v_buy,'n44b');
    PERFORM public._qa_s13_user(v_merch,'n44m');
    PERFORM public._qa_s13_user(v_adm,'n44a');
    PERFORM public._qa_s13_admin(v_adm);

    INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status)
      VALUES (v_merch,'qa-n44-a-'||substr(v_merch::text,1,8),'QA N44 Store','active','approved')
      RETURNING id INTO v_store;

    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    l_a := public.marche_listing_create(jsonb_build_object('store_id',v_store,'title','QA N44 Item A',
      'category','Autre','price_gnf',50000,'quantity_in_stock',10,'publish',true));
    l_b := public.marche_listing_create(jsonb_build_object('store_id',v_store,'title','QA N44 Item B',
      'category','Autre','price_gnf',25000,'quantity_in_stock',10,'publish',true));
    l_odd := public.marche_listing_create(jsonb_build_object('store_id',v_store,'title','QA N44 Item Odd',
      'category','Autre','price_gnf',41152,'quantity_in_stock',10,'publish',true));

    -- D1 multi-line order freezes exact economics
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_key := 'qa-n44-key-main-'||substr(v_buy::text,1,8);
    v_res := public.marche_order_commit(jsonb_build_object(
      'client_request_id', v_key,
      'items', jsonb_build_array(
        jsonb_build_object('listing_id', l_a, 'qty', 2),
        jsonb_build_object('listing_id', l_b, 'qty', 3)),
      'delivery_address','Kaloum, Conakry'));
    v_o1 := (v_res->>'id')::uuid;
    SELECT * INTO v_ord FROM public.marche_orders WHERE id = v_o1;
    v_fee1 := v_ord.merchant_fee_gnf; v_pay1 := v_ord.merchant_payable_gnf;
    v_bps1 := v_ord.merchant_platform_fee_bps; v_polid1 := v_ord.fee_policy_id;

    r := r || public._qa_s13_ok('N4R4.D1 multi-line subtotal frozen server-side',
          v_ord.merchandise_subtotal_gnf = 175000, v_ord.merchandise_subtotal_gnf::text);
    r := r || public._qa_s13_ok('N4R4.D2 merchant platform fee frozen at 1% of subtotal',
          v_ord.merchant_fee_gnf = 1750, v_ord.merchant_fee_gnf::text);
    r := r || public._qa_s13_ok('N4R4.D3 merchant payable = subtotal - fee exactly',
          v_ord.merchant_payable_gnf = 173250
      AND v_ord.merchant_payable_gnf = v_ord.merchandise_subtotal_gnf - v_ord.merchant_fee_gnf,
          v_ord.merchant_payable_gnf::text);
    r := r || public._qa_s13_ok('N4R4.D4 policy identity, rate and effective date frozen on the order',
          v_ord.fee_policy_id IS NOT NULL AND v_ord.merchant_platform_fee_bps = 100
      AND v_ord.fee_policy_effective_from IS NOT NULL AND v_ord.economics_resolved_at IS NOT NULL, NULL);
    r := r || public._qa_s13_ok('N4R4.D5 frozen snapshot is self-sufficient for later settlement',
          v_ord.economics_snapshot->>'schema' = 'chopchop.marche.order_economics'
      AND (v_ord.economics_snapshot->>'merchant_platform_fee_bps')::int = 100
      AND (v_ord.economics_snapshot->>'merchandise_subtotal_gnf')::bigint = 175000
      AND (v_ord.economics_snapshot->>'merchant_payable_gnf')::bigint = 173250
      AND v_ord.economics_snapshot->>'rounding' = 'floor_gnf_clamped_to_subtotal'
      AND (v_ord.economics_snapshot->'policy_snapshot'->>'policy_id')::uuid = v_ord.fee_policy_id, NULL);
    r := r || public._qa_s13_ok('N4R4.D6 customer delivery economics stay a separate, unresolved axis',
          v_ord.delivery_charge_gnf IS NULL AND v_ord.delivery_pricing_state = 'unresolved'
      AND (v_ord.economics_snapshot->>'customer_delivery_charge_gnf') IS NULL, NULL);
    r := r || public._qa_s13_ok('N4R4.D7 merchant payable is merchandise-only, no delivery netting',
          v_ord.merchant_payable_gnf = v_ord.merchandise_subtotal_gnf - v_ord.merchant_fee_gnf, NULL);
    r := r || public._qa_s13_ok('N4R4.D8 buyer payload never exposes merchant economics',
          NOT (v_res ? 'merchant_fee_gnf') AND NOT (v_res ? 'merchant_payable_gnf')
      AND NOT (v_res ? 'economics_snapshot'), NULL);
    r := r || public._qa_s13_ok('N4R4.D9 buyer payload still shows honest delivery state',
          v_res->>'delivery_pricing_state' = 'unresolved', v_res->>'delivery_pricing_state');

    -- D10 merchant + admin visibility
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
    v_res2 := public.marche_order_get(v_o1);
    r := r || public._qa_s13_ok('N4R4.D10 merchant sees its own frozen economics',
          (v_res2->>'merchant_fee_gnf')::bigint = 1750
      AND (v_res2->>'merchant_payable_gnf')::bigint = 173250
      AND (v_res2->>'merchant_platform_fee_bps')::int = 100, NULL);
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_adm), true);
    v_res2 := public.marche_order_get(v_o1);
    r := r || public._qa_s13_ok('N4R4.D11 admin sees frozen economics',
          (v_res2->>'merchant_payable_gnf')::bigint = 173250, NULL);

    -- D12 odd subtotal rounding at runtime
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    v_res := public.marche_order_commit(jsonb_build_object(
      'client_request_id','qa-n44-key-odd-'||substr(v_buy::text,1,8),
      'items', jsonb_build_array(jsonb_build_object('listing_id', l_odd, 'qty', 3))));
    SELECT * INTO v_ord2 FROM public.marche_orders WHERE id = (v_res->>'id')::uuid;
    r := r || public._qa_s13_ok('N4R4.D12 runtime rounding floors a non-divisible subtotal',
          v_ord2.merchandise_subtotal_gnf = 123456 AND v_ord2.merchant_fee_gnf = 1234
      AND v_ord2.merchant_payable_gnf = 122222, v_ord2.merchant_fee_gnf::text);
    r := r || public._qa_s13_ok('N4R4.D13 payable never negative, fee never above subtotal',
          v_ord2.merchant_payable_gnf >= 0 AND v_ord2.merchant_fee_gnf <= v_ord2.merchandise_subtotal_gnf, NULL);

    -- ============ E. IDEMPOTENCY ============
    v_res2 := public.marche_order_commit(jsonb_build_object(
      'client_request_id', v_key,
      'items', jsonb_build_array(
        jsonb_build_object('listing_id', l_a, 'qty', 2),
        jsonb_build_object('listing_id', l_b, 'qty', 3)),
      'delivery_address','Kaloum, Conakry'));
    r := r || public._qa_s13_ok('N4R4.E1 replay returns the same order',
          (v_res2->>'id')::uuid = v_o1, v_res2->>'id');
    SELECT * INTO v_ord FROM public.marche_orders WHERE id = v_o1;
    r := r || public._qa_s13_ok('N4R4.E2 replay preserves identical economics and policy snapshot',
          v_ord.merchant_fee_gnf = v_fee1 AND v_ord.merchant_payable_gnf = v_pay1
      AND v_ord.merchant_platform_fee_bps = v_bps1 AND v_ord.fee_policy_id = v_polid1, NULL);
    SELECT count(*) INTO v_n FROM public.marche_orders WHERE buyer_user_id = v_buy AND client_request_id = v_key;
    r := r || public._qa_s13_ok('N4R4.E3 exactly one order per idempotency key', v_n = 1, v_n::text);

    -- ============ G. NO CLIENT AUTHORITY ============
    v_err := NULL;
    BEGIN
      PERFORM public.marche_order_commit(jsonb_build_object('client_request_id','qa-n44-attack-fee',
        'merchant_fee_gnf', 0, 'items', jsonb_build_array(jsonb_build_object('listing_id', l_a,'qty',1))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R4.G1 client-sent merchant fee is refused fail-closed',
          v_err = 'CLIENT_ECONOMICS_NOT_ALLOWED', v_err);
    v_err := NULL;
    BEGIN
      PERFORM public.marche_order_commit(jsonb_build_object('client_request_id','qa-n44-attack-pay',
        'merchant_payable_gnf', 999999, 'items', jsonb_build_array(jsonb_build_object('listing_id', l_a,'qty',1))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R4.G2 client-sent payable is refused', v_err = 'CLIENT_ECONOMICS_NOT_ALLOWED', v_err);
    v_err := NULL;
    BEGIN
      PERFORM public.marche_order_commit(jsonb_build_object('client_request_id','qa-n44-attack-pol',
        'fee_policy_id', gen_random_uuid(), 'items', jsonb_build_array(jsonb_build_object('listing_id', l_a,'qty',1))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R4.G3 client-sent policy id is refused', v_err = 'CLIENT_ECONOMICS_NOT_ALLOWED', v_err);
    v_err := NULL;
    BEGIN
      PERFORM public.marche_order_commit(jsonb_build_object('client_request_id','qa-n44-attack-bps',
        'merchant_platform_fee_bps', 0, 'items', jsonb_build_array(jsonb_build_object('listing_id', l_a,'qty',1))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R4.G4 client-sent rate is refused', v_err = 'CLIENT_ECONOMICS_NOT_ALLOWED', v_err);
    v_err := NULL;
    BEGIN
      PERFORM public.marche_order_commit(jsonb_build_object('client_request_id','qa-n44-attack-del',
        'delivery_charge_gnf', 0, 'items', jsonb_build_array(jsonb_build_object('listing_id', l_a,'qty',1))));
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R4.G5 client-sent delivery charge is refused',
          v_err = 'CLIENT_ECONOMICS_NOT_ALLOWED', v_err);
    v_err := NULL;
    BEGIN
      PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
      UPDATE public.marche_orders SET merchant_fee_gnf = 0 WHERE id = v_o1;
    EXCEPTION WHEN OTHERS THEN v_err := SQLERRM; END;
    r := r || public._qa_s13_ok('N4R4.G6 committed economics cannot be rewritten',
          v_err IS NOT NULL, v_err);
    SELECT * INTO v_ord FROM public.marche_orders WHERE id = v_o1;
    r := r || public._qa_s13_ok('N4R4.G7 economics survived the tamper attempt',
          v_ord.merchant_fee_gnf = v_fee1, v_ord.merchant_fee_gnf::text);

    -- ============ F. EFFECTIVE-DATED POLICY CHANGE (fixture-safe, rolled back) ============
    BEGIN
      PERFORM set_config('request.jwt.claims', public._as_user_claims(v_adm), true);
      PERFORM public.admin_set_finance_policy(
        p_mission_type := 'marche',
        p_effective_from := now(),
        p_note := 'QA N44 temporary marche merchant fee change (rolled back)',
        p_merchant_platform_fee_bps := 250);
      SELECT * INTO v_pol FROM public.finance_policy_at('marche', now());
      r := r || public._qa_s13_ok('N4R4.F1 new effective policy resolves to the new rate',
            v_pol.merchant_platform_fee_bps = 250, v_pol.merchant_platform_fee_bps::text);

      PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
      v_res := public.marche_order_commit(jsonb_build_object(
        'client_request_id','qa-n44-key-after-'||substr(v_buy::text,1,8),
        'items', jsonb_build_array(jsonb_build_object('listing_id', l_a, 'qty', 2))));
      v_o2 := (v_res->>'id')::uuid;
      SELECT * INTO v_ord2 FROM public.marche_orders WHERE id = v_o2;
      r := r || public._qa_s13_ok('N4R4.F2 the new order uses the new effective rate',
            v_ord2.merchant_platform_fee_bps = 250 AND v_ord2.merchant_fee_gnf = 2500
        AND v_ord2.merchant_payable_gnf = 97500, v_ord2.merchant_fee_gnf::text);
      SELECT * INTO v_ord FROM public.marche_orders WHERE id = v_o1;
      r := r || public._qa_s13_ok('N4R4.F3 the historical order still carries its original 1% economics',
            v_ord.merchant_platform_fee_bps = 100 AND v_ord.merchant_fee_gnf = v_fee1
        AND v_ord.merchant_payable_gnf = v_pay1 AND v_ord.fee_policy_id = v_polid1, NULL);
      r := r || public._qa_s13_ok('N4R4.F4 the two orders reference different policy versions',
            v_ord2.fee_policy_id <> v_ord.fee_policy_id, NULL);
      v_res2 := public.marche_order_commit(jsonb_build_object(
        'client_request_id', v_key,
        'items', jsonb_build_array(
          jsonb_build_object('listing_id', l_a, 'qty', 2),
          jsonb_build_object('listing_id', l_b, 'qty', 3)),
        'delivery_address','Kaloum, Conakry'));
      SELECT * INTO v_ord FROM public.marche_orders WHERE id = v_o1;
      r := r || public._qa_s13_ok('N4R4.F5 replay after a policy change never re-snapshots the newer policy',
            (v_res2->>'id')::uuid = v_o1 AND v_ord.merchant_platform_fee_bps = 100
        AND v_ord.fee_policy_id = v_polid1, NULL);
      RAISE EXCEPTION 'QA_N44_ROLLBACK';
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM <> 'QA_N44_ROLLBACK' THEN
        r := r || public._qa_s13_ok('N4R4.F0 policy-change block completed', false, SQLERRM);
      END IF;
    END;
    SELECT count(*) INTO v_n FROM public.finance_policies WHERE note LIKE 'QA N44%';
    r := r || public._qa_s13_ok('N4R4.F6 the temporary QA policy row was rolled back', v_n = 0, v_n::text);
    SELECT * INTO v_pol FROM public.finance_policy_at('marche', now());
    r := r || public._qa_s13_ok('N4R4.F7 production marche policy restored to 100 bps',
          v_pol.merchant_platform_fee_bps = 100, v_pol.merchant_platform_fee_bps::text);

    -- ============ K/L. R3 + R3.5 INTEGRITY ============
    PERFORM set_config('request.jwt.claims', public._as_user_claims(v_buy), true);
    r := r || public._qa_s13_ok('N4R4.K1 stock reservation still applies at commitment',
          (SELECT quantity_reserved FROM public.marketplace_listings WHERE id = l_a) = 2,
          (SELECT quantity_reserved::text FROM public.marketplace_listings WHERE id = l_a));
    r := r || public._qa_s13_ok('N4R4.K2 cancellation still releases reserved stock',
          (public.marche_order_cancel(v_o1,'qa n44'))->>'status' = 'cancelled', NULL);
    r := r || public._qa_s13_ok('N4R4.K3 released stock returns to zero for that line',
          (SELECT quantity_reserved FROM public.marketplace_listings WHERE id = l_a) = 0, NULL);
    SELECT * INTO v_ord FROM public.marche_orders WHERE id = v_o1;
    r := r || public._qa_s13_ok('N4R4.K4 cancellation does not rewrite frozen economics',
          v_ord.merchant_fee_gnf = v_fee1 AND v_ord.merchant_payable_gnf = v_pay1, NULL);
    r := r || public._qa_s13_ok('N4R4.L1 R3.5 basket profile still created exactly once',
          (SELECT count(*) FROM public.marche_fulfillment_profiles WHERE order_id = v_o1) = 1, NULL);
    r := r || public._qa_s13_ok('N4R4.L2 ORDER_COMMITTED remains the only milestone',
          (SELECT count(*) FROM public.marche_fulfillment_events WHERE order_id = v_o1) = 1
      AND (SELECT event_type FROM public.marche_fulfillment_events WHERE order_id = v_o1) = 'ORDER_COMMITTED', NULL);
    r := r || public._qa_s13_ok('N4R4.L3 category snapshots still frozen on lines',
          (SELECT count(*) FROM public.marche_order_items WHERE order_id = v_o1
            AND category_snapshot IS NOT NULL) = 2, NULL);

  EXCEPTION WHEN OTHERS THEN
    r := r || public._qa_s13_ok('N4R4.FIXTURE runtime block completed without unhandled error', false, SQLERRM);
  END;

  -- ============ CLEANUP ============
  PERFORM set_config('request.jwt.claims','', true);
  PERFORM set_config('marche.rpc','1', true);
  DELETE FROM public.marche_fulfillment_observations WHERE order_id IN
    (SELECT id FROM public.marche_orders WHERE buyer_user_id = v_buy);
  DELETE FROM public.marche_fulfillment_events WHERE order_id IN
    (SELECT id FROM public.marche_orders WHERE buyer_user_id = v_buy);
  DELETE FROM public.marche_fulfillment_profiles WHERE order_id IN
    (SELECT id FROM public.marche_orders WHERE buyer_user_id = v_buy);
  DELETE FROM public.marche_order_items WHERE order_id IN
    (SELECT id FROM public.marche_orders WHERE buyer_user_id = v_buy);
  DELETE FROM public.marche_orders WHERE buyer_user_id = v_buy;
  UPDATE public.marketplace_listings SET quantity_reserved = 0
   WHERE id IN (l_a, l_b, l_odd) AND quantity_reserved <> 0;
  PERFORM set_config('marche.rpc','', true);
  DELETE FROM public.listing_images WHERE listing_id IN (l_a,l_b,l_odd);
  DELETE FROM public.listing_metrics WHERE listing_id IN (l_a,l_b,l_odd);
  DELETE FROM public.marketplace_listings WHERE seller_id IN (v_buy, v_merch, v_adm);
  DELETE FROM public.account_bans WHERE user_id IN (v_buy, v_merch, v_adm);
  DELETE FROM public.merchant_stores WHERE owner_user_id = v_merch;
  DELETE FROM public.admin_users WHERE user_id = v_adm;
  DELETE FROM public.wallet_transactions
   WHERE from_wallet_id IN (SELECT id FROM public.wallets WHERE owner_user_id IN (v_buy,v_merch,v_adm))
      OR to_wallet_id IN (SELECT id FROM public.wallets WHERE owner_user_id IN (v_buy,v_merch,v_adm));
  DELETE FROM public.wallets WHERE owner_user_id IN (v_buy,v_merch,v_adm);
  DELETE FROM auth.users WHERE id IN (v_buy,v_merch,v_adm);

  -- ============ J/M. SYSTEMIC ============
  SELECT count(*) INTO v_w1 FROM public.wallets;
  SELECT count(*) INTO v_wt1 FROM public.wallet_transactions;
  SELECT count(*) INTO v_lj1 FROM public.ledger_journals;
  SELECT count(*) INTO v_lp1 FROM public.ledger_postings;
  SELECT count(*) INTO v_pi1 FROM public.payment_intents;
  SELECT count(*) INTO v_ms1 FROM public.missions;
  SELECT count(*) INTO v_mp1 FROM public.merchant_payables;
  SELECT count(*) INTO v_fpc1 FROM public.finance_policies;
  SELECT count(*) INTO v_total1 FROM public.marketplace_listings;
  SELECT count(*) INTO v_none1 FROM public.marketplace_listings WHERE store_id IS NULL;
  SELECT count(*) INTO v_demo1 FROM public.v_marche_listing_truth WHERE is_demo;
  SELECT COALESCE(sum(quantity_reserved),0) INTO v_res1 FROM public.marketplace_listings;
  SELECT jsonb_object_agg(key, enabled) INTO v_flags1 FROM public.feature_flags;

  r := r || public._qa_s13_ok('N4R4.J1 zero wallet / ledger / payment / mission drift',
        v_w1=v_w0 AND v_wt1=v_wt0 AND v_lj1=v_lj0 AND v_lp1=v_lp0 AND v_pi1=v_pi0 AND v_ms1=v_ms0,
        format('%s/%s/%s/%s/%s/%s', v_w1-v_w0, v_wt1-v_wt0, v_lj1-v_lj0, v_lp1-v_lp0, v_pi1-v_pi0, v_ms1-v_ms0));
  r := r || public._qa_s13_ok('N4R4.J2 zero merchant settlement / payable drift', v_mp1 = v_mp0,
        format('%s->%s', v_mp0, v_mp1));
  r := r || public._qa_s13_ok('N4R4.J3 finance policy population unchanged by QA', v_fpc1 = v_fpc0,
        format('%s->%s', v_fpc0, v_fpc1));
  r := r || public._qa_s13_ok('N4R4.M1 feature flags byte-identical', v_flags1 = v_flags0, NULL);
  r := r || public._qa_s13_ok('N4R4.M2 production listing population unchanged', v_total1 = v_total0,
        format('%s->%s', v_total0, v_total1));
  r := r || public._qa_s13_ok('N4R4.M3 storeless quarantine unchanged', v_none1 = v_none0,
        format('%s->%s', v_none0, v_none1));
  r := r || public._qa_s13_ok('N4R4.M4 demo quarantine intact', v_demo1 = v_demo0 AND v_demo1 > 0, v_demo1::text);
  r := r || public._qa_s13_ok('N4R4.M5 reserved stock back to baseline', v_res1 = v_res0,
        format('%s->%s', v_res0, v_res1));
  SELECT count(*) INTO v_n FROM public.marketplace_listings WHERE title LIKE 'QA N44%';
  r := r || public._qa_s13_ok('N4R4.M6 zero listing fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_orders WHERE client_request_id LIKE 'qa-n44-%';
  r := r || public._qa_s13_ok('N4R4.M7 zero order fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.merchant_stores WHERE slug LIKE 'qa-n44-%';
  r := r || public._qa_s13_ok('N4R4.M8 zero store fixture residue', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_orders
   WHERE merchant_fee_gnf IS NOT NULL
     AND (merchant_payable_gnf <> merchandise_subtotal_gnf - merchant_fee_gnf
       OR merchant_fee_gnf < 0 OR merchant_fee_gnf > merchandise_subtotal_gnf);
  r := r || public._qa_s13_ok('N4R4.M9 global economics invariant holds across all orders', v_n = 0, v_n::text);
  SELECT count(*) INTO v_n FROM public.marche_orders WHERE delivery_charge_gnf IS NOT NULL;
  r := r || public._qa_s13_ok('N4R4.M10 no order fabricates customer delivery money', v_n = 0, v_n::text);
  r := r || public._qa_s13_ok('N4R4.M11 has_role still not executable by anon',
        NOT has_function_privilege('anon','public.has_role(uuid,app_role)','EXECUTE'), NULL);

  RETURN public._qa_s13_summary(34, r);
END $qa$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r4() FROM PUBLIC, anon, authenticated;