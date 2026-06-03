
-- 1. Add missing 'in_app' value to message_channel enum (idempotent)
ALTER TYPE public.message_channel ADD VALUE IF NOT EXISTS 'in_app';

-- 2. Recreate driver_apply with safe notification insert
CREATE OR REPLACE FUNCTION public.driver_apply(p_payload jsonb)
RETURNS public.driver_applications
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_app public.driver_applications;
  v_vehicle public.driver_vehicle_type;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT (p_payload ? 'vehicle_type') THEN
    RAISE EXCEPTION 'vehicle_type required';
  END IF;

  v_vehicle := (p_payload->>'vehicle_type')::public.driver_vehicle_type;

  INSERT INTO public.driver_profiles (
    user_id, status, vehicle_type, plate_number,
    driver_photo_url, id_doc_url, vehicle_photo_url, zones
  ) VALUES (
    v_uid, 'pending', v_vehicle,
    NULLIF(p_payload->>'plate_number',''),
    NULLIF(p_payload->>'driver_photo_url',''),
    NULLIF(p_payload->>'id_doc_url',''),
    NULLIF(p_payload->>'vehicle_photo_url',''),
    COALESCE(ARRAY(SELECT jsonb_array_elements_text(p_payload->'zones')), '{}')
  )
  ON CONFLICT (user_id) DO UPDATE SET
    status = 'pending',
    vehicle_type = EXCLUDED.vehicle_type,
    plate_number = EXCLUDED.plate_number,
    driver_photo_url = COALESCE(EXCLUDED.driver_photo_url, public.driver_profiles.driver_photo_url),
    id_doc_url = COALESCE(EXCLUDED.id_doc_url, public.driver_profiles.id_doc_url),
    vehicle_photo_url = COALESCE(EXCLUDED.vehicle_photo_url, public.driver_profiles.vehicle_photo_url),
    zones = EXCLUDED.zones,
    rejected_reason = NULL,
    suspended_reason = NULL,
    updated_at = now();

  INSERT INTO public.driver_applications (user_id, payload, decision)
  VALUES (v_uid, p_payload, 'pending')
  RETURNING * INTO v_app;

  -- Notification log (non-blocking)
  BEGIN
    INSERT INTO public.notification_log (user_id, channel, template, status, payload)
    VALUES (
      v_uid, 'in_app'::public.message_channel, 'driver_application_submitted',
      'pending'::public.notification_status,
      jsonb_build_object('application_id', v_app.id)
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE LOG 'driver_apply notification_log insert failed: %', SQLERRM;
  END;

  RETURN v_app;
END;
$$;

-- 3. Recreate driver_admin_decide with safe notification insert
CREATE OR REPLACE FUNCTION public.driver_admin_decide(
  p_user_id uuid,
  p_decision text,
  p_reason text DEFAULT NULL
)
RETURNS public.driver_profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_profile public.driver_profiles;
  v_app_id uuid;
  v_template text;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.can_manage_operations(v_caller) THEN
    RAISE EXCEPTION 'Only operations or god admins can decide';
  END IF;

  SELECT * INTO v_profile FROM public.driver_profiles WHERE user_id = p_user_id FOR UPDATE;
  IF v_profile.user_id IS NULL THEN RAISE EXCEPTION 'Driver profile not found'; END IF;

  IF p_decision = 'approve' THEN
    UPDATE public.driver_profiles SET
      status = 'approved', approved_at = now(), approved_by = v_caller,
      rejected_reason = NULL, suspended_reason = NULL
      WHERE user_id = p_user_id RETURNING * INTO v_profile;
    INSERT INTO public.user_roles (user_id, role) VALUES (p_user_id, 'driver'::public.app_role)
      ON CONFLICT DO NOTHING;
    INSERT INTO public.wallets (owner_user_id, party_type) VALUES (p_user_id, 'driver')
      ON CONFLICT (owner_user_id, party_type) DO NOTHING;
    v_template := 'driver_approved';
  ELSIF p_decision = 'reject' THEN
    UPDATE public.driver_profiles SET
      status = 'rejected', rejected_reason = p_reason
      WHERE user_id = p_user_id RETURNING * INTO v_profile;
    v_template := 'driver_rejected';
  ELSIF p_decision = 'suspend' THEN
    UPDATE public.driver_profiles SET
      status = 'suspended', suspended_reason = p_reason, presence = 'offline'
      WHERE user_id = p_user_id RETURNING * INTO v_profile;
    v_template := 'driver_suspended';
  ELSIF p_decision = 'reactivate' THEN
    UPDATE public.driver_profiles SET
      status = 'approved', suspended_reason = NULL
      WHERE user_id = p_user_id RETURNING * INTO v_profile;
    v_template := 'driver_reactivated';
  ELSIF p_decision = 'more_info' THEN
    v_template := 'driver_more_info';
  ELSE
    RAISE EXCEPTION 'Unknown decision %', p_decision;
  END IF;

  SELECT id INTO v_app_id FROM public.driver_applications
    WHERE user_id = p_user_id ORDER BY created_at DESC LIMIT 1;
  IF v_app_id IS NOT NULL THEN
    UPDATE public.driver_applications SET
      decision = (CASE
        WHEN p_decision = 'approve' THEN 'approved'::driver_application_decision
        WHEN p_decision = 'reject' THEN 'rejected'::driver_application_decision
        WHEN p_decision = 'more_info' THEN 'more_info'::driver_application_decision
        ELSE decision END),
      decision_reason = p_reason,
      decided_by = v_caller,
      decided_at = now()
      WHERE id = v_app_id;
  END IF;

  INSERT INTO public.audit_logs (actor_user_id, actor_role, module, action, target_type, target_id, after, note)
  VALUES (
    v_caller, public.current_admin_role(v_caller),
    'drivers', 'driver.' || p_decision, 'driver_profile', p_user_id::text,
    jsonb_build_object('status', v_profile.status, 'reason', p_reason),
    p_reason
  );

  BEGIN
    INSERT INTO public.notification_log (user_id, channel, template, status, payload)
    VALUES (
      p_user_id, 'in_app'::public.message_channel, v_template,
      'pending'::public.notification_status,
      jsonb_build_object('reason', p_reason)
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE LOG 'driver_admin_decide notification_log insert failed: %', SQLERRM;
  END;

  RETURN v_profile;
END;
$$;
