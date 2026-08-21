-- NODE 5 · A9 finding F1 — residual table-wide privileges on identity surfaces.
-- TRUNCATE is NOT filtered by row level security, so a client-key holder could
-- destroy account state despite correct policies. Revoke the whole class.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['user_preferences','user_roles','driver_profiles',
                           'profiles','user_pins','user_legal_consents'] LOOP
    EXECUTE format('REVOKE ALL ON public.%I FROM anon', t);
    EXECUTE format('REVOKE TRUNCATE, TRIGGER, REFERENCES, DELETE ON public.%I FROM authenticated', t);
    EXECUTE format('GRANT ALL ON public.%I TO service_role', t);
  END LOOP;
END $$;

-- keep the exact surface each table's policies already allow
GRANT SELECT, INSERT, UPDATE ON public.user_preferences   TO authenticated;
GRANT SELECT                  ON public.user_roles        TO authenticated;
GRANT SELECT, INSERT, UPDATE  ON public.driver_profiles   TO authenticated;
GRANT SELECT, INSERT, UPDATE  ON public.profiles          TO authenticated;
GRANT SELECT, INSERT, UPDATE  ON public.user_pins         TO authenticated;
GRANT SELECT, INSERT          ON public.user_legal_consents TO authenticated;
