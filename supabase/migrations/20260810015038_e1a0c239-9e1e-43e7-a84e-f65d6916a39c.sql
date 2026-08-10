REVOKE EXECUTE ON FUNCTION public.create_marketplace_offer(uuid, bigint, text, text) FROM anon;
REVOKE EXECUTE ON FUNCTION public.mission_claim(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public._cash_order_runtime_immutable() FROM anon, authenticated;