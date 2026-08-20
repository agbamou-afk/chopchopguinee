CREATE OR REPLACE FUNCTION public._qa_a2_cleanup(p_ids uuid[])
RETURNS void
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  DELETE FROM public.professional_identities WHERE user_id = ANY(p_ids);
  DELETE FROM public.wallet_transactions
   WHERE from_wallet_id IN (SELECT id FROM public.wallets WHERE owner_user_id = ANY(p_ids))
      OR to_wallet_id   IN (SELECT id FROM public.wallets WHERE owner_user_id = ANY(p_ids));
  DELETE FROM public.wallets WHERE owner_user_id = ANY(p_ids);
  DELETE FROM public.user_roles WHERE user_id = ANY(p_ids);
  PERFORM public._qa_users_purge(p_ids);
END $$;

REVOKE ALL ON FUNCTION public._qa_a2_cleanup(uuid[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_a2_cleanup(uuid[]) TO service_role, postgres;