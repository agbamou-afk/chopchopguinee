import { supabase } from "@/integrations/supabase/client";

/**
 * Slice 5 — Repas / Marché Chop Pay order engine client bindings.
 *
 * Mirrors `@/lib/cash/cashOrders`: every money transition is server
 * authoritative and this module only forwards to the audited RPCs.
 *
 * Driver acceptance (collateral) and completion are NOT exposed here: they are
 * owned by the canonical mission lifecycle (`mission_claim`,
 * `mission_confirm_pickup`, `mission_confirm_dropoff`), which runs the engine
 * inside the same transaction using the economics frozen at authorization.
 */

export type ChopPayModule = "repas" | "marche";

export type ChopPayOrderState =
  | "authorized"
  | "accepted"
  | "merchant_accepted"
  | "preparing"
  | "merchant_rejected"
  | "cancelled"
  | "completed"
  | "disputed"
  | "dispute_resolved";

export interface ChopPayOrderRuntime {
  id: string;
  order_key: string;
  source_module: ChopPayModule;
  source_id: string;
  mission_type: string;
  mission_id: string | null;
  customer_user_id: string;
  driver_user_id: string | null;
  merchant_store_id: string | null;
  merchant_user_id: string | null;
  merchandise_subtotal_gnf: number;
  delivery_fee_gnf: number;
  platform_fee_gnf: number;
  order_total_gnf: number;
  /** Frozen at authorization — never re-derived from the live policy. */
  collateral_gnf: number | null;
  policy_snapshot: any | null;
  state: ChopPayOrderState;
  authorized_at: string | null;
  accepted_at: string | null;
  funded_at: string | null;
  prep_locked_at: string | null;
  completed_at: string | null;
  cancelled_at: string | null;
  disputed_at: string | null;
  dispute_reason: string | null;
  dispute_resolution: any | null;
  merchant_credited_gnf: number | null;
  driver_earning_gnf: number | null;
  platform_revenue_gnf: number | null;
  cancellation_charge_gnf: number | null;
  customer_refunded_gnf: number | null;
  is_sandbox: boolean;
  created_at: string;
}

export const CHOP_PAY_STATE_LABEL: Record<ChopPayOrderState, string> = {
  authorized: "Paiement autorisé",
  accepted: "Coursier engagé",
  merchant_accepted: "Marchand payé",
  preparing: "En préparation",
  merchant_rejected: "Refusé par le marchand",
  cancelled: "Annulé",
  completed: "Livré · paiement réglé",
  disputed: "Litige ouvert",
  dispute_resolved: "Litige résolu",
};

export function formatGnf(n: number | null | undefined): string {
  return `${Number(n ?? 0).toLocaleString("fr-FR")} GNF`;
}

/** Runtime row for one source order (null when the order is not a Chop Pay order). */
export async function getChopPayRuntime(
  module: ChopPayModule,
  sourceId: string,
): Promise<ChopPayOrderRuntime | null> {
  const { data, error } = await (supabase as any)
    .from("chop_pay_order_runtime")
    .select("*")
    .eq("source_module", module)
    .eq("source_id", sourceId)
    .maybeSingle();
  if (error) return null;
  return (data as ChopPayOrderRuntime) ?? null;
}

/** Batch variant used by list screens. */
export async function listChopPayRuntimes(
  module: ChopPayModule,
  sourceIds: string[],
): Promise<Map<string, ChopPayOrderRuntime>> {
  const out = new Map<string, ChopPayOrderRuntime>();
  if (sourceIds.length === 0) return out;
  const { data, error } = await (supabase as any)
    .from("chop_pay_order_runtime")
    .select("*")
    .eq("source_module", module)
    .in("source_id", sourceIds);
  if (error) return out;
  for (const r of (data ?? []) as ChopPayOrderRuntime[]) out.set(r.source_id, r);
  return out;
}

async function rpc<T = any>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await (supabase as any).rpc(fn, args);
  if (error) throw new Error(translateChopPayError(error.message));
  return data as T;
}

/** Read-only economics + eligibility preview (participants only, server-scoped). */
export function quoteChopPayOrder(module: ChopPayModule, sourceId: string) {
  return rpc("chop_pay_quote", { p_source_module: module, p_source_id: sourceId });
}

/** Customer authorization — holds the full order total and freezes economics. */
export function authorizeChopPayOrder(module: ChopPayModule, sourceId: string) {
  return rpc("chop_pay_authorize_order", { p_source_module: module, p_source_id: sourceId });
}

