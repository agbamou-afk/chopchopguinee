REVOKE ALL ON FUNCTION public._dcal_guard() FROM PUBLIC, anon, authenticated;

-- ---------- closure core records the dormant liability ----------
CREATE OR REPLACE FUNCTION public._account_closure_core(_target uuid, _mode text, _reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_bl jsonb; v_lane text; v_core jsonb; v_status text; v_n int;
  v_auth jsonb := '{}'::jsonb;
  v_liab jsonb;
BEGIN
  IF _target IS NULL THEN RAISE EXCEPTION 'TARGET_REQUIRED'; END IF;

  SELECT account_status INTO v_status FROM public.profiles
   WHERE user_id = _target FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ACCOUNT_NOT_FOUND'; END IF;
  IF v_status = 'deleted' THEN RAISE EXCEPTION 'ACCOUNT_ALREADY_CLOSED'; END IF;

  v_bl := public._account_closure_blockers(_target, _mode);
  IF (v_bl->>'eligible')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'ACCOUNT_CLOSURE_BLOCKED: %', (v_bl->'blockers')::text
      USING ERRCODE = 'P0001';
  END IF;

  SELECT professional_type INTO v_lane FROM public.professional_identities
   WHERE user_id = _target AND claim_state = 'active' FOR UPDATE;
  IF v_lane = 'driver' THEN
    UPDATE public.driver_profiles
       SET status = 'suspended'::public.driver_status,
           presence = 'offline'::public.driver_presence,
           suspended_reason = COALESCE(suspended_reason, 'account_closure'),
           updated_at = now()
     WHERE user_id = _target;
  ELSIF v_lane IS NOT NULL THEN
    UPDATE public.merchant_stores SET status='suspended', updated_at=now()
     WHERE owner_user_id = _target AND status = 'active';
    UPDATE public.food_restaurants SET status='suspended', updated_at=now()
     WHERE owner_user_id = _target AND COALESCE(status,'') = 'active';
  END IF;
  IF v_lane IS NOT NULL THEN
    PERFORM public._professional_identity_release(_target, 'account_closure');
    v_auth := v_auth || jsonb_build_object('professional_lane_released', v_lane);
  END IF;

  UPDATE public.admin_users
     SET status = 'suspended'::public.admin_user_status, updated_at = now()
   WHERE user_id = _target AND status = 'active'::public.admin_user_status;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_auth := v_auth || jsonb_build_object('governance_suspended', v_n);

  DELETE FROM public.user_roles WHERE user_id = _target;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_auth := v_auth || jsonb_build_object('roles_revoked', v_n);

  DELETE FROM public.account_recovery_challenges WHERE user_id = _target;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_auth := v_auth || jsonb_build_object('recovery_challenges_erased', v_n);
  DELETE FROM public.account_recovery_profiles WHERE user_id = _target;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_auth := v_auth || jsonb_build_object('recovery_profiles_erased', v_n);

  UPDATE public.ride_offers SET status='expired'::public.ride_offer_status,
         responded_at = now()
   WHERE driver_id = _target AND status = 'pending'::public.ride_offer_status;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_auth := v_auth || jsonb_build_object('ride_offers_expired', v_n);

  -- NODE 5 finance law: a positive residual balance is preserved, in place,
  -- as dormant closed-account liability on this canonical UUID. No payout.
  v_liab := public._dormant_liability_classify(_target, 'account_closure_' || _mode);
  v_auth := v_auth || jsonb_build_object('dormant_liability', v_liab);

  v_core := public._anonymize_user_core(
              _target,
              CASE WHEN _mode = 'self' THEN 'account_deleted_by_user'
                   ELSE 'admin_anonymized' END);

  PERFORM public._account_access_terminate_enqueue(
            _target, 'closure_' || _mode, _reason);
  v_auth := v_auth || jsonb_build_object('auth_access_termination', 'enqueued');

  INSERT INTO public.audit_logs(actor_user_id, module, action, target_type, target_id,
                                before, after, note)
  VALUES (auth.uid(), 'identity', 'account.closure', 'account', _target::text,
          jsonb_build_object('account_status', v_status, 'lane', COALESCE(v_lane,'none')),
          jsonb_build_object('account_status','deleted','authority', v_auth),
          _reason);

  RETURN jsonb_build_object('ok', true, 'mode', 'anonymized', 'closure_mode', _mode,
                            'user_id', _target, 'authority', v_auth,
                            'steps', v_core->'steps');
END;
$function$;

-- ---------- legacy reconciliation records the dormant liability ----------
CREATE OR REPLACE FUNCTION public.admin_account_closure_reconcile(_target uuid, _reason text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller uuid := auth.uid();
  _role text := COALESCE(
    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    current_user::text);
  v_status text; v_lane text; v_pb jsonb; v_n int;
  v_acts jsonb := '{}'::jsonb;
BEGIN
  IF _target IS NULL THEN RAISE EXCEPTION 'TARGET_REQUIRED'; END IF;
  IF v_caller IS NULL THEN
    IF _role IS DISTINCT FROM 'service_role' THEN
      RAISE EXCEPTION 'NOT_AUTHORIZED' USING ERRCODE='42501'; END IF;
  ELSIF NOT public._is_ops_or_god_admin(v_caller) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED' USING ERRCODE='42501';
  END IF;
  IF v_caller IS NOT NULL AND v_caller = _target THEN
    RAISE EXCEPTION 'SELF_RECONCILE_FORBIDDEN' USING ERRCODE='42501';
  END IF;

  SELECT account_status INTO v_status FROM public.profiles
   WHERE user_id = _target FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ACCOUNT_NOT_FOUND'; END IF;
  IF v_status IS DISTINCT FROM 'deleted' THEN
    RAISE EXCEPTION 'ACCOUNT_NOT_CLOSED' USING ERRCODE='P0001';
  END IF;

  UPDATE public.ride_offers SET status='expired'::public.ride_offer_status,
         responded_at = now()
   WHERE driver_id = _target AND status = 'pending'::public.ride_offer_status;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_acts := v_acts || jsonb_build_object('ride_offers_expired', v_n);

  SELECT professional_type INTO v_lane FROM public.professional_identities
   WHERE user_id = _target AND claim_state = 'active' FOR UPDATE;
  IF v_lane IS NOT NULL THEN
    v_pb := public.professional_offboard_blockers(_target);
    IF (v_pb->>'eligible')::boolean IS NOT TRUE THEN
      RAISE EXCEPTION 'PROFESSIONAL_OFFBOARD_BLOCKED: %', (v_pb->'blockers')::text
        USING ERRCODE='P0001';
    END IF;
    IF v_lane = 'driver' THEN
      UPDATE public.driver_profiles
         SET status = 'suspended'::public.driver_status,
             presence = 'offline'::public.driver_presence,
             suspended_reason = COALESCE(suspended_reason,'account_closure'),
             updated_at = now()
       WHERE user_id = _target;
    ELSE
      UPDATE public.merchant_stores SET status='suspended', updated_at=now()
       WHERE owner_user_id = _target AND status = 'active';
      UPDATE public.food_restaurants SET status='suspended', updated_at=now()
       WHERE owner_user_id = _target AND COALESCE(status,'') = 'active';
    END IF;
    PERFORM public._professional_identity_release(_target, 'account_closure_reconcile');
    v_acts := v_acts || jsonb_build_object('professional_lane_released', v_lane);
  ELSE
    v_acts := v_acts || jsonb_build_object('professional_lane_released', 'none');
  END IF;

  UPDATE public.driver_profiles
     SET presence = 'offline'::public.driver_presence, updated_at = now()
   WHERE user_id = _target AND presence <> 'offline'::public.driver_presence;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_acts := v_acts || jsonb_build_object('presence_forced_offline', v_n);

  UPDATE public.admin_users
     SET status = 'suspended'::public.admin_user_status, updated_at = now()
   WHERE user_id = _target AND status = 'active'::public.admin_user_status;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_acts := v_acts || jsonb_build_object('governance_suspended', v_n);

  DELETE FROM public.user_roles WHERE user_id = _target;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_acts := v_acts || jsonb_build_object('roles_revoked', v_n);

  DELETE FROM public.account_recovery_challenges WHERE user_id = _target;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_acts := v_acts || jsonb_build_object('recovery_challenges_erased', v_n);
  DELETE FROM public.account_recovery_profiles WHERE user_id = _target;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_acts := v_acts || jsonb_build_object('recovery_profiles_erased', v_n);

  -- NODE 5 finance law: preserve any residual positive balance in place as
  -- dormant closed-account liability. Never paid, swept, or written off here.
  v_acts := v_acts || jsonb_build_object('dormant_liability',
              public._dormant_liability_classify(_target, 'account_closure_reconcile'));

  PERFORM public._account_access_terminate_enqueue(
            _target, 'closure_reconcile', _reason);
  v_acts := v_acts || jsonb_build_object('auth_access_termination','enqueued');

  INSERT INTO public.audit_logs(actor_user_id, module, action, target_type, target_id,
                                before, after, note)
  VALUES (v_caller, 'identity', 'account.closure_reconcile', 'account', _target::text,
          jsonb_build_object('account_status', v_status, 'lane', COALESCE(v_lane,'none')),
          jsonb_build_object('account_status','deleted','authority', v_acts),
          _reason);

  RETURN jsonb_build_object('ok', true, 'user_id', _target,
                            'reconciled', true, 'authority', v_acts);
END;
$function$;
