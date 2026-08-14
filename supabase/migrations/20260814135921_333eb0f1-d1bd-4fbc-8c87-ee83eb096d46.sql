-- R7: table-wide SELECT is what re-exposed the private finance columns.
-- Replace it with an explicit column-level grant.
REVOKE SELECT ON public.missions FROM authenticated, anon;
REVOKE SELECT ON public.food_orders FROM authenticated, anon;

GRANT SELECT (
  id, type, state, courier_id, customer_id, merchant_id,
  pickup_address, pickup_lat, pickup_lng,
  dropoff_address, dropoff_lat, dropoff_lng,
  payload_summary, estimated_distance_m, estimated_duration_s,
  ref_ride_id, ref_food_order_id, ref_market_order_id,
  pickup_confirmed_at, pickup_confirmed_by,
  dropoff_confirmed_at, dropoff_confirmed_by,
  issue_reason, created_at, updated_at, issue_district, issue_hub_id,
  merchant_store_id, pickup_photo_url, delivery_photo_url,
  merchant_handoff_code, customer_handoff_code,
  customer_confirmed_at, customer_confirmed_by
) ON public.missions TO authenticated, anon;

GRANT SELECT (
  id, user_id, restaurant_id, fulfillment, state,
  payment_method, payment_status,
  subtotal_gnf, base_delivery_fee_gnf, delivery_fee_gnf,
  promo_discount_gnf, platform_fee_gnf, order_total_gnf,
  delivery_distance_km, notes,
  delivery_address, delivery_lat, delivery_lng,
  paid_at, completed_at, settlement_state, client_request_id,
  created_at, updated_at
) ON public.food_orders TO authenticated, anon;

-- Test-only: give the R7 fixture restaurant real coordinates so the delivery
-- scenario can resolve a verifiable distance.
CREATE OR REPLACE FUNCTION public._qa_node3_repas_r7_fixture_geo(p_resto uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  UPDATE public.food_restaurants
     SET latitude = 9.5370, longitude = -13.6785
   WHERE id = p_resto;
$$;
REVOKE ALL ON FUNCTION public._qa_node3_repas_r7_fixture_geo(uuid) FROM PUBLIC, anon, authenticated;