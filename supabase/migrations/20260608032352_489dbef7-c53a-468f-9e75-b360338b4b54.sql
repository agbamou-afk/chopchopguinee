
-- ============================================================
-- Driver Groups / Syndicates v5
-- ============================================================

-- 1) Storage RLS for private bucket 'driver-group-checkins'
--    path layout: {group_id}/{filename}
DROP POLICY IF EXISTS "dgci leaders upload own group" ON storage.objects;
CREATE POLICY "dgci leaders upload own group"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'driver-group-checkins'
    AND EXISTS (
      SELECT 1 FROM public.driver_groups g
      WHERE g.id::text = (storage.foldername(name))[1]
        AND g.leader_user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "dgci leaders read own group" ON storage.objects;
CREATE POLICY "dgci leaders read own group"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'driver-group-checkins'
    AND (
      public._is_ops_or_god_admin(auth.uid())
      OR EXISTS (
        SELECT 1 FROM public.driver_groups g
        WHERE g.id::text = (storage.foldername(name))[1]
          AND g.leader_user_id = auth.uid()
      )
    )
  );

DROP POLICY IF EXISTS "dgci admins manage" ON storage.objects;
CREATE POLICY "dgci admins manage"
  ON storage.objects FOR ALL TO authenticated
  USING (bucket_id = 'driver-group-checkins' AND public._is_ops_or_god_admin(auth.uid()))
  WITH CHECK (bucket_id = 'driver-group-checkins' AND public._is_ops_or_god_admin(auth.uid()));

-- 2) Scheduler run log
CREATE TABLE IF NOT EXISTS public.driver_referral_milestone_job_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source text NOT NULL DEFAULT 'cron',
  processed integer NOT NULL DEFAULT 0,
  failed integer NOT NULL DEFAULT 0,
  eligible integer NOT NULL DEFAULT 0,
  error text,
  ran_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.driver_referral_milestone_job_runs TO authenticated;
GRANT ALL ON public.driver_referral_milestone_job_runs TO service_role;
ALTER TABLE public.driver_referral_milestone_job_runs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "admins read job runs" ON public.driver_referral_milestone_job_runs;
CREATE POLICY "admins read job runs" ON public.driver_referral_milestone_job_runs
  FOR SELECT TO authenticated USING (public._is_ops_or_god_admin(auth.uid()));

-- 3) Cron-callable wrapper that logs each run.
CREATE OR REPLACE FUNCTION public.process_driver_referral_milestone_jobs_cron(p_limit integer DEFAULT 100)
RETURNS public.driver_referral_milestone_job_runs
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r record;
  run public.driver_referral_milestone_job_runs;
BEGIN
  BEGIN
    SELECT * INTO r FROM public.process_driver_referral_milestone_jobs(p_limit);
    INSERT INTO public.driver_referral_milestone_job_runs(source, processed, failed, eligible)
      VALUES ('cron', COALESCE(r.processed,0), COALESCE(r.failed,0), COALESCE(r.eligible,0))
      RETURNING * INTO run;
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO public.driver_referral_milestone_job_runs(source, error)
      VALUES ('cron', SQLERRM) RETURNING * INTO run;
  END;
  RETURN run;
END $$;
REVOKE ALL ON FUNCTION public.process_driver_referral_milestone_jobs_cron(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.process_driver_referral_milestone_jobs_cron(integer) TO service_role, authenticated;

-- 4) Group scorecard (admin)
CREATE OR REPLACE FUNCTION public.admin_group_scorecard(p_group uuid, p_days integer DEFAULT 30)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v jsonb;
  v_from timestamptz := now() - make_interval(days => GREATEST(p_days,1));
