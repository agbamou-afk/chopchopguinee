/**
 * Repas merchant-side operations — menu CRUD with photo upload, restaurant
 * profile editing, and order detail enrichment.
 *
 * Storage strategy: the workspace blocks creating new public buckets, so menu
 * photos are stored under the existing public `marche-listings` bucket at
 * `{owner_user_id}/repas-menu/{restaurant_id}/{uuid}.{ext}`. The existing
 * storage policy already restricts writes to the auth.uid() prefix, so no
 * new policy is needed and reads stay public.
 *
 * No wallet, pricing, payment_status, or settlement logic is touched.
 * Order state advancement still flows through the existing
 * `advanceRestaurantOrder` / `repas_complete_order` RPC.
 */
import { supabase } from "@/integrations/supabase/client";
import type {
  FoodMenuItem,
  FoodOrder,
  FoodOrderState,
} from "./types";

const MENU_BUCKET = "marche-listings";
const MENU_PREFIX = "repas-menu";
const MAX_BYTES = 5 * 1024 * 1024;
const ALLOWED_MIME = ["image/jpeg", "image/png", "image/webp"];

export const REPAS_MENU_CATEGORIES = [
  "Plats",
  "Boissons",
  "Petit déjeuner",
  "Grillades",
  "Desserts",
  "Accompagnements",
  "Autre",
] as const;
export type RepasMenuCategory = (typeof REPAS_MENU_CATEGORIES)[number];

export interface CreateMenuItemInput {
  restaurantId: string;
  name: string;
  description?: string | null;
  price_gnf: number;
  category?: string | null;
  prep_time_min?: number | null;
  is_available?: boolean;
  photo_url?: string | null;
}

export async function createMenuItem(input: CreateMenuItemInput): Promise<FoodMenuItem> {
  const payload = {
    restaurant_id: input.restaurantId,
    name: input.name.trim(),
    description: input.description?.trim() || null,
    price_gnf: Math.max(0, Math.round(input.price_gnf)),
    category: input.category?.trim() || null,
    prep_time_min: input.prep_time_min ?? null,
    is_available: input.is_available ?? true,
    photo_url: input.photo_url ?? null,
  };
  const { data, error } = await (supabase as any)
    .from("food_menu_items")
    .insert(payload)
    .select("*")
    .single();
  if (error) throw error;
  return data as FoodMenuItem;
}

export interface UpdateMenuItemInput {
  name?: string;
  description?: string | null;
  price_gnf?: number;
  category?: string | null;
  prep_time_min?: number | null;
  is_available?: boolean;
  photo_url?: string | null;
}

export async function updateMenuItem(itemId: string, patch: UpdateMenuItemInput): Promise<void> {
  const { error } = await (supabase as any)
    .from("food_menu_items")
    .update(patch)
    .eq("id", itemId);
  if (error) throw error;
}

export async function deleteMenuItem(itemId: string): Promise<void> {
  const { error } = await (supabase as any)
    .from("food_menu_items")
    .delete()
    .eq("id", itemId);
  if (error) throw error;
}

/**
 * Upload a menu item photo and return the public URL.
 * Path: `{owner_user_id}/repas-menu/{restaurant_id}/{uuid}.{ext}` so the
 * existing marche-listings RLS (foldername[1] = auth.uid()) accepts it.
 */
export async function uploadMenuItemPhoto(opts: {
  ownerUserId: string;
  restaurantId: string;
  file: File;
}): Promise<string> {
  if (!ALLOWED_MIME.includes(opts.file.type)) {
    throw new Error("Format d'image non supporté (JPEG, PNG ou WebP).");
  }
  if (opts.file.size > MAX_BYTES) {
    throw new Error("Image trop lourde (5 Mo max).");
  }
  const ext = (opts.file.name.split(".").pop() || "jpg").toLowerCase();
  const path = `${opts.ownerUserId}/${MENU_PREFIX}/${opts.restaurantId}/${crypto.randomUUID()}.${ext}`;
  const { error: upErr } = await (supabase as any).storage
    .from(MENU_BUCKET)
    .upload(path, opts.file, { contentType: opts.file.type, upsert: false });
  if (upErr) throw new Error(upErr.message || "Téléversement impossible.");
  const { data: pub } = (supabase as any).storage.from(MENU_BUCKET).getPublicUrl(path);
  return pub?.publicUrl as string;
}

