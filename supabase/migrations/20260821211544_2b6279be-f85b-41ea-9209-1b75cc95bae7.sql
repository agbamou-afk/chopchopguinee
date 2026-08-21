
-- =====================================================================
-- NODE 5 · FINAL REMEDIATION
-- (1) closure-bound auth access termination queue
-- (2) server-side deleted-account authority gate
-- (3) governed legacy already-deleted reconciliation
-- No new identity subsystem: everything reuses A12/A14 primitives.
-- =====================================================================

-- ---------------------------------------------------------------
-- 1. Canonical "is this caller a live account" gate.
--    Returns auth.uid() only while the canonical profile is not closed.
--    account_status stays the PRODUCT truth; this is pure access law.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.auth_uid_active()
RETURNS uuid
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT CASE
    WHEN auth.uid() IS NULL THEN NULL
    WHEN EXISTS (SELECT 1 FROM public.profiles p
                  WHERE p.user_id = auth.uid()
                    AND p.account_status = 'deleted') THEN NULL
    ELSE auth.uid()
  END;
$$;

REVOKE ALL ON FUNCTION public.auth_uid_active() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.auth_uid_active() TO authenticated, service_role;

-- ---------------------------------------------------------------
-- 2. Apply the gate to customer-axis ownership policies.
--    Profile SELECT stays ungated on purpose: the client must still be
--    able to read its own closed row to drive sign-out. It carries no
--    authority and no PII after anonymization.
-- ---------------------------------------------------------------
DROP POLICY IF EXISTS "Users view own wallets" ON public.wallets;
CREATE POLICY "Users view own wallets" ON public.wallets
  FOR SELECT TO authenticated
  USING (owner_user_id = public.auth_uid_active());

DROP POLICY IF EXISTS "Users view own transactions" ON public.wallet_transactions;
CREATE POLICY "Users view own transactions" ON public.wallet_transactions
  FOR SELECT TO authenticated
  USING (
    related_user_id = public.auth_uid_active()
    OR EXISTS (SELECT 1 FROM public.wallets w
                WHERE w.id = wallet_transactions.from_wallet_id
                  AND w.owner_user_id = public.auth_uid_active())
    OR EXISTS (SELECT 1 FROM public.wallets w
                WHERE w.id = wallet_transactions.to_wallet_id
                  AND w.owner_user_id = public.auth_uid_active())
  );

DROP POLICY IF EXISTS "Clients view own rides" ON public.rides;
CREATE POLICY "Clients view own rides" ON public.rides
  FOR SELECT USING (client_id = public.auth_uid_active());

DROP POLICY IF EXISTS "Drivers view assigned rides" ON public.rides;
CREATE POLICY "Drivers view assigned rides" ON public.rides
  FOR SELECT USING (driver_id = public.auth_uid_active());

DROP POLICY IF EXISTS "Courier reads own missions" ON public.missions;
CREATE POLICY "Courier reads own missions" ON public.missions
  FOR SELECT USING (courier_id = public.auth_uid_active());

DROP POLICY IF EXISTS "Customer reads own missions" ON public.missions;
CREATE POLICY "Customer reads own missions" ON public.missions
  FOR SELECT USING (customer_id = public.auth_uid_active());

DROP POLICY IF EXISTS "Merchant reads own missions" ON public.missions;
CREATE POLICY "Merchant reads own missions" ON public.missions
  FOR SELECT USING (merchant_id = public.auth_uid_active());

DROP POLICY IF EXISTS "Customer creates own mission" ON public.missions;
CREATE POLICY "Customer creates own mission" ON public.missions
  FOR INSERT TO authenticated
  WITH CHECK (customer_id = public.auth_uid_active());

DROP POLICY IF EXISTS "Eligible couriers read available missions" ON public.missions;
CREATE POLICY "Eligible couriers read available missions" ON public.missions
  FOR SELECT USING (
    courier_id IS NULL
    AND state = 'assigned'::public.mission_state
    AND public.auth_uid_active() IS NOT NULL
    AND public.driver_has_capability(public.auth_uid_active(),
          public.mission_required_capability(type))
  );

