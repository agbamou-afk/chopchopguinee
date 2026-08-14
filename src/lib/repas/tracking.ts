/**
 * Node 3 / R7 — canonical Repas tracking + receipt read models.
 *
 * Both entry points are server-authoritative, read-only and participant
 * authorized. The client never re-derives a status, a next action, or a money
 * amount: it renders exactly what the server returns.
 */
import { supabase } from "@/integrations/supabase/client";
import type { FoodFulfillment, FoodOrderState, FoodPaymentMethod } from "./types";

export type RepasViewerRole = "customer" | "merchant" | "courier" | "finance";

export interface RepasTrackingCustodyCredential {
  kind: string;
  consumed: boolean;
  locked: boolean;
  holder_is_self: boolean;
}

/**
 * R11 — frozen destination snapshot as returned by `repas_order_tracking`.
 * `coordinates` is only ever present for the courier and finance roles.
 */
export interface RepasTrackingDestination {
  label: string | null;
  landmark: string | null;
  instructions: string | null;
  location_source: string | null;
  location_quality: string | null;
  has_coordinates: boolean;
  coordinates?: { lat: number | null; lng: number | null } | null;
}

export interface RepasTracking {
  order_id: string;
  viewer_role: RepasViewerRole;
  state: FoodOrderState;
  fulfillment: FoodFulfillment;
  terminal: boolean;
  terminal_reason: string | null;
  engine_state: string | null;
  restaurant: { id: string; name: string; district: string | null; prep_time_min: number | null };
  created_at: string;
  updated_at: string | null;
  completed_at: string | null;
  custody: { credentials: RepasTrackingCustodyCredential[]; pending_kind: string | null };
  mission: {
    id: string;
    state: string;
    courier_assigned: boolean;
    pickup_confirmed_at: string | null;
    dropoff_confirmed_at: string | null;
  } | null;
  payment_method: FoodPaymentMethod;
  payment_status?: string | null;
  order_total_gnf?: number;
  merchandise_subtotal_gnf?: number;
  delivery_address?: string | null;
  pickup_address?: string | null;
  /** Null for Retrait: a pickup order has no destination at all. */
  destination?: RepasTrackingDestination | null;
  cash_due_gnf?: number | null;
  courier?: { full_name: string | null; phone: string | null } | null;
  customer?: { full_name: string | null; phone: string | null } | null;
  /** Merchant/finance only — canonical, server-derived. */
  allowed_actions?: string[];
}

export interface RepasReceiptLine {
  name: string;
  qty: number;
  unit_price_gnf: number;
  line_total_gnf: number;
}

/**
 * Canonical payment truth derived server-side from the committed tender
 * runtime (Chop Pay / cash). The legacy `food_orders.payment_status` column is
 * never authoritative when it disagrees with the engine.
 */
export type RepasPaymentState =
  | "authorized"
  | "paid"
  | "released"
  | "due"
  | "collected"
  | "cancelled"
  | "disputed"
  | "dispute_resolved"
  | "unknown";

export interface RepasReceipt {
  order_id: string;
  viewer_role: RepasViewerRole;
  restaurant: { id: string; name: string; district: string | null };
  fulfillment: FoodFulfillment;
  state: FoodOrderState;
  payment_method: FoodPaymentMethod;
  payment_status: string | null;
  /** Legacy raw `food_orders.payment_status` — never canonical on its own. */
  legacy_payment_status?: string | null;
  /** Canonical committed tender runtime state (Chop Pay / cash engine). */
  engine_state?: string | null;
  payment_rail?: "chop_pay" | "cash" | null;
  payment_state?: RepasPaymentState;
  payment_settled?: boolean;
  created_at: string;
  paid_at: string | null;
  completed_at: string | null;
  items: RepasReceiptLine[];
  merchandise_subtotal_gnf: number;
  items_line_total_gnf: number;
  base_delivery_fee_gnf: number;
  promo_discount_gnf: number;
  promotion_name: string | null;
  delivery_fee_gnf: number;
  platform_fee_gnf: number;
  order_total_gnf: number;
  cancelled: boolean;
  custody_timeline: { boundary: string; method: string; occurred_at: string }[];
  totals_reconcile: boolean;
}

export async function getRepasTracking(orderId: string): Promise<RepasTracking> {
  const { data, error } = await (supabase as any).rpc("repas_order_tracking", {
    p_order_id: orderId,
  });
  if (error) throw new Error(translateTrackingError(error.message));
  return data as RepasTracking;
}

export async function getRepasReceipt(orderId: string): Promise<RepasReceipt> {
  const { data, error } = await (supabase as any).rpc("repas_order_receipt", {
    p_order_id: orderId,
  });
  if (error) throw new Error(translateTrackingError(error.message));
  return data as RepasReceipt;
}

