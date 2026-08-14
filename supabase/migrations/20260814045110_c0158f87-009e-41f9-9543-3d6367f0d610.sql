-- R4.5 — Repas Retrait / pickup enablement (no courier leg).

-- 1) Facts expose the product fulfillment shape.
CREATE OR REPLACE FUNCTION public._chop_pay_facts(p_source_module text, p_source_id uuid)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_customer uuid; v_store uuid; v_owner uuid; v_sub bigint := 0;
  v_is_cp boolean := false; v_mixed boolean := false; v_pstate text;
  v_mission public.missions; v_del bigint := 0; v_tender text; v_ful text := 'delivery';
BEGIN
  IF p_source_module = 'repas' THEN
    SELECT fo.user_id, r.merchant_store_id, COALESCE(r.owner_user_id, ms.owner_user_id),
           fo.subtotal_gnf, (fo.payment_method::text = 'choppay'),
           (fo.captured_intent_id IS NOT NULL),
           fo.state::text, fo.payment_method::text, fo.fulfillment::text
      INTO v_customer, v_store, v_owner, v_sub, v_is_cp, v_mixed, v_pstate, v_tender, v_ful
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
    v_ful := 'delivery';
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
    'fulfillment', COALESCE(v_ful,'delivery'),
    'is_pickup', COALESCE(v_ful,'delivery') = 'pickup',
    'is_chop_pay', COALESCE(v_is_cp,false),
    'mixed_tender', COALESCE(v_mixed,false),
    'product_state', v_pstate,
    'mission_id', v_mission.id,
    'mission_state', v_mission.state::text,
    'courier_id', v_mission.courier_id,
    'pickup_confirmed', v_mission.pickup_confirmed_at IS NOT NULL);
END; $function$;

-- 2) Customer hold: pickup has no mission, no delivery fee, no collateral.
CREATE OR REPLACE FUNCTION public._chop_pay_customer_hold_internal(p_source_module text, p_source_id uuid, p_actor uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_f jsonb; v_e jsonb; v_row public.chop_pay_order_runtime; v_key text;
  v_sub bigint; v_del bigint; v_fee bigint; v_total bigint; v_snap jsonb; v_col bigint;
  v_w public.wallets; v_avail bigint; v_tx public.wallet_transactions; v_customer uuid;
  v_pickup boolean := false;
BEGIN
  IF NOT public._finance_flag('chop_pay_checkout_enabled') THEN
    RAISE EXCEPTION 'CHOP_PAY_CHECKOUT_DISABLED';
  END IF;
  v_key := format('%s:%s', p_source_module, p_source_id);
  PERFORM pg_advisory_xact_lock(hashtextextended('choppay:'||v_key, 0));

  SELECT * INTO v_row FROM public.chop_pay_order_runtime WHERE order_key = v_key FOR UPDATE;
  IF v_row.id IS NOT NULL THEN
    RETURN jsonb_build_object('status','already_authorized','runtime_id',v_row.id,
                              'state',v_row.state,'order_total_gnf',v_row.order_total_gnf,
                              'collateral_gnf',v_row.collateral_gnf);
  END IF;

  v_f := public._chop_pay_facts(p_source_module, p_source_id);
  IF NOT (v_f->>'is_chop_pay')::boolean THEN RAISE EXCEPTION 'CHOP_PAY_TENDER_REQUIRED'; END IF;
  IF (v_f->>'mixed_tender')::boolean THEN RAISE EXCEPTION 'MIXED_TENDER_NOT_SUPPORTED'; END IF;
  IF (v_f->>'merchant_store_id') IS NULL THEN RAISE EXCEPTION 'MERCHANT_STORE_MISSING'; END IF;
  v_pickup := COALESCE((v_f->>'is_pickup')::boolean, false);
  IF v_pickup THEN
    -- R4.5: a pickup order must never carry a courier leg.
    IF (v_f->>'mission_id') IS NOT NULL THEN
      RAISE EXCEPTION 'PICKUP_MUST_HAVE_NO_MISSION';
    END IF;
  ELSIF (v_f->>'mission_id') IS NULL THEN
    RAISE EXCEPTION 'CHOP_PAY_DELIVERY_NOT_READY'
      USING DETAIL = 'delivery mission must exist so the delivery fee is part of the hold';
  END IF;
  v_customer := (v_f->>'customer_user_id')::uuid;

  v_e := public._chop_pay_economics(v_f);
  v_sub := (v_e->>'merchandise_subtotal_gnf')::bigint;
  v_del := (v_e->>'delivery_fee_gnf')::bigint;
  v_fee := (v_e->>'platform_fee_gnf')::bigint;
  v_total := (v_e->>'order_total_gnf')::bigint;
  v_col := GREATEST(COALESCE((v_e->>'collateral_gnf')::bigint,0),0);
  v_snap := v_e->'policy_snapshot';
  IF v_pickup THEN
    IF v_del <> 0 THEN RAISE EXCEPTION 'PICKUP_MUST_HAVE_ZERO_DELIVERY_FEE'; END IF;
    v_col := 0;  -- no courier => no collateral requirement
    v_total := v_sub + v_fee;
  END IF;
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
                        'merchandise_gnf',v_sub,'delivery_gnf',v_del,'platform_fee_gnf',v_fee,
                        'fulfillment', v_f->>'fulfillment'))
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
     platform_fee_gnf, order_total_gnf, collateral_gnf, policy_snapshot, state)
  VALUES (v_key, p_source_module, p_source_id, v_f->>'mission_type',
          (v_f->>'mission_id')::uuid, v_customer,
          (v_f->>'merchant_store_id')::uuid, (v_f->>'merchant_user_id')::uuid,
          v_sub, v_del, v_fee, v_total, v_col, v_snap, 'authorized')
  RETURNING * INTO v_row;

  RETURN jsonb_build_object('status','authorized','runtime_id',v_row.id,
    'merchandise_subtotal_gnf',v_sub,'delivery_fee_gnf',v_del,'platform_fee_gnf',v_fee,
    'order_total_gnf',v_total,'held_gnf',v_total,'collateral_gnf',v_col,
    'fulfillment', v_f->>'fulfillment');
