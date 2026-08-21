-- =====================================================================
-- NODE 5 · A5 — PROFESSIONAL IDENTITY VS CAPABILITY
-- Identity = professional class (driver | merchant).
-- Capability = what a professional of that class may do.
-- Capability may NEVER create, imply or convert identity.
-- =====================================================================

-- 1. Canonical, single capability vocabulary --------------------------
CREATE OR REPLACE FUNCTION public.driver_capability_vocabulary()
RETURNS text[]
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $$
  SELECT ARRAY[
    'rides_moto',
    'rides_toktok',
    'rides_taxi',
    'repas_delivery',
    'marche_delivery',
    'package_delivery',
    'marche_shopper'
  ]::text[];
$$;
REVOKE ALL ON FUNCTION public.driver_capability_vocabulary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.driver_capability_vocabulary() TO authenticated, service_role;

-- 2. Active professional class of a user (server-derived) -------------
CREATE OR REPLACE FUNCTION public.professional_active_type(_user uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT pi.professional_type
    FROM public.professional_identities pi
   WHERE pi.user_id = _user AND pi.claim_state = 'active'
   LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.professional_active_type(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.professional_active_type(uuid) TO authenticated, service_role;

-- 3. Capability prerequisite gate (server-only) -----------------------
CREATE OR REPLACE FUNCTION public._driver_capability_lane_gate(_user uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_type text;
BEGIN
  IF _user IS NULL THEN
    RAISE EXCEPTION 'PROFESSIONAL_IDENTITY_REQUIRED';
  END IF;
  v_type := public.professional_active_type(_user);
  IF v_type IS NULL THEN
    RAISE EXCEPTION 'PROFESSIONAL_IDENTITY_REQUIRED';
  END IF;
  IF v_type <> 'driver' THEN
    RAISE EXCEPTION 'PROFESSIONAL_IDENTITY_CONFLICT';
  END IF;
END $$;
REVOKE ALL ON FUNCTION public._driver_capability_lane_gate(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._driver_capability_lane_gate(uuid) TO service_role;

-- 4. Database-boundary guard: capability cannot exist off-class -------
CREATE OR REPLACE FUNCTION public._driver_capability_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  caps text[] := COALESCE(NEW.capabilities, ARRAY[]::text[]);
  bad  text[];
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.capabilities IS NOT DISTINCT FROM OLD.capabilities THEN
    RETURN NEW;
  END IF;
  -- clearing capabilities is always lawful
  IF COALESCE(array_length(caps, 1), 0) = 0 THEN
    RETURN NEW;
  END IF;
  SELECT COALESCE(array_agg(c), ARRAY[]::text[]) INTO bad
    FROM unnest(caps) c
   WHERE c <> ALL (public.driver_capability_vocabulary());
  IF COALESCE(array_length(bad, 1), 0) > 0 THEN
    RAISE EXCEPTION 'DRIVER_CAPABILITY_UNKNOWN: %', array_to_string(bad, ',');
  END IF;
  PERFORM public._driver_capability_lane_gate(NEW.user_id);
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public._driver_capability_guard() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS driver_capability_guard ON public.driver_profiles;
CREATE TRIGGER driver_capability_guard
  BEFORE INSERT OR UPDATE ON public.driver_profiles
  FOR EACH ROW EXECUTE FUNCTION public._driver_capability_guard();

-- 5. Admin capability assignment respects professional class ----------
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
  IF NOT public._is_ops_or_god_admin() THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;
  IF _capability IS NULL OR _capability <> ALL (public.driver_capability_vocabulary()) THEN
    RAISE EXCEPTION 'unknown_capability';
  END IF;

  -- A5 law: admin governance does not bypass professional class.
  -- Granting requires an ACTIVE driver lane. Revoking stays possible so
  -- historical/incorrect assignments can always be withdrawn.
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

-- 6. Driver self-service capability toggle respects professional class -
CREATE OR REPLACE FUNCTION public.driver_set_capabilities(_caps text[])
RETURNS driver_profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  _row public.driver_profiles;
  _existing text[];
  _extra text[];
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  PERFORM public._driver_capability_lane_gate(auth.uid());
  SELECT * INTO _row FROM public.driver_profiles WHERE user_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'driver_profile_not_found'; END IF;
  IF _row.status IS DISTINCT FROM 'approved' THEN
    RAISE EXCEPTION 'driver_not_approved';
  END IF;
  _existing := COALESCE(_row.capabilities, ARRAY[]::text[]);
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

-- 7. Runtime capability truth = class + operational status + assignment
CREATE OR REPLACE FUNCTION public.driver_has_capability(_user_id uuid, _capability text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.driver_profiles dp
    WHERE dp.user_id = _user_id
      AND _capability = ANY (dp.capabilities)
      AND dp.status = 'approved'
      AND EXISTS (
        SELECT 1 FROM public.professional_identities pi
         WHERE pi.user_id = dp.user_id
           AND pi.claim_state = 'active'
           AND pi.professional_type = 'driver'
      )
  );
$$;
REVOKE ALL ON FUNCTION public.driver_has_capability(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.driver_has_capability(uuid, text) TO authenticated, service_role;

-- 8. Stored-assignment (history) read, explicitly NOT operational truth
CREATE OR REPLACE FUNCTION public.driver_capability_assigned(_user_id uuid, _capability text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.driver_profiles dp
     WHERE dp.user_id = _user_id
       AND _capability = ANY (dp.capabilities)
  );
$$;
REVOKE ALL ON FUNCTION public.driver_capability_assigned(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.driver_capability_assigned(uuid, text) TO authenticated, service_role;

COMMENT ON FUNCTION public.driver_has_capability(uuid, text) IS
  'A5: OPERATIONAL capability truth — active DRIVER professional identity AND approved driver status AND assigned capability.';
COMMENT ON FUNCTION public.driver_capability_assigned(uuid, text) IS
  'A5: STORED capability assignment only (audit/history). Never use for authorization.';
