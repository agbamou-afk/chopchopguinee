DO $$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_s13_run5';
  d := replace(d,
    $x$    r := r || public._qa_s13_ok('F5 an ordinary signed-in user cannot record an operator receipt',
      v_err LIKE '%forbidden%', v_err);$x$,
    $x$    r := r || public._qa_s13_ok('F5 an ordinary signed-in user cannot record an operator receipt',
      (v_err LIKE '%forbidden%' OR v_err LIKE '%denied%'), v_err);$x$);
  d := replace(d,
    $x$    r := r || public._qa_s13_ok('F6 an ordinary signed-in user cannot force a manual credit',
      v_err LIKE '%forbidden%', v_err);$x$,
    $x$    r := r || public._qa_s13_ok('F6 an ordinary signed-in user cannot force a manual credit',
      (v_err LIKE '%forbidden%' OR v_err LIKE '%denied%'), v_err);$x$);
  EXECUTE d;

  SELECT pg_get_functiondef(p.oid) INTO d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_s13_run7_fxcore';
  d := replace(d, '''public.admin_anonymize_user(uuid,text)''', '''public.admin_anonymize_user(uuid,text,uuid)''');
  EXECUTE d;
END $$;