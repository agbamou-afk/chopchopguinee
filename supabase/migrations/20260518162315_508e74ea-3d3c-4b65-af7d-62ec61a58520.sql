
DO $$ BEGIN
  CREATE TYPE listing_availability AS ENUM ('available','limited','to_confirm','reserved','sold');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

ALTER TABLE public.marketplace_listings
  ADD COLUMN IF NOT EXISTS availability listing_availability NOT NULL DEFAULT 'to_confirm',
  ADD COLUMN IF NOT EXISTS fulfillment_options text[] NOT NULL DEFAULT ARRAY['to_confirm']::text[],
  ADD COLUMN IF NOT EXISTS photo_count integer NOT NULL DEFAULT 0;

-- Backfill: merchants default to available, community to to_confirm
UPDATE public.marketplace_listings
SET availability = 'available'
WHERE kind = 'merchant' AND availability = 'to_confirm';

-- Photo count trigger
CREATE OR REPLACE FUNCTION public.marche_sync_photo_count()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE lid uuid;
BEGIN
  lid := COALESCE(NEW.listing_id, OLD.listing_id);
  UPDATE public.marketplace_listings
  SET photo_count = (SELECT count(*) FROM public.listing_images WHERE listing_id = lid)
  WHERE id = lid;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_marche_sync_photo_count ON public.listing_images;
CREATE TRIGGER trg_marche_sync_photo_count
AFTER INSERT OR DELETE ON public.listing_images
FOR EACH ROW EXECUTE FUNCTION public.marche_sync_photo_count();

-- Backfill existing counts
UPDATE public.marketplace_listings l
SET photo_count = (SELECT count(*) FROM public.listing_images i WHERE i.listing_id = l.id);
