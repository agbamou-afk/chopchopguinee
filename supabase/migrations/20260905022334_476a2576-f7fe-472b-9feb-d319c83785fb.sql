DO $$
DECLARE w record; d text;
BEGIN
  FOR w IN SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='public' AND p.prosrc LIKE '%public.public.%'
  LOOP
    d := replace(pg_get_functiondef(w.oid), 'public.public.', 'public.');
    EXECUTE d;
  END LOOP;
END $$;