END; $function$;

-- 3) Merchant acceptance: a pickup order is funded straight from 'authorized'
--    (there is no courier acceptance step to create the payable).
CREATE OR REPLACE FUNCTION public.chop_pay_merchant_accept(p_source_module text, p_source_id uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_caller uuid := auth.uid(); v_row public.chop_pay_order_runtime;
        v_p public.merchant_payables; v_cap jsonb; v_pickup boolean := false;
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

  v_pickup := COALESCE((public._chop_pay_facts(p_source_module, p_source_id)->>'is_pickup')::boolean,false)
              AND v_row.mission_id IS NULL AND v_row.delivery_fee_gnf = 0;

  IF v_pickup AND v_row.state = 'authorized' THEN
    IF NOT EXISTS (SELECT 1 FROM public.merchant_payables
                    WHERE source_module = p_source_module AND source_id = p_source_id
                      AND merchant_store_id = v_row.merchant_store_id) THEN
      PERFORM public._merchant_payable_create_internal(
        p_source_module, p_source_id, v_row.merchant_store_id,
        v_row.merchandise_subtotal_gnf, 0, v_row.mission_type, v_row.policy_snapshot, false);
    END IF;
  ELSIF v_row.state <> 'accepted' THEN
    RAISE EXCEPTION 'INVALID_STATE' USING DETAIL = v_row.state;
  END IF;

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
    'payable_id', v_p.id, 'settlement_state','pending', 'pickup', v_pickup);
END; $function$;

