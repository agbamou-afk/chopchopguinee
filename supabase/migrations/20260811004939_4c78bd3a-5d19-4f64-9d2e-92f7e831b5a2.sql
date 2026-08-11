REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.package_evidence_photos FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON public.package_runtime FROM anon, authenticated;
REVOKE SELECT ON public.package_evidence_photos FROM anon;
REVOKE SELECT ON public.package_runtime FROM anon;

GRANT SELECT ON public.package_evidence_photos TO authenticated;
GRANT SELECT ON public.package_runtime TO authenticated;
GRANT ALL ON public.package_evidence_photos TO service_role;
GRANT ALL ON public.package_runtime TO service_role;