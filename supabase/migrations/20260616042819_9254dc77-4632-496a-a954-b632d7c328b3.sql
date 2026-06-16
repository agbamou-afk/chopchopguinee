
-- 1. Roles
DO $$ BEGIN
  ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'field_captain';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TYPE public.app_role ADD VALUE IF NOT EXISTS 'field_agent';
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 2. Enums
DO $$ BEGIN
  CREATE TYPE public.field_pilot_status AS ENUM ('planned','active','paused','completed','cancelled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.field_assignment_role AS ENUM ('field_captain','field_agent','verifier');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.field_assignment_status AS ENUM ('active','paused','completed','removed');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.field_visit_interest AS ENUM ('cold','interested','signed_up','needs_follow_up','rejected');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.field_visit_status AS ENUM ('visited','submitted','duplicate_possible','needs_review','converted','rejected');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE public.field_report_status AS ENUM ('submitted','reviewed','needs_correction','approved');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 3. Tables
CREATE TABLE IF NOT EXISTS public.field_pilots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  start_date date,
  end_date date,
  status public.field_pilot_status NOT NULL DEFAULT 'planned',
  target_merchant_count integer DEFAULT 0,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.field_pilots TO authenticated;
GRANT ALL ON public.field_pilots TO service_role;
ALTER TABLE public.field_pilots ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.field_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pilot_id uuid NOT NULL REFERENCES public.field_pilots(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role public.field_assignment_role NOT NULL DEFAULT 'field_agent',
  assigned_zone_id uuid REFERENCES public.map_service_zones(id) ON DELETE SET NULL,
  status public.field_assignment_status NOT NULL DEFAULT 'active',
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_field_assignments_pilot ON public.field_assignments(pilot_id);
CREATE INDEX IF NOT EXISTS idx_field_assignments_user ON public.field_assignments(user_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.field_assignments TO authenticated;
GRANT ALL ON public.field_assignments TO service_role;
ALTER TABLE public.field_assignments ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.field_merchant_visits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pilot_id uuid NOT NULL REFERENCES public.field_pilots(id) ON DELETE CASCADE,
  assigned_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  field_captain_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  map_service_zone_id uuid REFERENCES public.map_service_zones(id) ON DELETE SET NULL,
  merchant_name text NOT NULL,
  merchant_phone text,
  merchant_category text,
  interest_level public.field_visit_interest NOT NULL DEFAULT 'cold',
  visit_status public.field_visit_status NOT NULL DEFAULT 'visited',
  lat double precision,
  lng double precision,
  address_text text,
  landmark_note text,
  entrance_note text,
  pickup_note text,
  notes text,
  photo_url text,
  linked_merchant_store_id uuid,
  linked_map_place_id uuid REFERENCES public.map_places(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_field_visits_pilot ON public.field_merchant_visits(pilot_id);
CREATE INDEX IF NOT EXISTS idx_field_visits_user ON public.field_merchant_visits(assigned_user_id);
CREATE INDEX IF NOT EXISTS idx_field_visits_zone ON public.field_merchant_visits(map_service_zone_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.field_merchant_visits TO authenticated;
GRANT ALL ON public.field_merchant_visits TO service_role;
ALTER TABLE public.field_merchant_visits ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.field_daily_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pilot_id uuid NOT NULL REFERENCES public.field_pilots(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  report_date date NOT NULL DEFAULT (now()::date),
  zone_id uuid REFERENCES public.map_service_zones(id) ON DELETE SET NULL,
  merchants_visited_count integer NOT NULL DEFAULT 0,
  merchants_submitted_count integer NOT NULL DEFAULT 0,
  merchants_interested_count integer NOT NULL DEFAULT 0,
  merchants_converted_count integer NOT NULL DEFAULT 0,
  transport_morning_paid boolean NOT NULL DEFAULT false,
  transport_return_paid boolean NOT NULL DEFAULT false,
  notes text,
  submitted_at timestamptz NOT NULL DEFAULT now(),
  reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  status public.field_report_status NOT NULL DEFAULT 'submitted',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (pilot_id, user_id, report_date)
);
CREATE INDEX IF NOT EXISTS idx_field_reports_pilot ON public.field_daily_reports(pilot_id);
CREATE INDEX IF NOT EXISTS idx_field_reports_user ON public.field_daily_reports(user_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.field_daily_reports TO authenticated;
GRANT ALL ON public.field_daily_reports TO service_role;
ALTER TABLE public.field_daily_reports ENABLE ROW LEVEL SECURITY;

-- 4. Helpers
CREATE OR REPLACE FUNCTION public.is_field_captain_of_pilot(_user uuid, _pilot uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.field_assignments
    WHERE pilot_id = _pilot AND user_id = _user
      AND role = 'field_captain' AND status = 'active'
  );
$$;

CREATE OR REPLACE FUNCTION public.is_assigned_to_pilot(_user uuid, _pilot uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.field_assignments
    WHERE pilot_id = _pilot AND user_id = _user AND status = 'active'
  );
$$;

-- 5. RLS policies

-- field_pilots
DROP POLICY IF EXISTS "admins manage pilots" ON public.field_pilots;
CREATE POLICY "admins manage pilots" ON public.field_pilots
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'god_admin') OR public.has_role(auth.uid(), 'operations_admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'god_admin') OR public.has_role(auth.uid(), 'operations_admin'));

DROP POLICY IF EXISTS "assigned read pilot" ON public.field_pilots;
CREATE POLICY "assigned read pilot" ON public.field_pilots
  FOR SELECT TO authenticated
  USING (public.is_assigned_to_pilot(auth.uid(), id));

-- field_assignments
DROP POLICY IF EXISTS "admins manage assignments" ON public.field_assignments;
CREATE POLICY "admins manage assignments" ON public.field_assignments
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'god_admin') OR public.has_role(auth.uid(), 'operations_admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'god_admin') OR public.has_role(auth.uid(), 'operations_admin'));

DROP POLICY IF EXISTS "user reads own assignment" ON public.field_assignments;
CREATE POLICY "user reads own assignment" ON public.field_assignments
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_field_captain_of_pilot(auth.uid(), pilot_id));

-- field_merchant_visits
DROP POLICY IF EXISTS "admins manage visits" ON public.field_merchant_visits;
CREATE POLICY "admins manage visits" ON public.field_merchant_visits
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'god_admin') OR public.has_role(auth.uid(), 'operations_admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'god_admin') OR public.has_role(auth.uid(), 'operations_admin'));

DROP POLICY IF EXISTS "agents insert own visits" ON public.field_merchant_visits;
CREATE POLICY "agents insert own visits" ON public.field_merchant_visits
  FOR INSERT TO authenticated
  WITH CHECK (assigned_user_id = auth.uid() AND public.is_assigned_to_pilot(auth.uid(), pilot_id));

DROP POLICY IF EXISTS "agents read own visits" ON public.field_merchant_visits;
CREATE POLICY "agents read own visits" ON public.field_merchant_visits
  FOR SELECT TO authenticated
  USING (assigned_user_id = auth.uid() OR public.is_field_captain_of_pilot(auth.uid(), pilot_id));

DROP POLICY IF EXISTS "agents update own visits" ON public.field_merchant_visits;
CREATE POLICY "agents update own visits" ON public.field_merchant_visits
  FOR UPDATE TO authenticated
  USING (assigned_user_id = auth.uid())
  WITH CHECK (assigned_user_id = auth.uid());

-- field_daily_reports
DROP POLICY IF EXISTS "admins manage reports" ON public.field_daily_reports;
CREATE POLICY "admins manage reports" ON public.field_daily_reports
  FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'god_admin') OR public.has_role(auth.uid(), 'operations_admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin') OR public.has_role(auth.uid(), 'god_admin') OR public.has_role(auth.uid(), 'operations_admin'));

DROP POLICY IF EXISTS "agents insert own reports" ON public.field_daily_reports;
CREATE POLICY "agents insert own reports" ON public.field_daily_reports
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() AND public.is_assigned_to_pilot(auth.uid(), pilot_id));

DROP POLICY IF EXISTS "agents read own or captain reports" ON public.field_daily_reports;
CREATE POLICY "agents read own or captain reports" ON public.field_daily_reports
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_field_captain_of_pilot(auth.uid(), pilot_id));

DROP POLICY IF EXISTS "agents update own pending reports" ON public.field_daily_reports;
CREATE POLICY "agents update own pending reports" ON public.field_daily_reports
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid() AND status IN ('submitted','needs_correction'))
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "captain reviews reports" ON public.field_daily_reports;
CREATE POLICY "captain reviews reports" ON public.field_daily_reports
  FOR UPDATE TO authenticated
  USING (public.is_field_captain_of_pilot(auth.uid(), pilot_id) AND user_id <> auth.uid())
  WITH CHECK (public.is_field_captain_of_pilot(auth.uid(), pilot_id) AND user_id <> auth.uid());

