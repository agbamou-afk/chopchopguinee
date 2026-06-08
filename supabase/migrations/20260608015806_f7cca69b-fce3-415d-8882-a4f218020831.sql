
-- Driver Syndicates / Group Leaders v0
-- Admin-managed driver groups with commission ledger (pending only, no wallet credits).

-- =========================
-- TABLES
-- =========================

CREATE TABLE public.driver_groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  leader_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  leader_name text,
  leader_phone text,
  status text NOT NULL DEFAULT 'active',
  commission_percent numeric(5,2) NOT NULL DEFAULT 1.00,
  signup_bonus_gnf bigint NOT NULL DEFAULT 0,
  assigned_zones text[] NOT NULL DEFAULT '{}',
  referral_code text UNIQUE,
  notes text,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT driver_groups_status_chk CHECK (status IN ('active','suspended','archived')),
  CONSTRAINT driver_groups_commission_chk CHECK (commission_percent >= 0 AND commission_percent <= 100),
  CONSTRAINT driver_groups_bonus_chk CHECK (signup_bonus_gnf >= 0)
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.driver_groups TO authenticated;
GRANT ALL ON public.driver_groups TO service_role;
ALTER TABLE public.driver_groups ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admins manage driver_groups" ON public.driver_groups
  FOR ALL TO authenticated
  USING (public._is_ops_or_god_admin(auth.uid()))
  WITH CHECK (public._is_ops_or_god_admin(auth.uid()));

CREATE TABLE public.driver_group_memberships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL REFERENCES public.driver_groups(id) ON DELETE CASCADE,
  driver_user_id uuid NOT NULL,
  driver_profile_id uuid REFERENCES public.driver_profiles(user_id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'active',
  assigned_zone text,
  joined_at timestamptz NOT NULL DEFAULT now(),
  added_by uuid,
  removed_at timestamptz,
  removed_by uuid,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT dgm_status_chk CHECK (status IN ('active','removed','pending'))
);
CREATE UNIQUE INDEX dgm_one_active_per_driver
  ON public.driver_group_memberships(driver_user_id)
  WHERE status = 'active';
CREATE INDEX dgm_group_idx ON public.driver_group_memberships(group_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.driver_group_memberships TO authenticated;
GRANT ALL ON public.driver_group_memberships TO service_role;
ALTER TABLE public.driver_group_memberships ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admins manage memberships" ON public.driver_group_memberships
  FOR ALL TO authenticated
  USING (public._is_ops_or_god_admin(auth.uid()))
  WITH CHECK (public._is_ops_or_god_admin(auth.uid()));
CREATE POLICY "driver reads own membership" ON public.driver_group_memberships
  FOR SELECT TO authenticated
  USING (driver_user_id = auth.uid());

CREATE TABLE public.driver_referrals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid REFERENCES public.driver_groups(id) ON DELETE SET NULL,
  referrer_user_id uuid,
  referred_driver_user_id uuid NOT NULL,
  referral_code text,
  status text NOT NULL DEFAULT 'pending',
  bonus_amount_gnf bigint NOT NULL DEFAULT 0,
  approved_at timestamptz,
  paid_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT dr_status_chk CHECK (status IN ('pending','approved','bonus_eligible','paid','rejected')),
  CONSTRAINT dr_bonus_chk CHECK (bonus_amount_gnf >= 0)
);
CREATE INDEX dr_referred_idx ON public.driver_referrals(referred_driver_user_id);
CREATE INDEX dr_group_idx ON public.driver_referrals(group_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.driver_referrals TO authenticated;
GRANT ALL ON public.driver_referrals TO service_role;
ALTER TABLE public.driver_referrals ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admins manage referrals" ON public.driver_referrals
  FOR ALL TO authenticated
  USING (public._is_ops_or_god_admin(auth.uid()))
  WITH CHECK (public._is_ops_or_god_admin(auth.uid()));

CREATE TABLE public.driver_group_commissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL REFERENCES public.driver_groups(id) ON DELETE RESTRICT,
  leader_user_id uuid,
  driver_user_id uuid NOT NULL,
  source_type text NOT NULL,
  source_id uuid,
  gross_driver_earning_gnf bigint NOT NULL DEFAULT 0,
  commission_percent numeric(5,2) NOT NULL DEFAULT 0,
  commission_amount_gnf bigint NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'pending',
  wallet_transaction_id uuid,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  approved_at timestamptz,
  paid_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT dgc_source_chk CHECK (source_type IN ('ride_earning','signup_bonus','adjustment')),
  CONSTRAINT dgc_status_chk CHECK (status IN ('pending','approved','paid','reversed'))
);
CREATE UNIQUE INDEX dgc_source_unique
  ON public.driver_group_commissions(source_type, source_id, driver_user_id)
  WHERE source_id IS NOT NULL;
