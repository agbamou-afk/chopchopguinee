-- ============================================================
-- R5 CLOSEOUT — corrective pass (no schema rebuild)
-- ============================================================

-- 1) QUOTE MENU + ORDERABILITY + DISTANCE TRUTH
CREATE OR REPLACE FUNCTION public.repas_quote_preview(
  p_restaurant_id uuid, p_items jsonb, p_fulfillment text,
  p_delivery_lat double precision DEFAULT NULL::double precision,
  p_delivery_lng double precision DEFAULT NULL::double precision)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid(); v_r public.food_restaurants%ROWTYPE;
  v_it jsonb; v_mi public.food_menu_items%ROWTYPE; v_qty int;
  v_sub bigint := 0; v_pickup boolean; v_eff jsonb;
  v_del bigint; v_fee bigint; v_max numeric; v_dist numeric; v_eligible boolean := true;
  v_reason text := NULL; v_geo boolean := false; v_verified boolean := false;
  v_open boolean; v_orderable boolean := true;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF p_fulfillment NOT IN ('pickup','delivery') THEN RAISE EXCEPTION 'INVALID_FULFILLMENT'; END IF;
  v_pickup := (p_fulfillment = 'pickup');

  SELECT * INTO v_r FROM public.food_restaurants WHERE id = p_restaurant_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'RESTAURANT_NOT_FOUND'; END IF;
  -- categorical refusal at commitment => categorical refusal at quote
  IF v_r.status <> 'active' THEN RAISE EXCEPTION 'RESTAURANT_NOT_ORDERABLE'; END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'EMPTY_CART';
  END IF;
  IF jsonb_array_length(p_items) > 40 THEN RAISE EXCEPTION 'CART_TOO_LARGE'; END IF;

  FOR v_it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_qty := COALESCE((v_it->>'qty')::int, 0);
    IF v_qty <= 0 OR v_qty > 50 THEN RAISE EXCEPTION 'INVALID_QUANTITY'; END IF;
    SELECT * INTO v_mi FROM public.food_menu_items WHERE id = (v_it->>'menu_item_id')::uuid;
    IF NOT FOUND THEN RAISE EXCEPTION 'MENU_ITEM_NOT_FOUND'; END IF;
    IF v_mi.restaurant_id <> p_restaurant_id THEN RAISE EXCEPTION 'ITEM_WRONG_RESTAURANT'; END IF;
    -- canonical parity with repas_order_create
    IF NOT COALESCE(v_mi.is_available,false) THEN RAISE EXCEPTION 'ITEM_UNAVAILABLE'; END IF;
    v_sub := v_sub + (v_mi.price_gnf::bigint * v_qty);
  END LOOP;

  v_eff := public.repas_pricing_effective(p_fulfillment, now());
  v_del := COALESCE((v_eff->>'customer_delivery_fee_gnf')::bigint, 0);
  v_fee := public.repas_platform_fee_gnf(v_sub, v_del, v_eff->>'fee_basis',
                                         (v_eff->>'platform_fee_bps')::int);

  -- Non-categorical (operational) truths surface as ineligibility, never as a price lie.
  v_open := COALESCE(v_r.is_open, false);
  IF NOT v_open THEN
    v_orderable := false; v_eligible := false; v_reason := 'RESTAURANT_CLOSED';
  ELSIF v_pickup AND NOT COALESCE(v_r.pickup_available,false) THEN
    v_orderable := false; v_eligible := false; v_reason := 'PICKUP_NOT_AVAILABLE';
  ELSIF NOT v_pickup AND NOT COALESCE(v_r.delivery_available,false) THEN
    v_orderable := false; v_eligible := false; v_reason := 'DELIVERY_NOT_AVAILABLE';
  END IF;

  IF NOT v_pickup THEN
    v_geo  := (v_r.latitude IS NOT NULL AND v_r.longitude IS NOT NULL);
    v_max  := NULLIF(v_eff->>'delivery_max_distance_km','')::numeric;
    v_dist := public.repas_delivery_distance_km(p_restaurant_id, p_delivery_lat, p_delivery_lng);
    v_verified := (v_dist IS NOT NULL);
    IF v_max IS NOT NULL THEN
      -- A configured zone means distance MUST be server-verifiable. Fail closed.
      IF NOT v_geo THEN
        v_eligible := false;
        v_reason := COALESCE(v_reason, 'DELIVERY_DISTANCE_UNVERIFIABLE');
      ELSIF p_delivery_lat IS NULL OR p_delivery_lng IS NULL THEN
        v_eligible := false; v_reason := COALESCE(v_reason, 'DESTINATION_REQUIRED');
      ELSIF v_dist IS NULL THEN
        v_eligible := false; v_reason := COALESCE(v_reason, 'DELIVERY_DISTANCE_UNVERIFIABLE');
      ELSIF v_dist > v_max THEN
        v_eligible := false; v_reason := COALESCE(v_reason, 'OUTSIDE_DELIVERY_ZONE');
      END IF;
    END IF;
  ELSE
    v_verified := true;  -- pickup needs no distance
  END IF;

  RETURN jsonb_build_object(
    'fulfillment', p_fulfillment,
    'merchandise_subtotal_gnf', v_sub,
    'base_delivery_fee_gnf', COALESCE((v_eff->>'base_delivery_fee_gnf')::bigint,0),
    'delivery_fee_gnf', v_del,
    'promo_discount_gnf', COALESCE((v_eff->>'promo_discount_gnf')::bigint,0),
    'promotion_id', v_eff->>'promotion_id',
    'promotion_name', v_eff->>'promotion_name',
    'platform_fee_gnf', v_fee,
    'order_total_gnf', v_sub + v_del + v_fee,
    'courier_payout_gnf', COALESCE((v_eff->>'courier_payout_gnf')::bigint,0),
    'delivery_distance_km', v_dist,
    'delivery_max_distance_km', v_max,
    'distance_verified', v_verified,
    'distance_method', 'geodesic_straight_line',
    'delivery_eligible', v_eligible,
    'ineligible_reason', v_reason,
    'restaurant_open', v_open,
    'orderable', v_orderable,
    'pickup_available', COALESCE(v_r.pickup_available,false),
    'delivery_available', COALESCE(v_r.delivery_available,false),
    'chop_pay_enabled', public._finance_flag('chop_pay_checkout_enabled'),
    'cash_enabled', public._finance_flag('cash_order_funding_enabled'),
    'cash_pickup_supported', false,
    'policy_id', v_eff->>'policy_id',
    'policy_effective_from', v_eff->>'policy_effective_from',
    'transaction_fee_bps', (v_eff->>'platform_fee_bps')::int);
