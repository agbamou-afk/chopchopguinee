/**
 * WONGO Payments — shared TS types mirroring the DB enums declared in
 * the "WONGO Payments Foundation" migration. Keep these in lock-step
 * with `payment_state`, `payment_provider`, `payment_purpose`,
 * `payment_recon_event` in Postgres.
 */

export type PaymentState =
  | "pending"
  | "processing"
  | "confirmed"
  | "failed"
  | "cancelled"
  | "refunded"
  | "reversed"
  | "expired";

export type PaymentProvider =
  | "orange_money"
  | "mtn_money"
  | "cash"
  | "manual"
  | "internal"
  | "agent";

export type PaymentPurpose =
  | "wallet_topup"
  | "repas_payment"
  | "marche_payment"
  | "courier_payout"
  | "merchant_settlement"
  | "refund";

export type PaymentReconEvent =
  | "intent_created"
  | "provider_pending"
  | "provider_confirmed"
  | "provider_failed"
  | "wallet_credited"
  | "payout_queued"
  | "payout_paid"
  | "refund_created"
  | "refund_completed";

export interface PaymentIntent {
  id: string;
  user_id: string;
  amount_gnf: number;
  currency: string;
  purpose: PaymentPurpose;
  state: PaymentState;
  provider: PaymentProvider;
  provider_reference: string | null;
  internal_reference: string;
  related_order_id: string | null;
  related_mission_id: string | null;
  related_listing_id: string | null;
  related_store_id: string | null;
  metadata: Record<string, unknown>;
  created_at: string;
  updated_at: string;
}

export interface PaymentReconciliationEvent {
  id: string;
  intent_id: string;
  event_type: PaymentReconEvent;
  provider: PaymentProvider | null;
  provider_reference: string | null;
  payload: Record<string, unknown>;
  actor_user_id: string | null;
  created_at: string;
}