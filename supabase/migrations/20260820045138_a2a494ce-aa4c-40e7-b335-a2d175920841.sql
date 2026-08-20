CREATE OR REPLACE FUNCTION public.marche_merchant_order_ops(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE caller uuid := auth.uid(); o public.marche_orders; v_items jsonb;
BEGIN
  SELECT * INTO o FROM public.marche_orders WHERE id = p_order_id;
  IF o.id IS NULL THEN RAISE EXCEPTION 'ORDER_NOT_FOUND'; END IF;
  IF NOT public._marche_merchant_ops_authorized(o, caller) THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', i.id, 'listing_id', i.listing_id, 'title', i.title_snapshot,
           'category', i.category_snapshot,
           'qty', i.qty, 'unit_price_gnf', i.unit_price_gnf,
           'line_total_gnf', i.line_total_gnf) ORDER BY i.created_at), '[]'::jsonb)
    INTO v_items FROM public.marche_order_items i WHERE i.order_id = o.id;

  RETURN jsonb_build_object(
    'order_id', o.id,
    'status', o.status,
    'fulfillment_state', o.fulfillment_state,
    'ops_bucket', public._marche_order_ops_bucket(o),
    'allowed_actions', to_jsonb(public._marche_merchant_allowed_actions(o)),
    'courier_assigned', (o.mission_id IS NOT NULL),
    'item_count', o.item_count,
    'line_count', o.line_count,
    'items', v_items,
    'delivery_address', o.delivery_address,
    'created_at', o.created_at,
    'accepted_at', o.accepted_at,
    'ready_at', o.ready_at,
    'delivered_at', o.delivered_at,
    'rejected_at', o.rejected_at,
    'cancelled_at', o.cancelled_at,
    'tender', public._marche_order_tender(o.id, o.source_offer_id),
    'money', public._marche_order_money(o));
END $$;

REVOKE ALL ON FUNCTION public.marche_merchant_order_ops(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.marche_merchant_order_ops(uuid) TO authenticated, service_role;
