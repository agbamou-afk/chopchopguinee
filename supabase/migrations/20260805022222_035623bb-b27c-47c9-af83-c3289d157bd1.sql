-- =========================================================
-- Envoyer operational wiring
-- =========================================================

-- ---------- 1. Notification helper (sender-facing, log only) ----------
CREATE OR REPLACE FUNCTION public._package_notify(
  _user_id uuid,
  _template text,
  _payload jsonb DEFAULT '{}'::jsonb,
  _priority public.notification_priority DEFAULT 'normal'
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF _user_id IS NULL THEN RETURN; END IF;
  BEGIN
    INSERT INTO public.notification_log(user_id, channel, template, status, priority, payload)
    VALUES (_user_id, 'inapp'::public.notification_channel, _template,
            'pending'::public.notification_status, _priority, COALESCE(_payload, '{}'::jsonb));
  EXCEPTION WHEN OTHERS THEN
    -- Notifications must never break an operational transition.
    NULL;
  END;
END;
$$;

-- ---------- 2. DEF-016: admin capability control ----------
CREATE OR REPLACE FUNCTION public.admin_set_driver_capability(
  _driver_user_id uuid,
  _capability text,
  _grant boolean
) RETURNS public.driver_profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  _row public.driver_profiles;
  _before text[];
  _after text[];
BEGIN
  IF NOT public._is_ops_or_god_admin() THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;
  IF _capability NOT IN ('rides_moto','rides_toktok','repas_delivery','marche_delivery','package_delivery') THEN
    RAISE EXCEPTION 'unknown_capability';
  END IF;

  SELECT * INTO _row FROM public.driver_profiles WHERE user_id = _driver_user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'driver_profile_not_found'; END IF;

  _before := COALESCE(_row.capabilities, ARRAY[]::text[]);

  IF _grant THEN
    _after := CASE WHEN _capability = ANY(_before) THEN _before ELSE _before || _capability END;
  ELSE
    SELECT COALESCE(ARRAY_AGG(c), ARRAY[]::text[]) INTO _after
      FROM unnest(_before) c WHERE c <> _capability;
  END IF;

  IF _after IS NOT DISTINCT FROM _before THEN
    RETURN _row;
  END IF;

  UPDATE public.driver_profiles
     SET capabilities = _after
   WHERE user_id = _driver_user_id
   RETURNING * INTO _row;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, before, after)
  VALUES (auth.uid(), 'drivers', 'driver.capability.' || CASE WHEN _grant THEN 'granted' ELSE 'revoked' END,
          'driver_profile', _driver_user_id::text,
          jsonb_build_object('capabilities', _before),
          jsonb_build_object('capabilities', _after, 'capability', _capability));

  RETURN _row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_set_driver_capability(uuid, text, boolean) TO authenticated;