DROP POLICY IF EXISTS "Users can view their own roles" ON public.user_roles;
CREATE POLICY "Users can view their own roles" ON public.user_roles
  FOR SELECT TO authenticated
  USING (user_id = public.auth_uid_active());

DROP POLICY IF EXISTS "Users update own profile" ON public.profiles;
CREATE POLICY "Users update own profile" ON public.profiles
  FOR UPDATE TO authenticated
  USING (user_id = public.auth_uid_active());

DROP POLICY IF EXISTS "Users insert own profile" ON public.profiles;
CREATE POLICY "Users insert own profile" ON public.profiles
  FOR INSERT TO authenticated
  WITH CHECK (user_id = public.auth_uid_active());

-- ---------------------------------------------------------------
-- 3. Closure-bound auth access termination queue.
--    SQL may never touch the auth schema, so the canonical closure path
--    ENQUEUES the termination and a service-role worker performs the
--    Supabase auth disable + session/refresh revocation.
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.account_access_terminations (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL,
  status       text NOT NULL DEFAULT 'pending',
  source       text NOT NULL,
  reason       text,
  requested_at timestamptz NOT NULL DEFAULT now(),
  terminated_at timestamptz,
  last_error   text,
  attempts     int NOT NULL DEFAULT 0,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT account_access_terminations_status_chk
    CHECK (status IN ('pending','terminated','failed')),
  CONSTRAINT account_access_terminations_user_uniq UNIQUE (user_id)
);

GRANT SELECT ON public.account_access_terminations TO authenticated;
GRANT ALL    ON public.account_access_terminations TO service_role;

ALTER TABLE public.account_access_terminations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Ops and god admins read access terminations"
  ON public.account_access_terminations
  FOR SELECT TO authenticated
  USING (public._is_ops_or_god_admin(auth.uid()));

CREATE OR REPLACE FUNCTION public._touch_account_access_terminations()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public'
AS $$ BEGIN NEW.updated_at := now(); RETURN NEW; END $$;

DROP TRIGGER IF EXISTS trg_account_access_terminations_touch
  ON public.account_access_terminations;
CREATE TRIGGER trg_account_access_terminations_touch
  BEFORE UPDATE ON public.account_access_terminations
  FOR EACH ROW EXECUTE FUNCTION public._touch_account_access_terminations();

