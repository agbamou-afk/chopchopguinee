CREATE OR REPLACE FUNCTION public.repas_order_receipt(p_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_o public.food_orders%ROWTYPE;
  v_r public.food_restaurants%ROWTYPE;
  v_m public.missions%ROWTYPE;
  v_role text;
  v_items jsonb;
  v_lines_total bigint := 0;
  v_promo_name text := NULL;
  v_promo_frozen boolean := false;
  v_total bigint;
  v_merch bigint;
  v_del bigint;
  v_fee bigint;
  v_custody jsonb;
  v_payload jsonb;
  v_engine_state text := NULL;
  v_rail text := NULL;
  v_pay_state text;
  v_settled boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  SELECT * INTO v_o FROM public.food_orders WHERE id = p_order_id;
  IF v_o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  SELECT * INTO v_r FROM public.food_restaurants WHERE id = v_o.restaurant_id;
  SELECT * INTO v_m FROM public.missions
   WHERE ref_food_order_id = p_order_id ORDER BY created_at DESC LIMIT 1;

  IF v_uid = v_o.user_id THEN v_role := 'customer';
  ELSIF v_uid = v_r.owner_user_id THEN v_role := 'merchant';
  ELSIF v_m.id IS NOT NULL AND v_uid = v_m.courier_id THEN v_role := 'courier';
  ELSIF public._finance_privileged(v_uid) THEN v_role := 'finance';
  ELSE RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'name', i.name_snapshot,
           'qty', i.qty,
           'unit_price_gnf', i.unit_price_gnf,
           'line_total_gnf', i.unit_price_gnf * i.qty) ORDER BY i.created_at, i.id), '[]'::jsonb),
         COALESCE(SUM(i.unit_price_gnf * i.qty), 0)
    INTO v_items, v_lines_total
    FROM public.food_order_items i
   WHERE i.order_id = p_order_id;

  -- R7 historical truth: the promotion name is a FROZEN receipt fact taken from the
  -- pricing snapshot captured at commitment. The current (mutable / disable-able /
  -- deletable) promotion row is never consulted as historical truth.
  v_promo_name := NULLIF(v_o.pricing_snapshot->>'promotion_name', '');
  v_promo_frozen := (v_promo_name IS NOT NULL);

  v_merch := COALESCE(v_o.subtotal_gnf, 0);
  v_del   := COALESCE(v_o.delivery_fee_gnf, 0);
  v_fee   := COALESCE(v_o.platform_fee_gnf, 0);
  v_total := COALESCE(v_o.order_total_gnf, v_merch + v_del + v_fee);

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'boundary', e.boundary,
           'method', e.method,
           'occurred_at', e.occurred_at) ORDER BY e.occurred_at), '[]'::jsonb)
    INTO v_custody
    FROM public.repas_custody_events e
   WHERE e.order_id = p_order_id;

  -- Canonical tender truth: same source of truth as repas_order_tracking.
  SELECT state INTO v_engine_state FROM public.chop_pay_order_runtime
   WHERE source_module = 'repas' AND source_id = p_order_id;
  IF v_engine_state IS NOT NULL THEN
    v_rail := 'chop_pay';
    v_pay_state := CASE v_engine_state
      WHEN 'completed' THEN 'paid'
      WHEN 'cancelled' THEN 'released'
      WHEN 'merchant_rejected' THEN 'released'
      WHEN 'disputed' THEN 'disputed'
      WHEN 'dispute_resolved' THEN 'dispute_resolved'
      ELSE 'authorized'
    END;
  ELSE
    SELECT state INTO v_engine_state FROM public.cash_order_runtime
     WHERE source_module = 'repas' AND source_id = p_order_id;
    IF v_engine_state IS NOT NULL THEN
      v_rail := 'cash';
      v_pay_state := CASE v_engine_state
        WHEN 'completed' THEN 'collected'
        WHEN 'cancelled' THEN 'cancelled'
        WHEN 'merchant_rejected' THEN 'cancelled'
        WHEN 'disputed' THEN 'disputed'
        WHEN 'dispute_resolved' THEN 'dispute_resolved'
        ELSE 'due'
      END;
    ELSIF v_o.payment_method::text = 'cash' THEN
      -- Canonical cash lifecycle creates no cash_order_runtime before courier
      -- engagement. Derive only the minimum truthful state from the committed
      -- tender; never claim 'collected' without a completed cash runtime.
      v_rail := 'cash';
      v_pay_state := CASE WHEN v_o.state::text = 'cancelled' THEN 'cancelled' ELSE 'due' END;
    ELSE
      v_rail := NULL;
      v_pay_state := CASE WHEN v_o.state::text = 'cancelled' THEN 'cancelled' ELSE 'unknown' END;
    END IF;
  END IF;
  v_settled := v_pay_state IN ('paid','collected');

  v_payload := jsonb_build_object(
    'order_id', v_o.id,
    'viewer_role', v_role,
    'restaurant', jsonb_build_object('id', v_r.id, 'name', v_r.name, 'district', v_r.district),
    'fulfillment', v_o.fulfillment::text,
    'state', v_o.state::text,
    'payment_method', v_o.payment_method::text,
    'payment_status', v_o.payment_status,
    'legacy_payment_status', v_o.payment_status,
    'engine_state', v_engine_state,
    'payment_rail', v_rail,
    'payment_state', v_pay_state,
    'payment_settled', v_settled,
    'created_at', v_o.created_at,
    'paid_at', v_o.paid_at,
    'completed_at', v_o.completed_at,
    'items', v_items,
    'merchandise_subtotal_gnf', v_merch,
    'items_line_total_gnf', v_lines_total,
    'base_delivery_fee_gnf', COALESCE(v_o.base_delivery_fee_gnf, 0),
    'promo_discount_gnf', COALESCE(v_o.promo_discount_gnf, 0),
    'promotion_name', v_promo_name,
    'promotion_name_frozen', v_promo_frozen,
    'delivery_fee_gnf', v_del,
    'platform_fee_gnf', v_fee,
    'order_total_gnf', v_total,
    'cancelled', v_o.state::text = 'cancelled',
    'custody_timeline', v_custody,
    'totals_reconcile', (v_merch + v_del + v_fee = v_total) AND (v_lines_total = v_merch));

  IF v_role IN ('courier','finance') THEN
    v_payload := v_payload || jsonb_build_object(
      'courier_payout_gnf', COALESCE(v_o.courier_payout_gnf, 0));
  END IF;

  RETURN v_payload;
