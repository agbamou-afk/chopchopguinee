CREATE OR REPLACE FUNCTION public._admin_capability_registry_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  -- Governance law: the constitutional registry is changeable only by system
  -- migrations / service execution, never from an authenticated browser session
  -- (not even God Admin). Deny by default.
  IF NOT public._g2_internal_caller() THEN
    RAISE EXCEPTION 'capability_registry_immutable_from_session' USING ERRCODE = '42501';
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$function$;

DROP TRIGGER IF EXISTS trg_admin_capability_registry_guard ON public.admin_capability_grants;
CREATE TRIGGER trg_admin_capability_registry_guard
  BEFORE INSERT OR UPDATE OR DELETE ON public.admin_capability_grants
  FOR EACH ROW EXECUTE FUNCTION public._admin_capability_registry_guard();