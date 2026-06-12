import { supabase } from "@/integrations/supabase/client";
import { normalizeGuineaPhone } from "@/lib/phone/guinea";

export interface P2PRecipient {
  user_id: string;
  display_name: string;
  masked_phone: string;
}

export interface P2PTransferResult {
  id: string;
  reference: string;
  amount_gnf: number;
  created_at: string;
}

export async function p2pLookupRecipient(rawPhone: string): Promise<P2PRecipient> {
  const phone = normalizeGuineaPhone(rawPhone);
  const { data, error } = await (supabase as any).rpc("wallet_p2p_lookup_recipient", {
    p_phone: phone,
  });
  if (error) throw new Error(translateLookupError(error.message));
  const row = Array.isArray(data) ? data[0] : data;
  if (!row?.user_id) throw new Error("Bénéficiaire introuvable.");
  return row as P2PRecipient;
}

export async function p2pTransfer(input: {
  recipientUserId: string;
  amountGnf: number;
  note?: string | null;
  idempotencyKey?: string;
}): Promise<P2PTransferResult> {
  const { data, error } = await (supabase as any).rpc("wallet_p2p_transfer", {
    p_recipient_user_id: input.recipientUserId,
    p_amount_gnf: input.amountGnf,
    p_note: input.note ?? null,
    p_idempotency_key: input.idempotencyKey ?? null,
  });
  if (error) throw new Error(translateTransferError(error.message));
  return data as P2PTransferResult;
}

function translateLookupError(msg: string): string {
  const m = (msg || "").toLowerCase();
  if (m.includes("not_authenticated")) return "Connectez-vous pour envoyer.";
  if (m.includes("invalid_phone")) return "Numéro invalide.";
  if (m.includes("recipient_not_found")) return "Bénéficiaire introuvable.";
  if (m.includes("self_transfer_forbidden"))
    return "Vous ne pouvez pas vous envoyer de l'argent à vous-même.";
  if (m.includes("recipient_unavailable")) return "Bénéficiaire indisponible.";
  return "Recherche impossible.";
}

function translateTransferError(msg: string): string {
  const m = (msg || "").toLowerCase();
  if (m.includes("not_authenticated")) return "Connectez-vous pour envoyer.";
  if (m.includes("self_transfer_forbidden"))
    return "Vous ne pouvez pas vous envoyer de l'argent à vous-même.";
  if (m.includes("insufficient_funds")) return "Solde insuffisant.";
  if (m.includes("p2p_limit_single_min")) return "Montant minimum : 1 000 GNF.";
  if (m.includes("p2p_limit_single_exceeded"))
    return "Limite par transfert dépassée (max 500 000 GNF).";
  if (m.includes("p2p_limit_daily_total_exceeded"))
    return "Plafond quotidien dépassé (1 500 000 GNF).";
  if (m.includes("p2p_limit_daily_count_exceeded"))
    return "Trop de transferts aujourd'hui (max 10).";
  if (m.includes("recipient_unavailable")) return "Bénéficiaire indisponible.";
  if (m.includes("recipient_wallet")) return "Portefeuille bénéficiaire indisponible.";
  if (m.includes("sender_wallet")) return "Portefeuille indisponible.";
  if (m.includes("invalid_amount")) return "Montant invalide.";
  return "Transfert impossible.";
}