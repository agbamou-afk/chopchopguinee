-- Tighten realtime messages SELECT policy: remove public:% wildcard, restrict to user-scoped topics
DROP POLICY IF EXISTS "Authenticated can read own topic messages" ON realtime.messages;
CREATE POLICY "Authenticated can read own topic messages"
ON realtime.messages
FOR SELECT
TO authenticated
USING (
  realtime.topic() IS NULL
  OR realtime.topic() = (auth.uid())::text
  OR realtime.topic() = 'user:' || (auth.uid())::text
  OR realtime.topic() LIKE 'private:' || (auth.uid())::text || ':%'
);

-- Add DELETE policies for driver-docs bucket (driver owns folder, ops admins can delete)
CREATE POLICY "Drivers delete own docs"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'driver-docs'
  AND (auth.uid())::text = (storage.foldername(name))[1]
);

CREATE POLICY "Admins delete driver docs"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'driver-docs'
  AND can_manage_operations(auth.uid())
);