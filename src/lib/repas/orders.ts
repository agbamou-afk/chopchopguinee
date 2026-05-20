import { supabase } from "@/integrations/supabase/client";
import type { FoodFulfillment, FoodOrder, FoodPaymentMethod } from "./types";
import { createMission } from "@/lib/missions/missions";

export interface CreateOrderInput {
  restaurantId: string;
  fulfillment: FoodFulfillment;
  paymentMethod: FoodPaymentMethod;
  notes?: string;
  deliveryAddress?: string;
  deliveryLat?: number;
  deliveryLng?: number;
  items: { menuItemId: string; name: string; unitPriceGnf: number; qty: number }[];
}

export interface CreateOrderResult {
  order: FoodOrder;
  missionId: string | null;
  /** True when a delivery was requested but no mission could be dispatched. */
  deliveryPending: boolean;
}

const REPAS_DEFAULT_COURIER_EARNING_GNF = 15000;

export async function createFoodOrder(input: CreateOrderInput): Promise<CreateOrderResult> {
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
      delivery_lat: input.deliveryLat ?? null,
      delivery_lng: input.deliveryLng ?? null,
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

  const foodOrder = order as FoodOrder;

  // --- Mission dispatch (delivery only, additive, non-blocking) -----------
  let missionId: string | null = null;
  let deliveryPending = false;

  if (input.fulfillment === "delivery") {
    deliveryPending = true;
    try {
      // Load restaurant for pickup context + delivery eligibility.
      const { data: r } = await (supabase as any)
        .from("food_restaurants")
        .select("id,name,district,delivery_available,owner_user_id")
        .eq("id", input.restaurantId)
        .maybeSingle();

      if (
        r?.delivery_available &&
        (input.deliveryAddress || (input.deliveryLat && input.deliveryLng))
      ) {
        const itemCount = input.items.reduce((n, i) => n + i.qty, 0);
        const summary = `${r.name} · ${itemCount} article${itemCount > 1 ? "s" : ""} · ${subtotal.toLocaleString("fr-FR")} GNF`;
        const mission = await createMission({
          type: "food_delivery",
          customer_id: uid,
          merchant_id: r.owner_user_id ?? null,
          pickup_address: r.district ? `${r.name} · ${r.district}` : r.name,
          dropoff_address: input.deliveryAddress ?? null,
          dropoff_lat: input.deliveryLat,
          dropoff_lng: input.deliveryLng,
          payload_summary: summary,
          estimated_earning_gnf: REPAS_DEFAULT_COURIER_EARNING_GNF,
          ref_food_order_id: foodOrder.id,
        });
        missionId = mission.id;
        deliveryPending = false;
      }
    } catch (err) {
      // Honest fallback — order stands, delivery to confirm.
      console.warn("[repas] mission dispatch failed", err);
    }
  }

  return { order: foodOrder, missionId, deliveryPending };
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
