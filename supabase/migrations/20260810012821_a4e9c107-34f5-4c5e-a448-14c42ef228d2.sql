REVOKE ALL ON FUNCTION public._cash_order_accept_internal(text,uuid,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._cash_order_complete_internal(text,uuid,uuid,boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._cash_order_deactivate_source(text,uuid,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._merchant_payable_reverse_internal(text,uuid,uuid,uuid,text,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._mission_cash_source(public.missions) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._cash_order_block_direct_state() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._cash_order_is_cash(text,uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_offer_set_tender(uuid,text) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public._cash_order_accept_internal(text,uuid,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._cash_order_complete_internal(text,uuid,uuid,boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public._cash_order_deactivate_source(text,uuid,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._merchant_payable_reverse_internal(text,uuid,uuid,uuid,text,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._mission_cash_source(public.missions) TO service_role;
GRANT EXECUTE ON FUNCTION public._cash_order_is_cash(text,uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.marche_offer_set_tender(uuid,text) TO authenticated, service_role;