-- ============ NODE 4 — MARCHÉ R10 : DISCOVERY + RANKING INTELLIGENCE ============
-- Part A: versioned/effective-dated ranking policy + canonical per-listing evidence engine.

CREATE TABLE IF NOT EXISTS public.marche_ranking_policies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  version integer NOT NULL UNIQUE,
  label text NOT NULL,
  effective_from timestamptz NOT NULL DEFAULT now(),
  effective_to timestamptz,
  w_price integer NOT NULL DEFAULT 2500,
  w_reputation integer NOT NULL DEFAULT 2500,
  w_reliability integer NOT NULL DEFAULT 2000,
  w_distance integer NOT NULL DEFAULT 2000,
  w_freshness integer NOT NULL DEFAULT 1000,
  min_price_observations integer NOT NULL DEFAULT 3,
  min_reputation_events integer NOT NULL DEFAULT 3,
  min_fulfillment_history integer NOT NULL DEFAULT 3,
  distance_max_m integer NOT NULL DEFAULT 15000,
  freshness_half_life_days integer NOT NULL DEFAULT 14,
  notes text,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT marche_ranking_weights_nonneg CHECK (
    w_price >= 0 AND w_reputation >= 0 AND w_reliability >= 0
    AND w_distance >= 0 AND w_freshness >= 0
  ),
  CONSTRAINT marche_ranking_weights_sum CHECK (
    w_price + w_reputation + w_reliability + w_distance + w_freshness = 10000
  ),
  CONSTRAINT marche_ranking_thresholds CHECK (
    min_price_observations >= 1 AND min_reputation_events >= 1
    AND min_fulfillment_history >= 1 AND distance_max_m > 0
    AND freshness_half_life_days > 0
  ),
  CONSTRAINT marche_ranking_window CHECK (effective_to IS NULL OR effective_to > effective_from)
);

-- Ranking policy is server-sovereign: no client role may touch it directly.
REVOKE ALL ON public.marche_ranking_policies FROM PUBLIC;
REVOKE ALL ON public.marche_ranking_policies FROM anon, authenticated;
GRANT ALL ON public.marche_ranking_policies TO service_role;
ALTER TABLE public.marche_ranking_policies ENABLE ROW LEVEL SECURITY;
-- No policies on purpose: all access flows through SECURITY DEFINER RPCs.

CREATE UNIQUE INDEX IF NOT EXISTS marche_ranking_policies_one_open
  ON public.marche_ranking_policies ((effective_to IS NULL))
  WHERE effective_to IS NULL;

CREATE INDEX IF NOT EXISTS marche_ranking_policies_window
  ON public.marche_ranking_policies (effective_from DESC);

DROP TRIGGER IF EXISTS trg_marche_ranking_policies_touch ON public.marche_ranking_policies;
CREATE OR REPLACE FUNCTION public._marche_ranking_touch()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END; $$;
CREATE TRIGGER trg_marche_ranking_policies_touch
  BEFORE UPDATE ON public.marche_ranking_policies
  FOR EACH ROW EXECUTE FUNCTION public._marche_ranking_touch();

-- Seed version 1 (idempotent).
INSERT INTO public.marche_ranking_policies (version, label, notes)
SELECT 1, 'R10 baseline', 'Initial evidence-weighted recommended ordering. No paid boost.'
WHERE NOT EXISTS (SELECT 1 FROM public.marche_ranking_policies);

-- ---------------------------------------------------------------------------
-- Effective policy resolution (effective-dated, deterministic).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._marche_ranking_policy(p_at timestamptz DEFAULT now())
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT to_jsonb(p) FROM public.marche_ranking_policies p
   WHERE p.effective_from <= COALESCE(p_at, now())
     AND (p.effective_to IS NULL OR p.effective_to > COALESCE(p_at, now()))
   ORDER BY p.effective_from DESC, p.version DESC
   LIMIT 1;
$$;

