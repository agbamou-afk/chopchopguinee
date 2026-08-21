-- =====================================================================
-- NODE 5 · A6 — DRIVER ARCHITECTURE MIGRATION
-- Canonical Driver authority = ACTIVE professional identity of type driver.
-- Layers kept independent: CLASS / OPERATIONAL STATUS / CAPABILITY / OBJECT.
-- =====================================================================

CREATE OR REPLACE FUNCTION public._driver_class_active(_uid uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT _uid IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.professional_identities pi
     WHERE pi.user_id = _uid
       AND pi.claim_state = 'active'
       AND pi.professional_type = 'driver'
  );
$$;

-- CLASS layer only. Never consults status, capability or assignment.
CREATE OR REPLACE FUNCTION public._driver_class_require(_uid uuid, _ctx text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_type text;
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED' USING DETAIL = COALESCE(_ctx,'driver action');
  END IF;
  SELECT pi.professional_type INTO v_type
    FROM public.professional_identities pi
   WHERE pi.user_id = _uid AND pi.claim_state = 'active';
  IF v_type = 'driver' THEN RETURN; END IF;
  IF v_type IS NOT NULL THEN
    RAISE EXCEPTION 'PROFESSIONAL_IDENTITY_CONFLICT'
      USING DETAIL = COALESCE(_ctx,'driver action')
                     || ' requires the DRIVER professional class; active class is ' || v_type;
  END IF;
  RAISE EXCEPTION 'PROFESSIONAL_IDENTITY_REQUIRED'
    USING DETAIL = COALESCE(_ctx,'driver action')
                   || ' requires an ACTIVE DRIVER professional identity';
END $$;

-- CLASS + OPERATIONAL STATUS (+ optional CAPABILITY). Assignment stays with the caller.
CREATE OR REPLACE FUNCTION public._driver_operational_require(
  _uid uuid, _ctx text DEFAULT NULL, _capability text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_status public.driver_status;
BEGIN
  PERFORM public._driver_class_require(_uid, _ctx);
  SELECT dp.status INTO v_status FROM public.driver_profiles dp WHERE dp.user_id = _uid;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'DRIVER_PROFILE_REQUIRED' USING DETAIL = COALESCE(_ctx,'driver action');
  END IF;
  IF v_status <> 'approved' THEN
    RAISE EXCEPTION 'DRIVER_NOT_OPERATIONAL'
      USING DETAIL = COALESCE(_ctx,'driver action') || ': driver status is ' || v_status::text;
  END IF;
  IF _capability IS NOT NULL AND NOT public.driver_has_capability(_uid, _capability) THEN
    RAISE EXCEPTION 'DRIVER_CAPABILITY_MISSING'
      USING DETAIL = COALESCE(_ctx,'driver action') || ': ' || _capability;
  END IF;
END $$;

REVOKE ALL ON FUNCTION public._driver_class_active(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._driver_class_require(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._driver_operational_require(uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._driver_class_active(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._driver_class_require(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public._driver_operational_require(uuid, text, text) TO service_role;

-- ---------------------------------------------------------------------
-- Surgical anchored insertion of the class prerequisite into each
-- Driver authority surface. Anchors are placed AFTER existing object /
-- ownership validation so no frozen refusal message is displaced.
-- ---------------------------------------------------------------------
DO $mig$
DECLARE
  spec jsonb := jsonb_build_array(
    jsonb_build_array('driver_set_status',
      E'IF v_profile.user_id IS NULL THEN RAISE EXCEPTION ''No driver profile''; END IF;',
      E'\n  PERFORM public._driver_class_require(v_uid, ''driver_set_status'');'),
    jsonb_build_array('driver_offer_accept',
      E'IF v_offer.driver_id <> v_uid THEN RAISE EXCEPTION ''Not your offer''; END IF;',
      E'\n  PERFORM public._driver_class_require(v_uid, ''driver_offer_accept'');'),
    jsonb_build_array('driver_offer_decline',
      E'IF v_offer.id IS NULL THEN RAISE EXCEPTION ''Cannot decline this offer''; END IF;',
      E'\n  PERFORM public._driver_class_require(v_uid, ''driver_offer_decline'');'),
    jsonb_build_array('ride_accept',
      E'RAISE EXCEPTION ''OFFER_CONTRACT_REQUIRED'';\n  END IF;',
      E'\n\n  PERFORM public._driver_class_require(v_uid, ''ride_accept'');'),
    jsonb_build_array('ride_start',
      E'RAISE EXCEPTION ''Only the assigned driver can start the trip'';\n  END IF;',
      E'\n  IF v_ride.driver_id = v_uid THEN PERFORM public._driver_class_require(v_uid, ''ride_start''); END IF;'),
    jsonb_build_array('ride_complete',
      E'RAISE EXCEPTION ''ONLY_ASSIGNED_DRIVER_CAN_COMPLETE'';\n    END IF;',
      E'\n    PERFORM public._driver_class_require(v_uid, ''ride_complete'');'),
    jsonb_build_array('ride_set_phase',
      E'RAISE EXCEPTION ''Not authorized'';\n  END IF;',
      E'\n  IF v_ride.driver_id = v_uid THEN PERFORM public._driver_class_require(v_uid, ''ride_set_phase''); END IF;'),
    jsonb_build_array('mission_set_state',
      E'RAISE EXCEPTION ''forbidden'';\n  END IF;',
      E'\n  IF _m.courier_id = _uid THEN PERFORM public._driver_class_require(_uid, ''mission_set_state''); END IF;'),
    jsonb_build_array('mission_confirm_pickup',
      E'RAISE EXCEPTION ''forbidden'';\n  END IF;',
      E'\n  IF _m.courier_id = _uid THEN PERFORM public._driver_class_require(_uid, ''mission_confirm_pickup''); END IF;'),
    jsonb_build_array('mission_confirm_dropoff',
      E'RAISE EXCEPTION ''forbidden'';\n  END IF;',
      E'\n  IF _m.courier_id = _uid THEN PERFORM public._driver_class_require(_uid, ''mission_confirm_dropoff''); END IF;'),
    jsonb_build_array('mission_confirm_pickup_with_proof',
      E'RAISE EXCEPTION ''forbidden'';\n  END IF;',
      E'\n  IF _m.courier_id = _uid THEN PERFORM public._driver_class_require(_uid, ''mission_confirm_pickup_with_proof''); END IF;'),
    jsonb_build_array('mission_confirm_dropoff_with_proof',
      E'RAISE EXCEPTION ''forbidden'';\n  END IF;',
      E'\n  IF _m.courier_id = _uid THEN PERFORM public._driver_class_require(_uid, ''mission_confirm_dropoff_with_proof''); END IF;'),
    jsonb_build_array('mission_report_issue',
      E'RAISE EXCEPTION ''forbidden'';\n  END IF;',
      E'\n  IF _m.courier_id = _uid THEN PERFORM public._driver_class_require(_uid, ''mission_report_issue''); END IF;'),
    jsonb_build_array('mission_claim',
      E'RAISE EXCEPTION ''capability_missing'';\n  END IF;',
      E'\n  PERFORM public._driver_operational_require(_uid, ''mission_claim'');'),
    jsonb_build_array('repas_custody_confirm_handoff',
      E'IF v_m.courier_id IS DISTINCT FROM v_uid THEN RAISE EXCEPTION ''NOT_ASSIGNED_COURIER''; END IF;',
      E'\n  PERFORM public._driver_class_require(v_uid, ''repas_custody_confirm_handoff'');'),
    jsonb_build_array('repas_custody_confirm_delivery',
      E'IF v_m.courier_id IS DISTINCT FROM v_uid THEN RAISE EXCEPTION ''NOT_ASSIGNED_COURIER''; END IF;',
      E'\n  PERFORM public._driver_class_require(v_uid, ''repas_custody_confirm_delivery'');'),
    jsonb_build_array('package_verify_pickup',
      E'IF v_m.courier_id IS DISTINCT FROM v_uid THEN RAISE EXCEPTION ''forbidden'' USING ERRCODE=''42501''; END IF;',
      E'\n  PERFORM public._driver_class_require(v_uid, ''package_verify_pickup'');'),
    jsonb_build_array('package_verify_delivery',
      E'IF v_m.courier_id IS DISTINCT FROM v_uid THEN RAISE EXCEPTION ''forbidden'' USING ERRCODE=''42501''; END IF;',
      E'\n  PERFORM public._driver_class_require(v_uid, ''package_verify_delivery'');'),
    jsonb_build_array('marche_courier_transition',
      E'IF m.courier_id IS DISTINCT FROM caller THEN RAISE EXCEPTION ''NOT_THE_ASSIGNED_COURIER''; END IF;',
      E'\n  PERFORM public._driver_class_require(caller, ''marche_courier_transition'');'),
    jsonb_build_array('marche_shopper_claim',
      E'IF NOT public._marche_shopper_eligible(v_uid) THEN RAISE EXCEPTION ''PROCUREMENT_SHOPPER_NOT_ELIGIBLE''; END IF;',
      E'\n  PERFORM public._driver_operational_require(v_uid, ''marche_shopper_claim'', ''marche_shopper'');'),
    jsonb_build_array('_marche_pm_shopper_lock',
      E'IF NOT public._marche_shopper_eligible(p_uid) THEN RAISE EXCEPTION ''PROCUREMENT_SHOPPER_NOT_ELIGIBLE''; END IF;',
      E'\n  PERFORM public._driver_class_require(p_uid, ''marche_shopper_action'');'),
    jsonb_build_array('driver_update_location_signal',
      E'RAISE EXCEPTION ''auth required'' USING ERRCODE = ''42501'';\n  END IF;',
      E'\n  PERFORM public._driver_class_require(v_uid, ''driver_update_location_signal'');'),
    jsonb_build_array('driver_admin_decide',
      E'IF v_profile.user_id IS NULL THEN RAISE EXCEPTION ''Driver profile not found''; END IF;',
      E'\n  IF p_decision IN (''approve'',''reactivate'') AND NOT public._driver_class_active(p_user_id) THEN\n    RAISE EXCEPTION ''PROFESSIONAL_IDENTITY_CONFLICT''\n      USING DETAIL = ''driver approval requires the target account to hold an ACTIVE DRIVER professional identity'';\n  END IF;'),
    jsonb_build_array('ride_dispatch',
      E'WHERE dp.status=''approved'' AND dp.vehicle_type = v_vehicle',
      E'\n     AND public._driver_class_active(dl.user_id)')
  );
  it jsonb; fn text; anchor text; ins text; def text; occ int; patched int := 0;
BEGIN
  FOR it IN SELECT * FROM jsonb_array_elements(spec) LOOP
    fn     := it->>0;
    anchor := it->>1;
    ins    := it->>2;
    def    := pg_get_functiondef(('public.'||fn)::regproc);

    IF position('_driver_class_require' in def) > 0
       OR position('_driver_operational_require' in def) > 0
       OR position('_driver_class_active' in def) > 0 THEN
      RAISE NOTICE 'skip % (already class-gated)', fn;
      CONTINUE;
    END IF;

    occ := (length(def) - length(replace(def, anchor, ''))) / NULLIF(length(anchor),0);
    IF occ <> 1 THEN
      RAISE EXCEPTION 'A6_ANCHOR_NOT_UNIQUE in %: % occurrence(s)', fn, occ;
    END IF;

    EXECUTE replace(def, anchor, anchor || ins);
    patched := patched + 1;
    RAISE NOTICE 'A6 class gate applied to %', fn;
  END LOOP;

  RAISE NOTICE 'A6: % driver authority surface(s) migrated', patched;
END $mig$;