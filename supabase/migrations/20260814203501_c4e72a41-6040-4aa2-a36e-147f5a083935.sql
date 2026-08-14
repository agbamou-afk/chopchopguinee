CREATE OR REPLACE FUNCTION public._qa_node3_repas_r10_operations_fxcore()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE r jsonb;
BEGIN
  RETURN public._qa_node3_repas_r10_operations_fxcore_v2();
END; $function$;

-- v2 = v1 body with an explicit god_admin fixture row.
CREATE OR REPLACE FUNCTION public._qa_node3_repas_r10_operations_fxcore_v2()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
  RAISE EXCEPTION 'PLACEHOLDER';
END; $function$;