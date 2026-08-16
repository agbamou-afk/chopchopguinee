/**
 * Node 4 — Marché R3: canonical order commitment client.
 *
 * The client may only submit listing ids, quantities, an accepted R2
 * agreement reference, destination metadata and an idempotency key.
 * Every monetary value (unit price, line total, merchandise subtotal) is
 * derived and frozen by the server; the UI must display the server response
 * and never its own arithmetic as authority.
 */
import { supabase } from "@/integrations/supabase/client";
import type { OrderCommitIntent } from "./orderRequestId";

type Rpc = { rpc: (n: string, a?: Record<string, unknown>) => Promise<{ data: unknown; error: { message: string } | null }> };
const db = supabase as unknown as Rpc;

export type MarcheOrderStatus = "committed" | "cancelled" | "expired";

export interface MarcheOrderItem {
  id: string;
  listing_id: string;
  store_id: string;
  title: string;
  qty: number;
  unit_price_gnf: number;
  line_total_gnf: number;
  source_offer_id: string | null;
}

export interface MarcheOrder {
  id: string;
  buyer_user_id: string;
  merchant_store_id: string;
  merchant_user_id: string;
  status: MarcheOrderStatus;
  merchandise_subtotal_gnf: number;
  item_count: number;
  line_count: number;
  source_offer_id: string | null;
  client_request_id: string;
  delivery_address: string | null;
  dropoff_lat: number | null;
  dropoff_lng: number | null;
  /** R3 carries no finance: always null until a later certified pass. */
  merchant_fee_gnf: number | null;
  delivery_charge_gnf: number | null;
  fee_policy_id: string | null;
  reservation_expires_at: string | null;
  cancelled_at: string | null;
  cancel_reason: string | null;
  created_at: string;
  updated_at: string;
  items: MarcheOrderItem[];
}

/** Machine-readable server refusals, translated for Guinean customers. */
const REFUSALS: Record<string, string> = {
  AUTH_REQUIRED: "Connectez-vous pour commander.",
  CLIENT_PRICE_NOT_ALLOWED: "Prix invalide : le prix est calculé par CHOP CHOP.",
  CLIENT_REQUEST_ID_REQUIRED: "Commande invalide, réessayez.",
  EMPTY_BASKET: "Votre panier est vide.",
  BASKET_TOO_LARGE: "Trop d'articles dans ce panier.",
  DUPLICATE_LINE: "Cet article est déjà dans le panier.",
  INVALID_QUANTITY: "Quantité invalide.",
  INSUFFICIENT_STOCK: "Stock insuffisant pour cette quantité.",
  OUT_OF_STOCK: "Article épuisé.",
  SINGLE_STORE_ONLY: "Une commande ne peut concerner qu'une seule boutique.",
  SELF_PURCHASE_NOT_ALLOWED: "Vous ne pouvez pas commander votre propre article.",
  IDEMPOTENCY_CONFLICT: "Panier modifié : relancez la commande.",
  QUOTE_NOT_ORDERABLE: "Cet article se traite sur devis.",
  OFFER_REQUIRED: "Un accord de prix est requis pour cet article.",
  OFFER_NOT_AGREED: "Aucun prix convenu valide pour cet article.",
  OFFER_NOT_FOUND: "Accord introuvable.",
  OFFER_NOT_FOR_THIS_BUYER: "Cet accord ne vous appartient pas.",
  OFFER_NOT_APPLICABLE: "Cet article est à prix fixe.",
  MERCHANT_STORE_REQUIRED: "Article indisponible à la commande.",
  STORE_NOT_APPROVED: "Boutique non approuvée.",
  LISTING_PAUSED: "Annonce en pause.",
  LISTING_PRIVATE: "Annonce non publiée.",
  LISTING_SOLD: "Article déjà vendu.",
  LISTING_REMOVED: "Annonce retirée.",
  LISTING_NOT_FOUND: "Annonce introuvable.",
  DEMO_SUPPLY: "Article de démonstration, non commandable.",
  SELLER_NOT_ELIGIBLE: "Vendeur non éligible.",
  INVALID_PRICE: "Prix invalide.",
  NOT_AUTHORIZED: "Action non autorisée.",
  ORDER_NOT_FOUND: "Commande introuvable.",
};