-- ---------------------------------------------------------------------------
-- Canonical per-listing evidence engine.
-- Laws: missing evidence != bad evidence (NULL + reason, never a fake 0);
--       no self-benchmarking on the R8 price component;
--       R9 merchant_store reputation only (no cross-role mixing);
--       merchant rejection penalises reliability, buyer cancellation never does;
--       availability_accuracy is NOT invented (telemetry does not exist);
--       distance only with real customer + store coordinates.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._marche_rank_evidence(
  p_listing_id uuid,
  p_lat double precision DEFAULT NULL,
  p_lng double precision DEFAULT NULL,
  p_policy jsonb DEFAULT NULL,
  p_at timestamptz DEFAULT now()
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  pol jsonb := COALESCE(p_policy, public._marche_ranking_policy(p_at));
  l record; st record;
  comp jsonb := '{}'::jsonb;
  own_price numeric; own_unit text; own_variant uuid;
  n_obs int; p25 numeric; p75 numeric;
  rep_n int; rep_avg numeric;
  n_delivered int; n_rejected int; rel_total int;
  dist_m double precision;
  age_days numeric; fresh numeric;
  s numeric; wsum numeric := 0; acc numeric := 0; used int := 0; total_comp int := 5;
BEGIN
  IF pol IS NULL THEN
    RETURN jsonb_build_object('listing_id', p_listing_id, 'ranked', false,
                              'reason', 'NO_EFFECTIVE_RANKING_POLICY');
  END IF;

  SELECT ml.id, ml.store_id, ml.price_gnf, ml.created_at, ml.staple_variant_id
    INTO l FROM public.marketplace_listings ml WHERE ml.id = p_listing_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('listing_id', p_listing_id, 'ranked', false,
                              'reason', 'LISTING_NOT_FOUND');
  END IF;

  SELECT s2.id, s2.latitude, s2.longitude
    INTO st FROM public.merchant_stores s2 WHERE s2.id = l.store_id;

  ---------------------------------------------------------------- 1) PRICE (R8)
  own_variant := l.staple_variant_id;
  IF own_variant IS NULL THEN
    comp := comp || jsonb_build_object('price', jsonb_build_object(
      'available', false, 'score', NULL, 'reason', 'LISTING_NOT_MAPPED_TO_VARIANT'));
  ELSE
    SELECT o.normalized_unit_price_gnf, o.canonical_base_unit
      INTO own_price, own_unit
      FROM public.marche_procurement_price_observations o
     WHERE o.listing_id = l.id AND o.source_type = 'merchant_ask'
       AND o.comparable AND o.superseded_by IS NULL
     ORDER BY o.observed_at DESC LIMIT 1;

    IF own_price IS NULL THEN
      comp := comp || jsonb_build_object('price', jsonb_build_object(
        'available', false, 'score', NULL, 'reason', 'NO_COMPARABLE_LISTING_ASK'));
    ELSE
      -- Peer cohort: same variant/unit, EXCLUDING this listing's own observations.
      SELECT count(*),
             percentile_cont(0.25) WITHIN GROUP (ORDER BY o.normalized_unit_price_gnf),
             percentile_cont(0.75) WITHIN GROUP (ORDER BY o.normalized_unit_price_gnf)
        INTO n_obs, p25, p75
        FROM public.marche_procurement_price_observations o
       WHERE o.variant_id = own_variant
         AND o.canonical_base_unit = own_unit
         AND o.comparable AND o.superseded_by IS NULL
         AND o.source_type IN ('merchant_ask','verified_procurement')
         AND (o.listing_id IS NULL OR o.listing_id <> l.id);

      IF COALESCE(n_obs,0) < (pol->>'min_price_observations')::int THEN
        comp := comp || jsonb_build_object('price', jsonb_build_object(
          'available', false, 'score', NULL, 'sample_count', COALESCE(n_obs,0),
          'reason', 'INSUFFICIENT_PRICE_OBSERVATIONS'));
      ELSE
        IF p75 IS NULL OR p25 IS NULL OR p75 <= p25 THEN
          s := 0.5;
        ELSE
          s := GREATEST(0, LEAST(1, (p75 - own_price) / (p75 - p25)));
        END IF;
        comp := comp || jsonb_build_object('price', jsonb_build_object(
          'available', true, 'score', round(s, 6), 'sample_count', n_obs,
          'self_excluded', true, 'method', 'r8_peer_cohort_p25_p75'));
        acc := acc + s * (pol->>'w_price')::numeric;
        wsum := wsum + (pol->>'w_price')::numeric; used := used + 1;
      END IF;
    END IF;
  END IF;

  ------------------------------------------------------- 2) REPUTATION (R9 store)
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

  ------------------------------------------------- 3) MERCHANT RELIABILITY (R5)
  SELECT count(*) FILTER (WHERE o.fulfillment_state = 'delivered'),
         count(*) FILTER (WHERE o.rejected_at IS NOT NULL)
    INTO n_delivered, n_rejected
    FROM public.marche_orders o
   WHERE o.merchant_store_id = l.store_id;
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
      'buyer_cancellation_counted', false));
    acc := acc + s * (pol->>'w_reliability')::numeric;
    wsum := wsum + (pol->>'w_reliability')::numeric; used := used + 1;
  END IF;

  ----------------------------------------------------------------- 4) DISTANCE
  IF p_lat IS NULL OR p_lng IS NULL THEN
    comp := comp || jsonb_build_object('distance', jsonb_build_object(
      'available', false, 'score', NULL, 'distance_m', NULL,
      'reason', 'NO_CUSTOMER_COORDINATES'));
  ELSIF st.latitude IS NULL OR st.longitude IS NULL THEN
    comp := comp || jsonb_build_object('distance', jsonb_build_object(
      'available', false, 'score', NULL, 'distance_m', NULL,
      'reason', 'NO_STORE_COORDINATES'));
  ELSE
    dist_m := public._map_distance_meters(p_lat, p_lng, st.latitude, st.longitude);
    s := GREATEST(0, 1 - LEAST(1, dist_m / (pol->>'distance_max_m')::numeric));
    comp := comp || jsonb_build_object('distance', jsonb_build_object(
      'available', true, 'score', round(s, 6), 'distance_m', round(dist_m::numeric, 1),
      'method', 'haversine_great_circle', 'road_distance', false));
    acc := acc + s * (pol->>'w_distance')::numeric;
    wsum := wsum + (pol->>'w_distance')::numeric; used := used + 1;
  END IF;

  ---------------------------------------------------------------- 5) FRESHNESS
  age_days := GREATEST(0, EXTRACT(EPOCH FROM (COALESCE(p_at, now()) - l.created_at)) / 86400.0);
  fresh := power(0.5, age_days / (pol->>'freshness_half_life_days')::numeric);
  comp := comp || jsonb_build_object('freshness', jsonb_build_object(
    'available', true, 'score', round(fresh, 6), 'age_days', round(age_days, 3),
    'method', 'exponential_half_life'));
  acc := acc + fresh * (pol->>'w_freshness')::numeric;
  wsum := wsum + (pol->>'w_freshness')::numeric; used := used + 1;

  ------------------------------------------- availability accuracy: NOT INVENTED
  comp := comp || jsonb_build_object('availability_accuracy', jsonb_build_object(
    'available', false, 'score', NULL, 'reason', 'NOT_COLLECTED',
    'note', 'No structured stock-miss telemetry exists; component is not synthesised.'));

  RETURN jsonb_build_object(
    'listing_id', l.id,
    'store_id', l.store_id,
    'ranked', true,
    'policy_version', (pol->>'version')::int,
    'policy_id', pol->>'id',
    'components', comp,
    'components_available', used,
    'components_total', total_comp,
    'evidence_completeness', round(used::numeric / total_comp::numeric, 4),
    'cold_start', (used <= 1),
    'score', CASE WHEN wsum > 0 THEN round(acc / wsum, 6) ELSE NULL END,
    'score_bps', CASE WHEN wsum > 0 THEN round(10000 * acc / wsum)::int ELSE NULL END,
    'computed_at', COALESCE(p_at, now())
  );
END;
$$;

REVOKE ALL ON FUNCTION public._marche_ranking_policy(timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._marche_rank_evidence(uuid, double precision, double precision, jsonb, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._marche_ranking_policy(timestamptz) TO service_role;
GRANT EXECUTE ON FUNCTION public._marche_rank_evidence(uuid, double precision, double precision, jsonb, timestamptz) TO service_role;