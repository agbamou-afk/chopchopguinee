import { supabase } from "@/integrations/supabase/client";
import type { FoodOrder, FoodOrderState } from "@/lib/repas/types";
import { translateCashError } from "@/lib/cash/cashOrders";

/* ------------------------------------------------------------------ */
/* Repas — restaurant operations                                      */
/* ------------------------------------------------------------------ */

export async function setRestaurantOpen(restaurantId: string, isOpen: boolean) {
  const { error } = await (supabase as any)
    .from("food_restaurants")
    .update({ is_open: isOpen })
    .eq("id", restaurantId);
  if (error) throw error;
}

export async function setRestaurantFulfillment(
  restaurantId: string,
  patch: { delivery_available?: boolean; pickup_available?: boolean },
) {
  const { error } = await (supabase as any)
    .from("food_restaurants")
    .update(patch)
    .eq("id", restaurantId);
  if (error) throw error;
}

export async function listRestaurantOrders(restaurantId: string, limit = 30): Promise<FoodOrder[]> {
  const { data, error } = await (supabase as any)
    .from("food_orders")
    .select("*")
    .eq("restaurant_id", restaurantId)
    .order("created_at", { ascending: false })
    .limit(limit);
  if (error) throw error;
  return (data ?? []) as FoodOrder[];
}

/** Next state in the restaurant prep flow. */
export const RESTAURANT_NEXT_STATE: Partial<Record<FoodOrderState, FoodOrderState>> = {
  placed: "confirmed",
  confirmed: "preparing",
  preparing: "ready",
  ready: "out_for_delivery", // handed off to courier or customer
  out_for_delivery: "completed",
};

export const RESTAURANT_NEXT_LABEL: Partial<Record<FoodOrderState, string>> = {
  placed: "Confirmer",
  confirmed: "Démarrer préparation",
  preparing: "Marquer prêt",
  ready: "Remettre au coursier",
  out_for_delivery: "Marquer terminé",
};

/**
 * R4.5 — a pickup order has no courier leg: `ready` is followed directly by the
 * customer collecting at the counter, which completes the order.
 */
export function restaurantNextState(
  current: FoodOrderState,
  fulfillment?: string | null,
): FoodOrderState | undefined {
  if (fulfillment === "pickup" && current === "ready") return "completed";
  return RESTAURANT_NEXT_STATE[current];
}

export function restaurantNextLabel(
  current: FoodOrderState,
  fulfillment?: string | null,
): string | undefined {
  if (fulfillment === "pickup" && current === "ready") return "Client a récupéré";
  return RESTAURANT_NEXT_LABEL[current];
}

/**
 * Node 3 / R4 — every restaurant-side transition is server-authoritative.
 * The client may only *request* an action; `repas_merchant_transition`
 * validates ownership, the legal lifecycle, and routes cash / Chop Pay orders
 * through the locked Slice 4 / Slice 5 engines. No raw state UPDATE remains.
 */
export type RepasMerchantAction =
  | "accept"
  | "prepare"
  | "ready"
  | "handoff"
  | "complete"
  | "reject";

const NEXT_ACTION: Partial<Record<FoodOrderState, RepasMerchantAction>> = {
  placed: "accept",
  confirmed: "prepare",
  preparing: "ready",
  ready: "handoff",
  out_for_delivery: "complete",
};

export async function repasMerchantTransition(
  orderId: string,
  action: RepasMerchantAction,
  reason?: string,
): Promise<void> {
  const { error } = await (supabase as any).rpc("repas_merchant_transition", {
    p_order_id: orderId,
    p_action: action,
    p_reason: reason ?? null,
  });
  if (error) throw new Error(translateRepasMerchantError(error.message));
}

export function translateRepasMerchantError(msg: string): string {
  const m = (msg || "").toUpperCase();
  if (m.includes("ILLEGAL_TRANSITION")) return "Cette étape n'est pas possible depuis l'état actuel.";
  if (m.includes("CASH_ORDER_NOT_ACCEPTED")) return "Commande espèces : aucun coursier engagé pour l'instant.";
  if (m.includes("CHOP_PAY_NOT_AUTHORIZED")) return "Paiement Chop Pay non autorisé sur cette commande.";
  if (m.includes("NOT_AUTHORIZED")) return "Action non autorisée.";
  if (m.includes("UNSUPPORTED_TENDER")) return "Mode de paiement non pris en charge.";
  return translateCashError(msg);
}

export async function advanceRestaurantOrder(
  orderId: string,
  current: FoodOrderState,
  fulfillment?: string | null,
): Promise<FoodOrderState> {
  const pickupHandover = fulfillment === "pickup" && current === "ready";
  const next = pickupHandover ? ("completed" as FoodOrderState) : RESTAURANT_NEXT_STATE[current];
  const action: RepasMerchantAction | undefined = pickupHandover ? "complete" : NEXT_ACTION[current];
  if (!next || !action) throw new Error("Aucune étape suivante");
  await repasMerchantTransition(orderId, action);
  return next;
}

export async function rejectRestaurantOrder(orderId: string, reason?: string): Promise<void> {
  await repasMerchantTransition(orderId, "reject", reason);
}

export async function listRestaurantMenu(restaurantId: string) {
  const { data, error } = await (supabase as any)
    .from("food_menu_items")
    .select("*")
    .eq("restaurant_id", restaurantId)
    .order("position", { ascending: true })
    .order("name", { ascending: true });
  if (error) throw error;
  return data ?? [];
}

