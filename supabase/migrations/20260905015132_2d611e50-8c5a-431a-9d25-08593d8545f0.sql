-- G2.A — Canonical role resolution, fail closed.

CREATE OR REPLACE FUNCTION public.admin_role_classes(_uid uuid)
RETURNS text[]
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT COALESCE(array_agg(DISTINCT c ORDER BY c), ARRAY[]::text[])
  FROM (
    SELECT CASE ur.role::text
             WHEN 'god_admin'        THEN 'god_admin'
             WHEN 'finance_admin'    THEN 'finance_admin'
             WHEN 'operations_admin' THEN 'operations_admin'
             ELSE NULL            -- bare 'admin' and every other app_role: NO authority
           END AS c
    FROM public.user_roles ur
    WHERE ur.user_id = _uid
    UNION ALL
    SELECT CASE au.admin_role::text
             WHEN 'god_admin'        THEN 'god_admin'
             WHEN 'super_admin'      THEN 'god_admin'
             WHEN 'ops_admin'        THEN 'operations_admin'
             WHEN 'operations_admin' THEN 'operations_admin'
             WHEN 'support_admin'    THEN 'operations_admin'
             WHEN 'finance_admin'    THEN 'finance_admin'
             ELSE NULL
           END
    FROM public.admin_users au
    WHERE au.user_id = _uid AND au.status = 'active'
  ) s
  WHERE c IS NOT NULL;
$function$;

CREATE OR REPLACE FUNCTION public.admin_role_canonical(_uid uuid DEFAULT auth.uid())
RETURNS text
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_classes text[];
BEGIN
  IF _uid IS NULL THEN RETURN NULL; END IF;
  -- Node 5: a closed/deleted caller resolving itself has no authority.
  IF _uid = auth.uid() AND public.auth_uid_active() IS NULL THEN RETURN NULL; END IF;
  IF EXISTS (SELECT 1 FROM public.profiles p
              WHERE p.user_id = _uid AND p.account_status = 'deleted') THEN
    RETURN NULL;
  END IF;
  v_classes := public.admin_role_classes(_uid);
  IF array_length(v_classes, 1) IS DISTINCT FROM 1 THEN
    RETURN NULL;  -- zero authority, or a cross-source class conflict: fail closed.
  END IF;
  RETURN v_classes[1];
END;
$function$;

COMMENT ON FUNCTION public.admin_role_canonical(uuid) IS
  'G2 constitutional resolver. Single canonical class or NULL. Bare user_roles.admin grants nothing. Class conflict = deny.';

CREATE OR REPLACE FUNCTION public.admin_role_diagnose(_uid uuid DEFAULT auth.uid())
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_classes text[]; v_reason text;
BEGIN
  IF _uid IS NULL THEN RETURN jsonb_build_object('role', NULL, 'reason', 'no_caller'); END IF;
  IF EXISTS (SELECT 1 FROM public.profiles p WHERE p.user_id=_uid AND p.account_status='deleted') THEN
    RETURN jsonb_build_object('role', NULL, 'reason', 'account_closed');
  END IF;
  v_classes := public.admin_role_classes(_uid);
  v_reason := CASE
    WHEN COALESCE(array_length(v_classes,1),0) = 0 THEN 'no_admin_class'
    WHEN array_length(v_classes,1) > 1 THEN 'class_conflict'
    ELSE 'resolved' END;
  RETURN jsonb_build_object(
    'role', CASE WHEN array_length(v_classes,1) = 1 THEN v_classes[1] ELSE NULL END,
    'classes', to_jsonb(v_classes),
    'reason', v_reason);
END;
$function$;

-- Legacy helpers now derive from the canonical law. None may treat bare 'admin' as God.
CREATE OR REPLACE FUNCTION public._is_god_admin(_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$ SELECT public.admin_role_canonical(_user) = 'god_admin'; $function$;

CREATE OR REPLACE FUNCTION public.is_god_admin(_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$ SELECT public.admin_role_canonical(_user_id) = 'god_admin'; $function$;

CREATE OR REPLACE FUNCTION public._is_ops_or_god_admin(_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$ SELECT public.admin_role_canonical(_user) IN ('god_admin','operations_admin'); $function$;

CREATE OR REPLACE FUNCTION public.can_manage_operations(_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$ SELECT public.admin_role_canonical(_user_id) IN ('god_admin','operations_admin'); $function$;

CREATE OR REPLACE FUNCTION public.can_manage_wallet(_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$ SELECT public.admin_role_canonical(_user_id) IN ('god_admin','finance_admin'); $function$;

CREATE OR REPLACE FUNCTION public.is_any_admin(_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$ SELECT public.admin_role_canonical(_user_id) IS NOT NULL; $function$;

CREATE OR REPLACE FUNCTION public.has_admin_role(_user_id uuid, _role admin_role)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT public.admin_role_canonical(_user_id) = CASE _role::text
    WHEN 'god_admin' THEN 'god_admin'
    WHEN 'super_admin' THEN 'god_admin'
    WHEN 'ops_admin' THEN 'operations_admin'
    WHEN 'operations_admin' THEN 'operations_admin'
    WHEN 'support_admin' THEN 'operations_admin'
    WHEN 'finance_admin' THEN 'finance_admin'
    ELSE NULL END;
$function$;

-- Preserves internal/service-role execution required by frozen finance architecture.
CREATE OR REPLACE FUNCTION public._finance_privileged(p_caller uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT (
    p_caller IS NULL
    AND (
      COALESCE(NULLIF(current_setting('request.jwt.claims', true), ''), '') = ''
      OR COALESCE((NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'), '') = 'service_role'
    )
  )
  OR public.admin_role_canonical(p_caller) IN ('god_admin','finance_admin');
$function$;

REVOKE EXECUTE ON FUNCTION public.admin_role_classes(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_role_classes(uuid) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.admin_role_diagnose(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_role_diagnose(uuid) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.admin_role_canonical(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_role_canonical(uuid) TO authenticated, service_role;