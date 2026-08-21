
CREATE OR REPLACE FUNCTION public._qa_node5_fr_cleanup(p_ids uuid[], p_ride uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
SET statement_timeout TO '60s'
AS $function$
BEGIN
  DELETE FROM public.account_access_terminations WHERE user_id = ANY(p_ids);
  DELETE FROM public.audit_logs WHERE target_id = ANY(SELECT x::text FROM unnest(p_ids) x);
  DELETE FROM public.audit_logs WHERE actor_user_id = ANY(p_ids);
  DELETE FROM public.ride_offers WHERE driver_id = ANY(p_ids);
  DELETE FROM public.rides WHERE id = p_ride;
  DELETE FROM public.account_recovery_profiles WHERE user_id = ANY(p_ids);
  DELETE FROM public.merchant_stores WHERE owner_user_id = ANY(p_ids);
  DELETE FROM public.admin_users WHERE user_id = ANY(p_ids);
  DELETE FROM public.user_roles WHERE user_id = ANY(p_ids);
  DELETE FROM public.wallet_transactions WHERE wallet_id IN
    (SELECT id FROM public.wallets WHERE owner_user_id = ANY(p_ids));
  DELETE FROM public.wallets WHERE owner_user_id = ANY(p_ids);
  DELETE FROM public.driver_profiles WHERE user_id = ANY(p_ids);
  PERFORM public._qa_users_purge(p_ids);
END $function$;
