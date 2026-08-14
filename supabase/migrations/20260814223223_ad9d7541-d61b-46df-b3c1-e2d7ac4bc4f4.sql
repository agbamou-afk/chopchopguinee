REVOKE EXECUTE ON FUNCTION public.marche_toggle_listing_save(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.withdraw_marketplace_offer(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.get_listing_minimum_price(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.set_primary_listing_image(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.marche_toggle_listing_save(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.withdraw_marketplace_offer(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_listing_minimum_price(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_primary_listing_image(uuid) TO authenticated;