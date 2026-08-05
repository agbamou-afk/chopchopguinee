CREATE OR REPLACE FUNCTION public._qa_ccd_shim(
  p_ignored text, p_source_module text, p_source_id uuid, p_customer uuid,
  p_mission_type text, p_stage text, p_basis_gnf bigint,
  p_exempt_reason text DEFAULT NULL, p_is_sandbox boolean DEFAULT false)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT public.customer_cancellation_debt_create(
    p_source_module, p_source_id, p_customer, p_mission_type, p_stage,
    p_basis_gnf, p_exempt_reason, p_is_sandbox);
$$;

CREATE OR REPLACE FUNCTION public.customer_cancellation_debt_create(
  p_ignored text, p_source_module text, p_source_id uuid, p_customer uuid,
  p_mission_type text, p_stage text, p_basis_gnf bigint,
  p_exempt_reason text DEFAULT NULL, p_is_sandbox boolean DEFAULT false)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT public._qa_ccd_shim(p_ignored, p_source_module, p_source_id, p_customer,
                             p_mission_type, p_stage, p_basis_gnf, p_exempt_reason, p_is_sandbox);
$$;