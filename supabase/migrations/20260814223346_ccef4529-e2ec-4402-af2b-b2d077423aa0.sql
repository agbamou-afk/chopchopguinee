REVOKE EXECUTE ON FUNCTION public.marche_toggle_listing_save(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.withdraw_marketplace_offer(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_listing_minimum_price(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.set_primary_listing_image(uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.marche_sync_photo_count()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE lid uuid; prev text;
BEGIN
  lid := COALESCE(NEW.listing_id, OLD.listing_id);
  prev := COALESCE(current_setting('marche.rpc', true), '');
  PERFORM set_config('marche.rpc', '1', true);
  UPDATE public.marketplace_listings
     SET photo_count = (SELECT count(*) FROM public.listing_images WHERE listing_id = lid)
   WHERE id = lid;
  PERFORM set_config('marche.rpc', prev, true);
  RETURN NULL;
END $function$;