
REVOKE EXECUTE ON FUNCTION public.auth_uid_active() FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.auth_uid_active() TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public.admin_account_closure_reconcile(uuid,text) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.admin_account_closure_reconcile(uuid,text) TO authenticated, service_role;

REVOKE EXECUTE ON FUNCTION public._account_access_terminate_enqueue(uuid,text,text)
  FROM anon, authenticated, PUBLIC;
GRANT  EXECUTE ON FUNCTION public._account_access_terminate_enqueue(uuid,text,text) TO service_role;

REVOKE EXECUTE ON FUNCTION public.account_access_termination_record(uuid,boolean,text)
  FROM anon, authenticated, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.account_access_termination_record(uuid,boolean,text) TO service_role;

REVOKE ALL ON TABLE public.account_access_terminations FROM anon, authenticated, PUBLIC;
GRANT ALL ON TABLE public.account_access_terminations TO service_role;
