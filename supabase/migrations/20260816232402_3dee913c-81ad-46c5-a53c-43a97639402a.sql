REVOKE ALL ON public.marche_staple_categories FROM anon, authenticated;
REVOKE ALL ON public.marche_staple_commodities FROM anon, authenticated;
REVOKE ALL ON public.marche_staple_variants FROM anon, authenticated;
REVOKE ALL ON public.marche_staple_purchase_options FROM anon, authenticated;
GRANT ALL ON public.marche_staple_categories TO service_role;
GRANT ALL ON public.marche_staple_commodities TO service_role;
GRANT ALL ON public.marche_staple_variants TO service_role;
GRANT ALL ON public.marche_staple_purchase_options TO service_role;

REVOKE ALL ON FUNCTION public.marche_staples_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_staples_admin() TO authenticated, service_role;