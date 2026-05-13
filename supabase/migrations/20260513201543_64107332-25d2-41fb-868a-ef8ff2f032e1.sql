
-- ============================================================
-- Day 5 — Driver operational system
-- ============================================================

-- Enums --------------------------------------------------------
DO $$ BEGIN
  CREATE TYPE public.driver_status AS ENUM ('pending','approved','rejected','suspended');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.driver_vehicle_type AS ENUM ('moto','toktok','livraison','auto');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.driver_presence AS ENUM ('offline','online','on_trip');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.ride_offer_status AS ENUM ('pending','accepted','declined','missed','expired','cancelled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.driver_application_decision AS ENUM ('pending','approved','rejected','more_info');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- driver_profiles ----------------------------------------------
CREATE TABLE IF NOT EXISTS public.driver_profiles (
  user_id uuid PRIMARY KEY,
  status public.driver_status NOT NULL DEFAULT 'pending',
  vehicle_type public.driver_vehicle_type NOT NULL DEFAULT 'moto',
  plate_number text,
  driver_photo_url text,
  id_doc_url text,
  vehicle_photo_url text,
  zones text[] NOT NULL DEFAULT '{}',
  rating numeric(3,2) NOT NULL DEFAULT 0,
  accept_rate numeric(5,4) NOT NULL DEFAULT 0,
  cash_debt_gnf bigint NOT NULL DEFAULT 0,
  debt_limit_gnf bigint NOT NULL DEFAULT 200000,
  presence public.driver_presence NOT NULL DEFAULT 'offline',
  last_seen_at timestamptz,
  approved_at timestamptz,
  approved_by uuid,
  rejected_reason text,
  suspended_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.driver_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Drivers read own profile" ON public.driver_profiles;
CREATE POLICY "Drivers read own profile" ON public.driver_profiles
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Drivers update own profile" ON public.driver_profiles;
CREATE POLICY "Drivers update own profile" ON public.driver_profiles
  FOR UPDATE TO authenticated USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Admins manage driver profiles" ON public.driver_profiles;
CREATE POLICY "Admins manage driver profiles" ON public.driver_profiles
  FOR ALL TO authenticated USING (public.can_manage_operations(auth.uid()))
  WITH CHECK (public.can_manage_operations(auth.uid()));

CREATE INDEX IF NOT EXISTS idx_driver_profiles_status ON public.driver_profiles(status);
CREATE INDEX IF NOT EXISTS idx_driver_profiles_presence ON public.driver_profiles(presence);

-- driver_applications ------------------------------------------
CREATE TABLE IF NOT EXISTS public.driver_applications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  decision public.driver_application_decision NOT NULL DEFAULT 'pending',
  decision_reason text,
  decided_by uuid,
  decided_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.driver_applications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read own applications" ON public.driver_applications;
CREATE POLICY "Users read own applications" ON public.driver_applications
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Admins manage applications" ON public.driver_applications;
CREATE POLICY "Admins manage applications" ON public.driver_applications
  FOR ALL TO authenticated USING (public.can_manage_operations(auth.uid()))
  WITH CHECK (public.can_manage_operations(auth.uid()));

CREATE INDEX IF NOT EXISTS idx_driver_apps_user ON public.driver_applications(user_id);
CREATE INDEX IF NOT EXISTS idx_driver_apps_decision ON public.driver_applications(decision);

-- ride_offers --------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ride_offers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id uuid NOT NULL,
  driver_id uuid NOT NULL,
  status public.ride_offer_status NOT NULL DEFAULT 'pending',
  estimated_fare_gnf bigint,
  estimated_earning_gnf bigint,
  pickup_zone text,
  destination_zone text,
  distance_to_pickup_m integer,
  decline_reason text,
  sent_at timestamptz NOT NULL DEFAULT now(),
  responded_at timestamptz,
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '20 seconds')
);

ALTER TABLE public.ride_offers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Drivers read own offers" ON public.ride_offers;
CREATE POLICY "Drivers read own offers" ON public.ride_offers
  FOR SELECT TO authenticated USING (auth.uid() = driver_id);

DROP POLICY IF EXISTS "Clients read offers for own ride" ON public.ride_offers;
CREATE POLICY "Clients read offers for own ride" ON public.ride_offers
  FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public.rides r WHERE r.id = ride_offers.ride_id AND r.client_id = auth.uid())
  );

