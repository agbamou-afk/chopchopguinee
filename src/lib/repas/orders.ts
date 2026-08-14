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
import { FOOD_ORDER_SAFE_COLS } from "@/lib/missions/columns";
import type { RepasLocationSource } from "./destinationDraft";

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
  /** R11 — Conakry landmark ("près de Prima Center"). Stored verbatim. */
  deliveryLandmark?: string;
  /** R11 — arrival instructions ("portail bleu, appeler en arrivant"). */
  deliveryInstructions?: string;
  /** R11 — how the point was obtained. The server derives the quality verdict. */
  locationSource?: RepasLocationSource;
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
  REPAS_DESTINATION_IMMUTABLE:
    "La destination de cette commande est figée et ne peut plus être modifiée.",
  CHOP_PAY_CHECKOUT_DISABLED: "Le paiement Chop Pay n'est pas encore activé.",
  MENU_ITEM_NOT_FOUND: "Un article n'est plus au menu.",
  ITEM_WRONG_RESTAURANT: "Un article ne provient pas de ce restaurant.",
  ITEM_UNAVAILABLE: "Un article n'est plus disponible.",
  INVALID_QUANTITY: "Quantité invalide.",
  PICKUP_CASH_NOT_SUPPORTED:
    "Le retrait sur place se règle uniquement avec Chop Pay pour le moment.",
  PICKUP_HAS_NO_COURIER_HANDOFF: "Une commande à retirer n'a pas de livreur.",
  CASH_ORDER_FUNDING_DISABLED: "Le paiement en espèces n'est pas encore activé.",
  CUSTOMER_CASH_RESTRICTED_BY_DEBT:
    "Des frais d'annulation restent dus : réglez-les avant une nouvelle commande en espèces.",
  OUTSIDE_DELIVERY_ZONE:
    "Cette adresse est en dehors de la zone de livraison de ce restaurant.",
  DELIVERY_DISTANCE_UNVERIFIABLE:
    "Impossible de vérifier la distance : précisez votre position pour la livraison.",
  CASH_DELIVERY_PRICING_UNSUPPORTED:
    "Ce tarif de livraison ne peut pas être réglé en espèces. Utilisez Chop Pay.",
  REPAS_PRICING_NOT_CONFIGURED:
    "La tarification Repas n'est pas encore configurée. Réessayez plus tard.",
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
    p_delivery_landmark: input.deliveryLandmark?.trim() || null,
    p_delivery_instructions: input.deliveryInstructions?.trim() || null,
    p_location_source: input.locationSource ?? "unspecified",
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
    .select(FOOD_ORDER_SAFE_COLS)
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(limit);
  if (error) throw error;
  return (data ?? []) as FoodOrder[];
}

export type { FoodPaymentMethod };

/**
 * R4.5-E — server-authoritative pre-commit quote. The client never computes
 * the platform fee or the delivery fee itself.
 */
export interface RepasQuote {
  fulfillment: FoodFulfillment;
  merchandiseSubtotalGnf: number;
  /** Catalogue delivery price before any campaign. */
  baseDeliveryFeeGnf: number;
  /** What the customer actually pays for delivery. */
  deliveryFeeGnf: number;
  promoDiscountGnf: number;
  promotionName: string | null;
  platformFeeGnf: number;
  orderTotalGnf: number;
  deliveryDistanceKm: number | null;
  deliveryMaxDistanceKm: number | null;
  deliveryEligible: boolean;
  ineligibleReason: string | null;
  pickupAvailable: boolean;
  deliveryAvailable: boolean;
  chopPayEnabled: boolean;
  cashEnabled: boolean;
  cashPickupSupported: boolean;
  transactionFeeBps: number;
}

