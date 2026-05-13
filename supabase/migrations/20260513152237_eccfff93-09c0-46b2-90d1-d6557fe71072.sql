
-- Backfill: promote super_admin → god_admin in user_roles, etc.
INSERT INTO public.user_roles (user_id, role)
SELECT user_id, 'god_admin'::public.app_role
FROM public.admin_users
WHERE admin_role = 'super_admin' AND status = 'active'
ON CONFLICT DO NOTHING;

INSERT INTO public.user_roles (user_id, role)
SELECT user_id, 'operations_admin'::public.app_role
FROM public.admin_users
WHERE admin_role = 'ops_admin' AND status = 'active'
ON CONFLICT DO NOTHING;

INSERT INTO public.user_roles (user_id, role)
SELECT user_id, 'finance_admin'::public.app_role
FROM public.admin_users
WHERE admin_role = 'finance_admin' AND status = 'active'
ON CONFLICT DO NOTHING;

-- Backfill missing profiles for any existing auth users
INSERT INTO public.profiles (user_id, phone, email, first_name, last_name, full_name, display_name, account_status)
SELECT
  u.id,
  u.phone,
  u.email,
  COALESCE(u.raw_user_meta_data->>'first_name',
           split_part(COALESCE(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name', ''), ' ', 1)),
  u.raw_user_meta_data->>'last_name',
  COALESCE(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name'),
  COALESCE(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name', u.email, u.phone),
  'active'
FROM auth.users u
LEFT JOIN public.profiles p ON p.user_id = u.id
WHERE p.user_id IS NULL;

-- Trigger: prevent privilege escalation via user_roles inserts/updates
CREATE OR REPLACE FUNCTION public.guard_user_roles_write()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_protected text[] := ARRAY['god_admin','operations_admin','finance_admin','admin'];
BEGIN
  -- Allow service_role / superuser (no JWT) and god_admins
  IF v_caller IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.role::text = ANY (v_protected) THEN
    IF NOT public.is_god_admin(v_caller) THEN
      RAISE EXCEPTION 'Only god_admin can assign role %', NEW.role;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS guard_user_roles_write ON public.user_roles;
CREATE TRIGGER guard_user_roles_write
  BEFORE INSERT OR UPDATE ON public.user_roles
  FOR EACH ROW EXECUTE FUNCTION public.guard_user_roles_write();
