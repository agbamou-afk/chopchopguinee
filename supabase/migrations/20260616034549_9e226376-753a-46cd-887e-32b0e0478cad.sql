CREATE OR REPLACE FUNCTION public.admin_set_merchant_location_status(p_store_id uuid, p_status text, p_note text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_store public.merchant_stores%ROWTYPE;
  v_place_status map_verification_status;
BEGIN
  IF NOT public.has_role(v_uid, 'admin') THEN
    RAISE EXCEPTION 'admin required';
  END IF;
  IF p_status NOT IN ('submitted','needs_review','admin_verified','trusted','rejected') THEN
    RAISE EXCEPTION 'invalid status';
  END IF;

  SELECT * INTO v_store FROM public.merchant_stores WHERE id = p_store_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'store not found'; END IF;

  v_place_status := CASE p_status
    WHEN 'admin_verified' THEN 'admin_verified'::map_verification_status
    WHEN 'trusted' THEN 'trusted'::map_verification_status
    WHEN 'needs_review' THEN 'needs_review'::map_verification_status
    WHEN 'rejected' THEN 'closed'::map_verification_status
    ELSE 'submitted'::map_verification_status
  END;

  IF v_store.map_place_id IS NOT NULL THEN
    UPDATE public.map_places SET
      verification_status = v_place_status,
      confidence_score = public.map_default_confidence(v_place_status),
      verified_at = CASE WHEN p_status IN ('admin_verified','trusted') THEN now() ELSE verified_at END,
      verified_by = CASE WHEN p_status IN ('admin_verified','trusted') THEN v_uid ELSE verified_by END,
      active = CASE WHEN p_status='rejected' THEN false ELSE active END,
      updated_at = now()
    WHERE id = v_store.map_place_id;
  END IF;

  UPDATE public.merchant_stores SET
    location_submission_status = p_status,
    location_verified_at = CASE WHEN p_status IN ('admin_verified','trusted') THEN now() ELSE location_verified_at END,
    location_verified_by = CASE WHEN p_status IN ('admin_verified','trusted') THEN v_uid ELSE location_verified_by END,
    location_notes = COALESCE(NULLIF(btrim(p_note),''), location_notes),
    updated_at = now()
  WHERE id = p_store_id;

  BEGIN
    INSERT INTO public.audit_logs (actor_id, action, target_type, target_id, metadata)
    VALUES (v_uid, 'admin.merchant.location.' || p_status, 'merchant_store', p_store_id,
            jsonb_build_object('map_place_id', v_store.map_place_id, 'note', p_note));
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
END;
$function$;