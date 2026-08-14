-- ============================================================
-- NODE 3 REPAS R6 — CUSTODY CHAIN
-- ============================================================

CREATE TABLE IF NOT EXISTS public.repas_custody_credentials (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.food_orders(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('restaurant_handoff','customer_delivery','customer_pickup')),
  holder_user_id uuid NOT NULL,
  code_salt text NOT NULL,
  code_hash text NOT NULL,
  code_plain text NOT NULL,
  attempts int NOT NULL DEFAULT 0,
  locked_at timestamptz,
  consumed_at timestamptz,
  consumed_by uuid,
  expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (order_id, kind)
);

-- Deliberately NO grants to anon/authenticated: the table is reachable only
-- through holder-scoped SECURITY DEFINER RPCs.
REVOKE ALL ON public.repas_custody_credentials FROM anon, authenticated;
GRANT ALL ON public.repas_custody_credentials TO service_role;
ALTER TABLE public.repas_custody_credentials ENABLE ROW LEVEL SECURITY;
-- No policies at all => fully closed to the Data API.

CREATE TABLE IF NOT EXISTS public.repas_custody_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.food_orders(id) ON DELETE CASCADE,
  mission_id uuid,
  boundary text NOT NULL CHECK (boundary IN
    ('restaurant_to_courier','courier_to_customer','merchant_to_customer_pickup')),
  actor_user_id uuid NOT NULL,
  counterparty_user_id uuid,
  method text NOT NULL,
  photo_path text,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS repas_custody_events_boundary_uq
  ON public.repas_custody_events(order_id, boundary);
CREATE INDEX IF NOT EXISTS repas_custody_events_order_idx
  ON public.repas_custody_events(order_id);

GRANT SELECT ON public.repas_custody_events TO authenticated;
GRANT ALL ON public.repas_custody_events TO service_role;
ALTER TABLE public.repas_custody_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "custody events readable by participants" ON public.repas_custody_events;
CREATE POLICY "custody events readable by participants"
ON public.repas_custody_events FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.food_orders fo
    JOIN public.food_restaurants r ON r.id = fo.restaurant_id
    WHERE fo.id = repas_custody_events.order_id
      AND (fo.user_id = auth.uid() OR r.owner_user_id = auth.uid())
  )
  OR EXISTS (
    SELECT 1 FROM public.missions m
    WHERE m.id = repas_custody_events.mission_id AND m.courier_id = auth.uid()
  )
  OR public._finance_privileged(auth.uid())
);

CREATE OR REPLACE FUNCTION public._repas_custody_events_append_only()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  RAISE EXCEPTION 'CUSTODY_EVENTS_APPEND_ONLY';
END; $$;

DROP TRIGGER IF EXISTS repas_custody_events_immutable ON public.repas_custody_events;
CREATE TRIGGER repas_custody_events_immutable
BEFORE UPDATE OR DELETE ON public.repas_custody_events
FOR EACH ROW EXECUTE FUNCTION public._repas_custody_events_append_only();

-- ============================================================
-- Credential primitives (internal only)
-- ============================================================