export async function toggleMenuItemAvailable(itemId: string, available: boolean) {
  const { error } = await (supabase as any)
    .from("food_menu_items")
    .update({ is_available: available })
    .eq("id", itemId);
  if (error) throw error;
}

/* ------------------------------------------------------------------ */
/* Marché — store / listings operations                               */
/* ------------------------------------------------------------------ */

export async function setStoreDelivery(storeId: string, available: boolean) {
  const { error } = await (supabase as any)
    .from("merchant_stores")
    .update({ delivery_available: available })
    .eq("id", storeId);
  if (error) throw error;
}

export async function setStoreOpen(storeId: string, open: boolean) {
  // Marché stores use `status` ('active' / 'paused')
  const { error } = await (supabase as any)
    .from("merchant_stores")
    .update({ status: open ? "active" : "paused" })
    .eq("id", storeId);
  if (error) throw error;
}

export async function listSellerListings(sellerId: string, limit = 30) {
  const { data, error } = await (supabase as any)
    .from("marketplace_listings")
    .select("*")
    .eq("seller_id", sellerId)
    .order("created_at", { ascending: false })
    .limit(limit);
  if (error) throw error;
  return data ?? [];
}

export async function setListingAvailability(
  listingId: string,
  availability: "available" | "reserved" | "sold" | "to_confirm",
) {
  const { error } = await (supabase as any)
    .from("marketplace_listings")
    .update({ availability })
    .eq("id", listingId);
  if (error) throw error;
}

export async function listSellerInterests(sellerId: string, limit = 30) {
  // Try the embedded query first (uses the FK relationship).
  const embed = await (supabase as any)
    .from("listing_interests")
    .select("*, marketplace_listings(title)")
    .eq("seller_id", sellerId)
    .order("created_at", { ascending: false })
    .limit(limit);
  if (!embed.error) return embed.data ?? [];

  // Fallback: schema cache may be stale or FK missing — fetch in two steps.
  if (import.meta.env.DEV) {
    console.warn("[merchant] listing_interests embed failed, falling back", embed.error?.message);
  }
  const base = await (supabase as any)
    .from("listing_interests")
    .select("*")
    .eq("seller_id", sellerId)
    .order("created_at", { ascending: false })
    .limit(limit);
  if (base.error) throw base.error;
  const rows = (base.data ?? []) as any[];
  const ids = Array.from(new Set(rows.map((r) => r.listing_id).filter(Boolean)));
  if (ids.length === 0) return rows;
  const { data: listings } = await (supabase as any)
    .from("marketplace_listings")
    .select("id, title")
    .in("id", ids);
  const map = new Map<string, { title: string }>(
    ((listings ?? []) as any[]).map((l) => [l.id, { title: l.title }]),
  );
  return rows.map((r) => ({ ...r, marketplace_listings: map.get(r.listing_id) ?? null }));
}

export async function respondToInterest(
  interestId: string,
  state: "accepted" | "declined" | "fulfilled",
  response?: string,
) {
  const { error } = await (supabase as any)
    .from("listing_interests")
    .update({ state, response: response ?? null })
    .eq("id", interestId);
  if (error) throw error;
}

/* ------------------------------------------------------------------ */
/* Missions tied to this merchant                                     */
/* ------------------------------------------------------------------ */

export async function listMerchantMissions(merchantUserId: string, limit = 20) {
  const { data, error } = await (supabase as any)
    .from("missions")
    .select("*")
    .eq("merchant_id", merchantUserId)
    .order("created_at", { ascending: false })
    .limit(limit);
  if (error) throw error;
  return data ?? [];
}

/* ------------------------------------------------------------------ */
/* Lightweight analytics                                              */
/* ------------------------------------------------------------------ */

export async function getSellerAnalytics(sellerId: string) {
  // Aggregate listing_metrics across the seller's listings.
  const { data: listings } = await (supabase as any)
    .from("marketplace_listings")
    .select("id")
    .eq("seller_id", sellerId);
  const ids = (listings ?? []).map((l: any) => l.id);
  if (ids.length === 0) return { views: 0, saves: 0, messages: 0, clicks: 0, listings: 0 };
  const { data: metrics } = await (supabase as any)
    .from("listing_metrics")
    .select("*")
    .in("listing_id", ids);
  const sum = (k: string) => (metrics ?? []).reduce((n: number, m: any) => n + (m?.[k] ?? 0), 0);
  return {
    views: sum("views"),
    saves: sum("saves"),
    messages: sum("messages"),
    clicks: sum("clicks"),
    listings: ids.length,
  };
}

export async function getRestaurantAnalytics(restaurantId: string) {
  const since = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
  const { data } = await (supabase as any)
    .from("food_orders")
    .select("state,subtotal_gnf,created_at")
    .eq("restaurant_id", restaurantId)
    .gte("created_at", since);
  const rows = (data ?? []) as { state: FoodOrderState; subtotal_gnf: number }[];
  const completed = rows.filter((r) => r.state === "completed");
  return {
    orders7d: rows.length,
    completed7d: completed.length,
    revenue7d: completed.reduce((n, r) => n + (r.subtotal_gnf ?? 0), 0),
  };
}