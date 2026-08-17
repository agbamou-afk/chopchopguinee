-- =====================================================================
-- NODE 4 — MARCHE R6.5: ChopChop Procurement Basket + Authorization
-- Managed-procurement rail. Reuses Slice 13 money primitives only.
-- =====================================================================

INSERT INTO public.ledger_accounts(code, name, kind, restricted, description)
VALUES ('L_PROCUREMENT_FLOAT','Avance achat marché ChopChop','liability',true,
        'Customer funds captured for ChopChop-managed market procurement, not yet spent out')
ON CONFLICT (code) DO NOTHING;

-- ---------------------------------------------------------------
-- A. Real, auditable procurement price observation source
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.marche_procurement_price_observations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  purchase_option_id uuid NOT NULL REFERENCES public.marche_staple_purchase_options(id) ON DELETE RESTRICT,
  variant_id uuid NOT NULL REFERENCES public.marche_staple_variants(id) ON DELETE RESTRICT,
  commodity_id uuid NOT NULL REFERENCES public.marche_staple_commodities(id) ON DELETE RESTRICT,
  market_id uuid REFERENCES public.physical_markets(id) ON DELETE SET NULL,
  observed_unit_price_gnf bigint NOT NULL,
  observed_at timestamptz NOT NULL DEFAULT now(),
  source_kind text NOT NULL,
  source_ref text,
  recorded_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT mppo_price_chk CHECK (observed_unit_price_gnf > 0),
  CONSTRAINT mppo_source_chk CHECK (source_kind = ANY (ARRAY['field_agent','shopper_receipt','ops_survey'])),
  CONSTRAINT mppo_not_future_chk CHECK (observed_at <= now() + interval '1 hour')
);
CREATE INDEX IF NOT EXISTS idx_mppo_option_time
  ON public.marche_procurement_price_observations(purchase_option_id, observed_at DESC);
GRANT ALL ON public.marche_procurement_price_observations TO service_role;
ALTER TABLE public.marche_procurement_price_observations ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------
-- B. Procurement request (basket + authorization truth)
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.marche_procurement_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  buyer_user_id uuid NOT NULL,
  status text NOT NULL DEFAULT 'authorized',
  currency text NOT NULL DEFAULT 'GNF',
  authorized_ceiling_gnf bigint NOT NULL,
  held_total_gnf bigint NOT NULL DEFAULT 0,
  captured_total_gnf bigint NOT NULL DEFAULT 0,
  released_total_gnf bigint NOT NULL DEFAULT 0,
  actual_spend_gnf bigint,
  settled_at timestamptz,
  cancelled_at timestamptz,
  estimate_status text NOT NULL,
  estimate_basis text NOT NULL,
  estimated_subtotal_gnf bigint,
  estimate_confidence text,
  estimate_sample_count integer,
  estimate_freshness_hours numeric(12,2),
  estimate_unavailable_reason text,
  line_count integer NOT NULL,
  item_count numeric(14,3) NOT NULL,
  client_request_id uuid NOT NULL,
  request_fingerprint text NOT NULL,
  authorized_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT mpr_status_chk CHECK (status = ANY (ARRAY['authorized','settled','cancelled'])),
  CONSTRAINT mpr_currency_chk CHECK (currency = 'GNF'),
  CONSTRAINT mpr_ceiling_chk CHECK (authorized_ceiling_gnf > 0),
  CONSTRAINT mpr_actual_chk CHECK (actual_spend_gnf IS NULL OR (actual_spend_gnf >= 0 AND actual_spend_gnf <= authorized_ceiling_gnf)),
  CONSTRAINT mpr_estimate_status_chk CHECK (estimate_status = ANY (ARRAY['available','insufficient_data'])),
  CONSTRAINT mpr_estimate_basis_chk CHECK (estimate_basis = ANY (ARRAY['observed_procurement','customer_declared_ceiling'])),
  CONSTRAINT mpr_estimate_coherence_chk CHECK (
    (estimate_status = 'available'
       AND estimated_subtotal_gnf IS NOT NULL AND estimate_confidence IS NOT NULL
       AND estimate_sample_count IS NOT NULL AND estimate_unavailable_reason IS NULL)
    OR
    (estimate_status = 'insufficient_data'
       AND estimated_subtotal_gnf IS NULL AND estimate_confidence IS NULL
       AND estimate_sample_count IS NULL AND estimate_unavailable_reason IS NOT NULL)),
  CONSTRAINT mpr_confidence_chk CHECK (estimate_confidence IS NULL OR estimate_confidence = ANY (ARRAY['low','medium','high'])),
  CONSTRAINT mpr_lines_chk CHECK (line_count > 0 AND item_count > 0),
  CONSTRAINT mpr_money_chk CHECK (held_total_gnf >= 0 AND captured_total_gnf >= 0 AND released_total_gnf >= 0
    AND captured_total_gnf + released_total_gnf <= held_total_gnf)
);
CREATE UNIQUE INDEX IF NOT EXISTS mpr_buyer_request_key
  ON public.marche_procurement_requests(buyer_user_id, client_request_id);
CREATE INDEX IF NOT EXISTS idx_mpr_buyer_status
  ON public.marche_procurement_requests(buyer_user_id, status, created_at DESC);
