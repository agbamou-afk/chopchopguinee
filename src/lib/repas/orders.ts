import { supabase } from "@/integrations/supabase/client";
import type { FoodFulfillment, FoodOrder, FoodPaymentMethod } from "./types";

export interface CreateOrderInput {
  restaurantId: string;
  fulfillment: FoodFulfillment;
  paymentMethod: FoodPaymentMethod;
  notes?: string;
  deliveryAddress?: string;
  items: { menuItemId: string; name: string; unitPriceGnf: number; qty: number }[];
}

export async function createFoodOrder(input: CreateOrderInput): Promise<FoodOrder> {
  const { data: auth } = await supabase.auth.getUser();
  const uid = auth.user?.id;
  if (!uid) throw new Error("not_authenticated");

  const subtotal = input.items.reduce((s, i) => s + i.unitPriceGnf * i.qty, 0);

  const { data: order, error } = await (supabase as any)
    .from("food_orders")
    .insert({
      user_id: uid,
      restaurant_id: input.restaurantId,
      fulfillment: input.fulfillment,
      payment_method: input.paymentMethod,
      subtotal_gnf: subtotal,
      notes: input.notes ?? null,
      delivery_address: input.deliveryAddress ?? null,
      state: "placed",
    })
    .select("*")
    .single();
  if (error) throw error;

  const itemRows = input.items.map((i) => ({
    order_id: order.id,
    menu_item_id: i.menuItemId,
    name_snapshot: i.name,
    unit_price_gnf: i.unitPriceGnf,
    qty: i.qty,
  }));
  const { error: itemsErr } = await (supabase as any).from("food_order_items").insert(itemRows);
  if (itemsErr) throw itemsErr;

  return order as FoodOrder;
}

export async function listMyFoodOrders(userId: string, limit = 20): Promise<FoodOrder[]> {
  const { data, error } = await (supabase as any)
    .from("food_orders")
    .select("*")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(limit);
  if (error) throw error;
  return (data ?? []) as FoodOrder[];
}