export function customerCancelChopPayOrder(
  module: ChopPayModule,
  sourceId: string,
  reason?: string | null,
) {
  return rpc("chop_pay_customer_cancel", {
    p_source_module: module,
    p_source_id: sourceId,
    p_reason: reason ?? null,
  });
}

export function merchantAcceptChopPayOrder(module: ChopPayModule, sourceId: string) {
  return rpc("chop_pay_merchant_accept", { p_source_module: module, p_source_id: sourceId });
}

export function merchantRejectChopPayOrder(
  module: ChopPayModule,
  sourceId: string,
  reason?: string | null,
) {
  return rpc("chop_pay_merchant_reject", {
    p_source_module: module,
    p_source_id: sourceId,
    p_reason: reason ?? null,
  });
}

export function merchantPrepareChopPayOrder(module: ChopPayModule, sourceId: string) {
  return rpc("chop_pay_merchant_prepare", { p_source_module: module, p_source_id: sourceId });
}

export function openChopPayDispute(module: ChopPayModule, sourceId: string, reason: string) {
  return rpc("chop_pay_dispute_open", {
    p_source_module: module,
    p_source_id: sourceId,
    p_reason: reason,
  });
}

export type ChopPayDisputeOutcome =
  | "complete_as_delivered"
  | "refund_customer"
  | "close_no_value";

export const CHOP_PAY_DISPUTE_OUTCOME_LABEL: Record<ChopPayDisputeOutcome, string> = {
  complete_as_delivered: "Clôturer comme livré (régler les parties)",
  refund_customer: "Rembourser le client",
  close_no_value: "Clôturer sans mouvement (libérer les gages)",
};

/** God / finance admin only — enforced server-side by `_finance_privileged`. */
export function resolveChopPayDispute(
  module: ChopPayModule,
  sourceId: string,
  outcome: ChopPayDisputeOutcome,
  reason?: string | null,
) {
  return rpc("admin_chop_pay_dispute_resolve", {
    p_source_module: module,
    p_source_id: sourceId,
    p_outcome: outcome,
    p_reason: reason ?? null,
  });
}

export function translateChopPayError(msg: string): string {
  const m = (msg || "").toUpperCase();
  if (m.includes("CHOP_PAY_CHECKOUT_DISABLED")) return "Le paiement Chop Pay est désactivé.";
  if (m.includes("CHOP_PAY_DISABLED")) return "Chop Pay n'est pas encore activé.";
  if (m.includes("NOT_A_CHOP_PAY_ORDER")) return "Cette commande n'est pas une commande Chop Pay.";
  if (m.includes("MIXED_TENDER")) return "Paiement mixte non pris en charge.";
  if (m.includes("ALREADY_AUTHORIZED")) return "Le paiement est déjà autorisé.";
  if (m.includes("INSUFFICIENT_CUSTOMER_BALANCE")) return "Solde Chop Pay insuffisant pour cette commande.";
  if (m.includes("INSUFFICIENT_DRIVER_BALANCE")) return "Solde coursier insuffisant pour le gage de mission.";
  if (m.includes("RESTRICTED_FUNDS")) return "Le crédit bonus ne peut pas servir de gage ni payer la marchandise.";
  if (m.includes("INSUFFICIENT")) return "Solde disponible insuffisant.";
  if (m.includes("STALE_OFFER")) return "Cette mission n'est plus disponible.";
  if (m.includes("PREPARATION_LOCKED")) return "La préparation a commencé : ouvrez un litige.";
  if (m.includes("MERCHANT_REJECTION_AFTER_CAPTURE")) return "Refus impossible après encaissement : ouvrez un litige.";
  if (m.includes("PREPARATION_REQUIRES")) return "Acceptez d'abord la commande.";
  if (m.includes("PREPARATION_REQUIRED_BEFORE_DELIVERY")) return "La préparation doit être lancée avant la livraison.";
  if (m.includes("CUSTODY_NOT_ESTABLISHED")) return "Le retrait doit être confirmé avant la livraison.";
  if (m.includes("ORDER_IN_DISPUTE")) return "Commande en litige.";
  if (m.includes("DISPUTE_REQUIRES")) return "Litige possible seulement après autorisation du paiement.";
  if (m.includes("FINANCE_RECONCILIATION_REQUIRED")) return "Réconciliation Finance requise pour ce dossier.";
  if (m.includes("CHOP_PAY_STATE_ENGINE_ONLY")) return "Cette commande doit passer par le moteur Chop Pay.";
  if (m.includes("TENDER_LOCKED")) return "Le mode de paiement ne peut plus être modifié.";
  if (m.includes("NOT AUTHORIZED")) return "Action non autorisée.";
  return msg || "Action impossible.";
}
