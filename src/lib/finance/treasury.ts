/**
 * Slice 12 — treasury / finance-operations read models.
 *
 * HARD RULE (same as Slice 7 and Slice 11): nothing in this file or in any
 * consumer may compute, net, infer or balance a financial figure. Every
 * number is returned verbatim by a role-gated SECURITY DEFINER RPC grounded
 * in wallet / ledger / payable / claim / provider truth. The client formats.
 */
import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";

export type TreasuryOverview = {
  generated_at: string;

  verified_assets_gnf: number;
  om_inbound_credited_gnf: number;
  om_outbound_settled_gnf: number;
  provider_clearing_ledger_gnf: number;

  total_customer_liability_gnf: number;
  total_driver_liability_gnf: number;
  total_merchant_liability_gnf: number;
  merchant_wallet_liability_gnf: number;
  merchant_payable_outstanding_gnf: number;
  restricted_or_held_liability_gnf: number;
  promotional_credit_liability_gnf: number;
  merchant_settlement_reserved_gnf: number;
  merchant_settlement_reserved_count: number;
  master_wallet_balance_gnf: number;
  master_wallet_held_gnf: number;

  recognized_claims_obligation_gnf: number;
  open_claims_exposure_gnf: number;
  claims_paid_gnf: number;
  claims_released_gnf: number;
  open_claims_count: number;

  cancellation_debt_receivable_gnf: number;
  cancellation_debt_collected_gnf: number;
  cancellation_debt_waived_gnf: number;
  cancellation_debt_open_count: number;

  captured_revenue_gnf: number;
  captured_revenue_breakdown: {
    ride_commission_gnf: number;
    transaction_fee_gnf: number;
    cancellation_fee_gnf: number;
    recovered_collateral_gnf: number;
  };

  inbound_om_unreconciled_gnf: number;
  inbound_om_unreconciled_count: number;
  inbound_om_pending_gnf: number;
  inbound_om_unmatched_events_gnf: number;
  inbound_om_unmatched_events_count: number;
  outbound_payout_unreconciled_gnf: number;
  outbound_payout_unreconciled_count: number;

  covered_obligations_gnf: number;
  treasury_coverage_delta_gnf: number;

  ledger_posting_count: number;
  ledger_global_sum_gnf: number;
};

export type TreasuryExceptionCode =
  | "TREASURY_SHORTFALL"
  | "TREASURY_SURPLUS"
  | "WALLET_LEDGER_MISMATCH"
  | "MASTER_WALLET_DEFICIT"
  | "MERCHANT_PAYABLE_MISMATCH"
  | "CLAIM_RESERVE_MISMATCH"
  | "PROVIDER_CLEARING_MISMATCH"
  | "INBOUND_OM_UNRECONCILED"
  | "INBOUND_OM_UNMATCHED_EVENT"
  | "OUTBOUND_PAYOUT_UNRECONCILED"
  | "LEDGER_GLOBAL_IMBALANCE"
  | "LEDGER_JOURNAL_IMBALANCE";

export type TreasuryException = {
  code: TreasuryExceptionCode | string;
  severity: "critical" | "high" | "warning" | string;
  amount_gnf: number;
  entity_count: number;
  source_module: string;
  account_code: string | null;
  detail: string;
  state: string;
  occurred_at: string;
};

export type TreasuryDrilldownRow = {
  ref: string;
  label: string;
  amount_gnf: number;
  state: string;
  source_module: string;
  source_ref: string | null;
  occurred_at: string;
};

export async function fetchTreasuryOverview(): Promise<
  { ok: true; data: TreasuryOverview } | { ok: false; error: string }
> {
  const { data, error } = await supabase.rpc("finance_treasury_overview" as never, {} as never);
  if (error) return { ok: false, error: error.message };
  return { ok: true, data: data as unknown as TreasuryOverview };
}

export async function fetchTreasuryExceptions(): Promise<
  { ok: true; data: TreasuryException[] } | { ok: false; error: string }
> {
  const { data, error } = await supabase.rpc("finance_treasury_exceptions" as never, {} as never);
  if (error) return { ok: false, error: error.message };
  return { ok: true, data: (data as unknown as TreasuryException[]) ?? [] };
}

export async function fetchTreasuryDrilldown(code: string, limit = 50): Promise<TreasuryDrilldownRow[]> {
  const { data, error } = await supabase.rpc("finance_treasury_drilldown" as never, {
    p_code: code, p_limit: limit,
  } as never);
  if (error) return [];
  return (data as unknown as TreasuryDrilldownRow[]) ?? [];
}

export function useTreasury() {
  const [overview, setOverview] = useState<TreasuryOverview | null>(null);
  const [exceptions, setExceptions] = useState<TreasuryException[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const refresh = useCallback(async () => {
    setLoading(true);
    setError(null);
    const [ov, ex] = await Promise.all([fetchTreasuryOverview(), fetchTreasuryExceptions()]);
    if (ov.ok === true) setOverview(ov.data);
    else { setOverview(null); setError(ov.error); }
    if (ex.ok === true) setExceptions(ex.data);
    else { setExceptions([]); setError((prev) => prev ?? ex.error); }
    setLoading(false);
  }, []);

  useEffect(() => { void refresh(); }, [refresh]);
  return { overview, exceptions, error, loading, refresh };
}