GRANT ALL ON public.marche_procurement_requests TO service_role;
ALTER TABLE public.marche_procurement_requests ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------
-- C. Immutable basket lines (frozen at authorization)
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.marche_procurement_request_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.marche_procurement_requests(id) ON DELETE RESTRICT,
  line_no integer NOT NULL,
  commodity_id uuid NOT NULL REFERENCES public.marche_staple_commodities(id) ON DELETE RESTRICT,
  variant_id uuid NOT NULL REFERENCES public.marche_staple_variants(id) ON DELETE RESTRICT,
  purchase_option_id uuid NOT NULL REFERENCES public.marche_staple_purchase_options(id) ON DELETE RESTRICT,
  commodity_code text NOT NULL,
  variant_code text NOT NULL,
  option_code text NOT NULL,
  category_code text NOT NULL,
  commodity_name_fr text NOT NULL,
  variant_name_fr text NOT NULL,
  option_label_fr text NOT NULL,
  grade_note_fr text,
  sale_unit text NOT NULL,
  normalization_kind text NOT NULL,
  canonical_base_unit text,
  canonical_quantity numeric(14,4),
  requested_qty numeric(12,3) NOT NULL,
  normalized_quantity numeric(16,4),
  estimate_source text NOT NULL,
  estimated_unit_price_gnf bigint,
  estimated_line_total_gnf bigint,
  estimate_sample_count integer,
  estimate_observed_from timestamptz,
  estimate_observed_to timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT mpri_qty_chk CHECK (requested_qty > 0),
  CONSTRAINT mpri_norm_chk CHECK (normalization_kind = ANY (ARRAY['exact','unit_native','non_comparable'])),
  CONSTRAINT mpri_norm_qty_chk CHECK (
    (normalization_kind = 'exact' AND canonical_base_unit IS NOT NULL AND canonical_quantity > 0 AND normalized_quantity > 0)
    OR (normalization_kind <> 'exact' AND canonical_base_unit IS NULL AND canonical_quantity IS NULL AND normalized_quantity IS NULL)),
  CONSTRAINT mpri_estimate_source_chk CHECK (estimate_source = ANY (ARRAY['observed_procurement','insufficient_data'])),
  CONSTRAINT mpri_estimate_coherence_chk CHECK (
    (estimate_source = 'observed_procurement' AND estimated_unit_price_gnf > 0
       AND estimated_line_total_gnf > 0 AND estimate_sample_count > 0)
    OR (estimate_source = 'insufficient_data' AND estimated_unit_price_gnf IS NULL
       AND estimated_line_total_gnf IS NULL AND estimate_sample_count IS NULL))
);
CREATE UNIQUE INDEX IF NOT EXISTS mpri_line_unique ON public.marche_procurement_request_items(request_id, line_no);
GRANT ALL ON public.marche_procurement_request_items TO service_role;
ALTER TABLE public.marche_procurement_request_items ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------
-- D. Append-only authorization increments (one Slice 13 hold each)
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.marche_procurement_authorizations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.marche_procurement_requests(id) ON DELETE RESTRICT,
  seq integer NOT NULL,
  kind text NOT NULL,
  amount_gnf bigint NOT NULL,
  ceiling_before_gnf bigint NOT NULL,
  ceiling_after_gnf bigint NOT NULL,
  hold_source_module text NOT NULL DEFAULT 'marche_procurement',
  approved_by uuid NOT NULL,
  client_request_id uuid NOT NULL,
  captured_gnf bigint NOT NULL DEFAULT 0,
  released_gnf bigint NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT mpa_kind_chk CHECK (kind = ANY (ARRAY['initial','increase'])),
  CONSTRAINT mpa_amount_chk CHECK (amount_gnf > 0),
  CONSTRAINT mpa_monotonic_chk CHECK (ceiling_after_gnf = ceiling_before_gnf + amount_gnf),
  CONSTRAINT mpa_settle_chk CHECK (captured_gnf >= 0 AND released_gnf >= 0 AND captured_gnf + released_gnf <= amount_gnf)
);
CREATE UNIQUE INDEX IF NOT EXISTS mpa_seq_unique ON public.marche_procurement_authorizations(request_id, seq);
CREATE UNIQUE INDEX IF NOT EXISTS mpa_key_unique ON public.marche_procurement_authorizations(request_id, client_request_id);
GRANT ALL ON public.marche_procurement_authorizations TO service_role;
ALTER TABLE public.marche_procurement_authorizations ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------
-- E. Append-only event trail
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.marche_procurement_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES public.marche_procurement_requests(id) ON DELETE RESTRICT,
  event text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  actor_user_id uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_mpe_request ON public.marche_procurement_events(request_id, created_at);
GRANT ALL ON public.marche_procurement_events TO service_role;
ALTER TABLE public.marche_procurement_events ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------
-- F. Immutability guards
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._marche_procurement_append_only()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $fn$
BEGIN
  IF TG_OP = 'DELETE' AND COALESCE(current_setting('marche.procurement_purge', true),'') = 'on' THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION 'PROCUREMENT_APPEND_ONLY';
END $fn$;

DROP TRIGGER IF EXISTS trg_mpri_append_only ON public.marche_procurement_request_items;
CREATE TRIGGER trg_mpri_append_only BEFORE UPDATE OR DELETE ON public.marche_procurement_request_items
  FOR EACH ROW EXECUTE FUNCTION public._marche_procurement_append_only();
DROP TRIGGER IF EXISTS trg_mpe_append_only ON public.marche_procurement_events;
CREATE TRIGGER trg_mpe_append_only BEFORE UPDATE OR DELETE ON public.marche_procurement_events
  FOR EACH ROW EXECUTE FUNCTION public._marche_procurement_append_only();
DROP TRIGGER IF EXISTS trg_mppo_append_only ON public.marche_procurement_price_observations;
CREATE TRIGGER trg_mppo_append_only BEFORE UPDATE OR DELETE ON public.marche_procurement_price_observations
  FOR EACH ROW EXECUTE FUNCTION public._marche_procurement_append_only();

CREATE OR REPLACE FUNCTION public._marche_procurement_auth_immutable()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $fn$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF COALESCE(current_setting('marche.procurement_purge', true),'') = 'on' THEN RETURN OLD; END IF;
    RAISE EXCEPTION 'PROCUREMENT_APPEND_ONLY';
  END IF;
  IF NEW.request_id <> OLD.request_id OR NEW.seq <> OLD.seq OR NEW.kind <> OLD.kind
     OR NEW.amount_gnf <> OLD.amount_gnf OR NEW.ceiling_before_gnf <> OLD.ceiling_before_gnf
     OR NEW.ceiling_after_gnf <> OLD.ceiling_after_gnf OR NEW.approved_by <> OLD.approved_by
     OR NEW.client_request_id <> OLD.client_request_id OR NEW.created_at <> OLD.created_at THEN
    RAISE EXCEPTION 'PROCUREMENT_AUTHORIZATION_IMMUTABLE';
  END IF;
  IF NEW.captured_gnf < OLD.captured_gnf OR NEW.released_gnf < OLD.released_gnf THEN
    RAISE EXCEPTION 'PROCUREMENT_SETTLEMENT_MONOTONIC';
  END IF;
  RETURN NEW;
END $fn$;
DROP TRIGGER IF EXISTS trg_mpa_immutable ON public.marche_procurement_authorizations;
CREATE TRIGGER trg_mpa_immutable BEFORE UPDATE OR DELETE ON public.marche_procurement_authorizations
  FOR EACH ROW EXECUTE FUNCTION public._marche_procurement_auth_immutable();

CREATE OR REPLACE FUNCTION public._marche_procurement_request_immutable()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $fn$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF COALESCE(current_setting('marche.procurement_purge', true),'') = 'on' THEN RETURN OLD; END IF;
    RAISE EXCEPTION 'PROCUREMENT_APPEND_ONLY';
  END IF;
  IF NEW.buyer_user_id <> OLD.buyer_user_id
     OR NEW.client_request_id <> OLD.client_request_id
     OR NEW.request_fingerprint <> OLD.request_fingerprint
     OR NEW.currency <> OLD.currency
     OR NEW.line_count <> OLD.line_count OR NEW.item_count <> OLD.item_count
     OR NEW.estimate_status <> OLD.estimate_status
     OR NEW.estimate_basis <> OLD.estimate_basis
     OR NEW.estimated_subtotal_gnf IS DISTINCT FROM OLD.estimated_subtotal_gnf
     OR NEW.estimate_confidence IS DISTINCT FROM OLD.estimate_confidence
     OR NEW.estimate_sample_count IS DISTINCT FROM OLD.estimate_sample_count
     OR NEW.authorized_at <> OLD.authorized_at OR NEW.created_at <> OLD.created_at THEN
    RAISE EXCEPTION 'PROCUREMENT_REQUEST_IMMUTABLE';
  END IF;
  IF NEW.authorized_ceiling_gnf < OLD.authorized_ceiling_gnf THEN
    RAISE EXCEPTION 'PROCUREMENT_CEILING_NOT_MONOTONIC';
  END IF;
  IF OLD.actual_spend_gnf IS NOT NULL AND NEW.actual_spend_gnf IS DISTINCT FROM OLD.actual_spend_gnf THEN
    RAISE EXCEPTION 'PROCUREMENT_ACTUAL_SPEND_IMMUTABLE';
  END IF;
  IF OLD.settled_at IS NOT NULL AND NEW.settled_at IS DISTINCT FROM OLD.settled_at THEN
    RAISE EXCEPTION 'PROCUREMENT_SETTLEMENT_IMMUTABLE';
  END IF;
  IF OLD.status = 'settled' AND NEW.status <> 'settled' THEN
    RAISE EXCEPTION 'PROCUREMENT_TERMINAL_STATE';
  END IF;
  IF OLD.status = 'cancelled' AND NEW.status <> 'cancelled' THEN
    RAISE EXCEPTION 'PROCUREMENT_TERMINAL_STATE';
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END $fn$;
DROP TRIGGER IF EXISTS trg_mpr_immutable ON public.marche_procurement_requests;
CREATE TRIGGER trg_mpr_immutable BEFORE UPDATE OR DELETE ON public.marche_procurement_requests
  FOR EACH ROW EXECUTE FUNCTION public._marche_procurement_request_immutable();

