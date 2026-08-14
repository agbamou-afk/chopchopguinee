import { supabase } from "@/integrations/supabase/client";
import type { FoodMenuItem } from "./types";

/**
 * Node 3 — R8 Discovery Truth.
 *
 * The client never derives visibility, openness or orderability. Those three
 * concepts are distinct and all three come from the server read models:
 *  - visibility    -> the row is returned at all (published supply only)
 *  - is_open       -> merchant-declared opening state
 *  - orderable_now -> published AND open AND real stock AND a usable fulfilment
 */
export interface RepasDiscoveryRestaurant {
  id: string;
  name: string;
  cuisine: string | null;
  district: string | null;
  cover_url: string | null;
  avatar_url: string | null;
  is_open: boolean;
  prep_time_min: number;
  delivery_available: boolean;
  pickup_available: boolean;
  choppay_enabled: boolean;
  verified: boolean;
  has_coordinates: boolean;
  delivery_ready: boolean;
  pickup_ready: boolean;
  menu_items_total: number;
  menu_items_available: number;
  orderable_now: boolean;
  blocked_reason: RepasBlockedReason | null;
}

export interface RepasRestaurantPublic extends RepasDiscoveryRestaurant {
  published: boolean;
  publication_state: "published" | "draft" | "suspended";
  viewer_is_owner: boolean;
}

export type RepasBlockedReason =
  | "not_published"
  | "closed"
  | "no_menu"
  | "no_available_items"
  | "no_fulfillment";

export const REPAS_BLOCKED_REASON_LABEL: Record<RepasBlockedReason, string> = {
  not_published: "Ce restaurant n'est pas encore publié.",
  closed: "Restaurant fermé pour le moment.",
  no_menu: "Menu pas encore renseigné.",
  no_available_items: "Aucun plat disponible pour le moment.",
  no_fulfillment: "Aucun mode de récupération disponible.",
};

export function repasBlockedLabel(reason: string | null | undefined): string | null {
  if (!reason) return null;
  return REPAS_BLOCKED_REASON_LABEL[reason as RepasBlockedReason] ?? "Commande indisponible.";
}

/** Short chip label for a discovery card. */
export function repasAvailabilityLabel(r: RepasDiscoveryRestaurant): string {
  if (r.orderable_now) return "Commande ouverte";
  if (r.blocked_reason === "closed") return "Fermé";
  if (r.blocked_reason === "no_available_items") return "Plats épuisés";
  return "Indisponible";
}

export async function discoverRestaurants(
  search: string | null,
  limit = 40,
): Promise<RepasDiscoveryRestaurant[]> {
  const { data, error } = await (supabase as any).rpc("repas_restaurants_discover", {
    p_search: search && search.trim().length > 0 ? search.trim() : null,
    p_limit: limit,
  });
  if (error) throw error;
  return (data ?? []) as RepasDiscoveryRestaurant[];
}

export async function getPublicRestaurant(id: string): Promise<RepasRestaurantPublic | null> {
  const { data, error } = await (supabase as any).rpc("repas_restaurant_public", {
    p_restaurant_id: id,
  });
  if (error) throw error;
  return (data ?? null) as RepasRestaurantPublic | null;
}

export async function getPublicMenu(id: string): Promise<FoodMenuItem[]> {
  const { data, error } = await (supabase as any).rpc("repas_restaurant_menu_public", {
    p_restaurant_id: id,
  });
  if (error) throw error;
  return ((data ?? []) as Array<Record<string, unknown>>).map((row) => ({
    id: row.id as string,
    restaurant_id: row.restaurant_id as string,
    name: row.name as string,
    description: (row.description ?? null) as string | null,
    photo_url: (row.photo_url ?? null) as string | null,
    price_gnf: Number(row.price_gnf ?? 0),
    category: (row.category ?? null) as string | null,
    is_available: !!row.is_available,
    prep_time_min: (row.prep_time_min ?? null) as number | null,
    position: Number(row.sort_position ?? 0),
  }));
}

export type RepasPublicationAction = "publish" | "unpublish" | "suspend" | "reject";

/** Staff-only. Owners cannot publish themselves — the database refuses it. */
export async function setRestaurantPublication(
  restaurantId: string,
  action: RepasPublicationAction,
  reason?: string,
): Promise<void> {
  const { error } = await (supabase as any).rpc("repas_admin_set_publication", {
    p_restaurant_id: restaurantId,
    p_action: action,
    p_reason: reason ?? null,
  });
  if (error) throw error;
}