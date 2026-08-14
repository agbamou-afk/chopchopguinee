import { supabase } from "@/integrations/supabase/client";
import type { FoodMenuItem, FoodRestaurant } from "./types";

/**
 * Owner/merchant-side helpers only. Customer discovery goes through the
 * canonical R8 read models in `@/lib/repas/discovery`.
 */
export async function getRestaurant(id: string): Promise<FoodRestaurant | null> {
  const { data, error } = await (supabase as any)
    .from("food_restaurants")
    .select("*")
    .eq("id", id)
    .maybeSingle();
  if (error) throw error;
  return (data ?? null) as FoodRestaurant | null;
}

export async function listMenu(restaurantId: string): Promise<FoodMenuItem[]> {
  const { data, error } = await (supabase as any)
    .from("food_menu_items")
    .select("*")
    .eq("restaurant_id", restaurantId)
    .order("position", { ascending: true })
    .order("name", { ascending: true });
  if (error) throw error;
  return (data ?? []) as FoodMenuItem[];
}

function slugify(s: string) {
  return s
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 48) || "resto";
}

export async function getOwnRestaurant(ownerUserId: string): Promise<FoodRestaurant | null> {
  const { data } = await (supabase as any)
    .from("food_restaurants")
    .select("*")
    .eq("owner_user_id", ownerUserId)
    .maybeSingle();
  return (data ?? null) as FoodRestaurant | null;
}

export async function createOrUpdateRestaurant(input: {
  ownerUserId: string;
  name: string;
  cuisine?: string | null;
  district?: string | null;
  delivery_available?: boolean;
  pickup_available?: boolean;
  is_open?: boolean;
}): Promise<FoodRestaurant> {
  const existing = await getOwnRestaurant(input.ownerUserId);
  /**
   * R8 — publication state, canonical status, Chop Pay capability and the
   * owner link are staff-only. The database rejects them on update, so the
   * merchant payload never carries them.
   */
  const payload: Record<string, unknown> = {
    name: input.name,
    cuisine: input.cuisine ?? null,
    district: input.district ?? null,
    delivery_available: !!input.delivery_available,
    pickup_available: input.pickup_available ?? true,
    is_open: input.is_open ?? true,
  };
  const t = (supabase as any).from("food_restaurants");
  if (existing) {
    const { data, error } = await t.update(payload).eq("id", existing.id).select("*").single();
    if (error) throw error;
    return data as FoodRestaurant;
  }
  const { data, error } = await t
    .insert({
      ...payload,
      owner_user_id: input.ownerUserId,
      slug: `${slugify(input.name)}-${input.ownerUserId.slice(0, 6)}`,
    })
    .select("*")
    .single();
  if (error) throw error;
  return data as FoodRestaurant;
}