-- ---------------------------------------------------------------
-- G. Server-authoritative policy + estimate law
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._marche_procurement_policy()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT jsonb_build_object(
    'min_ceiling_gnf', COALESCE((SELECT (value->>'min_ceiling_gnf')::bigint
        FROM public.app_settings WHERE key = 'marche_procurement'), 10000::bigint),
    'max_ceiling_gnf', COALESCE((SELECT (value->>'max_ceiling_gnf')::bigint
        FROM public.app_settings WHERE key = 'marche_procurement'), 20000000::bigint),
    'max_lines', COALESCE((SELECT (value->>'max_lines')::int
        FROM public.app_settings WHERE key = 'marche_procurement'), 25),
    'observation_window_hours', 336,
    'min_samples', 3,
    'currency', 'GNF',
    'disclaimer_fr', 'Estimation — le prix réel au marché peut varier.');
$fn$;

CREATE OR REPLACE FUNCTION public._marche_procurement_option_estimate(p_option_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_pol jsonb := public._marche_procurement_policy();
  v_win interval := ((v_pol->>'observation_window_hours')::int || ' hours')::interval;
  v_min int := (v_pol->>'min_samples')::int;
  v_n int; v_med numeric; v_from timestamptz; v_to timestamptz; v_age_h numeric; v_conf text;
BEGIN
  SELECT count(*), percentile_cont(0.5) WITHIN GROUP (ORDER BY observed_unit_price_gnf),
         min(observed_at), max(observed_at)
    INTO v_n, v_med, v_from, v_to
    FROM public.marche_procurement_price_observations
   WHERE purchase_option_id = p_option_id
     AND observed_at >= now() - v_win;

  IF COALESCE(v_n,0) < v_min THEN
    RETURN jsonb_build_object('estimate_source','insufficient_data',
      'reason', 'NO_RECENT_PROCUREMENT_OBSERVATIONS',
      'sample_count_in_window', COALESCE(v_n,0), 'min_samples', v_min);
  END IF;

  v_age_h := EXTRACT(EPOCH FROM (now() - v_to)) / 3600.0;
  v_conf := CASE
    WHEN v_n >= 8 AND v_age_h <= 72 THEN 'high'
    WHEN v_n >= 5 AND v_age_h <= 168 THEN 'medium'
    ELSE 'low' END;

  RETURN jsonb_build_object(
    'estimate_source','observed_procurement',
    'unit_price_gnf', floor(v_med)::bigint,
    'sample_count', v_n,
    'observed_from', v_from,
    'observed_to', v_to,
    'freshness_hours', round(v_age_h, 2),
    'confidence', v_conf);
END $fn$;

-- ---------------------------------------------------------------
-- H. Basket resolution: identity, unit and quantity truth
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._marche_procurement_resolve(p_lines jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_pol jsonb := public._marche_procurement_policy();
  v_line jsonb; v_out jsonb := '[]'::jsonb; v_no int := 0;
  v_qty numeric; v_o record; v_est jsonb; v_norm numeric;
  v_sub bigint := 0; v_all_ok boolean := true; v_items numeric := 0;
  v_samples int := NULL; v_conf text := NULL; v_fresh numeric := NULL; v_reason text := NULL;
  v_key text;
BEGIN
  IF p_lines IS NULL OR jsonb_typeof(p_lines) <> 'array' OR jsonb_array_length(p_lines) = 0 THEN
    RAISE EXCEPTION 'PROCUREMENT_EMPTY_BASKET';
  END IF;
  IF jsonb_array_length(p_lines) > (v_pol->>'max_lines')::int THEN
    RAISE EXCEPTION 'PROCUREMENT_TOO_MANY_LINES';
  END IF;

  FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    FOR v_key IN SELECT jsonb_object_keys(v_line) LOOP
      IF v_key IN ('listing_id','store_id','merchant_store_id','merchant_user_id','offer_id','seller_id') THEN
        RAISE EXCEPTION 'PROCUREMENT_MERCHANT_FIELD_FORBIDDEN';
      END IF;
      IF v_key NOT IN ('commodity_code','variant_code','option_code','qty') THEN
        RAISE EXCEPTION 'PROCUREMENT_CLIENT_FIELD_FORBIDDEN' USING DETAIL = v_key;
      END IF;
    END LOOP;

    v_no := v_no + 1;
    SELECT o.id AS option_id, o.code AS option_code, o.sale_unit, o.label_fr,
           o.normalization_kind, o.canonical_base_unit, o.canonical_quantity,
           o.min_qty, o.max_qty, o.step_qty, o.is_active AS o_active,
           vv.id AS variant_id, vv.code AS variant_code, vv.name_fr AS variant_name, vv.grade_note_fr,
           vv.is_active AS v_active,
           c.id AS commodity_id, c.code AS commodity_code, c.name_fr AS commodity_name,
           c.category_code, c.is_active AS c_active
      INTO v_o
      FROM public.marche_staple_purchase_options o
      JOIN public.marche_staple_variants vv ON vv.id = o.variant_id
      JOIN public.marche_staple_commodities c ON c.id = vv.commodity_id
     WHERE c.code = (v_line->>'commodity_code')
       AND vv.code = (v_line->>'variant_code')
       AND o.code = (v_line->>'option_code');
    IF v_o.option_id IS NULL THEN
      RAISE EXCEPTION 'PROCUREMENT_UNKNOWN_STAPLE'
        USING DETAIL = COALESCE(v_line->>'commodity_code','?') || '/' ||
                       COALESCE(v_line->>'variant_code','?') || '/' || COALESCE(v_line->>'option_code','?');
    END IF;
    IF NOT (v_o.o_active AND v_o.v_active AND v_o.c_active) THEN
      RAISE EXCEPTION 'PROCUREMENT_OPTION_INACTIVE';
    END IF;

    BEGIN
      v_qty := (v_line->>'qty')::numeric;
    EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'PROCUREMENT_QTY_INVALID'; END;
    IF v_qty IS NULL OR v_qty <= 0 THEN RAISE EXCEPTION 'PROCUREMENT_QTY_INVALID'; END IF;
    IF v_qty < v_o.min_qty OR v_qty > v_o.max_qty THEN
      RAISE EXCEPTION 'PROCUREMENT_QTY_OUT_OF_RANGE'
        USING DETAIL = format('qty=%s allowed=%s..%s', v_qty, v_o.min_qty, v_o.max_qty);
    END IF;
    IF mod((v_qty - v_o.min_qty)::numeric, v_o.step_qty::numeric) <> 0 THEN
      RAISE EXCEPTION 'PROCUREMENT_QTY_NOT_STEP_ALIGNED'
        USING DETAIL = format('qty=%s step=%s', v_qty, v_o.step_qty);
    END IF;

    v_norm := CASE WHEN v_o.normalization_kind = 'exact'
                   THEN round(v_qty * v_o.canonical_quantity, 4) ELSE NULL END;
    v_est := public._marche_procurement_option_estimate(v_o.option_id);

    IF v_est->>'estimate_source' = 'observed_procurement' THEN
      v_sub := v_sub + floor((v_est->>'unit_price_gnf')::numeric * v_qty)::bigint;
      v_samples := LEAST(COALESCE(v_samples, (v_est->>'sample_count')::int), (v_est->>'sample_count')::int);
      v_fresh := GREATEST(COALESCE(v_fresh, (v_est->>'freshness_hours')::numeric), (v_est->>'freshness_hours')::numeric);
      v_conf := CASE
        WHEN v_conf IS NULL THEN v_est->>'confidence'
        WHEN 'low' IN (v_conf, v_est->>'confidence') THEN 'low'
        WHEN 'medium' IN (v_conf, v_est->>'confidence') THEN 'medium'
        ELSE 'high' END;
    ELSE
      v_all_ok := false;
      v_reason := COALESCE(v_reason, v_est->>'reason');
    END IF;

    v_items := v_items + v_qty;
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'line_no', v_no,
      'commodity_id', v_o.commodity_id, 'variant_id', v_o.variant_id, 'purchase_option_id', v_o.option_id,
      'commodity_code', v_o.commodity_code, 'variant_code', v_o.variant_code, 'option_code', v_o.option_code,
      'category_code', v_o.category_code,
      'commodity_name_fr', v_o.commodity_name, 'variant_name_fr', v_o.variant_name,
      'option_label_fr', v_o.label_fr, 'grade_note_fr', v_o.grade_note_fr,
      'sale_unit', v_o.sale_unit, 'normalization_kind', v_o.normalization_kind,
      'canonical_base_unit', v_o.canonical_base_unit, 'canonical_quantity', v_o.canonical_quantity,
      'requested_qty', v_qty, 'normalized_quantity', v_norm,
      'estimate_source', v_est->>'estimate_source',
      'estimated_unit_price_gnf', CASE WHEN v_est->>'estimate_source'='observed_procurement'
                                       THEN (v_est->>'unit_price_gnf')::bigint END,
      'estimated_line_total_gnf', CASE WHEN v_est->>'estimate_source'='observed_procurement'
                                       THEN floor((v_est->>'unit_price_gnf')::numeric * v_qty)::bigint END,
      'estimate_sample_count', CASE WHEN v_est->>'estimate_source'='observed_procurement'
                                    THEN (v_est->>'sample_count')::int END,
      'estimate_observed_from', v_est->>'observed_from',
      'estimate_observed_to', v_est->>'observed_to',
      'estimate_confidence', v_est->>'confidence',
      'estimate_unavailable_reason', v_est->>'reason'));
  END LOOP;

  RETURN jsonb_build_object(
    'lines', v_out,
    'line_count', v_no,
    'item_count', v_items,
    'currency', 'GNF',
    'estimate_status', CASE WHEN v_all_ok THEN 'available' ELSE 'insufficient_data' END,
    'estimate_basis', CASE WHEN v_all_ok THEN 'observed_procurement' ELSE 'customer_declared_ceiling' END,
    'estimated_subtotal_gnf', CASE WHEN v_all_ok THEN v_sub END,
    'estimate_confidence', CASE WHEN v_all_ok THEN v_conf END,
    'estimate_sample_count', CASE WHEN v_all_ok THEN v_samples END,
    'estimate_freshness_hours', CASE WHEN v_all_ok THEN v_fresh END,
    'estimate_unavailable_reason', CASE WHEN v_all_ok THEN NULL ELSE COALESCE(v_reason,'NO_RECENT_PROCUREMENT_OBSERVATIONS') END,
    'min_ceiling_gnf', GREATEST((v_pol->>'min_ceiling_gnf')::bigint, CASE WHEN v_all_ok THEN v_sub ELSE 0 END),
    'max_ceiling_gnf', (v_pol->>'max_ceiling_gnf')::bigint,
    'disclaimer_fr', v_pol->>'disclaimer_fr');
