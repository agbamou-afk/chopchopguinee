-- Add missing FK so PostgREST can embed marketplace_listings from listing_interests
ALTER TABLE public.listing_interests
  ADD CONSTRAINT listing_interests_listing_id_fkey
  FOREIGN KEY (listing_id) REFERENCES public.marketplace_listings(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS listing_interests_listing_id_idx ON public.listing_interests(listing_id);
CREATE INDEX IF NOT EXISTS listing_interests_seller_id_idx ON public.listing_interests(seller_id);

-- Refresh PostgREST schema cache
NOTIFY pgrst, 'reload schema';