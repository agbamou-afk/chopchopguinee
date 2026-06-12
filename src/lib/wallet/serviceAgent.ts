import { supabase } from "@/integrations/supabase/client";
import { normalizeGuineaPhone } from "@/lib/phone/guinea";

export interface AgentCustomerPreview {
  customer_user_id: string;
  display_name: string;
  masked_phone: string;
  wallet_exists: boolean;
}

export interface AgentCashInResult {
  id: string;
  reference: string;
  amount_gnf: number;
  status: string;
  created_at: string;
}

export async function agentLookupCustomer(rawPhone: string): Promise<AgentCustomerPreview> {
  const phone = normalizeGuineaPhone(rawPhone);
  const { data, error } = await (supabase as any).rpc("agent_lookup_customer_wallet", {
    p_phone: phone,
  });
  if (error) throw new Error(translateAgentError(error.message));
  const row = Array.isArray(data) ? data[0] : data;
  if (!row?.customer_user_id) throw new Error("Client introuvable.");
  return row as AgentCustomerPreview;
}

export async function agentCashInCustomer(input: {
  customerUserId: string;
  amountGnf: number;
  note?: string | null;
  idempotencyKey?: string;
}): Promise<AgentCashInResult> {
  const { data, error } = await (supabase as any).rpc("agent_cash_in_customer_wallet", {
    p_customer_user_id: input.customerUserId,
    p_amount_gnf: input.amountGnf,
    p_reference_note: input.note ?? null,
    p_idempotency_key: input.idempotencyKey ?? null,
  });
  if (error) throw new Error(translateAgentError(error.message));
  return data as AgentCashInResult;
}

export function translateAgentError(msg: string): string {
  const m = (msg || "").toLowerCase();
  if (m.includes("not_authenticated")) return "Connectez-vous pour continuer.";
  if (m.includes("service_agent_not_approved"))
    return "Votre compte Agent CHOP Wallet n'est pas encore approuvé.";
  if (m.includes("invalid_phone")) return "Numéro invalide.";
  if (m.includes("customer_not_found")) return "Client introuvable.";
  if (m.includes("self_cashin_forbidden"))
    return "Vous ne pouvez pas vous recharger vous-même.";
  if (m.includes("customer_unavailable")) return "Client indisponible.";
  if (m.includes("invalid_amount")) return "Montant invalide.";
  if (m.includes("agent_cash_in_limit_single_min"))
    return "Montant minimum : 1 000 GNF.";
  if (m.includes("agent_cash_in_limit_single_exceeded"))
    return "Limite par recharge dépassée (max 1 000 000 GNF).";
  if (m.includes("agent_cash_in_daily_agent_total_exceeded"))
    return "Plafond quotidien agent dépassé (5 000 000 GNF).";
  if (m.includes("agent_cash_in_daily_count_exceeded"))
    return "Trop de recharges aujourd'hui (max 25).";
  if (m.includes("agent_cash_in_daily_customer_total_exceeded"))
    return "Plafond quotidien client dépassé (2 000 000 GNF).";
  if (m.includes("customer_wallet_missing"))
    return "Portefeuille client indisponible.";
  return "Recharge impossible.";
}