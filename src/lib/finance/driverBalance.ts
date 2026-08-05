/**
 * Driver operating-balance client helpers (Chop Pay ledger revival).
 *
 * The operating balance funds CHOPCHOP commission reserves and mission
 * collateral. It is NEVER computed on the client: every value here comes
 * from server-authoritative SECURITY DEFINER RPCs.
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
  "Votre solde chauffeur est insuffisant pour recevoir de nouvelles missions. Rechargez votre compte pour reprendre les courses.";

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
