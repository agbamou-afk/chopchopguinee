import { supabase } from "@/integrations/supabase/client";

/**
 * Slice 4 — Repas / Marché cash-order engine client bindings.
 *
 * Every money transition is server-authoritative: this module only forwards to
 * the audited RPCs. There is no client-side two-step money movement here.
 *
 * Driver acceptance and cash completion are NOT exposed as standalone calls:
 * they are owned by the canonical mission lifecycle (`mission_claim`,
 * `mission_confirm_dropoff` / `mission_set_state('delivered')`), which invokes
 * the engine inside the same transaction.
 */

export type CashOrderModule = "repas" | "marche";

export type CashOrderState =
  | "accepted"
  | "merchant_accepted"
  | "preparing"
  | "merchant_rejected"
  | "cancelled"
  | "completed"
  | "disputed"
  | "dispute_resolved";

export interface CashOrderRuntime {
  id: string;
  source_module: CashOrderModule;
  source_id: string;
  mission_id: string | null;
  mission_type: string;
  customer_user_id: string;
  driver_user_id: string;
  merchant_store_id: string | null;
  merchant_user_id: string | null;
  merchandise_subtotal_gnf: number;
  delivery_fee_gnf: number;
  platform_fee_gnf: number;
  cash_due_gnf: number;
  state: CashOrderState;
  prep_locked_at: string | null;
  completed_at: string | null;
  cancelled_at: string | null;
  disputed_at: string | null;
  dispute_reason: string | null;
  dispute_resolution: any | null;
  cash_collected_gnf: number | null;
  created_at: string;
}

export const CASH_ORDER_STATE_LABEL: Record<CashOrderState, string> = {
  accepted: "Coursier engagé",
  merchant_accepted: "Marchandise financée",
  preparing: "En préparation",
  merchant_rejected: "Refusé par le marchand",
  cancelled: "Annulé",
  completed: "Livré · espèces encaissées",
  disputed: "Litige ouvert",
  dispute_resolved: "Litige résolu",
};

export function formatGnf(n: number | null | undefined): string {
  return `${Number(n ?? 0).toLocaleString("fr-FR")} GNF`;
}

/** Runtime row for one source order (null when the order is not a cash order). */
export async function getCashOrderRuntime(
  module: CashOrderModule,
  sourceId: string,
): Promise<CashOrderRuntime | null> {
  const { data, error } = await (supabase as any)
    .from("cash_order_runtime")
    .select("*")
    .eq("source_module", module)
    .eq("source_id", sourceId)
    .maybeSingle();
  if (error) return null;
  return (data as CashOrderRuntime) ?? null;
}

/** Batch variant used by list screens. */
export async function listCashOrderRuntimes(
  module: CashOrderModule,
  sourceIds: string[],
): Promise<Map<string, CashOrderRuntime>> {
  const out = new Map<string, CashOrderRuntime>();
  if (sourceIds.length === 0) return out;
  const { data, error } = await (supabase as any)
    .from("cash_order_runtime")
    .select("*")
    .eq("source_module", module)
    .in("source_id", sourceIds);
  if (error) return out;
  for (const r of (data ?? []) as CashOrderRuntime[]) out.set(r.source_id, r);
  return out;
}

async function rpc<T = any>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await (supabase as any).rpc(fn, args);
  if (error) throw new Error(translateCashError(error.message));
  return data as T;
}

/** Read-only economics + eligibility preview (participants only, server-scoped). */
export function quoteCashOrder(module: CashOrderModule, sourceId: string) {
  return rpc("cash_order_quote", { p_source_module: module, p_source_id: sourceId });
}

export function merchantAcceptCashOrder(module: CashOrderModule, sourceId: string) {
  return rpc("cash_order_merchant_accept", { p_source_module: module, p_source_id: sourceId });
}

export function merchantRejectCashOrder(
  module: CashOrderModule,
  sourceId: string,
  reason?: string | null,
) {
  return rpc("cash_order_merchant_reject", {
    p_source_module: module,
    p_source_id: sourceId,
    p_reason: reason ?? null,
  });
}

export function merchantPrepareCashOrder(module: CashOrderModule, sourceId: string) {
  return rpc("cash_order_merchant_prepare", { p_source_module: module, p_source_id: sourceId });
}

