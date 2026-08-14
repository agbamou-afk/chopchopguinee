-- =====================================================================
-- Node 3 Repas R7 — canonical tracking + receipt read models
-- Additive, read-only. No write/economic/custody engine is modified.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Role-shaped mission earning read (replaces raw column access)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.mission_earnings(p_mission_ids uuid[])
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT COALESCE(jsonb_object_agg(m.id::text, COALESCE(m.estimated_earning_gnf, 0)), '{}'::jsonb)
  FROM public.missions m
  WHERE auth.uid() IS NOT NULL
    AND m.id = ANY(COALESCE(p_mission_ids, '{}'::uuid[]))
    AND (
      m.courier_id = auth.uid()
      OR (
        m.courier_id IS NULL
        AND m.state = 'assigned'
        AND public.driver_has_capability(auth.uid(), public.mission_required_capability(m.type))
      )
      OR public._finance_privileged(auth.uid())
    );
$$;

REVOKE ALL ON FUNCTION public.mission_earnings(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mission_earnings(uuid[]) TO authenticated;

-- ---------------------------------------------------------------------
-- 2. repas_order_tracking — canonical, participant-authorized, role-shaped
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.repas_order_tracking(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_o public.food_orders%ROWTYPE;
  v_r public.food_restaurants%ROWTYPE;
  v_m public.missions%ROWTYPE;
  v_role text;
  v_pickup boolean;
  v_terminal boolean;
  v_terminal_reason text := NULL;
  v_engine_state text := NULL;
  v_dispute_reason text := NULL;
  v_cash_due bigint := NULL;
  v_actions text[] := '{}';
  v_custody jsonb;
  v_pending text := NULL;
  v_courier jsonb := NULL;
  v_customer jsonb := NULL;
  v_base jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  SELECT * INTO v_o FROM public.food_orders WHERE id = p_order_id;
  IF v_o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  SELECT * INTO v_r FROM public.food_restaurants WHERE id = v_o.restaurant_id;

  v_pickup := (v_o.fulfillment::text = 'pickup');

  IF NOT v_pickup THEN
    SELECT * INTO v_m FROM public.missions
     WHERE ref_food_order_id = p_order_id
     ORDER BY created_at DESC LIMIT 1;
  END IF;

  -- Participant authorization
  IF v_uid = v_o.user_id THEN
    v_role := 'customer';
  ELSIF v_uid = v_r.owner_user_id THEN
    v_role := 'merchant';
  ELSIF v_m.id IS NOT NULL AND v_uid = v_m.courier_id THEN
    v_role := 'courier';
  ELSIF public._finance_privileged(v_uid) THEN
    v_role := 'finance';
  ELSE
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  -- Engine truth (state + dispute), never re-derived client-side
  SELECT state, dispute_reason INTO v_engine_state, v_dispute_reason
    FROM public.chop_pay_order_runtime
   WHERE source_module = 'repas' AND source_id = p_order_id;
  IF v_engine_state IS NULL THEN
    SELECT state, dispute_reason, cash_due_gnf
      INTO v_engine_state, v_dispute_reason, v_cash_due
      FROM public.cash_order_runtime
     WHERE source_module = 'repas' AND source_id = p_order_id;
  END IF;

  v_terminal := v_o.state::text IN ('completed','cancelled');
  IF v_o.state::text = 'cancelled' THEN
    v_terminal_reason := COALESCE(v_dispute_reason, 'ORDER_CANCELLED');
  ELSIF v_engine_state = 'disputed' THEN
    v_terminal_reason := COALESCE(v_dispute_reason, 'ORDER_DISPUTED');
  ELSIF NOT v_pickup AND v_m.id IS NOT NULL AND v_m.state::text = 'failed' THEN
    v_terminal_reason := COALESCE(v_m.issue_reason, 'DELIVERY_FAILED');
  END IF;

  -- Custody truth (R6), safe projection only
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'kind', c.kind,
           'consumed', c.consumed_at IS NOT NULL,
           'locked', c.locked_at IS NOT NULL,
           'holder_is_self', c.holder_user_id = v_uid)), '[]'::jsonb)
    INTO v_custody
    FROM public.repas_custody_credentials c
   WHERE c.order_id = p_order_id;

  SELECT c.kind INTO v_pending
    FROM public.repas_custody_credentials c
   WHERE c.order_id = p_order_id
     AND c.consumed_at IS NULL
     AND c.locked_at IS NULL
   ORDER BY c.created_at DESC LIMIT 1;

  -- Server-derived merchant next actions (no client guessing)
  IF v_role IN ('merchant','finance') AND NOT v_terminal THEN
    v_actions := CASE v_o.state::text
      WHEN 'placed'    THEN ARRAY['accept','reject']
      WHEN 'confirmed' THEN ARRAY['prepare','reject']
      WHEN 'preparing' THEN ARRAY['ready']
      WHEN 'ready'     THEN CASE WHEN v_pickup THEN ARRAY['pickup_collection'] ELSE '{}'::text[] END
      ELSE '{}'::text[]
    END;
  END IF;

  -- Contact projections
  IF v_role IN ('customer','finance') AND v_m.id IS NOT NULL AND v_m.courier_id IS NOT NULL AND NOT v_terminal THEN
    SELECT jsonb_build_object('full_name', p.full_name, 'phone', p.phone)
      INTO v_courier FROM public.profiles p WHERE p.user_id = v_m.courier_id;
  END IF;
  IF v_role IN ('merchant','courier','finance') THEN
    SELECT jsonb_build_object('full_name', p.full_name, 'phone', p.phone)
      INTO v_customer FROM public.profiles p WHERE p.user_id = v_o.user_id;
  END IF;

  v_base := jsonb_build_object(
    'order_id', v_o.id,
    'viewer_role', v_role,
    'state', v_o.state::text,
    'fulfillment', v_o.fulfillment::text,
    'terminal', v_terminal,
    'terminal_reason', v_terminal_reason,
    'engine_state', v_engine_state,
    'restaurant', jsonb_build_object(
      'id', v_r.id, 'name', v_r.name, 'district', v_r.district,
      'prep_time_min', v_r.prep_time_min),
    'created_at', v_o.created_at,
    'updated_at', v_o.updated_at,
    'completed_at', v_o.completed_at,
    'custody', jsonb_build_object(
      'credentials', v_custody,
      'pending_kind', v_pending),
    'mission', CASE
      WHEN v_pickup OR v_m.id IS NULL THEN NULL
      ELSE jsonb_build_object(
        'id', v_m.id,
        'state', v_m.state::text,
        'courier_assigned', v_m.courier_id IS NOT NULL,
        'pickup_confirmed_at', v_m.pickup_confirmed_at,
        'dropoff_confirmed_at', v_m.dropoff_confirmed_at)
    END);

  IF v_role = 'customer' THEN
    RETURN v_base || jsonb_build_object(
      'payment_method', v_o.payment_method::text,
      'payment_status', v_o.payment_status,
      'order_total_gnf', COALESCE(v_o.order_total_gnf, v_o.subtotal_gnf),
      'delivery_address', v_o.delivery_address,
      'courier', v_courier);
  ELSIF v_role = 'courier' THEN
    RETURN v_base || jsonb_build_object(
      'payment_method', v_o.payment_method::text,
      'cash_due_gnf', v_cash_due,
      'customer', v_customer,
      'delivery_address', v_o.delivery_address,
      'pickup_address', v_m.pickup_address);
  ELSE
    RETURN v_base || jsonb_build_object(
      'payment_method', v_o.payment_method::text,
      'payment_status', v_o.payment_status,
      'allowed_actions', to_jsonb(v_actions),
      'customer', v_customer,
      'merchandise_subtotal_gnf', v_o.subtotal_gnf,
      'delivery_address', v_o.delivery_address);
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.repas_order_tracking(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.repas_order_tracking(uuid) TO authenticated;

-- ---------------------------------------------------------------------
-- 3. repas_order_receipt — frozen, immutable, itemized truth
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.repas_order_receipt(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_o public.food_orders%ROWTYPE;
  v_r public.food_restaurants%ROWTYPE;
  v_m public.missions%ROWTYPE;
  v_role text;
  v_items jsonb;
  v_lines_total bigint := 0;
  v_promo_name text := NULL;
  v_total bigint;
  v_merch bigint;
  v_del bigint;
  v_fee bigint;
  v_custody jsonb;
  v_payload jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;

  SELECT * INTO v_o FROM public.food_orders WHERE id = p_order_id;
  IF v_o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  SELECT * INTO v_r FROM public.food_restaurants WHERE id = v_o.restaurant_id;
  SELECT * INTO v_m FROM public.missions
   WHERE ref_food_order_id = p_order_id ORDER BY created_at DESC LIMIT 1;

  IF v_uid = v_o.user_id THEN v_role := 'customer';
  ELSIF v_uid = v_r.owner_user_id THEN v_role := 'merchant';
  ELSIF v_m.id IS NOT NULL AND v_uid = v_m.courier_id THEN v_role := 'courier';
  ELSIF public._finance_privileged(v_uid) THEN v_role := 'finance';
  ELSE RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'name', i.name_snapshot,
           'qty', i.qty,
           'unit_price_gnf', i.unit_price_gnf,
           'line_total_gnf', i.unit_price_gnf * i.qty) ORDER BY i.created_at, i.id), '[]'::jsonb),
         COALESCE(SUM(i.unit_price_gnf * i.qty), 0)
    INTO v_items, v_lines_total
    FROM public.food_order_items i
   WHERE i.order_id = p_order_id;

  IF v_o.promotion_id IS NOT NULL THEN
    SELECT name INTO v_promo_name FROM public.repas_pricing_promotions WHERE id = v_o.promotion_id;
  END IF;

  v_merch := COALESCE(v_o.subtotal_gnf, 0);
  v_del   := COALESCE(v_o.delivery_fee_gnf, 0);
  v_fee   := COALESCE(v_o.platform_fee_gnf, 0);
  v_total := COALESCE(v_o.order_total_gnf, v_merch + v_del + v_fee);

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'boundary', e.boundary,
           'method', e.method,
           'occurred_at', e.occurred_at) ORDER BY e.occurred_at), '[]'::jsonb)
    INTO v_custody
    FROM public.repas_custody_events e
   WHERE e.order_id = p_order_id;

  v_payload := jsonb_build_object(
    'order_id', v_o.id,
    'viewer_role', v_role,
    'restaurant', jsonb_build_object('id', v_r.id, 'name', v_r.name, 'district', v_r.district),
    'fulfillment', v_o.fulfillment::text,
    'state', v_o.state::text,
    'payment_method', v_o.payment_method::text,
    'payment_status', v_o.payment_status,
    'created_at', v_o.created_at,
    'paid_at', v_o.paid_at,
    'completed_at', v_o.completed_at,
    'items', v_items,
    'merchandise_subtotal_gnf', v_merch,
    'items_line_total_gnf', v_lines_total,
    'base_delivery_fee_gnf', COALESCE(v_o.base_delivery_fee_gnf, 0),
    'promo_discount_gnf', COALESCE(v_o.promo_discount_gnf, 0),
    'promotion_name', v_promo_name,
    'delivery_fee_gnf', v_del,
    'platform_fee_gnf', v_fee,
    'order_total_gnf', v_total,
    'cancelled', v_o.state::text = 'cancelled',
    'custody_timeline', v_custody,
    'totals_reconcile', (v_merch + v_del + v_fee = v_total) AND (v_lines_total = v_merch));

  IF v_role IN ('courier','finance') THEN
    v_payload := v_payload || jsonb_build_object(
      'courier_payout_gnf', COALESCE(v_o.courier_payout_gnf, 0));
  END IF;

  RETURN v_payload;
END;
$$;

REVOKE ALL ON FUNCTION public.repas_order_receipt(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.repas_order_receipt(uuid) TO authenticated;

-- ---------------------------------------------------------------------
-- 4. Raw read-surface hardening — private finance columns
--    RLS rows stay unchanged; only column privileges narrow.
-- ---------------------------------------------------------------------
REVOKE SELECT (courier_payout_gnf, pricing_policy_id, promotion_id, pricing_snapshot)
  ON public.food_orders FROM authenticated, anon;

REVOKE SELECT (estimated_earning_gnf)
  ON public.missions FROM authenticated, anon;