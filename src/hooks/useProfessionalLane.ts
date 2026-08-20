import { useCallback, useEffect, useState } from "react";
import { useAuth } from "@/contexts/AuthContext";
import {
  fetchProfessionalIdentity,
  type ProfessionalIdentity,
  type ProfessionalType,
} from "@/lib/identity/professionalIdentity";

const NONE: ProfessionalIdentity = {
  professional_type: "none",
  claim_state: null,
  identity_id: null,
  claimed_at: null,
};

/**
 * Node 5 · A3 — client read of the server-authoritative professional lane.
 *
 * The server refuses conflicting onboarding regardless of what the UI shows;
 * this hook only exists so the app can be honest BEFORE the user fills a form.
 */
export function useProfessionalLane() {
  const { isLoggedIn, ready } = useAuth();
  const [identity, setIdentity] = useState<ProfessionalIdentity>(NONE);
  const [loading, setLoading] = useState(true);

  const refetch = useCallback(async () => {
    if (!isLoggedIn) {
      setIdentity(NONE);
      setLoading(false);
      return;
    }
    setLoading(true);
    setIdentity(await fetchProfessionalIdentity());
    setLoading(false);
  }, [isLoggedIn]);

  useEffect(() => {
    if (!ready) return;
    void refetch();
  }, [ready, refetch]);

  const lane = identity.professional_type;
  return {
    identity,
    lane,
    loading: loading || !ready,
    /** True when the user already holds the OTHER professional class. */
    blockedFor: (wanted: Exclude<ProfessionalType, "none">) =>
      lane !== "none" && lane !== wanted,
    refetch,
  };
}

/** Machine-readable server refusal for a conflicting lane claim. */
export const PROFESSIONAL_IDENTITY_CONFLICT = "PROFESSIONAL_IDENTITY_CONFLICT";

export function laneConflictMessage(lane: ProfessionalType): string {
  if (lane === "driver") {
    return "Votre compte est déjà enregistré comme chauffeur CHOPCHOP. Un même compte ne peut pas être à la fois chauffeur et marchand. Contactez le support pour changer d'activité.";
  }
  if (lane === "merchant") {
    return "Votre compte est déjà enregistré comme marchand CHOPCHOP. Un même compte ne peut pas être à la fois marchand et chauffeur. Contactez le support pour changer d'activité.";
  }
  return "Cette activité professionnelle n'est pas disponible pour votre compte.";
}