END $fn$;

CREATE OR REPLACE FUNCTION public._marche_procurement_fingerprint(p_lines jsonb, p_ceiling bigint)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = public AS $fn$
  SELECT md5(COALESCE((
    SELECT string_agg(format('%s/%s/%s@%s', l->>'commodity_code', l->>'variant_code',
                             l->>'option_code', (l->>'requested_qty')::numeric), ',' ORDER BY
                      format('%s/%s/%s', l->>'commodity_code', l->>'variant_code', l->>'option_code'))
      FROM jsonb_array_elements(p_lines) l), '') || '|ceiling=' || COALESCE(p_ceiling,0)::text);
$fn$;

-- ---------------------------------------------------------------
-- I. Slice 13 money adapters (no parallel wallet/ledger system)
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._marche_procurement_capture_internal(
  p_auth_id uuid, p_amount bigint, p_actor uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_a public.marche_procurement_authorizations;
  v_h public.mission_financial_holds; v_open bigint;
  v_cw public.wallets; v_master public.wallets; v_buyer uuid; v_key text;
BEGIN
  IF COALESCE(p_amount,0) <= 0 THEN RETURN jsonb_build_object('status','zero','captured_gnf',0); END IF;
  SELECT * INTO v_a FROM public.marche_procurement_authorizations WHERE id = p_auth_id FOR UPDATE;
  IF v_a.id IS NULL THEN RAISE EXCEPTION 'PROCUREMENT_AUTHORIZATION_MISSING'; END IF;
  SELECT buyer_user_id INTO v_buyer FROM public.marche_procurement_requests WHERE id = v_a.request_id;

  v_key := format('mproc-capture:%s', p_auth_id);
  IF EXISTS (SELECT 1 FROM public.ledger_journals WHERE journal_key = v_key) THEN
    RETURN jsonb_build_object('status','already_captured','captured_gnf',0);
  END IF;

  SELECT * INTO v_h FROM public.mission_financial_holds
   WHERE source_module = 'marche_procurement' AND source_id = p_auth_id
     AND kind = 'customer_payment' FOR UPDATE;
  IF v_h.id IS NULL THEN RAISE EXCEPTION 'PROCUREMENT_HOLD_MISSING'; END IF;
  v_open := v_h.amount_gnf - v_h.captured_gnf - v_h.released_gnf;
  IF v_open < p_amount THEN
    RAISE EXCEPTION 'PROCUREMENT_HOLD_INSUFFICIENT'
      USING DETAIL = format('open=%s requested=%s', v_open, p_amount);
  END IF;

  SELECT * INTO v_cw FROM public.wallets
   WHERE owner_user_id = v_buyer AND party_type = 'client' FOR UPDATE;
  IF v_cw.id IS NULL THEN RAISE EXCEPTION 'PROCUREMENT_WALLET_MISSING'; END IF;
  UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - p_amount, 0),
                            balance_gnf = balance_gnf - p_amount, updated_at = now()
   WHERE id = v_cw.id;

  SELECT * INTO v_master FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;
  IF v_master.id IS NULL THEN RAISE EXCEPTION 'MASTER_WALLET_MISSING'; END IF;
  UPDATE public.wallets SET balance_gnf = balance_gnf + p_amount, updated_at = now()
   WHERE id = v_master.id;

  INSERT INTO public.wallet_transactions
    (reference, type, status, amount_gnf, from_wallet_id, to_wallet_id, related_user_id,
     related_entity, description, metadata, completed_at)
  VALUES (v_key, 'capture', 'completed', p_amount, v_cw.id, v_master.id, v_buyer,
     'marche_procurement:' || p_auth_id::text, 'Achat marché ChopChop (dépense réelle)',
     jsonb_build_object('purpose','procurement_spend','mission_type','marche_procurement',
                        'tender','chop_pay','request_id', v_a.request_id), now());

  PERFORM public._ledger_post(v_key, 'marche_procurement', p_auth_id, 'capture_procurement_spend',
    jsonb_build_array(
      jsonb_build_object('account','L_CUSTOMER_HOLD','amount_gnf',p_amount,
                         'party_type','client','party_user_id',v_buyer,'memo','consume procurement authorization'),
      jsonb_build_object('account','L_PROCUREMENT_FLOAT','amount_gnf',-p_amount,
                         'party_type','client','party_user_id',v_buyer,'memo','ChopChop market procurement float')),
    'marche_procurement', p_actor, '{}'::jsonb, v_h.is_sandbox);

  UPDATE public.mission_financial_holds
     SET captured_gnf = captured_gnf + p_amount,
         state = CASE WHEN captured_gnf + p_amount + released_gnf >= amount_gnf
                      THEN 'captured' ELSE 'partially_captured' END,
         resolved_at = CASE WHEN captured_gnf + p_amount + released_gnf >= amount_gnf
                            THEN now() ELSE resolved_at END
   WHERE id = v_h.id;
  UPDATE public.wallet_transactions SET status = 'completed', completed_at = now()
   WHERE id = v_h.hold_tx_id AND status = 'pending'
     AND EXISTS (SELECT 1 FROM public.mission_financial_holds h
                  WHERE h.id = v_h.id AND h.captured_gnf + h.released_gnf >= h.amount_gnf);
  UPDATE public.marche_procurement_authorizations
     SET captured_gnf = captured_gnf + p_amount WHERE id = p_auth_id;

  RETURN jsonb_build_object('status','captured','captured_gnf',p_amount);
