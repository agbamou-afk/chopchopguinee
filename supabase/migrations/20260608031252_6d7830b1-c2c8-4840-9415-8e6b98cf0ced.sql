
-- ============================================================
-- DRIVER SYNDICATES V4
-- ============================================================

-- ---------- 1. Milestone job queue ----------
CREATE TABLE IF NOT EXISTS public.driver_referral_milestone_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  referral_id uuid,
  driver_user_id uuid,
  ride_id uuid,
  event_type text NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  attempts integer NOT NULL DEFAULT 0,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  CONSTRAINT drmj_event_chk CHECK (event_type IN ('driver_approved','ride_completed','manual_refresh','seven_day_check')),
  CONSTRAINT drmj_status_chk CHECK (status IN ('pending','processing','processed','failed'))
);
CREATE INDEX IF NOT EXISTS drmj_pending_idx ON public.driver_referral_milestone_jobs(created_at) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS drmj_driver_idx ON public.driver_referral_milestone_jobs(driver_user_id);

GRANT SELECT ON public.driver_referral_milestone_jobs TO authenticated;
GRANT ALL ON public.driver_referral_milestone_jobs TO service_role;
ALTER TABLE public.driver_referral_milestone_jobs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admins manage milestone jobs" ON public.driver_referral_milestone_jobs;
CREATE POLICY "admins manage milestone jobs" ON public.driver_referral_milestone_jobs
  TO authenticated
  USING (public._is_ops_or_god_admin(auth.uid()))
  WITH CHECK (public._is_ops_or_god_admin(auth.uid()));

-- Replace heavy ride trigger with a lightweight enqueue trigger
DROP TRIGGER IF EXISTS trg_dr_milestones_on_ride ON public.rides;
DROP FUNCTION IF EXISTS public._dr_milestones_on_ride_complete();

CREATE OR REPLACE FUNCTION public._dr_milestones_enqueue_on_ride()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status::text = 'completed' AND (OLD.status::text IS DISTINCT FROM 'completed') AND NEW.driver_id IS NOT NULL THEN
    BEGIN
      -- Only enqueue if this driver has any active referral
      IF EXISTS (
        SELECT 1 FROM public.driver_referrals
        WHERE referred_driver_user_id = NEW.driver_id AND status NOT IN ('rejected','paid')
      ) THEN
        INSERT INTO public.driver_referral_milestone_jobs (driver_user_id, ride_id, event_type)
        VALUES (NEW.driver_id, NEW.id, 'ride_completed');
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'milestone enqueue failed: %', SQLERRM;
    END;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_dr_milestones_enqueue
  AFTER UPDATE OF status ON public.rides
  FOR EACH ROW EXECUTE FUNCTION public._dr_milestones_enqueue_on_ride();

