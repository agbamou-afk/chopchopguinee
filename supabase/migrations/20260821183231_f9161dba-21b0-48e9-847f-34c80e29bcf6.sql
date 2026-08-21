-- =====================================================================
-- NODE 5 · A12 — IDENTITY DEACTIVATION / OFFBOARDING INTEGRITY
-- =====================================================================

-- ---------------------------------------------------------------
-- 1. GOVERNANCE AXIS: status lifecycle (audited)
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_governance_set_status(
  _target uuid, _status text, _reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_caller uuid := auth.uid();
  v_before public.admin_users;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF NOT public._is_god_admin(v_caller) THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  IF _status IS NULL OR _status NOT IN ('active','suspended') THEN
    RAISE EXCEPTION 'GOVERNANCE_STATUS_INVALID';
  END IF;
  IF _target = v_caller AND _status = 'suspended' THEN
    RAISE EXCEPTION 'CANNOT_SUSPEND_SELF';
  END IF;

  SELECT * INTO v_before FROM public.admin_users WHERE user_id = _target FOR UPDATE;
  IF v_before.user_id IS NULL THEN RAISE EXCEPTION 'GOVERNANCE_ACCOUNT_NOT_FOUND'; END IF;

  UPDATE public.admin_users
     SET status = _status::public.admin_user_status, updated_at = now()
   WHERE user_id = _target;

  INSERT INTO public.audit_logs(actor_user_id, module, action, target_type, target_id, before, after, note)
  VALUES (v_caller, 'identity', 'governance.set_status', 'admin_user', _target::text,
          jsonb_build_object('status', v_before.status),
          jsonb_build_object('status', _status), _reason);

  RETURN jsonb_build_object('user_id', _target, 'status', _status,
                            'previous_status', v_before.status, 'reason', _reason);
END $fn$;

-- ---------------------------------------------------------------
-- 2. GOVERNANCE AXIS: staff role grant / revoke (audited)
--    Professional roles are NEVER governance and are refused here.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._governance_role_allowed(_role text)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path TO 'public'
AS $fn$
  SELECT _role IN ('admin','operations_admin','finance_admin','god_admin',
                   'agent','recharge_agent','onboarding_specialist',
                   'field_captain','field_agent');
$fn$;

CREATE OR REPLACE FUNCTION public.admin_staff_role_grant(
  _target uuid, _role text, _reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE v_caller uuid := auth.uid(); v_n int;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF NOT public._is_god_admin(v_caller) THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  IF _target IS NULL THEN RAISE EXCEPTION 'TARGET_REQUIRED'; END IF;
  IF NOT public._governance_role_allowed(_role) THEN
    RAISE EXCEPTION 'PROFESSIONAL_ROLE_NOT_GOVERNANCE';
  END IF;

  INSERT INTO public.user_roles(user_id, role)
  VALUES (_target, _role::public.app_role)
  ON CONFLICT (user_id, role) DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;

  INSERT INTO public.audit_logs(actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (v_caller, 'identity', 'governance.role_grant', 'user_role', _target::text,
          jsonb_build_object('role', _role, 'inserted', v_n), _reason);

  RETURN jsonb_build_object('user_id', _target, 'role', _role, 'granted', true, 'inserted', v_n);
END $fn$;

CREATE OR REPLACE FUNCTION public.admin_staff_role_revoke(
  _target uuid, _role text, _reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE v_caller uuid := auth.uid(); v_n int;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF NOT public._is_god_admin(v_caller) THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  IF _target IS NULL THEN RAISE EXCEPTION 'TARGET_REQUIRED'; END IF;
  IF NOT public._governance_role_allowed(_role) THEN
    RAISE EXCEPTION 'PROFESSIONAL_ROLE_NOT_GOVERNANCE';
  END IF;

  DELETE FROM public.user_roles WHERE user_id = _target AND role = _role::public.app_role;
  GET DIAGNOSTICS v_n = ROW_COUNT;

  INSERT INTO public.audit_logs(actor_user_id, module, action, target_type, target_id, before, note)
  VALUES (v_caller, 'identity', 'governance.role_revoke', 'user_role', _target::text,
          jsonb_build_object('role', _role, 'removed', v_n), _reason);

  RETURN jsonb_build_object('user_id', _target, 'role', _role, 'revoked', true, 'removed', v_n);
END $fn$;

-- ---------------------------------------------------------------
-- 3. PROFESSIONAL AXIS: finance-safe offboarding blockers
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.professional_offboard_blockers(_user uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE v_lane text; v_b jsonb := '[]'::jsonb;
BEGIN
  SELECT professional_type INTO v_lane FROM public.professional_identities
   WHERE user_id = _user AND claim_state = 'active';
  IF v_lane IS NULL THEN
    RETURN jsonb_build_object('lane','none','blockers', jsonb_build_array('NO_ACTIVE_PROFESSIONAL_LANE'));
  END IF;

  IF v_lane = 'driver' THEN
    IF EXISTS (SELECT 1 FROM public.mission_financial_holds
                WHERE driver_user_id = _user AND state IN ('held','partially_captured','frozen'))
      THEN v_b := v_b || '"DRIVER_OPEN_FINANCIAL_HOLD"'::jsonb; END IF;
    IF EXISTS (SELECT 1 FROM public.driver_profiles
                WHERE user_id = _user AND COALESCE(cash_debt_gnf,0) > 0)
      THEN v_b := v_b || '"DRIVER_CASH_DEBT_OUTSTANDING"'::jsonb; END IF;
  ELSE
    IF EXISTS (SELECT 1 FROM public.merchant_payables
                WHERE merchant_user_id = _user
                  AND state IN ('pending_funding','funded','due','settlement_held','disputed'))
      THEN v_b := v_b || '"MERCHANT_UNSETTLED_PAYABLE"'::jsonb; END IF;
    IF EXISTS (SELECT 1 FROM public.merchant_settlement_requests
                WHERE merchant_user_id = _user AND status IN ('requested','pending_review'))
      THEN v_b := v_b || '"MERCHANT_SETTLEMENT_IN_FLIGHT"'::jsonb; END IF;
    IF EXISTS (SELECT 1 FROM public.mission_financial_holds h
                JOIN public.merchant_stores s ON s.id = h.merchant_store_id
               WHERE s.owner_user_id = _user AND h.state IN ('held','partially_captured','frozen'))
      THEN v_b := v_b || '"MERCHANT_OPEN_FINANCIAL_HOLD"'::jsonb; END IF;
  END IF;

  RETURN jsonb_build_object('lane', v_lane, 'blockers', v_b,
                            'eligible', (jsonb_array_length(v_b) = 0));
END $fn$;

-- ---------------------------------------------------------------
-- 4. PROFESSIONAL AXIS: admin offboarding (non-destructive)
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_professional_offboard(
  _target uuid, _reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_caller uuid := auth.uid();
  v_lane text; v_bl jsonb; v_arts jsonb := '{}'::jsonb; v_n int;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF NOT public._is_ops_or_god_admin(v_caller) THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;

  SELECT professional_type INTO v_lane FROM public.professional_identities
   WHERE user_id = _target AND claim_state = 'active' FOR UPDATE;
  IF v_lane IS NULL THEN RAISE EXCEPTION 'NO_ACTIVE_PROFESSIONAL_LANE'; END IF;

  v_bl := public.professional_offboard_blockers(_target);
  IF (v_bl->>'eligible')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'PROFESSIONAL_OFFBOARD_BLOCKED: %', (v_bl->'blockers')::text;
  END IF;

  IF v_lane = 'driver' THEN
    UPDATE public.driver_profiles
       SET status = 'suspended'::public.driver_status,
           presence = 'offline'::public.driver_presence,
           suspended_reason = COALESCE(_reason,'admin_offboard'),
           updated_at = now()
     WHERE user_id = _target AND status <> 'suspended'::public.driver_status;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_arts := v_arts || jsonb_build_object('driver_profiles', v_n);
  ELSE
    UPDATE public.merchant_stores
       SET status = 'suspended', updated_at = now()
     WHERE owner_user_id = _target AND status = 'active';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_arts := v_arts || jsonb_build_object('merchant_stores', v_n);

    UPDATE public.food_restaurants
       SET status = 'suspended', updated_at = now()
     WHERE owner_user_id = _target AND COALESCE(status,'') = 'active';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_arts := v_arts || jsonb_build_object('food_restaurants', v_n);
  END IF;

  PERFORM public._professional_identity_release(
    _target, COALESCE(_reason, 'admin_offboard'));

  INSERT INTO public.audit_logs(actor_user_id, module, action, target_type, target_id, before, after, note)
  VALUES (v_caller, 'identity', 'professional_identity.admin_offboard',
          'professional_identity', _target::text,
          jsonb_build_object('lane', v_lane, 'claim_state','active'),
          jsonb_build_object('lane', v_lane, 'claim_state','released', 'artifacts', v_arts), _reason);

  RETURN jsonb_build_object('offboarded', true, 'user_id', _target,
                            'lane', v_lane, 'artifacts', v_arts, 'reason', _reason);
END $fn$;

-- ---------------------------------------------------------------
-- 5. PROFESSIONAL AXIS: explicit restoration (never automatic)
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_professional_restore(
  _target uuid, _type text DEFAULT NULL, _reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_caller uuid := auth.uid();
  v_lane text;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF NOT public._is_ops_or_god_admin(v_caller) THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;

  IF EXISTS (SELECT 1 FROM public.professional_identities
              WHERE user_id = _target AND claim_state = 'active') THEN
    RAISE EXCEPTION 'PROFESSIONAL_LANE_ALREADY_ACTIVE';
  END IF;

  v_lane := _type;
  IF v_lane IS NULL THEN
    SELECT professional_type INTO v_lane FROM public.professional_identities
     WHERE user_id = _target AND claim_state = 'released'
     ORDER BY released_at DESC LIMIT 1;
  END IF;
  IF v_lane IS NULL THEN RAISE EXCEPTION 'NO_RELEASED_PROFESSIONAL_LANE'; END IF;
  IF v_lane NOT IN ('driver','merchant') THEN
    RAISE EXCEPTION 'PROFESSIONAL_IDENTITY_TYPE_INVALID';
  END IF;

  PERFORM public._professional_identity_claim(_target, v_lane, 'admin_restore');

  INSERT INTO public.audit_logs(actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (v_caller, 'identity', 'professional_identity.admin_restore',
          'professional_identity', _target::text,
          jsonb_build_object('lane', v_lane, 'claim_state','active'), _reason);

  -- Approval / store activation deliberately NOT restored here: each remains an
  -- explicit, independently audited governance decision (Node 5 A12 law 8).
  RETURN jsonb_build_object('restored', true, 'user_id', _target,
                            'lane', v_lane,
                            'operational_authority_restored', false,
                            'reason', _reason);
END $fn$;

REVOKE ALL ON FUNCTION public.admin_governance_set_status(uuid,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_staff_role_grant(uuid,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_staff_role_revoke(uuid,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_professional_offboard(uuid,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_professional_restore(uuid,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.professional_offboard_blockers(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public._governance_role_allowed(text) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.admin_governance_set_status(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_staff_role_grant(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_staff_role_revoke(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_professional_offboard(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_professional_restore(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.professional_offboard_blockers(uuid) TO authenticated;