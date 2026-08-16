/**
 * Node 4 — Marché R5: merchant fulfillment + delivery client surface.
 *
 * The client never asserts a lifecycle state; it only requests a transition.
 * Every authority check, timestamp, stock settlement and milestone is
 * server-derived. This module is a thin, typed request layer.
 */
import { supabase } from "@/integrations/supabase/client";
import { translateOrderError, type MarcheOrder } from "./orders";

type Rpc = { rpc: (n: string, a?: Record<string, unknown>) => Promise<{ data: unknown; error: { message: string } | null }> };
const db = supabase as unknown as Rpc;

export type MarcheFulfillmentState =
  | "committed" | "accepted" | "preparing" | "ready"
  | "courier_engaged" | "collected" | "delivering" | "delivered"
  | "rejected" | "cancelled";

export type MerchantAction = "accept" | "prepare" | "ready" | "reject";
export type CourierAction = "arrive_store" | "collect" | "start_delivery" | "deliver";

export interface MarcheFulfillmentStep {
  from_state: string | null;
  to_state: string;
  actor_role: string;
  reason: string | null;
  at: string;
  actor_id?: string | null;
  mission_id?: string | null;
}

const STATE_LABEL: Record<string, string> = {
  committed: "Commande reçue",
  accepted: "Acceptée par la boutique",
  preparing: "En préparation",
  ready: "Prête au retrait",
  courier_engaged: "Coursier assigné",
  collected: "Colis récupéré",
  delivering: "En cours de livraison",
  delivered: "Livrée",
  rejected: "Refusée par la boutique",
  cancelled: "Annulée",
};

export function fulfillmentStateLabel(state: string | null | undefined): string {
  return STATE_LABEL[state ?? ""] ?? (state ?? "—");
}

/** Merchant actions offered by the UI for the current server state. */
export function merchantActionsFor(state: string | null | undefined): MerchantAction[] {
  switch (state) {
    case "committed": return ["accept", "reject"];
    case "accepted": return ["prepare", "reject"];
    case "preparing": return ["ready"];
    default: return [];
  }
}

export const MERCHANT_ACTION_LABEL: Record<MerchantAction, string> = {
  accept: "Accepter",
  prepare: "Préparer",
  ready: "Prête",
  reject: "Refuser",
};

export const COURIER_ACTION_LABEL: Record<CourierAction, string> = {
  arrive_store: "Je suis à la boutique",
  collect: "Colis récupéré",
  start_delivery: "Démarrer la livraison",
  deliver: "Livrée",
};

/** The merchant may hand the order to a courier only once it is ready. */
export function canRequestDispatch(order: Pick<MarcheOrder, "fulfillment_state" | "mission_id">): boolean {
  return order.fulfillment_state === "ready" && !order.mission_id;
}

async function call<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await db.rpc(fn, args);
  if (error) throw new Error(translateOrderError(error.message));
  return data as T;
}

export function merchantTransition(orderId: string, action: MerchantAction, reason?: string | null) {
  return call<MarcheOrder>("marche_merchant_transition", {
    p_order_id: orderId, p_action: action, p_reason: reason ?? null,
  });
}

export function courierTransition(orderId: string, action: CourierAction) {
  return call<MarcheOrder>("marche_courier_transition", { p_order_id: orderId, p_action: action });
}

export function requestDispatch(orderId: string) {
  return call<MarcheOrder>("marche_dispatch_request", { p_order_id: orderId });
}

export function orderFulfillmentHistory(orderId: string) {
  return call<MarcheFulfillmentStep[]>("marche_order_fulfillment_history", { p_order_id: orderId });
}