-- 4) Completion: pickup has no courier custody handshake.
CREATE OR REPLACE FUNCTION public._chop_pay_complete_internal(p_source_module text, p_source_id uuid, p_actor uuid, p_from_dispute boolean DEFAULT false)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_row public.chop_pay_order_runtime; v_f jsonb; v_p public.merchant_payables;
  v_del jsonb; v_fee jsonb; v_rel jsonb; v_tail jsonb; v_pickup boolean := false;
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
  v_pickup := COALESCE((v_f->>'is_pickup')::boolean,false) AND v_row.mission_id IS NULL;

  IF v_pickup THEN
    -- Customer collects at the counter: there is no courier custody chain.
    -- R6 will add explicit customer-side pickup verification.
    IF v_row.delivery_fee_gnf <> 0 OR v_row.collateral_gnf <> 0 THEN
      RAISE EXCEPTION 'PICKUP_ECONOMICS_CORRUPT';
    END IF;
  ELSE
    IF NOT COALESCE((v_f->>'pickup_confirmed')::boolean,false) THEN
      RAISE EXCEPTION 'CUSTODY_NOT_ESTABLISHED';
    END IF;
    IF COALESCE(v_f->>'mission_state','') NOT IN ('picked_up','heading_to_dropoff','arrived_dropoff','delivered') THEN
      RAISE EXCEPTION 'INVALID_MISSION_STATE' USING DETAIL = COALESCE(v_f->>'mission_state','none');
    END IF;
  END IF;

  v_del := public._chop_pay_customer_capture_internal(
    p_source_module, p_source_id, v_row.delivery_fee_gnf, 'delivery', p_actor);
  v_fee := public._chop_pay_customer_capture_internal(
    p_source_module, p_source_id, v_row.platform_fee_gnf, 'platform_fee', p_actor);
  v_rel := public._driver_mission_hold_release_internal(
    p_source_module, p_source_id, 'collateral', 'chop_pay_completion', p_actor);
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
    'pickup', v_pickup,
    'commission_gnf', 0, 'driver_merchandise_advance_gnf', 0);
END; $function$;

