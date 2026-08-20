-- =====================================================================
-- R11 QA BOARD CLOSEOUT — QA-ONLY execution topology repair.
-- No product function, table, policy, grant or feature flag is touched.
-- Root cause: 11 QA suites are SECURITY INVOKER (required: they use
-- SET LOCAL ROLE probes, which Postgres forbids inside SECURITY DEFINER)
-- and therefore execute as service_role, which has no privileges on
-- auth.users. Fix = narrow SECURITY DEFINER QA fixture helpers,
-- restricted to postgres/service_role exactly, search_path pinned.
-- =====================================================================

CREATE OR REPLACE FUNCTION public._qa_users_new(p_id uuid, p_email text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
BEGIN
  INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                          created_at, updated_at, raw_app_meta_data, raw_user_meta_data)
  VALUES ('00000000-0000-0000-0000-000000000000', p_id, 'authenticated','authenticated',
          p_email,'x', now(), now(),
          '{"provider":"email"}'::jsonb, '{}'::jsonb);
END $fn$;

CREATE OR REPLACE FUNCTION public._qa_users_purge(p_ids uuid[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
BEGIN
  DELETE FROM auth.users WHERE id = ANY(p_ids);
END $fn$;

CREATE OR REPLACE FUNCTION public._qa_users_count(p_ids uuid[])
RETURNS integer LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM auth.users WHERE id = ANY(p_ids);
  RETURN n;
END $fn$;

CREATE OR REPLACE FUNCTION public._qa_users_count_like(p_pattern text)
RETURNS integer LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM auth.users WHERE email LIKE p_pattern;
  RETURN n;
END $fn$;

CREATE OR REPLACE FUNCTION public._qa_users_ids_like(p_pattern text)
RETURNS uuid[] LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE ids uuid[];
BEGIN
  SELECT coalesce(array_agg(id), ARRAY[]::uuid[]) INTO ids
    FROM auth.users WHERE email LIKE p_pattern;
  RETURN ids;
END $fn$;

DO $acl$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public._qa_users_new(uuid, text)',
    'public._qa_users_purge(uuid[])',
    'public._qa_users_count(uuid[])',
    'public._qa_users_count_like(text)',
    'public._qa_users_ids_like(text)'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', f);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon, authenticated', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO postgres, service_role', f);
  END LOOP;
END $acl$;

-- ---------------------------------------------------------------------
-- Mechanical, assertion-preserving rewrite of the 11 blocked suites.
-- Only auth.users fixture access is redirected to the helpers above.
-- Every assertion label, count, ordering and product call is untouched;
-- function signature, volatility, security posture and ACLs are
-- preserved by CREATE OR REPLACE.
-- ---------------------------------------------------------------------
DO $mig$
DECLARE
  fn   text;
  d    text;
  nd   text;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    '_qa_node4_marche_r1','_qa_node4_marche_r15','_qa_node4_marche_r2','_qa_node4_marche_r3',
    '_qa_node4_marche_r4','_qa_node4_marche_r6','_qa_node4_marche_r65',
    '_qa_s13_run4','_qa_s13_run5','_qa_s13_run6','_qa_s13_run7_fxcore'
  ] LOOP
    SELECT pg_get_functiondef(p.oid) INTO d
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = fn;
    IF d IS NULL THEN RAISE EXCEPTION 'QA suite % not found', fn; END IF;

    nd := regexp_replace(d,
      'DELETE FROM auth\.users WHERE id IN \(([^)]*)\);',
      'PERFORM public._qa_users_purge(ARRAY[\1]);', 'g');
    nd := regexp_replace(nd,
      'SELECT count\(\*\) INTO (\w+) FROM auth\.users WHERE id IN \(([^)]*)\);',
      'SELECT public._qa_users_count(ARRAY[\2]) INTO \1;', 'g');
    nd := regexp_replace(nd,
      'SELECT count\(\*\) INTO (\w+) FROM auth\.users WHERE email LIKE (''[^'']*'');',
      'SELECT public._qa_users_count_like(\2) INTO \1;', 'g');
    nd := regexp_replace(nd,
      'IN \(SELECT id FROM auth\.users WHERE email LIKE (''[^'']*'')\)',
      '= ANY(public._qa_users_ids_like(\1))', 'g');
    nd := regexp_replace(nd,
      'INSERT INTO auth\.users \(instance_id.*?VALUES \(''00000000-0000-0000-0000-000000000000'', (\w+), ''authenticated'',''authenticated'',\s+(.*?),''x'', now\(\), now\(\),.*?''\{\}''::jsonb\);',
      'PERFORM public._qa_users_new(\1, \2);', 'g');

    IF nd = d THEN RAISE EXCEPTION 'QA suite % unchanged - rewrite pattern drift', fn; END IF;
    IF position('auth.users' in nd) > 0 THEN
      RAISE EXCEPTION 'QA suite % still references auth.users directly', fn;
    END IF;

    EXECUTE nd;
  END LOOP;
END $mig$;

-- Post-condition: none of the invoker QA suites may touch auth.users.
DO $verify$
DECLARE bad text;
BEGIN
  SELECT string_agg(proname, ', ') INTO bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname LIKE '\_qa\_%'
     AND p.prosecdef = false
     AND p.prosrc LIKE '%auth.users%';
  IF bad IS NOT NULL THEN
    RAISE EXCEPTION 'invoker QA suites still reference auth.users: %', bad;
  END IF;
END $verify$;