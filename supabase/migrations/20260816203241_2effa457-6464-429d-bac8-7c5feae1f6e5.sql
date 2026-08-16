-- ============ Node 4 — Marché R3.5: Basket + Fulfillment Intelligence Foundation ============
-- OBSERVE BEFORE PREDICT. Measurement substrate only. No money, no ETA, no prediction.

-- ---------- A. immutable category snapshot on R3 order lines ----------
ALTER TABLE public.marche_order_items ADD COLUMN IF NOT EXISTS category_snapshot text;

-- ---------- B. immutable basket / fulfillment profile ----------
CREATE TABLE IF NOT EXISTS public.marche_fulfillment_profiles (
  order_id uuid PRIMARY KEY REFERENCES public.marche_orders(id) ON DELETE CASCADE,
  merchant_store_id uuid NOT NULL,
  basket_units integer NOT NULL CHECK (basket_units >= 0),
  distinct_products integer NOT NULL CHECK (distinct_products >= 0),
  product_categories text[] NOT NULL DEFAULT '{}'::text[],
  fulfillment_mode text NOT NULL DEFAULT 'unspecified'
    CHECK (fulfillment_mode IN ('unspecified','delivery','pickup')),
  fulfillment_mode_source text,
  distance_m double precision CHECK (distance_m IS NULL OR distance_m >= 0),
  distance_method text CHECK (distance_method IN ('geodesic','road','unverified')),
  distance_source text,
  origin_lat double precision,
  origin_lng double precision,
  dropoff_lat double precision,
  dropoff_lng double precision,
  weight_grams integer CHECK (weight_grams IS NULL OR weight_grams > 0),
  bulk_complexity text,
  frozen_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT marche_profile_distance_honest
    CHECK ((distance_m IS NULL AND distance_method = 'unverified')
        OR (distance_m IS NOT NULL AND distance_method IN ('geodesic','road')))
);
GRANT ALL ON public.marche_fulfillment_profiles TO service_role;
ALTER TABLE public.marche_fulfillment_profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "service only profiles" ON public.marche_fulfillment_profiles
  FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE INDEX IF NOT EXISTS idx_mfp_store ON public.marche_fulfillment_profiles(merchant_store_id);
CREATE INDEX IF NOT EXISTS idx_mfp_mode ON public.marche_fulfillment_profiles(fulfillment_mode);

-- ---------- C. append-only raw fulfillment events ----------
CREATE TABLE IF NOT EXISTS public.marche_fulfillment_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.marche_orders(id) ON DELETE CASCADE,
  event_type text NOT NULL CHECK (event_type IN (
    'ORDER_COMMITTED','MERCHANT_ACCEPTED','MERCHANT_READY','COURIER_ENGAGED',
    'COURIER_AT_STORE','SHOPPING_STARTED','SHOPPING_COMPLETED','PICKED_UP','DELIVERED')),
  occurred_at timestamptz NOT NULL,
  source_type text NOT NULL,
  source_id text,
  source_key text NOT NULL,
  actor_role text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT marche_event_unique_source UNIQUE (order_id, event_type, source_key)
);
GRANT ALL ON public.marche_fulfillment_events TO service_role;
ALTER TABLE public.marche_fulfillment_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "service only events" ON public.marche_fulfillment_events
  FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE INDEX IF NOT EXISTS idx_mfe_order ON public.marche_fulfillment_events(order_id, event_type);

