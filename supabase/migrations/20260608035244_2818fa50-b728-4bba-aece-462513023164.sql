
-- =====================================================================
-- 1) Fix driver-group-checkins storage policies
--    The previous policies referenced unqualified `name` inside a
--    subquery that aliases driver_groups as g, so Postgres resolved
--    `name` to g.name (the group's text name) instead of the storage
--    object's name. This effectively granted cross-group access.
--    We re-create the policies using a fully qualified
--    `storage.objects.name` reference.
-- =====================================================================

DROP POLICY IF EXISTS "dgci leaders upload own group" ON storage.objects;
CREATE POLICY "dgci leaders upload own group"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'driver-group-checkins'
    AND EXISTS (
      SELECT 1 FROM public.driver_groups g
      WHERE g.id::text = (storage.foldername(storage.objects.name))[1]
        AND g.leader_user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "dgci leaders read own group" ON storage.objects;
CREATE POLICY "dgci leaders read own group"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'driver-group-checkins'
    AND (
      public._is_ops_or_god_admin(auth.uid())
      OR EXISTS (
        SELECT 1 FROM public.driver_groups g
        WHERE g.id::text = (storage.foldername(storage.objects.name))[1]
          AND g.leader_user_id = auth.uid()
      )
    )
  );

-- (admins manage policy already correct — keep as-is)

-- =====================================================================
-- 2) Tighten profile-avatars storage SELECT — owner-only.
--    Other users continue to render avatars via signed URLs stored on
--    profiles.avatar_url, which bypass RLS via storage's signing layer.
-- =====================================================================

DROP POLICY IF EXISTS "profile_avatars_select_auth" ON storage.objects;
CREATE POLICY "profile_avatars_select_own"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'profile-avatars'
    AND (auth.uid())::text = (storage.foldername(storage.objects.name))[1]
  );

-- =====================================================================
-- 3) Lock down app_settings: admins only.
--    Frontend does not read this table; only the om-import-csv edge
--    function does, and that runs with the service role (bypasses RLS).
-- =====================================================================

DROP POLICY IF EXISTS "Authenticated read app_settings" ON public.app_settings;
DROP POLICY IF EXISTS "Anyone read app_settings" ON public.app_settings;

CREATE POLICY "Admins read app_settings"
  ON public.app_settings FOR SELECT TO authenticated
  USING (public.is_any_admin(auth.uid()));
