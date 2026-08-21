CREATE OR REPLACE FUNCTION public._qa_n5a9_role_governance()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET statement_timeout = '300s'
AS $fn$
DECLARE
  r jsonb := '[]'::jsonb;
  u_plain uuid := gen_random_uuid();
  u_sa    uuid := gen_random_uuid();
  ids uuid[];
  n_before bigint;
  n_after bigint;
  plain_pass boolean;
  sa_pass boolean;
BEGIN
  ids := ARRAY[u_plain, u_sa];
  SELECT count(*) INTO n_before FROM public.user_roles;

  -- A17a: every mutating policy on user_roles is governance-scoped (super-admin only)
  r := r || public._qa_s13_ok(
    'N5A9.A17a user_roles mutation policies are governance-scoped, not open',
    NOT EXISTS (
      SELECT 1 FROM pg_policies
       WHERE schemaname='public' AND tablename='user_roles' AND cmd <> 'SELECT'
         AND (COALESCE(qual,'') !~ 'has_admin_role' OR COALESCE(with_check,'') !~ 'has_admin_role')
    ),
    (SELECT string_agg(policyname||':'||cmd, ',') FROM pg_policies
      WHERE schemaname='public' AND tablename='user_roles' AND cmd <> 'SELECT'));

  -- A17b: anon is on no policy and holds no mutation grant
  r := r || public._qa_s13_ok(
    'N5A9.A17b no user_roles policy is exposed to anon and anon holds no mutation grant',
    NOT EXISTS (SELECT 1 FROM pg_policies
                 WHERE schemaname='public' AND tablename='user_roles'
                   AND 'anon' = ANY(roles))
    AND NOT has_table_privilege('anon','public.user_roles','INSERT')
    AND NOT has_table_privilege('anon','public.user_roles','UPDATE')
    AND NOT has_table_privilege('anon','public.user_roles','DELETE'), NULL);

  -- A17c: destructive privileges absent for signed-in clients
  r := r || public._qa_s13_ok(
    'N5A9.A17c signed-in clients hold no DELETE or TRUNCATE on user_roles',
    NOT has_table_privilege('authenticated','public.user_roles','DELETE')
    AND NOT has_table_privilege('authenticated','public.user_roles','TRUNCATE'), NULL);

  -- A17d: the table grant is meaningless without RLS — RLS must be enabled
  r := r || public._qa_s13_ok(
    'N5A9.A17d user_roles enforces row level security so the INSERT/UPDATE grant is policy-bound',
    (SELECT c.relrowsecurity FROM pg_class c
      WHERE c.oid = 'public.user_roles'::regclass), NULL);

  -- fixtures
  PERFORM public._qa_users_new(u_plain, 'qa-n5a9g-p-'||substr(u_plain::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_sa,    'qa-n5a9g-s-'||substr(u_sa::text,1,8)||'@example.com');
  UPDATE public.profiles SET phone = '+22462' || lpad((floor(random()*10000000))::bigint::text, 7, '0')
   WHERE user_id = ANY(ids) AND (phone IS NULL OR phone = '');
  INSERT INTO public.admin_users(user_id, admin_role, status)
  VALUES (u_sa, 'super_admin', 'active') ON CONFLICT DO NOTHING;

  -- A17e: an ordinary signed-in user fails the governance predicate of every
  -- mutating policy, so no direct INSERT/UPDATE of a role row can pass RLS
  plain_pass := public.has_admin_role(u_plain, 'super_admin'::admin_role);
  r := r || public._qa_s13_ok(
    'N5A9.A17e ordinary signed-in user fails the user_roles governance predicate (no direct role write)',
    plain_pass IS FALSE
    AND NOT public.has_role(u_plain, 'admin'::app_role), NULL);

  -- A17f: the legitimate super-admin governance path still evaluates true
  sa_pass := public.has_admin_role(u_sa, 'super_admin'::admin_role);
  r := r || public._qa_s13_ok(
    'N5A9.A17f super-admin governance path may still manage roles',
    sa_pass IS TRUE, NULL);

  -- cleanup
  PERFORM set_config('request.jwt.claims', NULL, true);
  DELETE FROM public.user_roles WHERE user_id = ANY(ids);
  DELETE FROM public.admin_users WHERE user_id = ANY(ids);
  PERFORM public._qa_a5_cleanup(ids);

  SELECT count(*) INTO n_after FROM public.user_roles;
  r := r || public._qa_s13_ok(
    'N5A9.A17g role governance probe left zero residue',
    n_after = n_before
    AND NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = ANY(ids))
    AND NOT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = ANY(ids)),
    n_before::text||'->'||n_after::text);

  RETURN r;
END;
$fn$;

REVOKE ALL ON FUNCTION public._qa_n5a9_role_governance() FROM PUBLIC, anon, authenticated;