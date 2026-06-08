
CREATE OR REPLACE FUNCTION public.marche_enforce_pending_merchant_privacy()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  s_status text;
  s_onboard text;
BEGIN
  IF NEW.store_id IS NULL THEN
    RETURN NEW;
  END IF;
  SELECT status, onboarding_status INTO s_status, s_onboard
    FROM public.merchant_stores WHERE id = NEW.store_id;
  IF s_onboard IS DISTINCT FROM 'approved'
     OR s_status NOT IN ('active', 'paused') THEN
    NEW.visibility := 'private';
    IF NEW.status = 'active' THEN
      NEW.status := 'paused';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_marche_enforce_pending_privacy ON public.marketplace_listings;
CREATE TRIGGER trg_marche_enforce_pending_privacy
  BEFORE INSERT OR UPDATE ON public.marketplace_listings
  FOR EACH ROW EXECUTE FUNCTION public.marche_enforce_pending_merchant_privacy();
