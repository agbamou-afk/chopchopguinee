ALTER TABLE public.marketplace_listings
  ADD COLUMN IF NOT EXISTS staple_variant_id uuid REFERENCES public.marche_staple_variants(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS staple_purchase_option_id uuid REFERENCES public.marche_staple_purchase_options(id) ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION public._marche_listing_staple_map_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_variant uuid;
BEGIN
  IF NEW.staple_purchase_option_id IS NOT NULL THEN
    SELECT variant_id INTO v_variant FROM public.marche_staple_purchase_options
     WHERE id = NEW.staple_purchase_option_id AND is_active;
    IF v_variant IS NULL THEN RAISE EXCEPTION 'STAPLE_OPTION_INVALID'; END IF;
    IF NEW.staple_variant_id IS NULL THEN NEW.staple_variant_id := v_variant; END IF;
    IF NEW.staple_variant_id IS DISTINCT FROM v_variant THEN
      RAISE EXCEPTION 'STAPLE_MAPPING_INCOHERENT';
    END IF;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_marche_listing_staple_map ON public.marketplace_listings;
CREATE TRIGGER trg_marche_listing_staple_map
  BEFORE INSERT OR UPDATE ON public.marketplace_listings
  FOR EACH ROW EXECUTE FUNCTION public._marche_listing_staple_map_guard();

DROP TRIGGER IF EXISTS trg_mppo_append_only ON public.marche_procurement_price_observations;

ALTER TABLE public.marche_procurement_price_observations
  ADD COLUMN IF NOT EXISTS source_type text NOT NULL DEFAULT 'survey',
  ADD COLUMN IF NOT EXISTS store_id uuid REFERENCES public.merchant_stores(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS listing_id uuid REFERENCES public.marketplace_listings(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS zone_commune text,
  ADD COLUMN IF NOT EXISTS zone_label text,
  ADD COLUMN IF NOT EXISTS normalization_kind text,
  ADD COLUMN IF NOT EXISTS canonical_base_unit text,
  ADD COLUMN IF NOT EXISTS normalized_quantity numeric,
  ADD COLUMN IF NOT EXISTS normalized_unit_price_gnf bigint,
  ADD COLUMN IF NOT EXISTS raw_amount_gnf bigint,
  ADD COLUMN IF NOT EXISTS raw_quantity numeric,
  ADD COLUMN IF NOT EXISTS raw_unit text,
  ADD COLUMN IF NOT EXISTS comparable boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS cohort_key text,
  ADD COLUMN IF NOT EXISTS superseded_by uuid REFERENCES public.marche_procurement_price_observations(id),
  ADD COLUMN IF NOT EXISTS superseded_reason text,
  ADD COLUMN IF NOT EXISTS ingested_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.marche_procurement_price_observations DROP CONSTRAINT IF EXISTS mppo_source_chk;
ALTER TABLE public.marche_procurement_price_observations
  ADD CONSTRAINT mppo_source_chk CHECK (source_kind = ANY (ARRAY['field_agent','shopper_receipt','ops_survey','merchant_ask']));
ALTER TABLE public.marche_procurement_price_observations DROP CONSTRAINT IF EXISTS mppo_source_type_chk;
ALTER TABLE public.marche_procurement_price_observations
  ADD CONSTRAINT mppo_source_type_chk CHECK (source_type = ANY (ARRAY['merchant_ask','verified_procurement','survey']));
ALTER TABLE public.marche_procurement_price_observations DROP CONSTRAINT IF EXISTS mppo_norm_kind_chk;
ALTER TABLE public.marche_procurement_price_observations
  ADD CONSTRAINT mppo_norm_kind_chk CHECK (normalization_kind IS NULL OR normalization_kind = ANY (ARRAY['exact','unit_native','non_comparable']));

UPDATE public.marche_procurement_price_observations o
   SET source_type = CASE WHEN o.source_kind = 'shopper_receipt' THEN 'verified_procurement' ELSE 'survey' END,
       raw_amount_gnf = COALESCE(o.raw_amount_gnf, o.observed_unit_price_gnf),
       raw_quantity = COALESCE(o.raw_quantity, 1),
       zone_commune = COALESCE(o.zone_commune, (SELECT m.commune FROM public.physical_markets m WHERE m.id = o.market_id)),
       normalization_kind = COALESCE(o.normalization_kind, po.normalization_kind),
       raw_unit = COALESCE(o.raw_unit, po.sale_unit),
       canonical_base_unit = COALESCE(o.canonical_base_unit,
         CASE WHEN po.normalization_kind = 'exact' THEN po.canonical_base_unit
              WHEN po.normalization_kind = 'unit_native' THEN 'unit:' || po.sale_unit END),
       normalized_quantity = COALESCE(o.normalized_quantity,
         CASE WHEN po.normalization_kind = 'exact' THEN po.canonical_quantity
              WHEN po.normalization_kind = 'unit_native' THEN 1 END),
       normalized_unit_price_gnf = COALESCE(o.normalized_unit_price_gnf,
         CASE WHEN po.normalization_kind = 'exact' AND COALESCE(po.canonical_quantity,0) > 0
                THEN floor(o.observed_unit_price_gnf::numeric / po.canonical_quantity)::bigint
              WHEN po.normalization_kind = 'unit_native' THEN o.observed_unit_price_gnf END),
       comparable = (po.normalization_kind IN ('exact','unit_native'))
  FROM public.marche_staple_purchase_options po
 WHERE po.id = o.purchase_option_id;

UPDATE public.marche_procurement_price_observations
   SET cohort_key = variant_id::text || '|' || COALESCE(canonical_base_unit,'none') || '|' || COALESCE(zone_commune,'unknown')
 WHERE cohort_key IS NULL;

DO $$
BEGIN
  PERFORM set_config('marche.procurement_purge','on', true);
  DELETE FROM public.marche_procurement_price_observations a
   USING public.marche_procurement_price_observations b
   WHERE a.source_ref IS NOT NULL AND a.source_ref = b.source_ref
     AND a.source_kind = b.source_kind AND a.ctid > b.ctid;
  PERFORM set_config('marche.procurement_purge','', true);
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS mppo_source_identity_uq
  ON public.marche_procurement_price_observations (source_kind, source_ref)
  WHERE source_ref IS NOT NULL;
CREATE INDEX IF NOT EXISTS mppo_cohort_idx
  ON public.marche_procurement_price_observations (variant_id, canonical_base_unit, observed_at DESC)
  WHERE comparable AND superseded_by IS NULL;

CREATE OR REPLACE FUNCTION public._marche_price_observation_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF COALESCE(current_setting('marche.procurement_purge', true),'') = 'on' THEN RETURN OLD; END IF;
    RAISE EXCEPTION 'PROCUREMENT_APPEND_ONLY';
  END IF;
  IF COALESCE(current_setting('marche.price_supersede', true),'') = 'on'
     AND OLD.superseded_by IS NULL
     AND (to_jsonb(NEW) - 'superseded_by' - 'superseded_reason')
       = (to_jsonb(OLD) - 'superseded_by' - 'superseded_reason') THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'PROCUREMENT_APPEND_ONLY';
END $$;

CREATE TRIGGER trg_mppo_append_only
  BEFORE UPDATE OR DELETE ON public.marche_procurement_price_observations
  FOR EACH ROW EXECUTE FUNCTION public._marche_price_observation_guard();

CREATE OR REPLACE FUNCTION public._marche_price_normalize(
  p_option_id uuid, p_amount_gnf bigint, p_quantity numeric)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE o public.marche_staple_purchase_options; q numeric; unit text;
BEGIN
  SELECT * INTO o FROM public.marche_staple_purchase_options WHERE id = p_option_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('comparable', false, 'normalization_kind', 'non_comparable');
  END IF;
  IF p_amount_gnf IS NULL OR p_amount_gnf <= 0 OR COALESCE(p_quantity, 0) <= 0 THEN
    RETURN jsonb_build_object('comparable', false, 'normalization_kind', o.normalization_kind,
                              'raw_unit', o.sale_unit);
  END IF;
  IF o.normalization_kind = 'exact' AND o.canonical_base_unit IS NOT NULL
     AND COALESCE(o.canonical_quantity, 0) > 0 THEN
    q := p_quantity * o.canonical_quantity; unit := o.canonical_base_unit;
  ELSIF o.normalization_kind = 'unit_native' THEN
    q := p_quantity; unit := 'unit:' || o.sale_unit;
  ELSE
    RETURN jsonb_build_object('comparable', false, 'normalization_kind', 'non_comparable',
                              'raw_unit', o.sale_unit);
  END IF;
  RETURN jsonb_build_object(
    'comparable', true,
    'normalization_kind', o.normalization_kind,
    'canonical_base_unit', unit,
    'normalized_quantity', q,
    'normalized_unit_price_gnf', floor(p_amount_gnf::numeric / q)::bigint,
    'raw_unit', o.sale_unit);
END $$;

CREATE OR REPLACE FUNCTION public._marche_price_record(
  p_option_id uuid, p_source_type text, p_source_kind text, p_source_ref text,
  p_amount_gnf bigint, p_quantity numeric, p_observed_at timestamptz,
  p_market_id uuid DEFAULT NULL, p_store_id uuid DEFAULT NULL, p_listing_id uuid DEFAULT NULL,
  p_zone_commune text DEFAULT NULL, p_zone_label text DEFAULT NULL, p_recorded_by uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n jsonb; v_variant uuid; v_com uuid; v_unit_price bigint; v_id uuid;
BEGIN
  SELECT po.variant_id, v.commodity_id INTO v_variant, v_com
    FROM public.marche_staple_purchase_options po
    JOIN public.marche_staple_variants v ON v.id = po.variant_id
   WHERE po.id = p_option_id;
  IF v_variant IS NULL THEN RETURN NULL; END IF;
  IF p_amount_gnf IS NULL OR p_amount_gnf <= 0 OR COALESCE(p_quantity, 0) <= 0 THEN RETURN NULL; END IF;

  n := public._marche_price_normalize(p_option_id, p_amount_gnf, p_quantity);
  v_unit_price := COALESCE((n->>'normalized_unit_price_gnf')::bigint,
                           floor(p_amount_gnf::numeric / p_quantity)::bigint);
  IF v_unit_price <= 0 THEN RETURN NULL; END IF;

  INSERT INTO public.marche_procurement_price_observations (
    purchase_option_id, variant_id, commodity_id, market_id, observed_unit_price_gnf,
    observed_at, source_kind, source_ref, recorded_by, source_type, store_id, listing_id,
    zone_commune, zone_label, normalization_kind, canonical_base_unit, normalized_quantity,
    normalized_unit_price_gnf, raw_amount_gnf, raw_quantity, raw_unit, comparable, cohort_key)
  VALUES (
    p_option_id, v_variant, v_com, p_market_id, v_unit_price,
    COALESCE(p_observed_at, now()), p_source_kind, p_source_ref, p_recorded_by, p_source_type,
    p_store_id, p_listing_id, p_zone_commune, p_zone_label,
    n->>'normalization_kind', n->>'canonical_base_unit', (n->>'normalized_quantity')::numeric,
    (n->>'normalized_unit_price_gnf')::bigint, p_amount_gnf, p_quantity, n->>'raw_unit',
    COALESCE((n->>'comparable')::boolean, false),
    v_variant::text || '|' || COALESCE(n->>'canonical_base_unit','none') || '|' || COALESCE(p_zone_commune,'unknown'))
  ON CONFLICT (source_kind, source_ref) WHERE source_ref IS NOT NULL DO NOTHING
  RETURNING id INTO v_id;

  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION public.marche_price_ingest_merchant_ask(p_listing_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE l public.marketplace_listings; s public.merchant_stores; v_price bigint; v_id uuid; v_ref text;
BEGIN
  SELECT * INTO l FROM public.marketplace_listings WHERE id = p_listing_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ingested', false, 'reason', 'LISTING_NOT_FOUND'); END IF;
  IF l.kind <> 'merchant'::listing_kind OR l.store_id IS NULL THEN
    RETURN jsonb_build_object('ingested', false, 'reason', 'MERCHANT_STORE_REQUIRED');
  END IF;
  IF l.visibility <> 'public' OR l.status <> 'active'::listing_status THEN
    RETURN jsonb_build_object('ingested', false, 'reason', 'MERCHANT_ASK_NOT_PUBLISHED');
  END IF;
  SELECT * INTO s FROM public.merchant_stores WHERE id = l.store_id;
  IF s.onboarding_status IS DISTINCT FROM 'approved' OR COALESCE(s.status,'') <> 'active' THEN
    RETURN jsonb_build_object('ingested', false, 'reason', 'STORE_NOT_APPROVED');
  END IF;
  IF l.staple_purchase_option_id IS NULL THEN
    RETURN jsonb_build_object('ingested', false, 'reason', 'MERCHANT_ASK_NOT_CANONICAL');
  END IF;
  v_price := COALESCE(l.asking_price_gnf, l.price_gnf);
  IF COALESCE(v_price, 0) <= 0 THEN
    RETURN jsonb_build_object('ingested', false, 'reason', 'MERCHANT_ASK_NO_PRICE');
  END IF;

  v_ref := 'listing:' || l.id::text || ':' || v_price::text;
  v_id := public._marche_price_record(
    l.staple_purchase_option_id, 'merchant_ask', 'merchant_ask', v_ref,
    v_price, 1, now(), NULL, l.store_id, l.id,
    COALESCE(s.commune, l.commune), COALESCE(s.market_name, s.district), NULL);

  RETURN jsonb_build_object('ingested', v_id IS NOT NULL, 'observation_id', v_id,
                            'reason', CASE WHEN v_id IS NULL THEN 'ALREADY_OBSERVED' ELSE NULL END);
END $$;

CREATE OR REPLACE FUNCTION public._marche_price_listing_ask_trg()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  BEGIN
    PERFORM public.marche_price_ingest_merchant_ask(NEW.id);
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_marche_price_merchant_ask ON public.marketplace_listings;
CREATE TRIGGER trg_marche_price_merchant_ask
  AFTER INSERT OR UPDATE ON public.marketplace_listings
  FOR EACH ROW EXECUTE FUNCTION public._marche_price_listing_ask_trg();

CREATE OR REPLACE FUNCTION public._marche_price_policy()
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT jsonb_build_object(
    'min_samples', 5, 'high_samples', 12,
    'fresh_hours', 72, 'aging_hours', 168, 'stale_hours', 336,
    'window_hours', 336)
$$;

CREATE OR REPLACE FUNCTION public.marche_price_freshness(p_latest timestamptz)
RETURNS text LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT CASE
    WHEN p_latest IS NULL THEN 'none'
    WHEN p_latest >= now() - interval '72 hours' THEN 'fresh'
    WHEN p_latest >= now() - interval '168 hours' THEN 'aging'
    ELSE 'stale' END
$$;

CREATE OR REPLACE FUNCTION public.marche_price_confidence(p_sample_count integer, p_latest timestamptz)
RETURNS text LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT CASE
    WHEN COALESCE(p_sample_count,0) < 5 THEN 'insufficient'
    WHEN public.marche_price_freshness(p_latest) = 'stale' THEN 'low'
    WHEN p_sample_count < 12 THEN 'medium'
    WHEN public.marche_price_freshness(p_latest) = 'aging' THEN 'medium'
    ELSE 'high' END
$$;

CREATE OR REPLACE FUNCTION public._marche_price_cohort(
  p_variant_id uuid, p_base_unit text, p_zone text DEFAULT NULL,
  p_window_hours integer DEFAULT NULL, p_source_type text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  pol jsonb := public._marche_price_policy();
  win interval; n int; p25 numeric; p50 numeric; p75 numeric;
  lo bigint; hi bigint; first_at timestamptz; last_at timestamptz;
  n_ask int; n_proc int; n_srv int;
  cur numeric; prev numeric; n_prev int; mv jsonb := NULL;
BEGIN
  win := ((COALESCE(p_window_hours, (pol->>'window_hours')::int))::text || ' hours')::interval;

  WITH src AS (
    SELECT o.* FROM public.marche_procurement_price_observations o
     WHERE o.variant_id = p_variant_id
       AND o.comparable AND o.superseded_by IS NULL
       AND o.canonical_base_unit = p_base_unit
       AND (p_zone IS NULL OR COALESCE(o.zone_commune,'unknown') = p_zone)
       AND (p_source_type IS NULL OR o.source_type = p_source_type)
       AND o.source_type IN ('merchant_ask','verified_procurement')
       AND o.observed_at >= now() - win
  )
  SELECT count(*),
         percentile_cont(0.25) WITHIN GROUP (ORDER BY normalized_unit_price_gnf),
         percentile_cont(0.50) WITHIN GROUP (ORDER BY normalized_unit_price_gnf),
         percentile_cont(0.75) WITHIN GROUP (ORDER BY normalized_unit_price_gnf),
         min(normalized_unit_price_gnf), max(normalized_unit_price_gnf),
         min(observed_at), max(observed_at),
         count(*) FILTER (WHERE source_type='merchant_ask'),
         count(*) FILTER (WHERE source_type='verified_procurement'),
         count(*) FILTER (WHERE source_type='survey')
    INTO n, p25, p50, p75, lo, hi, first_at, last_at, n_ask, n_proc, n_srv
    FROM src;

  IF COALESCE(n,0) < (pol->>'min_samples')::int THEN
    RETURN jsonb_build_object(
      'variant_id', p_variant_id, 'canonical_base_unit', p_base_unit,
      'zone', COALESCE(p_zone,'all'), 'sample_count', COALESCE(n,0),
      'insufficient_data', true, 'confidence', 'insufficient',
      'freshness', public.marche_price_freshness(last_at),
      'reason', 'INSUFFICIENT_OBSERVATIONS', 'min_samples', (pol->>'min_samples')::int,
      'source_mix', jsonb_build_object('merchant_ask', COALESCE(n_ask,0),
                                       'verified_procurement', COALESCE(n_proc,0)));
  END IF;

  SELECT count(*), percentile_cont(0.5) WITHIN GROUP (ORDER BY normalized_unit_price_gnf)
    INTO n_prev, prev
    FROM public.marche_procurement_price_observations
   WHERE variant_id = p_variant_id AND comparable AND superseded_by IS NULL
     AND canonical_base_unit = p_base_unit
     AND (p_zone IS NULL OR COALESCE(zone_commune,'unknown') = p_zone)
     AND source_type IN ('merchant_ask','verified_procurement')
     AND observed_at < now() - (win / 2) AND observed_at >= now() - win;
  SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY normalized_unit_price_gnf)
    INTO cur
    FROM public.marche_procurement_price_observations
   WHERE variant_id = p_variant_id AND comparable AND superseded_by IS NULL
     AND canonical_base_unit = p_base_unit
     AND (p_zone IS NULL OR COALESCE(zone_commune,'unknown') = p_zone)
     AND source_type IN ('merchant_ask','verified_procurement')
     AND observed_at >= now() - (win / 2);
  IF n_prev >= (pol->>'min_samples')::int AND (n - n_prev) >= (pol->>'min_samples')::int
     AND prev IS NOT NULL AND cur IS NOT NULL AND prev > 0 THEN
    mv := jsonb_build_object('comparable', true,
      'previous_median_gnf', floor(prev)::bigint,
      'current_median_gnf', floor(cur)::bigint,
      'delta_gnf', floor(cur)::bigint - floor(prev)::bigint,
      'delta_pct', round(((cur - prev) / prev) * 100, 2));
  ELSE
    mv := jsonb_build_object('comparable', false, 'reason', 'INSUFFICIENT_COMPARISON_WINDOW');
  END IF;

  RETURN jsonb_build_object(
    'variant_id', p_variant_id, 'canonical_base_unit', p_base_unit,
    'zone', COALESCE(p_zone,'all'), 'sample_count', n,
    'p25_gnf', floor(p25)::bigint, 'median_gnf', floor(p50)::bigint, 'p75_gnf', floor(p75)::bigint,
    'min_gnf', lo, 'max_gnf', hi,
    'first_observed_at', first_at, 'latest_observed_at', last_at,
    'freshness', public.marche_price_freshness(last_at),
    'confidence', public.marche_price_confidence(n, last_at),
    'insufficient_data', false,
    'window_hours', COALESCE(p_window_hours, (pol->>'window_hours')::int),
    'source_mix', jsonb_build_object('merchant_ask', n_ask, 'verified_procurement', n_proc),
    'movement', mv);
END $$;

CREATE OR REPLACE FUNCTION public.marche_price_cohort_stats(
  p_variant_id uuid, p_base_unit text, p_zone text DEFAULT NULL,
  p_window_hours integer DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public._marche_price_cohort(p_variant_id, p_base_unit, p_zone, p_window_hours, NULL)
$$;

CREATE OR REPLACE FUNCTION public.marche_price_observed_public(
  p_commodity_code text, p_zone text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_com uuid; out_rows jsonb := '[]'::jsonb; rec record;
BEGIN
  SELECT id INTO v_com FROM public.marche_staple_commodities
   WHERE code = p_commodity_code AND is_active;
  IF v_com IS NULL THEN
    RETURN jsonb_build_object('commodity_code', p_commodity_code, 'cohorts', out_rows,
                              'doctrine', 'Prix observé sur ChopChop');
  END IF;
  FOR rec IN
    SELECT DISTINCT v.id AS variant_id, v.code AS variant_code, v.name_fr,
           o.canonical_base_unit
      FROM public.marche_staple_variants v
      JOIN public.marche_procurement_price_observations o ON o.variant_id = v.id
     WHERE v.commodity_id = v_com AND o.comparable AND o.superseded_by IS NULL
       AND o.source_type IN ('merchant_ask','verified_procurement')
       AND (p_zone IS NULL OR COALESCE(o.zone_commune,'unknown') = p_zone)
     ORDER BY v.name_fr, o.canonical_base_unit
  LOOP
    out_rows := out_rows || jsonb_build_array(
      jsonb_build_object('variant_code', rec.variant_code, 'variant_name_fr', rec.name_fr)
      || public._marche_price_cohort(rec.variant_id, rec.canonical_base_unit, p_zone, NULL, NULL));
  END LOOP;
  RETURN jsonb_build_object('commodity_code', p_commodity_code, 'zone', COALESCE(p_zone,'all'),
                            'cohorts', out_rows, 'doctrine', 'Prix observé sur ChopChop');
END $$;

CREATE OR REPLACE FUNCTION public.marche_price_observations_admin(
  p_variant_id uuid DEFAULT NULL, p_limit integer DEFAULT 200)
RETURNS SETOF public.marche_procurement_price_observations
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'PRICE_ADMIN_ONLY';
  END IF;
  RETURN QUERY SELECT * FROM public.marche_procurement_price_observations
    WHERE (p_variant_id IS NULL OR variant_id = p_variant_id)
    ORDER BY observed_at DESC LIMIT LEAST(COALESCE(p_limit,200), 1000);
END $$;

CREATE OR REPLACE FUNCTION public.marche_price_supersede_observation(
  p_observation_id uuid, p_reason text, p_replacement_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rows integer;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'PRICE_ADMIN_ONLY';
  END IF;
  PERFORM set_config('marche.price_supersede','on', true);
  UPDATE public.marche_procurement_price_observations
     SET superseded_by = COALESCE(p_replacement_id, p_observation_id),
         superseded_reason = COALESCE(NULLIF(btrim(p_reason),''), 'admin_correction')
   WHERE id = p_observation_id AND superseded_by IS NULL;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  PERFORM set_config('marche.price_supersede','', true);
  RETURN jsonb_build_object('superseded', v_rows > 0, 'observation_id', p_observation_id);
END $$;

REVOKE ALL ON FUNCTION public._marche_price_normalize(uuid,bigint,numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._marche_price_record(uuid,text,text,text,bigint,numeric,timestamptz,uuid,uuid,uuid,text,text,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.marche_price_ingest_merchant_ask(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._marche_price_cohort(uuid,text,text,integer,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._marche_price_listing_ask_trg() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._marche_price_observation_guard() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._marche_listing_staple_map_guard() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._marche_price_policy() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.marche_price_observations_admin(uuid,integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_price_supersede_observation(uuid,text,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_price_observations_admin(uuid,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_price_supersede_observation(uuid,text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_price_cohort_stats(uuid,text,text,integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.marche_price_observed_public(text,text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.marche_price_freshness(timestamptz) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.marche_price_confidence(integer,timestamptz) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.marche_shopper_submit_purchase(p jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid(); v_rid uuid; m public.marche_procurement_missions;
  v_req public.marche_procurement_requests; v_total bigint; v_unresolved int; v_pending int; v_ev int;
  rec record; v_zone text;
BEGIN
  v_rid := (p->>'request_id')::uuid;
  m := public._marche_pm_shopper_lock(v_rid, v_uid);
  IF m.state IN ('purchase_verified','delivering','delivered','completed') THEN
    RETURN public.marche_procurement_mission_get(v_rid) || jsonb_build_object('replayed', true);
  END IF;
  IF m.state <> 'shopping' THEN RAISE EXCEPTION 'PROCUREMENT_ILLEGAL_TRANSITION' USING DETAIL = m.state; END IF;

  SELECT count(*) INTO v_unresolved FROM public.marche_procurement_line_resolutions
   WHERE request_id = v_rid AND state NOT IN ('acquired','unavailable');
  IF v_unresolved > 0 THEN RAISE EXCEPTION 'PROCUREMENT_LINES_UNRESOLVED' USING DETAIL = v_unresolved::text; END IF;

  SELECT count(*) INTO v_pending FROM public.marche_procurement_proposals
   WHERE request_id = v_rid AND status = 'pending';
  IF v_pending > 0 THEN RAISE EXCEPTION 'PROCUREMENT_APPROVAL_PENDING'; END IF;

  SELECT count(*) INTO v_ev FROM public.marche_procurement_purchase_evidence WHERE request_id = v_rid;
  IF v_ev = 0 THEN RAISE EXCEPTION 'PROCUREMENT_EVIDENCE_REQUIRED'; END IF;

  SELECT COALESCE(sum(actual_line_total_gnf),0) INTO v_total
    FROM public.marche_procurement_line_resolutions WHERE request_id = v_rid AND state='acquired';

  SELECT * INTO v_req FROM public.marche_procurement_requests WHERE id = v_rid FOR UPDATE;
  IF v_total > v_req.authorized_ceiling_gnf THEN
    PERFORM public._marche_pm_note(v_rid, 'purchase_over_ceiling',
      jsonb_build_object('requested_spend_gnf', v_total,
                         'authorized_ceiling_gnf', v_req.authorized_ceiling_gnf), v_uid, 'shopper');
    RETURN jsonb_build_object('status','authorization_required',
      'code','PROCUREMENT_AUTHORIZATION_REQUIRED',
      'request_id', v_rid, 'requested_spend_gnf', v_total,
      'authorized_ceiling_gnf', v_req.authorized_ceiling_gnf,
      'required_ceiling_gnf', v_total);
  END IF;

  UPDATE public.marche_procurement_missions
     SET state='purchase_verified', purchase_submitted_at = now(),
         purchase_verified_at = now(), verified_spend_gnf = v_total
   WHERE request_id = v_rid;

  SELECT commune INTO v_zone FROM public.physical_markets WHERE id = m.market_id;
  FOR rec IN
    SELECT i.purchase_option_id, lr.line_no,
           COALESCE(lr.actual_normalized_quantity, lr.actual_qty, i.qty) AS qty,
           lr.actual_line_total_gnf, lr.actual_unit_price_gnf
      FROM public.marche_procurement_line_resolutions lr
      JOIN public.marche_procurement_request_items i
        ON i.request_id = lr.request_id AND i.line_no = lr.line_no
     WHERE lr.request_id = v_rid AND lr.state = 'acquired'
       AND lr.substitute_label_fr IS NULL AND lr.actual_unit_price_gnf > 0
  LOOP
    PERFORM public._marche_price_record(
      rec.purchase_option_id, 'verified_procurement', 'shopper_receipt',
      v_rid::text || ':' || rec.line_no::text,
      COALESCE(rec.actual_line_total_gnf, rec.actual_unit_price_gnf),
      GREATEST(COALESCE(rec.qty, 1), 0.000001),
      now(), m.market_id, NULL, NULL, v_zone, NULL, v_uid);
  END LOOP;

  PERFORM public._marche_pm_note(v_rid, 'purchase_verified',
    jsonb_build_object('verified_spend_gnf', v_total), v_uid, 'shopper');
  RETURN public.marche_procurement_mission_get(v_rid);
END $$;

CREATE OR REPLACE FUNCTION public.marche_listing_set_staple_mapping(
  p_listing_id uuid, p_option_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cur public.marketplace_listings; v_variant uuid;
BEGIN
  cur := public._marche_listing_authz(p_listing_id);
  IF p_option_id IS NOT NULL THEN
    SELECT variant_id INTO v_variant FROM public.marche_staple_purchase_options
     WHERE id = p_option_id AND is_active;
    IF v_variant IS NULL THEN RAISE EXCEPTION 'STAPLE_OPTION_INVALID'; END IF;
  END IF;
  PERFORM set_config('marche.rpc','1', true);
  UPDATE public.marketplace_listings
     SET staple_purchase_option_id = p_option_id, staple_variant_id = v_variant
   WHERE id = p_listing_id;
  PERFORM set_config('marche.rpc','', true);
  RETURN jsonb_build_object('listing_id', p_listing_id, 'staple_purchase_option_id', p_option_id,
                            'staple_variant_id', v_variant);
END $$;
REVOKE ALL ON FUNCTION public.marche_listing_set_staple_mapping(uuid,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_listing_set_staple_mapping(uuid,uuid) TO authenticated;