DO $mig$
DECLARE def text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO def
    FROM pg_proc WHERE oid = 'public._qa_node5_identity_a14()'::regprocedure;
  def := replace(def,
    'INSERT INTO public.admin_users(user_id, role, status)',
    'INSERT INTO public.admin_users(user_id, admin_role, status)');
  IF position('admin_users(user_id, admin_role, status)' in def) = 0 THEN
    RAISE EXCEPTION 'patch did not apply';
  END IF;
  EXECUTE def;
END
$mig$;

REVOKE ALL ON FUNCTION public._qa_node5_identity_a14() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node5_identity_a14() TO service_role;