DROP POLICY IF EXISTS "Admins manage offers" ON public.ride_offers;
CREATE POLICY "Admins manage offers" ON public.ride_offers
  FOR ALL TO authenticated USING (public.can_manage_operations(auth.uid()))
  WITH CHECK (public.can_manage_operations(auth.uid()));

CREATE INDEX IF NOT EXISTS idx_ride_offers_driver ON public.ride_offers(driver_id, status);
CREATE INDEX IF NOT EXISTS idx_ride_offers_ride ON public.ride_offers(ride_id);

-- driver_cash_ledger -------------------------------------------
CREATE TABLE IF NOT EXISTS public.driver_cash_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id uuid NOT NULL,
  ride_id uuid,
  cash_collected_gnf bigint NOT NULL DEFAULT 0,
  commission_owed_gnf bigint NOT NULL DEFAULT 0,
  settled_at timestamptz,
  settled_amount_gnf bigint NOT NULL DEFAULT 0,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.driver_cash_ledger ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Drivers read own cash" ON public.driver_cash_ledger;
CREATE POLICY "Drivers read own cash" ON public.driver_cash_ledger
  FOR SELECT TO authenticated USING (auth.uid() = driver_id);

DROP POLICY IF EXISTS "Admins manage cash ledger" ON public.driver_cash_ledger;
CREATE POLICY "Admins manage cash ledger" ON public.driver_cash_ledger
  FOR ALL TO authenticated USING (public.can_manage_operations(auth.uid()))
  WITH CHECK (public.can_manage_operations(auth.uid()));

CREATE INDEX IF NOT EXISTS idx_cash_ledger_driver ON public.driver_cash_ledger(driver_id, settled_at);

-- updated_at trigger -------------------------------------------
DROP TRIGGER IF EXISTS trg_driver_profiles_updated_at ON public.driver_profiles;
CREATE TRIGGER trg_driver_profiles_updated_at
  BEFORE UPDATE ON public.driver_profiles
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Storage bucket -----------------------------------------------
INSERT INTO storage.buckets (id, name, public)
VALUES ('driver-docs', 'driver-docs', false)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Drivers read own docs" ON storage.objects;
CREATE POLICY "Drivers read own docs" ON storage.objects
  FOR SELECT TO authenticated USING (
    bucket_id = 'driver-docs' AND auth.uid()::text = (storage.foldername(name))[1]
  );

DROP POLICY IF EXISTS "Drivers upload own docs" ON storage.objects;
CREATE POLICY "Drivers upload own docs" ON storage.objects
  FOR INSERT TO authenticated WITH CHECK (
    bucket_id = 'driver-docs' AND auth.uid()::text = (storage.foldername(name))[1]
  );

DROP POLICY IF EXISTS "Drivers update own docs" ON storage.objects;
CREATE POLICY "Drivers update own docs" ON storage.objects
  FOR UPDATE TO authenticated USING (
    bucket_id = 'driver-docs' AND auth.uid()::text = (storage.foldername(name))[1]
  );

DROP POLICY IF EXISTS "Admins read all driver docs" ON storage.objects;
CREATE POLICY "Admins read all driver docs" ON storage.objects
  FOR SELECT TO authenticated USING (
    bucket_id = 'driver-docs' AND public.can_manage_operations(auth.uid())
  );

-- ============================================================
-- RPCs
-- ============================================================

-- driver_apply --------------------------------------------------
CREATE OR REPLACE FUNCTION public.driver_apply(p_payload jsonb)
RETURNS public.driver_applications
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_app public.driver_applications;
  v_vehicle public.driver_vehicle_type;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT (p_payload ? 'vehicle_type') THEN
    RAISE EXCEPTION 'vehicle_type required';
  END IF;

  v_vehicle := (p_payload->>'vehicle_type')::public.driver_vehicle_type;

  -- Upsert driver_profiles in pending state (preserve existing if rejected/suspended → re-apply)
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

  -- Notification log
  INSERT INTO public.notification_log (user_id, channel, template, status, payload)
  VALUES (
    v_uid, 'in_app'::message_channel, 'driver_application_submitted',
    'pending'::notification_status,
    jsonb_build_object('application_id', v_app.id)
  );

  RETURN v_app;
END;
$$;

