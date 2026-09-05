DO $$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO d FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='_qa_node4_marche_r11';
  d := replace(d, '    PERFORM public._qa_s13_admin(v_adm);',
$x$    INSERT INTO public.admin_users(user_id, admin_role, status)
    VALUES (v_adm, 'ops_admin', 'active')
    ON CONFLICT (user_id) DO UPDATE SET admin_role='ops_admin', status='active';$x$);
  d := replace(d, 'N4R11.B5 a plain admin is not finance-privileged',
                  'N4R11.B5 an operations admin is not finance-privileged');
  EXECUTE d;
END $$;