BEGIN
  IF NOT public._is_ops_or_god_admin(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  SELECT jsonb_build_object(
    'group_id', p_group,
    'period_days', p_days,
    'recruited', (SELECT count(*) FROM public.driver_referrals WHERE group_id = p_group),
    'approved', (SELECT count(*) FROM public.driver_referrals WHERE group_id = p_group AND status IN ('approved','bonus_eligible','paid')),
    'active_drivers', (SELECT count(*) FROM public.driver_group_memberships WHERE group_id = p_group AND status = 'active'),
    'rides_completed', COALESCE((
      SELECT count(*) FROM public.rides r
      JOIN public.driver_group_memberships m ON m.driver_user_id = r.driver_id AND m.group_id = p_group AND m.status='active'
      WHERE r.status = 'completed' AND r.completed_at >= v_from
    ),0),
    'gross_earnings_gnf', COALESCE((
      SELECT SUM(r.driver_earnings_gnf) FROM public.rides r
      JOIN public.driver_group_memberships m ON m.driver_user_id = r.driver_id AND m.group_id = p_group AND m.status='active'
      WHERE r.status = 'completed' AND r.completed_at >= v_from
    ),0),
    'commissions_pending_gnf', COALESCE((SELECT SUM(commission_amount_gnf) FROM public.driver_group_commissions WHERE group_id=p_group AND status IN ('pending','approved')),0),
    'commissions_paid_gnf', COALESCE((SELECT SUM(commission_amount_gnf) FROM public.driver_group_commissions WHERE group_id=p_group AND status='paid' AND paid_at >= v_from),0),
    'signup_bonuses_eligible', (SELECT count(*) FROM public.driver_referrals WHERE group_id=p_group AND status='bonus_eligible'),
    'signup_bonuses_paid_gnf', COALESCE((SELECT SUM(bonus_amount_gnf) FROM public.driver_referrals WHERE group_id=p_group AND status='paid' AND paid_at >= v_from),0),
    'checkins_count', (SELECT count(*) FROM public.driver_group_field_checkins WHERE group_id=p_group AND created_at >= v_from),
    'risk_held_count', (SELECT count(*) FROM public.driver_referrals WHERE group_id=p_group AND COALESCE(risk_status,'clear') IN ('held','review','rejected'))
  ) INTO v;
  RETURN v;
END $$;
REVOKE ALL ON FUNCTION public.admin_group_scorecard(uuid,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_group_scorecard(uuid,integer) TO authenticated;

-- 5) Leader-facing scorecard (own group only)
CREATE OR REPLACE FUNCTION public.leader_get_my_scorecard(p_days integer DEFAULT 30)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_group uuid;
BEGIN
  SELECT id INTO v_group FROM public.driver_groups WHERE leader_user_id = auth.uid() LIMIT 1;
  IF v_group IS NULL THEN RETURN NULL; END IF;
  RETURN (
    SELECT jsonb_build_object(
      'group_id', v_group,
      'period_days', p_days,
      'recruited', (SELECT count(*) FROM public.driver_referrals WHERE group_id = v_group),
      'approved', (SELECT count(*) FROM public.driver_referrals WHERE group_id = v_group AND status IN ('approved','bonus_eligible','paid')),
      'active_drivers', (SELECT count(*) FROM public.driver_group_memberships WHERE group_id = v_group AND status='active'),
      'commissions_pending_gnf', COALESCE((SELECT SUM(commission_amount_gnf) FROM public.driver_group_commissions WHERE group_id=v_group AND status IN ('pending','approved')),0),
      'commissions_paid_gnf', COALESCE((SELECT SUM(commission_amount_gnf) FROM public.driver_group_commissions WHERE group_id=v_group AND status='paid' AND paid_at >= now() - make_interval(days => GREATEST(p_days,1))),0),
      'signup_bonuses_eligible', (SELECT count(*) FROM public.driver_referrals WHERE group_id=v_group AND status='bonus_eligible'),
      'checkins_count', (SELECT count(*) FROM public.driver_group_field_checkins WHERE group_id=v_group AND created_at >= now() - make_interval(days => GREATEST(p_days,1)))
    )
  );
END $$;
REVOKE ALL ON FUNCTION public.leader_get_my_scorecard(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.leader_get_my_scorecard(integer) TO authenticated;

-- 6) Group risk scorecard aggregate (admin)
CREATE OR REPLACE FUNCTION public.admin_group_risk_scorecard()
RETURNS TABLE(group_id uuid, group_name text, referrals_count bigint, risk_held bigint, risk_review bigint, commissions_held bigint, last_review_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public._is_ops_or_god_admin(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  RETURN QUERY
    SELECT g.id, g.name,
      (SELECT count(*) FROM public.driver_referrals dr WHERE dr.group_id=g.id),
      (SELECT count(*) FROM public.driver_referrals dr WHERE dr.group_id=g.id AND dr.risk_status='held'),
      (SELECT count(*) FROM public.driver_referrals dr WHERE dr.group_id=g.id AND dr.risk_status='review'),
      (SELECT count(*) FROM public.driver_group_commissions c WHERE c.group_id=g.id AND COALESCE(c.risk_status,'clear')='held'),
      (SELECT max(rr.reviewed_at) FROM public.driver_group_risk_reviews rr
         WHERE rr.entity_type IN ('referral','commission','group')
           AND (rr.entity_id = g.id OR rr.entity_id IN (SELECT id FROM public.driver_referrals WHERE group_id=g.id)
                OR rr.entity_id IN (SELECT id FROM public.driver_group_commissions WHERE group_id=g.id)))
    FROM public.driver_groups g
    ORDER BY g.name;
END $$;
REVOKE ALL ON FUNCTION public.admin_group_risk_scorecard() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_group_risk_scorecard() TO authenticated;

-- 7) Incentive suggestions (data-backed, non-automatic)
CREATE OR REPLACE FUNCTION public.admin_incentive_suggestions()
RETURNS TABLE(kind text, target_group uuid, target_zone uuid, severity text, message text, signal jsonb)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public._is_ops_or_god_admin(auth.uid()) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- Low active drivers on a group
  RETURN QUERY
  SELECT 'low_active_drivers'::text, g.id, NULL::uuid, 'medium'::text,
    format('Relancer le groupe %s : %s chauffeurs actifs.', g.name,
      (SELECT count(*) FROM public.driver_group_memberships WHERE group_id=g.id AND status='active')),
    jsonb_build_object('active',
      (SELECT count(*) FROM public.driver_group_memberships WHERE group_id=g.id AND status='active'))
  FROM public.driver_groups g
  WHERE g.status='active'
    AND (SELECT count(*) FROM public.driver_group_memberships WHERE group_id=g.id AND status='active') < 3;

  -- Group with high risk-held referrals
  RETURN QUERY
  SELECT 'risk_pause'::text, g.id, NULL::uuid, 'high'::text,
    format('Examiner les paiements du groupe %s : %s parrainages en attente de revue.', g.name, h.held_count),
    jsonb_build_object('risk_held', h.held_count)
  FROM public.driver_groups g
  JOIN LATERAL (
    SELECT count(*)::bigint AS held_count FROM public.driver_referrals
    WHERE group_id=g.id AND risk_status IN ('held','review')
  ) h ON true
  WHERE h.held_count >= 3;

  -- Zones with no group coverage
  RETURN QUERY
  SELECT 'uncovered_zone'::text, NULL::uuid, z.id, 'low'::text,
    format('Aucun groupe assigné à %s — envisager une campagne de recrutement.',
      COALESCE(z.neighborhood, z.commune, z.city, 'zone')),
    jsonb_build_object('zone', COALESCE(z.neighborhood,z.commune,z.city))
  FROM public.zones z
  WHERE NOT EXISTS (
    SELECT 1 FROM public.driver_group_memberships m WHERE m.assigned_zone_id = z.id AND m.status='active'
  );
END $$;
REVOKE ALL ON FUNCTION public.admin_incentive_suggestions() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_incentive_suggestions() TO authenticated;

-- 8) v5 risk scoring returning reason codes array
CREATE OR REPLACE FUNCTION public.score_driver_referral_risk_v2(p_referral uuid)
RETURNS TABLE(score integer, level text, reason_codes text[])
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r public.driver_referrals;
  v_group public.driver_groups;
  v_dp public.driver_profiles;
  v_score int := 0;
  v_reasons text[] := ARRAY[]::text[];
  v_recent int;
BEGIN
  SELECT * INTO r FROM public.driver_referrals WHERE id=p_referral;
  IF r.id IS NULL THEN RAISE EXCEPTION 'referral_not_found'; END IF;
  SELECT * INTO v_group FROM public.driver_groups WHERE id=r.group_id;
  SELECT * INTO v_dp FROM public.driver_profiles WHERE user_id=r.referred_driver_user_id;

  IF v_group.status <> 'active' THEN v_score := v_score+40; v_reasons := v_reasons || 'groupe_suspendu'; END IF;
  IF v_dp.status IN ('suspended','rejected','banned') THEN v_score := v_score+60; v_reasons := v_reasons || ('chauffeur_' || v_dp.status); END IF;
  IF r.status IN ('bonus_eligible','paid') AND r.rides_completed_count = 0 AND r.created_at < now() - interval '7 days' THEN
    v_score := v_score+30; v_reasons := v_reasons || 'aucune_course_post_bonus';
  END IF;
  SELECT count(*) INTO v_recent FROM public.driver_referrals WHERE group_id=r.group_id AND created_at > now() - interval '24 hours';
  IF v_recent > 10 THEN v_score := v_score+25; v_reasons := v_reasons || 'volume_24h_eleve'; END IF;

  RETURN QUERY SELECT v_score,
    CASE WHEN v_score>=60 THEN 'high' WHEN v_score>=25 THEN 'medium' WHEN v_score>=10 THEN 'low' ELSE 'clear' END,
    v_reasons;
END $$;
REVOKE ALL ON FUNCTION public.score_driver_referral_risk_v2(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.score_driver_referral_risk_v2(uuid) TO authenticated;
