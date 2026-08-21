DO $mig$
DECLARE def text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO def
    FROM pg_proc WHERE oid = 'public._qa_node5_identity_a14()'::regprocedure;
  def := replace(def,
    'INSERT INTO public.account_freezes(user_id, status, reason)
  VALUES (u_bl,''active'',''qa-n5a14'');',
    'INSERT INTO public.account_freezes(user_id, status, reason, frozen_by)
  VALUES (u_bl,''active'',''qa-n5a14'', u_god);');
  IF position('frozen_by' in def) = 0 THEN RAISE EXCEPTION 'patch failed'; END IF;
  EXECUTE def;
END
$mig$;

REVOKE ALL ON FUNCTION public._qa_node5_identity_a14() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node5_identity_a14() TO service_role;
