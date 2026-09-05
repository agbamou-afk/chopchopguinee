-- =====================================================================
-- G3 — STAFF ACCOUNT LIFECYCLE / GOVERNED ADMIN IDENTITY OPERATIONS
-- Layered on top of the frozen G2 capability law. No G2 rule weakened.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. LIFECYCLE READINESS (layered condition, not a new capability)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_staff_readiness(_uid uuid DEFAULT auth.uid())
RETURNS text
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT CASE
    WHEN _uid IS NULL THEN 'not_staff'
    WHEN EXISTS (SELECT 1 FROM public.admin_users a
                  WHERE a.user_id = _uid AND a.status = 'active'
                    AND a.must_change_password) THEN 'temp_password_required'
    WHEN EXISTS (SELECT 1 FROM public.admin_users a
                  WHERE a.user_id = _uid AND a.status = 'active') THEN 'ready'
    WHEN EXISTS (SELECT 1 FROM public.admin_users a WHERE a.user_id = _uid) THEN 'inactive'
    ELSE 'ready'
  END;
$$;
REVOKE ALL ON FUNCTION public.admin_staff_readiness(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_staff_readiness(uuid) TO authenticated, service_role;

-- Capability resolution now fails closed while the temporary password stands.
CREATE OR REPLACE FUNCTION public.admin_capability_mode(_capability text, _uid uuid DEFAULT auth.uid())
RETURNS text
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_role text := public.admin_role_canonical(_uid); v_mode text;
BEGIN
  IF v_role IS NULL OR _capability IS NULL THEN RETURN NULL; END IF;
  -- G3 lifecycle readiness: an unfinished temporary-password lifecycle carries
  -- zero effective authority, whatever the capability registry says.
  IF public.admin_staff_readiness(_uid) = 'temp_password_required' THEN RETURN NULL; END IF;
  SELECT g.mode INTO v_mode FROM public.admin_capability_grants g
   WHERE g.capability = _capability AND g.admin_role = v_role;
  RETURN v_mode;
END;
$$;

-- ---------------------------------------------------------------------
-- 2. DURABLE LIFECYCLE SAGA RECORD
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.staff_lifecycle_requests (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  idempotency_key      text NOT NULL UNIQUE,
  action               text NOT NULL CHECK (action IN
                         ('CREATE','DEACTIVATE','REACTIVATE','ROLE_CHANGE','ACCESS_RESET')),
  requester_id         uuid NOT NULL,
  requester_role       text,
  target_key           text NOT NULL,
  target_user_id       uuid,
  target_email_hash    text,
  target_role          text CHECK (target_role IS NULL OR target_role IN ('operations_admin','finance_admin')),
  previous_role        text,
  must_change_password boolean NOT NULL DEFAULT true,
  intent_hash          text NOT NULL,
  approval_id          uuid,
  state                text NOT NULL DEFAULT 'enforced'
                         CHECK (state IN ('enforced','auth_provisioned','completed','failed_final')),
  auth_user_id         uuid,
  outcome              text,
  error_code           text,
  reason               text,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  completed_at         timestamptz
);

GRANT SELECT ON public.staff_lifecycle_requests TO authenticated;
GRANT ALL    ON public.staff_lifecycle_requests TO service_role;
ALTER TABLE public.staff_lifecycle_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "god reads staff lifecycle" ON public.staff_lifecycle_requests;
CREATE POLICY "god reads staff lifecycle" ON public.staff_lifecycle_requests
  FOR SELECT TO authenticated
  USING (COALESCE(public.admin_role_canonical(auth.uid()) = 'god_admin', false));

-- Immutable except through governed lifecycle functions.
CREATE OR REPLACE FUNCTION public._g3_lifecycle_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF COALESCE(NULLIF(current_setting('chopchop.g3_lifecycle', true), ''), 'off') <> 'on' THEN
    RAISE EXCEPTION 'staff_lifecycle_requests is append-only through governed lifecycle functions'
      USING ERRCODE = '42501';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'staff lifecycle records cannot be deleted' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_g3_lifecycle_guard ON public.staff_lifecycle_requests;
CREATE TRIGGER trg_g3_lifecycle_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.staff_lifecycle_requests
  FOR EACH ROW EXECUTE FUNCTION public._g3_lifecycle_guard();

-- ---------------------------------------------------------------------
-- 3. SHARED HELPERS
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._g3_legacy_role(_class text)
RETURNS public.admin_role
LANGUAGE sql IMMUTABLE
AS $$ SELECT CASE _class WHEN 'operations_admin' THEN 'ops_admin'::public.admin_role
                         WHEN 'finance_admin'    THEN 'finance_admin'::public.admin_role END; $$;

CREATE OR REPLACE FUNCTION public._g3_active_god_count(_excluding uuid DEFAULT NULL)
RETURNS integer
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT count(*)::int FROM (
    SELECT user_id FROM public.admin_users WHERE status='active'
     AND admin_role::text IN ('god_admin','super_admin')
    UNION
    SELECT user_id FROM public.user_roles WHERE role::text = 'god_admin'
  ) g
  WHERE (_excluding IS NULL OR g.user_id <> _excluding)
    AND public.admin_role_canonical(g.user_id) = 'god_admin';
$$;

CREATE OR REPLACE FUNCTION public.admin_staff_quorum_status()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_caller uuid := auth.uid(); v_mode text; v_others int;
BEGIN
  IF public.admin_role_canonical(v_caller) IS DISTINCT FROM 'god_admin' THEN
    RAISE EXCEPTION 'capability_denied: governance.staff.manage' USING ERRCODE='42501';
  END IF;
  SELECT g.mode INTO v_mode FROM public.admin_capability_grants g
   WHERE g.capability='governance.staff.manage' AND g.admin_role='god_admin';
  v_others := public._g3_active_god_count(v_caller);
  RETURN jsonb_build_object(
    'capability','governance.staff.manage',
    'mode', v_mode,
    'approval_required', v_mode = 'approval_required',
    'other_active_god_admins', v_others,
    'quorum_available', (v_mode <> 'approval_required') OR v_others > 0);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_staff_quorum_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_staff_quorum_status() TO authenticated, service_role;

-- Sanitised roster for the staff-management surface (God only).
CREATE OR REPLACE FUNCTION public.admin_staff_roster()
RETURNS TABLE (
  user_id uuid, full_name text, phone text,
  canonical_role text, legacy_role text, status text,
  readiness text, must_change_password boolean,
  changed_password_at timestamptz, created_at timestamptz,
  last_action text, last_action_at timestamptz, last_outcome text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF public.admin_role_canonical(auth.uid()) IS DISTINCT FROM 'god_admin' THEN
    RAISE EXCEPTION 'capability_denied: governance.staff.manage' USING ERRCODE='42501';
  END IF;
  RETURN QUERY
  SELECT a.user_id,
         p.full_name,
         p.phone,
         public.admin_role_canonical(a.user_id),
         a.admin_role::text,
         a.status::text,
         public.admin_staff_readiness(a.user_id),
         a.must_change_password,
         a.changed_password_at,
         a.created_at,
         l.action, l.completed_at, l.outcome
    FROM public.admin_users a
    LEFT JOIN public.profiles p ON p.user_id = a.user_id
    LEFT JOIN LATERAL (
      SELECT s.action, s.completed_at, s.outcome
        FROM public.staff_lifecycle_requests s
       WHERE s.target_user_id = a.user_id AND s.state = 'completed'
       ORDER BY s.completed_at DESC NULLS LAST LIMIT 1) l ON true
   ORDER BY a.created_at DESC;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_staff_roster() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_staff_roster() TO authenticated, service_role;

-- ---------------------------------------------------------------------
-- 4. LIFECYCLE BEGIN (enforcement + idempotency + quorum honesty)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_staff_lifecycle_begin_as(
  _caller uuid, _action text, _idempotency_key text, _target_key text,
  _target_role text DEFAULT NULL, _must_change boolean DEFAULT true,
  _approval_id uuid DEFAULT NULL, _target_user_id uuid DEFAULT NULL,
  _reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_type text; v_material jsonb; v_hash text; v_row public.staff_lifecycle_requests;
  v_mode text; v_others int; v_id uuid; v_prev text;
BEGIN
  IF _caller IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE='42501'; END IF;
  IF _action NOT IN ('CREATE','DEACTIVATE','REACTIVATE','ROLE_CHANGE','ACCESS_RESET') THEN
    RAISE EXCEPTION 'BAD_ACTION' USING ERRCODE='22023'; END IF;
  IF _idempotency_key IS NULL OR length(_idempotency_key) < 8 THEN
    RAISE EXCEPTION 'BAD_IDEMPOTENCY_KEY' USING ERRCODE='22023'; END IF;
  IF _action IN ('CREATE','REACTIVATE','ROLE_CHANGE')
     AND _target_role NOT IN ('operations_admin','finance_admin') THEN
    RAISE EXCEPTION 'ROLE_FORBIDDEN: only operations_admin or finance_admin' USING ERRCODE='42501'; END IF;

  -- God / self safety for actions on an existing identity.
  IF _action <> 'CREATE' THEN
    IF _target_user_id IS NULL THEN RAISE EXCEPTION 'TARGET_REQUIRED' USING ERRCODE='22023'; END IF;
    IF _target_user_id = _caller THEN
      RAISE EXCEPTION 'SELF_LIFECYCLE_FORBIDDEN' USING ERRCODE='42501'; END IF;
    IF public.admin_role_canonical(_target_user_id) = 'god_admin'
       OR EXISTS (SELECT 1 FROM public.admin_users a WHERE a.user_id=_target_user_id
                   AND a.admin_role::text IN ('god_admin','super_admin'))
       OR EXISTS (SELECT 1 FROM public.user_roles r WHERE r.user_id=_target_user_id
                   AND r.role::text='god_admin') THEN
      RAISE EXCEPTION 'GOD_TARGET_FORBIDDEN' USING ERRCODE='42501'; END IF;
  END IF;

  v_type := CASE WHEN _action='CREATE' THEN 'staff_email' ELSE 'staff_user' END;
  v_material := jsonb_build_object('action',_action,'admin_role',_target_role,
                                   'must_change_password', COALESCE(_must_change,true));
  v_hash := public.admin_intent_hash('governance.staff.manage', v_type, _target_key, v_material);

  SELECT * INTO v_row FROM public.staff_lifecycle_requests
   WHERE idempotency_key = _idempotency_key FOR UPDATE;
  IF v_row.id IS NOT NULL THEN
    IF v_row.intent_hash IS DISTINCT FROM v_hash THEN
      RAISE EXCEPTION 'IDEMPOTENCY_INTENT_MISMATCH' USING ERRCODE='42501'; END IF;
    IF v_row.state = 'completed' THEN
      RETURN jsonb_build_object('result','ALREADY_COMPLETED','request_id',v_row.id,
                                'state',v_row.state,'auth_user_id',v_row.auth_user_id,
                                'target_user_id',v_row.target_user_id); END IF;
    IF v_row.state = 'failed_final' THEN
      RAISE EXCEPTION 'FAILED_FINAL: %', COALESCE(v_row.error_code,'unknown') USING ERRCODE='42501'; END IF;
    RETURN jsonb_build_object('result','RESUME','request_id',v_row.id,'state',v_row.state,
                              'auth_user_id',v_row.auth_user_id,'target_user_id',v_row.target_user_id);
  END IF;

  -- Honest quorum reporting before the generic approval_required denial.
  v_mode := public.admin_capability_mode('governance.staff.manage', _caller);
  IF v_mode = 'approval_required' AND _approval_id IS NULL THEN
    v_others := public._g3_active_god_count(_caller);
    IF v_others = 0 THEN
      RAISE EXCEPTION 'APPROVER_QUORUM_UNAVAILABLE: a second active God Admin is required'
        USING ERRCODE='42501';
    END IF;
  END IF;

  PERFORM public.admin_enforce_as(_caller, 'governance.staff.manage', v_type, _target_key,
                                  v_material, _approval_id, 'admins');

  v_prev := public.admin_role_canonical(_target_user_id);
  PERFORM set_config('chopchop.g3_lifecycle','on',true);
  INSERT INTO public.staff_lifecycle_requests
    (idempotency_key, action, requester_id, requester_role, target_key, target_user_id,
     target_email_hash, target_role, previous_role, must_change_password, intent_hash,
     approval_id, state, reason)
  VALUES (_idempotency_key, _action, _caller, public.admin_role_canonical(_caller), _target_key,
          _target_user_id,
          CASE WHEN _action='CREATE' THEN md5(lower(_target_key)) ELSE NULL END,
          _target_role, v_prev, COALESCE(_must_change,true), v_hash, _approval_id, 'enforced', _reason)
  RETURNING id INTO v_id;
  PERFORM set_config('chopchop.g3_lifecycle','off',true);

  RETURN jsonb_build_object('result','BEGUN','request_id',v_id,'state','enforced');
END;
$$;
REVOKE ALL ON FUNCTION public.admin_staff_lifecycle_begin_as(uuid,text,text,text,text,boolean,uuid,uuid,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_staff_lifecycle_begin_as(uuid,text,text,text,text,boolean,uuid,uuid,text)
  TO service_role;

-- Record the Auth-side provisioning so a retry never creates a second auth user.
CREATE OR REPLACE FUNCTION public.admin_staff_record_auth_as(_request_id uuid, _auth_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  PERFORM set_config('chopchop.g3_lifecycle','on',true);
  UPDATE public.staff_lifecycle_requests
     SET auth_user_id = COALESCE(auth_user_id, _auth_user_id),
         target_user_id = COALESCE(target_user_id, _auth_user_id),
         state = CASE WHEN state = 'enforced' THEN 'auth_provisioned' ELSE state END,
         updated_at = now()
   WHERE id = _request_id;
  PERFORM set_config('chopchop.g3_lifecycle','off',true);
  RETURN jsonb_build_object('ok', FOUND);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_staff_record_auth_as(uuid,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_staff_record_auth_as(uuid,uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.admin_staff_fail_as(_request_id uuid, _error_code text, _final boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  PERFORM set_config('chopchop.g3_lifecycle','on',true);
  UPDATE public.staff_lifecycle_requests
     SET error_code = _error_code,
         state = CASE WHEN _final THEN 'failed_final' ELSE state END,
         outcome = CASE WHEN _final THEN 'FAILED_FINAL' ELSE 'FAILED_RETRYABLE' END,
         updated_at = now()
   WHERE id = _request_id AND state <> 'completed';
  PERFORM set_config('chopchop.g3_lifecycle','off',true);
  RETURN jsonb_build_object('ok', FOUND);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_staff_fail_as(uuid,text,boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_staff_fail_as(uuid,text,boolean) TO service_role;

-- ---------------------------------------------------------------------
-- 5. CANONICAL AUTHORITY WRITER (single place that touches both sources)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._g3_set_staff_authority(
  _target uuid, _class text, _active boolean, _must_change boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_legacy public.admin_role;
BEGIN
  -- Staff-bearing user_roles labels are rebuilt from scratch; client and every
  -- professional/customer role is left untouched.
  DELETE FROM public.user_roles
   WHERE user_id = _target
     AND role::text IN ('operations_admin','finance_admin','support_admin');

  IF _active THEN
    v_legacy := public._g3_legacy_role(_class);
    IF v_legacy IS NULL THEN RAISE EXCEPTION 'ROLE_FORBIDDEN' USING ERRCODE='42501'; END IF;
    IF EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = _target) THEN
      UPDATE public.admin_users
         SET admin_role = v_legacy, status = 'active',
             must_change_password = _must_change,
             changed_password_at = CASE WHEN _must_change THEN NULL ELSE changed_password_at END,
             updated_at = now()
       WHERE user_id = _target;
    ELSE
      INSERT INTO public.admin_users (user_id, admin_role, status, must_change_password, created_via)
      VALUES (_target, v_legacy, 'active', _must_change, 'g3-staff-lifecycle');
    END IF;
    INSERT INTO public.user_roles (user_id, role)
    VALUES (_target, _class::public.app_role)
    ON CONFLICT (user_id, role) DO NOTHING;
  ELSE
    UPDATE public.admin_users
       SET status = 'suspended', updated_at = now()
     WHERE user_id = _target;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public._g3_set_staff_authority(uuid,text,boolean,boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._g3_set_staff_authority(uuid,text,boolean,boolean) TO service_role;

CREATE OR REPLACE FUNCTION public._g3_complete(
  _request_id uuid, _action text, _target uuid, _before jsonb, _after jsonb, _outcome text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_req public.staff_lifecycle_requests;
BEGIN
  SELECT * INTO v_req FROM public.staff_lifecycle_requests WHERE id = _request_id;
  PERFORM set_config('chopchop.g3_lifecycle','on',true);
  UPDATE public.staff_lifecycle_requests
     SET state='completed', outcome=_outcome, target_user_id=COALESCE(target_user_id,_target),
         completed_at=now(), updated_at=now(), error_code=NULL
   WHERE id=_request_id;
  PERFORM set_config('chopchop.g3_lifecycle','off',true);

  INSERT INTO public.audit_logs (actor_user_id, actor_role, module, action,
                                 target_type, target_id, before, after, note)
  VALUES (v_req.requester_id,
          CASE WHEN v_req.requester_role IS NULL THEN NULL ELSE v_req.requester_role::public.admin_role END,
          'admins', 'staff.lifecycle.' || _action, 'user', _target::text,
          _before,
          COALESCE(_after,'{}'::jsonb) || jsonb_build_object(
            'lifecycle_request_id', _request_id,
            'idempotency_key', v_req.idempotency_key,
            'approval_id', v_req.approval_id,
            'target_email_hash', v_req.target_email_hash,
            'outcome', _outcome),
          'g3_staff_lifecycle');
END;
$$;
REVOKE ALL ON FUNCTION public._g3_complete(uuid,text,uuid,jsonb,jsonb,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._g3_complete(uuid,text,uuid,jsonb,jsonb,text) TO service_role;

-- ---------------------------------------------------------------------
-- 6. FINALISERS
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_staff_finalize_create_as(
  _request_id uuid, _username text, _display_name text, _phone text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_req public.staff_lifecycle_requests; v_canon text;
BEGIN
  SELECT * INTO v_req FROM public.staff_lifecycle_requests WHERE id=_request_id FOR UPDATE;
  IF v_req.id IS NULL THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND' USING ERRCODE='42501'; END IF;
  IF v_req.action <> 'CREATE' THEN RAISE EXCEPTION 'ACTION_MISMATCH' USING ERRCODE='42501'; END IF;
  IF v_req.state = 'completed' THEN
    RETURN jsonb_build_object('result','ALREADY_COMPLETED','user_id',v_req.target_user_id); END IF;
  IF v_req.auth_user_id IS NULL THEN RAISE EXCEPTION 'AUTH_NOT_PROVISIONED' USING ERRCODE='42501'; END IF;

  INSERT INTO public.profiles (user_id, full_name, phone)
  VALUES (v_req.auth_user_id, COALESCE(NULLIF(_display_name,''), _username), NULLIF(_phone,''))
  ON CONFLICT (user_id) DO UPDATE
    SET full_name = COALESCE(NULLIF(EXCLUDED.full_name,''), public.profiles.full_name),
        phone     = COALESCE(EXCLUDED.phone, public.profiles.phone);

  PERFORM public._g3_set_staff_authority(v_req.auth_user_id, v_req.target_role, true,
                                         v_req.must_change_password);

  v_canon := public.admin_role_canonical(v_req.auth_user_id);
  IF v_canon IS DISTINCT FROM v_req.target_role THEN
    RAISE EXCEPTION 'CANONICAL_ASSERTION_FAILED: got %, expected %', COALESCE(v_canon,'null'), v_req.target_role
      USING ERRCODE='42501';
  END IF;

  PERFORM public._g3_complete(_request_id, 'CREATE', v_req.auth_user_id, NULL,
    jsonb_build_object('canonical_role', v_canon, 'username', _username,
                       'must_change_password', v_req.must_change_password), 'CREATED');
  RETURN jsonb_build_object('result','CREATED','user_id',v_req.auth_user_id,'canonical_role',v_canon);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_staff_finalize_create_as(uuid,text,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_staff_finalize_create_as(uuid,text,text,text) TO service_role;

CREATE OR REPLACE FUNCTION public.admin_staff_finalize_deactivate_as(_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_req public.staff_lifecycle_requests; v_before text; v_canon text;
BEGIN
  SELECT * INTO v_req FROM public.staff_lifecycle_requests WHERE id=_request_id FOR UPDATE;
  IF v_req.id IS NULL THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND' USING ERRCODE='42501'; END IF;
  IF v_req.action <> 'DEACTIVATE' THEN RAISE EXCEPTION 'ACTION_MISMATCH' USING ERRCODE='42501'; END IF;
  IF v_req.state = 'completed' THEN RETURN jsonb_build_object('result','ALREADY_COMPLETED'); END IF;
  v_before := public.admin_role_canonical(v_req.target_user_id);
  PERFORM public._g3_set_staff_authority(v_req.target_user_id, NULL, false, false);
  v_canon := public.admin_role_canonical(v_req.target_user_id);
  IF v_canon IS NOT NULL THEN
    RAISE EXCEPTION 'CANONICAL_ASSERTION_FAILED: authority survived deactivation (%)', v_canon
      USING ERRCODE='42501'; END IF;
  PERFORM public._g3_complete(_request_id,'DEACTIVATE',v_req.target_user_id,
    jsonb_build_object('canonical_role', v_before),
    jsonb_build_object('canonical_role', NULL, 'status','suspended'), 'DEACTIVATED');
  RETURN jsonb_build_object('result','DEACTIVATED','canonical_role',NULL);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_staff_finalize_deactivate_as(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_staff_finalize_deactivate_as(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.admin_staff_finalize_authority_as(_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_req public.staff_lifecycle_requests; v_before text; v_canon text;
BEGIN
  SELECT * INTO v_req FROM public.staff_lifecycle_requests WHERE id=_request_id FOR UPDATE;
  IF v_req.id IS NULL THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND' USING ERRCODE='42501'; END IF;
  IF v_req.action NOT IN ('REACTIVATE','ROLE_CHANGE','ACCESS_RESET') THEN
    RAISE EXCEPTION 'ACTION_MISMATCH' USING ERRCODE='42501'; END IF;
  IF v_req.state = 'completed' THEN RETURN jsonb_build_object('result','ALREADY_COMPLETED'); END IF;
  v_before := public.admin_role_canonical(v_req.target_user_id);

  IF v_req.action = 'ACCESS_RESET' THEN
    IF NOT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id=v_req.target_user_id AND status='active') THEN
      RAISE EXCEPTION 'TARGET_NOT_ACTIVE_STAFF' USING ERRCODE='42501'; END IF;
    UPDATE public.admin_users
       SET must_change_password = true, changed_password_at = NULL, updated_at = now()
     WHERE user_id = v_req.target_user_id;
  ELSE
    IF v_req.action = 'ROLE_CHANGE' AND v_before IS NULL THEN
      RAISE EXCEPTION 'TARGET_NOT_ACTIVE_STAFF' USING ERRCODE='42501'; END IF;
    PERFORM public._g3_set_staff_authority(v_req.target_user_id, v_req.target_role, true, true);
    v_canon := public.admin_role_canonical(v_req.target_user_id);
    -- readiness is temp_password_required, so the canonical class is installed but
    -- carries no effective capability until first-login completion.
    IF v_canon IS DISTINCT FROM v_req.target_role THEN
      RAISE EXCEPTION 'CANONICAL_ASSERTION_FAILED: got %, expected %',
        COALESCE(v_canon,'null'), v_req.target_role USING ERRCODE='42501'; END IF;
  END IF;

  PERFORM public._g3_complete(_request_id, v_req.action, v_req.target_user_id,
    jsonb_build_object('canonical_role', v_before),
    jsonb_build_object('canonical_role', public.admin_role_canonical(v_req.target_user_id),
                       'readiness', public.admin_staff_readiness(v_req.target_user_id)),
    v_req.action);
  RETURN jsonb_build_object('result', v_req.action,
                            'canonical_role', public.admin_role_canonical(v_req.target_user_id),
                            'readiness', public.admin_staff_readiness(v_req.target_user_id));
END;
$$;
REVOKE ALL ON FUNCTION public.admin_staff_finalize_authority_as(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_staff_finalize_authority_as(uuid) TO service_role;

-- ---------------------------------------------------------------------
-- 7. FIRST-LOGIN COMPLETION (self-service, audited)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_clear_must_change_password()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_uid uuid := auth.uid(); v_role public.admin_role;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='28000'; END IF;
  SELECT admin_role INTO v_role FROM public.admin_users
   WHERE user_id = v_uid AND status = 'active' LIMIT 1;
  IF v_role IS NULL THEN RAISE EXCEPTION 'not a staff account' USING ERRCODE='42501'; END IF;

  UPDATE public.admin_users
     SET must_change_password = false, changed_password_at = now(), updated_at = now()
   WHERE user_id = v_uid;

  INSERT INTO public.audit_logs (actor_user_id, actor_role, module, action, target_type, target_id, after, note)
  VALUES (v_uid, v_role, 'admins', 'staff.lifecycle.FIRST_PASSWORD_COMPLETED', 'user', v_uid::text,
          jsonb_build_object('changed_at', now(),
                             'readiness', public.admin_staff_readiness(v_uid)),
          'g3_staff_lifecycle');
  RETURN jsonb_build_object('ok', true, 'readiness', public.admin_staff_readiness(v_uid));
END;
$$;
REVOKE ALL ON FUNCTION public.admin_clear_must_change_password() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_clear_must_change_password() TO authenticated, service_role;