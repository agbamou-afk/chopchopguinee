DO $$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node4_marche_r4';
  d := replace(d,
$x$          AND proname='admin_set_finance_policy') LIKE '%is_god_admin%'$x$,
$x$          AND proname='admin_set_finance_policy') ~ '(is_god_admin|admin_enforce)'$x$);
  EXECUTE d;
END $$;