-- ============ R10 POLICY SHAPE (explicit, no implicit magic) ============
ALTER TABLE public.marche_ranking_policies
  DROP CONSTRAINT IF EXISTS marche_ranking_weights_sum,
  DROP CONSTRAINT IF EXISTS marche_ranking_weights_nonneg,
  DROP CONSTRAINT IF EXISTS marche_ranking_thresholds;

ALTER TABLE public.marche_ranking_policies
  ADD COLUMN IF NOT EXISTS w_responsiveness integer NOT NULL DEFAULT 750,
  ADD COLUMN IF NOT EXISTS w_preparation integer NOT NULL DEFAULT 750,
  ADD COLUMN IF NOT EXISTS price_lookback_hours integer NOT NULL DEFAULT 168,
  ADD COLUMN IF NOT EXISTS reliability_lookback_days integer NOT NULL DEFAULT 90,
  ADD COLUMN IF NOT EXISTS fulfillment_lookback_days integer NOT NULL DEFAULT 90,
  ADD COLUMN IF NOT EXISTS min_fulfillment_observations integer NOT NULL DEFAULT 5,
  ADD COLUMN IF NOT EXISTS min_qualified_components integer NOT NULL DEFAULT 2;

ALTER TABLE public.marche_ranking_policies
  DROP COLUMN IF EXISTS freshness_half_life_days;

ALTER TABLE public.marche_ranking_policies
  ALTER COLUMN w_price SET DEFAULT 2500,
  ALTER COLUMN w_reputation SET DEFAULT 2000,
  ALTER COLUMN w_reliability SET DEFAULT 1500,
  ALTER COLUMN w_distance SET DEFAULT 1500,
  ALTER COLUMN w_freshness SET DEFAULT 1000,
  ALTER COLUMN min_price_observations SET DEFAULT 5,
  ALTER COLUMN min_fulfillment_history SET DEFAULT 5;

UPDATE public.marche_ranking_policies SET
  w_price = 2500, w_reputation = 2000, w_reliability = 1500,
  w_distance = 1500, w_freshness = 1000, w_responsiveness = 750, w_preparation = 750,
  min_price_observations = GREATEST(min_price_observations, 5),
  min_fulfillment_history = GREATEST(min_fulfillment_history, 5),
  updated_at = now();

ALTER TABLE public.marche_ranking_policies
  ADD CONSTRAINT marche_ranking_weights_nonneg CHECK (
    w_price >= 0 AND w_reputation >= 0 AND w_reliability >= 0 AND w_distance >= 0
    AND w_freshness >= 0 AND w_responsiveness >= 0 AND w_preparation >= 0),
  ADD CONSTRAINT marche_ranking_weights_sum CHECK (
    w_price + w_reputation + w_reliability + w_distance + w_freshness
    + w_responsiveness + w_preparation = 10000),
  ADD CONSTRAINT marche_ranking_thresholds CHECK (
    min_price_observations >= 5 AND min_reputation_events >= 3
    AND min_fulfillment_history >= 3 AND min_fulfillment_observations >= 3
    AND min_qualified_components >= 2 AND distance_max_m > 0
    AND price_lookback_hours > 0 AND reliability_lookback_days > 0
    AND fulfillment_lookback_days > 0);

-- ============ R10 EVIDENCE (server-authoritative, fail-honest) ============
CREATE OR REPLACE FUNCTION public._marche_rank_evidence(
  p_listing_id uuid,
  p_lat double precision DEFAULT NULL,
  p_lng double precision DEFAULT NULL,
  p_policy jsonb DEFAULT NULL,
  p_at timestamptz DEFAULT now())
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  pol jsonb := COALESCE(p_policy, public._marche_ranking_policy(p_at));
  v_now timestamptz := COALESCE(p_at, now());
  l record; st record;
  comp jsonb := '{}'::jsonb;
  own_price numeric; own_unit text; own_variant uuid; own_zone text; own_latest timestamptz;
  v_fresh text;
  n_obs int; p25 numeric; p75 numeric; coh_latest timestamptz; coh_conf text;
  rep_n int; rep_avg numeric;
  n_delivered int; n_rejected int; rel_total int;
  dist_m double precision;
  resp_n int; resp_p50 numeric; resp_ref numeric; resp_ref_n int;
  prep_n int; prep_p50 numeric; prep_ref numeric; prep_ref_n int;
  s numeric; wsum numeric := 0; acc numeric := 0; used int := 0;
  total_comp int := 8; min_needed int;
  why jsonb := '[]'::jsonb; sc numeric; sbps int; cold boolean;
