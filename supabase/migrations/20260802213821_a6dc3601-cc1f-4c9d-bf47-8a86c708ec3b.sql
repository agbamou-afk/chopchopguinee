-- Fix: admin_preview_repas_payment_settlement referenced li.merchant_store_id,
-- but the `li` alias is the latest_intent CTE over public.payment_intents, which
-- has no merchant_store_id column (only related_store_id). Mirrors the fix already
-- applied to admin_preview_marche_payment_settlement.
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
    COALESCE(fr.merchant_store_id, li.related_store_id) AS merchant_store_id,
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
       AND COALESCE(fr.merchant_store_id, li.related_store_id) IS NOT NULL
       AND fo.settlement_state <> 'settled') AS eligible_for_settlement,
    CASE
      WHEN fo.payment_method <> 'wallet' THEN 'not_wallet_order'
      WHEN li.id IS NULL THEN 'no_payment_intent'
      WHEN fo.payment_status = 'paid' AND fo.settlement_state = 'settled' THEN 'already_settled'
      WHEN COALESCE(fr.merchant_store_id, li.related_store_id) IS NULL THEN 'missing_merchant_store_id'
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