-- driver_admin_decide -------------------------------------------
CREATE OR REPLACE FUNCTION public.driver_admin_decide(
  p_user_id uuid,
  p_decision text, -- 'approve' | 'reject' | 'suspend' | 'reactivate' | 'more_info'
  p_reason text DEFAULT NULL
)
RETURNS public.driver_profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_profile public.driver_profiles;
  v_app_id uuid;
  v_template text;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.can_manage_operations(v_caller) THEN
    RAISE EXCEPTION 'Only operations or god admins can decide';
  END IF;

  SELECT * INTO v_profile FROM public.driver_profiles WHERE user_id = p_user_id FOR UPDATE;
  IF v_profile.user_id IS NULL THEN RAISE EXCEPTION 'Driver profile not found'; END IF;

  IF p_decision = 'approve' THEN
    UPDATE public.driver_profiles SET
      status = 'approved', approved_at = now(), approved_by = v_caller,
      rejected_reason = NULL, suspended_reason = NULL
      WHERE user_id = p_user_id RETURNING * INTO v_profile;

    -- Grant driver role
    INSERT INTO public.user_roles (user_id, role) VALUES (p_user_id, 'driver'::public.app_role)
      ON CONFLICT DO NOTHING;

    -- Ensure driver wallet
    INSERT INTO public.wallets (owner_user_id, party_type) VALUES (p_user_id, 'driver')
      ON CONFLICT (owner_user_id, party_type) DO NOTHING;

    v_template := 'driver_approved';

  ELSIF p_decision = 'reject' THEN
    UPDATE public.driver_profiles SET
      status = 'rejected', rejected_reason = p_reason
      WHERE user_id = p_user_id RETURNING * INTO v_profile;
    v_template := 'driver_rejected';

  ELSIF p_decision = 'suspend' THEN
    UPDATE public.driver_profiles SET
      status = 'suspended', suspended_reason = p_reason, presence = 'offline'
      WHERE user_id = p_user_id RETURNING * INTO v_profile;
    v_template := 'driver_suspended';

  ELSIF p_decision = 'reactivate' THEN
    UPDATE public.driver_profiles SET
      status = 'approved', suspended_reason = NULL
      WHERE user_id = p_user_id RETURNING * INTO v_profile;
    v_template := 'driver_reactivated';

  ELSIF p_decision = 'more_info' THEN
    v_template := 'driver_more_info';

  ELSE
    RAISE EXCEPTION 'Unknown decision %', p_decision;
  END IF;

  -- Update latest application
  SELECT id INTO v_app_id FROM public.driver_applications
    WHERE user_id = p_user_id ORDER BY created_at DESC LIMIT 1;
  IF v_app_id IS NOT NULL THEN
    UPDATE public.driver_applications SET
      decision = (CASE
        WHEN p_decision = 'approve' THEN 'approved'::driver_application_decision
        WHEN p_decision = 'reject' THEN 'rejected'::driver_application_decision
        WHEN p_decision = 'more_info' THEN 'more_info'::driver_application_decision
        ELSE decision END),
      decision_reason = p_reason,
      decided_by = v_caller,
      decided_at = now()
      WHERE id = v_app_id;
  END IF;

  -- Audit log
  INSERT INTO public.audit_logs (actor_user_id, actor_role, module, action, target_type, target_id, after, note)
  VALUES (
    v_caller, public.current_admin_role(v_caller),
    'drivers', 'driver.' || p_decision, 'driver_profile', p_user_id::text,
    jsonb_build_object('status', v_profile.status, 'reason', p_reason),
    p_reason
  );

  -- Notification
  INSERT INTO public.notification_log (user_id, channel, template, status, payload)
  VALUES (
    p_user_id, 'in_app'::message_channel, v_template,
    'pending'::notification_status,
    jsonb_build_object('reason', p_reason)
  );

  RETURN v_profile;
END;
$$;