export function translateOrderError(raw: string | null | undefined): string {
  const code = (raw ?? "").trim();
  return REFUSALS[code] ?? code ?? "Erreur inattendue";
}

function asOrder(data: unknown): MarcheOrder {
  return data as MarcheOrder;
}

/**
 * Commit an order. `clientRequestId` MUST come from the durable key store so
 * that a retry of the same basket returns the same order and reserves stock
 * exactly once.
 */
export async function commitMarcheOrder(
  intent: OrderCommitIntent,
  clientRequestId: string,
): Promise<MarcheOrder> {
  const payload = {
    client_request_id: clientRequestId,
    items: intent.lines.map((l) => ({
      listing_id: l.listingId,
      qty: l.qty,
      ...(l.offerId ? { offer_id: l.offerId } : {}),
    })),
    ...(intent.deliveryAddress ? { delivery_address: intent.deliveryAddress } : {}),
    ...(intent.dropoffLat != null ? { dropoff_lat: intent.dropoffLat } : {}),
    ...(intent.dropoffLng != null ? { dropoff_lng: intent.dropoffLng } : {}),
  };
  const { data, error } = await db.rpc("marche_order_commit", { p_payload: payload });
  if (error) throw new Error(translateOrderError(error.message));
  return asOrder(data);
}

export async function cancelMarcheOrder(orderId: string, reason?: string | null): Promise<MarcheOrder> {
  const { data, error } = await db.rpc("marche_order_cancel", {
    p_order_id: orderId,
    p_reason: reason ?? null,
  });
  if (error) throw new Error(translateOrderError(error.message));
  return asOrder(data);
}

export async function getMarcheOrder(orderId: string): Promise<MarcheOrder | null> {
  const { data, error } = await db.rpc("marche_order_get", { p_order_id: orderId });
  if (error) throw new Error(translateOrderError(error.message));
  return (data as MarcheOrder | null) ?? null;
}

export async function listMyMarcheOrders(limit = 50, offset = 0): Promise<MarcheOrder[]> {
  const { data, error } = await db.rpc("marche_orders_for_buyer", { p_limit: limit, p_offset: offset });
  if (error) throw new Error(translateOrderError(error.message));
  return (data as MarcheOrder[]) ?? [];
}

export async function listMerchantMarcheOrders(
  storeId?: string | null,
  limit = 50,
  offset = 0,
): Promise<MarcheOrder[]> {
  const { data, error } = await db.rpc("marche_orders_for_merchant", {
    p_store_id: storeId ?? null,
    p_limit: limit,
    p_offset: offset,
  });
  if (error) throw new Error(translateOrderError(error.message));
  return (data as MarcheOrder[]) ?? [];
}

export async function listAdminMarcheOrders(limit = 100, offset = 0): Promise<MarcheOrder[]> {
  const { data, error } = await db.rpc("marche_orders_admin", { p_limit: limit, p_offset: offset });
  if (error) throw new Error(translateOrderError(error.message));
  return (data as MarcheOrder[]) ?? [];
}

export function orderStatusLabel(status: MarcheOrderStatus | string): string {
  switch (status) {
    case "committed": return "Commande confirmée";
    case "cancelled": return "Annulée";
    case "expired": return "Expirée";
    default: return status;
  }
}

/**
 * The ONLY amount the UI may present as the order total in R3: the server's
 * frozen merchandise subtotal. No fee, no delivery charge, no local math.
 */
export function orderDisplayTotalGnf(order: MarcheOrder): number {
  return order.merchandise_subtotal_gnf;
}
