-- Defect S13-D4 (P1): _finance_privileged(NULL) returned TRUE unconditionally,
-- i.e. an unauthenticated PostgREST context (auth.uid() IS NULL) satisfied the
-- privileged branch. Narrow it to genuine internal / service_role contexts.
CREATE OR REPLACE FUNCTION public._finance_privileged(p_caller uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT (
    p_caller IS NULL
    AND (
      -- no PostgREST request context at all = internal SQL / trigger / job
      COALESCE(NULLIF(current_setting('request.jwt.claims', true), ''), '') = ''
      -- or an explicit service-role key
      OR COALESCE(
           (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
           '') = 'service_role'
    )
  )
  OR public.is_god_admin(p_caller)
  OR public.has_admin_role(p_caller, 'finance_admin'::admin_role);
$$;
REVOKE ALL ON FUNCTION public._finance_privileged(uuid) FROM PUBLIC, anon, authenticated;

-- Part 1 · G1.4 refined: prove the Stage 6 gate itself (not just the role check)
CREATE OR REPLACE FUNCTION public._qa_s13_admin(p_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.admin_users(user_id, admin_role, status)
  VALUES (p_id, 'god_admin', 'active')
  ON CONFLICT (user_id) DO UPDATE SET admin_role='god_admin', status='active';
END $$;
REVOKE ALL ON FUNCTION public._qa_s13_admin(uuid) FROM PUBLIC, anon, authenticated;