DO $$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node3_repas_pickup_fxcore';
  d := replace(d,
$x$  SELECT pg_get_functiondef(p.oid) INTO v_def FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='admin_set_finance_policy';
  r := r || public._qa_s13_ok('P1.5 fee edits are god-admin only',$x$,
$x$  SELECT string_agg(pg_get_functiondef(p.oid), E'\n') INTO v_def FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public'
     AND p.proname IN ('admin_set_finance_policy','_g2i_admin_set_finance_policy');
  r := r || public._qa_s13_ok('P1.5 fee edits are god-admin only',$x$);
  d := replace(d, $x$        v_def LIKE '%is_god_admin%', NULL);$x$,
                  $x$        (v_def LIKE '%is_god_admin%' OR v_def LIKE '%admin_enforce%'), NULL);$x$);
  EXECUTE d;
END $$;