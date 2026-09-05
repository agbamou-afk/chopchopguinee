DO $$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node5_identity_a12';
  d := replace(d, $x$    'public._g2i_admin_governance_set_status(uuid,text,text)',$x$,
                  $x$    'admin_governance_set_status(uuid,text,text,uuid)',$x$);
  EXECUTE d;
END $$;