END; $function$;

REVOKE EXECUTE ON FUNCTION public.repas_quote_preview(uuid,jsonb,text,double precision,double precision) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.repas_quote_preview(uuid,jsonb,text,double precision,double precision) TO authenticated;

-- 2) COMMITMENT: an unmapped restaurant under a configured zone is unverifiable, not "allowed"
DO $mig$
DECLARE v_def text; v_old text; v_new text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc
   WHERE proname='repas_order_create' AND pronamespace='public'::regnamespace;
  v_old := '    ELSE' || E'\n' ||
           '      -- Restaurant has no mapped location yet: distance stays honestly unknown.';
  v_new := '    ELSIF v_max IS NOT NULL THEN' || E'\n' ||
           '      RAISE EXCEPTION ''DELIVERY_DISTANCE_UNVERIFIABLE''' || E'\n' ||
           '        USING DETAIL = ''restaurant location is not mapped; server distance cannot be verified'';' || E'\n' ||
           '    ELSE' || E'\n' ||
           '      -- No configured zone: distance stays honestly unknown, never fabricated.';
  IF position(v_old in v_def) = 0 THEN
    RAISE EXCEPTION 'R5_CLOSEOUT_PATCH_ANCHOR_MISSING: repas_order_create';
  END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $mig$;

-- 3) PROMOTION SHAPE — delivery scope only for R5
UPDATE public.repas_pricing_promotions SET fulfillment_scope = 'delivery'
 WHERE fulfillment_scope <> 'delivery';
ALTER TABLE public.repas_pricing_promotions DROP CONSTRAINT IF EXISTS repas_promo_scope_ck;
ALTER TABLE public.repas_pricing_promotions
  ADD CONSTRAINT repas_promo_scope_ck CHECK (fulfillment_scope = 'delivery');

