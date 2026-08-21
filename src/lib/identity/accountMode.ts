import { supabase } from "@/integrations/supabase/client";
import type { ProfessionalType } from "@/lib/identity/professionalIdentity";

/**
 * Node 5 · A8 — canonical account / workspace mode surface.
 *
 * Mode is PRESENTATION ONLY. It never grants identity, capability,
 * ownership, role, wallet access or any authorization. The server derives
 * the lawful mode set from the active professional identity (A2/A3):
 *
 *   none      -> ["client"]
 *   driver    -> ["client","driver"]
 *   merchant  -> ["client","merchant"]
 *
 * An unlawful stored preference degrades to "client" on the server, so the
 * client never has to reason about stale localStorage or tampered values.
 */
export type AccountMode = "client" | "driver" | "merchant";

export interface AccountModeContext {
  professionalType: ProfessionalType;
  availableModes: AccountMode[];
  preferredMode: AccountMode | null;
  effectiveMode: AccountMode;
}

export const CLIENT_ONLY: AccountModeContext = {
  professionalType: "none",
  availableModes: ["client"],
  preferredMode: null,
  effectiveMode: "client",
};

function normalizeMode(value: unknown): AccountMode | null {
  return value === "client" || value === "driver" || value === "merchant" ? value : null;
}

function normalizeModes(value: unknown): AccountMode[] {
  const list = Array.isArray(value) ? value : [];
  const modes = list.map(normalizeMode).filter((m): m is AccountMode => m !== null);
  return modes.length > 0 ? modes : ["client"];
}

/** Server-authoritative workspace context for the signed-in caller. */
export async function fetchAccountModeContext(): Promise<AccountModeContext> {
  const { data, error } = await (supabase as any).rpc("account_mode_context");
  if (error || !data) return CLIENT_ONLY;
  const row = data as Record<string, unknown>;
  const type = row.professional_type;
  return {
    professionalType: type === "driver" || type === "merchant" ? type : "none",
    availableModes: normalizeModes(row.available_modes),
    preferredMode: normalizeMode(row.preferred_mode),
    effectiveMode: normalizeMode(row.effective_mode) ?? "client",
  };
}

export interface AccountModeSetResult {
  effectiveMode: AccountMode;
  refused: boolean;
  availableModes: AccountMode[];
}

/**
 * Persist a preferred workspace. The server validates against the active
 * professional lane and silently degrades an unlawful request to "client".
 */
export async function setAccountMode(mode: AccountMode): Promise<AccountModeSetResult> {
  const { data, error } = await (supabase as any).rpc("account_mode_set", { p_mode: mode });
  if (error || !data) {
    return { effectiveMode: "client", refused: mode !== "client", availableModes: ["client"] };
  }
  const row = data as Record<string, unknown>;
  return {
    effectiveMode: normalizeMode(row.effective_mode) ?? "client",
    refused: row.refused === true,
    availableModes: normalizeModes(row.available_modes),
  };
}

export function modeLabel(mode: AccountMode): string {
  if (mode === "driver") return "Chauffeur";
  if (mode === "merchant") return "Marchand";
  return "Client";
}
