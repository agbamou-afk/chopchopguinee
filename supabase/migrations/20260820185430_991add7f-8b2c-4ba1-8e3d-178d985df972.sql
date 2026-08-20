CREATE OR REPLACE FUNCTION public._qa_auth_user_count()
RETURNS bigint LANGUAGE sql SECURITY DEFINER SET search_path = public
SET statement_timeout TO '60s' AS $$
  SELECT count(*) FROM auth.users;
$$;
REVOKE ALL ON FUNCTION public._qa_auth_user_count() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._qa_n4r12_orphan_admins()
RETURNS bigint LANGUAGE sql SECURITY DEFINER SET search_path = public
SET statement_timeout TO '60s' AS $$
  SELECT count(*) FROM public.admin_users a
   WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = a.user_id);
$$;
REVOKE ALL ON FUNCTION public._qa_n4r12_orphan_admins() FROM PUBLIC, anon, authenticated;