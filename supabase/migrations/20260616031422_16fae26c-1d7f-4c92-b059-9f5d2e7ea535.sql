
CREATE OR REPLACE FUNCTION public.map_default_confidence(_status public.map_verification_status)
RETURNS integer
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE _status
    WHEN 'unverified'      THEN 20
    WHEN 'submitted'       THEN 35
    WHEN 'field_checked'   THEN 60
    WHEN 'admin_verified'  THEN 80
    WHEN 'trusted'         THEN 95
    WHEN 'needs_review'    THEN 30
    WHEN 'duplicate'       THEN 10
    WHEN 'closed'          THEN 0
    ELSE 20
  END
$$;

REVOKE EXECUTE ON FUNCTION public.map_default_confidence(public.map_verification_status) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.map_default_confidence(public.map_verification_status) TO authenticated, service_role;
