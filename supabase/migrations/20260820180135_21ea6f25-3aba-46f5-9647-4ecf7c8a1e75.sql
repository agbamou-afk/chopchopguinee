DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname LIKE '\_qa\_%'
  LOOP
    EXECUTE format('ALTER FUNCTION %I.%I(%s) SET statement_timeout = %L', r.nspname, r.proname, r.args, '60s');
  END LOOP;
END $$;