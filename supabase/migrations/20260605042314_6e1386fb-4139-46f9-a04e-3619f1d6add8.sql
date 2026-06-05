
DROP FUNCTION IF EXISTS public.admin_anonymize_user(uuid, text);
DROP FUNCTION IF EXISTS public._anonymize_user_core(uuid, text);

CREATE FUNCTION public._anonymize_user_core(_target uuid, _suspended_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_steps jsonb := '[]'::jsonb;
  v_err text;
  v_state text;
BEGIN
  UPDATE public.profiles
     SET account_status='deleted', deleted_at=now(),
         full_name='Utilisateur supprimé', display_name='Utilisateur supprimé',
         first_name=NULL, last_name=NULL, phone=NULL, email=NULL, avatar_url=NULL,
         updated_at=now()
   WHERE user_id=_target;
  v_steps := v_steps || jsonb_build_object('step','profiles','ok',true);

  BEGIN
    UPDATE public.driver_profiles
       SET presence='offline', status='suspended',
           suspended_reason=COALESCE(suspended_reason,_suspended_reason),
           updated_at=now()
     WHERE user_id=_target;
    v_steps := v_steps || jsonb_build_object('step','driver_profiles','ok',true);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT, v_state = RETURNED_SQLSTATE;
    v_steps := v_steps || jsonb_build_object('step','driver_profiles','ok',false,'sqlstate',v_state,'error',v_err);
  END;

  BEGIN
    UPDATE public.merchants SET status='inactive', updated_at=now() WHERE owner_user_id=_target;
    v_steps := v_steps || jsonb_build_object('step','merchants','ok',true);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT, v_state = RETURNED_SQLSTATE;
    v_steps := v_steps || jsonb_build_object('step','merchants','ok',false,'sqlstate',v_state,'error',v_err);
  END;

  BEGIN
    UPDATE public.service_profiles SET status='archived', visibility='private', updated_at=now() WHERE user_id=_target;
    v_steps := v_steps || jsonb_build_object('step','service_profiles','ok',true);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT, v_state = RETURNED_SQLSTATE;
    v_steps := v_steps || jsonb_build_object('step','service_profiles','ok',false,'sqlstate',v_state,'error',v_err);
  END;

  -- listing_status enum: active/sold/paused/removed → use 'removed'
  BEGIN
    UPDATE public.marketplace_listings SET status='removed', updated_at=now() WHERE seller_id=_target;
    v_steps := v_steps || jsonb_build_object('step','marketplace_listings','ok',true);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT, v_state = RETURNED_SQLSTATE;
    v_steps := v_steps || jsonb_build_object('step','marketplace_listings','ok',false,'sqlstate',v_state,'error',v_err);
  END;

  BEGIN
    UPDATE public.merchant_stores SET is_active=false, updated_at=now() WHERE owner_user_id=_target;
    v_steps := v_steps || jsonb_build_object('step','merchant_stores','ok',true);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT, v_state = RETURNED_SQLSTATE;
    v_steps := v_steps || jsonb_build_object('step','merchant_stores','ok',false,'sqlstate',v_state,'error',v_err);
  END;

  BEGIN
    DELETE FROM public.driver_locations WHERE driver_id=_target;
    v_steps := v_steps || jsonb_build_object('step','driver_locations','ok',true);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT, v_state = RETURNED_SQLSTATE;
    v_steps := v_steps || jsonb_build_object('step','driver_locations','ok',false,'sqlstate',v_state,'error',v_err);
  END;

  RETURN jsonb_build_object('ok', true, 'steps', v_steps);
END;
$function$;

CREATE FUNCTION public.admin_anonymize_user(_target uuid, _reason text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  _caller uuid := auth.uid();
  v_core jsonb;
  v_err text;
  v_state text;
BEGIN
  IF _caller IS NOT NULL
     AND NOT (public.has_admin_role(_caller,'god_admin'::admin_role)
              OR public.has_admin_role(_caller,'super_admin'::admin_role)) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE='42501';
  END IF;

  BEGIN
    v_core := public._anonymize_user_core(_target, 'admin_anonymized');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT, v_state = RETURNED_SQLSTATE;
    RETURN jsonb_build_object('ok',false,'mode','anonymized','sqlstate',v_state,'detail',v_err);
  END;

  BEGIN
    INSERT INTO public.account_deletion_requests(user_id, requested_by, request_type, status, reason, processed_by, processed_at)
    VALUES (_target,_caller,'admin_anonymize','processed',_reason,_caller, now());
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT, v_state = RETURNED_SQLSTATE;
    v_core := v_core || jsonb_build_object('audit_warning',jsonb_build_object('sqlstate',v_state,'error',v_err));
  END;

  RETURN jsonb_build_object('ok', true, 'mode', 'anonymized', 'steps', v_core->'steps');
END;
$function$;
