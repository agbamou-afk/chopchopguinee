/**
 * Node 3 / R1–R3 — Repas order client bindings.
 *
 * The production checkout no longer writes to `food_orders` / `food_order_items`
 * directly. The single canonical entry point is `repas_order_create`, which:
 *  - binds the customer from auth.uid()
 *  - re-prices every line from `food_menu_items` (client prices are ignored)
 *  - validates restaurant/item orderability
 *  - creates the canonical `food_delivery` mission with the server-owned
 *    courier earning snapshot
 *  - authorizes Chop Pay through the locked Slice 5 engine in the same
 *    transaction
 *  - is idempotent on (customer, client_request_id)
 *
 * The legacy `choppay_create_payment_intent` branch has been removed.
 */
import { supabase } from "@/integrations/supabase/client";
import type { FoodFulfillment, FoodOrder, FoodPaymentMethod } from "./types";

/** Canonical launch tenders. `wallet` is deprecated and rejected server-side. */
export type RepasTender = "cash" | "choppay";

export interface CreateOrderInput {
  restaurantId: string;
  fulfillment: FoodFulfillment;
  paymentMethod: RepasTender;
  /** Sticky retry key — same value must be reused across retries. */
  clientRequestId: string;
  notes?: string;
  deliveryAddress?: string;
  deliveryLat?: number;
  deliveryLng?: number;
  items: { menuItemId: string; qty: number }[];
}

export interface CreateOrderResult {
  orderId: string;
  /** Server-authoritative subtotal. Never derived from the browser. */
  subtotalGnf: number;
  state: string;
  paymentMethod: RepasTender;
  missionId: string | null;
  deliveryPending: boolean;
  replay: boolean;
}

const ERROR_FR: Record<string, string> = {
  NOT_AUTHENTICATED: "Connectez-vous pour commander.",
  CLIENT_REQUEST_ID_REQUIRED: "Requête invalide.",
  UNSUPPORTED_TENDER: "Ce mode de paiement n'est plus pris en charge.",
  INVALID_FULFILLMENT: "Mode de retrait invalide.",
  EMPTY_CART: "Votre panier est vide.",
  CART_TOO_LARGE: "Panier trop volumineux.",
  IDEMPOTENCY_CONFLICT: "Cette commande a déjà été envoyée avec un contenu différent.",
  RESTAURANT_NOT_FOUND: "Restaurant introuvable.",
  RESTAURANT_NOT_ORDERABLE: "Ce restaurant n'accepte pas encore de commandes.",
  RESTAURANT_CLOSED: "Ce restaurant est fermé pour le moment.",
  DELIVERY_NOT_AVAILABLE: "Ce restaurant ne fait pas de livraison.",
  PICKUP_NOT_AVAILABLE: "Ce restaurant ne fait pas de retrait sur place.",
  DELIVERY_LOCATION_REQUIRED: "Indiquez une adresse de livraison.",
  CHOP_PAY_CHECKOUT_DISABLED: "Le paiement Chop Pay n'est pas encore activé.",
  MENU_ITEM_NOT_FOUND: "Un article n'est plus au menu.",
  ITEM_WRONG_RESTAURANT: "Un article ne provient pas de ce restaurant.",
  ITEM_UNAVAILABLE: "Un article n'est plus disponible.",
  INVALID_QUANTITY: "Quantité invalide.",
};

export function translateRepasError(msg: string): string {
  const raw = (msg || "").toUpperCase();
  for (const [k, v] of Object.entries(ERROR_FR)) if (raw.includes(k)) return v;
  return msg || "Impossible de passer la commande.";
}

export async function createFoodOrder(input: CreateOrderInput): Promise<CreateOrderResult> {
  const { data, error } = await (supabase as any).rpc("repas_order_create", {
    p_restaurant_id: input.restaurantId,
    p_items: input.items.map((i) => ({ menu_item_id: i.menuItemId, qty: i.qty })),
    p_fulfillment: input.fulfillment,
    p_payment_method: input.paymentMethod,
    p_client_request_id: input.clientRequestId,
    p_delivery_address: input.deliveryAddress ?? null,
    p_delivery_lat: input.deliveryLat ?? null,
    p_delivery_lng: input.deliveryLng ?? null,
    p_notes: input.notes ?? null,
  });
  if (error) throw new Error(translateRepasError(error.message));

  const missionId = (data?.mission_id as string | null) ?? null;
  return {
    orderId: data.order_id as string,
    subtotalGnf: Number(data.subtotal_gnf ?? 0),
    state: String(data.state ?? "placed"),
    paymentMethod: input.paymentMethod,
    missionId,
    deliveryPending: input.fulfillment === "delivery" && !missionId,
    replay: !!data.replay,
  };
}

/** Canonical customer cancellation — denied once the kitchen is preparing. */
export async function cancelMyFoodOrder(orderId: string, reason?: string) {
  const { data, error } = await (supabase as any).rpc("repas_customer_cancel_order", {
    p_order_id: orderId,
    p_reason: reason ?? null,
  });
  if (error) {
    if ((error.message || "").includes("REPAS_PREPARATION_LOCKED")) {
      throw new Error("La préparation a commencé : contactez le restaurant ou ouvrez un litige.");
    }
    throw new Error(translateRepasError(error.message));
  }
  return data;
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

export type { FoodPaymentMethod };
