-- ============================================================
-- NODE 5 · A14 — ACCOUNT CLOSURE / DELETION / ANONYMIZATION /
-- RE-REGISTRATION INTEGRITY  (remediation)
-- ============================================================

-- ---------- 1. BLOCKER ENGINE (internal, no authz) ----------
CREATE OR REPLACE FUNCTION public._account_closure_blockers(_user uuid, _mode text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  b jsonb := '[]'::jsonb;
  v_lane text;
  v_pb jsonb;
BEGIN
  IF _user IS NULL THEN RAISE EXCEPTION 'TARGET_REQUIRED'; END IF;

  -- ---- money held by / owed to the canonical account ----
  IF EXISTS (SELECT 1 FROM public.wallets
              WHERE owner_user_id = _user AND COALESCE(balance_gnf,0) <> 0)
    THEN b := b || '"WALLET_BALANCE_NONZERO"'::jsonb; END IF;

  IF EXISTS (SELECT 1 FROM public.wallets
              WHERE owner_user_id = _user AND COALESCE(held_gnf,0) > 0)
    THEN b := b || '"WALLET_FUNDS_HELD"'::jsonb; END IF;

  IF EXISTS (SELECT 1 FROM public.mission_financial_holds
              WHERE (driver_user_id = _user OR party_user_id = _user)
                AND state IN ('held','partially_captured','frozen'))
    THEN b := b || '"OPEN_FINANCIAL_HOLD"'::jsonb; END IF;

  IF EXISTS (SELECT 1 FROM public.customer_cancellation_debts
              WHERE customer_user_id = _user AND state = 'outstanding')
    THEN b := b || '"CUSTOMER_CANCELLATION_DEBT"'::jsonb; END IF;

  IF EXISTS (SELECT 1 FROM public.topup_requests
              WHERE (client_user_id = _user OR agent_user_id = _user)
                AND status IN ('pending','matched','needs_review'))
    THEN b := b || '"PENDING_TOPUP"'::jsonb; END IF;

  -- ---- driver-side finance ----
  IF EXISTS (SELECT 1 FROM public.driver_profiles
              WHERE user_id = _user AND COALESCE(cash_debt_gnf,0) > 0)
    THEN b := b || '"DRIVER_CASH_DEBT_OUTSTANDING"'::jsonb; END IF;

  IF EXISTS (SELECT 1 FROM public.driver_cashout_requests
              WHERE driver_user_id = _user AND status IN ('pending','approved'))
    THEN b := b || '"DRIVER_CASHOUT_IN_FLIGHT"'::jsonb; END IF;

  -- ---- merchant-side finance ----
  IF EXISTS (SELECT 1 FROM public.merchant_payables
              WHERE merchant_user_id = _user
                AND state IN ('pending_funding','funded','due','settlement_held','disputed'))
    THEN b := b || '"MERCHANT_UNSETTLED_PAYABLE"'::jsonb; END IF;

  IF EXISTS (SELECT 1 FROM public.merchant_settlement_requests
              WHERE merchant_user_id = _user AND status IN ('requested','pending_review'))
    THEN b := b || '"MERCHANT_SETTLEMENT_IN_FLIGHT"'::jsonb; END IF;

  -- ---- in-flight operations that existing law requires finished ----
  IF EXISTS (SELECT 1 FROM public.rides
              WHERE (client_id = _user OR driver_id = _user)
                AND status IN ('pending','in_progress'))
    THEN b := b || '"ACTIVE_RIDE"'::jsonb; END IF;

  IF EXISTS (SELECT 1 FROM public.missions
              WHERE (courier_id = _user OR customer_id = _user OR merchant_id = _user)
                AND state NOT IN ('delivered','failed'))
    THEN b := b || '"ACTIVE_MISSION"'::jsonb; END IF;

  IF EXISTS (SELECT 1 FROM public.food_orders
              WHERE user_id = _user AND state NOT IN ('completed','cancelled'))
    THEN b := b || '"ACTIVE_FOOD_ORDER"'::jsonb; END IF;

  IF EXISTS (SELECT 1 FROM public.marche_orders
              WHERE (buyer_user_id = _user OR merchant_user_id = _user)
                AND status = 'committed'
                AND fulfillment_state NOT IN ('delivered','rejected','cancelled'))
    THEN b := b || '"ACTIVE_MARCHE_ORDER"'::jsonb; END IF;

  IF EXISTS (SELECT 1 FROM public.package_deliveries
              WHERE sender_user_id = _user
                AND COALESCE(package_status,'') NOT IN ('delivered','cancelled','failed'))
    THEN b := b || '"ACTIVE_PACKAGE_DELIVERY"'::jsonb; END IF;

  -- ---- legal / ops holds ----
  IF EXISTS (SELECT 1 FROM public.account_freezes
              WHERE user_id = _user AND status = 'active')
    THEN b := b || '"ACCOUNT_FREEZE_ACTIVE"'::jsonb; END IF;

  IF EXISTS (SELECT 1 FROM public.support_issues
              WHERE (reporter_user_id = _user OR related_driver_id = _user
                     OR related_customer_id = _user)
                AND status NOT IN ('resolved','cancelled'))
    THEN b := b || '"OPEN_SUPPORT_ISSUE"'::jsonb; END IF;

  -- ---- professional lane: reuse the certified A12 blocker contract ----
  SELECT professional_type INTO v_lane
    FROM public.professional_identities
   WHERE user_id = _user AND claim_state = 'active';
  IF v_lane IS NOT NULL THEN
    v_pb := public.professional_offboard_blockers(_user);
    b := b || COALESCE(v_pb->'blockers','[]'::jsonb);
  END IF;

  -- ---- governance axis: a staff account can never self-close ----
  IF _mode = 'self' AND EXISTS (SELECT 1 FROM public.admin_users
                                 WHERE user_id = _user AND status = 'active')
    THEN b := b || '"GOVERNANCE_AUTHORITY_ACTIVE"'::jsonb; END IF;

  -- dedupe, stable order
  SELECT COALESCE(jsonb_agg(DISTINCT x ORDER BY x),'[]'::jsonb) INTO b
    FROM jsonb_array_elements_text(b) x;

  RETURN jsonb_build_object(
    'user_id', _user,
    'mode', _mode,
    'lane', COALESCE(v_lane,'none'),
    'blockers', b,
    'eligible', (jsonb_array_length(b) = 0));
END;
$fn$;

REVOKE ALL ON FUNCTION public._account_closure_blockers(uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._account_closure_blockers(uuid,text) TO service_role;

-- ---------- 2. GOVERNANCE / SELF READ SURFACE ----------
CREATE OR REPLACE FUNCTION public.account_closure_blockers(_user uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_caller uuid := auth.uid();
  v_target uuid := COALESCE(_user, auth.uid());
  v_mode text;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF v_target = v_caller THEN
    v_mode := 'self';
  ELSIF public._is_ops_or_god_admin(v_caller) THEN
    v_mode := 'admin';
  ELSE
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  RETURN public._account_closure_blockers(v_target, v_mode);
END;
$fn$;

REVOKE ALL ON FUNCTION public.account_closure_blockers(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.account_closure_blockers(uuid) TO authenticated, service_role;

-- ---------- 3. CLOSURE CORE (authority stand-down + PII release) ----------
CREATE OR REPLACE FUNCTION public._account_closure_core(_target uuid, _mode text, _reason text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_bl jsonb;
  v_lane text;
  v_core jsonb;
  v_status text;
  v_n int;
  v_auth jsonb := '{}'::jsonb;
BEGIN
  IF _target IS NULL THEN RAISE EXCEPTION 'TARGET_REQUIRED'; END IF;

  SELECT account_status INTO v_status FROM public.profiles
   WHERE user_id = _target FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ACCOUNT_NOT_FOUND'; END IF;
  IF v_status = 'deleted' THEN RAISE EXCEPTION 'ACCOUNT_ALREADY_CLOSED'; END IF;

  -- FAIL CLOSED: nothing has been mutated at this point.
  v_bl := public._account_closure_blockers(_target, _mode);
  IF (v_bl->>'eligible')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'ACCOUNT_CLOSURE_BLOCKED: %', (v_bl->'blockers')::text
      USING ERRCODE = 'P0001';
  END IF;

  -- ---- A. present PROFESSIONAL authority stand-down (A12 sequencing) ----
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
    UPDATE public.merchant_stores SET status='suspended', is_active=false, updated_at=now()
     WHERE owner_user_id = _target AND status = 'active';
    UPDATE public.food_restaurants SET status='suspended', updated_at=now()
     WHERE owner_user_id = _target AND COALESCE(status,'') = 'active';
  END IF;
  IF v_lane IS NOT NULL THEN
    PERFORM public._professional_identity_release(_target, 'account_closure');
    v_auth := v_auth || jsonb_build_object('professional_lane_released', v_lane);
  END IF;

  -- ---- B. present GOVERNANCE authority stand-down (row kept as provenance) ----
  UPDATE public.admin_users
     SET status = 'suspended'::public.admin_user_status, updated_at = now()
   WHERE user_id = _target AND status = 'active'::public.admin_user_status;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_auth := v_auth || jsonb_build_object('governance_suspended', v_n);

  -- ---- C. capability roles are present authority, not history ----
  DELETE FROM public.user_roles WHERE user_id = _target;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_auth := v_auth || jsonb_build_object('roles_revoked', v_n);

  -- ---- D. private recovery material is PII and must not survive closure ----
  DELETE FROM public.account_recovery_challenges WHERE user_id = _target;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_auth := v_auth || jsonb_build_object('recovery_challenges_erased', v_n);
  DELETE FROM public.account_recovery_profiles WHERE user_id = _target;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_auth := v_auth || jsonb_build_object('recovery_profiles_erased', v_n);

  -- ---- E. PII release via the already-canonical anonymization core ----
  v_core := public._anonymize_user_core(
              _target,
              CASE WHEN _mode = 'self' THEN 'account_deleted_by_user'
                   ELSE 'admin_anonymized' END);

  -- ---- F. audit provenance ----
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
$fn$;

REVOKE ALL ON FUNCTION public._account_closure_core(uuid,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._account_closure_core(uuid,text,text) TO service_role;

-- ---------- 4. SELF-CLOSURE ENTRYPOINT (hardened, same signature) ----------
CREATE OR REPLACE FUNCTION public.request_account_deletion(_reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE _uid uuid := auth.uid(); v_res jsonb;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  v_res := public._account_closure_core(_uid, 'self', _reason);
  INSERT INTO public.account_deletion_requests(user_id, requested_by, request_type,
                                               status, reason, processed_by, processed_at)
  VALUES (_uid, _uid, 'self_delete', 'processed', _reason, _uid, now());
  RETURN v_res;
END;
$fn$;

REVOKE ALL ON FUNCTION public.request_account_deletion(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_account_deletion(text) TO authenticated, service_role;

-- ---------- 5. ADMIN CLOSURE ENTRYPOINT (hardened, same contract) ----------
CREATE OR REPLACE FUNCTION public.admin_anonymize_user(_target uuid, _reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  _caller uuid := auth.uid();
  _role text := COALESCE(
    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    current_user::text);
  v_res jsonb; v_bl jsonb; v_err text; v_state text;
BEGIN
  IF _caller IS NULL THEN
    IF _role IS DISTINCT FROM 'service_role' THEN
      RAISE EXCEPTION 'forbidden' USING ERRCODE='42501';
    END IF;
  ELSIF NOT (public.has_admin_role(_caller,'god_admin'::admin_role)
             OR public.has_admin_role(_caller,'super_admin'::admin_role)) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE='42501';
  END IF;

  v_bl := public._account_closure_blockers(_target, 'admin');
  IF (v_bl->>'eligible')::boolean IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'mode', 'anonymized',
                              'error', 'ACCOUNT_CLOSURE_BLOCKED',
                              'blockers', v_bl->'blockers');
  END IF;

  BEGIN
    v_res := public._account_closure_core(_target, 'admin', _reason);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT, v_state = RETURNED_SQLSTATE;
    RETURN jsonb_build_object('ok',false,'mode','anonymized','sqlstate',v_state,'detail',v_err);
  END;

  BEGIN
    INSERT INTO public.account_deletion_requests(user_id, requested_by, request_type, status,
                                                 reason, processed_by, processed_at)
    VALUES (_target,_caller,'admin_anonymize','processed',_reason,_caller, now());
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT, v_state = RETURNED_SQLSTATE;
    v_res := v_res || jsonb_build_object('audit_warning',
               jsonb_build_object('sqlstate',v_state,'error',v_err));
  END;

  RETURN jsonb_build_object('ok', true, 'mode', 'anonymized',
                            'authority', v_res->'authority', 'steps', v_res->'steps');
END;
$fn$;

REVOKE ALL ON FUNCTION public.admin_anonymize_user(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_anonymize_user(uuid,text) TO authenticated, service_role;

-- ---------- 6. HARD-DELETE GATE: widen the evidence definition ----------
CREATE OR REPLACE FUNCTION public.user_has_financial_history(_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
  SELECT
    EXISTS (SELECT 1 FROM public.wallet_transactions WHERE related_user_id = _user_id)
    OR EXISTS (SELECT 1 FROM public.wallets WHERE owner_user_id = _user_id)
    OR EXISTS (SELECT 1 FROM public.topup_requests WHERE client_user_id = _user_id OR agent_user_id = _user_id)
    OR EXISTS (SELECT 1 FROM public.payment_intents WHERE user_id = _user_id)
    OR EXISTS (SELECT 1 FROM public.rides WHERE client_id = _user_id OR driver_id = _user_id)
    OR EXISTS (SELECT 1 FROM public.food_orders WHERE user_id = _user_id)
    -- A14: provenance that must survive closure and therefore forbids hard delete
    OR EXISTS (SELECT 1 FROM public.driver_cashout_requests WHERE driver_user_id = _user_id)
    OR EXISTS (SELECT 1 FROM public.merchant_payables WHERE merchant_user_id = _user_id)
    OR EXISTS (SELECT 1 FROM public.merchant_settlement_requests WHERE merchant_user_id = _user_id)
    OR EXISTS (SELECT 1 FROM public.mission_financial_holds
                WHERE driver_user_id = _user_id OR party_user_id = _user_id)
    OR EXISTS (SELECT 1 FROM public.customer_cancellation_debts WHERE customer_user_id = _user_id)
    OR EXISTS (SELECT 1 FROM public.marche_orders
                WHERE buyer_user_id = _user_id OR merchant_user_id = _user_id)
    OR EXISTS (SELECT 1 FROM public.package_deliveries WHERE sender_user_id = _user_id)
    OR EXISTS (SELECT 1 FROM public.missions
                WHERE courier_id = _user_id OR customer_id = _user_id OR merchant_id = _user_id)
    OR EXISTS (SELECT 1 FROM public.professional_identities WHERE user_id = _user_id)
    OR EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = _user_id)
    OR EXISTS (SELECT 1 FROM public.merchant_stores WHERE owner_user_id = _user_id)
    OR EXISTS (SELECT 1 FROM public.account_freezes WHERE user_id = _user_id)
    OR EXISTS (SELECT 1 FROM public.field_daily_reports WHERE user_id = _user_id)
    OR EXISTS (SELECT 1 FROM public.field_merchant_visits WHERE assigned_user_id = _user_id);
$fn$;

REVOKE ALL ON FUNCTION public.user_has_financial_history(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.user_has_financial_history(uuid) TO authenticated, service_role;

-- ---------- 7. HARD-DELETE SAFETY: stop silent provenance cascades ----------
ALTER TABLE public.driver_cashout_requests
  DROP CONSTRAINT IF EXISTS driver_cashout_requests_driver_user_id_fkey;
ALTER TABLE public.driver_cashout_requests
  ADD CONSTRAINT driver_cashout_requests_driver_user_id_fkey
  FOREIGN KEY (driver_user_id) REFERENCES auth.users(id) ON DELETE RESTRICT;

ALTER TABLE public.professional_identities
  DROP CONSTRAINT IF EXISTS professional_identities_user_id_fkey;
ALTER TABLE public.professional_identities
  ADD CONSTRAINT professional_identities_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE RESTRICT;

ALTER TABLE public.account_freezes
  DROP CONSTRAINT IF EXISTS account_freezes_user_id_fkey;
ALTER TABLE public.account_freezes
  ADD CONSTRAINT account_freezes_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE RESTRICT;

ALTER TABLE public.field_daily_reports
  DROP CONSTRAINT IF EXISTS field_daily_reports_user_id_fkey;
ALTER TABLE public.field_daily_reports
  ADD CONSTRAINT field_daily_reports_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE RESTRICT;

ALTER TABLE public.field_merchant_visits
  DROP CONSTRAINT IF EXISTS field_merchant_visits_assigned_user_id_fkey;
ALTER TABLE public.field_merchant_visits
  ADD CONSTRAINT field_merchant_visits_assigned_user_id_fkey
  FOREIGN KEY (assigned_user_id) REFERENCES auth.users(id) ON DELETE RESTRICT;

-- ---------- 8. keep disposable QA fixtures purgeable under RESTRICT ----------
CREATE OR REPLACE FUNCTION public._qa_users_purge(p_ids uuid[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET statement_timeout = '60s'
AS $fn$
BEGIN
  DELETE FROM public.field_merchant_visits WHERE assigned_user_id = ANY(p_ids);
  DELETE FROM public.field_daily_reports   WHERE user_id = ANY(p_ids);
  DELETE FROM public.account_freezes       WHERE user_id = ANY(p_ids);
  DELETE FROM public.driver_cashout_requests WHERE driver_user_id = ANY(p_ids);
  DELETE FROM public.professional_identities WHERE user_id = ANY(p_ids);
  DELETE FROM auth.users WHERE id = ANY(p_ids);
  -- profiles.id is an independent PK; the auth-user link lives in profiles.user_id.
  DELETE FROM public.profiles p
   WHERE (p.id = ANY(p_ids) OR p.user_id = ANY(p_ids))
     AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = p.id OR u.id = p.user_id);
END;
$fn$;
