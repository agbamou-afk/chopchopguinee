DROP FUNCTION IF EXISTS public._qa_node3_repas_r5_runtime();

CREATE OR REPLACE FUNCTION public._qa_node3_repas_r5_runtime()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_out jsonb;
BEGIN
  PERFORM set_config('app.repas_publication_ctx', '1', true);
  v_out := public._qa_node3_repas_r5_runtime_core();
  PERFORM set_config('app.repas_publication_ctx', '', true);
  RETURN v_out;
END;
$$;

REVOKE ALL ON FUNCTION public._qa_node3_repas_r5_runtime() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node3_repas_r5_runtime() TO service_role;