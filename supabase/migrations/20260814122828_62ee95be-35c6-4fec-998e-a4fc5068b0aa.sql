REVOKE ALL ON FUNCTION public._repas_custody_hash(text, text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._qa_r6_value(p_users uuid[])
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE((SELECT sum(balance_gnf + held_gnf) FROM public.wallets
                    WHERE owner_user_id = ANY(p_users)), 0)
       + COALESCE((SELECT sum(balance_gnf + held_gnf) FROM public.wallets
                    WHERE party_type = 'master'), 0);
$function$;

REVOKE ALL ON FUNCTION public._qa_r6_value(uuid[]) FROM PUBLIC, anon, authenticated;
