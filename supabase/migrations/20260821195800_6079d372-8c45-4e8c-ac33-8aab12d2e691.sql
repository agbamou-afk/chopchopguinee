DO $mig$
DECLARE def text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO def
    FROM pg_proc WHERE oid = 'public._qa_node5_identity_a14()'::regprocedure;
  def := replace(def, 'owner_user_id = u_d',
                      'owner_user_id = u_d AND party_type=''driver''::public.party_type');
  IF position('owner_user_id = u_d AND party_type' in def) = 0 THEN
    RAISE EXCEPTION 'patch failed';
  END IF;
  EXECUTE def;
END
$mig$;

REVOKE ALL ON FUNCTION public._qa_node5_identity_a14() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node5_identity_a14() TO service_role;
