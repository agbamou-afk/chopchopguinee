import { supabase } from "@/integrations/supabase/client";

export type MarchePaymentStatus =
  | "unpaid"
  | "pending"
  | "authorized"
  | "paid"
  | "failed"
  | "refunded"
  | "cancelled";

export interface MarcheOfferPaymentResult {
  paymentIntentId: string | null;
  paymentStatus: MarchePaymentStatus;
  intentState: string | null;
}

/**
 * Buyer-side: authorize CHOP Wallet payment for an accepted Marché offer.
 * Calls the SECURITY DEFINER RPC that wraps choppay_create_payment_intent
 * and updates marketplace_offers.payment_status. Idempotent: a repeat tap
 * returns the existing active intent.
 */
export async function authorizeMarcheOfferPayment(
  offerId: string,
): Promise<MarcheOfferPaymentResult> {
  const { data, error } = await (supabase as any).rpc(
    "marche_create_offer_payment_intent",
    { p_offer_id: offerId },
  );
  if (error) throw new Error(translatePaymentError(error.message));
  const state: string | null = data?.state ?? null;
  const paymentStatus: MarchePaymentStatus =
    state === "processing" || state === "confirmed"
      ? "authorized"
      : state === "failed"
        ? "failed"
        : state === "pending"
          ? "pending"
          : "pending";
  return {
    paymentIntentId: (data?.id as string | null) ?? null,
    paymentStatus,
    intentState: state,
  };
}

export function marchePaymentStatusLabel(s: MarchePaymentStatus | string | null | undefined): string {
  switch (s) {
    case "authorized": return "Autorisé";
    case "paid": return "Payé";
    case "failed": return "Échoué";
    case "cancelled": return "Annulé";
    case "refunded": return "Remboursé";
    case "pending": return "En attente";
    default: return "Non payé";
  }
}

function translatePaymentError(msg: string): string {
  const m = (msg || "").toLowerCase();
  if (m.includes("not_authenticated")) return "Connectez-vous pour payer.";
  if (m.includes("offer_not_found")) return "Offre introuvable.";
  if (m.includes("forbidden_not_buyer")) return "Seul l'acheteur peut payer.";
  if (m.includes("offer_not_accepted")) return "Le vendeur doit d'abord accepter l'offre.";
  if (m.includes("offer_already_paid")) return "Paiement déjà autorisé.";
  if (m.includes("listing_unavailable")) return "Annonce indisponible.";
  if (m.includes("invalid_amount")) return "Montant invalide.";
  if (m.includes("insufficient")) return "Solde CHOP insuffisant. Rechargez votre wallet.";
  return "Paiement impossible. Réessayez.";
}