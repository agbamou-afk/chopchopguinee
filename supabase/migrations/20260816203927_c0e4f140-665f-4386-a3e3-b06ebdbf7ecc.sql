REVOKE ALL ON public.marche_fulfillment_profiles FROM anon, authenticated;
REVOKE ALL ON public.marche_fulfillment_events FROM anon, authenticated;
REVOKE ALL ON public.marche_fulfillment_observations FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public._qa_n435_fixture_store_nc(p_owner uuid, p_slug text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v uuid;
BEGIN
  INSERT INTO public.merchant_stores(owner_user_id, slug, name, status, onboarding_status)
  VALUES (p_owner, p_slug, 'QA N435 Store NoCoords', 'active', 'approved')
  RETURNING id INTO v;
  RETURN v;
END $$;
REVOKE ALL ON FUNCTION public._qa_n435_fixture_store_nc(uuid,text) FROM PUBLIC, anon, authenticated;