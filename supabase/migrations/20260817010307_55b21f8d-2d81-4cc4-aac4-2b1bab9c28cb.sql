-- ============================================================================
-- 1. GENERIC CUSTOMER-HOLD SETTLEMENT PRIMITIVES (extracted, single source of
--    truth for wallet/hold/ledger mutation on a customer_payment hold).
--    Chop Pay merchant internals hard-require chop_pay_order_runtime, so they
--    cannot serve a non-merchant liability; these encode the SAME invariants
--    once and are the only place procurement money moves.
-- ============================================================================
CREATE OR REPLACE FUNCTION public._customer_hold_capture_internal(
  p_source_module text,
  p_source_id uuid,
  p_amount bigint,
  p_journal_key text,
  p_action text,
  p_credit_account text,
  p_credit_wallet_user uuid,          -- NULL => platform master wallet
  p_credit_wallet_type public.party_type,
  p_ledger_party_type public.party_type,
  p_ledger_party_user uuid,
  p_description text,
  p_mission_type text DEFAULT NULL,
  p_actor uuid DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $function$
DECLARE
  v_h public.mission_financial_holds; v_open bigint;
  v_cw public.wallets; v_target public.wallets;
BEGIN
  IF COALESCE(p_amount,0) <= 0 THEN RETURN jsonb_build_object('status','zero','captured_gnf',0); END IF;
  IF p_journal_key IS NULL OR btrim(p_journal_key) = '' THEN RAISE EXCEPTION 'LEDGER_KEY_REQUIRED'; END IF;

  IF EXISTS (SELECT 1 FROM public.ledger_journals WHERE journal_key = p_journal_key) THEN
    RETURN jsonb_build_object('status','already_captured','captured_gnf',0);
  END IF;

  SELECT * INTO v_h FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND kind = 'customer_payment' FOR UPDATE;
  IF v_h.id IS NULL THEN RAISE EXCEPTION 'CUSTOMER_HOLD_MISSING'; END IF;
  v_open := v_h.amount_gnf - v_h.captured_gnf - v_h.released_gnf;
  IF v_open < p_amount THEN
    RAISE EXCEPTION 'CUSTOMER_HOLD_INSUFFICIENT'
      USING DETAIL = format('open=%s requested=%s', v_open, p_amount);
  END IF;

  SELECT * INTO v_cw FROM public.wallets
   WHERE owner_user_id = v_h.party_user_id AND party_type = 'client' FOR UPDATE;
  IF v_cw.id IS NULL THEN RAISE EXCEPTION 'CUSTOMER_WALLET_MISSING'; END IF;
  UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - p_amount, 0),
                            balance_gnf = balance_gnf - p_amount, updated_at = now()
   WHERE id = v_cw.id;

  IF p_credit_wallet_user IS NOT NULL THEN
    INSERT INTO public.wallets (owner_user_id, party_type)
    VALUES (p_credit_wallet_user, p_credit_wallet_type) ON CONFLICT (owner_user_id, party_type) DO NOTHING;
    UPDATE public.wallets SET balance_gnf = balance_gnf + p_amount, updated_at = now()
     WHERE owner_user_id = p_credit_wallet_user AND party_type = p_credit_wallet_type
     RETURNING * INTO v_target;
  ELSE
    SELECT * INTO v_target FROM public.wallets WHERE party_type = 'master' FOR UPDATE LIMIT 1;
    IF v_target.id IS NULL THEN RAISE EXCEPTION 'MASTER_WALLET_MISSING'; END IF;
    UPDATE public.wallets SET balance_gnf = balance_gnf + p_amount, updated_at = now()
     WHERE id = v_target.id;
  END IF;

  INSERT INTO public.wallet_transactions
    (reference, type, status, amount_gnf, from_wallet_id, to_wallet_id, related_user_id,
     related_entity, description, metadata, completed_at)
  VALUES (p_journal_key, 'capture', 'completed', p_amount, v_cw.id, v_target.id, v_h.party_user_id,
     p_source_module || ':' || p_source_id::text, p_description,
     COALESCE(p_metadata,'{}'::jsonb) || jsonb_build_object('tender','chop_pay'), now());

  PERFORM public._ledger_post(p_journal_key, p_source_module, p_source_id, p_action,
    jsonb_build_array(
      jsonb_build_object('account','L_CUSTOMER_HOLD','amount_gnf',p_amount,
                         'party_type','client','party_user_id',v_h.party_user_id,
                         'memo','consume customer hold'),
      jsonb_build_object('account',p_credit_account,'amount_gnf',-p_amount,
                         'party_type', p_ledger_party_type, 'party_user_id', p_ledger_party_user,
                         'memo', p_description)),
    COALESCE(p_mission_type, v_h.mission_type), p_actor, COALESCE(v_h.policy_snapshot,'{}'::jsonb), v_h.is_sandbox);

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

  RETURN jsonb_build_object('status','captured','captured_gnf',p_amount);
