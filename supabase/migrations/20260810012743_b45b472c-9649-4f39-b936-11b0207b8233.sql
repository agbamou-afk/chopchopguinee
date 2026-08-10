-- =====================================================================
-- SLICE 4 INTEGRATION + DISPUTE MICRO-CLOSEOUT
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. EXPLICIT CASH TENDER (Marché must not default to cash)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._cash_order_facts(p_source_module text, p_source_id uuid)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_customer uuid; v_store uuid; v_owner uuid; v_sub bigint := 0;
  v_is_cash boolean := false; v_mixed boolean := false; v_pstate text;
  v_mission public.missions; v_del bigint := 0; v_tender text;
BEGIN
  IF p_source_module = 'repas' THEN
    SELECT fo.user_id, r.merchant_store_id, COALESCE(r.owner_user_id, ms.owner_user_id),
           fo.subtotal_gnf, (fo.payment_method::text = 'cash'),
           (fo.payment_method::text <> 'cash' OR fo.captured_intent_id IS NOT NULL),
           fo.state::text, fo.payment_method::text
      INTO v_customer, v_store, v_owner, v_sub, v_is_cash, v_mixed, v_pstate, v_tender
      FROM public.food_orders fo
      JOIN public.food_restaurants r ON r.id = fo.restaurant_id
      LEFT JOIN public.merchant_stores ms ON ms.id = r.merchant_store_id
     WHERE fo.id = p_source_id;

    SELECT * INTO v_mission FROM public.missions
     WHERE ref_food_order_id = p_source_id ORDER BY created_at DESC LIMIT 1;

  ELSIF p_source_module = 'marche' THEN
    -- EXPLICIT tender only. Missing / unknown metadata is NOT cash.
    SELECT mo.buyer_user_id, mo.merchant_store_id, mo.merchant_user_id,
           COALESCE(mo.counter_amount_gnf, mo.offer_amount_gnf),
           (mo.metadata->>'payment_method') = 'cash',
           (mo.payment_intent_id IS NOT NULL
             OR COALESCE(mo.payment_status,'unpaid') NOT IN ('unpaid','cancelled','failed')),
           mo.status, mo.metadata->>'payment_method'
      INTO v_customer, v_store, v_owner, v_sub, v_is_cash, v_mixed, v_pstate, v_tender
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
    'tender', v_tender,
    'is_cash', COALESCE(v_is_cash,false),
    'mixed_tender', COALESCE(v_mixed,false),
    'product_state', v_pstate,
    'mission_id', v_mission.id,
    'mission_state', v_mission.state::text,
    'courier_id', v_mission.courier_id,
    'pickup_confirmed', v_mission.pickup_confirmed_at IS NOT NULL);
END; $function$;

-- Safe boolean probe used by generic lifecycle paths.
CREATE OR REPLACE FUNCTION public._cash_order_is_cash(p_source_module text, p_source_id uuid)
 RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_f jsonb;
BEGIN
  IF p_source_module IS NULL OR p_source_id IS NULL THEN RETURN false; END IF;
  BEGIN
    v_f := public._cash_order_facts(p_source_module, p_source_id);
  EXCEPTION WHEN OTHERS THEN RETURN false; END;
  RETURN COALESCE((v_f->>'is_cash')::boolean, false);
