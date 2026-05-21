/**
 * Lightweight "À vérifier" classifier + reconciliation-event display helpers.
 * Pure functions — no DB writes. Used by the admin payments workspace.
 */
import type { PaymentIntent, PaymentReconciliationEvent, PaymentReconEvent } from "./types";

const PENDING_TOO_LONG_MS = 30 * 60 * 1000; // 30 min

export interface ReviewSignal {
  reason:
    | "pending_too_long"
    | "amount_mismatch"
    | "provider_mismatch"
    | "unknown_reference"
    | "duplicate_events"
    | "failed_after_pending"
    | "confirmed_without_credit"
    | "credited_without_confirmation";
  detail?: string;
}

export function reviewSignals(
  intent: PaymentIntent,
  events: PaymentReconciliationEvent[] = [],
): ReviewSignal[] {
  const out: ReviewSignal[] = [];
  const now = Date.now();

  if (
    (intent.state === "pending" || intent.state === "processing") &&
    now - new Date(intent.created_at).getTime() > PENDING_TOO_LONG_MS
  ) {
    out.push({ reason: "pending_too_long" });
  }

  const validationFailures = events.filter((e) => {
    const payload = (e.payload ?? {}) as { validation_reason?: string };
    return payload.validation_reason;
  });
  for (const v of validationFailures) {
    const r = (v.payload as { validation_reason?: string }).validation_reason;
    if (r === "amount_mismatch") out.push({ reason: "amount_mismatch" });
    else if (r === "provider_mismatch") out.push({ reason: "provider_mismatch" });
    else if (r === "unknown_reference") out.push({ reason: "unknown_reference" });
  }

  const duplicates = events.filter(
    (e) => (e.payload as { validation_reason?: string })?.validation_reason === "duplicate_event",
  );
  if (duplicates.length >= 2) out.push({ reason: "duplicate_events", detail: `${duplicates.length}×` });

  const hadPending = events.some((e) => e.event_type === "provider_pending");
  if (hadPending && intent.state === "failed") out.push({ reason: "failed_after_pending" });

  const confirmed = intent.state === "confirmed";
  const credited = events.some((e) => e.event_type === "wallet_credited");
  if (confirmed && events.length > 0 && !credited) {
    out.push({ reason: "confirmed_without_credit" });
  }
  const hadProviderConfirmed = events.some((e) => e.event_type === "provider_confirmed");
  if (credited && !hadProviderConfirmed && intent.provider !== "internal" && intent.provider !== "manual") {
    out.push({ reason: "credited_without_confirmation" });
  }

  // dedupe by reason
  const seen = new Set<string>();
  return out.filter((s) => (seen.has(s.reason) ? false : (seen.add(s.reason), true)));
}

export function needsReview(intent: PaymentIntent, events: PaymentReconciliationEvent[] = []): boolean {
  return reviewSignals(intent, events).length > 0;
}

export function reviewSignalLabel(s: ReviewSignal): string {
  switch (s.reason) {
    case "pending_too_long":              return "En attente depuis longtemps";
    case "amount_mismatch":               return "Montant provider ≠ intent";
    case "provider_mismatch":             return "Provider ≠ intent";
    case "unknown_reference":             return "Référence inconnue";
    case "duplicate_events":              return `Doublons d'événements${s.detail ? " " + s.detail : ""}`;
    case "failed_after_pending":          return "Échec après pending";
    case "confirmed_without_credit":      return "Confirmé sans crédit wallet";
    case "credited_without_confirmation": return "Wallet crédité sans confirmation provider";
  }
}

export function reconEventLabel(t: PaymentReconEvent | string): string {
  switch (t) {
    case "intent_created":      return "Intent créé";
    case "provider_pending":    return "Provider — en attente";
    case "provider_confirmed":  return "Provider — confirmé";
    case "provider_failed":     return "Provider — échoué";
    case "wallet_credited":     return "Wallet crédité";
    case "payout_queued":       return "Payout en file";
    case "payout_paid":         return "Payout payé";
    case "refund_created":      return "Remboursement créé";
    case "refund_completed":    return "Remboursement terminé";
    default:                    return String(t);
  }
}

export function reconEventTone(t: PaymentReconEvent | string): "ok" | "pending" | "failed" | "muted" {
  if (t === "provider_confirmed" || t === "wallet_credited" || t === "payout_paid" || t === "refund_completed") return "ok";
  if (t === "provider_failed") return "failed";
  if (t === "provider_pending" || t === "payout_queued" || t === "refund_created") return "pending";
  return "muted";
}

export function toCsv(intents: PaymentIntent[]): string {
  const headers = [
    "wongo_reference",
    "provider_reference",
    "provider",
    "amount_gnf",
    "status",
    "purpose",
    "user_id",
    "created_at",
    "updated_at",
  ];
  const esc = (v: unknown) => {
    const s = v == null ? "" : String(v);
    return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const lines = [headers.join(",")];
  for (const i of intents) {
    lines.push([
      i.internal_reference,
      i.provider_reference ?? "",
      i.provider,
      i.amount_gnf,
      i.state,
      i.purpose,
      i.user_id,
      i.created_at,
      i.updated_at,
    ].map(esc).join(","));
  }
  return lines.join("\n");
}