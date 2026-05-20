import { supabase } from "@/integrations/supabase/client";
import type { FoodOrder, FoodOrderState } from "@/lib/repas/types";

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

export async function advanceRestaurantOrder(orderId: string, current: FoodOrderState): Promise<FoodOrderState> {
  const next = RESTAURANT_NEXT_STATE[current];
  if (!next) throw new Error("Aucune étape suivante");
  const { error } = await (supabase as any)
    .from("food_orders")
    .update({ state: next })
    .eq("id", orderId);
  if (error) throw error;
  return next;
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
  const { data, error } = await (supabase as any)
    .from("listing_interests")
    .select("*, marketplace_listings(title)")
    .eq("seller_id", sellerId)
    .order("created_at", { ascending: false })
    .limit(limit);
  if (error) throw error;
  return data ?? [];
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