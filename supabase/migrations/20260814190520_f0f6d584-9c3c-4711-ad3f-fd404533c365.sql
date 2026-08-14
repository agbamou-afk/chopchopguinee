-- R8 fallout fix: the R5 runtime QA harness seeds a 'suspended' restaurant fixture,
-- which the new staff-only publication guard rejects. Wrap the existing harness in an
-- explicit privileged seeding context instead of weakening the guard.
ALTER FUNCTION public._qa_node3_repas_r5_runtime() RENAME TO _qa_node3_repas_r5_runtime_core;

CREATE OR REPLACE FUNCTION public._qa_node3_repas_r5_runtime()
RETURNS TABLE(ok boolean, label text, detail text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  PERFORM set_config('app.repas_publication_ctx', '1', true);
  RETURN QUERY SELECT * FROM public._qa_node3_repas_r5_runtime_core();
  PERFORM set_config('app.repas_publication_ctx', '', true);
END;
$$;

REVOKE ALL ON FUNCTION public._qa_node3_repas_r5_runtime() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._qa_node3_repas_r5_runtime_core() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node3_repas_r5_runtime() TO service_role;
GRANT EXECUTE ON FUNCTION public._qa_node3_repas_r5_runtime_core() TO service_role;