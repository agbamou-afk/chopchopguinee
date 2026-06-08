
-- =========================================================
-- admin_list_driver_applications
-- =========================================================
CREATE OR REPLACE FUNCTION public.admin_list_driver_applications(
  p_status text DEFAULT NULL
)
RETURNS TABLE (
  user_id uuid,
  application_id uuid,
  display_name text,
  phone text,
  email text,
  vehicle_type text,
  plate_number text,
  status text,
  application_decision text,
  zones text[],
  submitted_at timestamptz,
  driver_created_at timestamptz,
  has_selfie boolean,
  has_id_doc boolean,
  has_vehicle_photo boolean,
  missing_required text[],
  is_complete boolean,
  rejected_reason text,
  suspended_reason text,
  decision_reason text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.can_manage_operations(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  RETURN QUERY
  WITH latest_app AS (
    SELECT DISTINCT ON (a.user_id)
      a.user_id, a.id, a.decision::text AS decision, a.decision_reason,
      a.created_at, a.payload
    FROM public.driver_applications a
    ORDER BY a.user_id, a.created_at DESC
  )
  SELECT
    dp.user_id,
    la.id AS application_id,
    COALESCE(
      NULLIF(p.display_name, ''),
      NULLIF(p.full_name, ''),
      NULLIF(trim(concat_ws(' ', p.first_name, p.last_name)), ''),
      NULLIF(split_part(COALESCE(p.email,''), '@', 1), ''),
      'Candidat sans nom'
    ) AS display_name,
    p.phone,
    p.email,
    dp.vehicle_type::text,
    dp.plate_number,
    dp.status::text,
    la.decision,
    dp.zones,
    la.created_at AS submitted_at,
    dp.created_at AS driver_created_at,
    (dp.driver_photo_url IS NOT NULL) AS has_selfie,
    (dp.id_doc_url IS NOT NULL) AS has_id_doc,
    (dp.vehicle_photo_url IS NOT NULL) AS has_vehicle_photo,
    ARRAY(
      SELECT v FROM (VALUES
        ('selfie', dp.driver_photo_url IS NULL),
        ('id_doc', dp.id_doc_url IS NULL),
        ('vehicle_photo', dp.vehicle_photo_url IS NULL),
        ('plate_number', NULLIF(dp.plate_number,'') IS NULL),
        ('vehicle_type', dp.vehicle_type IS NULL)
      ) AS x(v, missing) WHERE missing
    ) AS missing_required,
    (dp.driver_photo_url IS NOT NULL
      AND dp.id_doc_url IS NOT NULL
      AND dp.vehicle_photo_url IS NOT NULL
      AND NULLIF(dp.plate_number,'') IS NOT NULL
      AND dp.vehicle_type IS NOT NULL) AS is_complete,
    dp.rejected_reason,
    dp.suspended_reason,
    la.decision_reason
  FROM public.driver_profiles dp
  LEFT JOIN latest_app la ON la.user_id = dp.user_id
  LEFT JOIN public.profiles p ON p.user_id = dp.user_id
  WHERE p_status IS NULL
     OR (p_status = 'pending' AND dp.status::text = 'pending')
     OR (p_status = 'approved' AND dp.status::text = 'approved')
     OR (p_status = 'suspended' AND dp.status::text IN ('suspended','rejected'))
     OR (p_status = 'needs_info' AND la.decision = 'more_info')
  ORDER BY la.created_at DESC NULLS LAST, dp.created_at DESC
  LIMIT 500;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_driver_applications(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_driver_applications(text) TO authenticated;

-- =========================================================
-- admin_get_driver_application_detail
-- =========================================================
CREATE OR REPLACE FUNCTION public.admin_get_driver_application_detail(
  p_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF NOT public.can_manage_operations(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT jsonb_build_object(
    'user_id', dp.user_id,
    'display_name', COALESCE(
      NULLIF(p.display_name,''), NULLIF(p.full_name,''),
      NULLIF(trim(concat_ws(' ', p.first_name, p.last_name)),''),
      NULLIF(split_part(COALESCE(p.email,''),'@',1),''),
      'Candidat sans nom'),
    'phone', p.phone,
    'email', p.email,
    'status', dp.status::text,
    'vehicle_type', dp.vehicle_type::text,
    'plate_number', dp.plate_number,
    'zones', dp.zones,
    'driver_photo_path', dp.driver_photo_url,
    'id_doc_path', dp.id_doc_url,
    'vehicle_photo_path', dp.vehicle_photo_url,
    'has_selfie', dp.driver_photo_url IS NOT NULL,
    'has_id_doc', dp.id_doc_url IS NOT NULL,
    'has_vehicle_photo', dp.vehicle_photo_url IS NOT NULL,
    'rejected_reason', dp.rejected_reason,
    'suspended_reason', dp.suspended_reason,
    'approved_at', dp.approved_at,
    'created_at', dp.created_at,
    'application', (
      SELECT jsonb_build_object(
        'id', a.id,
        'decision', a.decision::text,
        'decision_reason', a.decision_reason,
        'decided_at', a.decided_at,
        'created_at', a.created_at,
        'payload', a.payload
      ) FROM public.driver_applications a
        WHERE a.user_id = dp.user_id
        ORDER BY a.created_at DESC LIMIT 1
    )
  ) INTO v_result
  FROM public.driver_profiles dp
  LEFT JOIN public.profiles p ON p.user_id = dp.user_id
  WHERE dp.user_id = p_user_id;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_driver_application_detail(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_driver_application_detail(uuid) TO authenticated;

-- =========================================================
-- admin_request_driver_info
-- =========================================================
CREATE OR REPLACE FUNCTION public.admin_request_driver_info(
  p_user_id uuid,
  p_missing text[],
  p_note text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_app_id uuid;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.can_manage_operations(v_caller) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF p_note IS NULL OR length(trim(p_note)) = 0 THEN
    RAISE EXCEPTION 'note required';
  END IF;

  SELECT id INTO v_app_id FROM public.driver_applications
    WHERE user_id = p_user_id ORDER BY created_at DESC LIMIT 1;
  IF v_app_id IS NULL THEN
    RAISE EXCEPTION 'no application found';
  END IF;

  UPDATE public.driver_applications SET
    decision = 'more_info'::driver_application_decision,
    decision_reason = p_note,
    decided_by = v_caller,
    decided_at = now()
    WHERE id = v_app_id;

  INSERT INTO public.audit_logs (actor_user_id, actor_role, module, action, target_type, target_id, after, note)
  VALUES (
    v_caller, public.current_admin_role(v_caller),
    'drivers', 'driver.more_info', 'driver_profile', p_user_id::text,
    jsonb_build_object('missing', p_missing, 'note', p_note),
    p_note
  );

  BEGIN
    INSERT INTO public.notification_log (user_id, channel, template, status, payload)
    VALUES (
      p_user_id, 'in_app'::public.message_channel, 'driver_more_info',
      'pending'::public.notification_status,
      jsonb_build_object('missing', p_missing, 'note', p_note)
    );
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_request_driver_info(uuid, text[], text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_request_driver_info(uuid, text[], text) TO authenticated;
