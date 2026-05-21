/**
 * Orange Money adapter — SCAFFOLD ONLY.
 *
 * No real API endpoints are called from this file. No credentials are
 * stored here. The adapter exists so the wallet codebase can reason about
 * Orange Money lifecycle events through the same shape as MTN, cash,
 * agent, etc.
 *
 * Live wiring happens later in a server-side Edge Function (e.g.
 * `payment-webhook/orange-money`) that will reuse parseWebhookEvent +
 * validateSignature from here.
 */
import type { PaymentState } from "../types";
import type {
  NormalizedProviderEvent,
  PaymentProviderAdapter,
  ProviderIntentRequest,
  SimulatedKind,
} from "./types";

// Guinea Orange Money MSISDNs: country code 224 + 6/7/8/9 prefix + 8 digits.
const ORANGE_PHONE_RE = /^(?:\+?224)?(6|7)\d{8}$/;

function mapStatus(raw: string | null | undefined): PaymentState {
  switch ((raw ?? "").toLowerCase()) {
    case "init":
    case "initiated":
    case "pending":           return "pending";
    case "processing":
    case "in_progress":       return "processing";
    case "success":
    case "successful":
    case "completed":
    case "confirmed":         return "confirmed";
    case "failed":
    case "error":
    case "declined":          return "failed";
    case "expired":
    case "timeout":           return "expired";
    case "cancelled":
    case "canceled":          return "cancelled";
    case "reversed":
    case "refunded":          return "reversed";
    default:                  return "pending";
  }
}

export const orangeMoneyAdapter: PaymentProviderAdapter = {
  id: "orange_money",
  displayName: "Orange Money",
  supports: { topup: true, payment: true, payout: true },

  createPaymentIntentRequest(input: ProviderIntentRequest): Record<string, unknown> {
    return {
      provider: "orange_money",
      amount: input.amount_gnf,
      currency: "GNF",
      purpose: input.purpose,
      customer_msisdn: input.phone_number ?? null,
      internal_reference: input.internal_reference ?? null,
      metadata: input.metadata ?? {},
    };
  },

  normalizeProviderStatus: mapStatus,

  parseWebhookEvent(payload: Record<string, unknown>): NormalizedProviderEvent | null {
    const providerRef =
      (payload.provider_reference as string | undefined) ??
      (payload.transaction_id as string | undefined) ??
      null;
    const internalRef =
      (payload.internal_reference as string | undefined) ??
      (payload.merchant_reference as string | undefined) ??
      null;
    const status = (payload.status as string | undefined) ?? null;
    if (!providerRef || !status) return null;

    const amountRaw = payload.amount ?? payload.amount_gnf ?? null;
    const phoneRaw =
      (payload.msisdn as string | undefined) ??
      (payload.phone_number as string | undefined) ??
      null;

    return {
      provider: "orange_money",
      provider_reference: providerRef,
      internal_reference: internalRef,
      amount_gnf: typeof amountRaw === "number" ? amountRaw : amountRaw ? Number(amountRaw) : null,
      phone_number: phoneRaw,
      state: mapStatus(status),
      occurred_at:
        (payload.timestamp as string | undefined) ?? new Date().toISOString(),
      raw: payload,
    };
  },

  // TODO(live): replace with HMAC-SHA256 verification using server-side
  // secret. Today the only call sites are sandbox/admin simulators where
  // signatures are not transmitted.
  validateSignature(_payload: Record<string, unknown>, _signature: string | null): boolean {
    return true;
  },

  simulateProviderEvent(intent, kind: SimulatedKind, opts): NormalizedProviderEvent {
    const base = {
      provider: "orange_money" as const,
      provider_reference: `OM-SIM-${Math.random().toString(36).slice(2, 10).toUpperCase()}`,
      internal_reference: intent.internal_reference,
      amount_gnf: intent.amount_gnf,
      phone_number: opts?.phone_number ?? null,
      occurred_at: new Date().toISOString(),
      raw: { simulated: true, kind } as Record<string, unknown>,
    };
    switch (kind) {
      case "pending":           return { ...base, state: "pending" };
      case "confirmed":         return { ...base, state: "confirmed" };
      case "failed":            return { ...base, state: "failed" };
      case "expired":           return { ...base, state: "expired" };
      case "duplicate":         return { ...base, state: "confirmed" };
      case "wrong_amount":      return { ...base, state: "confirmed", amount_gnf: intent.amount_gnf + 1000 };
      case "unknown_reference": return { ...base, state: "confirmed", internal_reference: "WNG-0000-000000" };
    }
  },
};

export const ORANGE_MONEY_CAPABILITIES = {
  expectedPhoneRegex: ORANGE_PHONE_RE,
  expectedExternalReferenceShape: "OM-XXXXXXXX (8+ alnum)",
};

export function isLikelyOrangeMsisdn(phone: string): boolean {
  return ORANGE_PHONE_RE.test(phone.trim().replace(/\s/g, ""));
}

export function maskMsisdn(phone: string | null | undefined): string {
  if (!phone) return "—";
  const trimmed = phone.replace(/\s/g, "");
  if (trimmed.length < 4) return trimmed;
  return `${trimmed.slice(0, 4)}••••${trimmed.slice(-2)}`;
}