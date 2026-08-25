-- Repas discovery: anon must never evaluate has_role (Repas R8 invariant P15.5).
-- Split visibility exactly the way merchant_stores was split in Marché R1.

DROP POLICY IF EXISTS "Published restaurants are publicly readable" ON public.food_restaurants;
DROP POLICY IF EXISTS "Admins manage restaurants" ON public.food_restaurants;

CREATE POLICY "Anon read published restaurants"
  ON public.food_restaurants
  FOR SELECT
  TO anon
  USING (status = 'active' AND verification_state = 'verified');

CREATE POLICY "Auth read restaurants"
  ON public.food_restaurants
  FOR SELECT
  TO authenticated
  USING (
    (status = 'active' AND verification_state = 'verified')
    OR owner_user_id = auth.uid()
    OR has_role(auth.uid(), 'admin'::app_role)
  );

CREATE POLICY "Admins manage restaurants"
  ON public.food_restaurants
  FOR ALL
  TO authenticated
  USING (has_role(auth.uid(), 'admin'::app_role))
  WITH CHECK (has_role(auth.uid(), 'admin'::app_role));

GRANT SELECT ON public.food_restaurants TO anon;