CREATE INDEX dgc_group_idx ON public.driver_group_commissions(group_id);
CREATE INDEX dgc_status_idx ON public.driver_group_commissions(status);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.driver_group_commissions TO authenticated;
GRANT ALL ON public.driver_group_commissions TO service_role;
ALTER TABLE public.driver_group_commissions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admins manage commissions" ON public.driver_group_commissions
  FOR ALL TO authenticated
  USING (public._is_ops_or_god_admin(auth.uid()))
  WITH CHECK (public._is_ops_or_god_admin(auth.uid()));

-- =========================
-- updated_at triggers
-- =========================
CREATE OR REPLACE FUNCTION public._driver_groups_touch()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END $$;

CREATE TRIGGER trg_driver_groups_touch BEFORE UPDATE ON public.driver_groups
  FOR EACH ROW EXECUTE FUNCTION public._driver_groups_touch();
CREATE TRIGGER trg_dgm_touch BEFORE UPDATE ON public.driver_group_memberships
  FOR EACH ROW EXECUTE FUNCTION public._driver_groups_touch();
CREATE TRIGGER trg_dr_touch BEFORE UPDATE ON public.driver_referrals
  FOR EACH ROW EXECUTE FUNCTION public._driver_groups_touch();
CREATE TRIGGER trg_dgc_touch BEFORE UPDATE ON public.driver_group_commissions
  FOR EACH ROW EXECUTE FUNCTION public._driver_groups_touch();

-- =========================
-- RPCs
-- =========================