-- internal enqueue primitive (idempotent, re-arms a previously failed row)
CREATE OR REPLACE FUNCTION public._account_access_terminate_enqueue(
  _target uuid, _source text, _reason text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  IF _target IS NULL THEN RAISE EXCEPTION 'TARGET_REQUIRED'; END IF;
  INSERT INTO public.account_access_terminations(user_id, source, reason, status)
  VALUES (_target, _source, _reason, 'pending')
  ON CONFLICT (user_id) DO UPDATE
    SET status = CASE WHEN public.account_access_terminations.status = 'terminated'
                      THEN 'terminated' ELSE 'pending' END,
        source = EXCLUDED.source,
        reason = COALESCE(EXCLUDED.reason, public.account_access_terminations.reason),
        updated_at = now();
END $$;

REVOKE ALL ON FUNCTION public._account_access_terminate_enqueue(uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._account_access_terminate_enqueue(uuid,text,text) TO service_role;

-- worker-facing outcome recorder (service role only)
CREATE OR REPLACE FUNCTION public.account_access_termination_record(
  _target uuid, _ok boolean, _error text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  _role text := COALESCE(
    NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    current_user::text);
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public._is_ops_or_god_admin(auth.uid()) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED' USING ERRCODE='42501';
  END IF;
  IF auth.uid() IS NULL AND _role IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED' USING ERRCODE='42501';
  END IF;

  UPDATE public.account_access_terminations
     SET status        = CASE WHEN _ok THEN 'terminated' ELSE 'failed' END,
         terminated_at = CASE WHEN _ok THEN now() ELSE terminated_at END,
         last_error    = CASE WHEN _ok THEN NULL ELSE _error END,
         attempts      = attempts + 1
   WHERE user_id = _target;

  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'NOT_ENQUEUED'); END IF;
  RETURN jsonb_build_object('ok', true, 'user_id', _target, 'terminated', _ok);
END $$;

REVOKE ALL ON FUNCTION public.account_access_termination_record(uuid,boolean,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.account_access_termination_record(uuid,boolean,text) TO service_role;

-- ---------------------------------------------------------------
-- 4. Every canonical closure now enqueues access termination.
--    (single added step; all other A14 law byte-identical)
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._account_closure_core(_target uuid, _mode text, _reason text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_bl jsonb; v_lane text; v_core jsonb; v_status text; v_n int;
  v_auth jsonb := '{}'::jsonb;
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

  -- stale dispatch residue may never survive closure
  UPDATE public.ride_offers SET status='expired'::public.ride_offer_status,
         responded_at = now()
   WHERE driver_id = _target AND status = 'pending'::public.ride_offer_status;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_auth := v_auth || jsonb_build_object('ride_offers_expired', v_n);

  v_core := public._anonymize_user_core(
              _target,
              CASE WHEN _mode = 'self' THEN 'account_deleted_by_user'
                   ELSE 'admin_anonymized' END);

  -- NEW: closure ends ACCESS, structurally, at the auth layer too.
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

-- ---------------------------------------------------------------
-- 5. Governed reconciliation of accounts closed BEFORE A14 law.
--    Same laws, same primitives, idempotent, no identity reopening.
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_account_closure_reconcile(
  _target uuid, _reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
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

  -- A. stale dispatch residue first: no closed account may be matched
  UPDATE public.ride_offers SET status='expired'::public.ride_offer_status,
         responded_at = now()
   WHERE driver_id = _target AND status = 'pending'::public.ride_offer_status;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_acts := v_acts || jsonb_build_object('ride_offers_expired', v_n);

  -- B. professional authority stand-down (A12 semantics, fail closed on
  --    professional blockers ONLY -- wallet balance never gates authority)
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

  -- residual stale operational posture even without an active lane
  UPDATE public.driver_profiles
     SET presence = 'offline'::public.driver_presence, updated_at = now()
   WHERE user_id = _target AND presence <> 'offline'::public.driver_presence;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_acts := v_acts || jsonb_build_object('presence_forced_offline', v_n);

  -- C. governance authority stand-down (row retained as provenance)
  UPDATE public.admin_users
     SET status = 'suspended'::public.admin_user_status, updated_at = now()
   WHERE user_id = _target AND status = 'active'::public.admin_user_status;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_acts := v_acts || jsonb_build_object('governance_suspended', v_n);

  -- D. capability roles are present authority, not history
  DELETE FROM public.user_roles WHERE user_id = _target;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_acts := v_acts || jsonb_build_object('roles_revoked', v_n);

  -- E. recovery material is PII and may not survive closure
  DELETE FROM public.account_recovery_challenges WHERE user_id = _target;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_acts := v_acts || jsonb_build_object('recovery_challenges_erased', v_n);
  DELETE FROM public.account_recovery_profiles WHERE user_id = _target;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_acts := v_acts || jsonb_build_object('recovery_profiles_erased', v_n);

  -- F. access termination
  PERFORM public._account_access_terminate_enqueue(
            _target, 'closure_reconcile', _reason);
  v_acts := v_acts || jsonb_build_object('auth_access_termination','enqueued');

  -- G. audit provenance
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

REVOKE ALL ON FUNCTION public.admin_account_closure_reconcile(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_account_closure_reconcile(uuid,text)
  TO authenticated, service_role;