export function customerCancelCashOrder(
  module: CashOrderModule,
  sourceId: string,
  reason?: string | null,
) {
  return rpc("cash_order_customer_cancel", {
    p_source_module: module,
    p_source_id: sourceId,
    p_reason: reason ?? null,
  });
}

export function openCashOrderDispute(
  module: CashOrderModule,
  sourceId: string,
  reason: string,
) {
  return rpc("cash_order_dispute_open", {
    p_source_module: module,
    p_source_id: sourceId,
    p_reason: reason,
  });
}

export type DisputeOutcome =
  | "complete_as_delivered"
  | "release_driver_funding"
  | "close_no_value";

export const DISPUTE_OUTCOME_LABEL: Record<DisputeOutcome, string> = {
  complete_as_delivered: "Clôturer comme livré (encaisser les frais)",
  release_driver_funding: "Rembourser le coursier (reprise marchand)",
  close_no_value: "Clôturer sans mouvement (libérer les gages)",
};

/** God / finance admin only — enforced server-side by `_finance_privileged`. */
export function resolveCashOrderDispute(
  module: CashOrderModule,
  sourceId: string,
  outcome: DisputeOutcome,
  reason?: string | null,
) {
  return rpc("admin_cash_order_dispute_resolve", {
    p_source_module: module,
    p_source_id: sourceId,
    p_outcome: outcome,
    p_reason: reason ?? null,
  });
}

/** Buyer-selected explicit tender for a Marché offer. Never inferred. */
export function setMarcheOfferTender(offerId: string, method: "cash" | "choppay") {
  return rpc("marche_offer_set_tender", { p_offer_id: offerId, p_method: method });
}

export function translateCashError(msg: string): string {
  const m = (msg || "").toUpperCase();
  if (m.includes("CASH_ORDER_FUNDING_DISABLED")) return "Le financement des commandes espèces est désactivé.";
  if (m.includes("NOT_A_CASH_ORDER")) return "Cette commande n'est pas une commande espèces.";
  if (m.includes("MIXED_TENDER")) return "Paiement mixte non pris en charge.";
  if (m.includes("INSUFFICIENT")) return "Solde disponible insuffisant pour avancer la marchandise.";
  if (m.includes("RESTRICTED_FUNDS_CANNOT_FUND_MERCHANDISE")) return "Le crédit bonus ne peut pas financer la marchandise.";
  if (m.includes("STALE_OFFER")) return "Cette mission n'est plus disponible.";
  if (m.includes("CASH_ORDER_PREPARATION_LOCKED")) return "La préparation a commencé : ouvrez un litige.";
  if (m.includes("CASH_ORDER_ALREADY_FUNDED")) return "La marchandise est déjà financée : ouvrez un litige.";
  if (m.includes("MERCHANT_REJECTION_AFTER_FUNDING")) return "Refus impossible après financement : ouvrez un litige.";
  if (m.includes("PREPARATION_REQUIRES_FUNDED_ORDER")) return "Acceptez d'abord la commande.";
  if (m.includes("MERCHANDISE_FUNDING_NOT_SECURED")) return "Financement marchandise non sécurisé.";
  if (m.includes("PREPARATION_REQUIRED_BEFORE_DELIVERY")) return "La préparation doit être lancée avant la livraison.";
  if (m.includes("CUSTODY_NOT_ESTABLISHED")) return "Le retrait doit être confirmé avant la livraison.";
  if (m.includes("ORDER_IN_DISPUTE")) return "Commande en litige.";
  if (m.includes("DISPUTE_REQUIRES_FUNDED_ORDER")) return "Litige possible seulement après financement.";
  if (m.includes("FINANCE_RECONCILIATION_REQUIRED")) return "Réconciliation Finance requise : la reprise marchand n'est pas possible automatiquement.";
  if (m.includes("CASH_ORDER_STATE_ENGINE_ONLY")) return "Cette commande espèces doit passer par le moteur de commandes.";
  if (m.includes("TENDER_LOCKED")) return "Le mode de paiement ne peut plus être modifié.";
  if (m.includes("CASH_ORDER_NOT_ACCEPTED")) return "Aucun coursier engagé sur cette commande.";
  if (m.includes("NOT AUTHORIZED")) return "Action non autorisée.";
  return msg || "Action impossible.";
}