/* ------------------------------------------------------------------ */
/* Restaurant profile (owner editor)                                  */
/* ------------------------------------------------------------------ */

export interface UpdateRestaurantProfileInput {
  name?: string;
  cuisine?: string | null;
  district?: string | null;
  prep_time_min?: number;
  delivery_available?: boolean;
  pickup_available?: boolean;
  avatar_url?: string | null;
  cover_url?: string | null;
}

export async function updateRestaurantProfile(
  restaurantId: string,
  patch: UpdateRestaurantProfileInput,
): Promise<void> {
  const { error } = await (supabase as any)
    .from("food_restaurants")
    .update(patch)
    .eq("id", restaurantId);
  if (error) throw error;
}

export async function uploadRestaurantImage(opts: {
  ownerUserId: string;
  restaurantId: string;
  file: File;
  kind: "avatar" | "cover";
}): Promise<string> {
  const url = await uploadMenuItemPhoto({
    ownerUserId: opts.ownerUserId,
    restaurantId: opts.restaurantId,
    file: opts.file,
  });
  await updateRestaurantProfile(opts.restaurantId, {
    [opts.kind === "avatar" ? "avatar_url" : "cover_url"]: url,
  });
  return url;
}

/* ------------------------------------------------------------------ */
/* Order detail enrichment (items + customer + delivery context)      */
/* ------------------------------------------------------------------ */

export interface FoodOrderItemDetail {
  id: string;
  name_snapshot: string;
  unit_price_gnf: number;
  qty: number;
}

export interface FoodOrderCustomer {
  user_id: string;
  full_name: string | null;
  phone: string | null;
}

export interface FoodOrderMissionSummary {
  id: string;
  state: string;
  courier_id: string | null;
}

export interface FoodOrderDetail extends FoodOrder {
  items: FoodOrderItemDetail[];
  customer: FoodOrderCustomer | null;
  mission: FoodOrderMissionSummary | null;
}

export async function getRestaurantOrderDetail(orderId: string): Promise<FoodOrderDetail | null> {
  const { data: order, error } = await (supabase as any)
    .from("food_orders")
    .select("*")
    .eq("id", orderId)
    .maybeSingle();
  if (error || !order) return null;

  const { data: itemRows } = await (supabase as any)
    .from("food_order_items")
    .select("id, name_snapshot, unit_price_gnf, qty")
    .eq("order_id", orderId);

  let customer: FoodOrderCustomer | null = null;
  try {
    const { data: prof } = await (supabase as any)
      .from("profiles")
      .select("user_id, full_name, phone")
      .eq("user_id", (order as FoodOrder).user_id)
      .maybeSingle();
    if (prof) customer = prof as FoodOrderCustomer;
  } catch {
    /* profile RLS may block — non-fatal */
  }

  let mission: FoodOrderMissionSummary | null = null;
  if ((order as FoodOrder).fulfillment === "delivery") {
    try {
      const { data: m } = await (supabase as any)
        .from("missions")
        .select("id, state, courier_id")
        .eq("ref_food_order_id", orderId)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (m) mission = m as FoodOrderMissionSummary;
    } catch {
      /* mission may not have ref column on older deployments */
    }
  }

  return {
    ...(order as FoodOrder),
    items: (itemRows ?? []) as FoodOrderItemDetail[],
    customer,
    mission,
  };
}

/**
 * Restaurant-side order state machine label per state. Mirrors the
 * customer-facing labels but in operator voice.
 */
export const RESTAURANT_STATE_LABEL: Record<FoodOrderState, string> = {
  placed: "Nouveau",
  confirmed: "Confirmé",
  preparing: "En préparation",
  ready: "Prêt pour retrait",
  out_for_delivery: "En livraison",
  completed: "Terminé",
  cancelled: "Annulé",
};

/**
 * Mission status labels reused on the restaurant order card. We only mirror
 * the strings — we never expose route observations or driver idle location.
 */
export const RESTAURANT_MISSION_LABEL: Record<string, string> = {
  pending: "Recherche coursier",
  assigned: "Coursier assigné",
  en_route_pickup: "Coursier en route",
  arrived_pickup: "Coursier sur place",
  picked_up: "Commande récupérée",
  en_route_dropoff: "En livraison",
  delivered: "Livrée",
  cancelled: "Annulée",
  failed: "Échouée",
};