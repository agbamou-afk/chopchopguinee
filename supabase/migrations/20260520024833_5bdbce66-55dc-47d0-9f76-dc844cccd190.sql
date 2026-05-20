
-- Helper: does a driver have a given capability?
CREATE OR REPLACE FUNCTION public.driver_has_capability(_user_id uuid, _capability text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.driver_profiles dp
    WHERE dp.user_id = _user_id
      AND _capability = ANY (dp.capabilities)
      AND dp.status = 'approved'
  );
$$;

-- Map mission type -> required capability
CREATE OR REPLACE FUNCTION public.mission_required_capability(_type public.mission_type)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE _type
    WHEN 'food_delivery' THEN 'repas_delivery'
    WHEN 'marketplace_delivery' THEN 'marche_delivery'
    WHEN 'package_delivery' THEN 'package_delivery'
    WHEN 'ride' THEN 'rides_moto'
  END;
$$;

-- Couriers see unassigned missions matching their capability
CREATE POLICY "Eligible couriers read available missions" ON public.missions
  FOR SELECT
  USING (
    courier_id IS NULL
    AND state = 'assigned'
    AND public.driver_has_capability(auth.uid(), public.mission_required_capability(type))
  );

-- Couriers claim unassigned missions matching their capability
CREATE POLICY "Eligible couriers claim missions" ON public.missions
  FOR UPDATE
  USING (
    courier_id IS NULL
    AND public.driver_has_capability(auth.uid(), public.mission_required_capability(type))
  )
  WITH CHECK (
    courier_id = auth.uid()
  );
