
-- ============================================================
-- DRIVER SYNDICATES V3
-- ============================================================

-- ---------- 1. Extend driver_referrals ----------
ALTER TABLE public.driver_referrals
  ADD COLUMN IF NOT EXISTS campaign_id uuid,
  ADD COLUMN IF NOT EXISTS milestone_rule text NOT NULL DEFAULT 'approved',
  ADD COLUMN IF NOT EXISTS milestone_status text NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS milestone_met_at timestamptz,
  ADD COLUMN IF NOT EXISTS rides_completed_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS first_ride_completed_at timestamptz,
  ADD COLUMN IF NOT EXISTS eligible_at timestamptz,
  ADD COLUMN IF NOT EXISTS risk_status text NOT NULL DEFAULT 'clear',
  ADD COLUMN IF NOT EXISTS risk_reason text,
  ADD COLUMN IF NOT EXISTS risk_score integer NOT NULL DEFAULT 0;

DO $$ BEGIN
  ALTER TABLE public.driver_referrals
    ADD CONSTRAINT dr_milestone_rule_chk
    CHECK (milestone_rule IN ('approved','first_ride_completed','five_rides_completed','seven_days_active'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE public.driver_referrals
    ADD CONSTRAINT dr_milestone_status_chk
    CHECK (milestone_status IN ('pending','milestone_pending','met','not_met'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  ALTER TABLE public.driver_referrals
    ADD CONSTRAINT dr_risk_status_chk
    CHECK (risk_status IN ('clear','review','held','rejected'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ---------- 2. Extend driver_group_commissions ----------
ALTER TABLE public.driver_group_commissions
  ADD COLUMN IF NOT EXISTS risk_status text NOT NULL DEFAULT 'clear',
  ADD COLUMN IF NOT EXISTS risk_reason text;

DO $$ BEGIN
  ALTER TABLE public.driver_group_commissions
    ADD CONSTRAINT dgc_risk_status_chk
    CHECK (risk_status IN ('clear','review','held','rejected'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ---------- 3. Recruitment campaigns ----------
CREATE TABLE IF NOT EXISTS public.driver_recruitment_campaigns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL REFERENCES public.driver_groups(id) ON DELETE CASCADE,
  leader_user_id uuid,
  name text NOT NULL,
  description text,
  status text NOT NULL DEFAULT 'active',
  zone_ids uuid[] NOT NULL DEFAULT '{}'::uuid[],
  target_driver_count integer NOT NULL DEFAULT 0,
  target_active_driver_count integer NOT NULL DEFAULT 0,
  target_completed_rides integer NOT NULL DEFAULT 0,
  start_date date,
  end_date date,
  signup_bonus_gnf bigint NOT NULL DEFAULT 0,
  milestone_rule text NOT NULL DEFAULT 'approved',
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  notes text,
  CONSTRAINT drc_status_chk CHECK (status IN ('draft','active','paused','completed','cancelled')),
  CONSTRAINT drc_milestone_chk CHECK (milestone_rule IN ('approved','first_ride_completed','five_rides_completed','seven_days_active')),
  CONSTRAINT drc_bonus_chk CHECK (signup_bonus_gnf >= 0)
);
CREATE INDEX IF NOT EXISTS drc_group_idx ON public.driver_recruitment_campaigns(group_id);
CREATE INDEX IF NOT EXISTS drc_status_idx ON public.driver_recruitment_campaigns(status);

GRANT SELECT ON public.driver_recruitment_campaigns TO authenticated;
GRANT ALL ON public.driver_recruitment_campaigns TO service_role;
ALTER TABLE public.driver_recruitment_campaigns ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admins manage campaigns" ON public.driver_recruitment_campaigns;
CREATE POLICY "admins manage campaigns" ON public.driver_recruitment_campaigns
  TO authenticated
  USING (public._is_ops_or_god_admin(auth.uid()))
  WITH CHECK (public._is_ops_or_god_admin(auth.uid()));

DROP POLICY IF EXISTS "leaders read own campaigns" ON public.driver_recruitment_campaigns;
CREATE POLICY "leaders read own campaigns" ON public.driver_recruitment_campaigns
  FOR SELECT TO authenticated
  USING (
    leader_user_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.driver_groups g WHERE g.id = group_id AND g.leader_user_id = auth.uid())
  );

CREATE TRIGGER trg_drc_touch BEFORE UPDATE ON public.driver_recruitment_campaigns
  FOR EACH ROW EXECUTE FUNCTION public._driver_groups_touch();

-- Now we can add the FK on driver_referrals.campaign_id
DO $$ BEGIN
  ALTER TABLE public.driver_referrals
    ADD CONSTRAINT dr_campaign_fk FOREIGN KEY (campaign_id)
    REFERENCES public.driver_recruitment_campaigns(id) ON DELETE SET NULL;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS dr_campaign_idx ON public.driver_referrals(campaign_id);
CREATE INDEX IF NOT EXISTS dr_risk_idx ON public.driver_referrals(risk_status) WHERE risk_status <> 'clear';

-- ---------- 4. Performance contracts ----------
CREATE TABLE IF NOT EXISTS public.driver_group_contracts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL REFERENCES public.driver_groups(id) ON DELETE CASCADE,
  leader_user_id uuid,
  name text NOT NULL,
  status text NOT NULL DEFAULT 'active',
  period_start date,
  period_end date,
  target_driver_count integer NOT NULL DEFAULT 0,
  target_active_driver_count integer NOT NULL DEFAULT 0,
  target_completed_rides integer NOT NULL DEFAULT 0,
  target_gross_earnings_gnf bigint NOT NULL DEFAULT 0,
  target_zone_ids uuid[] NOT NULL DEFAULT '{}'::uuid[],
  commission_percent_override numeric(5,2),
  bonus_pool_gnf bigint,
  terms text,
  notes text,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT dgct_status_chk CHECK (status IN ('draft','active','completed','cancelled')),
  CONSTRAINT dgct_commission_chk CHECK (commission_percent_override IS NULL OR (commission_percent_override >= 0 AND commission_percent_override <= 100))
);
CREATE INDEX IF NOT EXISTS dgct_group_idx ON public.driver_group_contracts(group_id);

GRANT SELECT ON public.driver_group_contracts TO authenticated;
GRANT ALL ON public.driver_group_contracts TO service_role;
ALTER TABLE public.driver_group_contracts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admins manage contracts" ON public.driver_group_contracts;
CREATE POLICY "admins manage contracts" ON public.driver_group_contracts
  TO authenticated
  USING (public._is_ops_or_god_admin(auth.uid()))
  WITH CHECK (public._is_ops_or_god_admin(auth.uid()));

DROP POLICY IF EXISTS "leaders read own contracts" ON public.driver_group_contracts;
CREATE POLICY "leaders read own contracts" ON public.driver_group_contracts
  FOR SELECT TO authenticated
  USING (
    leader_user_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.driver_groups g WHERE g.id = group_id AND g.leader_user_id = auth.uid())
  );

CREATE TRIGGER trg_dgct_touch BEFORE UPDATE ON public.driver_group_contracts
  FOR EACH ROW EXECUTE FUNCTION public._driver_groups_touch();

-- ---------- 5. Payout statements ----------
CREATE TABLE IF NOT EXISTS public.driver_group_payout_statements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL REFERENCES public.driver_groups(id) ON DELETE RESTRICT,
  leader_user_id uuid,
  period_start date NOT NULL,
  period_end date NOT NULL,
  status text NOT NULL DEFAULT 'draft',
  commissions_total_gnf bigint NOT NULL DEFAULT 0,
  signup_bonuses_total_gnf bigint NOT NULL DEFAULT 0,
  adjustments_total_gnf bigint NOT NULL DEFAULT 0,
  total_due_gnf bigint NOT NULL DEFAULT 0,
  generated_by uuid,
  generated_at timestamptz NOT NULL DEFAULT now(),
  finalized_at timestamptz,
  paid_at timestamptz,
  notes text,
  CONSTRAINT dgps_status_chk CHECK (status IN ('draft','finalized','paid','void'))
);
CREATE INDEX IF NOT EXISTS dgps_group_idx ON public.driver_group_payout_statements(group_id);

GRANT SELECT ON public.driver_group_payout_statements TO authenticated;
GRANT ALL ON public.driver_group_payout_statements TO service_role;
ALTER TABLE public.driver_group_payout_statements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admins manage statements" ON public.driver_group_payout_statements;
CREATE POLICY "admins manage statements" ON public.driver_group_payout_statements
  TO authenticated
  USING (public._is_ops_or_god_admin(auth.uid()))
  WITH CHECK (public._is_ops_or_god_admin(auth.uid()));

DROP POLICY IF EXISTS "leaders read own finalized statements" ON public.driver_group_payout_statements;
CREATE POLICY "leaders read own finalized statements" ON public.driver_group_payout_statements
  FOR SELECT TO authenticated
  USING (
    status IN ('finalized','paid')
    AND EXISTS (SELECT 1 FROM public.driver_groups g WHERE g.id = group_id AND g.leader_user_id = auth.uid())
  );

CREATE TABLE IF NOT EXISTS public.driver_group_payout_statement_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  statement_id uuid NOT NULL REFERENCES public.driver_group_payout_statements(id) ON DELETE CASCADE,
  item_type text NOT NULL,
  source_id uuid,
  driver_user_id uuid,
  amount_gnf bigint NOT NULL DEFAULT 0,
  description text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT dgpsi_type_chk CHECK (item_type IN ('commission','signup_bonus','adjustment'))
);
CREATE INDEX IF NOT EXISTS dgpsi_statement_idx ON public.driver_group_payout_statement_items(statement_id);

GRANT SELECT ON public.driver_group_payout_statement_items TO authenticated;
GRANT ALL ON public.driver_group_payout_statement_items TO service_role;
ALTER TABLE public.driver_group_payout_statement_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admins manage statement items" ON public.driver_group_payout_statement_items;
CREATE POLICY "admins manage statement items" ON public.driver_group_payout_statement_items
  TO authenticated
  USING (public._is_ops_or_god_admin(auth.uid()))
  WITH CHECK (public._is_ops_or_god_admin(auth.uid()));

DROP POLICY IF EXISTS "leaders read own statement items" ON public.driver_group_payout_statement_items;
CREATE POLICY "leaders read own statement items" ON public.driver_group_payout_statement_items
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.driver_group_payout_statements s
      JOIN public.driver_groups g ON g.id = s.group_id
      WHERE s.id = statement_id
        AND s.status IN ('finalized','paid')
        AND g.leader_user_id = auth.uid()
    )
  );

