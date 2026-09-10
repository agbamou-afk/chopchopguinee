import { supabase } from "@/integrations/supabase/client";

/**
 * G6 — Orange Money receiving-account governed client seam.
 *
 * Constitutional law (see docs/admin/G6_FINAL_ADMIN_ARCHITECTURE_LOCK.md §15):
 * - The browser can never insert, update or delete a receiving account row.
 *   Table grants are revoked and a database trigger refuses any write that did
 *   not come from a governed RPC.
 * - Metadata (label, public instructions, internal notes) → allow mode under
 *   `finance.receiving_account.manage`.
 * - Activation / deactivation → explicit act, mandatory reason, same capability.
 * - Routing change (the Orange Money number itself) → `finance.receiving_account.route`,
 *   approval_required (four-eyes). An account already referenced by a top-up or a
 *   provider event is never rewritten: it is retired and superseded by a new
 *   versioned row, so historical financial meaning is preserved.
 * - Operations has no grant at all on either capability (absence = denial).
 */

export type ReceivingAccount = {
  id: string;
  provider: string;
  label: string;
  phone_e164: string;
  is_active: boolean;
  public_instructions: string | null;
  admin_notes: string | null;
  version: number;
  effective_from: string;
  retired_at: string | null;
  superseded_by: string | null;
  created_at: string;
  updated_at: string;
};

const MESSAGES: Record<string, string> = {
  capability_denied: "Votre rôle ne permet pas cette action sur les comptes de réception.",
  approval_required: "Cette modification de routage exige une approbation à quatre yeux.",
  approval_invalid: "L'approbation fournie ne correspond pas exactement à cette action.",
  approval_consumed: "Cette approbation a déjà été utilisée.",
  approval_expired: "Cette approbation a expiré.",
  reason_required: "Un motif est obligatoire.",
  label_required: "Le libellé est obligatoire.",
  invalid_receiving_phone: "Numéro invalide. Format attendu : +224 suivi de 9 chiffres.",
  routing_unchanged: "Le numéro est identique : aucune modification de routage.",
  receiving_account_not_found: "Compte de réception introuvable.",
  receiving_account_retired: "Ce compte a été retiré : il ne peut plus être réactivé ni modifié.",
  receiving_account_governed_rpc_required:
    "Écriture directe refusée : cette opération doit passer par une action contrôlée.",
};

export function receivingAccountError(raw: string | null | undefined): string {
  if (!raw) return "Action refusée.";
  const key = Object.keys(MESSAGES).find((k) => raw.includes(k));
  return key ? MESSAGES[key] : raw;
}

export async function fetchReceivingAccounts(): Promise<ReceivingAccount[]> {
  const { data } = await supabase
    .from("payment_receiving_accounts")
    .select("*")
    .order("provider", { ascending: true })
    .order("version", { ascending: false })
    .order("updated_at", { ascending: false });
  return (data ?? []) as unknown as ReceivingAccount[];
}

type Result = { ok: true } | { ok: false; error: string };

async function call(fn: string, args: Record<string, unknown>): Promise<Result> {
  const { error } = await (supabase as unknown as {
    rpc: (n: string, a: Record<string, unknown>) => Promise<{ error: { message: string } | null }>;
  }).rpc(fn, args);
  if (error) return { ok: false, error: receivingAccountError(error.message) };
  return { ok: true };
}

export function createReceivingAccount(input: {
  provider?: string;
  label: string;
  phone: string;
  instructions?: string | null;
  notes?: string | null;
}): Promise<Result> {
  return call("admin_receiving_account_create", {
    p_provider: input.provider ?? "orange_money",
    p_label: input.label,
    p_phone_e164: input.phone,
    p_public_instructions: input.instructions ?? null,
    p_admin_notes: input.notes ?? null,
  });
}

export function updateReceivingAccountMetadata(input: {
  id: string;
  label: string;
  instructions?: string | null;
  notes?: string | null;
}): Promise<Result> {
  return call("admin_receiving_account_update_metadata", {
    p_id: input.id,
    p_label: input.label,
    p_public_instructions: input.instructions ?? null,
    p_admin_notes: input.notes ?? null,
  });
}

export function setReceivingAccountActive(id: string, active: boolean, reason: string): Promise<Result> {
  return call("admin_receiving_account_set_active", { p_id: id, p_active: active, p_reason: reason });
}

export function replaceReceivingAccountRouting(
  id: string,
  newPhone: string,
  reason: string,
  approvalId?: string | null,
): Promise<Result> {
  return call("admin_receiving_account_replace_routing", {
    p_id: id,
    p_new_phone_e164: newPhone,
    p_reason: reason,
    _g2_approval: approvalId ?? null,
  });
}