END;
$function$;

CREATE OR REPLACE FUNCTION public._qa_node3_repas_r7_readtruth()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_cust uuid; v_merch uuid;
  v_store uuid; v_resto uuid; v_item uuid;
  v_promo uuid; v_op uuid; v_oc uuid;
  v_res jsonb; v_rc jsonb; v_rc2 jsonb; v_snap jsonb;
  v_n int; v_j int; v_wal text; v_wal2 text;
  v_cash_flag boolean;
BEGIN
  v_cust := gen_random_uuid(); v_merch := gen_random_uuid();
  PERFORM public._qa_s13_user(v_cust,'n3r7rc');
  PERFORM public._qa_s13_user(v_merch,'n3r7rm');
  PERFORM public._qa_s13_wallet(v_cust,'client',5000000,0);
  PERFORM public._qa_s13_wallet(v_merch,'merchant',0,0);

  INSERT INTO public.merchant_stores(owner_user_id, slug, name, delivery_available, status)
    VALUES (v_merch, 'qa-n3r7-store-rt-'||substr(v_merch::text,1,8), 'QA N3R7 RT Store', true, 'active')
    RETURNING id INTO v_store;
  INSERT INTO public.food_restaurants(owner_user_id, merchant_store_id, slug, name, status,
      is_open, delivery_available, pickup_available, choppay_enabled, prep_time_min, latitude, longitude)
    VALUES (v_merch, v_store, 'qa-n3r7-resto-rt-'||substr(v_merch::text,1,8), 'QA N3R7 RT Resto',
            'active', true, true, true, true, 20, 9.5370, -13.6785)
    RETURNING id INTO v_resto;
  INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
    VALUES (v_resto,'QA R7 RT Plat',100000,true) RETURNING id INTO v_item;

  -- ============ P14. FROZEN PROMOTION NAME ON THE RECEIPT ============
  r := r || public._qa_s13_ok('P14.0 the receipt no longer reads the live promotion table',
        pg_get_functiondef(to_regprocedure('public.repas_order_receipt(uuid)'))
          NOT LIKE '%FROM public.repas_pricing_promotions%', NULL);
  r := r || public._qa_s13_ok('P14.1 the receipt reads the promotion name from the frozen snapshot',
        pg_get_functiondef(to_regprocedure('public.repas_order_receipt(uuid)'))
          LIKE '%pricing_snapshot->>''promotion_name''%', NULL);

  INSERT INTO public.repas_pricing_promotions(name, reason, fulfillment_scope,
      delivery_discount_gnf, enabled, starts_at, ends_at, created_by)
    VALUES ('QA R7 RT Promo ORIGINALE', 'qa r7 readtruth', 'both',
            3000, true, now() - interval '1 hour', now() + interval '1 hour', v_merch)
    RETURNING id INTO v_promo;

  PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
  v_res := public.repas_order_create(v_resto,
      jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
      'delivery','choppay', gen_random_uuid(), 'QA R7 RT Promo Adresse', 9.5395, -13.6760);
  v_op := (v_res->>'order_id')::uuid;
  SELECT pricing_snapshot INTO v_snap FROM public.food_orders WHERE id = v_op;
  v_rc := public.repas_order_receipt(v_op);

  r := r || public._qa_s13_ok('P14.2 the promotional order actually froze this promotion',
        (SELECT promotion_id FROM public.food_orders WHERE id=v_op) = v_promo
        AND v_snap->>'promotion_name' = 'QA R7 RT Promo ORIGINALE', v_snap->>'promotion_name');
  r := r || public._qa_s13_ok('P14.3 the receipt shows the frozen promotion name',
        v_rc->>'promotion_name' = 'QA R7 RT Promo ORIGINALE', v_rc->>'promotion_name');
  r := r || public._qa_s13_ok('P14.4 the receipt marks the promotion name as frozen',
        (v_rc->>'promotion_name_frozen')::boolean, NULL);
  r := r || public._qa_s13_ok('P14.5 a real discount was applied to this receipt',
        (v_rc->>'promo_discount_gnf')::bigint = 3000, v_rc->>'promo_discount_gnf');

  -- Mutate the CURRENT promotion context: rename + disable + move it out of window.
  UPDATE public.repas_pricing_promotions
     SET name = 'QA R7 RT Promo RENOMMEE', enabled = false,
         disabled_at = now(), disabled_by = v_merch,
         ends_at = now() - interval '1 minute'
   WHERE id = v_promo;

  v_rc2 := public.repas_order_receipt(v_op);
  r := r || public._qa_s13_ok('P14.6 renaming + disabling the promotion does NOT rewrite history',
        v_rc2->>'promotion_name' = 'QA R7 RT Promo ORIGINALE', v_rc2->>'promotion_name');
  r := r || public._qa_s13_ok('P14.7 the frozen receipt amounts are byte-stable after the change',
        v_rc2->>'base_delivery_fee_gnf' = v_rc->>'base_delivery_fee_gnf'
    AND v_rc2->>'promo_discount_gnf'    = v_rc->>'promo_discount_gnf'
    AND v_rc2->>'delivery_fee_gnf'      = v_rc->>'delivery_fee_gnf'
    AND v_rc2->>'platform_fee_gnf'      = v_rc->>'platform_fee_gnf'
    AND v_rc2->>'order_total_gnf'       = v_rc->>'order_total_gnf',
        v_rc2->>'order_total_gnf');
  r := r || public._qa_s13_ok('P14.8 the receipt still reconciles after the promotion change',
        (v_rc2->>'totals_reconcile')::boolean, NULL);

  -- Deleting the promotion row entirely must not break or alter the historical receipt.
  UPDATE public.food_orders SET promotion_id = NULL WHERE id = v_op;
  DELETE FROM public.repas_pricing_promotions WHERE id = v_promo;
  v_rc2 := public.repas_order_receipt(v_op);
  r := r || public._qa_s13_ok('P14.9 the receipt survives deletion of the promotion row',
        v_rc2->>'promotion_name' = 'QA R7 RT Promo ORIGINALE'
    AND v_rc2->>'order_total_gnf' = v_rc->>'order_total_gnf', v_rc2->>'promotion_name');

  -- Legacy order without a frozen key returns NULL, never a borrowed current name.
  INSERT INTO public.repas_pricing_promotions(name, reason, fulfillment_scope,
      delivery_discount_gnf, enabled, starts_at, ends_at, created_by)
    VALUES ('QA R7 RT Promo ACTUELLE', 'qa r7 readtruth legacy', 'both',
            3000, true, now() - interval '1 hour', now() + interval '1 hour', v_merch);
  UPDATE public.food_orders SET pricing_snapshot = (pricing_snapshot - 'promotion_name')
   WHERE id = v_op;
  v_rc2 := public.repas_order_receipt(v_op);
  r := r || public._qa_s13_ok('P14.10 a legacy order without a frozen name returns null, not today''s promo',
        (v_rc2->>'promotion_name') IS NULL, COALESCE(v_rc2->>'promotion_name','<null>'));
  r := r || public._qa_s13_ok('P14.11 a legacy receipt is explicitly flagged as not frozen',
        (v_rc2->>'promotion_name_frozen')::boolean IS FALSE, NULL);
  r := r || public._qa_s13_ok('P14.12 legacy fallback never presents the current promotion as a receipt fact',
        (v_rc2::text NOT LIKE '%QA R7 RT Promo ACTUELLE%'), NULL);

  -- ============ P15. PRE-ENGAGEMENT CASH IS DUE, NEVER UNKNOWN ============
  SELECT enabled INTO v_cash_flag FROM public.feature_flags WHERE key = 'cash_order_funding_enabled';
  PERFORM public._qa_s13_flag('cash_order_funding_enabled', true);

  SELECT count(*) INTO v_j FROM public.ledger_journals;
  SELECT string_agg(w.owner_user_id::text||':'||w.balance_gnf||':'||w.held_gnf, '|' ORDER BY w.owner_user_id)
    INTO v_wal FROM public.wallets w
   WHERE w.owner_user_id IN (v_cust, v_merch) OR w.party_type = 'master';

  PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
  v_res := public.repas_order_create(v_resto,
      jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
      'delivery','cash', gen_random_uuid(), 'QA R7 RT Cash Adresse', 9.5395, -13.6760);
  v_oc := (v_res->>'order_id')::uuid;

  SELECT count(*) INTO v_n FROM public.cash_order_runtime
   WHERE source_module='repas' AND source_id = v_oc;
  r := r || public._qa_s13_ok('P15.0 a committed cash order has no cash runtime before courier engagement',
        v_n = 0, v_n::text);

  v_rc := public.repas_order_receipt(v_oc);
  r := r || public._qa_s13_ok('P15.1 a pre-engagement cash receipt is on the cash rail',
        v_rc->>'payment_rail' = 'cash', COALESCE(v_rc->>'payment_rail','<null>'));
  r := r || public._qa_s13_ok('P15.2 a pre-engagement cash receipt is due, never unknown',
        v_rc->>'payment_state' = 'due', v_rc->>'payment_state');
  r := r || public._qa_s13_ok('P15.3 a due cash receipt is never settled',
        (v_rc->>'payment_settled')::boolean IS FALSE, v_rc->>'payment_settled');
  r := r || public._qa_s13_ok('P15.4 no engine state is invented before a runtime exists',
        (v_rc->>'engine_state') IS NULL, COALESCE(v_rc->>'engine_state','<null>'));
  r := r || public._qa_s13_ok('P15.5 a due cash receipt is never reported as collected',
        v_rc->>'payment_state' <> 'collected', v_rc->>'payment_state');
  r := r || public._qa_s13_ok('P15.6 the committed tender is still the order tender',
        v_rc->>'payment_method' = 'cash', v_rc->>'payment_method');

  PERFORM public.repas_customer_cancel_order(v_oc, 'QA R7 readtruth cash cancellation proof');
  v_rc2 := public.repas_order_receipt(v_oc);
  r := r || public._qa_s13_ok('P15.7 a cancelled pre-engagement cash order reports cash/cancelled',
        v_rc2->>'payment_rail' = 'cash' AND v_rc2->>'payment_state' = 'cancelled',
        v_rc2->>'payment_state');
  r := r || public._qa_s13_ok('P15.8 the cancelled cash receipt is unsettled',
        (v_rc2->>'payment_settled')::boolean IS FALSE, NULL);
  SELECT count(*) INTO v_n FROM public.cash_order_runtime
   WHERE source_module='repas' AND source_id = v_oc;
  r := r || public._qa_s13_ok('P15.9 cancellation fabricated no cash runtime', v_n = 0, v_n::text);
  r := r || public._qa_s13_ok('P15.10 the cash receipt totals still reconcile after cancellation',
        (v_rc2->>'totals_reconcile')::boolean
    AND v_rc2->>'order_total_gnf' = v_rc->>'order_total_gnf', v_rc2->>'order_total_gnf');

  SELECT count(*) INTO v_n FROM public.ledger_journals;
  r := r || public._qa_s13_ok('P15.11 the pre-engagement cash path moved no ledger value',
        v_n = v_j, v_n::text);
  SELECT string_agg(w.owner_user_id::text||':'||w.balance_gnf||':'||w.held_gnf, '|' ORDER BY w.owner_user_id)
    INTO v_wal2 FROM public.wallets w
   WHERE w.owner_user_id IN (v_cust, v_merch) OR w.party_type = 'master';
  r := r || public._qa_s13_ok('P15.12 the pre-engagement cash path moved no wallet value',
        v_wal2 IS NOT DISTINCT FROM v_wal, NULL);

  PERFORM public._qa_s13_flag('cash_order_funding_enabled', COALESCE(v_cash_flag,false));
  r := r || public._qa_s13_ok('P15.13 the temporary cash rail flag was restored',
        (SELECT enabled FROM public.feature_flags WHERE key='cash_order_funding_enabled')
          IS NOT DISTINCT FROM v_cash_flag, NULL);

  PERFORM set_config('request.jwt.claims', ''::text, true);
  RETURN r;
END;
$function$;

REVOKE ALL ON FUNCTION public._qa_node3_repas_r7_readtruth() FROM PUBLIC, anon, authenticated;