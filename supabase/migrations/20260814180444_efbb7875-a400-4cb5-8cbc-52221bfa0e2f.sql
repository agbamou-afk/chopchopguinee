-- =====================================================================
-- R7 semantic closeout: canonical receipt payment truth (read-only)
-- =====================================================================
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

  IF v_o.promotion_id IS NOT NULL THEN
    SELECT name INTO v_promo_name FROM public.repas_pricing_promotions WHERE id = v_o.promotion_id;
  END IF;

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

REVOKE ALL ON FUNCTION public.repas_order_receipt(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.repas_order_receipt(uuid) TO authenticated;

-- =====================================================================
-- R7 QA extension: canonical payment semantics (runs inside the R7
-- rollback transaction, creates no lasting rows)
-- =====================================================================
CREATE OR REPLACE FUNCTION public._qa_node3_repas_r7_semantics()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  r jsonb := '[]'::jsonb;
  v_cust uuid; v_merch uuid; v_drv uuid;
  v_store uuid; v_resto uuid; v_item uuid;
  v_o1 uuid; v_o2 uuid; v_m1 uuid;
  v_res jsonb; v_rc jsonb; v_code text; v_proof text;
  v_n int; v_j int; v_wal text; v_i int;
BEGIN
  v_cust := gen_random_uuid(); v_merch := gen_random_uuid(); v_drv := gen_random_uuid();
  PERFORM public._qa_s13_user(v_cust,'n3r7sc');
  PERFORM public._qa_s13_user(v_merch,'n3r7sm');
  PERFORM public._qa_s13_user(v_drv,'n3r7sd');
  PERFORM public._qa_s13_wallet(v_cust,'client',5000000,0);
  PERFORM public._qa_s13_wallet(v_merch,'merchant',0,0);
  PERFORM public._qa_s13_wallet(v_drv,'driver',900000,0);
  INSERT INTO public.driver_profiles(user_id,status,vehicle_type,capabilities)
    VALUES (v_drv,'approved','livraison',ARRAY['repas_delivery'])
    ON CONFLICT (user_id) DO UPDATE SET status='approved', capabilities=ARRAY['repas_delivery'];

  INSERT INTO public.merchant_stores(owner_user_id, slug, name, delivery_available, status)
    VALUES (v_merch, 'qa-n3r7-store-s-'||substr(v_merch::text,1,8), 'QA N3R7 Sem Store', true, 'active')
    RETURNING id INTO v_store;
  INSERT INTO public.food_restaurants(owner_user_id, merchant_store_id, slug, name, status,
      is_open, delivery_available, pickup_available, choppay_enabled, prep_time_min, latitude, longitude)
    VALUES (v_merch, v_store, 'qa-n3r7-resto-s-'||substr(v_merch::text,1,8), 'QA N3R7 Sem Resto',
            'active', true, true, true, true, 20, 9.5370, -13.6785)
    RETURNING id INTO v_resto;
  INSERT INTO public.food_menu_items(restaurant_id,name,price_gnf,is_available)
    VALUES (v_resto,'QA R7 Sem Plat',100000,true) RETURNING id INTO v_item;

  -- ============ P13. CANONICAL RECEIPT PAYMENT SEMANTICS ============
  r := r || public._qa_s13_ok('P13.0 receipt exposes canonical payment fields',
        pg_get_functiondef(to_regprocedure('public.repas_order_receipt(uuid)')) LIKE '%payment_state%'
    AND pg_get_functiondef(to_regprocedure('public.repas_order_receipt(uuid)')) LIKE '%chop_pay_order_runtime%'
    AND pg_get_functiondef(to_regprocedure('public.repas_order_receipt(uuid)')) LIKE '%cash_order_runtime%', NULL);

  PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
  v_res := public.repas_order_create(v_resto,
      jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
      'delivery','choppay', gen_random_uuid(), 'QA R7 Sem Adresse', 9.5395, -13.6760);
  v_o1 := (v_res->>'order_id')::uuid;
  SELECT id INTO v_m1 FROM public.missions WHERE ref_food_order_id = v_o1 LIMIT 1;
  v_rc := public.repas_order_receipt(v_o1);
  r := r || public._qa_s13_ok('P13.1 a freshly placed Chop Pay order is canonically authorized',
        v_rc->>'payment_rail' = 'chop_pay' AND v_rc->>'payment_state' = 'authorized',
        v_rc->>'payment_state');
  r := r || public._qa_s13_ok('P13.2 an authorized order is never reported as settled',
        (v_rc->>'payment_settled')::boolean IS FALSE, v_rc->>'payment_settled');
  r := r || public._qa_s13_ok('P13.3 the receipt still carries the legacy raw payment field separately',
        (v_rc ? 'legacy_payment_status'), v_rc->>'legacy_payment_status');
  r := r || public._qa_s13_ok('P13.4 canonical engine state is echoed on the receipt',
        v_rc->>'engine_state' = (SELECT state FROM public.chop_pay_order_runtime
                                  WHERE source_module='repas' AND source_id=v_o1),
        v_rc->>'engine_state');
  r := r || public._qa_s13_ok('P13.5 tender label source stays the committed order tender',
        v_rc->>'payment_method' = 'choppay', v_rc->>'payment_method');

  -- Full canonical lifecycle to completion
  PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
  PERFORM public.mission_claim(v_m1);
  PERFORM set_config('request.jwt.claims', public._as_user_claims(v_merch), true);
  PERFORM public.repas_merchant_transition(v_o1,'accept');
  PERFORM public.repas_merchant_transition(v_o1,'prepare');
  PERFORM public.repas_merchant_transition(v_o1,'ready');
  v_code := public.repas_custody_code_view(v_o1,'restaurant_handoff')->>'code';
  PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
  PERFORM public.mission_set_state(v_m1,'arrived_pickup');
  v_proof := public._qa_r6_proof(v_m1,'pickup',v_drv,'r7sem');
  PERFORM public.repas_custody_confirm_handoff(v_m1, v_proof, v_code);

  PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
  v_rc := public.repas_order_receipt(v_o1);
  r := r || public._qa_s13_ok('P13.6 an in-flight (out for delivery) order is still not settled',
        (v_rc->>'payment_settled')::boolean IS FALSE AND v_rc->>'payment_state' = 'authorized',
        v_rc->>'payment_state');
  v_code := public.repas_custody_code_view(v_o1,'customer_delivery')->>'code';

  PERFORM set_config('request.jwt.claims', public._as_user_claims(v_drv), true);
  PERFORM public.mission_set_state(v_m1,'heading_to_dropoff');
  PERFORM public.mission_set_state(v_m1,'arrived_dropoff');
  v_proof := public._qa_r6_proof(v_m1,'delivery',v_drv,'r7sem');
  PERFORM public.repas_custody_confirm_delivery(v_m1, v_proof, v_code);

  PERFORM set_config('request.jwt.claims', public._as_user_claims(v_cust), true);
  v_rc := public.repas_order_receipt(v_o1);
  r := r || public._qa_s13_ok('P13.7 a completed Chop Pay order is canonically paid',
        v_rc->>'payment_state' = 'paid' AND (v_rc->>'payment_settled')::boolean,
        v_rc->>'payment_state');
  r := r || public._qa_s13_ok('P13.8 canonical paid truth holds even if the legacy row still says unpaid',
        v_rc->>'payment_state' = 'paid'
        AND (SELECT state FROM public.chop_pay_order_runtime
              WHERE source_module='repas' AND source_id=v_o1) = 'completed',
        COALESCE(v_rc->>'legacy_payment_status','<null>'));
  r := r || public._qa_s13_ok('P13.9 the legacy field was NOT mutated by the read model',
        (SELECT payment_status FROM public.food_orders WHERE id=v_o1)
          IS NOT DISTINCT FROM (v_rc->>'legacy_payment_status'), NULL);
  r := r || public._qa_s13_ok('P13.10 the completed receipt still reconciles its frozen totals',
        (v_rc->>'totals_reconcile')::boolean, v_rc->>'order_total_gnf');
  r := r || public._qa_s13_ok('P13.11 the completed receipt keeps the real R6 boundaries',
        (v_rc->'custody_timeline')::text LIKE '%restaurant_to_courier%'
        AND (v_rc->'custody_timeline')::text LIKE '%courier_to_customer%', v_rc->>'custody_timeline');
  r := r || public._qa_s13_ok('P13.12 no receipt boundary uses a stale credential-style key',
        (v_rc->'custody_timeline')::text NOT LIKE '%"boundary": "restaurant_handoff"%'
        AND (v_rc->'custody_timeline')::text NOT LIKE '%"boundary": "customer_delivery"%',
        v_rc->>'custody_timeline');

  -- Receipt reads are economically inert
  SELECT count(*) INTO v_j FROM public.ledger_journals;
  SELECT string_agg(w.owner_user_id::text||':'||w.balance_gnf||':'||w.held_gnf, '|' ORDER BY w.owner_user_id)
    INTO v_wal FROM public.wallets w
   WHERE w.owner_user_id IN (v_cust, v_merch, v_drv) OR w.party_type = 'master';
  FOR v_i IN 1..3 LOOP
    PERFORM public.repas_order_receipt(v_o1);
  END LOOP;
  SELECT count(*) INTO v_n FROM public.ledger_journals;
  r := r || public._qa_s13_ok('P13.13 canonical receipt reads create no ledger journal', v_n = v_j, v_n::text);
  SELECT string_agg(w.owner_user_id::text||':'||w.balance_gnf||':'||w.held_gnf, '|' ORDER BY w.owner_user_id)
    INTO v_code FROM public.wallets w
   WHERE w.owner_user_id IN (v_cust, v_merch, v_drv) OR w.party_type = 'master';
  r := r || public._qa_s13_ok('P13.14 canonical receipt reads move no wallet',
        v_code IS NOT DISTINCT FROM v_wal, NULL);

  -- Cancelled before dispatch => released, never paid
  v_res := public.repas_order_create(v_resto,
      jsonb_build_array(jsonb_build_object('menu_item_id',v_item,'qty',1)),
      'delivery','choppay', gen_random_uuid(), 'QA R7 Sem Annule', 9.5395, -13.6760);
  v_o2 := (v_res->>'order_id')::uuid;
  PERFORM public.repas_customer_cancel_order(v_o2, 'QA R7 semantics cancellation proof');
  v_rc := public.repas_order_receipt(v_o2);
  r := r || public._qa_s13_ok('P13.15 a cancelled Chop Pay order is canonically released, never paid',
        v_rc->>'payment_state' IN ('released','cancelled')
        AND (v_rc->>'payment_settled')::boolean IS FALSE, v_rc->>'payment_state');
  r := r || public._qa_s13_ok('P13.16 the cancelled receipt is terminal and marked cancelled',
        (v_rc->>'cancelled')::boolean AND (v_rc->>'completed_at') IS NULL, NULL);
  r := r || public._qa_s13_ok('P13.17 a cancelled receipt still exposes an order total without claiming payment',
        (v_rc->>'order_total_gnf')::bigint > 0 AND (v_rc->>'payment_settled')::boolean IS FALSE,
        v_rc->>'order_total_gnf');

  -- Cash honesty: rail stays truthful and unfaked
  r := r || public._qa_s13_ok('P13.18 cash semantics are derived from cash_order_runtime only',
        pg_get_functiondef(to_regprocedure('public.repas_order_receipt(uuid)'))
          LIKE '%WHEN ''completed'' THEN ''collected''%', NULL);
  SELECT count(*) INTO v_n FROM public.cash_order_runtime
   WHERE source_module='repas' AND source_id IN (v_o1, v_o2);
  r := r || public._qa_s13_ok('P13.19 no cash runtime was fabricated for Chop Pay orders', v_n = 0, v_n::text);

  PERFORM set_config('request.jwt.claims', ''::text, true);
  RETURN r;
END;
$function$;

REVOKE ALL ON FUNCTION public._qa_node3_repas_r7_semantics() FROM PUBLIC, anon, authenticated;

-- Wire the new section into the existing R7 extension harness (which is
-- itself invoked inside the R7 rollback transaction).
DO $wire$
DECLARE d text;
BEGIN
  d := pg_get_functiondef('public._qa_node3_repas_r7_ext()'::regprocedure);
  IF position('_qa_node3_repas_r7_semantics' in d) = 0 THEN
    d := regexp_replace(
      d,
      E'\\n  RETURN r;\\nEND;\\n\\$function\\$',
      E'\n  r := r || public._qa_node3_repas_r7_semantics();\n  PERFORM set_config(''request.jwt.claims'', ''''::text, true);\n  RETURN r;\nEND;\n$function$');
    EXECUTE d;
  END IF;
END
$wire$;