CREATE OR REPLACE FUNCTION public._g3_legacy_role(_class text)
RETURNS public.admin_role
LANGUAGE sql IMMUTABLE
SET search_path TO 'public'
AS $$ SELECT CASE _class WHEN 'operations_admin' THEN 'ops_admin'::public.admin_role
                         WHEN 'finance_admin'    THEN 'finance_admin'::public.admin_role END; $$;

REVOKE ALL ON FUNCTION public._g3_legacy_role(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._g3_legacy_role(text) TO service_role;

REVOKE ALL ON FUNCTION public._g3_active_god_count(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._g3_active_god_count(uuid) TO service_role;

REVOKE ALL ON FUNCTION public._g3_lifecycle_guard() FROM PUBLIC, anon, authenticated;