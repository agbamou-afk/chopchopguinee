
DO $mig$
DECLARE d text;
BEGIN
  d := pg_get_functiondef('public._qa_node5_fr_live_reconcile()'::regprocedure);
  d := replace(d,
    'FROM public.account_access_terminations t
            JOIN public.profiles p ON p.user_id=t.user_id',
    'FROM public.account_access_terminations aat
            JOIN public.profiles p ON p.user_id=aat.user_id');
  EXECUTE d;
END $mig$;
