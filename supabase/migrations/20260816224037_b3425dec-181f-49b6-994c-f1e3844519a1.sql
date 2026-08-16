-- =====================================================================
-- NODE 4 — MARCHÉ R5: MERCHANT FULFILLMENT + DELIVERY
-- Lifecycle-only. Zero money movement. Reuses canonical missions.
-- =====================================================================

ALTER TABLE public.marche_orders
  ADD COLUMN IF NOT EXISTS fulfillment_state text NOT NULL DEFAULT 'committed',
  ADD COLUMN IF NOT EXISTS fulfillment_updated_at timestamptz,
  ADD COLUMN IF NOT EXISTS mission_id uuid REFERENCES public.missions(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS accepted_at timestamptz,
  ADD COLUMN IF NOT EXISTS ready_at timestamptz,
  ADD COLUMN IF NOT EXISTS delivered_at timestamptz,
  ADD COLUMN IF NOT EXISTS rejected_at timestamptz,
  ADD COLUMN IF NOT EXISTS reservation_settled_at timestamptz,
  ADD COLUMN IF NOT EXISTS reservation_settlement_kind text;

ALTER TABLE public.marche_orders DROP CONSTRAINT IF EXISTS marche_orders_fulfillment_state_legal;
ALTER TABLE public.marche_orders ADD CONSTRAINT marche_orders_fulfillment_state_legal
  CHECK (fulfillment_state IN ('committed','accepted','preparing','ready',
                               'courier_engaged','collected','delivering','delivered',
                               'rejected','cancelled'));

ALTER TABLE public.marche_orders DROP CONSTRAINT IF EXISTS marche_orders_reservation_settlement_chk;
ALTER TABLE public.marche_orders ADD CONSTRAINT marche_orders_reservation_settlement_chk
  CHECK ((reservation_settled_at IS NULL AND reservation_settlement_kind IS NULL)
      OR (reservation_settled_at IS NOT NULL AND reservation_settlement_kind IN ('released','consumed')));

CREATE UNIQUE INDEX IF NOT EXISTS marche_orders_mission_unique
  ON public.marche_orders(mission_id) WHERE mission_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS marche_orders_fulfillment_idx
  ON public.marche_orders(fulfillment_state);

-- ---------------------------------------------------------------- history
CREATE TABLE IF NOT EXISTS public.marche_fulfillment_transitions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.marche_orders(id) ON DELETE CASCADE,
  from_state text NOT NULL,
  to_state text NOT NULL,
  actor_id uuid,
  actor_role text NOT NULL,
  mission_id uuid,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS marche_fulfillment_transitions_order_idx
  ON public.marche_fulfillment_transitions(order_id, created_at);

GRANT ALL ON public.marche_fulfillment_transitions TO service_role;
ALTER TABLE public.marche_fulfillment_transitions ENABLE ROW LEVEL SECURITY;
-- no policies: this log is reachable only through SECURITY DEFINER RPCs.

CREATE OR REPLACE FUNCTION public.marche_fulfillment_transition_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN RAISE EXCEPTION 'TRANSITION_LOG_APPEND_ONLY'; END IF;
  IF TG_OP = 'DELETE' THEN
    IF COALESCE(current_setting('marche.rpc', true),'') = '1' THEN RETURN OLD; END IF;
    RAISE EXCEPTION 'TRANSITION_LOG_APPEND_ONLY';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_marche_fulfillment_transition_guard ON public.marche_fulfillment_transitions;
CREATE TRIGGER trg_marche_fulfillment_transition_guard
  BEFORE UPDATE OR DELETE ON public.marche_fulfillment_transitions
  FOR EACH ROW EXECUTE FUNCTION public.marche_fulfillment_transition_guard();

-- ---------------------------------------------------------------- order guard
CREATE OR REPLACE FUNCTION public.marche_order_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF COALESCE(current_setting('marche.rpc', true),'') = '1' THEN RETURN OLD; END IF;
    RAISE EXCEPTION 'ORDER_IMMUTABLE';
  END IF;

  IF NEW.buyer_user_id IS DISTINCT FROM OLD.buyer_user_id
     OR NEW.merchant_store_id IS DISTINCT FROM OLD.merchant_store_id
     OR NEW.merchant_user_id IS DISTINCT FROM OLD.merchant_user_id
     OR NEW.merchandise_subtotal_gnf IS DISTINCT FROM OLD.merchandise_subtotal_gnf
     OR NEW.item_count IS DISTINCT FROM OLD.item_count
     OR NEW.line_count IS DISTINCT FROM OLD.line_count
     OR NEW.source_offer_id IS DISTINCT FROM OLD.source_offer_id
     OR NEW.client_request_id IS DISTINCT FROM OLD.client_request_id
     OR NEW.request_fingerprint IS DISTINCT FROM OLD.request_fingerprint
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
     OR NEW.delivery_address IS DISTINCT FROM OLD.delivery_address
     OR NEW.dropoff_lat IS DISTINCT FROM OLD.dropoff_lat
     OR NEW.dropoff_lng IS DISTINCT FROM OLD.dropoff_lng THEN
    RAISE EXCEPTION 'ORDER_IMMUTABLE';
  END IF;

  IF NEW.merchant_fee_gnf IS DISTINCT FROM OLD.merchant_fee_gnf
     OR NEW.merchant_payable_gnf IS DISTINCT FROM OLD.merchant_payable_gnf
     OR NEW.merchant_platform_fee_bps IS DISTINCT FROM OLD.merchant_platform_fee_bps
     OR NEW.fee_policy_id IS DISTINCT FROM OLD.fee_policy_id
     OR NEW.fee_policy_effective_from IS DISTINCT FROM OLD.fee_policy_effective_from
     OR NEW.economics_snapshot IS DISTINCT FROM OLD.economics_snapshot
     OR NEW.economics_resolved_at IS DISTINCT FROM OLD.economics_resolved_at
     OR NEW.delivery_charge_gnf IS DISTINCT FROM OLD.delivery_charge_gnf
     OR NEW.delivery_pricing_state IS DISTINCT FROM OLD.delivery_pricing_state THEN
    RAISE EXCEPTION 'ECONOMICS_IMMUTABLE';
  END IF;

  -- R5: the fulfillment axis is server-authoritative only.
  IF (NEW.fulfillment_state IS DISTINCT FROM OLD.fulfillment_state
      OR NEW.mission_id IS DISTINCT FROM OLD.mission_id
      OR NEW.fulfillment_updated_at IS DISTINCT FROM OLD.fulfillment_updated_at
      OR NEW.accepted_at IS DISTINCT FROM OLD.accepted_at
      OR NEW.ready_at IS DISTINCT FROM OLD.ready_at
      OR NEW.delivered_at IS DISTINCT FROM OLD.delivered_at
      OR NEW.rejected_at IS DISTINCT FROM OLD.rejected_at
      OR NEW.reservation_settled_at IS DISTINCT FROM OLD.reservation_settled_at
      OR NEW.reservation_settlement_kind IS DISTINCT FROM OLD.reservation_settlement_kind)
     AND COALESCE(current_setting('marche.rpc', true),'') <> '1' THEN
    RAISE EXCEPTION 'FULFILLMENT_SERVER_ONLY';
  END IF;

  IF NEW.fulfillment_state IS DISTINCT FROM OLD.fulfillment_state
     AND OLD.fulfillment_state IN ('delivered','rejected','cancelled') THEN
    RAISE EXCEPTION 'FULFILLMENT_TERMINAL';
  END IF;

  IF NEW.mission_id IS DISTINCT FROM OLD.mission_id
     AND OLD.mission_id IS NOT NULL AND NEW.mission_id IS NOT NULL THEN
    RAISE EXCEPTION 'MISSION_LINK_IMMUTABLE';
  END IF;

  IF NEW.reservation_settled_at IS DISTINCT FROM OLD.reservation_settled_at
     AND OLD.reservation_settled_at IS NOT NULL THEN
    RAISE EXCEPTION 'RESERVATION_ALREADY_SETTLED';
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF OLD.status <> 'committed' THEN RAISE EXCEPTION 'ORDER_TERMINAL'; END IF;
    IF NEW.status NOT IN ('cancelled','expired') THEN RAISE EXCEPTION 'ILLEGAL_ORDER_TRANSITION'; END IF;
    IF OLD.fulfillment_state NOT IN ('committed','accepted','preparing','ready') THEN
      RAISE EXCEPTION 'FULFILLMENT_IN_PROGRESS';
    END IF;
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END $$;

-- ---------------------------------------------------------------- internals
CREATE OR REPLACE FUNCTION public._marche_fulfillment_apply(
  p_order_id uuid, p_to text, p_actor uuid, p_role text, p_reason text)
RETURNS public.marche_orders LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE o public.marche_orders; v_from text;
BEGIN
  SELECT * INTO o FROM public.marche_orders WHERE id = p_order_id FOR UPDATE;
  IF o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  v_from := o.fulfillment_state;
  PERFORM set_config('marche.rpc','1', true);
  UPDATE public.marche_orders
     SET fulfillment_state = p_to,
         fulfillment_updated_at = now(),
         accepted_at  = CASE WHEN p_to='accepted'  AND accepted_at  IS NULL THEN now() ELSE accepted_at  END,
         ready_at     = CASE WHEN p_to='ready'     AND ready_at     IS NULL THEN now() ELSE ready_at     END,
         delivered_at = CASE WHEN p_to='delivered' AND delivered_at IS NULL THEN now() ELSE delivered_at END,
         rejected_at  = CASE WHEN p_to='rejected'  AND rejected_at  IS NULL THEN now() ELSE rejected_at  END
   WHERE id = o.id RETURNING * INTO o;
  INSERT INTO public.marche_fulfillment_transitions(order_id, from_state, to_state, actor_id, actor_role, mission_id, reason)
  VALUES (o.id, v_from, p_to, p_actor, p_role, o.mission_id, NULLIF(btrim(COALESCE(p_reason,'')),''));
  PERFORM set_config('marche.rpc','', true);
  RETURN o;
END $$;

CREATE OR REPLACE FUNCTION public._marche_fulfillment_note(
  p_order_id uuid, p_actor uuid, p_role text, p_reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE o public.marche_orders;
BEGIN
  SELECT * INTO o FROM public.marche_orders WHERE id = p_order_id;
  IF o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  INSERT INTO public.marche_fulfillment_transitions(order_id, from_state, to_state, actor_id, actor_role, mission_id, reason)
  VALUES (o.id, o.fulfillment_state, o.fulfillment_state, p_actor, p_role, o.mission_id, p_reason);
END $$;

-- Reservation settlement: exactly once, either released or consumed.
CREATE OR REPLACE FUNCTION public._marche_reservation_settle(p_order_id uuid, p_kind text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE o public.marche_orders; i record;
BEGIN
  IF p_kind NOT IN ('released','consumed') THEN RAISE EXCEPTION 'INVALID_SETTLEMENT_KIND'; END IF;
  SELECT * INTO o FROM public.marche_orders WHERE id = p_order_id FOR UPDATE;
  IF o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  IF o.reservation_settled_at IS NOT NULL THEN RETURN false; END IF;

  PERFORM set_config('marche.rpc','1', true);
  FOR i IN SELECT listing_id, qty FROM public.marche_order_items WHERE order_id = o.id LOOP
    IF p_kind = 'released' THEN
      UPDATE public.marketplace_listings
         SET quantity_reserved = GREATEST(COALESCE(quantity_reserved,0) - i.qty, 0)
       WHERE id = i.listing_id AND quantity_in_stock IS NOT NULL;
    ELSE
      UPDATE public.marketplace_listings
         SET quantity_reserved = GREATEST(COALESCE(quantity_reserved,0) - i.qty, 0),
             quantity_in_stock = GREATEST(COALESCE(quantity_in_stock,0) - i.qty, 0)
       WHERE id = i.listing_id AND quantity_in_stock IS NOT NULL;
    END IF;
  END LOOP;
  UPDATE public.marche_orders
     SET reservation_settled_at = now(), reservation_settlement_kind = p_kind
   WHERE id = o.id;
  PERFORM set_config('marche.rpc','', true);
  RETURN true;
END $$;

-- ---------------------------------------------------------------- cancel (R3, R5-aware)
CREATE OR REPLACE FUNCTION public.marche_order_cancel(p_order_id uuid, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE caller uuid := auth.uid(); o public.marche_orders;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  SELECT * INTO o FROM public.marche_orders WHERE id = p_order_id FOR UPDATE;
  IF o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  IF o.buyer_user_id <> caller AND o.merchant_user_id <> caller AND NOT public.is_any_admin(caller) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  IF o.status <> 'committed' THEN
    RETURN public.marche_order_json(o); -- idempotent replay, no second release
  END IF;
  -- R5: once a courier mission exists the order is in the field; cancellation is
  -- no longer a pure stock question and is refused rather than faked.
  IF o.mission_id IS NOT NULL
     OR o.fulfillment_state NOT IN ('committed','accepted','preparing','ready') THEN
    RAISE EXCEPTION 'FULFILLMENT_IN_PROGRESS';
  END IF;

  PERFORM public._marche_reservation_settle(o.id, 'released');

  PERFORM set_config('marche.rpc','1', true);
  UPDATE public.marche_orders
     SET status = 'cancelled', cancelled_at = now(),
         cancel_reason = NULLIF(btrim(COALESCE(p_reason,'')),'')
   WHERE id = o.id RETURNING * INTO o;
  PERFORM set_config('marche.rpc','', true);

  o := public._marche_fulfillment_apply(o.id, 'cancelled', caller,
        CASE WHEN o.buyer_user_id = caller THEN 'buyer'
             WHEN o.merchant_user_id = caller THEN 'merchant' ELSE 'admin' END,
        NULLIF(btrim(COALESCE(p_reason,'')),''));
  RETURN public.marche_order_json(o);
END $$;

-- ---------------------------------------------------------------- merchant authority
CREATE OR REPLACE FUNCTION public.marche_merchant_transition(
  p_order_id uuid, p_action text, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  caller uuid := auth.uid();
  o public.marche_orders; s public.merchant_stores;
  v_cur text; v_next text; v_event text;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  SELECT * INTO o FROM public.marche_orders WHERE id = p_order_id FOR UPDATE;
  IF o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  SELECT * INTO s FROM public.merchant_stores WHERE id = o.merchant_store_id;
  IF o.merchant_user_id IS DISTINCT FROM caller AND s.owner_user_id IS DISTINCT FROM caller THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  v_cur := o.fulfillment_state;

  IF p_action = 'accept' THEN
    IF v_cur IN ('accepted','preparing','ready','courier_engaged','collected','delivering','delivered') THEN
      RETURN public.marche_order_json(o);
    END IF;
    IF o.status <> 'committed' THEN RAISE EXCEPTION 'ORDER_NOT_ACTIVE'; END IF;
    IF v_cur <> 'committed' THEN RAISE EXCEPTION 'ILLEGAL_TRANSITION' USING DETAIL = v_cur; END IF;
    v_next := 'accepted'; v_event := 'MERCHANT_ACCEPTED';

  ELSIF p_action = 'prepare' THEN
    IF v_cur IN ('preparing','ready','courier_engaged','collected','delivering','delivered') THEN
      RETURN public.marche_order_json(o);
    END IF;
    IF o.status <> 'committed' THEN RAISE EXCEPTION 'ORDER_NOT_ACTIVE'; END IF;
    IF v_cur <> 'accepted' THEN RAISE EXCEPTION 'ILLEGAL_TRANSITION' USING DETAIL = v_cur; END IF;
    v_next := 'preparing'; v_event := NULL;

  ELSIF p_action = 'ready' THEN
    IF v_cur IN ('ready','courier_engaged','collected','delivering','delivered') THEN
      RETURN public.marche_order_json(o);
    END IF;
    IF o.status <> 'committed' THEN RAISE EXCEPTION 'ORDER_NOT_ACTIVE'; END IF;
    IF v_cur <> 'preparing' THEN RAISE EXCEPTION 'ILLEGAL_TRANSITION' USING DETAIL = v_cur; END IF;
    v_next := 'ready'; v_event := 'MERCHANT_READY';

  ELSIF p_action = 'reject' THEN
    IF v_cur = 'rejected' THEN RETURN public.marche_order_json(o); END IF;
    IF v_cur NOT IN ('committed','accepted','preparing','ready') OR o.mission_id IS NOT NULL THEN
      RAISE EXCEPTION 'FULFILLMENT_IN_PROGRESS';
    END IF;
    IF o.status <> 'committed' THEN RAISE EXCEPTION 'ORDER_NOT_ACTIVE'; END IF;

    PERFORM public._marche_reservation_settle(o.id, 'released');
    PERFORM set_config('marche.rpc','1', true);
    UPDATE public.marche_orders
       SET status = 'cancelled', cancelled_at = now(),
           cancel_reason = COALESCE(NULLIF(btrim(COALESCE(p_reason,'')),''), 'merchant_rejected')
     WHERE id = o.id RETURNING * INTO o;
    PERFORM set_config('marche.rpc','', true);
    o := public._marche_fulfillment_apply(o.id, 'rejected', caller, 'merchant', p_reason);
    RETURN public.marche_order_json(o);

  ELSE
    RAISE EXCEPTION 'UNSUPPORTED_ACTION' USING DETAIL = COALESCE(p_action,'');
  END IF;

  o := public._marche_fulfillment_apply(o.id, v_next, caller, 'merchant', p_reason);

  IF v_event IS NOT NULL THEN
    PERFORM public.marche_fulfillment_event_append(
      o.id, v_event, o.fulfillment_updated_at,
      'marche_merchant_transition', o.id::text, 'merchant:'||p_action, 'merchant');
  END IF;

  RETURN public.marche_order_json(o);
END $$;

-- ---------------------------------------------------------------- dispatch (order -> canonical mission)
CREATE OR REPLACE FUNCTION public.marche_dispatch_request(p_order_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  caller uuid := auth.uid();
  o public.marche_orders; s public.merchant_stores; m public.missions; v_mid uuid;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  SELECT * INTO o FROM public.marche_orders WHERE id = p_order_id FOR UPDATE;
  IF o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  SELECT * INTO s FROM public.merchant_stores WHERE id = o.merchant_store_id;
  IF o.merchant_user_id IS DISTINCT FROM caller AND s.owner_user_id IS DISTINCT FROM caller THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  IF o.status <> 'committed' THEN RAISE EXCEPTION 'ORDER_NOT_ACTIVE'; END IF;

  IF o.mission_id IS NOT NULL THEN
    RETURN public.marche_order_json(o); -- replay never creates a second mission
  END IF;
  IF o.fulfillment_state <> 'ready' THEN
    RAISE EXCEPTION 'ILLEGAL_TRANSITION' USING DETAIL = o.fulfillment_state;
  END IF;
  IF NULLIF(btrim(COALESCE(o.delivery_address,'')),'') IS NULL THEN
    RAISE EXCEPTION 'DELIVERY_DESTINATION_REQUIRED';
  END IF;

  INSERT INTO public.missions(type, state, customer_id, merchant_id, merchant_store_id,
    pickup_address, pickup_lat, pickup_lng, dropoff_address, dropoff_lat, dropoff_lng,
    payload_summary, estimated_earning_gnf, ref_market_order_id)
  VALUES ('marketplace_delivery', 'assigned', o.buyer_user_id, o.merchant_user_id, o.merchant_store_id,
    COALESCE(NULLIF(btrim(COALESCE(s.address_label,'')),''), COALESCE(s.name,'Boutique')),
    s.latitude, s.longitude, o.delivery_address, o.dropoff_lat, o.dropoff_lng,
    format('Marché · %s article(s) · %s ligne(s)', o.item_count, o.line_count),
    0, o.id)
  RETURNING * INTO m;
  v_mid := m.id;

  PERFORM set_config('marche.rpc','1', true);
  UPDATE public.marche_orders SET mission_id = v_mid WHERE id = o.id RETURNING * INTO o;
  PERFORM set_config('marche.rpc','', true);

  -- Fulfillment mode becomes truthful only now: a real dispatch decision exists.
  PERFORM public.marche_fulfillment_set_mode(o.id, 'delivery', 'marche_dispatch_request');
  PERFORM public._marche_fulfillment_note(o.id, caller, 'merchant', 'mission_linked:'||v_mid::text);

  RETURN public.marche_order_json(o);
END $$;

-- ---------------------------------------------------------------- courier engagement hook
CREATE OR REPLACE FUNCTION public._marche_courier_engaged_internal(
  p_order_id uuid, p_courier uuid, p_mission_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE o public.marche_orders;
BEGIN
  SELECT * INTO o FROM public.marche_orders WHERE id = p_order_id FOR UPDATE;
  IF o.id IS NULL THEN RETURN; END IF;
  IF o.mission_id IS DISTINCT FROM p_mission_id THEN RAISE EXCEPTION 'MISSION_NOT_LINKED'; END IF;
  IF o.fulfillment_state = 'courier_engaged' THEN RETURN; END IF;
  IF o.fulfillment_state <> 'ready' THEN
    RAISE EXCEPTION 'ILLEGAL_TRANSITION' USING DETAIL = o.fulfillment_state;
  END IF;
  PERFORM public._marche_fulfillment_apply(o.id, 'courier_engaged', p_courier, 'courier', NULL);
  PERFORM public.marche_fulfillment_event_append(
    o.id, 'COURIER_ENGAGED', now(), 'mission_claim', p_mission_id::text,
    'mission:'||p_mission_id::text, 'courier');
END $$;

-- ---------------------------------------------------------------- courier authority
CREATE OR REPLACE FUNCTION public.marche_courier_transition(p_order_id uuid, p_action text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  caller uuid := auth.uid();
  o public.marche_orders; m public.missions;
  v_cur text; v_next text; v_event text; v_mstate public.mission_state;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  SELECT * INTO o FROM public.marche_orders WHERE id = p_order_id FOR UPDATE;
  IF o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  IF o.mission_id IS NULL THEN RAISE EXCEPTION 'MISSION_NOT_LINKED'; END IF;
  SELECT * INTO m FROM public.missions WHERE id = o.mission_id FOR UPDATE;
  IF m.id IS NULL THEN RAISE EXCEPTION 'MISSION_NOT_FOUND'; END IF;
  IF m.courier_id IS NULL THEN RAISE EXCEPTION 'COURIER_NOT_ASSIGNED'; END IF;
  IF m.courier_id IS DISTINCT FROM caller THEN RAISE EXCEPTION 'NOT_THE_ASSIGNED_COURIER'; END IF;

  v_cur := o.fulfillment_state;

  IF p_action = 'arrive_store' THEN
    IF v_cur NOT IN ('courier_engaged') THEN
      IF v_cur IN ('collected','delivering','delivered') THEN RETURN public.marche_order_json(o); END IF;
      RAISE EXCEPTION 'ILLEGAL_TRANSITION' USING DETAIL = v_cur;
    END IF;
    UPDATE public.missions SET state = 'arrived_pickup' WHERE id = m.id;
    PERFORM public.marche_fulfillment_event_append(
      o.id, 'COURIER_AT_STORE', now(), 'marche_courier_transition', m.id::text,
      'mission:'||m.id::text, 'courier');
    PERFORM public._marche_fulfillment_note(o.id, caller, 'courier', 'courier_at_store');
    RETURN public.marche_order_json(o);

  ELSIF p_action = 'collect' THEN
    IF v_cur IN ('collected','delivering','delivered') THEN RETURN public.marche_order_json(o); END IF;
    IF v_cur <> 'courier_engaged' THEN RAISE EXCEPTION 'ILLEGAL_TRANSITION' USING DETAIL = v_cur; END IF;
    v_next := 'collected'; v_event := 'PICKED_UP'; v_mstate := 'picked_up';

  ELSIF p_action = 'start_delivery' THEN
    IF v_cur IN ('delivering','delivered') THEN RETURN public.marche_order_json(o); END IF;
    IF v_cur <> 'collected' THEN RAISE EXCEPTION 'ILLEGAL_TRANSITION' USING DETAIL = v_cur; END IF;
    v_next := 'delivering'; v_event := NULL; v_mstate := 'heading_to_dropoff';

  ELSIF p_action = 'deliver' THEN
    IF v_cur = 'delivered' THEN RETURN public.marche_order_json(o); END IF;
    IF v_cur <> 'delivering' THEN RAISE EXCEPTION 'ILLEGAL_TRANSITION' USING DETAIL = v_cur; END IF;
    v_next := 'delivered'; v_event := 'DELIVERED'; v_mstate := 'delivered';

  ELSE
    RAISE EXCEPTION 'UNSUPPORTED_ACTION' USING DETAIL = COALESCE(p_action,'');
  END IF;

  IF v_mstate = 'picked_up' THEN
    UPDATE public.missions SET state = v_mstate, pickup_confirmed_at = now(), pickup_confirmed_by = caller
     WHERE id = m.id;
  ELSIF v_mstate = 'delivered' THEN
    UPDATE public.missions SET state = v_mstate, dropoff_confirmed_at = now(), dropoff_confirmed_by = caller
     WHERE id = m.id;
  ELSE
    UPDATE public.missions SET state = v_mstate WHERE id = m.id;
  END IF;

  o := public._marche_fulfillment_apply(o.id, v_next, caller, 'courier', NULL);

  IF v_next = 'delivered' THEN
    PERFORM public._marche_reservation_settle(o.id, 'consumed');
    SELECT * INTO o FROM public.marche_orders WHERE id = o.id;
  END IF;

  IF v_event IS NOT NULL THEN
    PERFORM public.marche_fulfillment_event_append(
      o.id, v_event, o.fulfillment_updated_at, 'marche_courier_transition', m.id::text,
      'mission:'||m.id::text, 'courier');
  END IF;

  RETURN public.marche_order_json(o);
END $$;

-- ---------------------------------------------------------------- mission_claim: canonical marché engagement
CREATE OR REPLACE FUNCTION public.mission_claim(_mission_id uuid)
RETURNS public.missions LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  _uid uuid := auth.uid(); _m public.missions; _cs jsonb; _tender text; _pkg uuid;
  _marche uuid;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO _m FROM public.missions WHERE id = _mission_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mission_not_found'; END IF;
  IF _m.courier_id IS NOT NULL THEN RAISE EXCEPTION 'mission_already_claimed'; END IF;
  IF NOT public.driver_has_capability(_uid, public.mission_required_capability(_m.type)) THEN
    RAISE EXCEPTION 'capability_missing';
  END IF;

  IF _m.type = 'marketplace_delivery' AND _m.ref_market_order_id IS NOT NULL THEN
    SELECT id INTO _marche FROM public.marche_orders WHERE id = _m.ref_market_order_id;
    IF _marche IS NULL THEN
      -- legacy offer-backed Marché delivery keeps its tender gate
      SELECT mo.metadata->>'payment_method' INTO _tender
        FROM public.marketplace_offers mo WHERE mo.id = _m.ref_market_order_id;
      IF _tender IS NULL OR _tender NOT IN ('cash','choppay') THEN
        RAISE EXCEPTION 'MARCHE_TENDER_REQUIRED'
          USING DETAIL = 'explicit payment method required before courier assignment';
      END IF;
    END IF;
  END IF;

  UPDATE public.missions SET courier_id = _uid WHERE id = _mission_id RETURNING * INTO _m;

  IF _m.type = 'package_delivery' THEN
    SELECT package_id INTO _pkg FROM public.package_runtime WHERE mission_id = _mission_id;
    IF _pkg IS NOT NULL THEN
      PERFORM public._package_accept_internal(_pkg, _uid);
    END IF;
  END IF;

  _cs := public._mission_cash_source(_m);
  IF _cs IS NOT NULL THEN
    IF public._cash_order_is_cash(_cs->>'module', (_cs->>'source_id')::uuid) THEN
      PERFORM public._cash_order_accept_internal(_cs->>'module', (_cs->>'source_id')::uuid, _uid);
    ELSIF public._chop_pay_is_chop_pay(_cs->>'module', (_cs->>'source_id')::uuid) THEN
      PERFORM public._chop_pay_accept_internal(_cs->>'module', (_cs->>'source_id')::uuid, _uid);
    END IF;
  END IF;

  UPDATE public.missions SET state = 'heading_to_pickup' WHERE id = _mission_id RETURNING * INTO _m;

  IF _marche IS NOT NULL THEN
    PERFORM public._marche_courier_engaged_internal(_marche, _uid, _m.id);
  END IF;

  RETURN _m;
END $$;

-- ---------------------------------------------------------------- sanitized reads
CREATE OR REPLACE FUNCTION public.marche_order_json(o public.marche_orders)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
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
    -- R5 sanitized fulfillment truth (no courier identity, no secrets)
    'fulfillment_state', o.fulfillment_state,
    'fulfillment_updated_at', o.fulfillment_updated_at,
    'accepted_at', o.accepted_at,
    'ready_at', o.ready_at,
    'delivered_at', o.delivered_at,
    'rejected_at', o.rejected_at,
    'courier_assigned', EXISTS (SELECT 1 FROM public.missions m
                                 WHERE m.id = o.mission_id AND m.courier_id IS NOT NULL),
    'mission_state', (SELECT m.state::text FROM public.missions m WHERE m.id = o.mission_id),
    'items', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id', i.id, 'listing_id', i.listing_id, 'store_id', i.store_id_snapshot,
        'title', i.title_snapshot, 'qty', i.qty,
        'unit_price_gnf', i.unit_price_gnf, 'line_total_gnf', i.line_total_gnf,
        'source_offer_id', i.source_offer_id) ORDER BY i.created_at, i.id)
      FROM public.marche_order_items i WHERE i.order_id = o.id), '[]'::jsonb)
  )
  || CASE WHEN auth.uid() IS NOT NULL
            AND (o.merchant_user_id = auth.uid() OR public.is_any_admin(auth.uid()))
          THEN jsonb_build_object(
                 'mission_id', o.mission_id,
                 'reservation_settlement_kind', o.reservation_settlement_kind,
                 'merchant_fee_gnf', o.merchant_fee_gnf,
                 'merchant_payable_gnf', o.merchant_payable_gnf,
                 'merchant_platform_fee_bps', o.merchant_platform_fee_bps,
                 'fee_policy_id', o.fee_policy_id,
                 'fee_policy_effective_from', o.fee_policy_effective_from,
                 'economics_resolved_at', o.economics_resolved_at,
                 'economics_snapshot', o.economics_snapshot)
          ELSE '{}'::jsonb END;
$$;

CREATE OR REPLACE FUNCTION public.marche_order_fulfillment_history(p_order_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE caller uuid := auth.uid(); o public.marche_orders; v_admin boolean;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  SELECT * INTO o FROM public.marche_orders WHERE id = p_order_id;
  IF o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  v_admin := public.is_any_admin(caller);
  IF o.buyer_user_id <> caller AND o.merchant_user_id <> caller AND NOT v_admin THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'from_state', t.from_state, 'to_state', t.to_state,
      'actor_role', t.actor_role, 'reason', t.reason, 'at', t.created_at)
      || CASE WHEN v_admin THEN jsonb_build_object('actor_id', t.actor_id, 'mission_id', t.mission_id)
              ELSE '{}'::jsonb END
      ORDER BY t.created_at, t.id)
    FROM public.marche_fulfillment_transitions t WHERE t.order_id = o.id), '[]'::jsonb);
END $$;

-- ---------------------------------------------------------------- grants
REVOKE ALL ON FUNCTION public.marche_merchant_transition(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_dispatch_request(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_courier_transition(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_order_fulfillment_history(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public._marche_fulfillment_apply(uuid, text, uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._marche_fulfillment_note(uuid, uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._marche_reservation_settle(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._marche_courier_engaged_internal(uuid, uuid, uuid) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.marche_merchant_transition(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_dispatch_request(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_courier_transition(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_order_fulfillment_history(uuid) TO authenticated;