BEGIN
  IF pol IS NULL THEN
    RETURN jsonb_build_object('listing_id', p_listing_id, 'ranked', false,
                              'reason', 'NO_EFFECTIVE_RANKING_POLICY');
  END IF;
  min_needed := (pol->>'min_qualified_components')::int;

  SELECT ml.id, ml.store_id, ml.price_gnf, ml.created_at, ml.staple_variant_id
    INTO l FROM public.marketplace_listings ml WHERE ml.id = p_listing_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('listing_id', p_listing_id, 'ranked', false,
                              'reason', 'LISTING_NOT_FOUND');
  END IF;

  SELECT s2.id, s2.latitude, s2.longitude
    INTO st FROM public.merchant_stores s2 WHERE s2.id = l.store_id;

  ------------------------------------------------------ 1) PRICE POSITION (R8)
  own_variant := l.staple_variant_id;
  IF own_variant IS NULL THEN
    comp := comp || jsonb_build_object('price', jsonb_build_object(
      'available', false, 'score', NULL, 'reason', 'LISTING_NOT_MAPPED_TO_VARIANT'));
  ELSE
    SELECT o.normalized_unit_price_gnf, o.canonical_base_unit, o.zone_commune, o.observed_at
      INTO own_price, own_unit, own_zone, own_latest
      FROM public.marche_procurement_price_observations o
     WHERE o.listing_id = l.id AND o.source_type = 'merchant_ask'
       AND o.comparable AND o.superseded_by IS NULL
     ORDER BY o.observed_at DESC LIMIT 1;

    IF own_price IS NULL THEN
      comp := comp || jsonb_build_object('price', jsonb_build_object(
        'available', false, 'score', NULL, 'reason', 'NO_COMPARABLE_LISTING_ASK'));
    ELSE
      -- Cohort law: same variant + same canonical base unit + same zone_commune
      -- (NULL zone only cohorts with NULL zone), inside the policy freshness window,
      -- excluding this listing's own observations entirely.
      SELECT count(*), max(o.observed_at),
             percentile_cont(0.25) WITHIN GROUP (ORDER BY o.normalized_unit_price_gnf),
             percentile_cont(0.75) WITHIN GROUP (ORDER BY o.normalized_unit_price_gnf)
        INTO n_obs, coh_latest, p25, p75
        FROM public.marche_procurement_price_observations o
       WHERE o.variant_id = own_variant
         AND o.canonical_base_unit = own_unit
         AND o.zone_commune IS NOT DISTINCT FROM own_zone
         AND o.comparable AND o.superseded_by IS NULL
         AND o.source_type IN ('merchant_ask','verified_procurement')
         AND o.observed_at >= v_now - make_interval(hours => (pol->>'price_lookback_hours')::int)
         AND (o.listing_id IS NULL OR o.listing_id <> l.id);

      coh_conf := public.marche_price_confidence(COALESCE(n_obs,0), coh_latest);

      IF COALESCE(n_obs,0) < (pol->>'min_price_observations')::int
         OR coh_conf = 'insufficient'
         OR public.marche_price_freshness(coh_latest) IN ('none','stale') THEN
        comp := comp || jsonb_build_object('price', jsonb_build_object(
          'available', false, 'score', NULL, 'sample_count', COALESCE(n_obs,0),
          'cohort_zone_commune', own_zone, 'cohort_confidence', coh_conf,
          'reason', 'INSUFFICIENT_PRICE_EVIDENCE'));
      ELSE
        IF p75 IS NULL OR p25 IS NULL OR p75 <= p25 THEN
          s := 0.5;
        ELSE
          s := GREATEST(0, LEAST(1, (p75 - own_price) / (p75 - p25)));
        END IF;
        comp := comp || jsonb_build_object('price', jsonb_build_object(
          'available', true, 'score', round(s, 6), 'sample_count', n_obs,
          'cohort_zone_commune', own_zone, 'cohort_confidence', coh_conf,
          'canonical_base_unit', own_unit, 'self_excluded', true,
          'method', 'r8_zone_cohort_p25_p75'));
        acc := acc + s * (pol->>'w_price')::numeric;
        wsum := wsum + (pol->>'w_price')::numeric; used := used + 1;
      END IF;
    END IF;
  END IF;

  ------------------------------------------- 2) PRICE-ASK FRESHNESS (R8 only)
  v_fresh := public.marche_price_freshness(own_latest);
  IF v_fresh = 'none' THEN
    comp := comp || jsonb_build_object('price_freshness', jsonb_build_object(
      'available', false, 'score', NULL, 'freshness', 'none',
      'reason', 'NO_PRICE_OBSERVATION'));
  ELSE
    s := CASE v_fresh WHEN 'fresh' THEN 1.0 WHEN 'aging' THEN 0.5 ELSE 0.0 END;
    comp := comp || jsonb_build_object('price_freshness', jsonb_build_object(
      'available', true, 'score', round(s, 6), 'freshness', v_fresh,
      'observed_at', own_latest, 'method', 'r8_merchant_ask_freshness'));
    acc := acc + s * (pol->>'w_freshness')::numeric;
    wsum := wsum + (pol->>'w_freshness')::numeric; used := used + 1;
  END IF;

  ------------------------------------------------------- 3) REPUTATION (R9)
  SELECT count(*), avg(e.overall_score)
    INTO rep_n, rep_avg
    FROM public.marche_reputation_events e
   WHERE e.subject_kind = 'merchant_store' AND e.subject_store_id = l.store_id;

  IF COALESCE(rep_n,0) < (pol->>'min_reputation_events')::int THEN
    comp := comp || jsonb_build_object('reputation', jsonb_build_object(
      'available', false, 'score', NULL, 'sample_count', COALESCE(rep_n,0),
      'reason', 'INSUFFICIENT_REPUTATION_SAMPLE'));
  ELSE
    s := GREATEST(0, LEAST(1, (rep_avg - 1) / 4.0));
    comp := comp || jsonb_build_object('reputation', jsonb_build_object(
      'available', true, 'score', round(s, 6), 'sample_count', rep_n,
      'subject_kind', 'merchant_store'));
    acc := acc + s * (pol->>'w_reputation')::numeric;
    wsum := wsum + (pol->>'w_reputation')::numeric; used := used + 1;
  END IF;

  ----------------------------------- 4) MERCHANT RELIABILITY (merchant acts only)
  SELECT count(*) FILTER (WHERE o.fulfillment_state = 'delivered'),
         count(*) FILTER (WHERE o.rejected_at IS NOT NULL)
    INTO n_delivered, n_rejected
    FROM public.marche_orders o
   WHERE o.merchant_store_id = l.store_id
     AND o.created_at >= v_now - make_interval(days => (pol->>'reliability_lookback_days')::int);
  rel_total := COALESCE(n_delivered,0) + COALESCE(n_rejected,0);

  IF rel_total < (pol->>'min_fulfillment_history')::int THEN
    comp := comp || jsonb_build_object('reliability', jsonb_build_object(
      'available', false, 'score', NULL, 'sample_count', rel_total,
      'reason', 'INSUFFICIENT_FULFILLMENT_HISTORY'));
  ELSE
    s := n_delivered::numeric / rel_total::numeric;
    comp := comp || jsonb_build_object('reliability', jsonb_build_object(
      'available', true, 'score', round(s, 6), 'sample_count', rel_total,
      'delivered', n_delivered, 'merchant_rejected', n_rejected,
      'lookback_days', (pol->>'reliability_lookback_days')::int,
      'buyer_cancellation_counted', false, 'courier_failure_counted', false));
    acc := acc + s * (pol->>'w_reliability')::numeric;
    wsum := wsum + (pol->>'w_reliability')::numeric; used := used + 1;
  END IF;

  ------------------------- 5) RESPONSIVENESS (R3.5 COMMIT_TO_MERCHANT_ACCEPTED)
  SELECT count(*), percentile_cont(0.5) WITHIN GROUP (ORDER BY f.duration_seconds)
    INTO resp_n, resp_p50
    FROM public.marche_fulfillment_observations f
   WHERE f.merchant_store_id = l.store_id
     AND f.metric_name = 'COMMIT_TO_MERCHANT_ACCEPTED'
     AND f.observed_at >= v_now - make_interval(days => (pol->>'fulfillment_lookback_days')::int);

  SELECT count(*), percentile_cont(0.5) WITHIN GROUP (ORDER BY f.duration_seconds)
    INTO resp_ref_n, resp_ref
    FROM public.marche_fulfillment_observations f
   WHERE f.metric_name = 'COMMIT_TO_MERCHANT_ACCEPTED'
     AND f.observed_at >= v_now - make_interval(days => (pol->>'fulfillment_lookback_days')::int);

  IF COALESCE(resp_n,0) < (pol->>'min_fulfillment_observations')::int
     OR COALESCE(resp_ref_n,0) < (pol->>'min_fulfillment_observations')::int
     OR resp_ref IS NULL THEN
    comp := comp || jsonb_build_object('responsiveness', jsonb_build_object(
      'available', false, 'score', NULL, 'sample_count', COALESCE(resp_n,0),
      'reason', 'INSUFFICIENT_RESPONSIVENESS_OBSERVATIONS'));
  ELSE
    s := GREATEST(0, LEAST(1, GREATEST(resp_ref,1) / GREATEST(resp_p50,1)));
    comp := comp || jsonb_build_object('responsiveness', jsonb_build_object(
      'available', true, 'score', round(s, 6), 'sample_count', resp_n,
      'store_median_seconds', round(resp_p50,1), 'platform_median_seconds', round(resp_ref,1),
      'metric_name', 'COMMIT_TO_MERCHANT_ACCEPTED', 'method', 'observed_median_vs_platform_median'));
    acc := acc + s * (pol->>'w_responsiveness')::numeric;
    wsum := wsum + (pol->>'w_responsiveness')::numeric; used := used + 1;
  END IF;

  --------------------------- 6) PREPARATION (R3.5 MERCHANT_ACCEPTED_TO_READY)
  SELECT count(*), percentile_cont(0.5) WITHIN GROUP (ORDER BY f.duration_seconds)
    INTO prep_n, prep_p50
    FROM public.marche_fulfillment_observations f
   WHERE f.merchant_store_id = l.store_id
     AND f.metric_name = 'MERCHANT_ACCEPTED_TO_READY'
     AND f.observed_at >= v_now - make_interval(days => (pol->>'fulfillment_lookback_days')::int);

  SELECT count(*), percentile_cont(0.5) WITHIN GROUP (ORDER BY f.duration_seconds)
    INTO prep_ref_n, prep_ref
    FROM public.marche_fulfillment_observations f
   WHERE f.metric_name = 'MERCHANT_ACCEPTED_TO_READY'
     AND f.observed_at >= v_now - make_interval(days => (pol->>'fulfillment_lookback_days')::int);

  IF COALESCE(prep_n,0) < (pol->>'min_fulfillment_observations')::int
     OR COALESCE(prep_ref_n,0) < (pol->>'min_fulfillment_observations')::int
     OR prep_ref IS NULL THEN
    comp := comp || jsonb_build_object('preparation', jsonb_build_object(
      'available', false, 'score', NULL, 'sample_count', COALESCE(prep_n,0),
      'reason', 'INSUFFICIENT_PREPARATION_OBSERVATIONS'));
  ELSE
    s := GREATEST(0, LEAST(1, GREATEST(prep_ref,1) / GREATEST(prep_p50,1)));
    comp := comp || jsonb_build_object('preparation', jsonb_build_object(
      'available', true, 'score', round(s, 6), 'sample_count', prep_n,
      'store_median_seconds', round(prep_p50,1), 'platform_median_seconds', round(prep_ref,1),
      'metric_name', 'MERCHANT_ACCEPTED_TO_READY', 'method', 'observed_median_vs_platform_median'));
    acc := acc + s * (pol->>'w_preparation')::numeric;
    wsum := wsum + (pol->>'w_preparation')::numeric; used := used + 1;
  END IF;

  ------------------------------------------------- 7) DISTANCE (fully optional)
  IF p_lat IS NULL OR p_lng IS NULL THEN
    comp := comp || jsonb_build_object('distance', jsonb_build_object(
      'available', false, 'score', NULL, 'distance_m', NULL,
      'penalised', false, 'reason', 'NO_CUSTOMER_COORDINATES'));
  ELSIF st.latitude IS NULL OR st.longitude IS NULL THEN
    comp := comp || jsonb_build_object('distance', jsonb_build_object(
      'available', false, 'score', NULL, 'distance_m', NULL,
      'penalised', false, 'reason', 'NO_STORE_COORDINATES'));
  ELSE
    dist_m := public._map_distance_meters(p_lat, p_lng, st.latitude, st.longitude);
    s := GREATEST(0, 1 - LEAST(1, dist_m / (pol->>'distance_max_m')::numeric));
    comp := comp || jsonb_build_object('distance', jsonb_build_object(
      'available', true, 'score', round(s, 6), 'distance_m', round(dist_m::numeric, 1),
      'method', 'haversine_great_circle', 'road_distance', false));
    acc := acc + s * (pol->>'w_distance')::numeric;
    wsum := wsum + (pol->>'w_distance')::numeric; used := used + 1;
  END IF;

  ---------------------- 8) AVAILABILITY ACCURACY: never synthesised (hard gate only)
  comp := comp || jsonb_build_object('availability_accuracy', jsonb_build_object(
    'available', false, 'score', NULL, 'reason', 'NOT_COLLECTED',
    'note', 'Availability is a hard eligibility gate (R1/R3); no stock-miss telemetry exists.'));

  ------------------------------------------------- TRUE COLD START (no invention)
  cold := (used < min_needed);
  sc := CASE WHEN cold OR wsum <= 0 THEN NULL ELSE round(acc / wsum, 6) END;
  sbps := CASE WHEN cold OR wsum <= 0 THEN NULL ELSE round(10000 * acc / wsum)::int END;

  ------------------------------------------------- SERVER-AUTHORED REASONS (<=2)
  IF NOT cold THEN
    IF (comp#>>'{price,available}')::boolean AND (comp#>>'{price,score}')::numeric >= 0.7 THEN
      why := why || jsonb_build_array(jsonb_build_object(
        'code','GOOD_VALUE','label','Bon rapport qualité-prix'));
    END IF;
    IF jsonb_array_length(why) < 2
       AND (comp#>>'{reputation,available}')::boolean
       AND (comp#>>'{reputation,score}')::numeric >= 0.75 THEN
      why := why || jsonb_build_array(jsonb_build_object(
        'code','WELL_RATED','label','Très bien noté'));
    END IF;
    IF jsonb_array_length(why) < 2
       AND (comp#>>'{preparation,available}')::boolean
       AND (comp#>>'{preparation,score}')::numeric >= 0.7 THEN
      why := why || jsonb_build_array(jsonb_build_object(
        'code','FAST_PREPARATION','label','Préparation rapide'));
    END IF;
    IF jsonb_array_length(why) < 2
       AND (comp#>>'{distance,available}')::boolean
       AND (comp#>>'{distance,distance_m}')::numeric <= 3000 THEN
      why := why || jsonb_build_array(jsonb_build_object(
        'code','NEARBY','label','Proche de vous'));
    END IF;
    IF jsonb_array_length(why) < 2
       AND (comp#>>'{price_freshness,available}')::boolean
       AND (comp#>>'{price_freshness,freshness}') = 'fresh' THEN
      why := why || jsonb_build_array(jsonb_build_object(
        'code','PRICE_RECENTLY_UPDATED','label','Prix mis à jour récemment'));
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'listing_id', l.id,
    'store_id', l.store_id,
    'ranked', true,
    'policy_version', (pol->>'version')::int,
    'policy_id', pol->>'id',
    'components', comp,
    'components_total', total_comp,
    'qualified_components', used,
    'min_qualified_components', min_needed,
    'evidence_completeness', round(used::numeric / total_comp::numeric, 4),
    'cold_start', cold,
    'cold_start_reason', CASE WHEN cold THEN 'INSUFFICIENT_EVIDENCE' ELSE NULL END,
    'promotion_effect', 0,
    'score', sc,
    'score_bps', sbps,
    'why_ranked', why,
    'computed_at', v_now
  );
END;
$function$;

-- ============ POLICY PUBLISH (explicit shape, fail closed) ============
CREATE OR REPLACE FUNCTION public.marche_ranking_policy_publish(p_payload jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_uid uuid := auth.uid(); v_id uuid; v_version int; k text;
BEGIN
  IF NOT public._is_ops_or_god_admin(v_uid) THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  IF p_payload IS NULL THEN RAISE EXCEPTION 'PAYLOAD_REQUIRED'; END IF;

  FOREACH k IN ARRAY ARRAY['label','w_price','w_reputation','w_reliability','w_distance',
                           'w_freshness','w_responsiveness','w_preparation',
                           'min_price_observations','min_reputation_events','min_fulfillment_history',
                           'min_fulfillment_observations','min_qualified_components',
                           'distance_max_m','price_lookback_hours',
                           'reliability_lookback_days','fulfillment_lookback_days'] LOOP
    IF NOT (p_payload ? k) OR p_payload->>k IS NULL THEN
      RAISE EXCEPTION 'POLICY_FIELD_REQUIRED:%', k;
    END IF;
  END LOOP;

  SELECT COALESCE(max(version),0) + 1 INTO v_version FROM public.marche_ranking_policies;

  UPDATE public.marche_ranking_policies
     SET effective_to = now(), updated_at = now()
   WHERE effective_to IS NULL;

  INSERT INTO public.marche_ranking_policies(
    version, label, effective_from,
    w_price, w_reputation, w_reliability, w_distance, w_freshness,
    w_responsiveness, w_preparation,
    min_price_observations, min_reputation_events, min_fulfillment_history,
    min_fulfillment_observations, min_qualified_components,
    distance_max_m, price_lookback_hours, reliability_lookback_days, fulfillment_lookback_days,
    notes, created_by)
  VALUES (
    v_version, p_payload->>'label', now(),
    (p_payload->>'w_price')::int, (p_payload->>'w_reputation')::int,
    (p_payload->>'w_reliability')::int, (p_payload->>'w_distance')::int,
    (p_payload->>'w_freshness')::int, (p_payload->>'w_responsiveness')::int,
    (p_payload->>'w_preparation')::int,
    (p_payload->>'min_price_observations')::int, (p_payload->>'min_reputation_events')::int,
    (p_payload->>'min_fulfillment_history')::int, (p_payload->>'min_fulfillment_observations')::int,
    (p_payload->>'min_qualified_components')::int,
    (p_payload->>'distance_max_m')::int, (p_payload->>'price_lookback_hours')::int,
    (p_payload->>'reliability_lookback_days')::int, (p_payload->>'fulfillment_lookback_days')::int,
    p_payload->>'notes', v_uid)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', true, 'policy_id', v_id, 'version', v_version);
END;
$function$;

-- ============ SHOPPER INTELLIGENCE (eligibility-gated, honest) ============
CREATE OR REPLACE FUNCTION public.marche_shopper_performance(p_shopper_user_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
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

  -- R9 shopper reputation ONLY (delivery_driver events are a different subject).
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
      'read_only', true, 'affects_assignment', false);
  END IF;

  RETURN jsonb_build_object(
    'shopper_user_id', v_target,
    'available', true,
    'read_only', true,
    'affects_assignment', false,
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