-- ---------- D. derived observations ----------
CREATE TABLE IF NOT EXISTS public.marche_fulfillment_observations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.marche_orders(id) ON DELETE CASCADE,
  metric_name text NOT NULL CHECK (metric_name IN (
    'COMMIT_TO_MERCHANT_ACCEPTED','MERCHANT_ACCEPTED_TO_READY','COURIER_ENGAGED_TO_STORE_ARRIVAL',
    'SHOPPING_START_TO_COMPLETE','PICKUP_TO_DELIVERED','COMMIT_TO_DELIVERED')),
  duration_seconds bigint NOT NULL CHECK (duration_seconds >= 0),
  start_event_at timestamptz NOT NULL,
  end_event_at timestamptz NOT NULL,
  merchant_store_id uuid NOT NULL,
  fulfillment_mode text NOT NULL,
  distance_m double precision,
  distance_bucket text NOT NULL,
  basket_units integer NOT NULL,
  distinct_products integer NOT NULL,
  basket_bucket text NOT NULL,
  observed_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT marche_obs_unique UNIQUE (order_id, metric_name)
);
GRANT ALL ON public.marche_fulfillment_observations TO service_role;
ALTER TABLE public.marche_fulfillment_observations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "service only observations" ON public.marche_fulfillment_observations
  FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE INDEX IF NOT EXISTS idx_mfo_cohort ON public.marche_fulfillment_observations
  (metric_name, fulfillment_mode, distance_bucket, basket_bucket);

-- ---------- E. immutability guards ----------
CREATE OR REPLACE FUNCTION public.marche_fulfillment_profile_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF COALESCE(current_setting('marche.rpc', true),'') <> '1' THEN
    RAISE EXCEPTION 'FULFILLMENT_PROFILE_IMMUTABLE';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  IF NEW.order_id IS DISTINCT FROM OLD.order_id
     OR NEW.merchant_store_id IS DISTINCT FROM OLD.merchant_store_id
     OR NEW.basket_units IS DISTINCT FROM OLD.basket_units
     OR NEW.distinct_products IS DISTINCT FROM OLD.distinct_products
     OR NEW.product_categories IS DISTINCT FROM OLD.product_categories
     OR NEW.distance_m IS DISTINCT FROM OLD.distance_m
     OR NEW.distance_method IS DISTINCT FROM OLD.distance_method
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
     OR NEW.frozen_at IS DISTINCT FROM OLD.frozen_at THEN
    RAISE EXCEPTION 'FULFILLMENT_PROFILE_IMMUTABLE';
  END IF;
  IF NEW.fulfillment_mode IS DISTINCT FROM OLD.fulfillment_mode
     AND OLD.fulfillment_mode <> 'unspecified' THEN
    RAISE EXCEPTION 'FULFILLMENT_MODE_FROZEN';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_marche_fulfillment_profile_guard ON public.marche_fulfillment_profiles;
CREATE TRIGGER trg_marche_fulfillment_profile_guard
  BEFORE UPDATE OR DELETE ON public.marche_fulfillment_profiles
  FOR EACH ROW EXECUTE FUNCTION public.marche_fulfillment_profile_guard();

CREATE OR REPLACE FUNCTION public.marche_fulfillment_event_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF TG_OP = 'DELETE' AND COALESCE(current_setting('marche.rpc', true),'') = '1' THEN RETURN OLD; END IF;
  RAISE EXCEPTION 'FULFILLMENT_EVENT_APPEND_ONLY';
END $$;
DROP TRIGGER IF EXISTS trg_marche_fulfillment_event_guard ON public.marche_fulfillment_events;
CREATE TRIGGER trg_marche_fulfillment_event_guard
  BEFORE UPDATE OR DELETE ON public.marche_fulfillment_events
  FOR EACH ROW EXECUTE FUNCTION public.marche_fulfillment_event_guard();

CREATE OR REPLACE FUNCTION public.marche_fulfillment_observation_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF COALESCE(current_setting('marche.rpc', true),'') = '1' THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'FULFILLMENT_OBSERVATION_DERIVED_ONLY';
END $$;
DROP TRIGGER IF EXISTS trg_marche_fulfillment_observation_guard ON public.marche_fulfillment_observations;
CREATE TRIGGER trg_marche_fulfillment_observation_guard
  BEFORE UPDATE OR DELETE ON public.marche_fulfillment_observations
  FOR EACH ROW EXECUTE FUNCTION public.marche_fulfillment_observation_guard();

