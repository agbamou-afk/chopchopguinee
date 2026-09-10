CREATE OR REPLACE FUNCTION public.admin_review_approval(_approval_id uuid, _decision text, _note text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE v_caller uuid := auth.uid(); v_req public.approval_requests;
BEGIN
  IF public.admin_role_canonical(v_caller) IS DISTINCT FROM 'god_admin' THEN
    RAISE EXCEPTION 'approver_not_god_admin' USING ERRCODE='42501';
  END IF;
  -- G6: an approver whose own access is not fully established (temporary
  -- password still pending) holds zero authority, exactly like every other
  -- capability path. Four-eyes must not be the one door that stays open.
  IF public.admin_staff_readiness(v_caller) IS DISTINCT FROM 'ready' THEN
    RAISE EXCEPTION 'approver_not_ready' USING ERRCODE='42501';
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
$fn$;

REVOKE EXECUTE ON FUNCTION public.admin_review_approval(uuid,text,text) FROM anon;