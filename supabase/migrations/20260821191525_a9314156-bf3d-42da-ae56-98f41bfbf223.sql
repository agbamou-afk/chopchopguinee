
ALTER FUNCTION public._qa_node5_identity_a13() SECURITY INVOKER;
REVOKE ALL ON FUNCTION public._qa_node5_identity_a13() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_node5_identity_a13() TO service_role;
