
-- 1. Sync merchant_status inside admin_merchant_decision
CREATE OR REPLACE FUNCTION public.admin_merchant_decision(_store_id uuid, _decision text, _reason text DEFAULT NULL::text)
RETURNS merchant_stores
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  _admin uuid := auth.uid();
  _row public.merchant_stores;
BEGIN
  IF _admin IS NULL OR NOT public.has_role(_admin, 'admin') THEN
    RAISE EXCEPTION 'not_authorized';
  END IF;
  IF _decision NOT IN ('approve','reject','request_info','suspend','reactivate') THEN
    RAISE EXCEPTION 'invalid_decision';
  END IF;

  SELECT * INTO _row FROM public.merchant_stores WHERE id = _store_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'store_not_found'; END IF;
  IF _row.owner_user_id = _admin THEN
    RAISE EXCEPTION 'self_approval_forbidden';
  END IF;

  IF _decision = 'approve' THEN
    UPDATE public.merchant_stores
       SET status='active', onboarding_status='approved',
           merchant_status='active',
           approved_at=now(), approved_by=_admin,
           rejection_reason=NULL, updated_at=now()
     WHERE id=_store_id RETURNING * INTO _row;
  ELSIF _decision = 'reject' THEN
    UPDATE public.merchant_stores
       SET status='rejected', onboarding_status='rejected',
           merchant_status='rejected',
           rejection_reason=_reason, updated_at=now()
     WHERE id=_store_id RETURNING * INTO _row;
  ELSIF _decision = 'request_info' THEN
    UPDATE public.merchant_stores
       SET onboarding_status='needs_info',
           merchant_status='needs_info',
           rejection_reason=_reason, updated_at=now()
     WHERE id=_store_id RETURNING * INTO _row;
  ELSIF _decision = 'suspend' THEN
    UPDATE public.merchant_stores
       SET status='suspended',
           merchant_status='suspended',
           rejection_reason=_reason, updated_at=now()
     WHERE id=_store_id RETURNING * INTO _row;
  ELSIF _decision = 'reactivate' THEN
    UPDATE public.merchant_stores
       SET status='active',
           merchant_status='active',
           updated_at=now()
     WHERE id=_store_id RETURNING * INTO _row;
  END IF;

  BEGIN
    PERFORM public.log_admin_action(
      'merchants','merchant_decision','merchant_store', _store_id::text,
      NULL, jsonb_build_object('decision',_decision,'reason',_reason), _reason
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN _row;
END;
$function$;

-- 2. Auto-publish a merchant's listings when the store transitions to (active, approved)
CREATE OR REPLACE FUNCTION public.merchant_stores_publish_listings_on_approval()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only on transition INTO (active, approved)
  IF NEW.status = 'active' AND NEW.onboarding_status = 'approved'
     AND (OLD.status IS DISTINCT FROM 'active' OR OLD.onboarding_status IS DISTINCT FROM 'approved') THEN
    UPDATE public.marketplace_listings
       SET visibility = 'public',
           status     = 'active',
           updated_at = now()
     WHERE store_id  = NEW.id
       AND visibility = 'private'
       AND status     IN ('paused','active');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_merchant_stores_publish_listings_on_approval ON public.merchant_stores;
CREATE TRIGGER trg_merchant_stores_publish_listings_on_approval
  AFTER UPDATE OF status, onboarding_status ON public.merchant_stores
  FOR EACH ROW EXECUTE FUNCTION public.merchant_stores_publish_listings_on_approval();
