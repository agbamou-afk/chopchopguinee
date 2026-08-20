-- QA-only: fixture purge now removes the profile row created by the
-- profiles trigger for the same throwaway identity, so QA runs leave no
-- residue. No product function, policy or grant is changed.
CREATE OR REPLACE FUNCTION public._qa_users_purge(p_ids uuid[])
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
BEGIN
  DELETE FROM auth.users WHERE id = ANY(p_ids);
  DELETE FROM public.profiles p
   WHERE p.id = ANY(p_ids)
     AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = p.id);
END $fn$;

-- Restore this pass's baseline: drop orphaned QA fixture profiles created today.
DELETE FROM public.profiles p
 WHERE p.created_at >= timestamptz '2026-08-20 05:30:00+00'
   AND coalesce(p.full_name,'') = ''
   AND coalesce(p.phone,'') = ''
   AND NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = p.id);