END $fn$;

CREATE OR REPLACE FUNCTION public._marche_procurement_release_internal(
  p_auth_id uuid, p_reason text DEFAULT NULL, p_actor uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_a public.marche_procurement_authorizations;
  v_h public.mission_financial_holds; v_open bigint; v_cw public.wallets; v_buyer uuid;
BEGIN
  SELECT * INTO v_a FROM public.marche_procurement_authorizations WHERE id = p_auth_id FOR UPDATE;
  IF v_a.id IS NULL THEN RAISE EXCEPTION 'PROCUREMENT_AUTHORIZATION_MISSING'; END IF;
  SELECT buyer_user_id INTO v_buyer FROM public.marche_procurement_requests WHERE id = v_a.request_id;

  SELECT * INTO v_h FROM public.mission_financial_holds
   WHERE source_module = 'marche_procurement' AND source_id = p_auth_id
     AND kind = 'customer_payment' FOR UPDATE;
  IF v_h.id IS NULL THEN RETURN jsonb_build_object('status','no_hold','released_gnf',0); END IF;
  v_open := v_h.amount_gnf - v_h.captured_gnf - v_h.released_gnf;
  IF v_open <= 0 THEN RETURN jsonb_build_object('status','already_resolved','released_gnf',0); END IF;

  SELECT * INTO v_cw FROM public.wallets
   WHERE owner_user_id = v_buyer AND party_type = 'client' FOR UPDATE;
  UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - v_open, 0), updated_at = now()
   WHERE id = v_cw.id;
  UPDATE public.wallet_transactions SET status = 'cancelled', completed_at = now()
   WHERE id = v_h.hold_tx_id AND status = 'pending';

  PERFORM public._ledger_post(format('mproc-release:%s', p_auth_id),
    'marche_procurement', p_auth_id, 'release_procurement_authorization',
    jsonb_build_array(
      jsonb_build_object('account','L_CUSTOMER_HOLD','amount_gnf',v_open,
                         'party_type','client','party_user_id',v_buyer,'memo','release unused authorization'),
      jsonb_build_object('account','L_CUSTOMER_CHOPPAY','amount_gnf',-v_open,
                         'party_type','client','party_user_id',v_buyer,'memo','restored to chop pay balance')),
    'marche_procurement', p_actor, '{}'::jsonb, v_h.is_sandbox, p_reason);

  UPDATE public.mission_financial_holds
     SET released_gnf = released_gnf + v_open,
         state = CASE WHEN captured_gnf > 0 THEN 'captured' ELSE 'released' END,
         reason = COALESCE(p_reason, reason), resolved_at = now(), resolved_by = p_actor
   WHERE id = v_h.id;
  UPDATE public.marche_procurement_authorizations
     SET released_gnf = released_gnf + v_open WHERE id = p_auth_id;

  RETURN jsonb_build_object('status','released','released_gnf',v_open);
END $fn$;

