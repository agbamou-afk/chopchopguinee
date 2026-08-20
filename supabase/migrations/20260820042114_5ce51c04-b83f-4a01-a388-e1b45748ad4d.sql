ALTER TABLE public.marche_ranking_policies RENAME COLUMN min_fulfillment_history TO min_fulfillment_samples;

DO $mig$
DECLARE d text; fn text;
BEGIN
  FOREACH fn IN ARRAY ARRAY['_marche_rank_evidence','marche_ranking_policy_public','marche_ranking_policy_publish','_qa_node4_marche_r10'] LOOP
    FOR d IN SELECT pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'public' AND p.proname = fn LOOP
      EXECUTE replace(d, 'min_fulfillment_history', 'min_fulfillment_samples');
    END LOOP;
  END LOOP;
END $mig$;

DO $mig2$
DECLARE d text;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO d FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = '_qa_node4_marche_r10';
  d := regexp_replace(d,
    '''min_fulfillment_observations'',\s*''min_qualified_components''\)\) = 5',
    '''min_fulfillment_observations'',''min_fulfillment_samples'',''min_qualified_components'')) = 6');
  EXECUTE d;
END $mig2$;

CREATE OR REPLACE FUNCTION public.marche_shopper_performance(p_shopper_user_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_admin boolean := public._is_ops_or_god_admin(v_uid);
  v_target uuid := COALESCE(p_shopper_user_id, v_uid);
  n_assigned int; n_completed int; n_cancelled int;
  med_shop numeric; med_total numeric;
  n_lines int; n_sub int; n_unavail int;
  rep_n int; rep_avg numeric; rep_dims jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF v_target <> v_uid AND NOT v_admin THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;

  IF NOT public._marche_shopper_eligible(v_target) THEN
    RETURN jsonb_build_object(
      'shopper_user_id', v_target, 'available', false,
      'reason', 'SHOPPER_NOT_ELIGIBLE', 'read_only', true, 'affects_assignment', false);
  END IF;

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

  -- R9 shopper reputation ONLY (delivery_driver events are a different subject
  -- and carry strictly zero effect on shopper intelligence).
  SELECT count(*), avg(e.overall_score)
    INTO rep_n, rep_avg
    FROM public.marche_reputation_events e
   WHERE e.subject_kind = 'shopper' AND e.subject_user_id = v_target;

  SELECT COALESCE(jsonb_object_agg(d.dimension, round(d.avg_score, 2)), '{}'::jsonb)
    INTO rep_dims
    FROM (SELECT dm.dimension, avg(dm.score) AS avg_score
            FROM public.marche_reputation_dimensions dm
            JOIN public.marche_reputation_events e2 ON e2.id = dm.event_id
           WHERE e2.subject_kind = 'shopper' AND e2.subject_user_id = v_target
           GROUP BY dm.dimension) d;

  IF COALESCE(n_assigned, 0) = 0 THEN
    RETURN jsonb_build_object(
      'shopper_user_id', v_target, 'available', false,
      'reason', 'NO_PROCUREMENT_HISTORY',
      'read_only', true, 'affects_assignment', false,
      'delivery_driver_signal_effect', 0);
  END IF;

  RETURN jsonb_build_object(
    'shopper_user_id', v_target,
    'available', true,
    'read_only', true,
    'affects_assignment', false,
    'delivery_driver_signal_effect', 0,
    'reputation_subject_scope', 'shopper',
    'missions_assigned', n_assigned,
    'missions_completed', n_completed,
    'missions_cancelled_unattributed', jsonb_build_object(
      'value', n_cancelled, 'scored', false,
      'reason', 'NO_CANONICAL_CANCELLATION_ATTRIBUTION'),
    'median_shopping_minutes', CASE WHEN med_shop IS NULL THEN NULL ELSE round(med_shop, 2) END,
    'median_total_minutes', CASE WHEN med_total IS NULL THEN NULL ELSE round(med_total, 2) END,
    'lines_resolved', COALESCE(n_lines, 0),
    'substitution_rate', CASE WHEN COALESCE(n_lines,0) = 0 THEN NULL
                              ELSE round(n_sub::numeric / n_lines::numeric, 4) END,
    'unavailable_rate', CASE WHEN COALESCE(n_lines,0) = 0 THEN NULL
                             ELSE round(n_unavail::numeric / n_lines::numeric, 4) END,
    'reputation', CASE WHEN COALESCE(rep_n,0) < 3
      THEN jsonb_build_object('available', false, 'sample_count', COALESCE(rep_n,0),
                              'reason', 'INSUFFICIENT_REPUTATION_SAMPLE')
      ELSE jsonb_build_object('available', true, 'sample_count', rep_n,
                              'average_score', round(rep_avg, 2),
                              'subject_kind', 'shopper', 'dimensions', rep_dims)
      END
  );
END;
$function$;