
-- 1. Extend app_role enum with the unified role set
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'recharge_agent';
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'operations_admin';
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'finance_admin';
ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'god_admin';

-- 2. Extend profiles with personal info + status
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS first_name text,
  ADD COLUMN IF NOT EXISTS last_name text,
  ADD COLUMN IF NOT EXISTS display_name text,
  ADD COLUMN IF NOT EXISTS email text,
  ADD COLUMN IF NOT EXISTS account_status text NOT NULL DEFAULT 'active';

-- 3. Helper functions (use text cast so they don't bind to enum values until runtime)
CREATE OR REPLACE FUNCTION public.has_app_role(_user_id uuid, _role text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _user_id AND role::text = _role
  );
$$;

CREATE OR REPLACE FUNCTION public.is_any_admin(_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _user_id
      AND role::text IN ('admin','god_admin','operations_admin','finance_admin')
  );
$$;

CREATE OR REPLACE FUNCTION public.is_god_admin(_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _user_id AND role::text = 'god_admin'
  );
$$;

-- 4. Make is_admin recognise unified admin roles too
CREATE OR REPLACE FUNCTION public.is_admin(_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_users WHERE user_id = _user_id AND status = 'active'
  ) OR EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = _user_id
      AND role::text IN ('admin','god_admin','operations_admin','finance_admin')
  );
$$;

-- 5. Updated handle_new_user: capture first/last/email + assign client role
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_first text := NEW.raw_user_meta_data->>'first_name';
  v_last  text := NEW.raw_user_meta_data->>'last_name';
  v_full  text := COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name');
BEGIN
  IF (v_first IS NULL OR v_first = '') AND v_full IS NOT NULL THEN
    v_first := split_part(v_full, ' ', 1);
    v_last  := COALESCE(NULLIF(substring(v_full FROM position(' ' IN v_full) + 1), ''), v_last);
  END IF;

  INSERT INTO public.profiles (user_id, phone, email, first_name, last_name, full_name, display_name)
  VALUES (
    NEW.id,
    NEW.phone,
    NEW.email,
    v_first,
    v_last,
    COALESCE(v_full, NULLIF(trim(coalesce(v_first,'') || ' ' || coalesce(v_last,'')), '')),
    COALESCE(v_full, NULLIF(trim(coalesce(v_first,'') || ' ' || coalesce(v_last,'')), ''))
  )
  ON CONFLICT (user_id) DO NOTHING;

  INSERT INTO public.wallets (owner_user_id, party_type)
  VALUES (NEW.id, 'client')
  ON CONFLICT (owner_user_id, party_type) DO NOTHING;

  -- Default base role
  INSERT INTO public.user_roles (user_id, role)
  VALUES (NEW.id, 'client'::public.app_role)
  ON CONFLICT DO NOTHING;

  RETURN NEW;
END;
$$;

-- Ensure trigger exists
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
