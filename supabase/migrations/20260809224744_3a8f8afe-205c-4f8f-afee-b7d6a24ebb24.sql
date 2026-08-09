DO $$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef('public._qa_s3b_run()'::regprocedure) INTO d;
  d := replace(d, 'SELECT (public.wallet_topup_om_create(50000, NULL)->>''id'')::uuid INTO t;',
                  'SELECT (public.wallet_topup_om_create(50000, NULL)).id INTO t;');
  d := replace(d, 'PERFORM public.wallet_topup_om_credit(t, NULL);',
                  'PERFORM public.wallet_topup_om_credit(NULL, t);');
  EXECUTE d;
END $$;