CREATE OR REPLACE FUNCTION public.admin_create_driver_group(payload jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  IF NOT public._is_ops_or_god_admin(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;
  INSERT INTO public.driver_groups (
    name, description, leader_user_id, leader_name, leader_phone,
    commission_percent, signup_bonus_gnf, assigned_zones, referral_code, notes, created_by
  ) VALUES (
    COALESCE(payload->>'name', ''),
    payload->>'description',
    NULLIF(payload->>'leader_user_id','')::uuid,
    payload->>'leader_name',
    payload->>'leader_phone',
    COALESCE((payload->>'commission_percent')::numeric, 1.00),
    COALESCE((payload->>'signup_bonus_gnf')::bigint, 0),
    COALESCE(ARRAY(SELECT jsonb_array_elements_text(payload->'assigned_zones')), '{}'),
    NULLIF(payload->>'referral_code',''),
    payload->>'notes',
    auth.uid()
  ) RETURNING id INTO v_id;
  RETURN v_id;
END $$;
REVOKE EXECUTE ON FUNCTION public.admin_create_driver_group(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_create_driver_group(jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_update_driver_group(p_group uuid, payload jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public._is_ops_or_god_admin(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;
  UPDATE public.driver_groups SET
    name = COALESCE(payload->>'name', name),
    description = COALESCE(payload->>'description', description),
    leader_user_id = COALESCE(NULLIF(payload->>'leader_user_id','')::uuid, leader_user_id),
    leader_name = COALESCE(payload->>'leader_name', leader_name),
    leader_phone = COALESCE(payload->>'leader_phone', leader_phone),
    status = COALESCE(payload->>'status', status),
    commission_percent = COALESCE((payload->>'commission_percent')::numeric, commission_percent),
    signup_bonus_gnf = COALESCE((payload->>'signup_bonus_gnf')::bigint, signup_bonus_gnf),
    assigned_zones = COALESCE(ARRAY(SELECT jsonb_array_elements_text(payload->'assigned_zones')), assigned_zones),
    referral_code = COALESCE(NULLIF(payload->>'referral_code',''), referral_code),
    notes = COALESCE(payload->>'notes', notes)
  WHERE id = p_group;
END $$;
REVOKE EXECUTE ON FUNCTION public.admin_update_driver_group(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_driver_group(uuid, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_assign_driver_to_group(
  p_group uuid, p_driver uuid, p_zone text DEFAULT NULL, p_notes text DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  IF NOT public._is_ops_or_god_admin(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;
  -- Deactivate any existing active membership for that driver
  UPDATE public.driver_group_memberships
    SET status = 'removed', removed_at = now(), removed_by = auth.uid()
  WHERE driver_user_id = p_driver AND status = 'active';
  INSERT INTO public.driver_group_memberships (
    group_id, driver_user_id, driver_profile_id, status, assigned_zone, added_by, notes
  ) VALUES (
    p_group, p_driver,
    (SELECT user_id FROM public.driver_profiles WHERE user_id = p_driver),
    'active', p_zone, auth.uid(), p_notes
  ) RETURNING id INTO v_id;
  RETURN v_id;
END $$;
REVOKE EXECUTE ON FUNCTION public.admin_assign_driver_to_group(uuid,uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_assign_driver_to_group(uuid,uuid,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_remove_driver_from_group(p_membership uuid, p_reason text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public._is_ops_or_god_admin(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;
  UPDATE public.driver_group_memberships
    SET status='removed', removed_at=now(), removed_by=auth.uid(),
        notes = COALESCE(notes,'') || CASE WHEN p_reason IS NOT NULL THEN E'\nRemoved: '||p_reason ELSE '' END
  WHERE id = p_membership;
END $$;
REVOKE EXECUTE ON FUNCTION public.admin_remove_driver_from_group(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_remove_driver_from_group(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_review_commission(p_commission uuid, p_action text, p_notes text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public._is_ops_or_god_admin(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;
  IF p_action NOT IN ('approve','mark_paid','reverse') THEN
    RAISE EXCEPTION 'invalid action: %', p_action;
  END IF;
  UPDATE public.driver_group_commissions SET
    status = CASE p_action
      WHEN 'approve' THEN 'approved'
      WHEN 'mark_paid' THEN 'paid'
      WHEN 'reverse' THEN 'reversed' END,
    approved_at = CASE WHEN p_action='approve' THEN now() ELSE approved_at END,
    paid_at = CASE WHEN p_action='mark_paid' THEN now() ELSE paid_at END,
    notes = COALESCE(notes,'') || CASE WHEN p_notes IS NOT NULL THEN E'\n'||p_notes ELSE '' END
  WHERE id = p_commission;
END $$;
REVOKE EXECUTE ON FUNCTION public.admin_review_commission(uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_review_commission(uuid,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_mark_referral(p_referral uuid, p_action text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public._is_ops_or_god_admin(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;
  IF p_action NOT IN ('approve','mark_eligible','mark_paid','reject') THEN
    RAISE EXCEPTION 'invalid action: %', p_action;
  END IF;
  UPDATE public.driver_referrals SET
    status = CASE p_action
      WHEN 'approve' THEN 'approved'
      WHEN 'mark_eligible' THEN 'bonus_eligible'
      WHEN 'mark_paid' THEN 'paid'
      WHEN 'reject' THEN 'rejected' END,
    approved_at = CASE WHEN p_action IN ('approve','mark_eligible') AND approved_at IS NULL THEN now() ELSE approved_at END,
    paid_at = CASE WHEN p_action='mark_paid' THEN now() ELSE paid_at END
  WHERE id = p_referral;
END $$;
REVOKE EXECUTE ON FUNCTION public.admin_mark_referral(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_mark_referral(uuid,text) TO authenticated;

-- =========================
-- Triggers: commission auto-creation on ride completion
-- =========================
CREATE OR REPLACE FUNCTION public._driver_group_commission_on_ride()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_member record;
  v_group record;
  v_earning bigint;
  v_amount bigint;
BEGIN
  IF NEW.driver_id IS NULL THEN RETURN NEW; END IF;

  -- Completion: create pending commission
  IF NEW.status = 'completed' AND (OLD.status IS DISTINCT FROM 'completed') THEN
    SELECT m.* INTO v_member
      FROM public.driver_group_memberships m
     WHERE m.driver_user_id = NEW.driver_id AND m.status = 'active'
     LIMIT 1;
    IF v_member.id IS NULL THEN RETURN NEW; END IF;
    SELECT * INTO v_group FROM public.driver_groups WHERE id = v_member.group_id;
    IF v_group.id IS NULL OR v_group.status <> 'active' OR v_group.commission_percent <= 0 THEN
      RETURN NEW;
    END IF;
    v_earning := COALESCE(NEW.driver_earning_gnf, 0);
    v_amount := floor(v_earning * v_group.commission_percent / 100.0)::bigint;
    INSERT INTO public.driver_group_commissions (
      group_id, leader_user_id, driver_user_id, source_type, source_id,
      gross_driver_earning_gnf, commission_percent, commission_amount_gnf, status
    ) VALUES (
      v_group.id, v_group.leader_user_id, NEW.driver_id, 'ride_earning', NEW.id,
      v_earning, v_group.commission_percent, v_amount, 'pending'
    ) ON CONFLICT DO NOTHING;
  END IF;

  -- Cancellation after completion: reverse
  IF NEW.status = 'cancelled' AND OLD.status = 'completed' THEN
    UPDATE public.driver_group_commissions
      SET status = 'reversed'
    WHERE source_type = 'ride_earning' AND source_id = NEW.id
      AND status IN ('pending','approved');
  END IF;

  RETURN NEW;
END $$;

CREATE TRIGGER trg_ride_commission_after_complete
  AFTER UPDATE ON public.rides
  FOR EACH ROW EXECUTE FUNCTION public._driver_group_commission_on_ride();

-- =========================
-- Trigger: on driver approval, activate referral + membership
-- =========================
CREATE OR REPLACE FUNCTION public._driver_group_on_driver_approval()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_group record;
BEGIN
  IF NEW.status = 'approved' AND (OLD.status IS DISTINCT FROM 'approved') THEN
    -- activate pending membership
    UPDATE public.driver_group_memberships
       SET status = 'active'
     WHERE driver_user_id = NEW.user_id AND status = 'pending';

    -- mark referral as bonus_eligible and copy bonus amount
    FOR v_group IN
      SELECT r.id AS referral_id, g.signup_bonus_gnf
        FROM public.driver_referrals r
        LEFT JOIN public.driver_groups g ON g.id = r.group_id
       WHERE r.referred_driver_user_id = NEW.user_id AND r.status = 'pending'
    LOOP
      UPDATE public.driver_referrals
         SET status = 'bonus_eligible',
             approved_at = now(),
             bonus_amount_gnf = COALESCE(v_group.signup_bonus_gnf, 0)
       WHERE id = v_group.referral_id;
    END LOOP;
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_driver_group_on_approval
  AFTER UPDATE ON public.driver_profiles
  FOR EACH ROW EXECUTE FUNCTION public._driver_group_on_driver_approval();
