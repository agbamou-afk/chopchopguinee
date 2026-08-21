CREATE OR REPLACE FUNCTION public.admin_set_driver_capability(_driver_user_id uuid, _capability text, _grant boolean)
RETURNS driver_profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  _row public.driver_profiles;
  _before text[];
  _after text[];
BEGIN
  IF NOT public._is_ops_or_god_admin(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;
  IF _capability IS NULL OR _capability <> ALL (public.driver_capability_vocabulary()) THEN
    RAISE EXCEPTION 'unknown_capability';
  END IF;

  IF _grant THEN
    PERFORM public._driver_capability_lane_gate(_driver_user_id);
  END IF;

  SELECT * INTO _row FROM public.driver_profiles WHERE user_id = _driver_user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'driver_profile_not_found'; END IF;

  _before := COALESCE(_row.capabilities, ARRAY[]::text[]);

  IF _grant THEN
    _after := CASE WHEN _capability = ANY(_before) THEN _before ELSE _before || _capability END;
  ELSE
    SELECT COALESCE(ARRAY_AGG(c), ARRAY[]::text[]) INTO _after
      FROM unnest(_before) c WHERE c <> _capability;
  END IF;

  IF _after IS NOT DISTINCT FROM _before THEN
    RETURN _row;
  END IF;

  UPDATE public.driver_profiles
     SET capabilities = _after
   WHERE user_id = _driver_user_id
   RETURNING * INTO _row;

  INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, before, after)
  VALUES (auth.uid(), 'drivers', 'driver.capability.' || CASE WHEN _grant THEN 'granted' ELSE 'revoked' END,
          'driver_profile', _driver_user_id::text,
          jsonb_build_object('capabilities', _before),
          jsonb_build_object('capabilities', _after, 'capability', _capability));

  RETURN _row;
END;
$$;
