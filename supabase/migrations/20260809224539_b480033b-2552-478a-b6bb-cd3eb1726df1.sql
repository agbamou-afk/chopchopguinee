DO $$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef('public._qa_s3b_run()'::regprocedure) INTO d;
  d := replace(d, 'DELETE FROM public.finance_policies WHERE note=''qa post-acceptance edit'';', '');
  d := replace(d, 'DELETE FROM public.finance_policies WHERE note=''qa cancel policy edit'';', '');
  EXECUTE d;
END $$;