CREATE OR REPLACE FUNCTION public._repas_custody_hash(p_salt text, p_code text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT encode(sha256(convert_to(p_salt || ':' || p_code, 'UTF8')), 'hex');
$$;

CREATE OR REPLACE FUNCTION public._repas_custody_issue(
  p_order_id uuid, p_kind text, p_holder uuid)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_code text; v_salt text; v_id uuid;
BEGIN
  IF p_holder IS NULL THEN RAISE EXCEPTION 'CUSTODY_HOLDER_REQUIRED'; END IF;
  SELECT id INTO v_id FROM public.repas_custody_credentials
   WHERE order_id = p_order_id AND kind = p_kind;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;

  v_code := lpad(((get_byte(gen_random_bytes(4),0)::bigint * 16777216
                 + get_byte(gen_random_bytes(3),0)::bigint * 65536
                 + get_byte(gen_random_bytes(2),0)::bigint * 256
                 + get_byte(gen_random_bytes(1),0)::bigint) % 1000000)::text, 6, '0');
  v_salt := encode(gen_random_bytes(16), 'hex');

  INSERT INTO public.repas_custody_credentials(
    order_id, kind, holder_user_id, code_salt, code_hash, code_plain)
  VALUES (p_order_id, p_kind, p_holder, v_salt,
          public._repas_custody_hash(v_salt, v_code), v_code)
  RETURNING id INTO v_id;
  RETURN v_id;
END; $$;

REVOKE ALL ON FUNCTION public._repas_custody_issue(uuid, text, uuid) FROM PUBLIC, anon, authenticated;

-- Verify + consume. Fails closed, counts attempts, locks at 5.
CREATE OR REPLACE FUNCTION public._repas_custody_consume(
  p_order_id uuid, p_kind text, p_code text, p_actor uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v public.repas_custody_credentials;
BEGIN
  SELECT * INTO v FROM public.repas_custody_credentials
   WHERE order_id = p_order_id AND kind = p_kind FOR UPDATE;
  IF v.id IS NULL THEN RAISE EXCEPTION 'CUSTODY_CODE_NOT_ISSUED'; END IF;
  IF v.consumed_at IS NOT NULL THEN RAISE EXCEPTION 'CUSTODY_CODE_ALREADY_USED'; END IF;
  IF v.locked_at IS NOT NULL THEN RAISE EXCEPTION 'CUSTODY_CODE_LOCKED'; END IF;
  IF p_code IS NULL OR length(trim(p_code)) = 0 THEN
    RAISE EXCEPTION 'CUSTODY_CODE_REQUIRED';
  END IF;

  IF public._repas_custody_hash(v.code_salt, trim(p_code)) IS DISTINCT FROM v.code_hash THEN
    UPDATE public.repas_custody_credentials
       SET attempts = attempts + 1,
           locked_at = CASE WHEN attempts + 1 >= 5 THEN now() ELSE locked_at END,
           updated_at = now()
     WHERE id = v.id;
    RAISE EXCEPTION 'CUSTODY_CODE_INVALID';
  END IF;

  UPDATE public.repas_custody_credentials
     SET consumed_at = now(), consumed_by = p_actor, updated_at = now()
   WHERE id = v.id;
END; $$;

REVOKE ALL ON FUNCTION public._repas_custody_consume(uuid, text, text, uuid) FROM PUBLIC, anon, authenticated;

-- ============================================================
-- Holder-scoped read + participant status
-- ============================================================

CREATE OR REPLACE FUNCTION public.repas_custody_code_view(p_order_id uuid, p_kind text)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v public.repas_custody_credentials; v_state text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF p_kind NOT IN ('restaurant_handoff','customer_delivery','customer_pickup') THEN
    RAISE EXCEPTION 'INVALID_CUSTODY_KIND';
  END IF;
  SELECT state::text INTO v_state FROM public.food_orders WHERE id = p_order_id;
  IF v_state IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;

  SELECT * INTO v FROM public.repas_custody_credentials
   WHERE order_id = p_order_id AND kind = p_kind;
  IF v.id IS NULL THEN
    RETURN jsonb_build_object('issued', false, 'kind', p_kind);
  END IF;
  -- Holder scoping: only the designated holder ever sees the code.
  IF v.holder_user_id IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'CUSTODY_CODE_FORBIDDEN';
  END IF;
  IF v_state IN ('completed','cancelled') THEN
    RETURN jsonb_build_object('issued', true, 'kind', p_kind, 'expired', true);
  END IF;
  RETURN jsonb_build_object(
    'issued', true, 'kind', p_kind, 'expired', false,
    'code', CASE WHEN v.consumed_at IS NULL AND v.locked_at IS NULL THEN v.code_plain ELSE NULL END,
    'consumed', v.consumed_at IS NOT NULL,
    'locked', v.locked_at IS NOT NULL,
    'attempts', v.attempts);
END; $$;

REVOKE ALL ON FUNCTION public.repas_custody_code_view(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.repas_custody_code_view(uuid, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.repas_custody_status(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_o public.food_orders; v_owner uuid; v_courier uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  SELECT * INTO v_o FROM public.food_orders WHERE id = p_order_id;
  IF v_o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  SELECT owner_user_id INTO v_owner FROM public.food_restaurants WHERE id = v_o.restaurant_id;
  SELECT courier_id INTO v_courier FROM public.missions
   WHERE ref_food_order_id = p_order_id ORDER BY created_at DESC LIMIT 1;
  IF v_uid NOT IN (COALESCE(v_o.user_id,'00000000-0000-0000-0000-000000000000'::uuid),
                   COALESCE(v_owner,'00000000-0000-0000-0000-000000000000'::uuid),
                   COALESCE(v_courier,'00000000-0000-0000-0000-000000000000'::uuid))
     AND NOT public._finance_privileged(v_uid) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  RETURN jsonb_build_object(
    'order_id', p_order_id,
    'order_state', v_o.state::text,
    'fulfillment', v_o.fulfillment::text,
    'credentials', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'kind', c.kind, 'issued', true,
        'consumed', c.consumed_at IS NOT NULL,
        'locked', c.locked_at IS NOT NULL,
        'attempts', c.attempts,
        'holder_is_self', c.holder_user_id = v_uid))
      FROM public.repas_custody_credentials c WHERE c.order_id = p_order_id), '[]'::jsonb),
    'events', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'boundary', e.boundary, 'method', e.method,
        'occurred_at', e.occurred_at, 'actor_user_id', e.actor_user_id)
        ORDER BY e.occurred_at)
      FROM public.repas_custody_events e WHERE e.order_id = p_order_id), '[]'::jsonb));
