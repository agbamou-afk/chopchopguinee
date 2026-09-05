-- G2 fail-closed correction: NULL is not a denial in `IF NOT x THEN raise` guards.
-- Every canonical authority predicate must return a strict boolean.
CREATE OR REPLACE FUNCTION public.is_god_admin(_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT COALESCE(public.admin_role_canonical(_user_id) = 'god_admin', false); $$;

CREATE OR REPLACE FUNCTION public._is_god_admin(_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT COALESCE(public.admin_role_canonical(_user) = 'god_admin', false); $$;

CREATE OR REPLACE FUNCTION public._is_ops_or_god_admin(_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT COALESCE(public.admin_role_canonical(_user) IN ('god_admin','operations_admin'), false); $$;

CREATE OR REPLACE FUNCTION public.can_manage_operations(_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT COALESCE(public.admin_role_canonical(_user_id) IN ('god_admin','operations_admin'), false); $$;

CREATE OR REPLACE FUNCTION public.can_manage_wallet(_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT COALESCE(public.admin_role_canonical(_user_id) IN ('god_admin','finance_admin'), false); $$;

CREATE OR REPLACE FUNCTION public.is_any_admin(_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT public.admin_role_canonical(_user_id) IS NOT NULL; $$;

CREATE OR REPLACE FUNCTION public.has_admin_role(_user_id uuid, _role admin_role)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT COALESCE(public.admin_role_canonical(_user_id) = CASE _role::text
    WHEN 'god_admin' THEN 'god_admin'
    WHEN 'super_admin' THEN 'god_admin'
    WHEN 'ops_admin' THEN 'operations_admin'
    WHEN 'operations_admin' THEN 'operations_admin'
    WHEN 'support_admin' THEN 'operations_admin'
    WHEN 'finance_admin' THEN 'finance_admin'
    ELSE NULL END, false);
$$;

CREATE OR REPLACE FUNCTION public._finance_privileged(p_caller uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT COALESCE((
    p_caller IS NULL AND (
      COALESCE(NULLIF(current_setting('request.jwt.claims', true), ''), '') = ''
      OR COALESCE((NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'), '') = 'service_role')
  ) OR public.admin_role_canonical(p_caller) IN ('god_admin','finance_admin'), false);
$$;

CREATE OR REPLACE FUNCTION public.admin_capability(_capability text, _uid uuid DEFAULT auth.uid())
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT COALESCE(public.admin_capability_mode(_capability, _uid) = 'allow', false); $$;

-- Belt and braces: the role-write guard must deny on any non-true answer.
CREATE OR REPLACE FUNCTION public.guard_user_roles_write()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_protected text[] := ARRAY['god_admin','operations_admin','finance_admin','admin'];
BEGIN
  IF v_caller IS NULL THEN
    RETURN NEW;  -- service_role / migration execution
  END IF;
  IF NEW.role::text = ANY (v_protected) THEN
    IF public.is_god_admin(v_caller) IS NOT TRUE THEN
      RAISE EXCEPTION 'Only god_admin can assign role %', NEW.role USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;