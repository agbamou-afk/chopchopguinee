CREATE OR REPLACE FUNCTION public._g3_lifecycle_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF COALESCE(NULLIF(current_setting('chopchop.g3_lifecycle', true), ''), 'off') <> 'on' THEN
    RAISE EXCEPTION 'staff_lifecycle_requests is append-only through governed lifecycle functions'
      USING ERRCODE = '42501';
  END IF;
  IF TG_OP = 'DELETE' THEN
    -- Real lifecycle provenance is indelible. Only ephemeral QA-harness rows may be purged.
    IF COALESCE(NULLIF(current_setting('chopchop.g3_qa_purge', true), ''), 'off') = 'on'
       AND OLD.idempotency_key LIKE 'qa-g3-%' THEN
      RETURN OLD;
    END IF;
    RAISE EXCEPTION 'staff lifecycle records cannot be deleted' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public._qa_g3_purge_fixtures(_ids uuid[])
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  PERFORM set_config('chopchop.g3_lifecycle','on',true);
  PERFORM set_config('chopchop.g3_qa_purge','on',true);
  DELETE FROM public.staff_lifecycle_requests
   WHERE idempotency_key LIKE 'qa-g3-%'
     AND (requester_id = ANY(_ids) OR target_user_id = ANY(_ids) OR auth_user_id = ANY(_ids));
  PERFORM set_config('chopchop.g3_qa_purge','off',true);
  PERFORM set_config('chopchop.g3_lifecycle','off',true);
END;
$$;
REVOKE ALL ON FUNCTION public._qa_g3_purge_fixtures(uuid[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._qa_g3_purge_fixtures(uuid[]) TO service_role;