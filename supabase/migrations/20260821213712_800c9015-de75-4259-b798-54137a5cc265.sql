
CREATE OR REPLACE FUNCTION public.pgrst_pre_request()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_uid uuid;
BEGIN
  BEGIN
    v_uid := auth.uid();
  EXCEPTION WHEN OTHERS THEN
    RETURN; -- never break the API on claim parsing
  END;
  IF v_uid IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM public.profiles
              WHERE user_id = v_uid AND account_status = 'deleted') THEN
    RAISE EXCEPTION 'ACCOUNT_CLOSED' USING ERRCODE = '42501',
      HINT = 'This account has been closed. Access is terminated.';
  END IF;
END
$function$;

GRANT EXECUTE ON FUNCTION public.pgrst_pre_request() TO anon, authenticated, service_role;
ALTER ROLE authenticator SET pgrst.db_pre_request = 'public.pgrst_pre_request';
NOTIFY pgrst, 'reload config';