CREATE OR REPLACE FUNCTION public.admin_set_repas_promotion(
  p_name text, p_reason text, p_starts_at timestamp with time zone,
  p_ends_at timestamp with time zone, p_fulfillment_scope text DEFAULT 'delivery'::text,
  p_delivery_fee_override_gnf bigint DEFAULT NULL::bigint,
  p_delivery_discount_gnf bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_caller uuid := auth.uid(); v_row public.repas_pricing_promotions; v_clash int;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.is_god_admin(v_caller) THEN
    RAISE EXCEPTION 'Only a God Admin can change Repas promotions';
  END IF;
  IF length(btrim(COALESCE(p_reason,''))) < 5 THEN RAISE EXCEPTION 'REASON_REQUIRED'; END IF;
  IF length(btrim(COALESCE(p_name,''))) < 3 THEN RAISE EXCEPTION 'NAME_REQUIRED'; END IF;
  IF p_ends_at <= p_starts_at THEN RAISE EXCEPTION 'INVALID_PROMO_WINDOW'; END IF;
  IF p_ends_at <= now() THEN RAISE EXCEPTION 'PROMO_ALREADY_EXPIRED'; END IF;
  IF num_nonnulls(p_delivery_fee_override_gnf, p_delivery_discount_gnf) <> 1 THEN
    RAISE EXCEPTION 'PROMO_SHAPE_INVALID'
      USING DETAIL = 'provide exactly one of override or discount';
  END IF;
  IF COALESCE(p_delivery_fee_override_gnf, 0) < 0 OR COALESCE(p_delivery_discount_gnf, 0) < 0 THEN
    RAISE EXCEPTION 'PROMO_NEGATIVE_AMOUNT'; END IF;
  -- R5 promotions only move the customer delivery price. A pickup/both scope would
  -- silently do nothing, so it is refused rather than advertised.
  IF COALESCE(p_fulfillment_scope,'delivery') <> 'delivery' THEN
    RAISE EXCEPTION 'INVALID_FULFILLMENT_SCOPE'
      USING DETAIL = 'R5 promotions apply to delivery pricing only';
  END IF;

  SELECT count(*) INTO v_clash FROM public.repas_pricing_promotions
   WHERE enabled AND ends_at > p_starts_at AND starts_at < p_ends_at
     AND fulfillment_scope = 'delivery';
  IF v_clash > 0 THEN
    RAISE EXCEPTION 'PROMO_WINDOW_OVERLAP'
      USING DETAIL = 'an enabled promotion already covers part of this window';
  END IF;

  INSERT INTO public.repas_pricing_promotions(
      name, reason, fulfillment_scope, delivery_fee_override_gnf, delivery_discount_gnf,
      starts_at, ends_at, created_by)
  VALUES (btrim(p_name), btrim(p_reason), 'delivery',
          p_delivery_fee_override_gnf, p_delivery_discount_gnf,
          p_starts_at, p_ends_at, v_caller)
  RETURNING * INTO v_row;

  INSERT INTO public.audit_logs(actor_user_id, module, action, target_type, target_id, after, note)
  VALUES (v_caller, 'pricing', 'repas_promotion.create', 'repas_pricing_promotions',
          v_row.id::text, to_jsonb(v_row), btrim(p_reason));

  RETURN jsonb_build_object('ok', true, 'promotion_id', v_row.id);
END; $function$;

REVOKE EXECUTE ON FUNCTION public.admin_set_repas_promotion(text,text,timestamptz,timestamptz,text,bigint,bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_repas_promotion(text,text,timestamptz,timestamptz,text,bigint,bigint) TO authenticated;

-- 4) LEGACY HELPER — policy-driven, deprecated, no hardcoded product law
CREATE OR REPLACE FUNCTION public.repas_delivery_earning_gnf()
 RETURNS bigint
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE((SELECT courier_payout_gnf FROM public.finance_policy_at('repas', now())), 0)::bigint
$function$;

COMMENT ON FUNCTION public.repas_delivery_earning_gnf() IS
  'DEPRECATED (R5). Reads the effective repas policy courier_payout_gnf. Production paths use the frozen per-order courier_payout_gnf. No hardcoded amount is product law.';

-- 5) R1-R4 HARNESS — map fixtures, drop the "15 000 is truth" wording
DO $mig$
DECLARE v_def text; v_out text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO v_def FROM pg_proc
   WHERE proname='_qa_node3_repas_r1_r4' AND pronamespace='public'::regnamespace;
  v_out := v_def;
  v_out := replace(v_out,
    'is_open, delivery_available, pickup_available, choppay_enabled, prep_time_min)',
    'is_open, delivery_available, pickup_available, choppay_enabled, prep_time_min, latitude, longitude)');
  v_out := replace(v_out,
    '''active'', true, true, true, true, 20)',
    '''active'', true, true, true, true, 20, 9.5350, -13.6800)');
  v_out := replace(v_out,
    'delivery_available, pickup_available, prep_time_min)' || E'\n',
    'delivery_available, pickup_available, prep_time_min, latitude, longitude)' || E'\n');
  v_out := replace(v_out,
    '''active'', false, true, true, 20)',
    '''active'', false, true, true, 20, 9.5360, -13.6810)');
  v_out := replace(v_out,
    'C0.2 courier earning is the server snapshot (15 000 GNF)',
    'C0.2 courier earning equals the policy-driven courier payout (no hardcoded amount)');
  IF v_out = v_def THEN
    RAISE EXCEPTION 'R5_CLOSEOUT_PATCH_ANCHOR_MISSING: _qa_node3_repas_r1_r4';
  END IF;
  EXECUTE v_out;
END $mig$;