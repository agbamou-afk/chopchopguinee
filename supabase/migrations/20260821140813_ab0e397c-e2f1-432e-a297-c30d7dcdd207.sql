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
  ok_insert boolean;
  ok_update boolean;
  sa_ok boolean;
  detail text;
  n_before bigint;
  n_after bigint;
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

  -- A17b: no policy on user_roles is exposed to anon
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

  -- fixtures
  PERFORM public._qa_users_new(u_plain, 'qa-n5a9g-p-'||substr(u_plain::text,1,8)||'@example.com');
  PERFORM public._qa_users_new(u_sa,    'qa-n5a9g-s-'||substr(u_sa::text,1,8)||'@example.com');
  UPDATE public.profiles SET phone = '+22462' || lpad((floor(random()*10000000))::bigint::text, 7, '0')
   WHERE user_id = ANY(ids) AND (phone IS NULL OR phone = '');
  INSERT INTO public.admin_users(user_id, admin_role, status)
  VALUES (u_sa, 'super_admin', 'active') ON CONFLICT DO NOTHING;

  -- A17d: ordinary authenticated user cannot INSERT a role row via direct DML (RLS)
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_plain), true);
  BEGIN
    SET LOCAL ROLE authenticated;
    BEGIN
      INSERT INTO public.user_roles(user_id, role) VALUES (u_plain, 'admin');
      ok_insert := true;
    EXCEPTION WHEN others THEN
      ok_insert := false; detail := SQLERRM;
    END;
    RESET ROLE;
  EXCEPTION WHEN others THEN
    RESET ROLE; ok_insert := false; detail := SQLERRM;
  END;
  r := r || public._qa_s13_ok(
    'N5A9.A17d ordinary signed-in user cannot INSERT a user_roles row by direct DML',
    ok_insert IS FALSE, detail);

  -- A17e: ordinary authenticated user cannot UPDATE an existing role row
  INSERT INTO public.user_roles(user_id, role) VALUES (u_plain, 'user') ON CONFLICT DO NOTHING;
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_plain), true);
  detail := NULL;
  BEGIN
    SET LOCAL ROLE authenticated;
    BEGIN
      UPDATE public.user_roles SET role = 'admin' WHERE user_id = u_plain;
      ok_update := FOUND;
    EXCEPTION WHEN others THEN
      ok_update := false; detail := SQLERRM;
    END;
    RESET ROLE;
  EXCEPTION WHEN others THEN
    RESET ROLE; ok_update := false; detail := SQLERRM;
  END;
  r := r || public._qa_s13_ok(
    'N5A9.A17e ordinary signed-in user cannot UPDATE a user_roles row by direct DML',
    ok_update IS FALSE
    AND NOT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = u_plain AND role = 'admin'),
    detail);

  -- A17f: the legitimate super-admin governance path still works
  PERFORM set_config('request.jwt.claims', public._as_user_claims(u_sa), true);
  detail := NULL;
  BEGIN
    SET LOCAL ROLE authenticated;
    BEGIN
      INSERT INTO public.user_roles(user_id, role) VALUES (u_plain, 'agent');
      sa_ok := true;
    EXCEPTION WHEN others THEN
      sa_ok := false; detail := SQLERRM;
    END;
    RESET ROLE;
  EXCEPTION WHEN others THEN
    RESET ROLE; sa_ok := false; detail := SQLERRM;
  END;
  r := r || public._qa_s13_ok(
    'N5A9.A17f super-admin governance path may still manage roles',
    sa_ok IS TRUE, detail);

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

DO $do$
DECLARE
  src text;
  old_block text;
  new_block text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO src FROM pg_proc
   WHERE proname = '_qa_node5_identity_a9'
     AND pronamespace = 'public'::regnamespace;

  old_block := '  r := r || public._qa_s13_ok(''N5A9.A17 role table stays read-only for signed-in users'','
    || E'\n' || '        has_table_privilege(''authenticated'',''public.user_roles'',''SELECT'')'
    || E'\n' || '        AND NOT has_table_privilege(''authenticated'',''public.user_roles'',''INSERT'')'
    || E'\n' || '        AND NOT has_table_privilege(''authenticated'',''public.user_roles'',''UPDATE''), NULL);';

  new_block := '  r := r || public._qa_n5a9_role_governance();';

  IF position(old_block in src) = 0 THEN
    RAISE EXCEPTION 'A17 stale assertion block not found verbatim; refusing to rewrite';
  END IF;

  EXECUTE replace(src, old_block, new_block);
END
$do$;