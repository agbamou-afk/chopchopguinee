DO $$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node5_identity_a12';
  d := replace(d, $x$    'public._g2i_admin_staff_role_grant(uuid,text,text)',$x$,
                  $x$    'admin_staff_role_grant(uuid,text,text,uuid)',$x$);
  d := replace(d, $x$    'public._g2i_admin_staff_role_revoke(uuid,text,text)',$x$,
                  $x$    'admin_staff_role_revoke(uuid,text,text,uuid)',$x$);
  d := replace(d, $x$    'public._g2i_admin_professional_offboard(uuid,text)',$x$,
                  $x$    'admin_professional_offboard(uuid,text,uuid)',$x$);
  EXECUTE d;
END $$;