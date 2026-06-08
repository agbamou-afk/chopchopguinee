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
}

export async function createOffer(input: {
  listingId: string;
  amountGnf: number;
  message?: string | null;
}): Promise<string> {
  const { data, error } = await (supabase as any).rpc("create_marketplace_offer", {
    p_listing_id: input.listingId,
    p_amount_gnf: input.amountGnf,
    p_message: input.message ?? null,
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
  const { data, error } = await (supabase as any)
    .from("marketplace_offers")
    .select("*")
    .eq("listing_id", listingId)
    .eq("buyer_user_id", buyerId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) return null;
  return (data as MarketplaceOffer) ?? null;
}

export async function listMerchantOffers(merchantId: string): Promise<MarketplaceOffer[]> {
  const { data, error } = await (supabase as any)
    .from("marketplace_offers")
    .select("*")
    .eq("merchant_user_id", merchantId)
    .order("created_at", { ascending: false })
    .limit(100);
  if (error) return [];
  return (data ?? []) as MarketplaceOffer[];
}

export async function listAllOffersAdmin(): Promise<MarketplaceOffer[]> {
  const { data, error } = await (supabase as any)
    .from("marketplace_offers")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(200);
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
  if (m.includes("forbidden")) return "Action non autorisée.";
  return "Action impossible.";
}