-- ---------- 3. Cancellation preview (read-only) ----------
CREATE OR REPLACE FUNCTION public.package_delivery_cancel_preview(p_package_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_pkg public.package_deliveries;
  v_m public.missions;
  v_s public.package_delivery_secrets;
  v_fee bigint := 0;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_pkg FROM public.package_deliveries WHERE id = p_package_id;
  IF v_pkg.id IS NULL THEN RAISE EXCEPTION 'package_not_found'; END IF;
  IF v_pkg.sender_user_id <> v_uid THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;

  IF v_pkg.cancelled_at IS NOT NULL THEN
    RETURN jsonb_build_object('already_cancelled', true, 'self_service', false,
                              'fee_gnf', v_pkg.cancellation_fee_gnf,
                              'refund_gnf', 0);
  END IF;

  SELECT * INTO v_m FROM public.missions WHERE id = v_pkg.mission_id;
  SELECT * INTO v_s FROM public.package_delivery_secrets WHERE package_id = p_package_id;

  IF v_s.pickup_verified_at IS NOT NULL OR v_pkg.package_status IN ('in_transit','delivered') THEN
    RETURN jsonb_build_object('already_cancelled', false, 'self_service', false,
                              'reason', 'picked_up',
                              'fee_gnf', 0, 'refund_gnf', 0);
  END IF;

  IF v_m.id IS NOT NULL AND v_m.courier_id IS NOT NULL THEN
    v_fee := round(v_pkg.quoted_amount_gnf * 0.10);
  END IF;

  RETURN jsonb_build_object(
    'already_cancelled', false,
    'self_service', true,
    'courier_assigned', (v_m.courier_id IS NOT NULL),
    'fee_gnf', v_fee,
    'refund_gnf', GREATEST(v_pkg.quoted_amount_gnf - v_fee, 0),
    'paid', (v_pkg.payment_status IN ('authorized','settled'))
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.package_delivery_cancel_preview(uuid) TO authenticated;

-- ---------- 4. Pickup verification: persist failed attempts ----------
CREATE OR REPLACE FUNCTION public.package_verify_pickup(p_package_id uuid, p_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_pkg public.package_deliveries;
  v_m public.missions;
  v_s public.package_delivery_secrets;
  v_code text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_pkg FROM public.package_deliveries WHERE id = p_package_id FOR UPDATE;
  IF v_pkg.id IS NULL THEN RAISE EXCEPTION 'package_not_found'; END IF;
  SELECT * INTO v_m FROM public.missions WHERE id = v_pkg.mission_id FOR UPDATE;
  IF v_m.id IS NULL THEN RAISE EXCEPTION 'mission_not_found'; END IF;
  IF v_m.courier_id IS DISTINCT FROM v_uid THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;

  SELECT * INTO v_s FROM public.package_delivery_secrets WHERE package_id = p_package_id FOR UPDATE;
  IF v_s.package_id IS NULL THEN RAISE EXCEPTION 'secrets_missing'; END IF;

  IF v_s.pickup_verified_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'idempotent', true, 'mission_state', v_m.state);
  END IF;

  -- Lockout and wrong-code paths RETURN (never RAISE) so the attempt counter
  -- is actually committed. Raising rolled the increment back, which made the
  -- lockout unreachable.
  IF v_s.pickup_attempts >= 6 THEN
    RETURN jsonb_build_object('ok', false, 'idempotent', false, 'error', 'too_many_attempts',
                              'attempts', v_s.pickup_attempts, 'attempts_left', 0,
                              'mission_state', v_m.state);
  END IF;

  IF v_m.state NOT IN ('assigned','heading_to_pickup','arrived_pickup') THEN
    RAISE EXCEPTION 'invalid_state' USING ERRCODE='22023';
  END IF;

  v_code := regexp_replace(COALESCE(p_code,''), '\D', '', 'g');
  IF v_code <> v_s.pickup_code THEN
    UPDATE public.package_delivery_secrets
       SET pickup_attempts = pickup_attempts + 1
     WHERE package_id = p_package_id;
    INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
    VALUES (v_uid, 'package', 'package.pickup.code_failed', 'package_delivery', p_package_id::text,
            jsonb_build_object('attempts', v_s.pickup_attempts + 1));
    RETURN jsonb_build_object('ok', false, 'idempotent', false, 'error', 'invalid_code',
                              'attempts', v_s.pickup_attempts + 1,
                              'attempts_left', GREATEST(6 - (v_s.pickup_attempts + 1), 0),
                              'mission_state', v_m.state);
  END IF;

  UPDATE public.package_delivery_secrets
     SET pickup_verified_at = now(), pickup_attempts = pickup_attempts + 1
   WHERE package_id = p_package_id;

  UPDATE public.missions
     SET state = 'picked_up'::public.mission_state,
         pickup_confirmed_at = now(), pickup_confirmed_by = v_uid
   WHERE id = v_m.id;

  UPDATE public.package_deliveries SET package_status = 'in_transit' WHERE id = p_package_id;

  INSERT INTO public.mission_events(mission_id, event, actor_id, note)
  VALUES (v_m.id, 'picked_up', v_uid, 'package_code_verified');

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
  VALUES (v_uid, 'package', 'package.pickup.verified', 'package_delivery', p_package_id::text,
          jsonb_build_object('mission_id', v_m.id));

  PERFORM public._package_notify(
    v_pkg.sender_user_id, 'package_picked_up',
    jsonb_build_object('package_id', v_pkg.id, 'reference', v_pkg.reference,
                       'mission_id', v_m.id, 'sandbox', v_pkg.is_sandbox), 'high');

  RETURN jsonb_build_object('ok', true, 'idempotent', false, 'mission_state', 'picked_up');
END;
$$;

-- ---------- 5. Delivery verification: persist failed attempts ----------
CREATE OR REPLACE FUNCTION public.package_verify_delivery(
  p_package_id uuid, p_code text, p_recipient_name text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_pkg public.package_deliveries;
  v_m public.missions;
  v_s public.package_delivery_secrets;
  v_code text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_pkg FROM public.package_deliveries WHERE id = p_package_id FOR UPDATE;
  IF v_pkg.id IS NULL THEN RAISE EXCEPTION 'package_not_found'; END IF;
  SELECT * INTO v_m FROM public.missions WHERE id = v_pkg.mission_id FOR UPDATE;
  IF v_m.id IS NULL THEN RAISE EXCEPTION 'mission_not_found'; END IF;
  IF v_m.courier_id IS DISTINCT FROM v_uid THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;

  SELECT * INTO v_s FROM public.package_delivery_secrets WHERE package_id = p_package_id FOR UPDATE;
  IF v_s.package_id IS NULL THEN RAISE EXCEPTION 'secrets_missing'; END IF;
  IF v_s.delivery_verified_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', true, 'idempotent', true, 'mission_state', v_m.state);
  END IF;
  IF v_s.pickup_verified_at IS NULL THEN RAISE EXCEPTION 'pickup_not_verified' USING ERRCODE='22023'; END IF;

  IF v_s.delivery_attempts >= 6 THEN
    RETURN jsonb_build_object('ok', false, 'idempotent', false, 'error', 'too_many_attempts',
                              'attempts', v_s.delivery_attempts, 'attempts_left', 0,
                              'mission_state', v_m.state);
  END IF;

  IF v_m.state NOT IN ('picked_up','heading_to_dropoff','arrived_dropoff') THEN
    RAISE EXCEPTION 'invalid_state' USING ERRCODE='22023';
  END IF;

  v_code := regexp_replace(COALESCE(p_code,''), '\D', '', 'g');
  IF v_code <> v_s.delivery_code THEN
    UPDATE public.package_delivery_secrets
       SET delivery_attempts = delivery_attempts + 1
     WHERE package_id = p_package_id;
    INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
    VALUES (v_uid, 'package', 'package.delivery.code_failed', 'package_delivery', p_package_id::text,
            jsonb_build_object('attempts', v_s.delivery_attempts + 1));
    RETURN jsonb_build_object('ok', false, 'idempotent', false, 'error', 'invalid_code',
                              'attempts', v_s.delivery_attempts + 1,
                              'attempts_left', GREATEST(6 - (v_s.delivery_attempts + 1), 0),
                              'mission_state', v_m.state);
  END IF;

  UPDATE public.package_delivery_secrets
     SET delivery_verified_at = now(), delivery_attempts = delivery_attempts + 1
   WHERE package_id = p_package_id;

  UPDATE public.missions
     SET state = 'delivered'::public.mission_state,
         dropoff_confirmed_at = now(), dropoff_confirmed_by = v_uid
   WHERE id = v_m.id;

  UPDATE public.package_deliveries
     SET package_status = 'delivered', delivered_at = now(),
         recipient_confirmed_name = COALESCE(left(trim(p_recipient_name),120), recipient_name),
         payment_status = CASE WHEN is_sandbox THEN payment_status ELSE 'settled' END
   WHERE id = p_package_id;

  INSERT INTO public.mission_events(mission_id, event, actor_id, note)
  VALUES (v_m.id, 'delivered', v_uid, 'package_code_verified');

  IF NOT v_pkg.is_sandbox THEN
    BEGIN
      PERFORM public.wallet_credit_mission_earning(v_m.id, 'package_verify_delivery');
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO public.mission_events(mission_id, event, actor_id, note)
      VALUES (v_m.id, 'issue', v_uid, 'courier_earning_failed: ' || SQLERRM);
    END;
  END IF;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
  VALUES (v_uid, 'package', 'package.delivery.verified', 'package_delivery', p_package_id::text,
          jsonb_build_object('mission_id', v_m.id, 'sandbox', v_pkg.is_sandbox));

  PERFORM public._package_notify(
    v_pkg.sender_user_id, 'package_delivered',
    jsonb_build_object('package_id', v_pkg.id, 'reference', v_pkg.reference,
                       'mission_id', v_m.id, 'sandbox', v_pkg.is_sandbox), 'high');

  RETURN jsonb_build_object('ok', true, 'idempotent', false, 'mission_state', 'delivered');
END;
$$;

-- ---------- 6. Dispatch notification at finalisation ----------
CREATE OR REPLACE FUNCTION public.package_delivery_finalize_from_intent(p_intent_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_intent public.payment_intents;
  v_pkg public.package_deliveries;
  v_mission public.missions;
BEGIN
  SELECT * INTO v_intent FROM public.payment_intents WHERE id = p_intent_id FOR UPDATE;
  IF v_intent.id IS NULL THEN RAISE EXCEPTION 'intent_not_found'; END IF;
  IF v_intent.source_module <> 'package' OR v_intent.source_id IS NULL THEN
    RAISE EXCEPTION 'not_a_package_intent';
  END IF;

  SELECT * INTO v_pkg FROM public.package_deliveries WHERE id = v_intent.source_id FOR UPDATE;
  IF v_pkg.id IS NULL THEN RAISE EXCEPTION 'package_not_found'; END IF;

  IF v_pkg.mission_id IS NOT NULL THEN
    RETURN jsonb_build_object('idempotent', true, 'package_id', v_pkg.id, 'mission_id', v_pkg.mission_id);
  END IF;

  IF v_intent.amount_gnf <> v_pkg.quoted_amount_gnf THEN
    RAISE EXCEPTION 'amount_mismatch';
  END IF;

  INSERT INTO public.missions(
    type, state, customer_id, courier_id,
    pickup_address, pickup_lat, pickup_lng,
    dropoff_address, dropoff_lat, dropoff_lng,
    payload_summary, estimated_earning_gnf,
    estimated_distance_m, estimated_duration_s
  ) VALUES (
    'package_delivery'::public.mission_type, 'assigned'::public.mission_state, v_pkg.sender_user_id, NULL,
    v_pkg.pickup_label, v_pkg.pickup_lat, v_pkg.pickup_lng,
    v_pkg.destination_label, v_pkg.destination_lat, v_pkg.destination_lng,
    'Colis ' || v_pkg.reference || ' · ' || v_pkg.category, v_pkg.quoted_amount_gnf,
    v_pkg.distance_meters, v_pkg.duration_seconds
  ) RETURNING * INTO v_mission;

  INSERT INTO public.package_delivery_secrets(package_id, pickup_code, delivery_code)
  VALUES (v_pkg.id, public._package_new_code(), public._package_new_code())
  ON CONFLICT (package_id) DO NOTHING;

  UPDATE public.package_deliveries
     SET mission_id = v_mission.id,
         payment_status = 'authorized',
         package_status = 'dispatching'
   WHERE id = v_pkg.id;

  UPDATE public.payment_intents
     SET state = 'confirmed', authorized_at = COALESCE(authorized_at, now()),
         related_mission_id = v_mission.id,
         metadata = metadata || jsonb_build_object('package_mission_id', v_mission.id, 'finalized_at', now()),
         updated_at = now()
   WHERE id = v_intent.id;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after)
  VALUES (auth.uid(), 'package', 'package.finalized', 'package_delivery', v_pkg.id::text,
          jsonb_build_object('mission_id', v_mission.id, 'intent_id', v_intent.id, 'sandbox', v_pkg.is_sandbox));

  PERFORM public._package_notify(
    v_pkg.sender_user_id, 'package_dispatching',
    jsonb_build_object('package_id', v_pkg.id, 'reference', v_pkg.reference,
                       'mission_id', v_mission.id, 'sandbox', v_pkg.is_sandbox), 'high');

  RETURN jsonb_build_object('idempotent', false, 'package_id', v_pkg.id, 'mission_id', v_mission.id);
END;
$$;