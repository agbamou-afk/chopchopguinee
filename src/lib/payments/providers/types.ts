/**
 * Provider adapter contract — the single interface every mobile-money,
 * cash, agent, or manual rail must implement to plug into WONGO Wallet.
 *
 * Adapters are pure, side-effect free shape/normalization helpers. They
 * NEVER credit wallets directly. State transitions always flow through
 * the `confirm_payment_intent` / `fail_payment_intent` SECURITY DEFINER
 * RPCs guarded by admin-only RLS.
 */
import type {
  PaymentIntent,
  PaymentProvider,
  PaymentPurpose,
  PaymentState,
} from "../types";

/** Canonical normalized event the rest of WONGO reasons about. */
export interface NormalizedProviderEvent {
  provider: PaymentProvider;
  provider_reference: string;
  internal_reference: string | null;
  amount_gnf: number | null;
  phone_number: string | null;
  state: PaymentState;
  occurred_at: string; // ISO
  raw: Record<string, unknown>;
}

export interface ProviderIntentRequest {
  amount_gnf: number;
  purpose: PaymentPurpose;
  phone_number?: string;
  internal_reference?: string;
  metadata?: Record<string, unknown>;
}

export interface WebhookValidationOk {
  ok: true;
  event: NormalizedProviderEvent;
}
export interface WebhookValidationErr {
  ok: false;
  reason: WebhookValidationReason;
  detail?: string;
}
export type WebhookValidationResult = WebhookValidationOk | WebhookValidationErr;

export type WebhookValidationReason =
  | "missing_field"
  | "unknown_reference"
  | "amount_mismatch"
  | "provider_mismatch"
  | "already_terminal"
  | "invalid_status"
  | "invalid_signature"
  | "duplicate_event";

export type SimulatedKind =
  | "pending"
  | "confirmed"
  | "failed"
  | "expired"
  | "duplicate"
  | "wrong_amount"
  | "unknown_reference";

export interface PaymentProviderAdapter {
  readonly id: PaymentProvider;
  readonly displayName: string;
  readonly supports: { topup: boolean; payment: boolean; payout: boolean };

  /** Build the request body our server would send to this provider. */
  createPaymentIntentRequest(input: ProviderIntentRequest): Record<string, unknown>;

  /** Map raw provider-side status into WONGO's PaymentState vocabulary. */
  normalizeProviderStatus(raw: string | null | undefined): PaymentState;

  /** Light-touch parsing — pulls our canonical shape out of provider JSON. */
  parseWebhookEvent(payload: Record<string, unknown>): NormalizedProviderEvent | null;

  /** Signature/HMAC validation — stubbed today, real-mode TODO. */
  validateSignature(payload: Record<string, unknown>, signature: string | null): boolean;

  /** Sandbox/admin helper: synthesize a believable provider event. */
  simulateProviderEvent(
    intent: Pick<PaymentIntent, "internal_reference" | "amount_gnf" | "provider">,
    kind: SimulatedKind,
    opts?: { phone_number?: string },
  ): NormalizedProviderEvent;
}

/** Local catalogue type — kept here so adapters can self-describe. */
export interface ProviderCapabilities {
  expectedPhoneRegex?: RegExp;
  expectedExternalReferenceShape?: string;
}