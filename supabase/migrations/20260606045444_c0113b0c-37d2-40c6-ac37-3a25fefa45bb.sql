
-- Merchant onboarding: add verification doc paths, location metadata, and app mode
ALTER TABLE public.merchant_stores
  ADD COLUMN IF NOT EXISTS address_label text,
  ADD COLUMN IF NOT EXISTS landmark text,
  ADD COLUMN IF NOT EXISTS location_source text CHECK (location_source IS NULL OR location_source IN ('current_location','manual_pin')),
  ADD COLUMN IF NOT EXISTS location_accuracy_m double precision,
  ADD COLUMN IF NOT EXISTS location_confirmed_at timestamptz,
  ADD COLUMN IF NOT EXISTS id_photo_path text,
  ADD COLUMN IF NOT EXISTS selfie_photo_path text,
  ADD COLUMN IF NOT EXISTS storefront_photo_path text;

-- Default onboarding_status for newly-created stores should be 'submitted' (review),
-- but keep current default to avoid breaking specialist-created records.
ALTER TABLE public.merchant_stores ALTER COLUMN onboarding_status SET DEFAULT 'submitted';

-- User preferences: app mode + merchant slides completion
ALTER TABLE public.user_preferences
  ADD COLUMN IF NOT EXISTS app_mode text NOT NULL DEFAULT 'client' CHECK (app_mode IN ('client','merchant','driver')),
  ADD COLUMN IF NOT EXISTS merchant_slides_completed_at timestamptz;

-- Visibility enforcement trigger: pending stores cannot publish public listings
CREATE OR REPLACE FUNCTION public.enforce_listing_visibility()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_store_status text;
  v_onboarding_status text;
BEGIN
  IF NEW.store_id IS NULL THEN
    RETURN NEW;
  END IF;
  SELECT status, onboarding_status INTO v_store_status, v_onboarding_status
  FROM public.merchant_stores WHERE id = NEW.store_id;
  IF v_store_status IS DISTINCT FROM 'active' OR v_onboarding_status IS DISTINCT FROM 'approved' THEN
    NEW.visibility := 'private';
    NEW.status := 'pending_review'::listing_status;
  END IF;
  RETURN NEW;
END;
$$;

-- Make sure 'pending_review' value exists; if not, fall back to draft.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    WHERE t.typname = 'listing_status' AND e.enumlabel = 'pending_review'
  ) THEN
    -- Replace trigger body to use 'draft' instead
    CREATE OR REPLACE FUNCTION public.enforce_listing_visibility()
    RETURNS trigger
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public
    AS $f$
    DECLARE
      v_store_status text;
      v_onboarding_status text;
    BEGIN
      IF NEW.store_id IS NULL THEN
        RETURN NEW;
      END IF;
      SELECT status, onboarding_status INTO v_store_status, v_onboarding_status
      FROM public.merchant_stores WHERE id = NEW.store_id;
      IF v_store_status IS DISTINCT FROM 'active' OR v_onboarding_status IS DISTINCT FROM 'approved' THEN
        NEW.visibility := 'private';
      END IF;
      RETURN NEW;
    END;
    $f$;
  END IF;
END$$;

DROP TRIGGER IF EXISTS enforce_listing_visibility_trg ON public.marketplace_listings;
CREATE TRIGGER enforce_listing_visibility_trg
BEFORE INSERT OR UPDATE OF visibility, status, store_id
ON public.marketplace_listings
FOR EACH ROW EXECUTE FUNCTION public.enforce_listing_visibility();

-- Storage RLS for merchant-docs (private bucket)
DROP POLICY IF EXISTS "Merchant docs: owner insert" ON storage.objects;
DROP POLICY IF EXISTS "Merchant docs: owner read" ON storage.objects;
DROP POLICY IF EXISTS "Merchant docs: owner update" ON storage.objects;
DROP POLICY IF EXISTS "Merchant docs: owner delete" ON storage.objects;
DROP POLICY IF EXISTS "Merchant docs: admin read" ON storage.objects;

CREATE POLICY "Merchant docs: owner insert"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'merchant-docs'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "Merchant docs: owner read"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'merchant-docs'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "Merchant docs: owner update"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'merchant-docs'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "Merchant docs: owner delete"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'merchant-docs'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "Merchant docs: admin read"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'merchant-docs'
  AND (public.has_role(auth.uid(), 'admin'::app_role)
       OR public.has_role(auth.uid(), 'onboarding_specialist'::app_role))
);
