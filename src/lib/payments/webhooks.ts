/**
 * Provider webhook foundation.
 *
 * - Declares the canonical inbound payload shape every provider must map to.
 * - Centralises validation rules so a future Edge Function handler can
 *   reuse the exact same checks as the in-app sandbox simulator.
 *
 * NOTE: There is no live public webhook endpoint exposed yet. Wiring
 * the `payment-webhook/orange-money` Edge Function is a later sprint.
 */
import type { PaymentIntent, PaymentState } from "./types";
import type {
  NormalizedProviderEvent,
  WebhookValidationResult,
} from "./providers/types";
import { getProviderAdapter } from "./providers/registry";

export interface InboundWebhookEnvelope {
  provider: string;
  signature: string | null;
  payload: Record<string, unknown>;
  receivedAt: string;
}

const TERMINAL_STATES: PaymentState[] = [
  "confirmed",
  "failed",
  "cancelled",
  "refunded",
  "reversed",
  "expired",
];

/**
 * Validate a normalized provider event against the matching payment_intent.
 * Pure function — no DB writes. Callers (Edge Function or admin simulator)
 * decide whether to dispatch confirm/fail RPCs afterwards.
 */
export function validateProviderEvent(
  event: NormalizedProviderEvent,
  intent: PaymentIntent | null,
  opts: { knownProviderRefs?: Set<string> } = {},
): WebhookValidationResult {
  if (!intent) {
    return { ok: false, reason: "unknown_reference", detail: event.internal_reference ?? "(none)" };
  }
  if (intent.provider !== event.provider) {
    return { ok: false, reason: "provider_mismatch", detail: `intent=${intent.provider} event=${event.provider}` };
  }
  if (event.amount_gnf != null && event.amount_gnf !== intent.amount_gnf) {
    return { ok: false, reason: "amount_mismatch", detail: `intent=${intent.amount_gnf} event=${event.amount_gnf}` };
  }
  if (TERMINAL_STATES.includes(intent.state)) {
    // Duplicates of an already-confirmed intent are explicitly idempotent.
    if (event.state === intent.state) {
      return { ok: false, reason: "duplicate_event", detail: intent.internal_reference };
    }
    return { ok: false, reason: "already_terminal", detail: intent.state };
  }
  if (opts.knownProviderRefs?.has(event.provider_reference)) {
    return { ok: false, reason: "duplicate_event", detail: event.provider_reference };
  }
  return { ok: true, event };
}

/** Parse + signature-check in one call. */
export function ingestWebhook(env: InboundWebhookEnvelope):
  | { ok: true; event: NormalizedProviderEvent }
  | { ok: false; reason: "unknown_provider" | "invalid_payload" | "invalid_signature" } {
  const adapter = getProviderAdapter(env.provider as never);
  if (!adapter) return { ok: false, reason: "unknown_provider" };
  if (!adapter.validateSignature(env.payload, env.signature)) {
    return { ok: false, reason: "invalid_signature" };
  }
  const event = adapter.parseWebhookEvent(env.payload);
  if (!event) return { ok: false, reason: "invalid_payload" };
  return { ok: true, event };
}