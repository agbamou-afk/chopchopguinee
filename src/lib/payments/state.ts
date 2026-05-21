/**
 * Status mappers + FR copy for the unified WONGO payment-state vocabulary.
 * Receipts, notifications, and admin lists all funnel through these so the
 * UI stays consistent across wallet_transactions, topup_requests and
 * payment_intents.
 */
import type { PaymentState } from "./types";

export type StateTone = "pending" | "processing" | "ok" | "failed" | "cancelled" | "muted";

export function mapTxnStatus(s: string | null | undefined): PaymentState {
  switch ((s ?? "").toLowerCase()) {
    case "pending":   return "pending";
    case "completed": return "confirmed";
    case "failed":    return "failed";
    case "cancelled": return "cancelled";
    case "reversed":  return "reversed";
    default:          return "pending";
  }
}

export function mapTopupStatus(s: string | null | undefined): PaymentState {
  switch ((s ?? "").toLowerCase()) {
    case "pending":       return "pending";
    case "matched":
    case "needs_review":  return "processing";
    case "credited":
    case "confirmed":     return "confirmed";
    case "failed":        return "failed";
    case "cancelled":     return "cancelled";
    case "expired":       return "expired";
    default:              return "pending";
  }
}

export function stateLabel(s: PaymentState): string {
  switch (s) {
    case "pending":    return "En attente";
    case "processing": return "En traitement";
    case "confirmed":  return "Confirmé";
    case "failed":     return "Échoué";
    case "cancelled":  return "Annulé";
    case "refunded":   return "Remboursé";
    case "reversed":   return "Annulé (reversé)";
    case "expired":    return "Expiré";
  }
}

export function stateTone(s: PaymentState): StateTone {
  switch (s) {
    case "pending":    return "pending";
    case "processing": return "processing";
    case "confirmed":  return "ok";
    case "failed":     return "failed";
    case "cancelled":  return "cancelled";
    case "refunded":   return "ok";
    case "reversed":   return "muted";
    case "expired":    return "cancelled";
  }
}

/** FR copy used in receipts. Calm, customer-facing. */
export function statePhrase(s: PaymentState): string {
  switch (s) {
    case "pending":    return "Paiement en attente de confirmation.";
    case "processing": return "Paiement en cours de traitement.";
    case "confirmed":  return "Paiement confirmé.";
    case "failed":     return "Paiement échoué. Réessayez.";
    case "cancelled":  return "Paiement annulé.";
    case "refunded":   return "Remboursement traité.";
    case "reversed":   return "Transaction reversée.";
    case "expired":    return "Demande expirée.";
  }
}