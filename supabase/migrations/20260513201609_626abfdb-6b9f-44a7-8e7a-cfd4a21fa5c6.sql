
REVOKE EXECUTE ON FUNCTION public.driver_apply(jsonb) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.driver_admin_decide(uuid, text, text) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.driver_set_status(public.driver_presence) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.driver_offer_accept(uuid) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.driver_offer_decline(uuid, text) FROM anon, public;
REVOKE EXECUTE ON FUNCTION public.driver_cash_settle(uuid, bigint, text) FROM anon, public;

GRANT EXECUTE ON FUNCTION public.driver_apply(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.driver_admin_decide(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.driver_set_status(public.driver_presence) TO authenticated;
GRANT EXECUTE ON FUNCTION public.driver_offer_accept(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.driver_offer_decline(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.driver_cash_settle(uuid, bigint, text) TO authenticated;
