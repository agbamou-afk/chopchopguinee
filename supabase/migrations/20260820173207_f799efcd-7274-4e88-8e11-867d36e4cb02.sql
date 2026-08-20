CREATE OR REPLACE FUNCTION public._qa_users_purge(p_ids uuid[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  DELETE FROM auth.users WHERE id = ANY(p_ids);
  -- profiles.id is an independent PK; the auth-user link lives in profiles.user_id.
  -- Match both keys so trigger-created fixture profiles are actually removed.
  DELETE FROM public.profiles p
   WHERE (p.id = ANY(p_ids) OR p.user_id = ANY(p_ids))
     AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = p.id OR u.id = p.user_id);
END $function$;