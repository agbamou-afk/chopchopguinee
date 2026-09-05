-- G2.C — Real server-side approval object.

ALTER TABLE public.approval_requests
  ADD COLUMN IF NOT EXISTS capability     text,
  ADD COLUMN IF NOT EXISTS target_type    text,
  ADD COLUMN IF NOT EXISTS target_id      text,
  ADD COLUMN IF NOT EXISTS material       jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS intent_hash    text,
  ADD COLUMN IF NOT EXISTS expires_at     timestamptz,
  ADD COLUMN IF NOT EXISTS consumed_at    timestamptz,
  ADD COLUMN IF NOT EXISTS consumed_by    uuid,
  ADD COLUMN IF NOT EXISTS execution_ref  text,
  ADD COLUMN IF NOT EXISTS outcome        jsonb;

CREATE UNIQUE INDEX IF NOT EXISTS approval_requests_execution_ref_uk
  ON public.approval_requests (execution_ref) WHERE execution_ref IS NOT NULL;

CREATE OR REPLACE FUNCTION public.admin_intent_hash(
  _capability text, _target_type text, _target_id text, _material jsonb)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO 'public'
AS $function$
  SELECT md5(
    coalesce(_capability,'') || '|' ||
    coalesce(_target_type,'*none*') || '|' ||
    coalesce(_target_id,'*none*') || '|' ||
    coalesce(_material,'{}'::jsonb)::text);
$function$;

