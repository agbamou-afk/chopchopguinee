DO $$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_s13_run5';
  d := replace(d, '''SELECT public._g2i_admin_', '''SELECT public.admin_');
  EXECUTE d;

  SELECT pg_get_functiondef(p.oid) INTO d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_s13_run7_fxcore';
  d := replace(d, '''public._g2i_admin_anonymize_user(', '''public.admin_anonymize_user(');
  EXECUTE d;
END $$;