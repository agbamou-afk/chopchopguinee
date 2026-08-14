-- Node 3 / R9 — canonical customer-side recovery lookup.
-- Read-only. Resolves an ambiguous commit outcome to canonical server truth
-- without ever creating durable state. Never bypasses R6/R7 authorization:
-- it is strictly scoped to the calling customer's own request id.
CREATE OR REPLACE FUNCTION public.repas_order_resume(p_client_request_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_o public.food_orders%ROWTYPE;
  v_mission uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'NOT_AUTHENTICATED'; END IF;
  IF p_client_request_id IS NULL THEN RAISE EXCEPTION 'CLIENT_REQUEST_ID_REQUIRED'; END IF;

  SELECT * INTO v_o FROM public.food_orders
   WHERE user_id = v_uid AND client_request_id = p_client_request_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', true, 'found', false);
  END IF;

  SELECT id INTO v_mission FROM public.missions
   WHERE ref_food_order_id = v_o.id ORDER BY created_at DESC LIMIT 1;

  RETURN jsonb_build_object(
    'ok', true,
    'found', true,
    'order_id', v_o.id,
    'state', v_o.state,
    'fulfillment', v_o.fulfillment,
    'payment_method', v_o.payment_method,
    'subtotal_gnf', v_o.subtotal_gnf,
    'delivery_fee_gnf', COALESCE(v_o.delivery_fee_gnf, 0),
    'platform_fee_gnf', COALESCE(v_o.platform_fee_gnf, 0),
    'order_total_gnf', COALESCE(v_o.order_total_gnf, v_o.subtotal_gnf),
    'mission_id', v_mission,
    'created_at', v_o.created_at);
END; $function$;

REVOKE ALL ON FUNCTION public.repas_order_resume(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.repas_order_resume(uuid) TO authenticated;