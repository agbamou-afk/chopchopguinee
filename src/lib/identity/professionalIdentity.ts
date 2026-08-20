import { supabase } from "@/integrations/supabase/client";

/**
 * Node 5 · A2 — canonical professional identity read surface.
 *
 * Every ChopChop account is a customer account. A customer may additionally
 * hold AT MOST ONE active professional identity ("lane"): driver or merchant.
 * The lane is NOT approval truth: driver approval still lives in the driver
 * profile, merchant approval still lives in store/restaurant truth.
 */
export type ProfessionalType = "none" | "driver" | "merchant";

export interface ProfessionalIdentity {
  professional_type: ProfessionalType;
  claim_state: "active" | null;
  identity_id: string | null;
  claimed_at: string | null;
}

const NONE: ProfessionalIdentity = {
  professional_type: "none",
  claim_state: null,
  identity_id: null,
  claimed_at: null,
};

/**
 * Returns the caller's current professional lane. Server-derived only.
 * Signed-out callers resolve to "none" (the RPC itself refuses with
 * AUTH_REQUIRED — never trust a client-side lane value).
 */
export async function fetchProfessionalIdentity(): Promise<ProfessionalIdentity> {
  const { data, error } = await (supabase as any).rpc("professional_identity_current");
  if (error) return NONE;
  const row = (data ?? null) as Partial<ProfessionalIdentity> | null;
  const type = row?.professional_type;
  return {
    professional_type: type === "driver" || type === "merchant" ? type : "none",
    claim_state: row?.claim_state === "active" ? "active" : null,
    identity_id: row?.identity_id ?? null,
    claimed_at: row?.claimed_at ?? null,
  };
}

/** App modes a user may switch into, derived from the server lane only. */
export function availableModes(identity: ProfessionalIdentity): Array<"client" | "driver" | "merchant"> {
  if (identity.professional_type === "driver") return ["client", "driver"];
  if (identity.professional_type === "merchant") return ["client", "merchant"];
  return ["client"];
}