-- ============================================================
-- FUNCTIONS
-- ============================================================

-- ---------- Milestone refresh ----------
CREATE OR REPLACE FUNCTION public.refresh_driver_referral_milestones(p_driver uuid DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r RECORD;
  v_count integer := 0;
  v_rides integer;
  v_first timestamptz;
  v_approved_at timestamptz;
  v_status text;
  v_met boolean;
  v_now timestamptz := now();
BEGIN
  FOR r IN
    SELECT * FROM public.driver_referrals
    WHERE (p_driver IS NULL OR referred_driver_user_id = p_driver)
      AND status NOT IN ('rejected','paid')
      AND risk_status NOT IN ('rejected')
  LOOP
    SELECT COUNT(*)::int, MIN(completed_at)
      INTO v_rides, v_first
      FROM public.rides
      WHERE driver_id = r.referred_driver_user_id
        AND status::text = 'completed';

    SELECT approved_at INTO v_approved_at FROM public.driver_profiles
      WHERE user_id = r.referred_driver_user_id;

    v_met := false;
    CASE r.milestone_rule
      WHEN 'approved' THEN v_met := v_approved_at IS NOT NULL;
      WHEN 'first_ride_completed' THEN v_met := v_rides >= 1;
      WHEN 'five_rides_completed' THEN v_met := v_rides >= 5;
      WHEN 'seven_days_active' THEN
        v_met := v_approved_at IS NOT NULL AND v_approved_at <= v_now - interval '7 days';
      ELSE v_met := false;
    END CASE;

    v_status := CASE WHEN v_met THEN 'met' ELSE 'milestone_pending' END;

    UPDATE public.driver_referrals
    SET rides_completed_count = COALESCE(v_rides, 0),
        first_ride_completed_at = v_first,
        milestone_status = v_status,
        milestone_met_at = CASE WHEN v_met AND milestone_met_at IS NULL THEN v_now ELSE milestone_met_at END,
        eligible_at = CASE
          WHEN v_met AND risk_status = 'clear' AND eligible_at IS NULL THEN v_now
          WHEN NOT v_met THEN NULL
          ELSE eligible_at END,
        status = CASE
          WHEN v_met AND risk_status = 'clear' AND status IN ('pending','approved') THEN 'bonus_eligible'
          ELSE status END,
        updated_at = v_now
    WHERE id = r.id;
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.refresh_driver_referral_milestones(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.refresh_driver_referral_milestones(uuid) TO authenticated, service_role;

-- Trigger from rides completion (fire-and-forget, never block ride)
CREATE OR REPLACE FUNCTION public._dr_milestones_on_ride_complete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.status::text = 'completed' AND (OLD.status::text IS DISTINCT FROM 'completed') AND NEW.driver_id IS NOT NULL THEN
    BEGIN
      PERFORM public.refresh_driver_referral_milestones(NEW.driver_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'refresh_driver_referral_milestones failed: %', SQLERRM;
    END;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_dr_milestones_on_ride ON public.rides;
CREATE TRIGGER trg_dr_milestones_on_ride
  AFTER UPDATE OF status ON public.rides
  FOR EACH ROW EXECUTE FUNCTION public._dr_milestones_on_ride_complete();

-- ---------- Risk scoring ----------
CREATE OR REPLACE FUNCTION public.score_driver_referral_risk(p_referral uuid)
RETURNS TABLE(score integer, status text, reason text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r public.driver_referrals;
  v_score integer := 0;
  v_reasons text[] := ARRAY[]::text[];
  v_group public.driver_groups;
  v_dp public.driver_profiles;
  v_recent integer;
  v_status text;
BEGIN
  SELECT * INTO r FROM public.driver_referrals WHERE id = p_referral;
  IF r.id IS NULL THEN RAISE EXCEPTION 'referral_not_found'; END IF;

  SELECT * INTO v_group FROM public.driver_groups WHERE id = r.group_id;
  SELECT * INTO v_dp FROM public.driver_profiles WHERE user_id = r.referred_driver_user_id;

  IF v_group.status <> 'active' THEN
    v_score := v_score + 40; v_reasons := array_append(v_reasons, 'groupe_suspendu');
  END IF;
  IF v_dp.status IN ('suspended','rejected','banned') THEN
    v_score := v_score + 60; v_reasons := array_append(v_reasons, 'chauffeur_' || v_dp.status);
  END IF;

  -- Driver has bonus eligible / paid but zero rides within 7 days of approval
  IF r.status IN ('bonus_eligible','paid') AND r.rides_completed_count = 0 AND r.created_at < now() - interval '7 days' THEN
    v_score := v_score + 30; v_reasons := array_append(v_reasons, 'aucune_course');
  END IF;

  -- Rapid-fire: more than 10 referrals from this group in last 24h
  SELECT COUNT(*) INTO v_recent FROM public.driver_referrals
    WHERE group_id = r.group_id AND created_at > now() - interval '24 hours';
  IF v_recent > 10 THEN
    v_score := v_score + 25; v_reasons := array_append(v_reasons, 'volume_24h_eleve');
  END IF;

  v_status := CASE
    WHEN v_score >= 60 THEN 'held'
    WHEN v_score >= 25 THEN 'review'
    ELSE 'clear'
  END;

  RETURN QUERY SELECT v_score, v_status, array_to_string(v_reasons, ', ');
END;
$$;
REVOKE ALL ON FUNCTION public.score_driver_referral_risk(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.score_driver_referral_risk(uuid) TO authenticated, service_role;

-- ============================================================
-- ADMIN RPCs
-- ============================================================

-- Campaigns
CREATE OR REPLACE FUNCTION public.admin_create_campaign(payload jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid; v_caller uuid := auth.uid();
BEGIN
  IF NOT public._is_ops_or_god_admin(v_caller) THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  INSERT INTO public.driver_recruitment_campaigns (
    group_id, leader_user_id, name, description, status, zone_ids,
    target_driver_count, target_active_driver_count, target_completed_rides,
    start_date, end_date, signup_bonus_gnf, milestone_rule, notes, created_by
  ) VALUES (
    (payload->>'group_id')::uuid,
    NULLIF(payload->>'leader_user_id','')::uuid,
    payload->>'name',
    payload->>'description',
    COALESCE(payload->>'status','active'),
    COALESCE((SELECT array_agg(x::uuid) FROM jsonb_array_elements_text(payload->'zone_ids') x), '{}'),
    COALESCE((payload->>'target_driver_count')::int, 0),
    COALESCE((payload->>'target_active_driver_count')::int, 0),
    COALESCE((payload->>'target_completed_rides')::int, 0),
    NULLIF(payload->>'start_date','')::date,
    NULLIF(payload->>'end_date','')::date,
    COALESCE((payload->>'signup_bonus_gnf')::bigint, 0),
    COALESCE(payload->>'milestone_rule','approved'),
    payload->>'notes',
    v_caller
  ) RETURNING id INTO v_id;
  RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION public.admin_create_campaign(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_create_campaign(jsonb) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.admin_update_campaign(p_campaign uuid, payload jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public._is_ops_or_god_admin(auth.uid()) THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  UPDATE public.driver_recruitment_campaigns SET
    name = COALESCE(payload->>'name', name),
    description = COALESCE(payload->>'description', description),
    status = COALESCE(payload->>'status', status),
    zone_ids = COALESCE((SELECT array_agg(x::uuid) FROM jsonb_array_elements_text(payload->'zone_ids') x), zone_ids),
    target_driver_count = COALESCE((payload->>'target_driver_count')::int, target_driver_count),
    target_active_driver_count = COALESCE((payload->>'target_active_driver_count')::int, target_active_driver_count),
    target_completed_rides = COALESCE((payload->>'target_completed_rides')::int, target_completed_rides),
    start_date = COALESCE(NULLIF(payload->>'start_date','')::date, start_date),
    end_date = COALESCE(NULLIF(payload->>'end_date','')::date, end_date),
    signup_bonus_gnf = COALESCE((payload->>'signup_bonus_gnf')::bigint, signup_bonus_gnf),
    milestone_rule = COALESCE(payload->>'milestone_rule', milestone_rule),
    leader_user_id = COALESCE(NULLIF(payload->>'leader_user_id','')::uuid, leader_user_id),
    notes = COALESCE(payload->>'notes', notes)
  WHERE id = p_campaign;
END $$;
REVOKE ALL ON FUNCTION public.admin_update_campaign(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_campaign(uuid, jsonb) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.admin_attach_referral_campaign(p_referral uuid, p_campaign uuid, p_reason text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public._is_ops_or_god_admin(auth.uid()) THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  UPDATE public.driver_referrals
    SET campaign_id = p_campaign,
        metadata = metadata || jsonb_build_object('campaign_attach_reason', p_reason, 'campaign_attached_by', auth.uid())
    WHERE id = p_referral;
END $$;
REVOKE ALL ON FUNCTION public.admin_attach_referral_campaign(uuid, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_attach_referral_campaign(uuid, uuid, text) TO authenticated, service_role;

-- Contracts
CREATE OR REPLACE FUNCTION public.admin_create_contract(payload jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid; v_caller uuid := auth.uid();
BEGIN
  IF NOT public._is_ops_or_god_admin(v_caller) THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  INSERT INTO public.driver_group_contracts (
    group_id, leader_user_id, name, status, period_start, period_end,
    target_driver_count, target_active_driver_count, target_completed_rides,
    target_gross_earnings_gnf, target_zone_ids, commission_percent_override, bonus_pool_gnf,
    terms, notes, created_by
  ) VALUES (
    (payload->>'group_id')::uuid,
    NULLIF(payload->>'leader_user_id','')::uuid,
    payload->>'name',
    COALESCE(payload->>'status','active'),
    NULLIF(payload->>'period_start','')::date,
    NULLIF(payload->>'period_end','')::date,
    COALESCE((payload->>'target_driver_count')::int, 0),
    COALESCE((payload->>'target_active_driver_count')::int, 0),
    COALESCE((payload->>'target_completed_rides')::int, 0),
    COALESCE((payload->>'target_gross_earnings_gnf')::bigint, 0),
    COALESCE((SELECT array_agg(x::uuid) FROM jsonb_array_elements_text(payload->'target_zone_ids') x), '{}'),
    NULLIF(payload->>'commission_percent_override','')::numeric,
    NULLIF(payload->>'bonus_pool_gnf','')::bigint,
    payload->>'terms',
    payload->>'notes',
    v_caller
  ) RETURNING id INTO v_id;
  RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION public.admin_create_contract(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_create_contract(jsonb) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.admin_update_contract(p_contract uuid, payload jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public._is_ops_or_god_admin(auth.uid()) THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  UPDATE public.driver_group_contracts SET
    name = COALESCE(payload->>'name', name),
    status = COALESCE(payload->>'status', status),
    notes = COALESCE(payload->>'notes', notes),
    terms = COALESCE(payload->>'terms', terms)
  WHERE id = p_contract;
END $$;
REVOKE ALL ON FUNCTION public.admin_update_contract(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_contract(uuid, jsonb) TO authenticated, service_role;

-- Payout statements
CREATE OR REPLACE FUNCTION public.admin_generate_payout_statement(
  p_group uuid, p_from date, p_to date, p_notes text DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_id uuid;
  v_group public.driver_groups;
  v_comm_total bigint := 0;
  v_bonus_total bigint := 0;
  v_adj_total bigint := 0;
BEGIN
  IF NOT public._is_ops_or_god_admin(v_caller) THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_group FROM public.driver_groups WHERE id = p_group;
  IF v_group.id IS NULL THEN RAISE EXCEPTION 'group_not_found'; END IF;

  INSERT INTO public.driver_group_payout_statements (
    group_id, leader_user_id, period_start, period_end, status, generated_by, notes
  ) VALUES (
    p_group, v_group.leader_user_id, p_from, p_to, 'draft', v_caller, p_notes
  ) RETURNING id INTO v_id;

  -- Commission items (approved/paid in period, not held/rejected)
  INSERT INTO public.driver_group_payout_statement_items (statement_id, item_type, source_id, driver_user_id, amount_gnf, description)
  SELECT v_id, 'commission', c.id, c.driver_user_id, c.commission_amount_gnf,
         'Commission ' || c.source_type || ' · ' || c.status
  FROM public.driver_group_commissions c
  WHERE c.group_id = p_group
    AND c.status IN ('approved','paid')
    AND COALESCE(c.risk_status,'clear') NOT IN ('held','rejected')
    AND c.created_at::date BETWEEN p_from AND p_to;

  -- Signup bonus items (bonus_eligible / paid)
  INSERT INTO public.driver_group_payout_statement_items (statement_id, item_type, source_id, driver_user_id, amount_gnf, description)
  SELECT v_id, 'signup_bonus', r.id, r.referred_driver_user_id, r.bonus_amount_gnf,
         'Bonus parrainage · ' || r.status
  FROM public.driver_referrals r
  WHERE r.group_id = p_group
    AND r.status IN ('bonus_eligible','paid')
    AND COALESCE(r.risk_status,'clear') NOT IN ('held','rejected')
    AND r.created_at::date BETWEEN p_from AND p_to;

  SELECT
    COALESCE(SUM(amount_gnf) FILTER (WHERE item_type='commission'),0),
    COALESCE(SUM(amount_gnf) FILTER (WHERE item_type='signup_bonus'),0),
    COALESCE(SUM(amount_gnf) FILTER (WHERE item_type='adjustment'),0)
  INTO v_comm_total, v_bonus_total, v_adj_total
  FROM public.driver_group_payout_statement_items WHERE statement_id = v_id;

  UPDATE public.driver_group_payout_statements
    SET commissions_total_gnf = v_comm_total,
        signup_bonuses_total_gnf = v_bonus_total,
        adjustments_total_gnf = v_adj_total,
        total_due_gnf = v_comm_total + v_bonus_total + v_adj_total
    WHERE id = v_id;

  RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION public.admin_generate_payout_statement(uuid,date,date,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_generate_payout_statement(uuid,date,date,text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.admin_set_statement_status(p_statement uuid, p_status text, p_notes text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_unpaid integer;
BEGIN
  IF NOT public._is_ops_or_god_admin(auth.uid()) THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  IF p_status NOT IN ('draft','finalized','paid','void') THEN RAISE EXCEPTION 'invalid_status'; END IF;

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
        paid_at = CASE WHEN p_status='paid' AND paid_at IS NULL THEN now() ELSE paid_at END
    WHERE id = p_statement;
END $$;
REVOKE ALL ON FUNCTION public.admin_set_statement_status(uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_statement_status(uuid,text,text) TO authenticated, service_role;

-- Risk queue
CREATE OR REPLACE FUNCTION public.admin_review_referral_risk(p_referral uuid, p_action text, p_reason text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_new_status text;
BEGIN
  IF NOT public._is_ops_or_god_admin(auth.uid()) THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  v_new_status := CASE p_action
    WHEN 'clear' THEN 'clear'
    WHEN 'hold' THEN 'held'
    WHEN 'reject' THEN 'rejected'
    WHEN 'review' THEN 'review'
    ELSE NULL END;
  IF v_new_status IS NULL THEN RAISE EXCEPTION 'invalid_action'; END IF;
  UPDATE public.driver_referrals
    SET risk_status = v_new_status,
        risk_reason = COALESCE(p_reason, risk_reason),
        status = CASE WHEN v_new_status = 'rejected' THEN 'rejected' ELSE status END
    WHERE id = p_referral;
END $$;
REVOKE ALL ON FUNCTION public.admin_review_referral_risk(uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_review_referral_risk(uuid,text,text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.admin_review_commission_risk(p_commission uuid, p_action text, p_reason text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_new_status text;
BEGIN
  IF NOT public._is_ops_or_god_admin(auth.uid()) THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  v_new_status := CASE p_action
    WHEN 'clear' THEN 'clear'
    WHEN 'hold' THEN 'held'
    WHEN 'reject' THEN 'rejected'
    WHEN 'review' THEN 'review'
    ELSE NULL END;
  IF v_new_status IS NULL THEN RAISE EXCEPTION 'invalid_action'; END IF;
  UPDATE public.driver_group_commissions
    SET risk_status = v_new_status,
        risk_reason = COALESCE(p_reason, risk_reason)
    WHERE id = p_commission;
END $$;
REVOKE ALL ON FUNCTION public.admin_review_commission_risk(uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_review_commission_risk(uuid,text,text) TO authenticated, service_role;

-- Zone coverage intelligence
CREATE OR REPLACE FUNCTION public.admin_zone_coverage_stats()
RETURNS TABLE(
  zone_id uuid, zone_label text, drivers_count integer,
  active_drivers_count integer, groups_count integer
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public._is_ops_or_god_admin(auth.uid()) THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  RETURN QUERY
    SELECT z.id,
           COALESCE(z.commune, z.neighborhood, z.city, z.country) AS zone_label,
           COUNT(DISTINCT m.driver_user_id)::int AS drivers_count,
           COUNT(DISTINCT m.driver_user_id) FILTER (WHERE m.status = 'active')::int AS active_drivers_count,
           COUNT(DISTINCT g.id)::int AS groups_count
    FROM public.zones z
    LEFT JOIN public.driver_group_memberships m ON m.assigned_zone_id = z.id
    LEFT JOIN public.driver_groups g ON z.id = ANY(g.assigned_zone_ids)
    WHERE z.kind = 'service'
    GROUP BY z.id, zone_label
    ORDER BY zone_label;
END $$;
REVOKE ALL ON FUNCTION public.admin_zone_coverage_stats() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_zone_coverage_stats() TO authenticated, service_role;

-- ============================================================
-- LEADER RPCs (scoped)
-- ============================================================
CREATE OR REPLACE FUNCTION public.leader_list_my_campaigns()
RETURNS SETOF public.driver_recruitment_campaigns
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT c.* FROM public.driver_recruitment_campaigns c
  WHERE c.leader_user_id = auth.uid()
     OR EXISTS (SELECT 1 FROM public.driver_groups g WHERE g.id = c.group_id AND g.leader_user_id = auth.uid())
  ORDER BY c.created_at DESC;
$$;
REVOKE ALL ON FUNCTION public.leader_list_my_campaigns() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.leader_list_my_campaigns() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.leader_list_my_contracts()
RETURNS SETOF public.driver_group_contracts
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT c.* FROM public.driver_group_contracts c
  WHERE c.leader_user_id = auth.uid()
     OR EXISTS (SELECT 1 FROM public.driver_groups g WHERE g.id = c.group_id AND g.leader_user_id = auth.uid())
  ORDER BY c.created_at DESC;
$$;
REVOKE ALL ON FUNCTION public.leader_list_my_contracts() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.leader_list_my_contracts() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.leader_list_my_statements()
RETURNS SETOF public.driver_group_payout_statements
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT s.* FROM public.driver_group_payout_statements s
  WHERE s.status IN ('finalized','paid')
    AND EXISTS (SELECT 1 FROM public.driver_groups g WHERE g.id = s.group_id AND g.leader_user_id = auth.uid())
  ORDER BY s.generated_at DESC;
$$;
REVOKE ALL ON FUNCTION public.leader_list_my_statements() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.leader_list_my_statements() TO authenticated, service_role;
