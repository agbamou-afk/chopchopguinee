
CREATE OR REPLACE FUNCTION public._qa_node5_fr_seed(p_ids uuid[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
SET statement_timeout TO '60s'
AS $function$
DECLARE x uuid;
BEGIN
  FOREACH x IN ARRAY p_ids LOOP
    PERFORM public._qa_s13_user(x, 'n5fr');
  END LOOP;
END $function$;

REVOKE ALL ON FUNCTION public._qa_node5_fr_seed(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._qa_node5_fr_seed(uuid[]) TO service_role;

CREATE OR REPLACE FUNCTION public._qa_node5_fr_profiles(p_ids uuid[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
SET statement_timeout TO '60s'
AS $function$
BEGIN
  INSERT INTO public.profiles(user_id, full_name, account_status)
  SELECT x, 'QA N5FR', 'active' FROM unnest(p_ids) x
  ON CONFLICT DO NOTHING;
END $function$;

REVOKE ALL ON FUNCTION public._qa_node5_fr_profiles(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._qa_node5_fr_profiles(uuid[]) TO service_role;
