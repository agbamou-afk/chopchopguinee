/**
 * Driver Chop Pay wallet helpers (Chop Pay ledger revival).
 *
 * There is ONE driver ledger wallet. Top-ups and earnings credit it;
 * commission reserves, mission collateral and cashout requests place
 * holds on it. Held funds are not withdrawable until released or
 * captured. Every value here comes from server-authoritative
 * SECURITY DEFINER RPCs — nothing is computed on the client.
 */
import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";

export type DriverBalanceSummary = {
  wallet_id: string | null;
  balance_gnf: number;
  held_gnf: number;
  available_gnf: number;
  collateral_held_gnf: number;
  commission_held_gnf: number;
  status: string;
  /** Restricted CHOPCHOP starting credit still in the ledger (incl. held part). */
  promo_remaining_gnf?: number;
  promo_held_gnf?: number;
  promo_available_gnf?: number;
  /** Available funds excluding the restricted promotional bonus. */
  unrestricted_available_gnf?: number;
  /** What the driver may actually cash out — never includes the bonus. */
  withdrawable_gnf?: number;
  platform_fee_held_gnf?: number;
  cash_funding_held_gnf?: number;
};

export type MissionRequirement = {
  policy_id: string | null;
  mission_type: string;
  basis_value_gnf: number;
  commission_gnf: number;
  collateral_gnf: number;
  min_balance_gnf: number;
  required_hold_gnf: number;
  required_available_gnf: number;
  has_policy: boolean;
};

export type Eligibility = {
  eligible: boolean;
  available_gnf: number;
  required_gnf: number;
  shortfall_gnf: number;
  requirement: MissionRequirement;
  balance: DriverBalanceSummary;
};

/** French, non-punitive copy shown when a driver cannot take new missions. */
export const INSUFFICIENT_BALANCE_MESSAGE =
  "Votre solde disponible est insuffisant pour recevoir de nouvelles missions. Rechargez votre portefeuille ou attendez la libération d'une caution pour reprendre.";

/** Canonical driver-facing wording for the restricted starting credit. */
export const STARTER_CREDIT_LABEL = "Bonus de démarrage CHOPCHOP";
export const STARTER_CREDIT_NOTE =
  "Ce bonus de 25 000 GNF peut servir aux cautions et frais CHOPCHOP. Il ne peut pas être retiré ni transféré.";

export async function fetchDriverBalance(): Promise<DriverBalanceSummary | null> {
  const { data, error } = await supabase.rpc("driver_balance_summary" as never, {} as never);
  if (error) return null;
  return (data as unknown as DriverBalanceSummary) ?? null;
}

export async function fetchMissionRequirement(
  missionType: string,
  valueGnf = 0,
): Promise<MissionRequirement | null> {
  const { data, error } = await supabase.rpc("finance_mission_requirement" as never, {
    p_mission_type: missionType,
    p_value_gnf: valueGnf,
  } as never);
  if (error) return null;
  return (data as unknown as MissionRequirement) ?? null;
}

export async function fetchEligibility(
  missionType: string,
  valueGnf = 0,
): Promise<Eligibility | null> {
  const { data, error } = await supabase.rpc("driver_financial_eligibility" as never, {
    p_mission_type: missionType,
    p_value_gnf: valueGnf,
  } as never);
  if (error) return null;
  return (data as unknown as Eligibility) ?? null;
}

export function useDriverBalance() {
  const [summary, setSummary] = useState<DriverBalanceSummary | null>(null);
  const [loading, setLoading] = useState(true);

  const refresh = useCallback(async () => {
    setLoading(true);
    setSummary(await fetchDriverBalance());
    setLoading(false);
  }, []);

  useEffect(() => { void refresh(); }, [refresh]);

  return { summary, loading, refresh };
}