-- driver_set_status (online/offline) ----------------------------
CREATE OR REPLACE FUNCTION public.driver_set_status(p_status public.driver_presence)
RETURNS public.driver_profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_profile public.driver_profiles;
  v_phone text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_profile FROM public.driver_profiles WHERE user_id = v_uid FOR UPDATE;
  IF v_profile.user_id IS NULL THEN RAISE EXCEPTION 'No driver profile'; END IF;

  IF p_status = 'online' THEN
    IF v_profile.status <> 'approved' THEN
      RAISE EXCEPTION 'Driver not approved';
    END IF;
    SELECT phone INTO v_phone FROM public.profiles WHERE user_id = v_uid;
    IF v_phone IS NULL OR v_phone = '' THEN
      RAISE EXCEPTION 'Phone number required';
    END IF;
    IF v_profile.cash_debt_gnf >= v_profile.debt_limit_gnf AND v_profile.debt_limit_gnf > 0 THEN
      RAISE EXCEPTION 'Cash debt exceeds limit. Settle commission first.';
    END IF;
    INSERT INTO public.wallets (owner_user_id, party_type) VALUES (v_uid, 'driver')
      ON CONFLICT (owner_user_id, party_type) DO NOTHING;
  END IF;

  UPDATE public.driver_profiles SET
    presence = p_status,
    last_seen_at = now()
    WHERE user_id = v_uid RETURNING * INTO v_profile;

  RETURN v_profile;
END;
$$;

-- driver_offer_accept -------------------------------------------
CREATE OR REPLACE FUNCTION public.driver_offer_accept(p_offer_id uuid)
RETURNS public.ride_offers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_offer public.ride_offers;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO v_offer FROM public.ride_offers WHERE id = p_offer_id FOR UPDATE;
  IF v_offer.id IS NULL THEN RAISE EXCEPTION 'Offer not found'; END IF;
  IF v_offer.driver_id <> v_uid THEN RAISE EXCEPTION 'Not your offer'; END IF;
  IF v_offer.status <> 'pending' THEN RAISE EXCEPTION 'Offer no longer pending'; END IF;
  IF v_offer.expires_at < now() THEN
    UPDATE public.ride_offers SET status='expired', responded_at=now() WHERE id=p_offer_id;
    RAISE EXCEPTION 'Offer expired';
  END IF;

  PERFORM public.ride_accept(v_offer.ride_id);

  UPDATE public.ride_offers SET status='accepted', responded_at=now()
    WHERE id = p_offer_id RETURNING * INTO v_offer;

  UPDATE public.driver_profiles SET presence='on_trip', last_seen_at=now()
    WHERE user_id = v_uid;

  RETURN v_offer;
END;
$$;

-- driver_offer_decline ------------------------------------------
CREATE OR REPLACE FUNCTION public.driver_offer_decline(p_offer_id uuid, p_reason text DEFAULT NULL)
RETURNS public.ride_offers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_offer public.ride_offers;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  UPDATE public.ride_offers SET
    status = 'declined', decline_reason = p_reason, responded_at = now()
    WHERE id = p_offer_id AND driver_id = v_uid AND status = 'pending'
    RETURNING * INTO v_offer;
  IF v_offer.id IS NULL THEN RAISE EXCEPTION 'Cannot decline this offer'; END IF;
  RETURN v_offer;
END;
$$;

-- driver_cash_settle (admin) ------------------------------------
CREATE OR REPLACE FUNCTION public.driver_cash_settle(
  p_driver_user_id uuid,
  p_amount_gnf bigint,
  p_note text DEFAULT NULL
)
RETURNS public.driver_cash_ledger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_row public.driver_cash_ledger;
BEGIN
  IF v_caller IS NULL OR NOT public.can_manage_operations(v_caller) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  IF p_amount_gnf <= 0 THEN RAISE EXCEPTION 'Amount must be positive'; END IF;

  INSERT INTO public.driver_cash_ledger (driver_id, cash_collected_gnf, commission_owed_gnf, settled_at, settled_amount_gnf, note)
  VALUES (p_driver_user_id, 0, 0, now(), p_amount_gnf, COALESCE(p_note, 'Manual cash settlement'))
  RETURNING * INTO v_row;

  UPDATE public.driver_profiles
    SET cash_debt_gnf = GREATEST(cash_debt_gnf - p_amount_gnf, 0)
    WHERE user_id = p_driver_user_id;

  INSERT INTO public.audit_logs (actor_user_id, actor_role, module, action, target_type, target_id, after, note)
  VALUES (v_caller, public.current_admin_role(v_caller), 'drivers', 'driver.cash.settle',
    'driver_profile', p_driver_user_id::text,
    jsonb_build_object('amount_gnf', p_amount_gnf), p_note);

  RETURN v_row;
END;
$$;