-- ---------- F. centralized cohort bucket + confidence helpers ----------
CREATE OR REPLACE FUNCTION public.marche_distance_bucket(p_distance_m double precision)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN p_distance_m IS NULL THEN 'unknown'
    WHEN p_distance_m < 1000 THEN '0-1km'
    WHEN p_distance_m < 3000 THEN '1-3km'
    WHEN p_distance_m < 7000 THEN '3-7km'
    WHEN p_distance_m < 15000 THEN '7-15km'
    ELSE '15km+' END
$$;

CREATE OR REPLACE FUNCTION public.marche_basket_bucket(p_units integer, p_distinct integer)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN COALESCE(p_units,0) <= 0 THEN 'empty'
    WHEN COALESCE(p_units,0) <= 1 AND COALESCE(p_distinct,0) <= 1 THEN 'single'
    WHEN COALESCE(p_units,0) <= 5 THEN 'small'
    WHEN COALESCE(p_units,0) <= 15 THEN 'medium'
    ELSE 'large' END
$$;

CREATE OR REPLACE FUNCTION public.marche_fulfillment_freshness(p_latest timestamptz)
RETURNS text LANGUAGE sql STABLE SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN p_latest IS NULL THEN 'none'
    WHEN now() - p_latest <= interval '7 days' THEN 'fresh'
    WHEN now() - p_latest <= interval '30 days' THEN 'aging'
    ELSE 'stale' END
$$;

-- Deterministic + transparent: sample count first, then freshness. Never fake precision.
CREATE OR REPLACE FUNCTION public.marche_fulfillment_confidence(p_sample_count integer, p_latest timestamptz)
RETURNS text LANGUAGE sql STABLE SET search_path TO 'public' AS $$
  SELECT CASE
    WHEN COALESCE(p_sample_count,0) < 10 THEN 'insufficient'
    WHEN public.marche_fulfillment_freshness(p_latest) = 'stale' THEN 'low'
    WHEN p_sample_count < 30 THEN 'medium'
    WHEN public.marche_fulfillment_freshness(p_latest) = 'aging' THEN 'medium'
    ELSE 'high' END
$$;

