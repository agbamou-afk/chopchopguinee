REVOKE EXECUTE ON FUNCTION public.has_role(uuid, public.app_role) FROM anon;

DROP POLICY IF EXISTS "Admins manage listings" ON public.marketplace_listings;
CREATE POLICY "Admins manage listings" ON public.marketplace_listings
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::public.app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Public read approved listings" ON public.marketplace_listings;
CREATE POLICY "Public read approved listings" ON public.marketplace_listings
  FOR SELECT TO anon, authenticated
  USING (
    (
      status = 'active'::public.listing_status
      AND visibility = 'public'
      AND (
        store_id IS NULL
        OR EXISTS (
          SELECT 1 FROM public.merchant_stores s
           WHERE s.id = marketplace_listings.store_id
             AND s.status = 'active'
             AND s.onboarding_status = 'approved'
        )
      )
    )
    OR seller_id = auth.uid()
  );

DROP POLICY IF EXISTS "Admins manage listing images" ON public.listing_images;
CREATE POLICY "Admins manage listing images" ON public.listing_images
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::public.app_role))
  WITH CHECK (public.has_role(auth.uid(), 'admin'::public.app_role));

DROP POLICY IF EXISTS "Sellers manage own listing images" ON public.listing_images;
CREATE POLICY "Sellers manage own listing images" ON public.listing_images
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.marketplace_listings l
                  WHERE l.id = listing_images.listing_id AND l.seller_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.marketplace_listings l
                  WHERE l.id = listing_images.listing_id AND l.seller_id = auth.uid()));

DROP POLICY IF EXISTS "Public read images of public listings" ON public.listing_images;
CREATE POLICY "Public read images of public listings" ON public.listing_images
  FOR SELECT TO anon, authenticated
  USING (
    public.marche_listing_is_public(listing_id)
    OR EXISTS (SELECT 1 FROM public.marketplace_listings l
                WHERE l.id = listing_images.listing_id AND l.seller_id = auth.uid())
  );