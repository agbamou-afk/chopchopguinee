
-- G3 CLOSEOUT — readiness seam + sanitized governance reads + least-privilege reassertion.

-- 1) Governance READ authority = canonical god_admin AND lifecycle-ready.
CREATE OR REPLACE FUNCTION public._g3_require_governance_read()
RETURNS void
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_uid uuid := auth.uid(); v_ready text;
BEGIN
  IF COALESCE(public.admin_role_canonical(v_uid), '') <> 'god_admin' THEN
    RAISE EXCEPTION 'capability_denied: governance.staff.manage' USING ERRCODE='42501';
  END IF;
  v_ready := public.admin_staff_readiness(v_uid);
  IF v_ready IS DISTINCT FROM 'ready' THEN
    RAISE EXCEPTION 'readiness_denied: %', v_ready USING ERRCODE='42501';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public._g3_require_governance_read() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._g3_require_governance_read() TO service_role;

CREATE OR REPLACE FUNCTION public.admin_staff_roster()
RETURNS TABLE(user_id uuid, full_name text, phone text, canonical_role text, legacy_role text,
              status text, readiness text, must_change_password boolean,
              changed_password_at timestamptz, created_at timestamptz,
              last_action text, last_action_at timestamptz, last_outcome text)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  PERFORM public._g3_require_governance_read();
  RETURN QUERY
  SELECT a.user_id, p.full_name, p.phone,
         public.admin_role_canonical(a.user_id),
         a.admin_role::text, a.status::text,
         public.admin_staff_readiness(a.user_id),
         a.must_change_password, a.changed_password_at, a.created_at,
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

CREATE OR REPLACE FUNCTION public.admin_staff_quorum_status()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_caller uuid := auth.uid(); v_mode text; v_others int;
BEGIN
  PERFORM public._g3_require_governance_read();
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

-- 2) Sanitized lifecycle history for the /admin/admins mirror. No secrets, no email.
CREATE OR REPLACE FUNCTION public.admin_staff_lifecycle_history(_limit integer DEFAULT 50)
RETURNS TABLE(id uuid, action text, target_user_id uuid, target_label text, state text,
              outcome text, error_code text, approval_id uuid, target_role text,
              previous_role text, requester_id uuid, reason text,
              created_at timestamptz, completed_at timestamptz)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  PERFORM public._g3_require_governance_read();
  RETURN QUERY
  SELECT s.id, s.action, s.target_user_id,
         CASE WHEN s.action = 'CREATE'
              THEN '•••@' || COALESCE(split_part(s.target_key, '@', 2), '—')
              ELSE COALESCE(s.target_user_id::text, s.target_key) END,
         s.state, s.outcome, s.error_code, s.approval_id, s.target_role, s.previous_role,
         s.requester_id, s.reason, s.created_at, s.completed_at
    FROM public.staff_lifecycle_requests s
   ORDER BY s.created_at DESC
   LIMIT GREATEST(1, LEAST(COALESCE(_limit, 50), 200));
END;
$$;
REVOKE ALL ON FUNCTION public.admin_staff_lifecycle_history(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_staff_lifecycle_history(integer) TO authenticated, service_role;

-- 3) Sanitized four-eyes view for the staff capability.
CREATE OR REPLACE FUNCTION public.admin_staff_approvals(_limit integer DEFAULT 25)
RETURNS TABLE(id uuid, status text, target_type text, target_id text, material jsonb,
              requested_by uuid, reviewed_by uuid, expires_at timestamptz,
              consumed_at timestamptz, created_at timestamptz, usable boolean)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  PERFORM public._g3_require_governance_read();
  RETURN QUERY
  SELECT r.id, r.status::text, r.target_type, r.target_id,
         (r.material - 'temporary_password' - 'password'),
         r.requested_by, r.reviewed_by, r.expires_at, r.consumed_at, r.created_at,
         (r.status::text = 'approved' AND r.consumed_at IS NULL
          AND (r.expires_at IS NULL OR r.expires_at > now()))
    FROM public.approval_requests r
   WHERE r.capability = 'governance.staff.manage'
   ORDER BY r.created_at DESC
   LIMIT GREATEST(1, LEAST(COALESCE(_limit, 25), 100));
END;
$$;
REVOKE ALL ON FUNCTION public.admin_staff_approvals(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_staff_approvals(integer) TO authenticated, service_role;

-- 4) Least-privilege reassertion on the lifecycle provenance table.
ALTER TABLE public.staff_lifecycle_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.staff_lifecycle_requests FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.staff_lifecycle_requests TO service_role;
