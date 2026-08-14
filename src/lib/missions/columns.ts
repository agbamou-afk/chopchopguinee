/**
 * R7 — raw read-surface hardening.
 *
 * `missions.estimated_earning_gnf` is no longer readable by the `authenticated`
 * role: a customer must never be able to select the courier's private economics
 * from their own mission row (directly or through realtime payloads).
 *
 * Every client read therefore projects this explicit column list instead of
 * `select *`. Entitled actors (assigned courier, eligible courier on an open
 * mission, finance) hydrate the earning through the `mission_earnings` RPC.
 */
export const MISSION_SAFE_COLS = [
  "id",
  "type",
  "state",
  "courier_id",
  "customer_id",
  "merchant_id",
  "pickup_address",
  "pickup_lat",
  "pickup_lng",
  "dropoff_address",
  "dropoff_lat",
  "dropoff_lng",
  "payload_summary",
  "estimated_distance_m",
  "estimated_duration_s",
  "ref_ride_id",
  "ref_food_order_id",
  "ref_market_order_id",
  "pickup_confirmed_at",
  "pickup_confirmed_by",
  "dropoff_confirmed_at",
  "dropoff_confirmed_by",
  "issue_reason",
  "created_at",
  "updated_at",
  "issue_district",
  "issue_hub_id",
  "merchant_store_id",
  "pickup_photo_url",
  "delivery_photo_url",
  "merchant_handoff_code",
  "customer_handoff_code",
  "customer_confirmed_at",
  "customer_confirmed_by",
].join(",");

/**
 * `food_orders` private finance columns (`courier_payout_gnf`,
 * `pricing_policy_id`, `promotion_id`, `pricing_snapshot`) are likewise revoked
 * from `authenticated`. Customer- and merchant-facing reads use this list.
 */
export const FOOD_ORDER_SAFE_COLS = [
  "id",
  "user_id",
  "restaurant_id",
  "fulfillment",
  "state",
  "payment_method",
  "payment_status",
  "subtotal_gnf",
  "base_delivery_fee_gnf",
  "delivery_fee_gnf",
  "promo_discount_gnf",
  "platform_fee_gnf",
  "order_total_gnf",
  "delivery_distance_km",
  "notes",
  "delivery_address",
  "delivery_lat",
  "delivery_lng",
  "paid_at",
  "completed_at",
  "settlement_state",
  "client_request_id",
  "created_at",
  "updated_at",
].join(",");
