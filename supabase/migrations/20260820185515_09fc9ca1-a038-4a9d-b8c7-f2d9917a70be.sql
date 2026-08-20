DO $mig$
DECLARE s text; s0 text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO s FROM pg_proc
   WHERE proname = '_qa_node4_marche_r12' AND pronamespace = 'public'::regnamespace;
  s0 := s;

  s := replace(s, 'SELECT count(*) INTO v_au0 FROM auth.users;',
                  'v_au0 := public._qa_auth_user_count();');
  s := replace(s, 'SELECT count(*) INTO v_au1 FROM auth.users;',
                  'v_au1 := public._qa_auth_user_count();');
  s := replace(s,
    'SELECT count(*) INTO v_n FROM public.admin_users a' || E'\n' ||
    '    WHERE NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = a.user_id);',
    'v_n := public._qa_n4r12_orphan_admins()::int;');

  IF s = s0 OR position('FROM auth.users' in s) > 0 THEN
    RAISE EXCEPTION 'QA_R12_PATCH_FAILED';
  END IF;

  EXECUTE s;
END $mig$;

REVOKE ALL ON FUNCTION public._qa_node4_marche_r12() FROM PUBLIC, anon, authenticated;