-- ---------------------------------------------------------------
-- J. Customer-facing procurement RPCs
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marche_procurement_quote(p jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v jsonb;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'PROCUREMENT_AUTH_REQUIRED'; END IF;
  v := public._marche_procurement_resolve(p->'lines');
  RETURN v - 'lines' || jsonb_build_object('lines', (
    SELECT COALESCE(jsonb_agg(l - 'commodity_id' - 'variant_id' - 'purchase_option_id'
                                ORDER BY (l->>'line_no')::int), '[]'::jsonb)
      FROM jsonb_array_elements(v->'lines') l));
END $fn$;

CREATE OR REPLACE FUNCTION public.marche_procurement_get(p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_req public.marche_procurement_requests; v_uid uuid := auth.uid();
BEGIN
  SELECT * INTO v_req FROM public.marche_procurement_requests WHERE id = p_request_id;
  IF v_req.id IS NULL THEN RETURN NULL; END IF;
  IF v_req.buyer_user_id <> v_uid AND NOT public._finance_privileged(v_uid)
     AND NOT public.is_any_admin(v_uid) THEN
    RAISE EXCEPTION 'PROCUREMENT_NOT_AUTHORIZED';
  END IF;
  RETURN jsonb_build_object(
    'id', v_req.id, 'status', v_req.status, 'currency', v_req.currency,
    'buyer_user_id', v_req.buyer_user_id,
    'authorized_ceiling_gnf', v_req.authorized_ceiling_gnf,
    'held_total_gnf', v_req.held_total_gnf,
    'captured_total_gnf', v_req.captured_total_gnf,
    'released_total_gnf', v_req.released_total_gnf,
    'actual_spend_gnf', v_req.actual_spend_gnf,
    'settled_at', v_req.settled_at, 'cancelled_at', v_req.cancelled_at,
    'estimate_status', v_req.estimate_status, 'estimate_basis', v_req.estimate_basis,
    'estimated_subtotal_gnf', v_req.estimated_subtotal_gnf,
    'estimate_confidence', v_req.estimate_confidence,
    'estimate_sample_count', v_req.estimate_sample_count,
    'estimate_freshness_hours', v_req.estimate_freshness_hours,
    'estimate_unavailable_reason', v_req.estimate_unavailable_reason,
    'line_count', v_req.line_count, 'item_count', v_req.item_count,
    'client_request_id', v_req.client_request_id,
    'authorized_at', v_req.authorized_at,
    'disclaimer_fr', public._marche_procurement_policy()->>'disclaimer_fr',
    'items', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'line_no', i.line_no, 'commodity_code', i.commodity_code, 'variant_code', i.variant_code,
        'option_code', i.option_code, 'category_code', i.category_code,
        'commodity_name_fr', i.commodity_name_fr, 'variant_name_fr', i.variant_name_fr,
        'option_label_fr', i.option_label_fr, 'grade_note_fr', i.grade_note_fr,
        'sale_unit', i.sale_unit, 'normalization_kind', i.normalization_kind,
        'canonical_base_unit', i.canonical_base_unit, 'canonical_quantity', i.canonical_quantity,
        'requested_qty', i.requested_qty, 'normalized_quantity', i.normalized_quantity,
        'estimate_source', i.estimate_source,
        'estimated_unit_price_gnf', i.estimated_unit_price_gnf,
        'estimated_line_total_gnf', i.estimated_line_total_gnf,
        'estimate_sample_count', i.estimate_sample_count) ORDER BY i.line_no), '[]'::jsonb)
      FROM public.marche_procurement_request_items i WHERE i.request_id = v_req.id),
    'authorizations', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'seq', a.seq, 'kind', a.kind, 'amount_gnf', a.amount_gnf,
        'ceiling_before_gnf', a.ceiling_before_gnf, 'ceiling_after_gnf', a.ceiling_after_gnf,
        'captured_gnf', a.captured_gnf, 'released_gnf', a.released_gnf,
        'created_at', a.created_at) ORDER BY a.seq), '[]'::jsonb)
      FROM public.marche_procurement_authorizations a WHERE a.request_id = v_req.id));
END $fn$;

