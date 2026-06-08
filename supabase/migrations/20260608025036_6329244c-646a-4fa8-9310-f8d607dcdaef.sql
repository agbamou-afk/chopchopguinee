
-- ============================================================
-- Driver Groups / Syndicates v2
-- ============================================================

-- 1) Seed Conakry zones (idempotent)
INSERT INTO public.zones (country, city, commune, neighborhood, kind, metadata)
SELECT 'GN', 'Conakry', commune, NULL, 'service', '{}'::jsonb
FROM (VALUES
  ('Kaloum'), ('Dixinn'), ('Ratoma'), ('Matam'), ('Matoto'),
  ('Coyah'), ('Dubréka'), ('Kipé'), ('Lambanyi'), ('Sonfonia'),
  ('Cosa'), ('Bambéto'), ('Madina'), ('Enta'), ('Gbessia'),
  ('Taouyah'), ('Nongo'), ('Wanindara'), ('Hamdallaye'), ('Coleah')
) AS t(commune)
WHERE NOT EXISTS (
  SELECT 1 FROM public.zones z
   WHERE z.country = 'GN' AND z.commune = t.commune AND z.kind = 'service'
);

-- 2) Fraud guardrails: one non-rejected referral per referred driver.
--    (Allows re-attempt only if previous referrals were rejected.)
CREATE UNIQUE INDEX IF NOT EXISTS dr_unique_active_per_driver
  ON public.driver_referrals (referred_driver_user_id)
  WHERE status <> 'rejected';

-- 3) Validate a referral code (public read; no sensitive data).
CREATE OR REPLACE FUNCTION public.validate_referral_code(p_code text)
RETURNS TABLE (
  group_id uuid,
  group_name text,
  leader_name text,
  status text,
  valid boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT g.id, g.name, g.leader_name, g.status,
         (g.status = 'active') AS valid
    FROM public.driver_groups g
   WHERE g.referral_code IS NOT NULL
     AND upper(trim(g.referral_code)) = upper(trim(p_code))
   LIMIT 1;
$$;
GRANT EXECUTE ON FUNCTION public.validate_referral_code(text) TO authenticated, anon;

-- 4) Admin: regenerate a group's referral code
CREATE OR REPLACE FUNCTION public.admin_regenerate_group_referral_code(
  p_group uuid, p_code text DEFAULT NULL
) RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_code text;
  v_name text;
BEGIN
  IF NOT public._is_ops_or_god_admin(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;
  SELECT name INTO v_name FROM public.driver_groups WHERE id = p_group;
  IF v_name IS NULL THEN RAISE EXCEPTION 'group not found'; END IF;
  IF p_code IS NOT NULL AND length(trim(p_code)) > 0 THEN
    v_code := upper(regexp_replace(trim(p_code), '\s+', '-', 'g'));
  ELSE
    v_code := 'CHOP-' ||
      upper(regexp_replace(left(regexp_replace(v_name, '[^A-Za-z0-9]+', '', 'g'), 10), '\s+', '', 'g')) ||
      '-' || lpad((floor(random() * 9000) + 1000)::int::text, 4, '0');
  END IF;
  UPDATE public.driver_groups SET referral_code = v_code, updated_at = now()
   WHERE id = p_group;
  RETURN v_code;
END $$;
GRANT EXECUTE ON FUNCTION public.admin_regenerate_group_referral_code(uuid, text) TO authenticated;

-- 5) driver_apply: accept optional referral_code, create pending referral.
CREATE OR REPLACE FUNCTION public.driver_apply(p_payload jsonb)
RETURNS driver_applications
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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

  -- Optional referral capture (no auto-approve, no auto-bonus)
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
      EXCEPTION WHEN unique_violation THEN
        -- driver already has an active/eligible/paid referral; skip silently
        NULL;
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
$$;

-- 6) Activate group membership from approved referral
CREATE OR REPLACE FUNCTION public._driver_group_on_driver_approval()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_group record;
BEGIN
  IF NEW.status = 'approved' AND (OLD.status IS DISTINCT FROM 'approved') THEN
    UPDATE public.driver_group_memberships
       SET status = 'active'
     WHERE driver_user_id = NEW.user_id AND status = 'pending';

    FOR v_group IN
      SELECT r.id AS referral_id, r.group_id, g.signup_bonus_gnf
        FROM public.driver_referrals r
        LEFT JOIN public.driver_groups g ON g.id = r.group_id
       WHERE r.referred_driver_user_id = NEW.user_id AND r.status = 'pending'
    LOOP
      UPDATE public.driver_referrals
         SET status = 'bonus_eligible',
             approved_at = now(),
             bonus_amount_gnf = COALESCE(v_group.signup_bonus_gnf, 0)
       WHERE id = v_group.referral_id;

      -- Activate driver in their referring group if not yet a member of any group
      IF v_group.group_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.driver_group_memberships
         WHERE driver_user_id = NEW.user_id AND status = 'active'
      ) THEN
        INSERT INTO public.driver_group_memberships (
          group_id, driver_user_id, driver_profile_id, status, added_by, notes
        ) VALUES (
          v_group.group_id, NEW.user_id, NEW.user_id, 'active', NULL,
          'Auto-activated from referral attribution'
        );
      END IF;
    END LOOP;
  END IF;
  RETURN NEW;
END $$;

-- 7) Batch payout: wraps existing wallet_pay_driver_commission per row
CREATE OR REPLACE FUNCTION public.wallet_pay_driver_commission_batch(p_commission_ids uuid[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_id uuid;
  v_paid int := 0;
  v_skipped int := 0;
  v_total bigint := 0;
  v_errors jsonb := '[]'::jsonb;
  v_amount bigint;
  v_status text;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  -- god_admin or finance_admin only
  IF NOT (
    public.has_role(v_caller, 'god_admin'::public.app_role)
    OR public.has_role(v_caller, 'finance_admin'::public.app_role)
  ) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  IF p_commission_ids IS NULL OR array_length(p_commission_ids, 1) IS NULL THEN
    RETURN jsonb_build_object('paid_count', 0, 'skipped_count', 0, 'total_paid_gnf', 0, 'errors', v_errors);
  END IF;

  FOREACH v_id IN ARRAY p_commission_ids LOOP
    BEGIN
      SELECT status, commission_amount_gnf INTO v_status, v_amount
        FROM public.driver_group_commissions WHERE id = v_id FOR UPDATE;
      IF v_status IS NULL OR v_status NOT IN ('pending', 'approved') THEN
        v_skipped := v_skipped + 1;
        CONTINUE;
      END IF;
      PERFORM public.wallet_pay_driver_commission(v_id);
      v_paid := v_paid + 1;
      v_total := v_total + COALESCE(v_amount, 0);
    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors || jsonb_build_object('id', v_id, 'error', SQLERRM);
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'paid_count', v_paid,
    'skipped_count', v_skipped,
    'total_paid_gnf', v_total,
    'errors', v_errors
  );
END $$;
GRANT EXECUTE ON FUNCTION public.wallet_pay_driver_commission_batch(uuid[]) TO authenticated;