-- 5) Merchant-owned pickup handoff (R6 will strengthen custody proof).
CREATE OR REPLACE FUNCTION public.chop_pay_merchant_pickup_complete(p_source_module text, p_source_id uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_caller uuid := auth.uid(); v_row public.chop_pay_order_runtime; v_f jsonb;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_row FROM public.chop_pay_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id FOR UPDATE;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'CHOP_PAY_NOT_AUTHORIZED'; END IF;
  IF v_caller IS DISTINCT FROM v_row.merchant_user_id AND NOT public._finance_privileged(v_caller) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  v_f := public._chop_pay_facts(p_source_module, p_source_id);
  IF NOT COALESCE((v_f->>'is_pickup')::boolean,false) OR v_row.mission_id IS NOT NULL THEN
    RAISE EXCEPTION 'NOT_A_PICKUP_ORDER';
  END IF;
  IF p_source_module = 'repas' AND COALESCE(v_f->>'product_state','') NOT IN ('ready','completed') THEN
    RAISE EXCEPTION 'PICKUP_NOT_READY' USING DETAIL = COALESCE(v_f->>'product_state','none');
  END IF;
  RETURN public._chop_pay_complete_internal(p_source_module, p_source_id, v_caller, false);
END; $function$;

REVOKE ALL ON FUNCTION public.chop_pay_merchant_pickup_complete(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chop_pay_merchant_pickup_complete(text, uuid) TO authenticated, service_role;

-- 6) Commitment: pickup is real; cash pickup fails closed.
CREATE OR REPLACE FUNCTION public.repas_order_create(p_restaurant_id uuid, p_items jsonb, p_fulfillment text, p_payment_method text, p_client_request_id uuid, p_delivery_address text DEFAULT NULL::text, p_delivery_lat double precision DEFAULT NULL::double precision, p_delivery_lng double precision DEFAULT NULL::double precision, p_notes text DEFAULT NULL::text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_r public.food_restaurants%ROWTYPE;
  v_it jsonb; v_mi public.food_menu_items%ROWTYPE;
  v_qty int; v_sub bigint := 0;
  v_fp text; v_existing public.food_orders%ROWTYPE;
  v_order public.food_orders%ROWTYPE;
  v_mission_id uuid; v_del bigint := 0;
  v_auth jsonb := NULL; v_count int := 0;
  v_notes text; v_addr text; v_pickup boolean;
  v_lat double precision; v_lng double precision;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF p_client_request_id IS NULL THEN RAISE EXCEPTION 'CLIENT_REQUEST_ID_REQUIRED'; END IF;
  IF p_payment_method NOT IN ('cash','choppay') THEN
    RAISE EXCEPTION 'UNSUPPORTED_TENDER' USING DETAIL = COALESCE(p_payment_method,'null');
  END IF;
  IF p_fulfillment NOT IN ('pickup','delivery') THEN RAISE EXCEPTION 'INVALID_FULFILLMENT'; END IF;
  v_pickup := (p_fulfillment = 'pickup');

  -- R4.5-C: cash pickup has no canonical primitive that collects the platform
  -- fee honestly (no courier float to net it from). Refuse before any row.
  IF v_pickup AND p_payment_method = 'cash' THEN
    RAISE EXCEPTION 'PICKUP_CASH_NOT_SUPPORTED'
      USING DETAIL = 'cash pickup awaits a canonical merchant-fee primitive';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'EMPTY_CART';
  END IF;
  IF jsonb_array_length(p_items) > 40 THEN RAISE EXCEPTION 'CART_TOO_LARGE'; END IF;

  v_notes := NULLIF(trim(COALESCE(p_notes,'')),'');
  -- Delivery-only inputs are normalised away for pickup so a replay that varies
  -- an irrelevant field stays stable, while notes always matter.
  v_addr := CASE WHEN v_pickup THEN NULL ELSE NULLIF(trim(COALESCE(p_delivery_address,'')),'') END;
  v_lat  := CASE WHEN v_pickup THEN NULL ELSE p_delivery_lat END;
  v_lng  := CASE WHEN v_pickup THEN NULL ELSE p_delivery_lng END;

  v_fp := md5(
    p_restaurant_id::text || '|' || p_fulfillment || '|' || p_payment_method || '|' ||
    COALESCE(v_addr,'') || '|' ||
    COALESCE(round(v_lat::numeric, 6)::text,'') || '|' ||
    COALESCE(round(v_lng::numeric, 6)::text,'') || '|' ||
    COALESCE(v_notes,'') || '|' ||
    (SELECT COALESCE(string_agg(x.k, ','), '')
       FROM (SELECT (e->>'menu_item_id') || ':' || (e->>'qty') AS k
               FROM jsonb_array_elements(p_items) e ORDER BY 1) x)
  );

  SELECT * INTO v_existing FROM public.food_orders
   WHERE user_id = v_uid AND client_request_id = p_client_request_id FOR UPDATE;
  IF FOUND THEN
    IF v_existing.request_fingerprint IS DISTINCT FROM v_fp THEN
      RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT';
    END IF;
    SELECT id INTO v_mission_id FROM public.missions
      WHERE ref_food_order_id = v_existing.id ORDER BY created_at DESC LIMIT 1;
    RETURN jsonb_build_object('ok', true, 'replay', true, 'order_id', v_existing.id,
      'subtotal_gnf', v_existing.subtotal_gnf, 'state', v_existing.state,
      'payment_method', v_existing.payment_method, 'mission_id', v_mission_id,
      'fulfillment', v_existing.fulfillment);
  END IF;

  SELECT * INTO v_r FROM public.food_restaurants WHERE id = p_restaurant_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'RESTAURANT_NOT_FOUND'; END IF;
  IF v_r.status <> 'active' THEN RAISE EXCEPTION 'RESTAURANT_NOT_ORDERABLE'; END IF;
  IF NOT COALESCE(v_r.is_open, false) THEN RAISE EXCEPTION 'RESTAURANT_CLOSED'; END IF;
  IF v_pickup AND NOT COALESCE(v_r.pickup_available,false) THEN
    RAISE EXCEPTION 'PICKUP_NOT_AVAILABLE';
  END IF;
  IF NOT v_pickup AND NOT COALESCE(v_r.delivery_available,false) THEN
    RAISE EXCEPTION 'DELIVERY_NOT_AVAILABLE';
  END IF;
  IF NOT v_pickup AND v_addr IS NULL AND (v_lat IS NULL OR v_lng IS NULL) THEN
    RAISE EXCEPTION 'DELIVERY_LOCATION_REQUIRED';
  END IF;

  IF p_payment_method = 'choppay' AND NOT public._finance_flag('chop_pay_checkout_enabled') THEN
    RAISE EXCEPTION 'CHOP_PAY_CHECKOUT_DISABLED';
  END IF;
  IF p_payment_method = 'cash' AND NOT public._finance_flag('cash_order_funding_enabled') THEN
    RAISE EXCEPTION 'CASH_ORDER_FUNDING_DISABLED'
      USING DETAIL = 'cash order funding rail is disabled; commitment refused';
  END IF;

  INSERT INTO public.food_orders(
      user_id, restaurant_id, fulfillment, payment_method, subtotal_gnf, notes,
      delivery_address, delivery_lat, delivery_lng, state,
      client_request_id, request_fingerprint)
  VALUES (v_uid, p_restaurant_id, p_fulfillment::food_fulfillment,
          p_payment_method::food_payment_method, 0, v_notes,
          v_addr, v_lat, v_lng,
          'placed', p_client_request_id, v_fp)
  RETURNING * INTO v_order;

  FOR v_it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_qty := COALESCE((v_it->>'qty')::int, 0);
    IF v_qty <= 0 OR v_qty > 50 THEN RAISE EXCEPTION 'INVALID_QUANTITY'; END IF;
    SELECT * INTO v_mi FROM public.food_menu_items WHERE id = (v_it->>'menu_item_id')::uuid;
    IF NOT FOUND THEN RAISE EXCEPTION 'MENU_ITEM_NOT_FOUND'; END IF;
    IF v_mi.restaurant_id <> p_restaurant_id THEN RAISE EXCEPTION 'ITEM_WRONG_RESTAURANT'; END IF;
    IF NOT COALESCE(v_mi.is_available,false) THEN RAISE EXCEPTION 'ITEM_UNAVAILABLE'; END IF;
    INSERT INTO public.food_order_items(order_id, menu_item_id, name_snapshot, unit_price_gnf, qty)
    VALUES (v_order.id, v_mi.id, v_mi.name, v_mi.price_gnf, v_qty);
    v_sub := v_sub + (v_mi.price_gnf::bigint * v_qty);
    v_count := v_count + 1;
  END LOOP;
  IF v_count = 0 THEN RAISE EXCEPTION 'EMPTY_CART'; END IF;

  UPDATE public.food_orders SET subtotal_gnf = v_sub, updated_at = now()
   WHERE id = v_order.id RETURNING * INTO v_order;

  IF NOT v_pickup THEN
    v_del := public.repas_delivery_earning_gnf();
    INSERT INTO public.missions(type, customer_id, merchant_id, pickup_address,
        dropoff_address, dropoff_lat, dropoff_lng, payload_summary,
        estimated_earning_gnf, ref_food_order_id)
    VALUES ('food_delivery', v_uid, v_r.owner_user_id,
            COALESCE(NULLIF(v_r.district,''), '') || CASE WHEN COALESCE(v_r.district,'') <> ''
              THEN ' · ' ELSE '' END || v_r.name,
            v_order.delivery_address, v_lat, v_lng,
            v_r.name || ' · ' || v_count::text || ' article(s) · ' || v_sub::text || ' GNF',
            v_del, v_order.id)
    RETURNING id INTO v_mission_id;
  END IF;

  IF p_payment_method = 'choppay' THEN
    v_auth := public.chop_pay_authorize_order('repas', v_order.id);
  END IF;

  RETURN jsonb_build_object('ok', true, 'replay', false, 'order_id', v_order.id,
    'subtotal_gnf', v_sub, 'state', v_order.state, 'payment_method', p_payment_method,
    'fulfillment', p_fulfillment,
    'mission_id', v_mission_id, 'delivery_fee_gnf', v_del, 'authorization', v_auth);
END; $function$;

-- 7) Merchant lifecycle: pickup has no courier handoff, and completion of a
--    funded pickup rail runs through the canonical Chop Pay engine.
CREATE OR REPLACE FUNCTION public.repas_merchant_transition(p_order_id uuid, p_action text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_o public.food_orders%ROWTYPE;
  v_r public.food_restaurants%ROWTYPE;
  v_tender text; v_res jsonb := NULL; v_next text := NULL; v_cur text;
  v_engine_state text; v_pickup boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  SELECT * INTO v_o FROM public.food_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  SELECT * INTO v_r FROM public.food_restaurants WHERE id = v_o.restaurant_id;
  IF v_r.owner_user_id IS DISTINCT FROM v_uid AND NOT public._finance_privileged(v_uid) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  v_tender := v_o.payment_method::text;
  v_cur := v_o.state::text;
  v_pickup := (v_o.fulfillment::text = 'pickup');

  IF p_action = 'accept' THEN
    IF v_cur IN ('confirmed','preparing','ready','out_for_delivery','completed') THEN
      RETURN jsonb_build_object('ok', true, 'idempotent', true, 'state', v_cur);
    END IF;
    IF v_cur <> 'placed' THEN RAISE EXCEPTION 'ILLEGAL_TRANSITION' USING DETAIL = v_cur; END IF;
    IF v_tender = 'cash' THEN v_res := public.cash_order_merchant_accept('repas', p_order_id);
    ELSIF v_tender = 'choppay' THEN v_res := public.chop_pay_merchant_accept('repas', p_order_id);
    ELSE RAISE EXCEPTION 'UNSUPPORTED_TENDER'; END IF;
    v_next := 'confirmed';

  ELSIF p_action = 'prepare' THEN
    IF v_cur IN ('preparing','ready','out_for_delivery','completed') THEN
      RETURN jsonb_build_object('ok', true, 'idempotent', true, 'state', v_cur);
    END IF;
    IF v_cur <> 'confirmed' THEN RAISE EXCEPTION 'ILLEGAL_TRANSITION' USING DETAIL = v_cur; END IF;
    IF v_tender = 'cash' THEN v_res := public.cash_order_merchant_prepare('repas', p_order_id);
    ELSIF v_tender = 'choppay' THEN v_res := public.chop_pay_merchant_prepare('repas', p_order_id);
    ELSE RAISE EXCEPTION 'UNSUPPORTED_TENDER'; END IF;
    v_next := 'preparing';

  ELSIF p_action = 'ready' THEN
    IF v_cur IN ('ready','out_for_delivery','completed') THEN
      RETURN jsonb_build_object('ok', true, 'idempotent', true, 'state', v_cur);
    END IF;
    IF v_cur <> 'preparing' THEN RAISE EXCEPTION 'ILLEGAL_TRANSITION' USING DETAIL = v_cur; END IF;
    v_next := 'ready';

  ELSIF p_action = 'handoff' THEN
    IF v_pickup THEN
      RAISE EXCEPTION 'PICKUP_HAS_NO_COURIER_HANDOFF';
    END IF;
    IF v_cur IN ('out_for_delivery','completed') THEN
      RETURN jsonb_build_object('ok', true, 'idempotent', true, 'state', v_cur);
    END IF;
    IF v_cur <> 'ready' THEN RAISE EXCEPTION 'ILLEGAL_TRANSITION' USING DETAIL = v_cur; END IF;
    v_next := 'out_for_delivery';

  ELSIF p_action = 'reject' THEN
    IF v_cur = 'cancelled' THEN
      RETURN jsonb_build_object('ok', true, 'idempotent', true, 'state', v_cur);
    END IF;
    IF v_cur NOT IN ('placed','confirmed') THEN
      RAISE EXCEPTION 'ILLEGAL_TRANSITION' USING DETAIL = v_cur;
    END IF;
    IF v_tender = 'cash' AND EXISTS (SELECT 1 FROM public.cash_order_runtime
        WHERE source_module='repas' AND source_id=p_order_id) THEN
      v_res := public.cash_order_merchant_reject('repas', p_order_id, p_reason);
    ELSIF v_tender = 'choppay' AND EXISTS (SELECT 1 FROM public.chop_pay_order_runtime
        WHERE source_module='repas' AND source_id=p_order_id) THEN
      v_res := public.chop_pay_merchant_reject('repas', p_order_id, p_reason);
    END IF;
    v_next := 'cancelled';

  ELSIF p_action = 'complete' THEN
    -- Pickup: the customer collects at the counter, so the merchant owns the
    -- handoff. Value still moves only through the canonical Chop Pay engine.
    IF v_pickup AND v_tender = 'choppay' THEN
      IF v_cur = 'completed' THEN
        RETURN jsonb_build_object('ok', true, 'idempotent', true, 'state', v_cur);
      END IF;
      IF v_cur <> 'ready' THEN RAISE EXCEPTION 'ILLEGAL_TRANSITION' USING DETAIL = v_cur; END IF;
      v_res := public.chop_pay_merchant_pickup_complete('repas', p_order_id);
      RETURN jsonb_build_object('ok', true, 'idempotent', false, 'state', 'completed',
                                'pickup', true, 'engine', v_res);
    END IF;
    IF v_tender IN ('cash','choppay') THEN
      SELECT state INTO v_engine_state FROM public.cash_order_runtime
       WHERE source_module='repas' AND source_id=p_order_id;
      IF v_engine_state IS NULL THEN
        SELECT state INTO v_engine_state FROM public.chop_pay_order_runtime
         WHERE source_module='repas' AND source_id=p_order_id;
      END IF;
      IF COALESCE(v_engine_state,'none') <> 'completed' THEN
        RAISE EXCEPTION 'COMPLETION_OWNED_BY_DELIVERY_ENGINE'
          USING DETAIL = COALESCE(v_engine_state,'no_runtime');
      END IF;
    END IF;
    RETURN public.repas_complete_order(p_order_id, COALESCE(p_reason,'Restaurant completed order'));
  ELSE
    RAISE EXCEPTION 'UNKNOWN_ACTION' USING DETAIL = COALESCE(p_action,'null');
  END IF;

  IF v_next IS NOT NULL THEN
    PERFORM set_config('chopchop.cash_engine','1',true);
    UPDATE public.food_orders SET state = v_next::food_order_state, updated_at = now()
     WHERE id = p_order_id AND state::text <> v_next;
    PERFORM set_config('chopchop.cash_engine','0',true);
    IF v_next = 'cancelled' THEN
      UPDATE public.missions SET state = 'failed', updated_at = now()
       WHERE ref_food_order_id = p_order_id AND courier_id IS NULL AND state = 'assigned';
    END IF;
  END IF;

  RETURN jsonb_build_object('ok', true, 'idempotent', false, 'state', v_next, 'engine', v_res);
END; $function$;

-- 8) Pre-commitment quote so the client never computes the fee itself.
CREATE OR REPLACE FUNCTION public.repas_quote_preview(p_restaurant_id uuid, p_items jsonb, p_fulfillment text)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid(); v_r public.food_restaurants%ROWTYPE;
  v_it jsonb; v_mi public.food_menu_items%ROWTYPE; v_qty int;
  v_sub bigint := 0; v_del bigint := 0; v_req jsonb; v_pickup boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF p_fulfillment NOT IN ('pickup','delivery') THEN RAISE EXCEPTION 'INVALID_FULFILLMENT'; END IF;
  v_pickup := (p_fulfillment = 'pickup');
  SELECT * INTO v_r FROM public.food_restaurants WHERE id = p_restaurant_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'RESTAURANT_NOT_FOUND'; END IF;
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'EMPTY_CART';
  END IF;

  FOR v_it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_qty := COALESCE((v_it->>'qty')::int, 0);
    IF v_qty <= 0 OR v_qty > 50 THEN RAISE EXCEPTION 'INVALID_QUANTITY'; END IF;
    SELECT * INTO v_mi FROM public.food_menu_items WHERE id = (v_it->>'menu_item_id')::uuid;
    IF NOT FOUND THEN RAISE EXCEPTION 'MENU_ITEM_NOT_FOUND'; END IF;
    IF v_mi.restaurant_id <> p_restaurant_id THEN RAISE EXCEPTION 'ITEM_WRONG_RESTAURANT'; END IF;
    v_sub := v_sub + (v_mi.price_gnf::bigint * v_qty);
  END LOOP;

  IF NOT v_pickup THEN v_del := public.repas_delivery_earning_gnf(); END IF;
  v_req := public.finance_mission_requirement_v2('repas', 0, v_sub, v_del, 0, 'chop_pay');

  RETURN jsonb_build_object(
    'fulfillment', p_fulfillment,
    'merchandise_subtotal_gnf', v_sub,
    'delivery_fee_gnf', v_del,
    'platform_fee_gnf', COALESCE((v_req->>'platform_fee_gnf')::bigint,0),
    'order_total_gnf', v_sub + v_del + COALESCE((v_req->>'platform_fee_gnf')::bigint,0),
    'pickup_available', COALESCE(v_r.pickup_available,false),
    'delivery_available', COALESCE(v_r.delivery_available,false),
    'chop_pay_enabled', public._finance_flag('chop_pay_checkout_enabled'),
    'cash_enabled', public._finance_flag('cash_order_funding_enabled'),
    'cash_pickup_supported', false,
    'policy_id', v_req->'policy_snapshot'->>'policy_id',
    'transaction_fee_bps', (v_req->'policy_snapshot'->>'transaction_fee_bps')::int);
END; $function$;

REVOKE ALL ON FUNCTION public.repas_quote_preview(uuid, jsonb, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.repas_quote_preview(uuid, jsonb, text) TO authenticated, service_role;