CREATE OR REPLACE FUNCTION public.marche_procurement_authorize(p jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_res jsonb; v_pol jsonb := public._marche_procurement_policy();
  v_key uuid; v_ceiling bigint; v_fp text; v_req public.marche_procurement_requests;
  v_id uuid; v_auth_id uuid; v_l jsonb; v_hold jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'PROCUREMENT_AUTH_REQUIRED'; END IF;
  BEGIN v_key := (p->>'client_request_id')::uuid;
  EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'PROCUREMENT_REQUEST_KEY_REQUIRED'; END;
  IF v_key IS NULL THEN RAISE EXCEPTION 'PROCUREMENT_REQUEST_KEY_REQUIRED'; END IF;

  IF (p->'ceiling_gnf') IS NULL OR jsonb_typeof(p->'ceiling_gnf') <> 'number' THEN
    RAISE EXCEPTION 'PROCUREMENT_CEILING_INVALID';
  END IF;
  IF (p->>'ceiling_gnf')::numeric <> floor((p->>'ceiling_gnf')::numeric) THEN
    RAISE EXCEPTION 'PROCUREMENT_CEILING_INVALID';
  END IF;
  v_ceiling := (p->>'ceiling_gnf')::bigint;
  IF v_ceiling <= 0 THEN RAISE EXCEPTION 'PROCUREMENT_CEILING_INVALID'; END IF;

  v_res := public._marche_procurement_resolve(p->'lines');
  v_fp := public._marche_procurement_fingerprint(v_res->'lines', v_ceiling);

  SELECT * INTO v_req FROM public.marche_procurement_requests
   WHERE buyer_user_id = v_uid AND client_request_id = v_key;
  IF v_req.id IS NOT NULL THEN
    IF v_req.request_fingerprint <> v_fp THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT'; END IF;
    RETURN public.marche_procurement_get(v_req.id) || jsonb_build_object('replayed', true);
  END IF;

  IF v_ceiling < (v_res->>'min_ceiling_gnf')::bigint THEN
    RAISE EXCEPTION 'PROCUREMENT_CEILING_BELOW_MINIMUM'
      USING DETAIL = format('ceiling=%s minimum=%s', v_ceiling, v_res->>'min_ceiling_gnf');
  END IF;
  IF v_ceiling > (v_res->>'max_ceiling_gnf')::bigint THEN
    RAISE EXCEPTION 'PROCUREMENT_CEILING_ABOVE_MAXIMUM';
  END IF;

  INSERT INTO public.marche_procurement_requests
    (buyer_user_id, status, authorized_ceiling_gnf, estimate_status, estimate_basis,
     estimated_subtotal_gnf, estimate_confidence, estimate_sample_count, estimate_freshness_hours,
     estimate_unavailable_reason, line_count, item_count, client_request_id, request_fingerprint)
  VALUES (v_uid, 'authorized', v_ceiling, v_res->>'estimate_status', v_res->>'estimate_basis',
     NULLIF(v_res->>'estimated_subtotal_gnf','')::bigint,
     NULLIF(v_res->>'estimate_confidence',''),
     NULLIF(v_res->>'estimate_sample_count','')::int,
     NULLIF(v_res->>'estimate_freshness_hours','')::numeric,
     NULLIF(v_res->>'estimate_unavailable_reason',''),
     (v_res->>'line_count')::int, (v_res->>'item_count')::numeric, v_key, v_fp)
  RETURNING id INTO v_id;

  FOR v_l IN SELECT * FROM jsonb_array_elements(v_res->'lines') LOOP
    INSERT INTO public.marche_procurement_request_items
      (request_id, line_no, commodity_id, variant_id, purchase_option_id,
       commodity_code, variant_code, option_code, category_code,
       commodity_name_fr, variant_name_fr, option_label_fr, grade_note_fr,
       sale_unit, normalization_kind, canonical_base_unit, canonical_quantity,
       requested_qty, normalized_quantity, estimate_source, estimated_unit_price_gnf,
       estimated_line_total_gnf, estimate_sample_count, estimate_observed_from, estimate_observed_to)
    VALUES (v_id, (v_l->>'line_no')::int, (v_l->>'commodity_id')::uuid, (v_l->>'variant_id')::uuid,
       (v_l->>'purchase_option_id')::uuid, v_l->>'commodity_code', v_l->>'variant_code',
       v_l->>'option_code', v_l->>'category_code', v_l->>'commodity_name_fr', v_l->>'variant_name_fr',
       v_l->>'option_label_fr', v_l->>'grade_note_fr', v_l->>'sale_unit', v_l->>'normalization_kind',
       v_l->>'canonical_base_unit', NULLIF(v_l->>'canonical_quantity','')::numeric,
       (v_l->>'requested_qty')::numeric, NULLIF(v_l->>'normalized_quantity','')::numeric,
       v_l->>'estimate_source', NULLIF(v_l->>'estimated_unit_price_gnf','')::bigint,
       NULLIF(v_l->>'estimated_line_total_gnf','')::bigint,
       NULLIF(v_l->>'estimate_sample_count','')::int,
       NULLIF(v_l->>'estimate_observed_from','')::timestamptz,
       NULLIF(v_l->>'estimate_observed_to','')::timestamptz);
  END LOOP;

  INSERT INTO public.marche_procurement_authorizations
    (request_id, seq, kind, amount_gnf, ceiling_before_gnf, ceiling_after_gnf, approved_by, client_request_id)
  VALUES (v_id, 1, 'initial', v_ceiling, 0, v_ceiling, v_uid, v_key)
  RETURNING id INTO v_auth_id;

  v_hold := public.chop_pay_customer_hold_place('marche_procurement', v_auth_id, v_ceiling,
              'marche_procurement', v_uid, false,
              jsonb_build_object('rail','marche_procurement','request_id',v_id));
  IF COALESCE(v_hold->>'status','') <> 'held' THEN RAISE EXCEPTION 'PROCUREMENT_HOLD_FAILED'; END IF;

  UPDATE public.marche_procurement_requests SET held_total_gnf = v_ceiling WHERE id = v_id;
  INSERT INTO public.marche_procurement_events(request_id, event, payload, actor_user_id)
  VALUES (v_id, 'authorized', jsonb_build_object('ceiling_gnf', v_ceiling,
          'estimate_status', v_res->>'estimate_status'), v_uid);

  RETURN public.marche_procurement_get(v_id);
END $fn$;

CREATE OR REPLACE FUNCTION public.marche_procurement_increase(p jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_uid uuid := auth.uid(); v_rid uuid; v_key uuid; v_new bigint; v_delta bigint;
  v_req public.marche_procurement_requests; v_pol jsonb := public._marche_procurement_policy();
  v_auth_id uuid; v_seq int; v_hold jsonb; v_existing public.marche_procurement_authorizations;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'PROCUREMENT_AUTH_REQUIRED'; END IF;
  v_rid := (p->>'request_id')::uuid;
  v_key := (p->>'client_request_id')::uuid;
  IF v_rid IS NULL OR v_key IS NULL THEN RAISE EXCEPTION 'PROCUREMENT_REQUEST_KEY_REQUIRED'; END IF;
  IF (p->'new_ceiling_gnf') IS NULL OR jsonb_typeof(p->'new_ceiling_gnf') <> 'number'
     OR (p->>'new_ceiling_gnf')::numeric <> floor((p->>'new_ceiling_gnf')::numeric) THEN
    RAISE EXCEPTION 'PROCUREMENT_CEILING_INVALID';
  END IF;
  v_new := (p->>'new_ceiling_gnf')::bigint;

  SELECT * INTO v_req FROM public.marche_procurement_requests WHERE id = v_rid FOR UPDATE;
  IF v_req.id IS NULL THEN RAISE EXCEPTION 'PROCUREMENT_NOT_FOUND'; END IF;
  IF v_req.buyer_user_id <> v_uid THEN RAISE EXCEPTION 'PROCUREMENT_NOT_AUTHORIZED'; END IF;

  SELECT * INTO v_existing FROM public.marche_procurement_authorizations
   WHERE request_id = v_rid AND client_request_id = v_key;
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.ceiling_after_gnf <> v_new THEN RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT'; END IF;
    RETURN public.marche_procurement_get(v_rid) || jsonb_build_object('replayed', true);
  END IF;

  IF v_req.status <> 'authorized' THEN RAISE EXCEPTION 'PROCUREMENT_NOT_OPEN'; END IF;
  IF v_new <= v_req.authorized_ceiling_gnf THEN RAISE EXCEPTION 'PROCUREMENT_CEILING_NOT_MONOTONIC'; END IF;
  IF v_new > (v_pol->>'max_ceiling_gnf')::bigint THEN RAISE EXCEPTION 'PROCUREMENT_CEILING_ABOVE_MAXIMUM'; END IF;
  v_delta := v_new - v_req.authorized_ceiling_gnf;

  SELECT COALESCE(max(seq),0) + 1 INTO v_seq FROM public.marche_procurement_authorizations WHERE request_id = v_rid;
  INSERT INTO public.marche_procurement_authorizations
    (request_id, seq, kind, amount_gnf, ceiling_before_gnf, ceiling_after_gnf, approved_by, client_request_id)
  VALUES (v_rid, v_seq, 'increase', v_delta, v_req.authorized_ceiling_gnf, v_new, v_uid, v_key)
  RETURNING id INTO v_auth_id;

  v_hold := public.chop_pay_customer_hold_place('marche_procurement', v_auth_id, v_delta,
              'marche_procurement', v_uid, false,
              jsonb_build_object('rail','marche_procurement','request_id',v_rid,'kind','increase'));
  IF COALESCE(v_hold->>'status','') <> 'held' THEN RAISE EXCEPTION 'PROCUREMENT_HOLD_FAILED'; END IF;

  UPDATE public.marche_procurement_requests
     SET authorized_ceiling_gnf = v_new, held_total_gnf = held_total_gnf + v_delta
   WHERE id = v_rid;
  INSERT INTO public.marche_procurement_events(request_id, event, payload, actor_user_id)
  VALUES (v_rid, 'ceiling_increased',
          jsonb_build_object('from_gnf', v_req.authorized_ceiling_gnf, 'to_gnf', v_new,
                             'additional_hold_gnf', v_delta), v_uid);

  RETURN public.marche_procurement_get(v_rid);
END $fn$;

CREATE OR REPLACE FUNCTION public.marche_procurement_cancel(p_request_id uuid, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_uid uuid := auth.uid(); v_req public.marche_procurement_requests;
  v_a record; v_rel jsonb; v_total bigint := 0;
BEGIN
  SELECT * INTO v_req FROM public.marche_procurement_requests WHERE id = p_request_id FOR UPDATE;
  IF v_req.id IS NULL THEN RAISE EXCEPTION 'PROCUREMENT_NOT_FOUND'; END IF;
  IF v_req.buyer_user_id <> v_uid AND NOT public._finance_privileged(v_uid) THEN
    RAISE EXCEPTION 'PROCUREMENT_NOT_AUTHORIZED';
  END IF;
  IF v_req.status = 'cancelled' THEN
    RETURN public.marche_procurement_get(p_request_id) || jsonb_build_object('replayed', true, 'released_gnf', 0);
  END IF;
  IF v_req.status = 'settled' THEN RAISE EXCEPTION 'PROCUREMENT_ALREADY_SETTLED'; END IF;

  FOR v_a IN SELECT id FROM public.marche_procurement_authorizations
              WHERE request_id = p_request_id ORDER BY seq LOOP
    v_rel := public._marche_procurement_release_internal(v_a.id, COALESCE(p_reason,'customer_cancelled'), v_uid);
    v_total := v_total + COALESCE((v_rel->>'released_gnf')::bigint, 0);
  END LOOP;

  UPDATE public.marche_procurement_requests
     SET status = 'cancelled', cancelled_at = now(), released_total_gnf = released_total_gnf + v_total
   WHERE id = p_request_id;
  INSERT INTO public.marche_procurement_events(request_id, event, payload, actor_user_id)
  VALUES (p_request_id, 'cancelled', jsonb_build_object('released_gnf', v_total, 'reason', p_reason), v_uid);

  RETURN public.marche_procurement_get(p_request_id) || jsonb_build_object('released_gnf', v_total);
END $fn$;

CREATE OR REPLACE FUNCTION public.marche_procurement_list(p_limit integer DEFAULT 20)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'PROCUREMENT_AUTH_REQUIRED'; END IF;
  RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'id', r.id, 'status', r.status, 'authorized_ceiling_gnf', r.authorized_ceiling_gnf,
      'actual_spend_gnf', r.actual_spend_gnf, 'line_count', r.line_count,
      'estimate_status', r.estimate_status, 'client_request_id', r.client_request_id,
      'created_at', r.created_at) ORDER BY r.created_at DESC), '[]'::jsonb)
    FROM (SELECT * FROM public.marche_procurement_requests
           WHERE buyer_user_id = v_uid ORDER BY created_at DESC
           LIMIT GREATEST(LEAST(COALESCE(p_limit,20), 100), 1)) r);
