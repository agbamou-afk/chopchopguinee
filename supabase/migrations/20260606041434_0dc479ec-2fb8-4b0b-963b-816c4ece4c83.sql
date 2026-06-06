
-- profile-avatars storage policies. Path convention: {user_id}/avatar.{ext}
DROP POLICY IF EXISTS "profile_avatars_select_auth" ON storage.objects;
DROP POLICY IF EXISTS "profile_avatars_insert_own" ON storage.objects;
DROP POLICY IF EXISTS "profile_avatars_update_own" ON storage.objects;
DROP POLICY IF EXISTS "profile_avatars_delete_own" ON storage.objects;

CREATE POLICY "profile_avatars_select_auth"
  ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'profile-avatars');

CREATE POLICY "profile_avatars_insert_own"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'profile-avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "profile_avatars_update_own"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'profile-avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
  )
  WITH CHECK (
    bucket_id = 'profile-avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "profile_avatars_delete_own"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'profile-avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );
