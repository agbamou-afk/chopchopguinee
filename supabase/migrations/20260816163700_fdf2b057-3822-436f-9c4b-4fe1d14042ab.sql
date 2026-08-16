DROP POLICY IF EXISTS "Public read approved stores" ON public.merchant_stores;

CREATE POLICY "Anon read approved stores"
ON public.merchant_stores
FOR SELECT
TO anon
USING (status = 'active'::text AND onboarding_status = 'approved'::text);

CREATE POLICY "Auth read stores"
ON public.merchant_stores
FOR SELECT
TO authenticated
USING (
  (status = 'active'::text AND onboarding_status = 'approved'::text)
  OR owner_user_id = auth.uid()
  OR has_role(auth.uid(), 'admin'::app_role)
  OR has_role(auth.uid(), 'onboarding_specialist'::app_role)
);