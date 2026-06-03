
-- Restrict service_profiles to active+public listings for anonymous/public view
ALTER TABLE public.service_profiles
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'draft',
  ADD COLUMN IF NOT EXISTS visibility text NOT NULL DEFAULT 'private';

ALTER TABLE public.service_profiles
  DROP CONSTRAINT IF EXISTS service_profiles_status_check;
ALTER TABLE public.service_profiles
  ADD CONSTRAINT service_profiles_status_check
  CHECK (status IN ('draft','active','suspended','archived'));

ALTER TABLE public.service_profiles
  DROP CONSTRAINT IF EXISTS service_profiles_visibility_check;
ALTER TABLE public.service_profiles
  ADD CONSTRAINT service_profiles_visibility_check
  CHECK (visibility IN ('private','public'));

DROP POLICY IF EXISTS "Anyone view services" ON public.service_profiles;

CREATE POLICY "Public view active public services"
  ON public.service_profiles FOR SELECT
  USING (status = 'active' AND visibility = 'public');