-- Immutable provenance writer. Never receives secrets.
CREATE OR REPLACE FUNCTION public.admin_audit_write(
  _module text, _action text, _capability text,
  _target_type text, _target_id text,
  _before jsonb, _after jsonb, _approval_id uuid, _outcome text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_caller uuid := auth.uid(); v_role text := public.admin_role_canonical(auth.uid());
BEGIN
  INSERT INTO public.audit_logs (actor_user_id, actor_role, module, action,
                                 target_type, target_id, before, after, note)
  VALUES (v_caller,
          CASE WHEN v_role IS NULL THEN NULL ELSE v_role::admin_role END,
          coalesce(_module,'admin'), _action, _target_type, _target_id,
          _before,
          coalesce(_after,'{}'::jsonb) || jsonb_build_object(
            'capability', _capability,
            'canonical_role', v_role,
            'approval_id', _approval_id,
            'intent_hash', public.admin_intent_hash(_capability,_target_type,_target_id,coalesce(_after,'{}'::jsonb)),
            'outcome', _outcome),
          'g2_capability_enforcement');
END;
$function$;

-- Create an approval request bound to the exact intent.
CREATE OR REPLACE FUNCTION public.admin_request_approval(
  _capability text, _target_type text DEFAULT NULL, _target_id text DEFAULT NULL,
  _material jsonb DEFAULT '{}'::jsonb, _module text DEFAULT 'admin',
  _ttl_minutes int DEFAULT 1440)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_caller uuid := auth.uid(); v_mode text; v_id uuid;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE='42501'; END IF;
  v_mode := public.admin_capability_mode(_capability, v_caller);
  IF v_mode IS DISTINCT FROM 'approval_required' THEN
    RAISE EXCEPTION 'capability_not_approval_required: %', _capability USING ERRCODE='42501';
  END IF;
  INSERT INTO public.approval_requests
    (requested_by, module, action, payload, capability, target_type, target_id,
     material, intent_hash, expires_at, status)
  VALUES (v_caller, coalesce(_module,'admin'), _capability,
          coalesce(_material,'{}'::jsonb), _capability, _target_type, _target_id,
          coalesce(_material,'{}'::jsonb),
          public.admin_intent_hash(_capability,_target_type,_target_id,coalesce(_material,'{}'::jsonb)),
          now() + make_interval(mins => greatest(coalesce(_ttl_minutes,1440),1)),
          'pending')
  RETURNING id INTO v_id;
  PERFORM public.admin_audit_write(_module,'approval.request',_capability,_target_type,_target_id,
                                   NULL, coalesce(_material,'{}'::jsonb), v_id, 'pending');
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_review_approval(
  _approval_id uuid, _decision text, _note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_caller uuid := auth.uid(); v_req public.approval_requests;
BEGIN
  IF public.admin_role_canonical(v_caller) IS DISTINCT FROM 'god_admin' THEN
    RAISE EXCEPTION 'approver_not_god_admin' USING ERRCODE='42501';
  END IF;
  IF _decision NOT IN ('approved','rejected') THEN
    RAISE EXCEPTION 'bad_decision' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_req FROM public.approval_requests WHERE id=_approval_id FOR UPDATE;
  IF v_req.id IS NULL THEN RAISE EXCEPTION 'approval_not_found' USING ERRCODE='42501'; END IF;
  IF v_req.requested_by = v_caller THEN
    RAISE EXCEPTION 'four_eyes_violation_self_approval' USING ERRCODE='42501';
  END IF;
  IF v_req.status::text <> 'pending' THEN
    RAISE EXCEPTION 'approval_not_pending' USING ERRCODE='42501';
  END IF;
  UPDATE public.approval_requests
     SET status=_decision::approval_status, reviewed_by=v_caller, reviewed_at=now(), review_note=_note
   WHERE id=_approval_id;
  PERFORM public.admin_audit_write(v_req.module,'approval.review',v_req.capability,
          v_req.target_type, v_req.target_id, NULL, v_req.material, _approval_id, _decision);
  RETURN jsonb_build_object('id',_approval_id,'status',_decision);
END;
$function$;

/**
 * admin_enforce — the single constitutional gate.
 * ALLOW capability            -> passes, writes provenance.
 * APPROVAL_REQUIRED capability-> requires a matching, approved, unexpired,
 *                                unconsumed approval; consumes it in this transaction.
 */
CREATE OR REPLACE FUNCTION public.admin_enforce(
  _capability text,
  _target_type text DEFAULT NULL,
  _target_id text DEFAULT NULL,
  _material jsonb DEFAULT '{}'::jsonb,
  _approval_id uuid DEFAULT NULL,
  _module text DEFAULT 'admin')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_caller uuid := auth.uid();
  v_role   text := public.admin_role_canonical(auth.uid());
  v_mode   text;
  v_hash   text := public.admin_intent_hash(_capability,_target_type,_target_id,coalesce(_material,'{}'::jsonb));
  v_req    public.approval_requests;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE='42501'; END IF;
  IF v_role IS NULL THEN RAISE EXCEPTION 'capability_denied: %', _capability USING ERRCODE='42501'; END IF;
  v_mode := public.admin_capability_mode(_capability, v_caller);

  IF v_mode IS NULL OR v_mode = 'read' THEN
    RAISE EXCEPTION 'capability_denied: %', _capability USING ERRCODE='42501';
  END IF;

  IF v_mode = 'allow' THEN
    PERFORM public.admin_audit_write(_module,_capability,_capability,_target_type,_target_id,
                                     NULL,_material,NULL,'allow');
    RETURN jsonb_build_object('role',v_role,'capability',_capability,'mode','allow','intent_hash',v_hash);
  END IF;

  -- approval_required
  IF _approval_id IS NULL THEN
    RAISE EXCEPTION 'approval_required: %', _capability USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_req FROM public.approval_requests WHERE id=_approval_id FOR UPDATE;
  IF v_req.id IS NULL          THEN RAISE EXCEPTION 'approval_not_found' USING ERRCODE='42501'; END IF;
  IF v_req.status::text <> 'approved' THEN RAISE EXCEPTION 'approval_not_approved' USING ERRCODE='42501'; END IF;
  IF v_req.requested_by <> v_caller   THEN RAISE EXCEPTION 'approval_requester_mismatch' USING ERRCODE='42501'; END IF;
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
  IF v_req.consumed_at IS NOT NULL THEN
    RAISE EXCEPTION 'approval_already_consumed' USING ERRCODE='42501'; END IF;

  UPDATE public.approval_requests
     SET consumed_at = now(), consumed_by = v_caller,
         execution_ref = coalesce(execution_ref, _approval_id::text || ':' || v_hash)
   WHERE id = _approval_id AND consumed_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'approval_already_consumed' USING ERRCODE='42501';
  END IF;

  PERFORM public.admin_audit_write(_module,_capability,_capability,_target_type,_target_id,
                                   NULL,_material,_approval_id,'approved_consumed');
  RETURN jsonb_build_object('role',v_role,'capability',_capability,'mode','approval_required',
                            'approval_id',_approval_id,'approver',v_req.reviewed_by,'intent_hash',v_hash);
END;
$function$;

-- Legacy gate kept as a thin delegate so nothing silently bypasses the new law.
CREATE OR REPLACE FUNCTION public.admin_four_eyes_gate(_capability text, _approval_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.admin_enforce(_capability, NULL, NULL, '{}'::jsonb, _approval_id, 'admin');
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_audit_write(text,text,text,text,text,jsonb,jsonb,uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_audit_write(text,text,text,text,text,jsonb,jsonb,uuid,text) TO service_role;
REVOKE ALL ON FUNCTION public.admin_enforce(text,text,text,jsonb,uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_enforce(text,text,text,jsonb,uuid,text) TO service_role;
REVOKE EXECUTE ON FUNCTION public.admin_intent_hash(text,text,text,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_intent_hash(text,text,text,jsonb) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.admin_request_approval(text,text,text,jsonb,text,int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_request_approval(text,text,text,jsonb,text,int) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.admin_review_approval(uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_review_approval(uuid,text,text) TO authenticated, service_role;