function translateTrackingError(msg: string): string {
  const raw = (msg || "").toUpperCase();
  if (raw.includes("NOT_AUTHENTICATED")) return "Connectez-vous pour suivre cette commande.";
  if (raw.includes("NOT_AUTHORIZED")) return "Vous n'avez pas accès à cette commande.";
  if (raw.includes("ORDER_NOT_FOUND")) return "Commande introuvable.";
  return msg || "Suivi indisponible pour le moment.";
}

/* ------------------------------------------------------------------ */
/* French-first, mode-correct labels                                   */
/* ------------------------------------------------------------------ */

const DELIVERY_STATE_LABEL: Record<FoodOrderState, string> = {
  placed: "Commande envoyée au restaurant",
  confirmed: "Restaurant a confirmé",
  preparing: "En préparation",
  // `ready` is BEFORE the R6 restaurant→courier custody handoff: it must never
  // imply the courier already holds the order.
  ready: "Prête au restaurant",
  out_for_delivery: "Remise au coursier — en route vers vous",
  completed: "Livrée",
  cancelled: "Annulée",
};

const PICKUP_STATE_LABEL: Record<FoodOrderState, string> = {
  placed: "Commande envoyée au restaurant",
  confirmed: "Restaurant a confirmé",
  preparing: "En préparation",
  ready: "Prête — à retirer sur place",
  out_for_delivery: "Prête — à retirer sur place",
  completed: "Retirée",
  cancelled: "Annulée",
};

export function repasTrackingLabel(t: Pick<RepasTracking, "state" | "fulfillment">): string {
  return t.fulfillment === "pickup"
    ? PICKUP_STATE_LABEL[t.state]
    : DELIVERY_STATE_LABEL[t.state];
}

export const REPAS_MISSION_LABEL: Record<string, string> = {
  assigned: "Recherche d'un coursier",
  heading_to_pickup: "Coursier en route vers le restaurant",
  arrived_pickup: "Coursier au restaurant",
  picked_up: "Commande récupérée",
  heading_to_dropoff: "Coursier en route vers vous",
  arrived_dropoff: "Coursier arrivé",
  delivered: "Livrée",
  failed: "Livraison échouée",
};

export const REPAS_MERCHANT_ACTION_LABEL: Record<string, string> = {
  accept: "Confirmer la commande",
  prepare: "Démarrer la préparation",
  ready: "Marquer prête",
  reject: "Refuser la commande",
  pickup_collection: "Client a récupéré",
};

export const REPAS_CUSTODY_BOUNDARY_LABEL: Record<string, string> = {
  // Actual R6 `repas_custody_events.boundary` values.
  restaurant_to_courier: "Remise au coursier",
  courier_to_customer: "Remise au client",
  merchant_to_customer_pickup: "Retrait par le client",
  // Legacy credential-style aliases, kept only so historical rows never render
  // a raw snake_case identifier.
  restaurant_handoff: "Remise au coursier",
  customer_delivery: "Remise au client",
  customer_pickup: "Retrait par le client",
};

/** French label for the canonical (engine-derived) payment state. */
export const REPAS_PAYMENT_STATE_LABEL: Record<RepasPaymentState, string> = {
  authorized: "Autorisé — en cours",
  paid: "Payé",
  released: "Annulé — montant libéré",
  due: "À régler",
  collected: "Réglé en espèces",
  cancelled: "Annulée",
  disputed: "En litige",
  dispute_resolved: "Litige résolu",
  unknown: "Non confirmé",
};

export function repasPaymentStateLabel(state?: string | null): string {
  if (!state) return REPAS_PAYMENT_STATE_LABEL.unknown;
  return REPAS_PAYMENT_STATE_LABEL[state as RepasPaymentState] ?? REPAS_PAYMENT_STATE_LABEL.unknown;
}

/**
 * The total may only be labelled as paid when the canonical engine says the
 * value is really settled and retained.
 */
export function repasReceiptTotalLabel(
  r: Pick<RepasReceipt, "payment_state" | "payment_settled" | "payment_rail">,
): string {
  if (!r.payment_settled) return "Total de la commande";
  return r.payment_rail === "cash" || r.payment_state === "collected" ? "Total réglé" : "Total payé";
}

/** Fulfillment-correct custody card to show to the customer, if any. */
export function customerCustodyKind(t: RepasTracking): "customer_delivery" | "customer_pickup" | null {
  if (t.terminal) return null;
  const pending = t.custody.credentials.find((c) => c.holder_is_self && !c.consumed && !c.locked);
  if (!pending) return null;
  if (pending.kind === "customer_delivery" || pending.kind === "customer_pickup") return pending.kind;
  return null;
}
