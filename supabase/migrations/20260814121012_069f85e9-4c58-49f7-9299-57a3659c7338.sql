-- ============ R6.1 : credential secrecy at rest (vault) ============
ALTER TABLE public.repas_custody_credentials
  ADD COLUMN IF NOT EXISTS code_secret_id uuid;

-- purge any legacy plaintext still at rest, then drop the column
UPDATE public.repas_custody_credentials SET code_plain = NULL WHERE false;
ALTER TABLE public.repas_custody_credentials DROP COLUMN IF EXISTS code_plain;

REVOKE ALL ON public.repas_custody_credentials FROM anon, authenticated, sandbox_exec;
REVOKE ALL ON public.repas_custody_events FROM anon, sandbox_exec;
GRANT SELECT ON public.repas_custody_events TO authenticated;
GRANT ALL ON public.repas_custody_credentials TO service_role;
GRANT ALL ON public.repas_custody_events TO service_role;

-- ============ helpers ============
CREATE OR REPLACE FUNCTION public._repas_custody_purge_secret(p_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','vault' AS $$
DECLARE v_sec uuid;
BEGIN
  SELECT code_secret_id INTO v_sec FROM public.repas_custody_credentials WHERE id = p_id;
  IF v_sec IS NOT NULL THEN
    DELETE FROM vault.secrets WHERE id = v_sec;
    UPDATE public.repas_custody_credentials SET code_secret_id = NULL, updated_at = now()
     WHERE id = p_id;
  END IF;
END; $$;
REVOKE ALL ON FUNCTION public._repas_custody_purge_secret(uuid) FROM PUBLIC, anon, authenticated;

-- canonical dispute gate: unresolved dispute on either payment runtime blocks custody
CREATE OR REPLACE FUNCTION public._repas_custody_dispute_blocked(p_order_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.chop_pay_order_runtime r
     WHERE r.source_module = 'repas' AND r.source_id = p_order_id
       AND r.disputed_at IS NOT NULL AND r.dispute_resolution IS NULL
    UNION ALL
    SELECT 1 FROM public.cash_order_runtime c
     WHERE c.source_module = 'repas' AND c.source_id = p_order_id
       AND c.disputed_at IS NOT NULL AND c.dispute_resolution IS NULL
  );
$$;
REVOKE ALL ON FUNCTION public._repas_custody_dispute_blocked(uuid) FROM PUBLIC, anon;

-- real storage-object proof verification (private mission-proofs bucket)
CREATE OR REPLACE FUNCTION public._repas_custody_verify_photo(
  p_mission_id uuid, p_path text, p_courier uuid, p_phase text)
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public','storage' AS $$
DECLARE v_name text; v_owner uuid;
BEGIN
  IF p_path IS NULL OR length(trim(p_path)) = 0 THEN
    RAISE EXCEPTION 'CUSTODY_PHOTO_REQUIRED';
  END IF;
  SELECT o.name, COALESCE(o.owner, NULLIF(o.owner_id,'')::uuid)
    INTO v_name, v_owner
    FROM storage.objects o
   WHERE o.bucket_id = 'mission-proofs' AND o.name = trim(p_path)
   LIMIT 1;
  IF v_name IS NULL THEN
    RAISE EXCEPTION 'CUSTODY_PHOTO_NOT_FOUND' USING DETAIL = trim(p_path);
  END IF;
  IF split_part(v_name, '/', 1) <> p_mission_id::text THEN
    RAISE EXCEPTION 'CUSTODY_PHOTO_MISSION_MISMATCH';
  END IF;
  IF v_owner IS DISTINCT FROM p_courier THEN
    RAISE EXCEPTION 'CUSTODY_PHOTO_OWNER_MISMATCH';
  END IF;
  IF split_part(split_part(v_name, '/', 2), '-', 1) <> p_phase THEN
    RAISE EXCEPTION 'CUSTODY_PHOTO_PHASE_MISMATCH' USING DETAIL = v_name;
  END IF;
END; $$;
REVOKE ALL ON FUNCTION public._repas_custody_verify_photo(uuid,text,uuid,text) FROM PUBLIC, anon, authenticated;

-- ============ issue: encrypted at rest ============
CREATE OR REPLACE FUNCTION public._repas_custody_issue(p_order_id uuid, p_kind text, p_holder uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','vault' AS $$
DECLARE v_code text; v_salt text; v_id uuid; v_sec uuid;
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
  v_sec := vault.create_secret(
             v_code,
             'repas_custody:' || p_order_id::text || ':' || p_kind || ':' || encode(gen_random_bytes(4),'hex'),
             'CHOPCHOP R6 one-time custody credential');

  INSERT INTO public.repas_custody_credentials(
    order_id, kind, holder_user_id, code_salt, code_hash, code_secret_id)
  VALUES (p_order_id, p_kind, p_holder, v_salt,
          public._repas_custody_hash(v_salt, v_code), v_sec)
  RETURNING id INTO v_id;
  RETURN v_id;
END; $$;
REVOKE ALL ON FUNCTION public._repas_custody_issue(uuid,text,uuid) FROM PUBLIC, anon, authenticated;

-- ============ consume: destroy secret on success ============
CREATE OR REPLACE FUNCTION public._repas_custody_consume(p_order_id uuid, p_kind text, p_code text, p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','vault' AS $$
DECLARE v public.repas_custody_credentials; v_att int;
BEGIN
  SELECT * INTO v FROM public.repas_custody_credentials
   WHERE order_id = p_order_id AND kind = p_kind FOR UPDATE;
  IF v.id IS NULL THEN RAISE EXCEPTION 'CUSTODY_CODE_NOT_ISSUED'; END IF;
  IF v.consumed_at IS NOT NULL THEN RAISE EXCEPTION 'CUSTODY_CODE_ALREADY_USED'; END IF;
  IF v.locked_at IS NOT NULL THEN RAISE EXCEPTION 'CUSTODY_CODE_LOCKED'; END IF;
  IF public._repas_custody_dispute_blocked(p_order_id) THEN
    RAISE EXCEPTION 'CUSTODY_DISPUTE_BLOCKED';
  END IF;
  IF p_code IS NULL OR length(trim(p_code)) = 0 THEN
    RAISE EXCEPTION 'CUSTODY_CODE_REQUIRED';
  END IF;

  IF public._repas_custody_hash(v.code_salt, trim(p_code)) IS DISTINCT FROM v.code_hash THEN
    UPDATE public.repas_custody_credentials
       SET attempts = attempts + 1,
           locked_at = CASE WHEN attempts + 1 >= 5 THEN now() ELSE locked_at END,
           updated_at = now()
     WHERE id = v.id
     RETURNING attempts INTO v_att;
    IF v_att >= 5 THEN PERFORM public._repas_custody_purge_secret(v.id); END IF;
    RETURN jsonb_build_object('ok', false, 'error', 'CUSTODY_CODE_INVALID',
                              'attempts', v_att, 'attempts_left', GREATEST(5 - v_att, 0),
                              'locked', v_att >= 5);
  END IF;

  UPDATE public.repas_custody_credentials
     SET consumed_at = now(), consumed_by = p_actor, updated_at = now()
   WHERE id = v.id;
  PERFORM public._repas_custody_purge_secret(v.id);
  RETURN jsonb_build_object('ok', true);
END; $$;
REVOKE ALL ON FUNCTION public._repas_custody_consume(uuid,text,text,uuid) FROM PUBLIC, anon, authenticated;

-- ============ holder-scoped retrieval from vault ============
CREATE OR REPLACE FUNCTION public.repas_custody_code_view(p_order_id uuid, p_kind text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public','vault' AS $$
DECLARE v_uid uuid := auth.uid(); v public.repas_custody_credentials; v_state text; v_code text;
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
  IF v.holder_user_id IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'CUSTODY_CODE_FORBIDDEN';
  END IF;
  IF v_state IN ('completed','cancelled') THEN
    RETURN jsonb_build_object('issued', true, 'kind', p_kind, 'expired', true, 'active', false);
  END IF;
  IF public._repas_custody_dispute_blocked(p_order_id) THEN
    RETURN jsonb_build_object('issued', true, 'kind', p_kind, 'expired', true,
                              'active', false, 'disputed', true);
  END IF;

  IF v.consumed_at IS NULL AND v.locked_at IS NULL AND v.code_secret_id IS NOT NULL THEN
    SELECT decrypted_secret INTO v_code FROM vault.decrypted_secrets WHERE id = v.code_secret_id;
  END IF;

  RETURN jsonb_build_object(
    'issued', true, 'kind', p_kind, 'expired', false, 'active', true,
    'code', v_code,
    'consumed', v.consumed_at IS NOT NULL,
    'locked', v.locked_at IS NOT NULL,
    'attempts', v.attempts,
    'attempts_left', GREATEST(5 - v.attempts, 0));
END; $$;
REVOKE ALL ON FUNCTION public.repas_custody_code_view(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.repas_custody_code_view(uuid,text) TO authenticated;

-- ============ terminal invalidation trigger ============
CREATE OR REPLACE FUNCTION public._repas_custody_invalidate_on_terminal()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public' AS $$
DECLARE r record;
BEGIN
  IF NEW.state::text IN ('completed','cancelled') AND NEW.state IS DISTINCT FROM OLD.state THEN
    FOR r IN SELECT id FROM public.repas_custody_credentials WHERE order_id = NEW.id LOOP
      PERFORM public._repas_custody_purge_secret(r.id);
    END LOOP;
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_repas_custody_invalidate ON public.food_orders;
CREATE TRIGGER trg_repas_custody_invalidate
AFTER UPDATE OF state ON public.food_orders
FOR EACH ROW EXECUTE FUNCTION public._repas_custody_invalidate_on_terminal();

-- ============ confirm RPCs: real proof + dispute gate ============
CREATE OR REPLACE FUNCTION public.repas_custody_confirm_handoff(p_mission_id uuid, p_photo_path text, p_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public' AS $$
DECLARE v_consume jsonb; v_uid uuid := auth.uid(); v_m public.missions; v_o public.food_orders;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

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
  IF public._repas_custody_dispute_blocked(v_o.id) THEN
    RAISE EXCEPTION 'CUSTODY_DISPUTE_BLOCKED';
  END IF;

  PERFORM public._repas_custody_verify_photo(p_mission_id, p_photo_path, v_uid, 'pickup');

  v_consume := public._repas_custody_consume(v_o.id, 'restaurant_handoff', p_code, v_uid);
  IF NOT (v_consume->>'ok')::boolean THEN RETURN v_consume; END IF;

  UPDATE public.missions
     SET state = 'picked_up'::public.mission_state,
         pickup_confirmed_at = now(), pickup_confirmed_by = v_uid,
         pickup_photo_url = trim(p_photo_path)
   WHERE id = p_mission_id RETURNING * INTO v_m;

  INSERT INTO public.repas_custody_events(
    order_id, mission_id, boundary, actor_user_id, counterparty_user_id, method, photo_path)
  VALUES (v_o.id, p_mission_id, 'restaurant_to_courier', v_uid,
          (SELECT owner_user_id FROM public.food_restaurants WHERE id = v_o.restaurant_id),
          'code_photo', trim(p_photo_path));

  INSERT INTO public.mission_events(mission_id, event, actor_id, note)
  VALUES (p_mission_id, 'repas_custody_restaurant_to_courier', v_uid, trim(p_photo_path));

  PERFORM set_config('chopchop.cash_engine','1',true);
  UPDATE public.food_orders SET state = 'out_for_delivery', updated_at = now()
   WHERE id = v_o.id;
  PERFORM set_config('chopchop.cash_engine','0',true);

  PERFORM public._repas_custody_issue(v_o.id, 'customer_delivery', v_o.user_id);

  RETURN jsonb_build_object('ok', true, 'boundary','restaurant_to_courier',
                            'mission_state', v_m.state::text, 'order_state','out_for_delivery');
END; $$;

CREATE OR REPLACE FUNCTION public.repas_custody_confirm_delivery(p_mission_id uuid, p_photo_path text, p_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public' AS $$
DECLARE v_consume jsonb; v_uid uuid := auth.uid(); v_m public.missions; v_o public.food_orders;
        v_cash public.cash_order_runtime; v_cp public.chop_pay_order_runtime; v_res jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

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
  IF public._repas_custody_dispute_blocked(v_o.id) THEN
    RAISE EXCEPTION 'CUSTODY_DISPUTE_BLOCKED';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.repas_custody_events
                  WHERE order_id = v_o.id AND boundary = 'restaurant_to_courier') THEN
    RAISE EXCEPTION 'CUSTODY_NOT_ESTABLISHED';
  END IF;

  PERFORM public._repas_custody_verify_photo(p_mission_id, p_photo_path, v_uid, 'delivery');

  v_consume := public._repas_custody_consume(v_o.id, 'customer_delivery', p_code, v_uid);
  IF NOT (v_consume->>'ok')::boolean THEN RETURN v_consume; END IF;

  UPDATE public.missions
     SET state = 'delivered'::public.mission_state,
         dropoff_confirmed_at = now(), dropoff_confirmed_by = v_uid,
         delivery_photo_url = trim(p_photo_path)
   WHERE id = p_mission_id RETURNING * INTO v_m;

  INSERT INTO public.repas_custody_events(
    order_id, mission_id, boundary, actor_user_id, counterparty_user_id, method, photo_path)
  VALUES (v_o.id, p_mission_id, 'courier_to_customer', v_uid, v_o.user_id,
          'code_photo', trim(p_photo_path));

  INSERT INTO public.mission_events(mission_id, event, actor_id, note)
  VALUES (p_mission_id, 'repas_custody_courier_to_customer', v_uid, trim(p_photo_path));

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

CREATE OR REPLACE FUNCTION public.repas_custody_confirm_pickup_collection(p_order_id uuid, p_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public' AS $$
DECLARE v_consume jsonb; v_uid uuid := auth.uid(); v_o public.food_orders; v_owner uuid; v_res jsonb;
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
  IF public._repas_custody_dispute_blocked(p_order_id) THEN
    RAISE EXCEPTION 'CUSTODY_DISPUTE_BLOCKED';
  END IF;

  v_consume := public._repas_custody_consume(p_order_id, 'customer_pickup', p_code, v_uid);
  IF NOT (v_consume->>'ok')::boolean THEN RETURN v_consume; END IF;

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
