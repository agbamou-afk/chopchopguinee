import { createMission } from "@/lib/missions/missions";
import type { Mission } from "@/lib/missions/types";
import type { MerchantStore } from "@/lib/marche/stores";

/**
 * Marché → Mission dispatch wiring.
 *
 * Lightweight bridge that turns an agreed Marché transaction into a
 * `marketplace_delivery` mission. The cultural default in Conakry remains
 * in-person exchange — this helper is only used when both parties opt in.
 *
 * No new tables, no fake ETAs, no fake fees. We just hand the existing
 * unified Missions pipeline enough context to find a courier with the
 * `marketplace_delivery` capability.
 */

export type MarcheDeliveryEligibilityInput = {
  status?: string | null;
  availability?: string | null;
  delivery_available?: boolean | null;
  fulfillment_options?: string[] | null;
  store?: Pick<MerchantStore, "delivery_available"> | null;
};

/** Whether a listing can offer CHOP delivery at all. */
export function isMarcheDeliveryEligible(input: MarcheDeliveryEligibilityInput): boolean {
  if (input.status && input.status !== "active") return false;
  if (input.availability === "sold" || input.availability === "cancelled") return false;
  const fulfillment = input.fulfillment_options ?? [];
  if (fulfillment.includes("in_person_only")) return false;
  return (
    !!input.delivery_available ||
    fulfillment.includes("chop_delivery") ||
    !!input.store?.delivery_available
  );
}

export interface RequestMarcheDeliveryInput {
  listing: {
    id: string;
    title: string;
    category?: string | null;
    price_gnf?: number | null;
    neighborhood?: string | null;
    commune?: string | null;
    landmark?: string | null;
  };
  buyerId: string;
  sellerName?: string | null;
  storeId?: string | null;
  storeName?: string | null;
  pickupAddress?: string | null;
  dropoffAddress: string;
  notes?: string | null;
  paymentMethod?: "cash" | "choppay" | null;
  /** Optional reference to a future `market_orders` row. */
  refMarketOrderId?: string | null;
}

function joinAddress(parts: Array<string | null | undefined>): string {
  return parts.filter((p) => !!p && p!.trim().length).join(" · ") || "Conakry";
}

/** Build the calm operational summary stored on the mission row. */
export function summarizeMarcheDelivery(input: RequestMarcheDeliveryInput): string {
  const lines: string[] = [];
  lines.push(`Article : ${input.listing.title}`);
  if (input.listing.category) lines.push(`Catégorie : ${input.listing.category}`);
  if (input.storeName) lines.push(`Boutique : ${input.storeName}`);
  else if (input.sellerName) lines.push(`Vendeur : ${input.sellerName}`);
  if (input.paymentMethod === "choppay") lines.push("Paiement : WONGO Pay");
  else if (input.paymentMethod === "cash") lines.push("Paiement : Cash à la livraison");
  if (input.notes && input.notes.trim()) lines.push(`Note : ${input.notes.trim()}`);
  return lines.join(" • ");
}

export async function requestMarcheDelivery(
  input: RequestMarcheDeliveryInput,
): Promise<Mission> {
  const pickupAddress = input.pickupAddress?.trim()
    ? input.pickupAddress
    : joinAddress([input.listing.neighborhood, input.listing.commune, input.listing.landmark]);

  return createMission({
    type: "marketplace_delivery",
    customer_id: input.buyerId,
    merchant_id: input.storeId ?? null,
    pickup_address: pickupAddress,
    dropoff_address: input.dropoffAddress,
    payload_summary: summarizeMarcheDelivery(input),
    estimated_earning_gnf: 0,
    ref_market_order_id: input.refMarketOrderId ?? undefined,
  });
}