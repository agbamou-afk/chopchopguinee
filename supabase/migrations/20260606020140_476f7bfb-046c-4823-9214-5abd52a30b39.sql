
CREATE OR REPLACE FUNCTION public.admin_check_email_reuse_blocker(p_email text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _caller uuid := auth.uid();
  v_auth_user uuid;
  v_auth_deleted timestamptz;
  v_auth_banned timestamptz;
  v_profile_count int;
  v_profile_status text;
  v_can boolean;
  v_reason text;
BEGIN
  IF _caller IS NULL
     OR NOT (public.has_admin_role(_caller,'god_admin'::admin_role)
             OR public.has_admin_role(_caller,'super_admin'::admin_role)) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE='42501';
  END IF;

  SELECT id, deleted_at, banned_until
    INTO v_auth_user, v_auth_deleted, v_auth_banned
  FROM auth.users
  WHERE lower(email) = lower(p_email)
  ORDER BY created_at DESC
  LIMIT 1;

  SELECT count(*), max(account_status)
    INTO v_profile_count, v_profile_status
  FROM public.profiles
  WHERE lower(coalesce(email,'')) = lower(p_email);

  v_can := v_auth_user IS NULL;
  IF v_auth_user IS NOT NULL THEN
    v_reason := 'auth_user_exists';
  ELSIF v_profile_count > 0 AND coalesce(v_profile_status,'') <> 'deleted' THEN
    v_reason := 'profile_row_with_email_remains';
  ELSE
    v_reason := 'ok';
  END IF;

  RETURN jsonb_build_object(
    'email', p_email,
    'auth_user_exists', v_auth_user IS NOT NULL,
    'auth_user_id', v_auth_user,
    'auth_deleted_at', v_auth_deleted,
    'auth_banned_until', v_auth_banned,
    'profile_rows_with_email', v_profile_count,
    'profile_account_status', v_profile_status,
    'can_reuse_email', v_can,
    'blocker_reason', v_reason
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_check_email_reuse_blocker(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_check_email_reuse_blocker(text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.admin_pre_purge_test_user(_target uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _caller uuid := auth.uid();
  v_steps jsonb := '[]'::jsonb;
  v_err text;
  v_state text;
  v_has_history boolean;
BEGIN
  IF _caller IS NULL
     OR NOT (public.has_admin_role(_caller,'god_admin'::admin_role)
             OR public.has_admin_role(_caller,'super_admin'::admin_role)) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE='42501';
  END IF;

  v_has_history := public.user_has_financial_history(_target);
  IF v_has_history THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'has_financial_history');
  END IF;

  BEGIN DELETE FROM public.driver_locations WHERE driver_id = _target;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','driver_locations','ok',true));
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT,v_state=RETURNED_SQLSTATE;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','driver_locations','ok',false,'sqlstate',v_state,'error',v_err)); END;

  BEGIN DELETE FROM public.driver_route_traces WHERE driver_id = _target;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','driver_route_traces','ok',true));
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT,v_state=RETURNED_SQLSTATE;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','driver_route_traces','ok',false,'sqlstate',v_state,'error',v_err)); END;

  BEGIN DELETE FROM public.ride_route_summaries WHERE driver_id = _target OR client_id = _target;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','ride_route_summaries','ok',true));
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT,v_state=RETURNED_SQLSTATE;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','ride_route_summaries','ok',false,'sqlstate',v_state,'error',v_err)); END;

  BEGIN DELETE FROM public.navigation_events WHERE user_id = _target;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','navigation_events','ok',true));
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT,v_state=RETURNED_SQLSTATE;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','navigation_events','ok',false,'sqlstate',v_state,'error',v_err)); END;

  BEGIN DELETE FROM public.location_search_events WHERE user_id = _target;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','location_search_events','ok',true));
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT,v_state=RETURNED_SQLSTATE;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','location_search_events','ok',false,'sqlstate',v_state,'error',v_err)); END;

  BEGIN DELETE FROM public.saved_places WHERE user_id = _target;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','saved_places','ok',true));
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT,v_state=RETURNED_SQLSTATE;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','saved_places','ok',false,'sqlstate',v_state,'error',v_err)); END;

  BEGIN DELETE FROM public.saved_listings WHERE user_id = _target;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','saved_listings','ok',true));
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT,v_state=RETURNED_SQLSTATE;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','saved_listings','ok',false,'sqlstate',v_state,'error',v_err)); END;

  BEGIN DELETE FROM public.listing_saves WHERE user_id = _target;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','listing_saves','ok',true));
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT,v_state=RETURNED_SQLSTATE;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','listing_saves','ok',false,'sqlstate',v_state,'error',v_err)); END;

  BEGIN DELETE FROM public.listing_interests WHERE user_id = _target;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','listing_interests','ok',true));
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT,v_state=RETURNED_SQLSTATE;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','listing_interests','ok',false,'sqlstate',v_state,'error',v_err)); END;

  BEGIN DELETE FROM public.notification_preferences WHERE user_id = _target;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','notification_preferences','ok',true));
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT,v_state=RETURNED_SQLSTATE;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','notification_preferences','ok',false,'sqlstate',v_state,'error',v_err)); END;

  BEGIN DELETE FROM public.user_preferences WHERE user_id = _target;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','user_preferences','ok',true));
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT,v_state=RETURNED_SQLSTATE;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','user_preferences','ok',false,'sqlstate',v_state,'error',v_err)); END;

  BEGIN DELETE FROM public.user_legal_consents WHERE user_id = _target;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','user_legal_consents','ok',true));
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT,v_state=RETURNED_SQLSTATE;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','user_legal_consents','ok',false,'sqlstate',v_state,'error',v_err)); END;

  BEGIN DELETE FROM public.user_consent WHERE user_id = _target;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','user_consent','ok',true));
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT,v_state=RETURNED_SQLSTATE;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','user_consent','ok',false,'sqlstate',v_state,'error',v_err)); END;

  BEGIN DELETE FROM public.user_pins WHERE user_id = _target;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','user_pins','ok',true));
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT,v_state=RETURNED_SQLSTATE;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','user_pins','ok',false,'sqlstate',v_state,'error',v_err)); END;

  BEGIN DELETE FROM public.driver_applications WHERE user_id = _target;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','driver_applications','ok',true));
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT,v_state=RETURNED_SQLSTATE;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','driver_applications','ok',false,'sqlstate',v_state,'error',v_err)); END;

  BEGIN DELETE FROM public.driver_profiles WHERE user_id = _target;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','driver_profiles','ok',true));
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT,v_state=RETURNED_SQLSTATE;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','driver_profiles','ok',false,'sqlstate',v_state,'error',v_err)); END;

  BEGIN DELETE FROM public.user_roles WHERE user_id = _target;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','user_roles','ok',true));
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT,v_state=RETURNED_SQLSTATE;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','user_roles','ok',false,'sqlstate',v_state,'error',v_err)); END;

  BEGIN DELETE FROM public.account_deletion_requests WHERE user_id = _target;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','account_deletion_requests','ok',true));
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT,v_state=RETURNED_SQLSTATE;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','account_deletion_requests','ok',false,'sqlstate',v_state,'error',v_err)); END;

  BEGIN DELETE FROM public.profiles WHERE user_id = _target;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','profiles','ok',true));
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT,v_state=RETURNED_SQLSTATE;
    v_steps := v_steps || jsonb_build_array(jsonb_build_object('table','profiles','ok',false,'sqlstate',v_state,'error',v_err)); END;

  RETURN jsonb_build_object('ok', true, 'steps', v_steps);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_pre_purge_test_user(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_pre_purge_test_user(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.admin_auth_user_exists(_target uuid)
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS(SELECT 1 FROM auth.users WHERE id = _target);
$$;

REVOKE ALL ON FUNCTION public.admin_auth_user_exists(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_auth_user_exists(uuid) TO authenticated, service_role;
