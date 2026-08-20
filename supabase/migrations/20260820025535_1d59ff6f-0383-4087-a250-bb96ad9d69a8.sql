-- R10 Part C: admin/internal audit surfaces + read-only shopper performance intelligence.

CREATE OR REPLACE FUNCTION public.marche_ranking_policy_admin_list()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public._is_ops_or_god_admin(auth.uid()) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  RETURN COALESCE((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.version DESC)
                     FROM public.marche_ranking_policies p), '[]'::jsonb);
END;
$$;
REVOKE ALL ON FUNCTION public.marche_ranking_policy_admin_list() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_ranking_policy_admin_list() TO authenticated, service_role;

-- Publishing a policy closes the current one: versioned, never overwritten.
CREATE OR REPLACE FUNCTION public.marche_ranking_policy_publish(p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_uid uuid := auth.uid(); v_next int; v_id uuid; cur record; v_at timestamptz := now();
BEGIN
  IF NOT public._is_ops_or_god_admin(v_uid) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  SELECT * INTO cur FROM public.marche_ranking_policies
   WHERE effective_to IS NULL ORDER BY version DESC LIMIT 1;

  SELECT COALESCE(max(version), 0) + 1 INTO v_next FROM public.marche_ranking_policies;

  IF cur.id IS NOT NULL THEN
    UPDATE public.marche_ranking_policies SET effective_to = v_at WHERE id = cur.id;
  END IF;

  INSERT INTO public.marche_ranking_policies (
    version, label, effective_from,
    w_price, w_reputation, w_reliability, w_distance, w_freshness,
    min_price_observations, min_reputation_events, min_fulfillment_history,
    distance_max_m, freshness_half_life_days, notes, created_by)
  VALUES (
    v_next,
    COALESCE(NULLIF(btrim(p_payload->>'label'), ''), 'R10 policy v' || v_next),
    v_at,
    COALESCE((p_payload->>'w_price')::int, COALESCE(cur.w_price, 2500)),
    COALESCE((p_payload->>'w_reputation')::int, COALESCE(cur.w_reputation, 2500)),
    COALESCE((p_payload->>'w_reliability')::int, COALESCE(cur.w_reliability, 2000)),
    COALESCE((p_payload->>'w_distance')::int, COALESCE(cur.w_distance, 2000)),
    COALESCE((p_payload->>'w_freshness')::int, COALESCE(cur.w_freshness, 1000)),
    COALESCE((p_payload->>'min_price_observations')::int, COALESCE(cur.min_price_observations, 3)),
    COALESCE((p_payload->>'min_reputation_events')::int, COALESCE(cur.min_reputation_events, 3)),
    COALESCE((p_payload->>'min_fulfillment_history')::int, COALESCE(cur.min_fulfillment_history, 3)),
    COALESCE((p_payload->>'distance_max_m')::int, COALESCE(cur.distance_max_m, 15000)),
    COALESCE((p_payload->>'freshness_half_life_days')::int, COALESCE(cur.freshness_half_life_days, 14)),
    NULLIF(btrim(p_payload->>'notes'), ''), v_uid)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', true, 'version', v_next, 'policy_id', v_id,
                            'previous_closed_at', CASE WHEN cur.id IS NOT NULL THEN v_at END);
END;
$$;
REVOKE ALL ON FUNCTION public.marche_ranking_policy_publish(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_ranking_policy_publish(jsonb) TO authenticated, service_role;

-- Full unsanitized evidence audit (admin only).
CREATE OR REPLACE FUNCTION public.marche_ranking_audit_listing(
  p_listing_id uuid, p_lat double precision DEFAULT NULL, p_lng double precision DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public._is_ops_or_god_admin(auth.uid()) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  RETURN public._marche_rank_evidence(p_listing_id, p_lat, p_lng, NULL);
END;
$$;
REVOKE ALL ON FUNCTION public.marche_ranking_audit_listing(uuid, double precision, double precision) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_ranking_audit_listing(uuid, double precision, double precision) TO authenticated, service_role;

-- Read-only shopper performance intelligence.
-- LAW: purely derived from frozen R7 truth; writes nothing; grants no assignment authority.
CREATE OR REPLACE FUNCTION public.marche_shopper_performance(p_shopper_user_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_admin boolean := public._is_ops_or_god_admin(v_uid);
  v_target uuid := COALESCE(p_shopper_user_id, v_uid);
  n_assigned int; n_completed int; n_cancelled int;
  med_shop numeric; med_total numeric;
  n_lines int; n_sub int; n_unavail int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF v_target <> v_uid AND NOT v_admin THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;

  SELECT count(*),
         count(*) FILTER (WHERE m.completed_at IS NOT NULL),
         count(*) FILTER (WHERE m.cancelled_at IS NOT NULL),
         percentile_cont(0.5) WITHIN GROUP (
           ORDER BY EXTRACT(EPOCH FROM (m.purchase_submitted_at - m.shopping_started_at))/60.0)
           FILTER (WHERE m.purchase_submitted_at IS NOT NULL AND m.shopping_started_at IS NOT NULL),
         percentile_cont(0.5) WITHIN GROUP (
           ORDER BY EXTRACT(EPOCH FROM (m.completed_at - m.assigned_at))/60.0)
           FILTER (WHERE m.completed_at IS NOT NULL)
    INTO n_assigned, n_completed, n_cancelled, med_shop, med_total
    FROM public.marche_procurement_missions m
   WHERE m.shopper_user_id = v_target;

  SELECT count(*),
         count(*) FILTER (WHERE r.state = 'substituted'),
         count(*) FILTER (WHERE r.state = 'unavailable')
    INTO n_lines, n_sub, n_unavail
    FROM public.marche_procurement_line_resolutions r
    JOIN public.marche_procurement_missions m ON m.request_id = r.request_id
   WHERE m.shopper_user_id = v_target;

  IF COALESCE(n_assigned, 0) = 0 THEN
    RETURN jsonb_build_object(
      'shopper_user_id', v_target, 'available', false,
      'reason', 'NO_PROCUREMENT_HISTORY',
      'read_only', true, 'affects_assignment', false);
  END IF;

  RETURN jsonb_build_object(
    'shopper_user_id', v_target,
    'available', true,
    'read_only', true,
    'affects_assignment', false,
    'missions_assigned', n_assigned,
    'missions_completed', n_completed,
    'missions_cancelled', n_cancelled,
    'completion_rate', round(n_completed::numeric / n_assigned::numeric, 4),
    'median_shopping_minutes', CASE WHEN med_shop IS NULL THEN NULL ELSE round(med_shop, 2) END,
    'median_total_minutes', CASE WHEN med_total IS NULL THEN NULL ELSE round(med_total, 2) END,
    'lines_resolved', COALESCE(n_lines, 0),
    'substitution_rate', CASE WHEN COALESCE(n_lines,0) = 0 THEN NULL
                              ELSE round(n_sub::numeric / n_lines::numeric, 4) END,
    'unavailable_rate', CASE WHEN COALESCE(n_lines,0) = 0 THEN NULL
                             ELSE round(n_unavail::numeric / n_lines::numeric, 4) END
  );
END;
$$;
REVOKE ALL ON FUNCTION public.marche_shopper_performance(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_shopper_performance(uuid) TO authenticated, service_role;