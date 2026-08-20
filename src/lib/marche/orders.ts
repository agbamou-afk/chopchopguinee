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
  /** R13 destination truth. `destination_quality` is derived by the server. */
  destination_label?: string | null;
  destination_landmark?: string | null;
  destination_instructions?: string | null;
  destination_quality?:
    | "gps_verified"
    | "manually_placed"
    | "landmark_assisted"
    | "approximate"
    | "unverifiable"
    | null;
  /**
   * R4 merchant economics. Present ONLY for the merchant that owns the order
   * and for admins; the server omits these keys for buyers. Never recomputed
   * client-side.
   */
  merchant_fee_gnf?: number | null;
  merchant_payable_gnf?: number | null;
  merchant_platform_fee_bps?: number | null;
  fee_policy_id?: string | null;
  fee_policy_effective_from?: string | null;
  economics_resolved_at?: string | null;
  /** Customer delivery economics are a separate axis and stay unresolved. */
  delivery_charge_gnf: number | null;
  delivery_pricing_state: "unresolved" | "resolved" | "not_applicable";
  /** R5 server-derived fulfillment lifecycle. Never asserted by the client. */
  fulfillment_state: string;
  fulfillment_updated_at?: string | null;
  accepted_at?: string | null;
  ready_at?: string | null;
  delivered_at?: string | null;
  rejected_at?: string | null;
  /** Merchant/admin only — buyers never receive courier mission identity. */
  mission_id?: string | null;
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
  CLIENT_ECONOMICS_NOT_ALLOWED: "Montants invalides : les montants sont calculés par CHOP CHOP.",
  MERCHANT_FEE_POLICY_MISSING: "Tarification indisponible, réessayez plus tard.",
  NO_ACTIVE_POLICY: "Tarification indisponible, réessayez plus tard.",
  ECONOMICS_IMMUTABLE: "Les montants de cette commande sont définitifs.",
  // R13
  LISTING_QUARANTINED: "Article suspendu par CHOP CHOP.",
  STORE_SUSPENDED: "Boutique momentanément suspendue.",
  NOT_ORDERABLE: "Article indisponible à la commande.",
  CLIENT_LOCATION_QUALITY_NOT_ALLOWED: "Adresse invalide : la précision est déterminée par CHOP CHOP.",
  INVALID_LOCATION_SOURCE: "Origine de position invalide.",
  DESTINATION_TEXT_TOO_LONG: "Description du lieu trop longue.",
  LISTING_REQUIRED: "Article manquant.",
  PRICE_CHANGED: "Le prix a changé.",
};

export function translateOrderError(raw: string | null | undefined): string {
  const code = (raw ?? "").trim();
  return REFUSALS[code] ?? code ?? "Erreur inattendue";
}

/* ------------------------------------------------------------------ *
 * R13 — revalidation before commitment
 * ------------------------------------------------------------------ */

export type RevalidationLineStatus =
  | "ok"
  | "price_changed"
  | "quantity_unavailable"
  | "unavailable"
  | "review_required"
  | "not_found";

export interface BasketRevalidationLine {
  listing_id: string;
  title: string | null;
  store_id: string | null;
  status: RevalidationLineStatus;
  reason: string | null;
  requested_qty: number;
  available_qty: number | null;
  unit_price_gnf: number | null;
  cached_unit_price_gnf: number | null;
  price_changed: boolean;
}

export interface BasketRevalidation {
  schema: "chopchop.marche.basket_revalidation";
  version: number;
  revalidated_at: string;
  ok: boolean;
  material_change: boolean;
  blocking_reason: string | null;
  store_id: string | null;
  /** Server-computed presentation subtotal; null when the basket is blocked. */
  merchandise_subtotal_gnf: number | null;
  item_count: number;
  line_count: number;
  lines: BasketRevalidationLine[];
}

/**
 * Re-checks an offline-composed draft against live server truth right before
 * commitment. Read-only: reserves nothing, charges nothing, promises nothing.
 * Never send a cached total — the server refuses it.
 */
export async function revalidateMarcheBasket(
  lines: { listingId: string; qty: number; offerId?: string | null; cachedUnitPriceGnf?: number | null }[],
): Promise<BasketRevalidation> {
  const payload = {
    items: lines.map((l) => ({
      listing_id: l.listingId,
      qty: l.qty,
      ...(l.offerId ? { offer_id: l.offerId } : {}),
      ...(l.cachedUnitPriceGnf != null ? { cached_unit_price_gnf: l.cachedUnitPriceGnf } : {}),
    })),
  };
  const { data, error } = await db.rpc("marche_basket_revalidate", { p_payload: payload });
  if (error) throw new Error(translateOrderError(error.message));
  return data as BasketRevalidation;
}

/** Customer-facing sentence for a revalidation outcome. Never invents numbers. */
export function revalidationMessage(r: BasketRevalidation): string | null {
  if (!r.ok) {
    const line = r.lines.find((l) => l.status !== "ok" && l.status !== "price_changed");
    const what = line?.title ? `« ${line.title} » : ` : "";
    return `${what}${translateOrderError(r.blocking_reason ?? line?.reason ?? "NOT_ORDERABLE")}`;
  }
  if (r.material_change) return "Le prix a changé depuis votre dernière connexion. Vérifiez le nouveau montant.";
  return null;
}

/* ------------------------------------------------------------------ *
 * R13 — lost-response recovery
 * ------------------------------------------------------------------ */

export interface OrderRecovery {
  schema: "chopchop.marche.order_recovery";
  version: number;
  found: boolean;
  client_request_id: string;
  order: MarcheOrder | null;
}

/**
 * After an ambiguous network failure, asks the server what it actually
 * recorded for this commitment identity. Buyer-scoped and read-only: it can
 * never create a second order.
 */
export async function recoverMarcheOrder(clientRequestId: string): Promise<MarcheOrder | null> {
  const { data, error } = await db.rpc("marche_order_recover", { p_client_request_id: clientRequestId });
  if (error) throw new Error(translateOrderError(error.message));
  const rec = data as OrderRecovery | null;
  return rec?.found ? (rec.order as MarcheOrder) : null;
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
 * The ONLY amount the UI may present to a customer as the order total: the
 * server's frozen merchandise subtotal. Customer delivery pricing is not yet
 * canonically known, and the merchant platform fee is never a customer amount.
 */
export function orderDisplayTotalGnf(order: MarcheOrder): number {
  return order.merchandise_subtotal_gnf;
}

/** True when the server did not (yet) resolve customer delivery pricing. */
export function isDeliveryPricingUnresolved(order: MarcheOrder): boolean {
  return order.delivery_pricing_state !== "resolved";
}

/**
 * Merchant/admin internal truth only: what the merchant is owed on merchandise,
 * exactly as frozen by the server. Returns null for a buyer-scoped payload.
 */
export function merchantPayableGnf(order: MarcheOrder): number | null {
  return order.merchant_payable_gnf ?? null;
}
