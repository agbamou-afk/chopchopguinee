import { supabase } from "@/integrations/supabase/client";
import type { FoodMenuItem, FoodRestaurant } from "./types";

export async function listOpenRestaurants(limit = 30): Promise<FoodRestaurant[]> {
  const { data, error } = await (supabase as any)
    .from("food_restaurants")
    .select("*")
    .eq("status", "active")
    .order("is_open", { ascending: false })
    .order("name", { ascending: true })
    .limit(limit);
  if (error) throw error;
  return (data ?? []) as FoodRestaurant[];
}

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