END; $function$;
REVOKE ALL ON FUNCTION public._cash_order_is_cash(text,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._cash_order_is_cash(text,uuid) TO authenticated, service_role;

-- Buyer-selected explicit tender for Marché.
CREATE OR REPLACE FUNCTION public.marche_offer_set_tender(p_offer_id uuid, p_method text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_caller uuid := auth.uid(); v_o public.marketplace_offers;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF p_method NOT IN ('cash','choppay') THEN RAISE EXCEPTION 'INVALID_TENDER'; END IF;
  SELECT * INTO v_o FROM public.marketplace_offers WHERE id = p_offer_id FOR UPDATE;
  IF v_o.id IS NULL THEN RAISE EXCEPTION 'OFFER_NOT_FOUND'; END IF;
  IF v_caller <> v_o.buyer_user_id THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF COALESCE(v_o.payment_status,'unpaid') <> 'unpaid' OR v_o.payment_intent_id IS NOT NULL THEN
    RAISE EXCEPTION 'TENDER_LOCKED';
  END IF;
  IF EXISTS (SELECT 1 FROM public.cash_order_runtime
              WHERE source_module='marche' AND source_id=p_offer_id) THEN
    RAISE EXCEPTION 'TENDER_LOCKED' USING DETAIL = 'cash order already accepted';
  END IF;
  IF v_o.status NOT IN ('pending','countered','accepted') THEN RAISE EXCEPTION 'OFFER_CLOSED'; END IF;

  UPDATE public.marketplace_offers
     SET metadata = COALESCE(metadata,'{}'::jsonb) || jsonb_build_object('payment_method', p_method),
         updated_at = now()
   WHERE id = p_offer_id;

  RETURN jsonb_build_object('status','ok','payment_method',p_method);
END; $function$;
REVOKE ALL ON FUNCTION public.marche_offer_set_tender(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.marche_offer_set_tender(uuid,text) TO authenticated, service_role;

-- ---------------------------------------------------------------------
-- 2. INTERNAL ACCEPT (driver passed explicitly, service-only)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._cash_order_accept_internal(
  p_source_module text, p_source_id uuid, p_driver uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_f jsonb; v_e jsonb; v_row public.cash_order_runtime;
  v_key text; v_hold jsonb; v_sub bigint; v_del bigint; v_fee bigint; v_snap jsonb;
BEGIN
  IF p_driver IS NULL THEN RAISE EXCEPTION 'NO_DRIVER'; END IF;
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
  IF p_driver <> (v_f->>'courier_id')::uuid THEN RAISE EXCEPTION 'NOT_ASSIGNED_DRIVER'; END IF;
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

  v_hold := public.driver_mission_hold_place(
    v_f->>'mission_type', p_source_module, p_source_id, 0, p_driver, false,
    ARRAY['cash_funding','platform_fee'], 0, v_sub, v_del, 0, 'cash');

  PERFORM public._merchant_payable_create_internal(
    p_source_module, p_source_id, (v_f->>'merchant_store_id')::uuid,
    v_sub, 0, v_f->>'mission_type', v_snap, false);

  INSERT INTO public.cash_order_runtime
    (order_key, source_module, source_id, mission_type, mission_id, customer_user_id,
     driver_user_id, merchant_store_id, merchant_user_id, merchandise_subtotal_gnf,
     delivery_fee_gnf, platform_fee_gnf, cash_due_gnf, policy_snapshot, state)
  VALUES (v_key, p_source_module, p_source_id, v_f->>'mission_type',
          (v_f->>'mission_id')::uuid, (v_f->>'customer_user_id')::uuid, p_driver,
          (v_f->>'merchant_store_id')::uuid, (v_f->>'merchant_user_id')::uuid,
          v_sub, v_del, v_fee, v_sub + v_del + v_fee, v_snap, 'accepted')
  RETURNING * INTO v_row;

  RETURN jsonb_build_object('status','accepted','runtime_id',v_row.id,
    'merchandise_subtotal_gnf',v_sub,'delivery_fee_gnf',v_del,'platform_fee_gnf',v_fee,
    'cash_due_gnf',v_row.cash_due_gnf,'hold',v_hold);
END; $function$;
REVOKE ALL ON FUNCTION public._cash_order_accept_internal(text,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._cash_order_accept_internal(text,uuid,uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.cash_order_accept(p_source_module text, p_source_id uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_caller uuid := auth.uid();
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  RETURN public._cash_order_accept_internal(p_source_module, p_source_id, v_caller);
END; $function$;

-- ---------------------------------------------------------------------
-- 3. INTERNAL CASH COMPLETION (source + mission synchronisation)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._cash_order_complete_internal(
  p_source_module text, p_source_id uuid, p_actor uuid, p_from_dispute boolean DEFAULT false)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_row public.cash_order_runtime; v_f jsonb; v_fee jsonb;
BEGIN
  SELECT * INTO v_row FROM public.cash_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id FOR UPDATE;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'CASH_ORDER_NOT_ACCEPTED'; END IF;
  IF v_row.state = 'completed' THEN
    RETURN jsonb_build_object('status','already_completed','cash_due_gnf',v_row.cash_due_gnf);
  END IF;
  IF v_row.state = 'disputed' AND NOT p_from_dispute THEN RAISE EXCEPTION 'ORDER_IN_DISPUTE'; END IF;
  IF NOT (v_row.state IN ('preparing','merchant_accepted')
          OR (p_from_dispute AND v_row.state = 'disputed')) THEN
    RAISE EXCEPTION 'INVALID_STATE' USING DETAIL = v_row.state;
  END IF;
  IF p_source_module = 'repas' AND NOT p_from_dispute AND v_row.state <> 'preparing' THEN
    RAISE EXCEPTION 'PREPARATION_REQUIRED_BEFORE_DELIVERY';
  END IF;

  v_f := public._cash_order_facts(p_source_module, p_source_id);
  IF NOT COALESCE((v_f->>'pickup_confirmed')::boolean, false) THEN
    RAISE EXCEPTION 'CUSTODY_NOT_ESTABLISHED' USING DETAIL = 'pickup must be confirmed first';
  END IF;
  IF COALESCE(v_f->>'mission_state','') NOT IN ('picked_up','heading_to_dropoff','arrived_dropoff','delivered') THEN
    RAISE EXCEPTION 'INVALID_MISSION_STATE' USING DETAIL = COALESCE(v_f->>'mission_state','none');
  END IF;

  -- Physical cash: no courier wallet credit is ever created.
  v_fee := public._cash_order_capture_platform_fee(p_source_module, p_source_id, p_actor);

  UPDATE public.cash_order_runtime
     SET state = 'completed', completed_at = now(),
         cash_collected_gnf = v_row.cash_due_gnf,
         cash_principal_recovery_gnf = v_row.merchandise_subtotal_gnf,
         cash_delivery_earning_gnf = v_row.delivery_fee_gnf,
         cash_fee_recovery_gnf = v_row.platform_fee_gnf
   WHERE id = v_row.id;

  PERFORM set_config('chopchop.cash_engine','1',true);
  IF p_source_module = 'repas' THEN
    UPDATE public.food_orders SET state = 'completed', completed_at = now()
     WHERE id = p_source_id AND state <> 'completed';
  ELSE
    UPDATE public.marketplace_offers
       SET fulfillment_status = 'delivered', fulfilled_at = COALESCE(fulfilled_at, now()),
           completed_at = COALESCE(completed_at, now()), updated_at = now()
     WHERE id = p_source_id;
  END IF;
  PERFORM set_config('chopchop.cash_engine','0',true);

  UPDATE public.missions
     SET state = 'delivered',
         dropoff_confirmed_at = COALESCE(dropoff_confirmed_at, now()),
         dropoff_confirmed_by = COALESCE(dropoff_confirmed_by, p_actor)
   WHERE id = v_row.mission_id AND state <> 'delivered';

  RETURN jsonb_build_object('status','completed',
    'cash_due_gnf', v_row.cash_due_gnf,
    'merchandise_subtotal_gnf', v_row.merchandise_subtotal_gnf,
    'delivery_fee_gnf', v_row.delivery_fee_gnf,
    'platform_fee_gnf', v_row.platform_fee_gnf,
    'driver_wallet_credit_gnf', 0,
    'principal_recovery_is_income', false,
    'fee_capture', v_fee);
END; $function$;
REVOKE ALL ON FUNCTION public._cash_order_complete_internal(text,uuid,uuid,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._cash_order_complete_internal(text,uuid,uuid,boolean) TO service_role;

CREATE OR REPLACE FUNCTION public.cash_order_complete_cash(p_source_module text, p_source_id uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_caller uuid := auth.uid(); v_row public.cash_order_runtime;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_row FROM public.cash_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'CASH_ORDER_NOT_ACCEPTED'; END IF;
  IF v_caller <> v_row.driver_user_id AND NOT public._finance_privileged(v_caller) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  RETURN public._cash_order_complete_internal(p_source_module, p_source_id, v_caller, false);
END; $function$;

-- ---------------------------------------------------------------------
-- 4. SOURCE + MISSION SYNC ON REJECT / CANCEL
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._cash_order_deactivate_source(
  p_source_module text, p_source_id uuid, p_mission_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM set_config('chopchop.cash_engine','1',true);
  IF p_source_module = 'repas' THEN
    UPDATE public.food_orders SET state = 'cancelled'
     WHERE id = p_source_id AND state IN ('placed','confirmed','preparing','ready');
  ELSE
    UPDATE public.marketplace_offers
       SET fulfillment_status = 'cancelled', updated_at = now()
     WHERE id = p_source_id;
  END IF;
  PERFORM set_config('chopchop.cash_engine','0',true);

  UPDATE public.missions SET state = 'failed'
   WHERE id = p_mission_id AND state NOT IN ('delivered','failed');
END; $function$;
REVOKE ALL ON FUNCTION public._cash_order_deactivate_source(text,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._cash_order_deactivate_source(text,uuid,uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.cash_order_merchant_reject(p_source_module text, p_source_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
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
     SET state = 'reversed', reason = COALESCE(p_reason,'merchant_rejected'), updated_at = now()
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND state = 'pending_funding' AND funded_gnf = 0;

  UPDATE public.cash_order_runtime
     SET state = 'merchant_rejected', cancelled_at = now(),
         dispute_reason = COALESCE(p_reason, dispute_reason)
   WHERE id = v_row.id;

  PERFORM public._cash_order_deactivate_source(p_source_module, p_source_id, v_row.mission_id);

  RETURN jsonb_build_object('status','merchant_rejected','release',v_rel,
                            'customer_debt_created', false, 'platform_fee_revenue_gnf', 0);
END; $function$;

CREATE OR REPLACE FUNCTION public.cash_order_customer_cancel(p_source_module text, p_source_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
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
       SET state = 'reversed', updated_at = now()
     WHERE source_module = p_source_module AND source_id = p_source_id
       AND state = 'pending_funding' AND funded_gnf = 0;
    UPDATE public.cash_order_runtime
       SET state = 'cancelled', cancelled_at = now() WHERE id = v_row.id;
  END IF;

  PERFORM public._cash_order_deactivate_source(
    p_source_module, p_source_id, COALESCE(v_row.mission_id, (v_f->>'mission_id')::uuid));

  RETURN jsonb_build_object('status','cancelled','stage',v_stage,'debt',v_debt,'release',v_rel);
END; $function$;

-- Merchant accept / prepare must also flag the engine guard.
CREATE OR REPLACE FUNCTION public.cash_order_merchant_accept(p_source_module text, p_source_id uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
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

  PERFORM set_config('chopchop.cash_engine','1',true);
  IF p_source_module = 'repas' THEN
    UPDATE public.food_orders SET state = 'confirmed'
     WHERE id = p_source_id AND state = 'placed';
  END IF;
  PERFORM set_config('chopchop.cash_engine','0',true);

  RETURN jsonb_build_object('status','merchant_accepted','funding',v_fund,
                            'merchant_credited_gnf', v_row.merchandise_subtotal_gnf);
END; $function$;

CREATE OR REPLACE FUNCTION public.cash_order_merchant_prepare(p_source_module text, p_source_id uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
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

  PERFORM set_config('chopchop.cash_engine','1',true);
  IF p_source_module = 'repas' THEN
    UPDATE public.food_orders SET state = 'preparing'
     WHERE id = p_source_id AND state IN ('placed','confirmed');
  END IF;
  PERFORM set_config('chopchop.cash_engine','0',true);

  RETURN jsonb_build_object('status','preparing','customer_cancellation_locked',true);
END; $function$;

-- ---------------------------------------------------------------------
-- 5. LEGACY DIRECT-WRITE GUARD (Repas)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._cash_order_block_direct_state()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.state IS DISTINCT FROM OLD.state
     AND COALESCE(current_setting('chopchop.cash_engine', true), '0') <> '1'
     AND EXISTS (SELECT 1 FROM public.cash_order_runtime
                  WHERE source_module = 'repas' AND source_id = NEW.id) THEN
    RAISE EXCEPTION 'CASH_ORDER_STATE_ENGINE_ONLY'
      USING DETAIL = 'Cash orders must transition through the cash order engine';
  END IF;
  RETURN NEW;
END; $function$;

DROP TRIGGER IF EXISTS trg_cash_order_block_direct_state ON public.food_orders;
CREATE TRIGGER trg_cash_order_block_direct_state
BEFORE UPDATE OF state ON public.food_orders
FOR EACH ROW EXECUTE FUNCTION public._cash_order_block_direct_state();

-- ---------------------------------------------------------------------
-- 6. MISSION LIFECYCLE WIRING
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._mission_cash_source(_m public.missions)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_mod text; v_src uuid;
BEGIN
  IF _m.type = 'food_delivery' THEN v_mod := 'repas'; v_src := _m.ref_food_order_id;
  ELSIF _m.type = 'marketplace_delivery' THEN v_mod := 'marche'; v_src := _m.ref_market_order_id;
  ELSE RETURN NULL; END IF;
  IF v_src IS NULL THEN RETURN NULL; END IF;
  RETURN jsonb_build_object('module', v_mod, 'source_id', v_src);
END; $function$;
REVOKE ALL ON FUNCTION public._mission_cash_source(public.missions) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._mission_cash_source(public.missions) TO service_role;

CREATE OR REPLACE FUNCTION public.mission_claim(_mission_id uuid)
 RETURNS missions LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  _uid uuid := auth.uid();
  _m   public.missions;
  _cs  jsonb;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO _m FROM public.missions WHERE id = _mission_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mission_not_found'; END IF;
  IF _m.courier_id IS NOT NULL THEN RAISE EXCEPTION 'mission_already_claimed'; END IF;
  IF NOT public.driver_has_capability(_uid, public.mission_required_capability(_m.type)) THEN
    RAISE EXCEPTION 'capability_missing';
  END IF;

  -- Assign the courier first but keep the mission in 'assigned' so the cash
  -- engine sees a coherent (non-stale) state. Any funding failure below
  -- aborts the whole transaction: no half-assigned mission is possible.
  UPDATE public.missions SET courier_id = _uid WHERE id = _mission_id RETURNING * INTO _m;

  _cs := public._mission_cash_source(_m);
  IF _cs IS NOT NULL
     AND public._cash_order_is_cash(_cs->>'module', (_cs->>'source_id')::uuid) THEN
    PERFORM public._cash_order_accept_internal(
      _cs->>'module', (_cs->>'source_id')::uuid, _uid);
  END IF;

  UPDATE public.missions SET state = 'heading_to_pickup'
   WHERE id = _mission_id RETURNING * INTO _m;
  RETURN _m;
END; $function$;

CREATE OR REPLACE FUNCTION public.mission_confirm_dropoff(_mission_id uuid)
 RETURNS missions LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE _uid uuid := auth.uid(); _m public.missions; _rt public.cash_order_runtime;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO _m FROM public.missions WHERE id = _mission_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mission_not_found'; END IF;
  IF _m.courier_id IS DISTINCT FROM _uid AND NOT public.is_any_admin(_uid) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT * INTO _rt FROM public.cash_order_runtime WHERE mission_id = _mission_id;

  UPDATE public.missions
     SET state='delivered', dropoff_confirmed_at=now(), dropoff_confirmed_by=_uid
   WHERE id = _mission_id RETURNING * INTO _m;

  IF _rt.id IS NOT NULL THEN
    -- Physical cash order: the engine finalises economics. No wallet earning.
    PERFORM public._cash_order_complete_internal(_rt.source_module, _rt.source_id, _uid, false);
  ELSE
    BEGIN
      PERFORM public.wallet_credit_mission_earning(_mission_id, 'mission_confirm_dropoff');
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO public.mission_events(mission_id, kind, payload)
      VALUES (_mission_id, 'courier_earning_failed', jsonb_build_object('error', SQLERRM));
    END;
  END IF;
  RETURN _m;
END; $function$;

CREATE OR REPLACE FUNCTION public.mission_set_state(_mission_id uuid, _state mission_state)
 RETURNS missions LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  _uid uuid := auth.uid();
  _m public.missions;
  _prev public.mission_state;
  _rt public.cash_order_runtime;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO _m FROM public.missions WHERE id = _mission_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mission_not_found'; END IF;
  IF _m.courier_id IS DISTINCT FROM _uid AND NOT public.is_any_admin(_uid) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF _state NOT IN ('heading_to_pickup','arrived_pickup','picked_up','heading_to_dropoff','arrived_dropoff','delivered') THEN
    RAISE EXCEPTION 'state_not_allowed';
  END IF;
  _prev := _m.state;
  SELECT * INTO _rt FROM public.cash_order_runtime WHERE mission_id = _mission_id;

  UPDATE public.missions SET state = _state WHERE id = _mission_id RETURNING * INTO _m;

  IF _state = 'delivered'::public.mission_state
     AND _prev IS DISTINCT FROM 'delivered'::public.mission_state THEN
    IF _rt.id IS NOT NULL THEN
      PERFORM public._cash_order_complete_internal(_rt.source_module, _rt.source_id, _uid, false);
    ELSE
      BEGIN
        PERFORM public.wallet_credit_mission_earning(_mission_id, 'mission_set_state.delivered');
      EXCEPTION WHEN OTHERS THEN
        INSERT INTO public.mission_events(mission_id, kind, payload)
        VALUES (_mission_id, 'courier_earning_failed', jsonb_build_object('error', SQLERRM));
      END;
    END IF;
  END IF;
  RETURN _m;
END; $function$;

-- ---------------------------------------------------------------------
-- 7. SOURCE-SPECIFIC MERCHANT PAYABLE REVERSAL (new internal primitive)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._merchant_payable_reverse_internal(
  p_source_module text, p_source_id uuid, p_merchant_store_id uuid,
  p_beneficiary uuid, p_reason text, p_actor uuid DEFAULT NULL::uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_p public.merchant_payables; v_amount bigint; v_mw public.wallets; v_dw public.wallets;
BEGIN
  SELECT * INTO v_p FROM public.merchant_payables
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND merchant_store_id = p_merchant_store_id FOR UPDATE;
  IF v_p.id IS NULL THEN RETURN jsonb_build_object('status','no_payable','reversed_gnf',0); END IF;
  IF v_p.state = 'reversed' THEN
    RETURN jsonb_build_object('status','already_reversed','reversed_gnf',0);
  END IF;
  IF v_p.funded_gnf = 0 THEN
    UPDATE public.merchant_payables
       SET state = 'reversed', reason = COALESCE(p_reason, reason),
           resolved_at = now(), resolved_by = p_actor, updated_at = now()
     WHERE id = v_p.id;
    RETURN jsonb_build_object('status','not_funded','reversed_gnf',0);
  END IF;
  IF v_p.funding_source <> 'driver_cash_funding' THEN
    RETURN jsonb_build_object('status','reconciliation_required','reversed_gnf',0,
                              'detail','funding source is not driver cash funding');
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

  SELECT * INTO v_dw FROM public.wallets
   WHERE owner_user_id = (SELECT driver_user_id FROM public.cash_order_runtime
                           WHERE source_module = p_source_module AND source_id = p_source_id)
     AND party_type = 'driver' FOR UPDATE;
  IF v_dw.id IS NULL THEN
    RETURN jsonb_build_object('status','reconciliation_required','reversed_gnf',0,
                              'detail','driver wallet missing');
  END IF;

  UPDATE public.wallets SET balance_gnf = balance_gnf - v_amount, updated_at = now()
   WHERE id = v_mw.id;
  -- Principal is restored as UNRESTRICTED funds. Promo balance is untouched.
  UPDATE public.wallets SET balance_gnf = balance_gnf + v_amount, updated_at = now()
   WHERE id = v_dw.id;

  INSERT INTO public.wallet_transactions
    (reference, type, status, amount_gnf, from_wallet_id, to_wallet_id, related_user_id,
     related_entity, description, metadata, completed_at)
  VALUES
    (format('payable-reverse:%s:%s:%s', p_source_module, p_source_id, p_merchant_store_id),
     'reversal', 'completed', v_amount, v_mw.id, v_dw.id, v_p.merchant_user_id,
     p_source_module || ':' || p_source_id::text,
     'Reprise du financement marchandise (litige)',
     jsonb_build_object('reason', p_reason, 'restored_as','unrestricted',
                        'is_sandbox', v_p.is_sandbox), now());

  PERFORM public._ledger_post(
    format('payable-reverse:%s:%s:%s', p_source_module, p_source_id, p_merchant_store_id),
    p_source_module, p_source_id, 'merchant_payable_reversed',
    jsonb_build_array(
      jsonb_build_object('account','L_MERCHANT_PAYABLE','amount_gnf',v_amount,
                         'party_type','merchant','party_user_id',v_p.merchant_user_id,
                         'memo','reverse merchant liability'),
      jsonb_build_object('account','L_DRIVER_UNRESTRICTED','amount_gnf',-v_amount,
                         'party_type','driver','party_user_id',v_dw.owner_user_id,
                         'memo','restore merchandise principal as unrestricted')),
    v_p.mission_type, p_actor, v_p.policy_snapshot, v_p.is_sandbox);

  UPDATE public.merchant_payables
     SET funded_gnf = 0, state = 'reversed', reason = COALESCE(p_reason, reason),
         resolved_at = now(), resolved_by = p_actor, updated_at = now()
   WHERE id = v_p.id;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (p_actor, 'finance', 'merchant_payable_reversed', 'merchant_payables', v_p.id::text,
          jsonb_build_object('reversed_gnf', v_amount, 'merchant_user_id', v_p.merchant_user_id,
                             'driver_user_id', v_dw.owner_user_id), p_reason);

  RETURN jsonb_build_object('status','reversed','reversed_gnf',v_amount,
                            'merchant_user_id',v_p.merchant_user_id,
                            'driver_user_id',v_dw.owner_user_id);
END; $function$;
REVOKE ALL ON FUNCTION public._merchant_payable_reverse_internal(text,uuid,uuid,uuid,text,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._merchant_payable_reverse_internal(text,uuid,uuid,uuid,text,uuid) TO service_role;

-- ---------------------------------------------------------------------
-- 8. DISPUTE RESOLUTION ECONOMICS (D1 / D2 / D3)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_cash_order_dispute_resolve(
  p_source_module text, p_source_id uuid, p_outcome text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_caller uuid := auth.uid(); v_row public.cash_order_runtime;
  v_res jsonb; v_rev jsonb; v_rel jsonb; v_final_state text;
BEGIN
  IF NOT public._finance_privileged(v_caller) THEN RAISE EXCEPTION 'Not authorized'; END IF;
  IF p_outcome NOT IN ('complete_as_delivered','release_driver_funding','close_no_value') THEN
    RAISE EXCEPTION 'INVALID_DISPUTE_OUTCOME';
  END IF;

  SELECT * INTO v_row FROM public.cash_order_runtime
   WHERE source_module = p_source_module AND source_id = p_source_id FOR UPDATE;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'CASH_ORDER_NOT_ACCEPTED'; END IF;
  IF v_row.dispute_resolution IS NOT NULL THEN
    RETURN jsonb_build_object('status','already_resolved','resolution',v_row.dispute_resolution);
  END IF;
  IF v_row.state <> 'disputed' THEN RAISE EXCEPTION 'NOT_IN_DISPUTE' USING DETAIL = v_row.state; END IF;

  IF p_outcome = 'complete_as_delivered' THEN
    -- D1: true cash completion (fee captured once, cash fields, source + mission).
    v_res := public._cash_order_complete_internal(p_source_module, p_source_id, v_caller, true);
    v_final_state := 'completed';

  ELSIF p_outcome = 'release_driver_funding' THEN
    -- D2: actually give the captured merchandise principal back to the driver.
    v_rev := public._merchant_payable_reverse_internal(
      p_source_module, p_source_id, v_row.merchant_store_id, v_row.driver_user_id,
      COALESCE(p_reason,'dispute_release_driver_funding'), v_caller);
    IF v_rev->>'status' = 'reconciliation_required' THEN
      RAISE EXCEPTION 'FINANCE_RECONCILIATION_REQUIRED'
        USING DETAIL = COALESCE(v_rev->>'detail','merchant liability not recoverable');
    END IF;
    -- Release every remaining open hold (platform fee). No fee revenue.
    v_rel := public._driver_mission_hold_release_internal(
      p_source_module, p_source_id, NULL, COALESCE(p_reason,'dispute_resolution'), v_caller);
    v_res := jsonb_build_object('reversal', v_rev, 'release', v_rel,
                                'platform_fee_captured_gnf', 0);
    v_final_state := 'dispute_resolved';
    PERFORM public._cash_order_deactivate_source(p_source_module, p_source_id, v_row.mission_id);

  ELSE
    -- D3: no additional economic transfer, but nothing may stay encumbered.
    v_rel := public._driver_mission_hold_release_internal(
      p_source_module, p_source_id, NULL, COALESCE(p_reason,'dispute_close_no_value'), v_caller);
    v_res := jsonb_build_object('status','closed_no_value','release',v_rel,
                                'merchant_principal_change_gnf', 0,
                                'driver_principal_change_gnf', 0,
                                'platform_fee_captured_gnf', 0);
    v_final_state := 'dispute_resolved';
  END IF;

  UPDATE public.cash_order_runtime
     SET state = v_final_state, resolved_by = v_caller, resolved_at = now(),
         dispute_resolution = jsonb_build_object('outcome',p_outcome,'reason',p_reason,'result',v_res)
   WHERE id = v_row.id;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (v_caller, 'finance', 'cash_order_dispute_resolved', 'cash_order_runtime', v_row.id::text,
          jsonb_build_object('outcome',p_outcome,'result',v_res,'final_state',v_final_state), p_reason);

  RETURN jsonb_build_object('status','resolved','outcome',p_outcome,
                            'final_state',v_final_state,'result',v_res);
END; $function$;