END; $$;

REVOKE ALL ON FUNCTION public.repas_custody_status(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.repas_custody_status(uuid) TO authenticated, service_role;

-- ============================================================
-- A1 — restaurant -> courier
-- ============================================================

CREATE OR REPLACE FUNCTION public.repas_custody_confirm_handoff(
  p_mission_id uuid, p_photo_path text, p_code text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_m public.missions; v_o public.food_orders;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF p_photo_path IS NULL OR length(trim(p_photo_path)) = 0 THEN
    RAISE EXCEPTION 'CUSTODY_PHOTO_REQUIRED';
  END IF;

  SELECT * INTO v_m FROM public.missions WHERE id = p_mission_id FOR UPDATE;
  IF v_m.id IS NULL THEN RAISE EXCEPTION 'MISSION_NOT_FOUND'; END IF;
  IF v_m.type::text <> 'food_delivery' OR v_m.ref_food_order_id IS NULL THEN
    RAISE EXCEPTION 'NOT_A_REPAS_MISSION';
  END IF;
  IF v_m.courier_id IS DISTINCT FROM v_uid THEN RAISE EXCEPTION 'NOT_ASSIGNED_COURIER'; END IF;
  IF v_m.state::text <> 'arrived_pickup' THEN
    RAISE EXCEPTION 'INVALID_MISSION_STATE' USING DETAIL = v_m.state::text;
  END IF;

  SELECT * INTO v_o FROM public.food_orders WHERE id = v_m.ref_food_order_id FOR UPDATE;
  IF v_o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  IF v_o.fulfillment::text <> 'delivery' THEN RAISE EXCEPTION 'NOT_A_DELIVERY_ORDER'; END IF;
  IF v_o.state::text <> 'ready' THEN
    RAISE EXCEPTION 'ORDER_NOT_READY' USING DETAIL = v_o.state::text;
  END IF;

  PERFORM public._repas_custody_consume(v_o.id, 'restaurant_handoff', p_code, v_uid);

  UPDATE public.missions
     SET state = 'picked_up'::public.mission_state,
         pickup_confirmed_at = now(), pickup_confirmed_by = v_uid,
         pickup_photo_url = p_photo_path
   WHERE id = p_mission_id RETURNING * INTO v_m;

  INSERT INTO public.repas_custody_events(
    order_id, mission_id, boundary, actor_user_id, counterparty_user_id, method, photo_path)
  VALUES (v_o.id, p_mission_id, 'restaurant_to_courier', v_uid,
          (SELECT owner_user_id FROM public.food_restaurants WHERE id = v_o.restaurant_id),
          'code_photo', p_photo_path);

  INSERT INTO public.mission_events(mission_id, kind, payload)
  VALUES (p_mission_id, 'repas_custody_restaurant_to_courier',
          jsonb_build_object('photo_path', p_photo_path, 'order_id', v_o.id));

  PERFORM set_config('chopchop.cash_engine','1',true);
  UPDATE public.food_orders SET state = 'out_for_delivery', updated_at = now()
   WHERE id = v_o.id;
  PERFORM set_config('chopchop.cash_engine','0',true);

  -- Customer credential is only minted once the courier physically holds the food.
  PERFORM public._repas_custody_issue(v_o.id, 'customer_delivery', v_o.user_id);

  RETURN jsonb_build_object('ok', true, 'boundary','restaurant_to_courier',
                            'mission_state', v_m.state::text, 'order_state','out_for_delivery');
END; $$;

REVOKE ALL ON FUNCTION public.repas_custody_confirm_handoff(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.repas_custody_confirm_handoff(uuid, text, text) TO authenticated, service_role;

-- ============================================================
-- A2 — courier -> customer
-- ============================================================

CREATE OR REPLACE FUNCTION public.repas_custody_confirm_delivery(
  p_mission_id uuid, p_photo_path text, p_code text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_m public.missions; v_o public.food_orders;
        v_cash public.cash_order_runtime; v_cp public.chop_pay_order_runtime; v_res jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF p_photo_path IS NULL OR length(trim(p_photo_path)) = 0 THEN
    RAISE EXCEPTION 'CUSTODY_PHOTO_REQUIRED';
  END IF;

  SELECT * INTO v_m FROM public.missions WHERE id = p_mission_id FOR UPDATE;
  IF v_m.id IS NULL THEN RAISE EXCEPTION 'MISSION_NOT_FOUND'; END IF;
  IF v_m.type::text <> 'food_delivery' OR v_m.ref_food_order_id IS NULL THEN
    RAISE EXCEPTION 'NOT_A_REPAS_MISSION';
  END IF;
  IF v_m.courier_id IS DISTINCT FROM v_uid THEN RAISE EXCEPTION 'NOT_ASSIGNED_COURIER'; END IF;
  IF v_m.state::text <> 'arrived_dropoff' THEN
    RAISE EXCEPTION 'INVALID_MISSION_STATE' USING DETAIL = v_m.state::text;
  END IF;

  SELECT * INTO v_o FROM public.food_orders WHERE id = v_m.ref_food_order_id FOR UPDATE;
  IF v_o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  IF v_o.state::text IN ('completed','cancelled') THEN
    RAISE EXCEPTION 'ORDER_TERMINAL' USING DETAIL = v_o.state::text;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.repas_custody_events
                  WHERE order_id = v_o.id AND boundary = 'restaurant_to_courier') THEN
    RAISE EXCEPTION 'CUSTODY_NOT_ESTABLISHED';
  END IF;

  PERFORM public._repas_custody_consume(v_o.id, 'customer_delivery', p_code, v_uid);

  UPDATE public.missions
     SET state = 'delivered'::public.mission_state,
         dropoff_confirmed_at = now(), dropoff_confirmed_by = v_uid,
         delivery_photo_url = p_photo_path
   WHERE id = p_mission_id RETURNING * INTO v_m;

  INSERT INTO public.repas_custody_events(
    order_id, mission_id, boundary, actor_user_id, counterparty_user_id, method, photo_path)
  VALUES (v_o.id, p_mission_id, 'courier_to_customer', v_uid, v_o.user_id,
          'code_photo', p_photo_path);

  INSERT INTO public.mission_events(mission_id, kind, payload)
  VALUES (p_mission_id, 'repas_custody_courier_to_customer',
          jsonb_build_object('photo_path', p_photo_path, 'order_id', v_o.id));

  -- Canonical engines only. Exactly once.
  SELECT * INTO v_cash FROM public.cash_order_runtime
   WHERE source_module='repas' AND source_id = v_o.id;
  SELECT * INTO v_cp FROM public.chop_pay_order_runtime
   WHERE source_module='repas' AND source_id = v_o.id;
  IF v_cash.id IS NOT NULL THEN
    v_res := public._cash_order_complete_internal('repas', v_o.id, v_uid, false);
  ELSIF v_cp.id IS NOT NULL THEN
    v_res := public._chop_pay_complete_internal('repas', v_o.id, v_uid, false);
  ELSE
    RAISE EXCEPTION 'NO_PAYMENT_RUNTIME';
  END IF;

  RETURN jsonb_build_object('ok', true, 'boundary','courier_to_customer',
                            'mission_state','delivered', 'engine', v_res);
END; $$;

REVOKE ALL ON FUNCTION public.repas_custody_confirm_delivery(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.repas_custody_confirm_delivery(uuid, text, text) TO authenticated, service_role;

-- ============================================================
-- B — Retrait: merchant verifies the CUSTOMER-held credential
-- ============================================================

CREATE OR REPLACE FUNCTION public.repas_custody_confirm_pickup_collection(
  p_order_id uuid, p_code text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_o public.food_orders; v_owner uuid; v_res jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  SELECT * INTO v_o FROM public.food_orders WHERE id = p_order_id FOR UPDATE;
  IF v_o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  SELECT owner_user_id INTO v_owner FROM public.food_restaurants WHERE id = v_o.restaurant_id;
  IF v_owner IS DISTINCT FROM v_uid AND NOT public._finance_privileged(v_uid) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  IF v_o.fulfillment::text <> 'pickup' THEN RAISE EXCEPTION 'NOT_A_PICKUP_ORDER'; END IF;

  IF v_o.state::text = 'completed'
     AND EXISTS (SELECT 1 FROM public.repas_custody_events
                  WHERE order_id = p_order_id AND boundary = 'merchant_to_customer_pickup') THEN
    RETURN jsonb_build_object('ok', true, 'idempotent', true, 'state','completed');
  END IF;
  IF v_o.state::text <> 'ready' THEN
    RAISE EXCEPTION 'ORDER_NOT_READY' USING DETAIL = v_o.state::text;
  END IF;
  IF EXISTS (SELECT 1 FROM public.missions WHERE ref_food_order_id = p_order_id) THEN
    RAISE EXCEPTION 'PICKUP_MUST_BE_MISSIONLESS';
  END IF;

  PERFORM public._repas_custody_consume(p_order_id, 'customer_pickup', p_code, v_uid);

  INSERT INTO public.repas_custody_events(
    order_id, mission_id, boundary, actor_user_id, counterparty_user_id, method)
  VALUES (p_order_id, NULL, 'merchant_to_customer_pickup', v_uid, v_o.user_id, 'customer_code');

  PERFORM set_config('chopchop.repas_custody','1',true);
  BEGIN
    v_res := public.chop_pay_merchant_pickup_complete('repas', p_order_id);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('chopchop.repas_custody','0',true);
    RAISE;
  END;
  PERFORM set_config('chopchop.repas_custody','0',true);

  RETURN jsonb_build_object('ok', true, 'idempotent', false, 'state','completed',
                            'pickup', true, 'engine', v_res);
END; $$;

REVOKE ALL ON FUNCTION public.repas_custody_confirm_pickup_collection(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.repas_custody_confirm_pickup_collection(uuid, text) TO authenticated, service_role;

-- ============================================================
-- Close the bypasses
-- ============================================================

CREATE OR REPLACE FUNCTION public._repas_custody_guard(_m public.missions)
RETURNS void LANGUAGE plpgsql STABLE SET search_path = public AS $$
BEGIN
  IF _m.type::text = 'food_delivery' AND _m.ref_food_order_id IS NOT NULL
     AND COALESCE(current_setting('chopchop.repas_custody', true),'0') <> '1' THEN
    RAISE EXCEPTION 'REPAS_CUSTODY_REQUIRED'
      USING DETAIL = 'use repas_custody_confirm_handoff / repas_custody_confirm_delivery';
  END IF;
END; $$;

CREATE OR REPLACE FUNCTION public.mission_confirm_pickup(_mission_id uuid)
RETURNS missions LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE _uid uuid := auth.uid(); _m public.missions;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO _m FROM public.missions WHERE id = _mission_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mission_not_found'; END IF;
  IF _m.courier_id IS DISTINCT FROM _uid AND NOT public.is_any_admin(_uid) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  PERFORM public._repas_custody_guard(_m);
  UPDATE public.missions
     SET state='picked_up', pickup_confirmed_at=now(), pickup_confirmed_by=_uid
   WHERE id = _mission_id RETURNING * INTO _m;
  RETURN _m;
END; $function$;

REVOKE ALL ON FUNCTION public.mission_confirm_pickup(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mission_confirm_pickup(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.mission_confirm_dropoff(_mission_id uuid)
RETURNS missions LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE _uid uuid := auth.uid(); _m public.missions;
        _rt public.cash_order_runtime; _cp public.chop_pay_order_runtime;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO _m FROM public.missions WHERE id = _mission_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mission_not_found'; END IF;
  IF _m.courier_id IS DISTINCT FROM _uid AND NOT public.is_any_admin(_uid) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  PERFORM public._repas_custody_guard(_m);

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
END; $function$;

REVOKE ALL ON FUNCTION public.mission_confirm_dropoff(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mission_confirm_dropoff(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.mission_confirm_pickup_with_proof(
  _mission_id uuid, _photo_url text, _merchant_code text)
RETURNS missions LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE _uid uuid := auth.uid(); _m public.missions; _store public.merchant_stores; _ok boolean := false;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF _photo_url IS NULL OR length(trim(_photo_url)) = 0 THEN RAISE EXCEPTION 'photo_required'; END IF;
  IF _merchant_code IS NULL OR length(trim(_merchant_code)) = 0 THEN RAISE EXCEPTION 'merchant_code_required'; END IF;

  SELECT * INTO _m FROM public.missions WHERE id = _mission_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mission_not_found'; END IF;
  IF _m.courier_id IS DISTINCT FROM _uid AND NOT public.is_any_admin(_uid) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  PERFORM public._repas_custody_guard(_m);

  IF _m.merchant_store_id IS NOT NULL THEN
    SELECT * INTO _store FROM public.merchant_stores WHERE id = _m.merchant_store_id;
    _ok := (
      _merchant_code = COALESCE(_m.merchant_handoff_code,'')
      OR _merchant_code = COALESCE(_store.merchant_account_number,'')
      OR _merchant_code = COALESCE(_store.merchant_qr_payload,'')
    );
    IF NOT _ok THEN RAISE EXCEPTION 'invalid_merchant_code'; END IF;
  ELSE
    IF _merchant_code <> COALESCE(_m.merchant_handoff_code,'') THEN
      RAISE EXCEPTION 'invalid_merchant_code';
    END IF;
  END IF;

  UPDATE public.missions
     SET state = 'picked_up'::public.mission_state,
         pickup_confirmed_at = now(), pickup_confirmed_by = _uid,
         pickup_photo_url = _photo_url
   WHERE id = _mission_id RETURNING * INTO _m;

  INSERT INTO public.mission_events(mission_id, kind, payload)
  VALUES (_mission_id, 'pickup_confirmed', jsonb_build_object('photo_url', _photo_url));
  RETURN _m;
END; $function$;

REVOKE ALL ON FUNCTION public.mission_confirm_pickup_with_proof(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mission_confirm_pickup_with_proof(uuid, text, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.mission_confirm_dropoff_with_proof(
  _mission_id uuid, _photo_url text, _customer_code text)
RETURNS missions LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE _uid uuid := auth.uid(); _m public.missions;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF _photo_url IS NULL OR length(trim(_photo_url)) = 0 THEN RAISE EXCEPTION 'photo_required'; END IF;

  SELECT * INTO _m FROM public.missions WHERE id = _mission_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'mission_not_found'; END IF;
  IF _m.courier_id IS DISTINCT FROM _uid AND NOT public.is_any_admin(_uid) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  PERFORM public._repas_custody_guard(_m);

  IF _m.customer_handoff_code IS NOT NULL THEN
    IF _customer_code IS NULL OR _customer_code <> _m.customer_handoff_code THEN
      RAISE EXCEPTION 'invalid_customer_code';
    END IF;
  END IF;

  UPDATE public.missions
     SET state = 'delivered'::public.mission_state,
         dropoff_confirmed_at = now(), dropoff_confirmed_by = _uid,
         delivery_photo_url = _photo_url
   WHERE id = _mission_id RETURNING * INTO _m;

  INSERT INTO public.mission_events(mission_id, kind, payload)
  VALUES (_mission_id, 'dropoff_confirmed', jsonb_build_object('photo_url', _photo_url));

  BEGIN
    PERFORM public.wallet_credit_mission_earning(_mission_id, 'mission_confirm_dropoff_with_proof');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.mission_events(mission_id, kind, payload)
    VALUES (_mission_id, 'courier_earning_failed', jsonb_build_object('error', SQLERRM));
  END;
  RETURN _m;
END; $function$;

REVOKE ALL ON FUNCTION public.mission_confirm_dropoff_with_proof(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mission_confirm_dropoff_with_proof(uuid, text, text) TO authenticated, service_role;

-- Pickup completion is now owned by R6 proof.
CREATE OR REPLACE FUNCTION public.chop_pay_merchant_pickup_complete(
  p_source_module text, p_source_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_caller uuid := auth.uid(); v_row public.chop_pay_order_runtime; v_f jsonb;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF p_source_module = 'repas'
     AND COALESCE(current_setting('chopchop.repas_custody', true),'0') <> '1' THEN
    RAISE EXCEPTION 'PICKUP_REQUIRES_CUSTOMER_CODE'
      USING DETAIL = 'use repas_custody_confirm_pickup_collection';
  END IF;
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