-- ---------- G. profile creation (server-derived, internal) ----------
CREATE OR REPLACE FUNCTION public.marche_fulfillment_profile_create(p_order_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  o public.marche_orders;
  v_units int; v_distinct int; v_cats text[];
  v_olat double precision; v_olng double precision;
  v_dist double precision; v_method text; v_source text;
BEGIN
  SELECT * INTO o FROM public.marche_orders WHERE id = p_order_id;
  IF o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  IF EXISTS (SELECT 1 FROM public.marche_fulfillment_profiles WHERE order_id = o.id) THEN
    RETURN o.id;
  END IF;

  SELECT COALESCE(sum(qty),0), count(DISTINCT listing_id)
    INTO v_units, v_distinct
    FROM public.marche_order_items WHERE order_id = o.id;

  SELECT COALESCE(array_agg(DISTINCT c ORDER BY c), '{}'::text[]) INTO v_cats
    FROM (SELECT NULLIF(btrim(lower(category_snapshot)),'') AS c
            FROM public.marche_order_items WHERE order_id = o.id) s
   WHERE c IS NOT NULL;

  SELECT latitude, longitude INTO v_olat, v_olng
    FROM public.merchant_stores WHERE id = o.merchant_store_id;

  IF v_olat IS NOT NULL AND v_olng IS NOT NULL AND o.dropoff_lat IS NOT NULL AND o.dropoff_lng IS NOT NULL THEN
    v_dist := public._map_distance_meters(v_olat, v_olng, o.dropoff_lat, o.dropoff_lng);
    v_method := 'geodesic';
    v_source := 'store_coords+order_dropoff';
  ELSE
    v_dist := NULL; v_method := 'unverified'; v_source := NULL;
  END IF;

  INSERT INTO public.marche_fulfillment_profiles(
    order_id, merchant_store_id, basket_units, distinct_products, product_categories,
    fulfillment_mode, fulfillment_mode_source, distance_m, distance_method, distance_source,
    origin_lat, origin_lng, dropoff_lat, dropoff_lng, frozen_at)
  VALUES (o.id, o.merchant_store_id, v_units, v_distinct, v_cats,
    'unspecified', 'no_authoritative_dispatch_decision', v_dist, v_method, v_source,
    v_olat, v_olng, o.dropoff_lat, o.dropoff_lng, o.created_at)
  ON CONFLICT (order_id) DO NOTHING;

  RETURN o.id;
END $$;

-- one-way mode declaration, reserved for a future certified lifecycle transition
CREATE OR REPLACE FUNCTION public.marche_fulfillment_set_mode(p_order_id uuid, p_mode text, p_source text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_cur text;
BEGIN
  IF p_mode NOT IN ('delivery','pickup') THEN RAISE EXCEPTION 'INVALID_FULFILLMENT_MODE'; END IF;
  SELECT fulfillment_mode INTO v_cur FROM public.marche_fulfillment_profiles WHERE order_id = p_order_id;
  IF v_cur IS NULL THEN RAISE EXCEPTION 'PROFILE_NOT_FOUND'; END IF;
  IF v_cur <> 'unspecified' THEN
    IF v_cur = p_mode THEN RETURN; END IF;
    RAISE EXCEPTION 'FULFILLMENT_MODE_FROZEN';
  END IF;
  PERFORM set_config('marche.rpc','1', true);
  UPDATE public.marche_fulfillment_profiles
     SET fulfillment_mode = p_mode, fulfillment_mode_source = COALESCE(NULLIF(btrim(p_source),''),'server')
   WHERE order_id = p_order_id;
  PERFORM set_config('marche.rpc','', true);
END $$;

-- ---------- H. derived observation recomputation ----------
CREATE OR REPLACE FUNCTION public.marche_fulfillment_recompute_observations(p_order_id uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  p public.marche_fulfillment_profiles;
  m record; v_start timestamptz; v_end timestamptz; v_n int := 0;
BEGIN
  SELECT * INTO p FROM public.marche_fulfillment_profiles WHERE order_id = p_order_id;
  IF p.order_id IS NULL THEN RETURN 0; END IF;

  FOR m IN
    SELECT * FROM (VALUES
      ('COMMIT_TO_MERCHANT_ACCEPTED','ORDER_COMMITTED','MERCHANT_ACCEPTED'),
      ('MERCHANT_ACCEPTED_TO_READY','MERCHANT_ACCEPTED','MERCHANT_READY'),
      ('COURIER_ENGAGED_TO_STORE_ARRIVAL','COURIER_ENGAGED','COURIER_AT_STORE'),
      ('SHOPPING_START_TO_COMPLETE','SHOPPING_STARTED','SHOPPING_COMPLETED'),
      ('PICKUP_TO_DELIVERED','PICKED_UP','DELIVERED'),
      ('COMMIT_TO_DELIVERED','ORDER_COMMITTED','DELIVERED')
    ) AS v(metric, s_evt, e_evt)
  LOOP
    SELECT min(occurred_at) INTO v_start FROM public.marche_fulfillment_events
      WHERE order_id = p_order_id AND event_type = m.s_evt;
    SELECT min(occurred_at) INTO v_end FROM public.marche_fulfillment_events
      WHERE order_id = p_order_id AND event_type = m.e_evt;
    -- both endpoints required; impossible negative intervals are refused, never clamped
    CONTINUE WHEN v_start IS NULL OR v_end IS NULL OR v_end < v_start;

    PERFORM set_config('marche.rpc','1', true);
    INSERT INTO public.marche_fulfillment_observations(
      order_id, metric_name, duration_seconds, start_event_at, end_event_at,
      merchant_store_id, fulfillment_mode, distance_m, distance_bucket,
      basket_units, distinct_products, basket_bucket, observed_at)
    VALUES (p_order_id, m.metric, floor(EXTRACT(EPOCH FROM (v_end - v_start)))::bigint, v_start, v_end,
      p.merchant_store_id, p.fulfillment_mode, p.distance_m, public.marche_distance_bucket(p.distance_m),
      p.basket_units, p.distinct_products, public.marche_basket_bucket(p.basket_units, p.distinct_products),
      v_end)
    ON CONFLICT (order_id, metric_name) DO NOTHING;
    PERFORM set_config('marche.rpc','', true);
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END $$;

-- ---------- I. internal append (idempotent, provenance-bearing) ----------
CREATE OR REPLACE FUNCTION public.marche_fulfillment_event_append(
  p_order_id uuid, p_event_type text, p_occurred_at timestamptz,
  p_source_type text, p_source_id text DEFAULT NULL,
  p_source_key text DEFAULT NULL, p_actor_role text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_id uuid; v_key text;
BEGIN
  IF p_order_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.marche_orders WHERE id = p_order_id) THEN
    RAISE EXCEPTION 'ORDER_NOT_FOUND';
  END IF;
  IF NULLIF(btrim(COALESCE(p_source_type,'')),'') IS NULL THEN RAISE EXCEPTION 'SOURCE_REQUIRED'; END IF;
  IF p_occurred_at IS NULL THEN RAISE EXCEPTION 'OCCURRED_AT_REQUIRED'; END IF;
  v_key := COALESCE(NULLIF(btrim(COALESCE(p_source_key,'')),''), p_source_type || ':' || COALESCE(p_source_id,'default'));

  INSERT INTO public.marche_fulfillment_events(order_id, event_type, occurred_at, source_type, source_id, source_key, actor_role)
  VALUES (p_order_id, p_event_type, p_occurred_at, p_source_type, p_source_id, v_key, p_actor_role)
  ON CONFLICT (order_id, event_type, source_key) DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    SELECT id INTO v_id FROM public.marche_fulfillment_events
     WHERE order_id = p_order_id AND event_type = p_event_type AND source_key = v_key;
  END IF;

  PERFORM public.marche_fulfillment_recompute_observations(p_order_id);
  RETURN v_id;
END $$;

-- ---------- J. cohort statistics (descriptive only) ----------
CREATE OR REPLACE FUNCTION public.marche_fulfillment_cohort_stats(
  p_metric_name text DEFAULT NULL,
  p_fulfillment_mode text DEFAULT NULL,
  p_distance_bucket text DEFAULT NULL,
  p_basket_bucket text DEFAULT NULL,
  p_include_unspecified_mode boolean DEFAULT false)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT COALESCE(jsonb_agg(x ORDER BY x->>'metric_name', x->>'fulfillment_mode',
                            x->>'distance_bucket', x->>'basket_bucket'), '[]'::jsonb)
  FROM (
    SELECT jsonb_build_object(
      'metric_name', o.metric_name,
      'fulfillment_mode', o.fulfillment_mode,
      'distance_bucket', o.distance_bucket,
      'basket_bucket', o.basket_bucket,
      'sample_count', count(*)::int,
      'p50_seconds', percentile_cont(0.5) WITHIN GROUP (ORDER BY o.duration_seconds),
      'p75_seconds', percentile_cont(0.75) WITHIN GROUP (ORDER BY o.duration_seconds),
      'p90_seconds', percentile_cont(0.90) WITHIN GROUP (ORDER BY o.duration_seconds),
      'min_duration_seconds', min(o.duration_seconds),
      'max_duration_seconds', max(o.duration_seconds),
      'first_observed_at', min(o.observed_at),
      'latest_observed_at', max(o.observed_at),
      'freshness', public.marche_fulfillment_freshness(max(o.observed_at)),
      'confidence', public.marche_fulfillment_confidence(count(*)::int, max(o.observed_at)),
      'insufficient_data', (count(*) < 10)
    ) AS x
    FROM public.marche_fulfillment_observations o
    WHERE (p_metric_name IS NULL OR o.metric_name = p_metric_name)
      AND (p_fulfillment_mode IS NULL OR o.fulfillment_mode = p_fulfillment_mode)
      AND (p_distance_bucket IS NULL OR o.distance_bucket = p_distance_bucket)
      AND (p_basket_bucket IS NULL OR o.basket_bucket = p_basket_bucket)
      -- unknown mode is excluded from cohort output rather than pretending
      AND (p_include_unspecified_mode OR o.fulfillment_mode <> 'unspecified')
    GROUP BY o.metric_name, o.fulfillment_mode, o.distance_bucket, o.basket_bucket
  ) s
$$;

-- ---------- K. admin/ops sanitized reads ----------
CREATE OR REPLACE FUNCTION public.marche_fulfillment_profile_admin(p_order_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_any_admin(auth.uid()) THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  SELECT to_jsonb(p) INTO v FROM public.marche_fulfillment_profiles p WHERE p.order_id = p_order_id;
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION public.marche_fulfillment_events_admin(p_order_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_any_admin(auth.uid()) THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  SELECT COALESCE(jsonb_agg(to_jsonb(e) ORDER BY e.occurred_at), '[]'::jsonb) INTO v
    FROM public.marche_fulfillment_events e WHERE e.order_id = p_order_id;
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION public.marche_fulfillment_observations_admin(
  p_metric_name text DEFAULT NULL, p_limit integer DEFAULT 200)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_any_admin(auth.uid()) THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  SELECT COALESCE(jsonb_agg(to_jsonb(o) ORDER BY o.observed_at DESC), '[]'::jsonb) INTO v
    FROM (SELECT * FROM public.marche_fulfillment_observations
           WHERE (p_metric_name IS NULL OR metric_name = p_metric_name)
           ORDER BY observed_at DESC LIMIT LEAST(GREATEST(COALESCE(p_limit,200),1),1000)) o;
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION public.marche_fulfillment_cohorts_admin(
  p_metric_name text DEFAULT NULL, p_fulfillment_mode text DEFAULT NULL,
  p_distance_bucket text DEFAULT NULL, p_basket_bucket text DEFAULT NULL,
  p_include_unspecified_mode boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_any_admin(auth.uid()) THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;
  RETURN public.marche_fulfillment_cohort_stats(p_metric_name, p_fulfillment_mode,
           p_distance_bucket, p_basket_bucket, p_include_unspecified_mode);
END $$;

-- ---------- L. ACLs: no anon; internal writers are service_role only ----------
REVOKE ALL ON FUNCTION public.marche_fulfillment_profile_create(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.marche_fulfillment_event_append(uuid,text,timestamptz,text,text,text,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.marche_fulfillment_recompute_observations(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.marche_fulfillment_set_mode(uuid,text,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.marche_fulfillment_cohort_stats(text,text,text,text,boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.marche_fulfillment_profile_create(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.marche_fulfillment_event_append(uuid,text,timestamptz,text,text,text,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.marche_fulfillment_recompute_observations(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.marche_fulfillment_set_mode(uuid,text,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.marche_fulfillment_cohort_stats(text,text,text,text,boolean) TO service_role;

REVOKE ALL ON FUNCTION public.marche_fulfillment_profile_admin(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_fulfillment_events_admin(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_fulfillment_observations_admin(text,integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_fulfillment_cohorts_admin(text,text,text,text,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_fulfillment_profile_admin(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.marche_fulfillment_events_admin(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.marche_fulfillment_observations_admin(text,integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.marche_fulfillment_cohorts_admin(text,text,text,text,boolean) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.marche_distance_bucket(double precision) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_basket_bucket(integer,integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_fulfillment_freshness(timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_fulfillment_confidence(integer,timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_distance_bucket(double precision) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.marche_basket_bucket(integer,integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.marche_fulfillment_freshness(timestamptz) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.marche_fulfillment_confidence(integer,timestamptz) TO authenticated, service_role;
