import { supabase } from "@/integrations/supabase/client";

export type OfferStatus =
  | "pending"
  | "accepted"
  | "rejected"
  | "countered"
  | "withdrawn"
  | "expired";

export interface MarketplaceOffer {
  id: string;
  listing_id: string;
  merchant_store_id: string | null;
  buyer_user_id: string;
  merchant_user_id: string;
  offer_amount_gnf: number;
  counter_amount_gnf: number | null;
  status: OfferStatus;
  buyer_message: string | null;
  merchant_message: string | null;
  expires_at: string | null;
  responded_at: string | null;
  created_at: string;
  updated_at: string;
  /** Frozen, mutually consented amount. Null until both sides agreed. */
  agreed_amount_gnf?: number | null;
  agreed_by_user_id?: string | null;
  agreed_at?: string | null;
  /** Whose proposal is currently on the table. */
  current_proposer_role?: "buyer" | "merchant" | null;
  expired_at?: string | null;
  payment_status?: string | null;
  payment_intent_id?: string | null;
  authorized_at?: string | null;
  paid_at?: string | null;
  fulfillment_status?: string | null;
  fulfilled_at?: string | null;
  completed_at?: string | null;
  settlement_state?: string | null;
  captured_tx_id?: string | null;
  settlement_tx_id?: string | null;
}

/** The amount currently on the table, agreement first. Never invents a price. */
export function offerActiveAmountGnf(o: MarketplaceOffer): number {
  return (
    o.agreed_amount_gnf ??
    (o.status === "countered" ? o.counter_amount_gnf ?? o.offer_amount_gnf : o.offer_amount_gnf)
  );
}

/** True when the merchant countered and the buyer must now consent. */
export function offerAwaitsBuyer(o: MarketplaceOffer): boolean {
  return o.status === "countered" && o.current_proposer_role === "merchant";
}

/** True when the merchant may still act on the offer. */
export function offerAwaitsMerchant(o: MarketplaceOffer): boolean {
  return o.status === "pending" || (o.status === "countered" && o.current_proposer_role === "buyer");
}

export async function createOffer(input: {
  listingId: string;
  amountGnf: number;
  message?: string | null;
  /** Explicit tender. Persisted atomically with the offer. Never inferred. */
  paymentMethod: "cash" | "choppay";
}): Promise<string> {
  const { data, error } = await (supabase as any).rpc("create_marketplace_offer", {
    p_listing_id: input.listingId,
    p_amount_gnf: input.amountGnf,
    p_message: input.message ?? null,
    p_payment_method: input.paymentMethod,
  });
  if (error) throw new Error(translateOfferError(error.message));
  return data as string;
}

export async function respondOffer(input: {
  offerId: string;
  action: "accept" | "reject" | "counter";
  counterAmountGnf?: number | null;
  message?: string | null;
}): Promise<void> {
  const { error } = await (supabase as any).rpc(
    "merchant_respond_marketplace_offer",
    {
      p_offer_id: input.offerId,
      p_action: input.action,
      p_counter_amount_gnf: input.counterAmountGnf ?? null,
      p_message: input.message ?? null,
    },
  );
  if (error) throw new Error(translateOfferError(error.message));
}

/** Buyer consent on a merchant counter. Accept freezes the agreement server-side. */
export async function buyerRespondOffer(input: {
  offerId: string;
  action: "accept" | "reject";
  message?: string | null;
}): Promise<void> {
  const { error } = await (supabase as any).rpc("buyer_respond_marketplace_offer", {
    p_offer_id: input.offerId,
    p_action: input.action,
    p_message: input.message ?? null,
  });
  if (error) throw new Error(translateOfferError(error.message));
}

export async function withdrawOffer(offerId: string): Promise<void> {
  const { error } = await (supabase as any).rpc("withdraw_marketplace_offer", {
    p_offer_id: offerId,
  });
  if (error) throw new Error(translateOfferError(error.message));
}

export async function getMyOfferForListing(
  listingId: string,
  buyerId: string,
): Promise<MarketplaceOffer | null> {
  const { data, error } = await (supabase as any).rpc("marche_offers_for_buyer", {
    p_listing_id: listingId,
    p_limit: 1,
  });
  if (error) return null;
  const rows = (data ?? []) as MarketplaceOffer[];
  return rows[0] ?? null;
}

export async function listMerchantOffers(merchantId: string): Promise<MarketplaceOffer[]> {
  const { data, error } = await (supabase as any).rpc("marche_offers_for_merchant", {
    p_limit: 100,
  });
  if (error) return [];
  return (data ?? []) as MarketplaceOffer[];
}

export async function listAllOffersAdmin(): Promise<MarketplaceOffer[]> {
  const { data, error } = await (supabase as any).rpc("marche_offers_admin", { p_limit: 200 });
  if (error) return [];
  return (data ?? []) as MarketplaceOffer[];
}

export function offerStatusLabel(s: OfferStatus): string {
  switch (s) {
    case "pending": return "En attente";
    case "accepted": return "Acceptée";
    case "rejected": return "Refusée";
    case "countered": return "Contre-offre";
    case "withdrawn": return "Retirée";
    case "expired": return "Expirée";
  }
}

function translateOfferError(msg: string): string {
  const m = (msg || "").toLowerCase();
  if (m.includes("offers not allowed")) return "Ce produit n'accepte pas d'offres.";
  if (m.includes("merchant_store_required")) return "Ce produit n'est pas rattaché à une boutique marchande approuvée.";
  if (m.includes("store_not_approved")) return "Boutique non approuvée.";
  if (m.includes("demo_supply")) return "Produit de démonstration : offres indisponibles.";
  if (m.includes("seller_not_eligible")) return "Ce vendeur n'est pas éligible.";
  if (m.includes("out_of_stock")) return "Produit en rupture.";
  if (m.includes("listing_paused") || m.includes("listing_private")) return "Produit indisponible.";
  if (m.includes("counter_awaits_buyer")) return "En attente de la réponse de l'acheteur.";
  if (m.includes("no_merchant_proposal")) return "Aucune contre-offre à accepter.";
  if (m.includes("offer_expired")) return "Cette offre a expiré.";
  if (m.includes("agreement_immutable") || m.includes("offer_core_immutable") || m.includes("offer_terminal"))
    return "Cette offre est verrouillée.";
  if (m.includes("out of stock")) return "Produit en rupture.";
  if (m.includes("cannot offer on own")) return "Vous ne pouvez pas faire une offre sur votre propre produit.";
  if (m.includes("listing not available")) return "Produit indisponible.";
  if (m.includes("store not active")) return "Boutique indisponible.";
  if (m.includes("pending offer already")) return "Vous avez déjà une offre en cours.";
  if (m.includes("offer closed")) return "Cette offre est déjà clôturée.";
  if (m.includes("account frozen")) return "Compte gelé.";
  if (m.includes("account blocked")) return "Compte bloqué.";
  if (m.includes("invalid amount")) return "Montant invalide.";
  if (m.includes("invalid counter")) return "Contre-offre invalide.";
  if (m.includes("invalid_tender")) return "Mode de paiement invalide.";
  if (m.includes("forbidden")) return "Action non autorisée.";
  return "Action impossible.";
}