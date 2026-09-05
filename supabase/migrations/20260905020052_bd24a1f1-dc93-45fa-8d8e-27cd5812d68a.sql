-- G2 — explicit-caller variant for Edge Functions (service role only).
CREATE OR REPLACE FUNCTION public.admin_enforce_as(
  _caller uuid, _capability text,
  _target_type text DEFAULT NULL, _target_id text DEFAULT NULL,
  _material jsonb DEFAULT '{}'::jsonb, _approval_id uuid DEFAULT NULL,
  _module text DEFAULT 'admin')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_role text := public.admin_role_canonical(_caller);
  v_mode text;
  v_hash text := public.admin_intent_hash(_capability,_target_type,_target_id,coalesce(_material,'{}'::jsonb));
  v_req  public.approval_requests;
BEGIN
  IF _caller IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE='42501'; END IF;
  IF v_role IS NULL THEN RAISE EXCEPTION 'capability_denied: %', _capability USING ERRCODE='42501'; END IF;
  v_mode := public.admin_capability_mode(_capability, _caller);
  IF v_mode IS NULL OR v_mode = 'read' THEN
    RAISE EXCEPTION 'capability_denied: %', _capability USING ERRCODE='42501';
  END IF;

  IF v_mode = 'allow' THEN
    INSERT INTO public.audit_logs (actor_user_id, actor_role, module, action, target_type, target_id, after, note)
    VALUES (_caller, v_role::admin_role, _module, _capability, _target_type, _target_id,
            coalesce(_material,'{}'::jsonb) || jsonb_build_object('capability',_capability,
              'canonical_role',v_role,'intent_hash',v_hash,'outcome','allow'),
            'g2_capability_enforcement');
    RETURN jsonb_build_object('role',v_role,'capability',_capability,'mode','allow','intent_hash',v_hash);
  END IF;

  IF _approval_id IS NULL THEN
    RAISE EXCEPTION 'approval_required: %', _capability USING ERRCODE='42501'; END IF;
  SELECT * INTO v_req FROM public.approval_requests WHERE id=_approval_id FOR UPDATE;
  IF v_req.id IS NULL THEN RAISE EXCEPTION 'approval_not_found' USING ERRCODE='42501'; END IF;
  IF v_req.status::text <> 'approved' THEN RAISE EXCEPTION 'approval_not_approved' USING ERRCODE='42501'; END IF;
  IF v_req.requested_by <> _caller THEN RAISE EXCEPTION 'approval_requester_mismatch' USING ERRCODE='42501'; END IF;
  IF v_req.reviewed_by IS NULL OR v_req.reviewed_by = v_req.requested_by THEN
    RAISE EXCEPTION 'four_eyes_violation' USING ERRCODE='42501'; END IF;
  IF public.admin_role_canonical(v_req.reviewed_by) IS DISTINCT FROM 'god_admin' THEN
    RAISE EXCEPTION 'approver_not_god_admin' USING ERRCODE='42501'; END IF;
  IF v_req.capability IS DISTINCT FROM _capability THEN
    RAISE EXCEPTION 'approval_capability_mismatch' USING ERRCODE='42501'; END IF;
  IF v_req.target_type IS DISTINCT FROM _target_type OR v_req.target_id IS DISTINCT FROM _target_id THEN
    RAISE EXCEPTION 'approval_target_mismatch' USING ERRCODE='42501'; END IF;
  IF v_req.intent_hash IS DISTINCT FROM v_hash THEN
    RAISE EXCEPTION 'approval_material_mismatch' USING ERRCODE='42501'; END IF;
  IF v_req.expires_at IS NOT NULL AND v_req.expires_at <= now() THEN
    RAISE EXCEPTION 'approval_expired' USING ERRCODE='42501'; END IF;
  UPDATE public.approval_requests
     SET consumed_at=now(), consumed_by=_caller,
         execution_ref = coalesce(execution_ref, _approval_id::text||':'||v_hash)
   WHERE id=_approval_id AND consumed_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'approval_already_consumed' USING ERRCODE='42501'; END IF;

  INSERT INTO public.audit_logs (actor_user_id, actor_role, module, action, target_type, target_id, after, note)
  VALUES (_caller, v_role::admin_role, _module, _capability, _target_type, _target_id,
          coalesce(_material,'{}'::jsonb) || jsonb_build_object('capability',_capability,
            'canonical_role',v_role,'approval_id',_approval_id,'approver',v_req.reviewed_by,
            'intent_hash',v_hash,'outcome','approved_consumed'),
          'g2_capability_enforcement');
  RETURN jsonb_build_object('role',v_role,'capability',_capability,'mode','approval_required',
                            'approval_id',_approval_id,'intent_hash',v_hash);
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_enforce_as(uuid,text,text,text,jsonb,uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_enforce_as(uuid,text,text,text,jsonb,uuid,text) TO service_role;