-- ============================================================================
-- Node 5 · A4 — SAFE ONBOARDING ABANDONMENT
-- Law: a professional lane may be released ONLY while the server can prove no
-- irreversible operational, financial or historical dependency exists.
-- A4 is NOT a Driver<->Merchant conversion mechanism: release returns the
-- account to plain-customer state; re-entry is a fresh claim.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Eligibility (fail-closed, machine-readable blockers)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.professional_identity_release_eligibility(
  _user uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller uuid := auth.uid();
  v_user   uuid := COALESCE(_user, auth.uid());
  v_lane   text;
  v_idid   uuid;
  v_b      jsonb := '[]'::jsonb;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;
  IF v_user IS NULL THEN RAISE EXCEPTION 'PROFESSIONAL_IDENTITY_USER_REQUIRED'; END IF;
  IF v_user <> v_caller AND NOT public._is_ops_or_god_admin(v_caller) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  SELECT professional_type, id INTO v_lane, v_idid
    FROM public.professional_identities
   WHERE user_id = v_user AND claim_state = 'active'
   LIMIT 1;

  IF v_lane IS NULL THEN
    RETURN jsonb_build_object(
      'user_id', v_user, 'lane', 'none', 'identity_id', NULL,
      'eligible', false, 'blockers', jsonb_build_array('NO_ACTIVE_PROFESSIONAL_LANE'));
  END IF;

  IF v_lane = 'driver' THEN
    IF EXISTS (SELECT 1 FROM public.driver_profiles
                WHERE user_id = v_user AND status IN ('approved','suspended'))
      THEN v_b := v_b || '"DRIVER_ALREADY_APPROVED"'::jsonb; END IF;
    IF EXISTS (SELECT 1 FROM public.driver_applications
                WHERE user_id = v_user AND decision = 'approved')
      THEN v_b := v_b || '"DRIVER_APPLICATION_APPROVED"'::jsonb; END IF;
    IF EXISTS (SELECT 1 FROM public.user_roles
                WHERE user_id = v_user AND role = 'driver'::public.app_role)
      THEN v_b := v_b || '"DRIVER_ROLE_GRANTED"'::jsonb; END IF;
    IF EXISTS (SELECT 1 FROM public.missions WHERE courier_id = v_user)
      THEN v_b := v_b || '"DRIVER_HAS_MISSION_HISTORY"'::jsonb; END IF;
    IF EXISTS (SELECT 1 FROM public.rides WHERE driver_id = v_user)
      THEN v_b := v_b || '"DRIVER_HAS_RIDE_HISTORY"'::jsonb; END IF;
    IF EXISTS (SELECT 1 FROM public.marche_procurement_missions WHERE shopper_user_id = v_user)
      THEN v_b := v_b || '"DRIVER_HAS_PROCUREMENT_HISTORY"'::jsonb; END IF;
    IF EXISTS (SELECT 1 FROM public.driver_cash_ledger WHERE driver_id = v_user)
      THEN v_b := v_b || '"DRIVER_HAS_CASH_LEDGER"'::jsonb; END IF;
    IF EXISTS (SELECT 1 FROM public.wallets
                WHERE owner_user_id = v_user AND party_type = 'driver'::public.party_type)
      THEN v_b := v_b || '"DRIVER_WALLET_EXISTS"'::jsonb; END IF;
    IF EXISTS (SELECT 1 FROM public.driver_group_memberships
                WHERE driver_user_id = v_user)
      THEN v_b := v_b || '"DRIVER_HAS_GROUP_MEMBERSHIP"'::jsonb; END IF;

  ELSIF v_lane = 'merchant' THEN
    IF EXISTS (SELECT 1 FROM public.merchant_stores
                WHERE owner_user_id = v_user
                  AND status <> 'archived'
                  AND (approved_at IS NOT NULL
                       OR onboarding_status = 'approved'
                       OR status IN ('active','suspended','paused')))
      THEN v_b := v_b || '"MERCHANT_STORE_APPROVED"'::jsonb; END IF;
    IF EXISTS (SELECT 1 FROM public.food_restaurants
                WHERE owner_user_id = v_user AND COALESCE(status,'') NOT IN ('draft','archived'))
      THEN v_b := v_b || '"MERCHANT_RESTAURANT_ACTIVE"'::jsonb; END IF;
    IF EXISTS (SELECT 1 FROM public.merchants
                WHERE owner_user_id = v_user AND COALESCE(status,'') NOT IN ('draft','archived','pending'))
      THEN v_b := v_b || '"MERCHANT_LEGACY_ACTIVE"'::jsonb; END IF;
    IF EXISTS (SELECT 1 FROM public.user_roles
                WHERE user_id = v_user AND role = 'merchant'::public.app_role)
      THEN v_b := v_b || '"MERCHANT_ROLE_GRANTED"'::jsonb; END IF;
    IF EXISTS (SELECT 1 FROM public.marketplace_listings l
                JOIN public.merchant_stores s ON s.id = l.store_id
               WHERE s.owner_user_id = v_user)
      THEN v_b := v_b || '"MERCHANT_HAS_LISTINGS"'::jsonb; END IF;
    IF EXISTS (SELECT 1 FROM public.marche_orders WHERE merchant_user_id = v_user)
      THEN v_b := v_b || '"MERCHANT_HAS_ORDERS"'::jsonb; END IF;
    IF EXISTS (SELECT 1 FROM public.food_orders o
                JOIN public.food_restaurants r ON r.id = o.restaurant_id
               WHERE r.owner_user_id = v_user)
      THEN v_b := v_b || '"MERCHANT_HAS_FOOD_ORDERS"'::jsonb; END IF;
    IF EXISTS (SELECT 1 FROM public.merchant_payables WHERE merchant_user_id = v_user)
      THEN v_b := v_b || '"MERCHANT_HAS_PAYABLES"'::jsonb; END IF;
    IF EXISTS (SELECT 1 FROM public.merchant_settlement_requests WHERE merchant_user_id = v_user)
      THEN v_b := v_b || '"MERCHANT_HAS_SETTLEMENTS"'::jsonb; END IF;
    IF EXISTS (SELECT 1 FROM public.missions m
                WHERE m.merchant_id = v_user
                   OR m.merchant_store_id IN (SELECT id FROM public.merchant_stores
                                               WHERE owner_user_id = v_user))
      THEN v_b := v_b || '"MERCHANT_HAS_MISSION_HISTORY"'::jsonb; END IF;
    IF EXISTS (SELECT 1 FROM public.wallets
                WHERE owner_user_id = v_user AND party_type = 'merchant'::public.party_type)
      THEN v_b := v_b || '"MERCHANT_WALLET_EXISTS"'::jsonb; END IF;
  END IF;

  RETURN jsonb_build_object(
    'user_id', v_user,
    'lane', v_lane,
    'identity_id', v_idid,
    'eligible', (jsonb_array_length(v_b) = 0),
    'blockers', v_b);
END $function$;

REVOKE ALL ON FUNCTION public.professional_identity_release_eligibility(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.professional_identity_release_eligibility(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 2. Atomic self-release
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.professional_identity_self_release(
  _reason text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_lane text;
  v_elig jsonb;
  v_reason text := NULLIF(btrim(COALESCE(_reason,'')), '');
  v_arts jsonb := '{}'::jsonb;
  v_n int;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;

  -- Serialize against any concurrent lane mutation.
  SELECT professional_type INTO v_lane
    FROM public.professional_identities
   WHERE user_id = v_user AND claim_state = 'active'
   FOR UPDATE;

  IF v_lane IS NULL THEN RAISE EXCEPTION 'NO_ACTIVE_PROFESSIONAL_LANE'; END IF;

  -- Serialize against the approval paths (both take FOR UPDATE on these rows).
  IF v_lane = 'driver' THEN
    PERFORM 1 FROM public.driver_profiles WHERE user_id = v_user FOR UPDATE;
  ELSE
    PERFORM 1 FROM public.merchant_stores WHERE owner_user_id = v_user FOR UPDATE;
    PERFORM 1 FROM public.food_restaurants WHERE owner_user_id = v_user FOR UPDATE;
  END IF;

  -- Re-validate INSIDE the lock. Fail closed.
  v_elig := public.professional_identity_release_eligibility(v_user);
  IF (v_elig->>'eligible')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'PROFESSIONAL_RELEASE_BLOCKED: %', (v_elig->'blockers')::text;
  END IF;

  IF v_lane = 'driver' THEN
    UPDATE public.driver_profiles
       SET status = 'withdrawn'::public.driver_status,
           presence = 'offline'::public.driver_presence,
           updated_at = now()
     WHERE user_id = v_user;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_arts := v_arts || jsonb_build_object('driver_profiles', v_n);

    UPDATE public.driver_applications
       SET decision = 'withdrawn'::public.driver_application_decision,
           decision_reason = COALESCE(v_reason, 'self_withdrawn'),
           decided_at = now()
     WHERE user_id = v_user AND decision <> 'approved'::public.driver_application_decision;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_arts := v_arts || jsonb_build_object('driver_applications', v_n);
  ELSE
    UPDATE public.merchant_stores
       SET status = 'archived',
           onboarding_status = 'withdrawn',
           updated_at = now()
     WHERE owner_user_id = v_user AND status <> 'archived';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_arts := v_arts || jsonb_build_object('merchant_stores', v_n);

    UPDATE public.food_restaurants
       SET status = 'archived', updated_at = now()
     WHERE owner_user_id = v_user AND COALESCE(status,'') <> 'archived';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_arts := v_arts || jsonb_build_object('food_restaurants', v_n);

    UPDATE public.merchants
       SET status = 'archived'
     WHERE owner_user_id = v_user AND COALESCE(status,'') <> 'archived';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_arts := v_arts || jsonb_build_object('merchants', v_n);
  END IF;

  PERFORM public._professional_identity_release(
    v_user, COALESCE(v_reason, 'self_release:onboarding_abandoned'));

  BEGIN
    INSERT INTO public.audit_logs (actor_user_id, module, action, target_type, target_id, after, note)
    VALUES (v_user, 'identity', 'professional_identity.self_release',
            'professional_identity', v_user::text,
            jsonb_build_object('lane', v_lane, 'artifacts', v_arts), v_reason);
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object(
    'released', true, 'lane', v_lane, 'artifacts', v_arts, 'reason', v_reason);
END $function$;

REVOKE ALL ON FUNCTION public.professional_identity_self_release(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.professional_identity_self_release(text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. Operational state-transition lock: no approval without a held lane.
--    Closes the release-vs-approval race in the losing direction.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._professional_state_transition_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_type  text := TG_ARGV[0];
  v_owner uuid;
  v_live  boolean;
BEGIN
  IF TG_TABLE_NAME = 'driver_profiles' THEN
    IF NEW.status NOT IN ('approved','suspended') THEN RETURN NEW; END IF;
    IF TG_OP = 'UPDATE' AND OLD.status = NEW.status THEN RETURN NEW; END IF;
    v_owner := NEW.user_id;
  ELSIF TG_TABLE_NAME = 'merchant_stores' THEN
    IF NEW.status NOT IN ('active','suspended','paused')
       AND COALESCE(NEW.onboarding_status,'') <> 'approved' THEN RETURN NEW; END IF;
    IF TG_OP = 'UPDATE'
       AND OLD.status = NEW.status
       AND OLD.onboarding_status IS NOT DISTINCT FROM NEW.onboarding_status THEN RETURN NEW; END IF;
    v_owner := NEW.owner_user_id;
  ELSE
    RETURN NEW;
  END IF;

  IF v_owner IS NULL THEN RETURN NEW; END IF;

  SELECT true INTO v_live FROM public.professional_identities
   WHERE user_id = v_owner AND claim_state = 'active' AND professional_type = v_type
   LIMIT 1;

  IF v_live IS NOT TRUE THEN
    RAISE EXCEPTION 'PROFESSIONAL_LANE_RELEASED';
  END IF;
  RETURN NEW;
END $function$;

DROP TRIGGER IF EXISTS professional_state_transition_guard ON public.driver_profiles;
CREATE TRIGGER professional_state_transition_guard
  BEFORE INSERT OR UPDATE ON public.driver_profiles
  FOR EACH ROW EXECUTE FUNCTION public._professional_state_transition_guard('driver');

DROP TRIGGER IF EXISTS professional_state_transition_guard ON public.merchant_stores;
CREATE TRIGGER professional_state_transition_guard
  BEFORE INSERT OR UPDATE ON public.merchant_stores
  FOR EACH ROW EXECUTE FUNCTION public._professional_state_transition_guard('merchant');

-- ---------------------------------------------------------------------------
-- 4. Same-type re-entry: driver_apply must re-claim the lane explicitly,
--    because the ON CONFLICT UPDATE path leaves user_id unchanged and the
--    A3 artifact guard therefore short-circuits.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.driver_apply(p_payload jsonb)
 RETURNS driver_applications
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_app public.driver_applications;
  v_vehicle public.driver_vehicle_type;
  v_code text;
  v_group public.driver_groups;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT (p_payload ? 'vehicle_type') THEN
    RAISE EXCEPTION 'vehicle_type required';
  END IF;

  -- Node 5 · A4: explicit, idempotent lane claim (also covers re-entry after
  -- a certified A4 release, where the driver_profiles row already exists).
  PERFORM public._professional_lane_require(v_uid, 'driver', 'driver_apply');

  v_vehicle := (p_payload->>'vehicle_type')::public.driver_vehicle_type;

  INSERT INTO public.driver_profiles (
    user_id, status, vehicle_type, plate_number,
    driver_photo_url, id_doc_url, vehicle_photo_url, zones
  ) VALUES (
    v_uid, 'pending', v_vehicle,
    NULLIF(p_payload->>'plate_number',''),
    NULLIF(p_payload->>'driver_photo_url',''),
    NULLIF(p_payload->>'id_doc_url',''),
    NULLIF(p_payload->>'vehicle_photo_url',''),
    COALESCE(ARRAY(SELECT jsonb_array_elements_text(p_payload->'zones')), '{}')
  )
  ON CONFLICT (user_id) DO UPDATE SET
    status = 'pending',
    vehicle_type = EXCLUDED.vehicle_type,
    plate_number = EXCLUDED.plate_number,
    driver_photo_url = COALESCE(EXCLUDED.driver_photo_url, public.driver_profiles.driver_photo_url),
    id_doc_url = COALESCE(EXCLUDED.id_doc_url, public.driver_profiles.id_doc_url),
    vehicle_photo_url = COALESCE(EXCLUDED.vehicle_photo_url, public.driver_profiles.vehicle_photo_url),
    zones = EXCLUDED.zones,
    rejected_reason = NULL,
    suspended_reason = NULL,
    updated_at = now();

  INSERT INTO public.driver_applications (user_id, payload, decision)
  VALUES (v_uid, p_payload, 'pending')
  RETURNING * INTO v_app;

  v_code := NULLIF(trim(p_payload->>'referral_code'), '');
  IF v_code IS NOT NULL THEN
    SELECT * INTO v_group FROM public.driver_groups
      WHERE upper(trim(referral_code)) = upper(v_code) AND status = 'active' LIMIT 1;
    IF v_group.id IS NOT NULL AND v_group.leader_user_id <> v_uid THEN
      BEGIN
        INSERT INTO public.driver_referrals (
          group_id, referrer_user_id, referred_driver_user_id, referral_code, status, bonus_amount_gnf
        ) VALUES (
          v_group.id, v_group.leader_user_id, v_uid, v_code, 'pending', 0
        );
      EXCEPTION WHEN unique_violation THEN NULL;
      END;
    END IF;
  END IF;

  BEGIN
    INSERT INTO public.notification_log (user_id, channel, template, status, payload)
    VALUES (
      v_uid, 'in_app'::public.message_channel, 'driver_application_submitted',
      'pending'::public.notification_status,
      jsonb_build_object('application_id', v_app.id)
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE LOG 'driver_apply notification_log insert failed: %', SQLERRM;
  END;

  RETURN v_app;
END;
$function$;