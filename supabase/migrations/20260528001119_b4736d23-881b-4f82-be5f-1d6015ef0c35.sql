
-- Fix PRIVILEGE_ESCALATION errors: drivers/agents could update own profile rows
-- including financial/approval columns. Remove broad self-UPDATE policies and
-- route legitimate self-edits through a SECURITY DEFINER RPC that only touches
-- safe columns (capabilities, scoped to already-granted set).

DROP POLICY IF EXISTS "Agents update own profile" ON public.agent_profiles;
DROP POLICY IF EXISTS "Drivers update own profile" ON public.driver_profiles;

-- RPC: driver self-toggles within their already-granted capability set only.
-- Cannot add new capabilities (admin must grant), cannot change status,
-- vehicle, payout, cash_debt or any other column.
CREATE OR REPLACE FUNCTION public.driver_set_capabilities(_caps text[])
RETURNS public.driver_profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _row public.driver_profiles;
  _existing text[];
  _extra text[];
BEGIN
  SELECT * INTO _row FROM public.driver_profiles WHERE user_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'driver_profile_not_found'; END IF;
  IF _row.status IS DISTINCT FROM 'approved' THEN
    RAISE EXCEPTION 'driver_not_approved';
  END IF;
  _existing := COALESCE(_row.capabilities, ARRAY[]::text[]);
  -- requested must be a subset of existing (drivers can disable/reenable, not grant new)
  SELECT COALESCE(ARRAY_AGG(c), ARRAY[]::text[]) INTO _extra
    FROM unnest(_caps) c WHERE c <> ALL (_existing);
  IF array_length(_extra, 1) > 0 THEN
    RAISE EXCEPTION 'capability_not_granted: %', array_to_string(_extra, ',');
  END IF;
  UPDATE public.driver_profiles
     SET capabilities = _caps
   WHERE user_id = auth.uid()
   RETURNING * INTO _row;
  RETURN _row;
END;
$$;

REVOKE ALL ON FUNCTION public.driver_set_capabilities(text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.driver_set_capabilities(text[]) TO authenticated, service_role;
