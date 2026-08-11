ALTER FUNCTION public._qa_s13_om_rolecall(text, uuid, text, text, text) SECURITY INVOKER;
ALTER FUNCTION public._qa_s13_run5() SECURITY INVOKER;
REVOKE ALL ON FUNCTION public._qa_s13_om_rolecall(text, uuid, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._qa_s13_run5() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_s13_om_rolecall(text, uuid, text, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public._qa_s13_run5() TO service_role;