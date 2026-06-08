
ALTER TABLE public.listing_images
  ADD COLUMN IF NOT EXISTS image_type text NOT NULL DEFAULT 'original',
  ADD COLUMN IF NOT EXISTS source_image_id uuid NULL REFERENCES public.listing_images(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS processing_status text NOT NULL DEFAULT 'ready',
  ADD COLUMN IF NOT EXISTS processing_error_code text NULL,
  ADD COLUMN IF NOT EXISTS is_primary boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.listing_images
  DROP CONSTRAINT IF EXISTS listing_images_image_type_chk;
ALTER TABLE public.listing_images
  ADD CONSTRAINT listing_images_image_type_chk
  CHECK (image_type IN ('original','cleaned','thumbnail'));

ALTER TABLE public.listing_images
  DROP CONSTRAINT IF EXISTS listing_images_processing_status_chk;
ALTER TABLE public.listing_images
  ADD CONSTRAINT listing_images_processing_status_chk
  CHECK (processing_status IN ('pending','processing','ready','failed'));

CREATE UNIQUE INDEX IF NOT EXISTS uniq_listing_images_primary
  ON public.listing_images(listing_id) WHERE is_primary;

CREATE OR REPLACE FUNCTION public.listing_images_enforce_single_primary()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.is_primary THEN
    UPDATE public.listing_images
       SET is_primary = false, updated_at = now()
     WHERE listing_id = NEW.listing_id
       AND id <> NEW.id
       AND is_primary = true;
  END IF;
  NEW.updated_at = now();
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_listing_images_primary ON public.listing_images;
CREATE TRIGGER trg_listing_images_primary
  BEFORE INSERT OR UPDATE ON public.listing_images
  FOR EACH ROW EXECUTE FUNCTION public.listing_images_enforce_single_primary();

CREATE OR REPLACE FUNCTION public.set_primary_listing_image(p_image_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_listing uuid;
  v_seller uuid;
BEGIN
  SELECT li.listing_id, ml.seller_id
    INTO v_listing, v_seller
    FROM public.listing_images li
    JOIN public.marketplace_listings ml ON ml.id = li.listing_id
   WHERE li.id = p_image_id;
  IF v_listing IS NULL THEN RAISE EXCEPTION 'image_not_found'; END IF;
  IF v_seller <> auth.uid() AND NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  UPDATE public.listing_images
     SET is_primary = (id = p_image_id), updated_at = now()
   WHERE listing_id = v_listing;
END $$;

GRANT EXECUTE ON FUNCTION public.set_primary_listing_image(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_primary_listing_image(uuid) TO service_role;