export async function getRepasQuote(
  restaurantId: string,
  items: { menuItemId: string; qty: number }[],
  fulfillment: FoodFulfillment,
  destination?: { lat: number; lng: number } | null,
): Promise<RepasQuote> {
  const { data, error } = await (supabase as any).rpc("repas_quote_preview", {
    p_restaurant_id: restaurantId,
    p_items: items.map((i) => ({ menu_item_id: i.menuItemId, qty: i.qty })),
    p_fulfillment: fulfillment,
    p_delivery_lat: destination?.lat ?? null,
    p_delivery_lng: destination?.lng ?? null,
  });
  if (error) throw new Error(translateRepasError(error.message));
  return {
    fulfillment: data.fulfillment as FoodFulfillment,
    merchandiseSubtotalGnf: Number(data.merchandise_subtotal_gnf ?? 0),
    baseDeliveryFeeGnf: Number(data.base_delivery_fee_gnf ?? 0),
    deliveryFeeGnf: Number(data.delivery_fee_gnf ?? 0),
    promoDiscountGnf: Number(data.promo_discount_gnf ?? 0),
    promotionName: (data.promotion_name as string | null) ?? null,
    platformFeeGnf: Number(data.platform_fee_gnf ?? 0),
    orderTotalGnf: Number(data.order_total_gnf ?? 0),
    deliveryDistanceKm:
      data.delivery_distance_km === null || data.delivery_distance_km === undefined
        ? null
        : Number(data.delivery_distance_km),
    deliveryMaxDistanceKm:
      data.delivery_max_distance_km === null || data.delivery_max_distance_km === undefined
        ? null
        : Number(data.delivery_max_distance_km),
    deliveryEligible: data.delivery_eligible !== false,
    ineligibleReason: (data.ineligible_reason as string | null) ?? null,
    pickupAvailable: !!data.pickup_available,
    deliveryAvailable: !!data.delivery_available,
    chopPayEnabled: !!data.chop_pay_enabled,
    cashEnabled: !!data.cash_enabled,
    cashPickupSupported: !!data.cash_pickup_supported,
    transactionFeeBps: Number(data.transaction_fee_bps ?? 0),
  };
}

/** Human-readable explanation for a refused delivery, straight from server truth. */
export function repasIneligibleLabel(q: RepasQuote): string | null {
  if (q.deliveryEligible) return null;
  switch (q.ineligibleReason) {
    case "OUTSIDE_DELIVERY_ZONE":
      return q.deliveryDistanceKm !== null && q.deliveryMaxDistanceKm !== null
        ? `Hors zone de livraison : ${q.deliveryDistanceKm.toFixed(1)} km (maximum ${q.deliveryMaxDistanceKm} km).`
        : "Cette adresse est hors de la zone de livraison.";
    case "DESTINATION_REQUIRED":
      return "Partagez votre position pour vérifier que la livraison est possible.";
    case "DISTANCE_UNKNOWN":
      return "Distance de livraison non vérifiable pour cette adresse.";
    default:
      return "Livraison indisponible pour cette adresse.";
  }
}

/**
 * R9 — canonical recovery lookup.
 *
 * When a commit outcome is unknown (timeout, connection drop, tab killed), the
 * client must never guess and must never retry blindly into a second order.
 * It re-presents the same `client_request_id` and the server states whether a
 * canonical order already exists. Read-only: it can never create anything.
 */
export interface ResumedFoodOrder {
  orderId: string;
  state: string;
  fulfillment: FoodFulfillment;
  paymentMethod: string;
  orderTotalGnf: number;
  missionId: string | null;
  createdAt: string;
}

export async function resumeFoodOrder(
  clientRequestId: string,
): Promise<ResumedFoodOrder | null> {
  const { data, error } = await (supabase as any).rpc("repas_order_resume", {
    p_client_request_id: clientRequestId,
  });
  if (error) throw new Error(translateRepasError(error.message));
  if (!data?.found) return null;
  return {
    orderId: data.order_id as string,
    state: String(data.state),
    fulfillment: data.fulfillment as FoodFulfillment,
    paymentMethod: String(data.payment_method),
    orderTotalGnf: Number(data.order_total_gnf ?? 0),
    missionId: (data.mission_id as string | null) ?? null,
    createdAt: String(data.created_at),
  };
}