-- Job processor
CREATE OR REPLACE FUNCTION public.process_driver_referral_milestone_jobs(p_limit integer DEFAULT 50)
RETURNS TABLE(processed integer, failed integer, eligible integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  r RECORD;
  v_processed integer := 0;
  v_failed integer := 0;
  v_eligible integer := 0;
  v_pre_eligible integer;
  v_post_eligible integer;
BEGIN
  IF NOT public._is_ops_or_god_admin(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE='42501';
  END IF;

  FOR r IN
    SELECT * FROM public.driver_referral_milestone_jobs
     WHERE status = 'pending'
     ORDER BY created_at
     LIMIT p_limit
     FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE public.driver_referral_milestone_jobs
      SET status = 'processing', attempts = attempts + 1
      WHERE id = r.id;
    BEGIN
      SELECT COUNT(*) INTO v_pre_eligible FROM public.driver_referrals
        WHERE referred_driver_user_id = r.driver_user_id AND status = 'bonus_eligible';
      PERFORM public.refresh_driver_referral_milestones(r.driver_user_id);
      SELECT COUNT(*) INTO v_post_eligible FROM public.driver_referrals
        WHERE referred_driver_user_id = r.driver_user_id AND status = 'bonus_eligible';
      v_eligible := v_eligible + GREATEST(v_post_eligible - v_pre_eligible, 0);
      UPDATE public.driver_referral_milestone_jobs
        SET status = 'processed', processed_at = now(), last_error = NULL
        WHERE id = r.id;
      v_processed := v_processed + 1;
    EXCEPTION WHEN OTHERS THEN
      UPDATE public.driver_referral_milestone_jobs
        SET status = CASE WHEN attempts >= 5 THEN 'failed' ELSE 'pending' END,
            last_error = SQLERRM
        WHERE id = r.id;
      v_failed := v_failed + 1;
    END;
  END LOOP;
  RETURN QUERY SELECT v_processed, v_failed, v_eligible;
END;
$$;
REVOKE ALL ON FUNCTION public.process_driver_referral_milestone_jobs(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.process_driver_referral_milestone_jobs(integer) TO authenticated, service_role;

-- Admin manual enqueue (e.g. backfill or driver_approved event)
CREATE OR REPLACE FUNCTION public.admin_enqueue_milestone_refresh(p_driver uuid, p_event text DEFAULT 'manual_refresh')
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  IF NOT public._is_ops_or_god_admin(auth.uid()) THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  INSERT INTO public.driver_referral_milestone_jobs (driver_user_id, event_type)
    VALUES (p_driver, p_event) RETURNING id INTO v_id;
  RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION public.admin_enqueue_milestone_refresh(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_enqueue_milestone_refresh(uuid,text) TO authenticated, service_role;

-- ---------- 2. Field check-ins ----------
CREATE TABLE IF NOT EXISTS public.driver_group_field_checkins (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL REFERENCES public.driver_groups(id) ON DELETE CASCADE,
  leader_user_id uuid,
  driver_user_id uuid,
  zone_id uuid REFERENCES public.zones(id) ON DELETE SET NULL,
  checkin_type text NOT NULL DEFAULT 'field_visit',
  lat double precision,
  lng double precision,
  accuracy_m double precision,
  notes text,
  photo_url text,
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT dgfc_type_chk CHECK (checkin_type IN ('field_visit','recruitment_visit','driver_meeting','market_station','issue_report','training'))
);
CREATE INDEX IF NOT EXISTS dgfc_group_idx ON public.driver_group_field_checkins(group_id, created_at DESC);
CREATE INDEX IF NOT EXISTS dgfc_zone_idx ON public.driver_group_field_checkins(zone_id);

GRANT SELECT, INSERT ON public.driver_group_field_checkins TO authenticated;
GRANT ALL ON public.driver_group_field_checkins TO service_role;
ALTER TABLE public.driver_group_field_checkins ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admins manage checkins" ON public.driver_group_field_checkins;
CREATE POLICY "admins manage checkins" ON public.driver_group_field_checkins
  TO authenticated
  USING (public._is_ops_or_god_admin(auth.uid()))
  WITH CHECK (public._is_ops_or_god_admin(auth.uid()));

DROP POLICY IF EXISTS "leaders read own checkins" ON public.driver_group_field_checkins;
CREATE POLICY "leaders read own checkins" ON public.driver_group_field_checkins
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.driver_groups g WHERE g.id = group_id AND g.leader_user_id = auth.uid()));

DROP POLICY IF EXISTS "leaders insert own checkins" ON public.driver_group_field_checkins;
CREATE POLICY "leaders insert own checkins" ON public.driver_group_field_checkins
  FOR INSERT TO authenticated
  WITH CHECK (
    created_by = auth.uid()
    AND EXISTS (SELECT 1 FROM public.driver_groups g WHERE g.id = group_id AND g.leader_user_id = auth.uid())
  );

-- Leader RPC for safe insertion (sets created_by, validates group ownership)
CREATE OR REPLACE FUNCTION public.leader_create_field_checkin(payload jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_group uuid := (payload->>'group_id')::uuid;
  v_id uuid;
  v_is_admin boolean;
  v_owns boolean;
  v_type text := COALESCE(payload->>'checkin_type','field_visit');
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  v_is_admin := public._is_ops_or_god_admin(v_caller);
  SELECT EXISTS (SELECT 1 FROM public.driver_groups g WHERE g.id = v_group AND g.leader_user_id = v_caller)
    INTO v_owns;
  IF NOT (v_is_admin OR v_owns) THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  IF v_type = 'issue_report' AND COALESCE(trim(payload->>'notes'),'') = '' THEN
    RAISE EXCEPTION 'notes_required_for_issue_report';
  END IF;
  INSERT INTO public.driver_group_field_checkins (
    group_id, leader_user_id, driver_user_id, zone_id, checkin_type,
    lat, lng, accuracy_m, notes, photo_url, created_by, metadata
  ) VALUES (
    v_group,
    COALESCE(NULLIF(payload->>'leader_user_id','')::uuid, v_caller),
    NULLIF(payload->>'driver_user_id','')::uuid,
    NULLIF(payload->>'zone_id','')::uuid,
    v_type,
    NULLIF(payload->>'lat','')::double precision,
    NULLIF(payload->>'lng','')::double precision,
    NULLIF(payload->>'accuracy_m','')::double precision,
    payload->>'notes',
    payload->>'photo_url',
    v_caller,
    COALESCE(payload->'metadata', '{}'::jsonb)
  ) RETURNING id INTO v_id;
  RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION public.leader_create_field_checkin(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.leader_create_field_checkin(jsonb) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.leader_list_my_checkins(p_limit integer DEFAULT 100)
RETURNS SETOF public.driver_group_field_checkins
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT c.* FROM public.driver_group_field_checkins c
  WHERE EXISTS (SELECT 1 FROM public.driver_groups g WHERE g.id = c.group_id AND g.leader_user_id = auth.uid())
  ORDER BY c.created_at DESC
  LIMIT GREATEST(p_limit, 1);
$$;
REVOKE ALL ON FUNCTION public.leader_list_my_checkins(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.leader_list_my_checkins(integer) TO authenticated, service_role;

-- ---------- 3. Risk review audit ----------
CREATE TABLE IF NOT EXISTS public.driver_group_risk_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type text NOT NULL,
  entity_id uuid NOT NULL,
  risk_level text,
  status text NOT NULL,
  reason text,
  reviewed_by uuid,
  reviewed_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT dgrr_entity_chk CHECK (entity_type IN ('referral','commission','payout_statement','group')),
  CONSTRAINT dgrr_status_chk CHECK (status IN ('clear','review','held','rejected','released'))
);
CREATE INDEX IF NOT EXISTS dgrr_entity_idx ON public.driver_group_risk_reviews(entity_type, entity_id, reviewed_at DESC);

GRANT SELECT ON public.driver_group_risk_reviews TO authenticated;
GRANT ALL ON public.driver_group_risk_reviews TO service_role;
ALTER TABLE public.driver_group_risk_reviews ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admins manage risk reviews" ON public.driver_group_risk_reviews;
CREATE POLICY "admins manage risk reviews" ON public.driver_group_risk_reviews
  TO authenticated
  USING (public._is_ops_or_god_admin(auth.uid()))
  WITH CHECK (public._is_ops_or_god_admin(auth.uid()));

-- Update existing risk RPCs to write audit rows
CREATE OR REPLACE FUNCTION public.admin_review_referral_risk(p_referral uuid, p_action text, p_reason text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_new_status text;
BEGIN
  IF NOT public._is_ops_or_god_admin(auth.uid()) THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  v_new_status := CASE p_action
    WHEN 'clear' THEN 'clear'
    WHEN 'release' THEN 'clear'
    WHEN 'hold' THEN 'held'
    WHEN 'reject' THEN 'rejected'
    WHEN 'review' THEN 'review'
    ELSE NULL END;
  IF v_new_status IS NULL THEN RAISE EXCEPTION 'invalid_action'; END IF;
  IF p_action IN ('reject','hold','release') AND COALESCE(trim(p_reason),'') = '' THEN
    RAISE EXCEPTION 'reason_required';
  END IF;
  UPDATE public.driver_referrals
    SET risk_status = v_new_status,
        risk_reason = COALESCE(p_reason, risk_reason),
        status = CASE WHEN v_new_status = 'rejected' THEN 'rejected' ELSE status END
    WHERE id = p_referral;
  INSERT INTO public.driver_group_risk_reviews (entity_type, entity_id, status, reason, reviewed_by, metadata)
    VALUES ('referral', p_referral, CASE WHEN p_action='release' THEN 'released' ELSE v_new_status END,
            p_reason, auth.uid(), jsonb_build_object('action', p_action));
END $$;

CREATE OR REPLACE FUNCTION public.admin_review_commission_risk(p_commission uuid, p_action text, p_reason text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_new_status text;
BEGIN
  IF NOT public._is_ops_or_god_admin(auth.uid()) THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  v_new_status := CASE p_action
    WHEN 'clear' THEN 'clear'
    WHEN 'release' THEN 'clear'
    WHEN 'hold' THEN 'held'
    WHEN 'reject' THEN 'rejected'
    WHEN 'review' THEN 'review'
    ELSE NULL END;
  IF v_new_status IS NULL THEN RAISE EXCEPTION 'invalid_action'; END IF;
  IF p_action IN ('reject','hold','release') AND COALESCE(trim(p_reason),'') = '' THEN
    RAISE EXCEPTION 'reason_required';
  END IF;
  UPDATE public.driver_group_commissions
    SET risk_status = v_new_status,
        risk_reason = COALESCE(p_reason, risk_reason)
    WHERE id = p_commission;
  INSERT INTO public.driver_group_risk_reviews (entity_type, entity_id, status, reason, reviewed_by, metadata)
    VALUES ('commission', p_commission, CASE WHEN p_action='release' THEN 'released' ELSE v_new_status END,
            p_reason, auth.uid(), jsonb_build_object('action', p_action));
END $$;

-- ---------- 4. Payout statement lifecycle ----------
ALTER TABLE public.driver_group_payout_statements
  ADD COLUMN IF NOT EXISTS finalized_by uuid,
  ADD COLUMN IF NOT EXISTS paid_by uuid,
  ADD COLUMN IF NOT EXISTS voided_by uuid,
  ADD COLUMN IF NOT EXISTS void_reason text;

CREATE OR REPLACE FUNCTION public.admin_set_statement_status(p_statement uuid, p_status text, p_notes text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_unpaid integer;
BEGIN
  IF NOT public._is_ops_or_god_admin(v_caller) THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  IF p_status NOT IN ('draft','finalized','paid','void') THEN RAISE EXCEPTION 'invalid_status'; END IF;
  IF p_status = 'void' AND COALESCE(trim(p_notes),'') = '' THEN
    RAISE EXCEPTION 'void_reason_required';
  END IF;
  IF p_status = 'paid' THEN
    SELECT COUNT(*) INTO v_unpaid
    FROM public.driver_group_payout_statement_items i
    LEFT JOIN public.driver_group_commissions c ON c.id = i.source_id AND i.item_type = 'commission'
    WHERE i.statement_id = p_statement
      AND i.item_type = 'commission'
      AND (c.status IS NULL OR c.status <> 'paid');
    IF v_unpaid > 0 THEN RAISE EXCEPTION 'commissions_not_all_paid' USING ERRCODE='42501'; END IF;
  END IF;
  UPDATE public.driver_group_payout_statements
    SET status = p_status,
        notes = COALESCE(p_notes, notes),
        finalized_at = CASE WHEN p_status='finalized' AND finalized_at IS NULL THEN now() ELSE finalized_at END,
        finalized_by = CASE WHEN p_status='finalized' AND finalized_by IS NULL THEN v_caller ELSE finalized_by END,
        paid_at = CASE WHEN p_status='paid' AND paid_at IS NULL THEN now() ELSE paid_at END,
        paid_by = CASE WHEN p_status='paid' AND paid_by IS NULL THEN v_caller ELSE paid_by END,
        voided_by = CASE WHEN p_status='void' THEN v_caller ELSE voided_by END,
        void_reason = CASE WHEN p_status='void' THEN p_notes ELSE void_reason END
    WHERE id = p_statement;
  IF p_status IN ('void','finalized','paid') THEN
    INSERT INTO public.driver_group_risk_reviews (entity_type, entity_id, status, reason, reviewed_by, metadata)
    VALUES ('payout_statement', p_statement,
            CASE p_status WHEN 'void' THEN 'rejected' WHEN 'finalized' THEN 'clear' ELSE 'clear' END,
            p_notes, v_caller, jsonb_build_object('action', p_status));
  END IF;
END $$;

-- ---------- 5. Admin field check-in listing ----------
CREATE OR REPLACE FUNCTION public.admin_list_field_checkins(
  p_group uuid DEFAULT NULL, p_limit integer DEFAULT 200
)
RETURNS SETOF public.driver_group_field_checkins
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT c.* FROM public.driver_group_field_checkins c
  WHERE public._is_ops_or_god_admin(auth.uid())
    AND (p_group IS NULL OR c.group_id = p_group)
  ORDER BY c.created_at DESC
  LIMIT GREATEST(p_limit, 1);
$$;
REVOKE ALL ON FUNCTION public.admin_list_field_checkins(uuid,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_field_checkins(uuid,integer) TO authenticated, service_role;
