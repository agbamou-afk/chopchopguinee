DO $g$
DECLARE f record;
BEGIN
  FOR f IN
    SELECT oid::regprocedure::text AS sig FROM pg_proc
     WHERE pronamespace = 'public'::regnamespace
       AND proname LIKE '\_qa\_%'
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', f.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', f.sig);
  END LOOP;
END $g$;
