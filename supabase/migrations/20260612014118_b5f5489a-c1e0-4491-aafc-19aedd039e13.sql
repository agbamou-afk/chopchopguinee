
-- Phase 6B: Repas Capture + Merchant Settlement

-- 1. Restaurant <-> merchant_store linkage (nullable, no auto-guessing).
ALTER TABLE public.food_restaurants
  ADD COLUMN IF NOT EXISTS merchant_store_id uuid NULL
    REFERENCES public.merchant_stores(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_food_restaurants_merchant_store_id
  ON public.food_restaurants(merchant_store_id);

-- 2. food_orders capture / settlement tracking.
ALTER TABLE public.food_orders
  ADD COLUMN IF NOT EXISTS paid_at timestamptz NULL,
  ADD COLUMN IF NOT EXISTS settlement_state text NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS settlement_tx_id uuid NULL,
  ADD COLUMN IF NOT EXISTS captured_intent_id uuid NULL;

-- 3. Secure capture + settle RPC.
CREATE OR REPLACE FUNCTION public.repas_capture_and_settle_order(
  p_food_order_id uuid,
  p_reason text DEFAULT 'Repas order completed'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller text := current_user;
  v_order public.food_orders%ROWTYPE;
  v_intent public.payment_intents%ROWTYPE;
  v_captured public.payment_intents%ROWTYPE;
  v_restaurant_merchant_store uuid;
  v_settlement_tx public.wallet_transactions%ROWTYPE;
  v_amount bigint;
  v_settlement_state text;
  v_reference text;
BEGIN
  -- Trusted-context only.
  IF v_caller NOT IN ('service_role', 'postgres', 'supabase_admin')
     AND NOT (auth.uid() IS NOT NULL AND public.has_role(auth.uid(), 'admin'::app_role))
  THEN
    RAISE EXCEPTION 'forbidden_trusted_only' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_order FROM public.food_orders WHERE id = p_food_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'food_order_not_found' USING ERRCODE = 'P0002';
  END IF;

  -- Only CHOP Wallet orders settle to merchant via this rail.
  IF v_order.payment_method <> 'wallet' THEN
    RETURN jsonb_build_object(
      'ok', false,
      'reason', 'not_wallet_order',
      'food_order_id', v_order.id,
      'payment_method', v_order.payment_method
    );
  END IF;

  -- Already paid + settled => idempotent return.
  IF v_order.payment_status = 'paid' AND v_order.settlement_state = 'settled' THEN
    RETURN jsonb_build_object(
      'ok', true,
      'idempotent', true,
      'food_order_id', v_order.id,
      'payment_status', v_order.payment_status,
      'settlement_state', v_order.settlement_state,
      'captured_intent_id', v_order.captured_intent_id,
      'settlement_tx_id', v_order.settlement_tx_id
    );
  END IF;

  -- Locate the linked payment intent.
  SELECT * INTO v_intent
  FROM public.payment_intents
  WHERE source_module = 'repas'
    AND source_id = v_order.id
    AND payer_user_id = v_order.user_id
  ORDER BY created_at DESC
  LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'no_payment_intent', 'food_order_id', v_order.id);
  END IF;

  -- Must be authorized (processing) or already confirmed.
  IF v_intent.state NOT IN ('processing', 'confirmed') THEN
    RETURN jsonb_build_object(
      'ok', false,
      'reason', 'payment_not_authorized',
      'food_order_id', v_order.id,
      'intent_state', v_intent.state
    );
  END IF;

  -- Capture if still processing.
  IF v_intent.state = 'processing' THEN
    v_captured := public.choppay_capture_payment_intent(v_intent.id, p_reason);
  ELSE
    v_captured := v_intent;
  END IF;

  -- Mark order paid (trigger allows service_role/admin/postgres).
  UPDATE public.food_orders
     SET payment_status = 'paid',
         paid_at = COALESCE(paid_at, now()),
         captured_intent_id = v_captured.id,
         updated_at = now()
   WHERE id = v_order.id
   RETURNING * INTO v_order;

  -- Resolve merchant store (from intent metadata or restaurant link).
  v_restaurant_merchant_store := v_captured.merchant_store_id;
  IF v_restaurant_merchant_store IS NULL THEN
    SELECT merchant_store_id INTO v_restaurant_merchant_store
    FROM public.food_restaurants WHERE id = v_order.restaurant_id;
  END IF;

  -- Net merchant amount = subtotal (no platform fee modeled yet; delivery fee not stored on order).
  v_amount := v_order.subtotal_gnf;

  IF v_restaurant_merchant_store IS NULL OR v_amount IS NULL OR v_amount <= 0 THEN
    v_settlement_state := 'needs_review';
    UPDATE public.food_orders
       SET settlement_state = v_settlement_state, updated_at = now()
     WHERE id = v_order.id;
    RETURN jsonb_build_object(
      'ok', true,
      'captured', true,
      'settled', false,
      'reason', CASE WHEN v_restaurant_merchant_store IS NULL THEN 'missing_merchant_store_id' ELSE 'invalid_amount' END,
      'food_order_id', v_order.id,
      'captured_intent_id', v_captured.id,
      'payment_status', 'paid',
      'settlement_state', v_settlement_state
    );
  END IF;

  -- Idempotent merchant settlement (reference uniqueness enforced inside wallet_settle_merchant_revenue).
  v_reference := 'repas_merchant_revenue:' || v_order.id::text;
  v_settlement_tx := public.wallet_settle_merchant_revenue(
    p_source_module      := 'repas',
    p_source_id          := v_order.id,
    p_merchant_store_id  := v_restaurant_merchant_store,
    p_amount_gnf         := v_amount,
    p_reference          := v_reference,
    p_description        := 'Paiement Repas reçu',
    p_metadata           := jsonb_build_object(
      'food_order_id', v_order.id,
      'restaurant_id', v_order.restaurant_id,
      'merchant_store_id', v_restaurant_merchant_store,
      'subtotal_gnf', v_order.subtotal_gnf,
      'net_merchant_amount_gnf', v_amount,
      'payment_intent_id', v_captured.id,
      'captured_tx_id', v_captured.captured_tx_id,
      'created_by_function', 'repas_capture_and_settle_order'
    )
  );

  UPDATE public.food_orders
     SET settlement_state = 'settled',
         settlement_tx_id = v_settlement_tx.id,
         updated_at = now()
   WHERE id = v_order.id;

  RETURN jsonb_build_object(
    'ok', true,
    'captured', true,
    'settled', true,
    'food_order_id', v_order.id,
    'captured_intent_id', v_captured.id,
    'settlement_tx_id', v_settlement_tx.id,
    'merchant_store_id', v_restaurant_merchant_store,
    'amount_gnf', v_amount,
    'payment_status', 'paid',
    'settlement_state', 'settled'
  );
END;
$$;

-- Lock down: trusted callers only.
REVOKE ALL ON FUNCTION public.repas_capture_and_settle_order(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.repas_capture_and_settle_order(uuid, text) TO service_role;

COMMENT ON FUNCTION public.repas_capture_and_settle_order(uuid, text) IS
  'Phase 6B: trusted-only Repas capture + merchant settlement. Captures CHOPPay intent, sets food_orders.payment_status=paid, credits merchant wallet via wallet_settle_merchant_revenue. Idempotent. Admin or service_role only.';

-- 4. Admin preview helper.
CREATE OR REPLACE FUNCTION public.admin_preview_repas_payment_settlement(
  p_limit integer DEFAULT 100
)
RETURNS TABLE (
  food_order_id uuid,
  user_id uuid,
  restaurant_id uuid,
  merchant_store_id uuid,
  payment_method text,
  payment_status text,
  settlement_state text,
  payment_intent_id uuid,
  payment_intent_state text,
  subtotal_gnf bigint,
  eligible_for_capture boolean,
  eligible_for_settlement boolean,
  reason text,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.has_role(auth.uid(), 'admin'::app_role) THEN
    RAISE EXCEPTION 'forbidden_admin_only' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH latest_intent AS (
    SELECT DISTINCT ON (pi.source_id) pi.*
    FROM public.payment_intents pi
    WHERE pi.source_module = 'repas'
    ORDER BY pi.source_id, pi.created_at DESC
  )
  SELECT
    fo.id AS food_order_id,
    fo.user_id,
    fo.restaurant_id,
    COALESCE(li.merchant_store_id, fr.merchant_store_id) AS merchant_store_id,
    fo.payment_method::text,
    fo.payment_status::text,
    fo.settlement_state,
    li.id AS payment_intent_id,
    li.state::text AS payment_intent_state,
    fo.subtotal_gnf,
    (fo.payment_method = 'wallet'
       AND fo.payment_status IN ('authorized')
       AND li.state = 'processing') AS eligible_for_capture,
    (fo.payment_method = 'wallet'
       AND fo.payment_status IN ('authorized','paid')
       AND COALESCE(li.merchant_store_id, fr.merchant_store_id) IS NOT NULL
       AND fo.settlement_state <> 'settled') AS eligible_for_settlement,
    CASE
      WHEN fo.payment_method <> 'wallet' THEN 'not_wallet_order'
      WHEN li.id IS NULL THEN 'no_payment_intent'
      WHEN fo.payment_status = 'paid' AND fo.settlement_state = 'settled' THEN 'already_settled'
      WHEN COALESCE(li.merchant_store_id, fr.merchant_store_id) IS NULL THEN 'missing_merchant_store_id'
      WHEN fo.payment_status = 'failed' THEN 'auth_failed'
      WHEN fo.payment_status = 'authorized' AND li.state = 'processing' THEN 'ready_to_capture'
      ELSE 'ok'
    END AS reason,
    fo.created_at
  FROM public.food_orders fo
  LEFT JOIN latest_intent li ON li.source_id = fo.id
  LEFT JOIN public.food_restaurants fr ON fr.id = fo.restaurant_id
  WHERE fo.payment_method = 'wallet'
  ORDER BY fo.created_at DESC
  LIMIT GREATEST(1, LEAST(p_limit, 500));
END;
$$;

REVOKE ALL ON FUNCTION public.admin_preview_repas_payment_settlement(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_preview_repas_payment_settlement(integer) TO authenticated, service_role;

COMMENT ON FUNCTION public.admin_preview_repas_payment_settlement(integer) IS
  'Phase 6B admin/ops preview: lists Repas wallet orders with capture/settlement eligibility, intent state, and blocking reason.';