-- 6. updated_at triggers
CREATE OR REPLACE FUNCTION public.field_touch_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

DROP TRIGGER IF EXISTS trg_field_pilots_updated ON public.field_pilots;
CREATE TRIGGER trg_field_pilots_updated BEFORE UPDATE ON public.field_pilots
  FOR EACH ROW EXECUTE FUNCTION public.field_touch_updated_at();
DROP TRIGGER IF EXISTS trg_field_assignments_updated ON public.field_assignments;
CREATE TRIGGER trg_field_assignments_updated BEFORE UPDATE ON public.field_assignments
  FOR EACH ROW EXECUTE FUNCTION public.field_touch_updated_at();
DROP TRIGGER IF EXISTS trg_field_visits_updated ON public.field_merchant_visits;
CREATE TRIGGER trg_field_visits_updated BEFORE UPDATE ON public.field_merchant_visits
  FOR EACH ROW EXECUTE FUNCTION public.field_touch_updated_at();
DROP TRIGGER IF EXISTS trg_field_reports_updated ON public.field_daily_reports;
CREATE TRIGGER trg_field_reports_updated BEFORE UPDATE ON public.field_daily_reports
  FOR EACH ROW EXECUTE FUNCTION public.field_touch_updated_at();

-- 7. RPC: agent submit visit (handles optional map_place creation + duplicate flag)
CREATE OR REPLACE FUNCTION public.field_submit_visit(
  p_pilot_id uuid,
  p_merchant_name text,
  p_merchant_phone text DEFAULT NULL,
  p_merchant_category text DEFAULT NULL,
  p_interest_level public.field_visit_interest DEFAULT 'cold',
  p_lat double precision DEFAULT NULL,
  p_lng double precision DEFAULT NULL,
  p_address_text text DEFAULT NULL,
  p_landmark_note text DEFAULT NULL,
  p_entrance_note text DEFAULT NULL,
  p_pickup_note text DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_zone_id uuid DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user uuid := auth.uid();
  v_visit_id uuid;
  v_place_id uuid;
  v_visit_status public.field_visit_status := 'visited';
  v_dup_count integer := 0;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF NOT public.is_assigned_to_pilot(v_user, p_pilot_id) THEN
    RAISE EXCEPTION 'not assigned to pilot';
  END IF;

  IF p_lat IS NOT NULL AND p_lng IS NOT NULL THEN
    -- duplicate proximity scan (~120m, rough lat/lng box)
    SELECT count(*) INTO v_dup_count FROM public.map_places
      WHERE active = true
        AND abs(lat - p_lat) < 0.0012
        AND abs(lng - p_lng) < 0.0012;

    INSERT INTO public.map_places (
      name, lat, lng, source, verification_status, confidence_score,
      categories, notes, active
    ) VALUES (
      p_merchant_name, p_lat, p_lng, 'field_visit', 'submitted', 35,
      CASE WHEN p_merchant_category IS NULL THEN NULL ELSE ARRAY[p_merchant_category] END,
      p_landmark_note, true
    )
    RETURNING id INTO v_place_id;

    IF v_dup_count > 0 THEN
      v_visit_status := 'duplicate_possible';
    ELSE
      v_visit_status := 'submitted';
    END IF;
  END IF;

  INSERT INTO public.field_merchant_visits (
    pilot_id, assigned_user_id, map_service_zone_id, merchant_name, merchant_phone,
    merchant_category, interest_level, visit_status, lat, lng, address_text,
    landmark_note, entrance_note, pickup_note, notes, linked_map_place_id
  ) VALUES (
    p_pilot_id, v_user, p_zone_id, p_merchant_name, p_merchant_phone,
    p_merchant_category, p_interest_level, v_visit_status, p_lat, p_lng, p_address_text,
    p_landmark_note, p_entrance_note, p_pickup_note, p_notes, v_place_id
  ) RETURNING id INTO v_visit_id;

  RETURN v_visit_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.field_submit_visit(uuid, text, text, text, public.field_visit_interest, double precision, double precision, text, text, text, text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_field_captain_of_pilot(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_assigned_to_pilot(uuid, uuid) TO authenticated;