END $fn$;

-- ---------------------------------------------------------------
-- K. Internal actual-spend settlement (NOT client callable in R6.5)
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.marche_procurement_settle_internal(
  p_request_id uuid, p_actual_spend_gnf bigint, p_evidence_ref text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_uid uuid := auth.uid(); v_req public.marche_procurement_requests;
  v_a record; v_remaining bigint; v_take bigint; v_cap bigint := 0; v_rel bigint := 0; v_j jsonb;
BEGIN
  IF NOT public._finance_privileged(v_uid) THEN RAISE EXCEPTION 'PROCUREMENT_SETTLEMENT_FORBIDDEN'; END IF;
  IF p_actual_spend_gnf IS NULL OR p_actual_spend_gnf < 0 THEN
    RAISE EXCEPTION 'PROCUREMENT_ACTUAL_SPEND_INVALID';
  END IF;

  SELECT * INTO v_req FROM public.marche_procurement_requests WHERE id = p_request_id FOR UPDATE;
  IF v_req.id IS NULL THEN RAISE EXCEPTION 'PROCUREMENT_NOT_FOUND'; END IF;
  IF v_req.status = 'settled' THEN
    RETURN jsonb_build_object('status','already_settled','request_id',p_request_id,
      'actual_spend_gnf', v_req.actual_spend_gnf, 'captured_gnf', 0, 'released_gnf', 0);
  END IF;
  IF v_req.status = 'cancelled' THEN RAISE EXCEPTION 'PROCUREMENT_ALREADY_CANCELLED'; END IF;

  IF p_actual_spend_gnf > v_req.authorized_ceiling_gnf THEN
    RETURN jsonb_build_object('status','approval_required',
      'code','PROCUREMENT_AUTHORIZATION_REQUIRED',
      'request_id', p_request_id,
      'authorized_ceiling_gnf', v_req.authorized_ceiling_gnf,
      'requested_spend_gnf', p_actual_spend_gnf,
      'required_ceiling_gnf', p_actual_spend_gnf,
      'captured_gnf', 0, 'released_gnf', 0);
  END IF;

  v_remaining := p_actual_spend_gnf;
  FOR v_a IN SELECT id, amount_gnf FROM public.marche_procurement_authorizations
              WHERE request_id = p_request_id ORDER BY seq LOOP
    v_take := LEAST(v_remaining, v_a.amount_gnf);
    IF v_take > 0 THEN
      v_j := public._marche_procurement_capture_internal(v_a.id, v_take, v_uid);
      v_cap := v_cap + COALESCE((v_j->>'captured_gnf')::bigint, 0);
      v_remaining := v_remaining - v_take;
    END IF;
    v_j := public._marche_procurement_release_internal(v_a.id, 'procurement_unused_authorization', v_uid);
    v_rel := v_rel + COALESCE((v_j->>'released_gnf')::bigint, 0);
  END LOOP;

  UPDATE public.marche_procurement_requests
     SET status = 'settled', actual_spend_gnf = p_actual_spend_gnf, settled_at = now(),
         captured_total_gnf = captured_total_gnf + v_cap,
         released_total_gnf = released_total_gnf + v_rel
   WHERE id = p_request_id;
  INSERT INTO public.marche_procurement_events(request_id, event, payload, actor_user_id)
  VALUES (p_request_id, 'settled',
          jsonb_build_object('actual_spend_gnf', p_actual_spend_gnf, 'captured_gnf', v_cap,
                             'released_gnf', v_rel, 'evidence_ref', p_evidence_ref), v_uid);

  RETURN jsonb_build_object('status','settled','request_id',p_request_id,
    'actual_spend_gnf', p_actual_spend_gnf, 'captured_gnf', v_cap, 'released_gnf', v_rel,
    'authorized_ceiling_gnf', v_req.authorized_ceiling_gnf);
END $fn$;

CREATE OR REPLACE FUNCTION public.marche_procurement_observation_record(p jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_uid uuid := auth.uid(); v_o record; v_id uuid;
BEGIN
  IF NOT public._finance_privileged(v_uid) AND NOT public.marche_staple_can_manage(v_uid) THEN
    RAISE EXCEPTION 'PROCUREMENT_OBSERVATION_FORBIDDEN';
  END IF;
  SELECT o.id AS option_id, vv.id AS variant_id, c.id AS commodity_id
    INTO v_o
    FROM public.marche_staple_purchase_options o
    JOIN public.marche_staple_variants vv ON vv.id = o.variant_id
    JOIN public.marche_staple_commodities c ON c.id = vv.commodity_id
   WHERE c.code = p->>'commodity_code' AND vv.code = p->>'variant_code' AND o.code = p->>'option_code';
  IF v_o.option_id IS NULL THEN RAISE EXCEPTION 'PROCUREMENT_UNKNOWN_STAPLE'; END IF;
  IF COALESCE((p->>'observed_unit_price_gnf')::bigint, 0) <= 0 THEN
    RAISE EXCEPTION 'PROCUREMENT_OBSERVATION_PRICE_INVALID';
  END IF;
  INSERT INTO public.marche_procurement_price_observations
    (purchase_option_id, variant_id, commodity_id, market_id, observed_unit_price_gnf,
     observed_at, source_kind, source_ref, recorded_by)
  VALUES (v_o.option_id, v_o.variant_id, v_o.commodity_id, NULLIF(p->>'market_id','')::uuid,
     (p->>'observed_unit_price_gnf')::bigint,
     COALESCE(NULLIF(p->>'observed_at','')::timestamptz, now()),
     COALESCE(NULLIF(p->>'source_kind',''), 'ops_survey'), NULLIF(p->>'source_ref',''), v_uid)
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('status','recorded','id',v_id);
END $fn$;

-- ---------------------------------------------------------------
-- L. Grants — client may only reach the sanctioned RPC surface
-- ---------------------------------------------------------------
REVOKE ALL ON FUNCTION public._marche_procurement_policy() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._marche_procurement_option_estimate(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._marche_procurement_resolve(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._marche_procurement_fingerprint(jsonb, bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._marche_procurement_capture_internal(uuid, bigint, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._marche_procurement_release_internal(uuid, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.marche_procurement_settle_internal(uuid, bigint, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.marche_procurement_observation_record(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_procurement_quote(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_procurement_authorize(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_procurement_increase(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_procurement_cancel(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_procurement_get(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.marche_procurement_list(integer) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.marche_procurement_quote(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_procurement_authorize(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_procurement_increase(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_procurement_cancel(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_procurement_get(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_procurement_list(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_procurement_observation_record(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.marche_procurement_settle_internal(uuid, bigint, text) TO service_role;