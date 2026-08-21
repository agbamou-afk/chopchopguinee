-- RLS-facing predicate lives outside the reserved internal `_merchant_%` namespace.
CREATE OR REPLACE FUNCTION public.professional_merchant_active(_uid uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
  SELECT _uid IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.professional_identities pi
     WHERE pi.user_id = _uid
       AND pi.claim_state = 'active'
       AND pi.professional_type = 'merchant'
  );
$fn$;
REVOKE ALL ON FUNCTION public.professional_merchant_active(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.professional_merchant_active(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public._merchant_class_active(uuid) FROM PUBLIC, anon, authenticated;

DROP POLICY IF EXISTS "Owner updates own store" ON public.merchant_stores;
CREATE POLICY "Owner updates own store" ON public.merchant_stores FOR UPDATE TO authenticated
USING (owner_user_id = auth.uid() AND public.professional_merchant_active(auth.uid()))
WITH CHECK (owner_user_id = auth.uid() AND public.professional_merchant_active(auth.uid()));

DROP POLICY IF EXISTS "Owners update own restaurant" ON public.food_restaurants;
CREATE POLICY "Owners update own restaurant" ON public.food_restaurants FOR UPDATE
USING (auth.uid() = owner_user_id AND public.professional_merchant_active(auth.uid()))
WITH CHECK (auth.uid() = owner_user_id AND public.professional_merchant_active(auth.uid()));

DROP POLICY IF EXISTS "Owners manage own menu items" ON public.food_menu_items;
CREATE POLICY "Owners manage own menu items" ON public.food_menu_items FOR ALL
USING (EXISTS (SELECT 1 FROM public.food_restaurants r
                WHERE r.id = food_menu_items.restaurant_id AND r.owner_user_id = auth.uid())
       AND public.professional_merchant_active(auth.uid()))
WITH CHECK (EXISTS (SELECT 1 FROM public.food_restaurants r
                WHERE r.id = food_menu_items.restaurant_id AND r.owner_user_id = auth.uid())
       AND public.professional_merchant_active(auth.uid()));

DROP POLICY IF EXISTS "Sellers manage own listing images" ON public.listing_images;
CREATE POLICY "Sellers manage own listing images" ON public.listing_images FOR ALL TO authenticated
USING (EXISTS (SELECT 1 FROM public.marketplace_listings l
                WHERE l.id = listing_images.listing_id AND l.seller_id = auth.uid())
       AND public.professional_merchant_active(auth.uid()))
WITH CHECK (EXISTS (SELECT 1 FROM public.marketplace_listings l
                WHERE l.id = listing_images.listing_id AND l.seller_id = auth.uid())
       AND public.professional_merchant_active(auth.uid()));

DROP POLICY IF EXISTS "Owner manages own merchant" ON public.merchants;
CREATE POLICY "Owner manages own merchant" ON public.merchants FOR ALL
USING (owner_user_id = auth.uid() AND public.professional_merchant_active(auth.uid()))
WITH CHECK (owner_user_id = auth.uid() AND public.professional_merchant_active(auth.uid()));

-- Align the A7 suite with the renamed RLS predicate.
DO $mig$
DECLARE v_src text; v_new text;
BEGIN
  v_src := pg_get_functiondef('public._qa_node5_identity_a7()'::regprocedure);
  v_new := replace(v_src, 'v_pol ~ ''_merchant_class_active''', 'v_pol ~ ''merchant_active''');
  v_new := replace(v_new,
    'NOT has_function_privilege(''anon'',''public._merchant_class_active(uuid)'',''EXECUTE'')',
    'NOT has_function_privilege(''anon'',''public._merchant_class_active(uuid)'',''EXECUTE'')'
    || ' AND NOT has_function_privilege(''anon'',''public.professional_merchant_active(uuid)'',''EXECUTE'')');
  IF v_new = v_src THEN RAISE EXCEPTION 'A7_QA_RENAME_ANCHOR_MISSING'; END IF;
  EXECUTE v_new;
END $mig$;