END $function$;

CREATE OR REPLACE FUNCTION public._customer_hold_release_internal(
  p_source_module text,
  p_source_id uuid,
  p_journal_key text,
  p_action text,
  p_reason text DEFAULT NULL,
  p_mission_type text DEFAULT NULL,
  p_actor uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $function$
DECLARE v_h public.mission_financial_holds; v_open bigint; v_cw public.wallets;
BEGIN
  SELECT * INTO v_h FROM public.mission_financial_holds
   WHERE source_module = p_source_module AND source_id = p_source_id
     AND kind = 'customer_payment' FOR UPDATE;
  IF v_h.id IS NULL THEN RETURN jsonb_build_object('status','no_hold','released_gnf',0); END IF;
  v_open := v_h.amount_gnf - v_h.captured_gnf - v_h.released_gnf;
  IF v_open <= 0 THEN RETURN jsonb_build_object('status','already_resolved','released_gnf',0); END IF;

  SELECT * INTO v_cw FROM public.wallets
   WHERE owner_user_id = v_h.party_user_id AND party_type = 'client' FOR UPDATE;
  IF v_cw.id IS NULL THEN RAISE EXCEPTION 'CUSTOMER_WALLET_MISSING'; END IF;
  UPDATE public.wallets SET held_gnf = GREATEST(held_gnf - v_open, 0), updated_at = now()
   WHERE id = v_cw.id;
  UPDATE public.wallet_transactions SET status = 'cancelled', completed_at = now()
   WHERE id = v_h.hold_tx_id AND status = 'pending';

  PERFORM public._ledger_post(p_journal_key, p_source_module, p_source_id, p_action,
    jsonb_build_array(
      jsonb_build_object('account','L_CUSTOMER_HOLD','amount_gnf',v_open,
                         'party_type','client','party_user_id',v_h.party_user_id,'memo','release customer hold'),
      jsonb_build_object('account','L_CUSTOMER_CHOPPAY','amount_gnf',-v_open,
                         'party_type','client','party_user_id',v_h.party_user_id,'memo','restored to chop pay balance')),
    COALESCE(p_mission_type, v_h.mission_type), p_actor,
    COALESCE(v_h.policy_snapshot,'{}'::jsonb), v_h.is_sandbox, p_reason);

  UPDATE public.mission_financial_holds
     SET released_gnf = released_gnf + v_open,
         state = CASE WHEN captured_gnf > 0 THEN 'captured' ELSE 'released' END,
         reason = COALESCE(p_reason, reason), resolved_at = now(), resolved_by = p_actor
   WHERE id = v_h.id;

  RETURN jsonb_build_object('status','released','released_gnf',v_open);
END $function$;

REVOKE ALL ON FUNCTION public._customer_hold_capture_internal(text,uuid,bigint,text,text,text,uuid,public.party_type,public.party_type,uuid,text,text,uuid,jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._customer_hold_release_internal(text,uuid,text,text,text,text,uuid) FROM PUBLIC, anon, authenticated;

-- ============================================================================
-- 2. PROCUREMENT MONEY ADAPTERS ARE NOW THIN WRAPPERS (no wallet mutation)
-- ============================================================================
CREATE OR REPLACE FUNCTION public._marche_procurement_capture_internal(p_auth_id uuid, p_amount bigint, p_actor uuid DEFAULT NULL::uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $function$
DECLARE v_a public.marche_procurement_authorizations; v_buyer uuid; v_res jsonb;
BEGIN
  IF COALESCE(p_amount,0) <= 0 THEN RETURN jsonb_build_object('status','zero','captured_gnf',0); END IF;
  SELECT * INTO v_a FROM public.marche_procurement_authorizations WHERE id = p_auth_id FOR UPDATE;
  IF v_a.id IS NULL THEN RAISE EXCEPTION 'PROCUREMENT_AUTHORIZATION_MISSING'; END IF;
  SELECT buyer_user_id INTO v_buyer FROM public.marche_procurement_requests WHERE id = v_a.request_id;

  v_res := public._customer_hold_capture_internal(
    'marche_procurement', p_auth_id, p_amount,
    format('mproc-capture:%s', p_auth_id), 'capture_procurement_spend',
    'L_PROCUREMENT_FLOAT', NULL, NULL, 'client'::public.party_type, v_buyer,
    'Achat marché ChopChop (dépense réelle)', 'marche_procurement', p_actor,
    jsonb_build_object('purpose','procurement_spend','request_id', v_a.request_id));

  IF COALESCE((v_res->>'captured_gnf')::bigint,0) > 0 THEN
    UPDATE public.marche_procurement_authorizations
       SET captured_gnf = captured_gnf + (v_res->>'captured_gnf')::bigint WHERE id = p_auth_id;
  END IF;
  RETURN v_res;
END $function$;

CREATE OR REPLACE FUNCTION public._marche_procurement_release_internal(p_auth_id uuid, p_reason text DEFAULT NULL::text, p_actor uuid DEFAULT NULL::uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $function$
DECLARE v_a public.marche_procurement_authorizations; v_res jsonb;
BEGIN
  SELECT * INTO v_a FROM public.marche_procurement_authorizations WHERE id = p_auth_id FOR UPDATE;
  IF v_a.id IS NULL THEN RAISE EXCEPTION 'PROCUREMENT_AUTHORIZATION_MISSING'; END IF;

  v_res := public._customer_hold_release_internal(
    'marche_procurement', p_auth_id,
    format('mproc-release:%s', p_auth_id), 'release_procurement_authorization',
    p_reason, 'marche_procurement', p_actor);

  IF COALESCE((v_res->>'released_gnf')::bigint,0) > 0 THEN
    UPDATE public.marche_procurement_authorizations
       SET released_gnf = released_gnf + (v_res->>'released_gnf')::bigint WHERE id = p_auth_id;
  END IF;
  RETURN v_res;
END $function$;

-- ============================================================================
-- 3. NO INVENTED FLOOR, NO CUSTOMER-DECLARED BASIS
-- ============================================================================
CREATE OR REPLACE FUNCTION public._marche_procurement_policy()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $function$
  SELECT jsonb_build_object(
    'max_ceiling_gnf', COALESCE((SELECT (value->>'max_ceiling_gnf')::bigint
        FROM public.app_settings WHERE key = 'marche_procurement'), 20000000::bigint),
    'max_lines', COALESCE((SELECT (value->>'max_lines')::int
        FROM public.app_settings WHERE key = 'marche_procurement'), 25),
    'observation_window_hours', 336,
    'min_samples', 3,
    'currency', 'GNF',
    'disclaimer_fr', 'Estimation — le prix réel au marché peut varier.');
$function$;

CREATE OR REPLACE FUNCTION public._marche_procurement_resolve(p_lines jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $function$
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
      'sample_count_in_window', COALESCE((v_est->>'sample_count_in_window')::int,
                                         (v_est->>'sample_count')::int),
      'min_samples', (v_pol->>'min_samples')::int,
      'estimate_unavailable_reason', v_est->>'reason'));
  END LOOP;

  RETURN jsonb_build_object(
    'lines', v_out,
    'line_count', v_no,
    'item_count', v_items,
    'currency', 'GNF',
    'estimate_status', CASE WHEN v_all_ok THEN 'available' ELSE 'insufficient_data' END,
    'estimate_basis', CASE WHEN v_all_ok THEN 'observed_procurement' END,
    'estimated_subtotal_gnf', CASE WHEN v_all_ok THEN v_sub END,
    'estimate_confidence', CASE WHEN v_all_ok THEN v_conf END,
    'estimate_sample_count', CASE WHEN v_all_ok THEN v_samples END,
    'estimate_freshness_hours', CASE WHEN v_all_ok THEN v_fresh END,
    'estimate_unavailable_reason', CASE WHEN v_all_ok THEN NULL ELSE COALESCE(v_reason,'NO_RECENT_PROCUREMENT_OBSERVATIONS') END,
    'min_samples', (v_pol->>'min_samples')::int,
    'observation_window_hours', (v_pol->>'observation_window_hours')::int,
    'authorization_allowed', v_all_ok,
    'min_ceiling_gnf', CASE WHEN v_all_ok THEN v_sub END,
    'max_ceiling_gnf', (v_pol->>'max_ceiling_gnf')::bigint,
    'disclaimer_fr', v_pol->>'disclaimer_fr');
END $function$;

-- authorization now FAILS CLOSED without a server-supported estimate
CREATE OR REPLACE FUNCTION public.marche_procurement_authorize(p jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $function$
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

  -- R6.5 LAW: no trustworthy server estimate => no authorization, no hold, no request.
  IF v_res->>'estimate_status' <> 'available' THEN
    RAISE EXCEPTION 'PROCUREMENT_ESTIMATE_INSUFFICIENT_DATA'
      USING DETAIL = COALESCE(v_res->>'estimate_unavailable_reason','NO_RECENT_PROCUREMENT_OBSERVATIONS');
  END IF;

  IF v_ceiling < (v_res->>'min_ceiling_gnf')::bigint THEN
    RAISE EXCEPTION 'PROCUREMENT_CEILING_BELOW_ESTIMATE'
      USING DETAIL = format('ceiling=%s estimated_subtotal=%s', v_ceiling, v_res->>'min_ceiling_gnf');
  END IF;
  IF v_ceiling > (v_res->>'max_ceiling_gnf')::bigint THEN
    RAISE EXCEPTION 'PROCUREMENT_CEILING_ABOVE_MAXIMUM';
  END IF;

  INSERT INTO public.marche_procurement_requests
    (buyer_user_id, status, authorized_ceiling_gnf, estimate_status, estimate_basis,
     estimated_subtotal_gnf, estimate_confidence, estimate_sample_count, estimate_freshness_hours,
     estimate_unavailable_reason, line_count, item_count, client_request_id, request_fingerprint)
  VALUES (v_uid, 'authorized', v_ceiling, 'available', 'observed_procurement',
     (v_res->>'estimated_subtotal_gnf')::bigint,
     v_res->>'estimate_confidence',
     (v_res->>'estimate_sample_count')::int,
     (v_res->>'estimate_freshness_hours')::numeric,
     NULL,
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
          'estimated_subtotal_gnf', (v_res->>'estimated_subtotal_gnf')::bigint), v_uid);

  RETURN public.marche_procurement_get(v_id);
END $function$;

-- ============================================================================
-- 4. SCHEMA LAW: an insufficient-data / customer-declared request cannot exist
-- ============================================================================
ALTER TABLE public.marche_procurement_requests DROP CONSTRAINT IF EXISTS mpr_estimate_basis_chk;
ALTER TABLE public.marche_procurement_requests DROP CONSTRAINT IF EXISTS mpr_estimate_status_chk;
ALTER TABLE public.marche_procurement_requests DROP CONSTRAINT IF EXISTS mpr_estimate_coherence_chk;
ALTER TABLE public.marche_procurement_requests
  ADD CONSTRAINT mpr_estimate_basis_chk CHECK (estimate_basis = 'observed_procurement'),
  ADD CONSTRAINT mpr_estimate_status_chk CHECK (estimate_status = 'available'),
  ADD CONSTRAINT mpr_estimate_coherence_chk CHECK (
    estimated_subtotal_gnf IS NOT NULL AND estimated_subtotal_gnf > 0
    AND estimate_confidence IS NOT NULL AND estimate_sample_count IS NOT NULL
    AND estimate_unavailable_reason IS NULL),
  ADD CONSTRAINT mpr_ceiling_covers_estimate_chk CHECK (authorized_ceiling_gnf >= estimated_subtotal_gnf);

ALTER TABLE public.marche_procurement_request_items DROP CONSTRAINT IF EXISTS mpri_estimate_source_chk;
ALTER TABLE public.marche_procurement_request_items DROP CONSTRAINT IF EXISTS mpri_estimate_coherence_chk;
ALTER TABLE public.marche_procurement_request_items
  ADD CONSTRAINT mpri_estimate_source_chk CHECK (estimate_source = 'observed_procurement'),
  ADD CONSTRAINT mpri_estimate_coherence_chk CHECK (
    estimated_unit_price_gnf > 0 AND estimated_line_total_gnf > 0 AND estimate_sample_count > 0);