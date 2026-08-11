/**
 * Slice 7 — ledger-truth read models.
 *
 * HARD RULE: nothing in this file (or in any component consuming it) may
 * compute a financial amount. Every number here is returned verbatim by a
 * participant-scoped SECURITY DEFINER RPC grounded in canonical wallet /
 * hold / payable / ledger truth. The client only formats.
 */
import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";

/* ------------------------------- CUSTOMER ------------------------------- */

export type CustomerFinanceOverview = {
  wallet_id: string | null;
  has_wallet: boolean;
  status: string;
  balance_gnf: number;
  held_gnf: number;
  available_gnf: number;
  open_hold_gnf: number;
  holds_reconciled: boolean;
  ecosystem_spend_gnf: number;
  refund_total_gnf: number;
  topup_credited_gnf: number;
  topup_pending_gnf: number;
  topup_pending_count: number;
};

export type CustomerFinanceEvent = {
  event_id: string;
  source: "wallet_transaction" | "topup_request";
  reference: string;
  kind: string;
  direction: "in" | "out";
  amount_gnf: number;
  status: string;
  label: string;
  module: string;
  counts_as_balance: boolean;
  occurred_at: string;
};

export type CustomerReceipt = {
  transaction_id: string;
  reference: string;
  kind: string;
  status: string;
  amount_gnf: number;
  direction: "in" | "out";
  description: string | null;
  module: string;
  created_at: string;
  completed_at: string | null;
  journal: unknown | null;
  has_journal_provenance: boolean;
};

export async function fetchCustomerFinanceOverview(): Promise<CustomerFinanceOverview | null> {
  const { data, error } = await supabase.rpc("customer_finance_overview" as never, {} as never);
  if (error) return null;
  return (data as unknown as CustomerFinanceOverview) ?? null;
}

export async function fetchCustomerFinanceHistory(limit = 50): Promise<CustomerFinanceEvent[]> {
  const { data, error } = await supabase.rpc("customer_finance_history" as never, { p_limit: limit } as never);
  if (error) return [];
  return (data as unknown as CustomerFinanceEvent[]) ?? [];
}

export async function fetchCustomerReceipt(txId: string): Promise<CustomerReceipt | null> {
  const { data, error } = await supabase.rpc("customer_receipt" as never, { p_transaction_id: txId } as never);
  if (error) return null;
  return (data as unknown as CustomerReceipt) ?? null;
}

export function useCustomerFinanceOverview() {
  const [overview, setOverview] = useState<CustomerFinanceOverview | null>(null);
  const [loading, setLoading] = useState(true);

  const refresh = useCallback(async () => {
    setLoading(true);
    setOverview(await fetchCustomerFinanceOverview());
    setLoading(false);
  }, []);

  useEffect(() => { void refresh(); }, [refresh]);
  return { overview, loading, refresh };
}

/**
 * Customer financial history — server-authored event feed. The client may
 * filter/sort already-returned rows for presentation but never recomputes
 * amounts, direction or status.
 */
export function useCustomerFinanceHistory(limit = 50) {
  const [events, setEvents] = useState<CustomerFinanceEvent[]>([]);
  const [loading, setLoading] = useState(true);

  const refresh = useCallback(async () => {
    setLoading(true);
    setEvents(await fetchCustomerFinanceHistory(limit));
    setLoading(false);
  }, [limit]);

  useEffect(() => { void refresh(); }, [refresh]);
  return { events, loading, refresh };
}

/* -------------------------------- DRIVER -------------------------------- */

export type DriverTopupRow = {
  id: string;
  reference: string;
  amount_gnf: number;
  status: string;
  provider: string;
  created_at: string;
  confirmed_at: string | null;
  cancelled_reason: string | null;
  credited_transaction_id: string | null;
  credited: boolean;
  receiving_label: string | null;
  receiving_phone: string | null;
};

export async function fetchDriverTopupHistory(limit = 20): Promise<DriverTopupRow[]> {
  const { data, error } = await supabase.rpc("driver_topup_history" as never, { p_limit: limit } as never);
  if (error) return [];
  return (data as unknown as DriverTopupRow[]) ?? [];
}

export function useDriverTopupHistory(limit = 10) {
  const [rows, setRows] = useState<DriverTopupRow[]>([]);
  const [loading, setLoading] = useState(true);
  const refresh = useCallback(async () => {
    setLoading(true);
    setRows(await fetchDriverTopupHistory(limit));
    setLoading(false);
  }, [limit]);
  useEffect(() => { void refresh(); }, [refresh]);
  return { rows, loading, refresh };
}

/* ------------------------------- MERCHANT ------------------------------- */

export type MerchantFinanceOverview = {
  store_id: string;
  wallet_id: string | null;
  wallet_status: string;
  sales_balance_gnf: number;
  held_gnf: number;
  available_gnf: number;
  pending_payable_gnf: number;
  funded_unsettled_gnf: number;
  settlement_held_gnf: number;
  settled_total_gnf: number;
  reversed_total_gnf: number;
  open_request_gnf: number;
  reserved_for_settlement_gnf: number;
  eligible_settlement_gnf: number;
  settlement_rail_enabled: boolean;
};

export type MerchantSettlementRequest = {
  id: string;
  request_key: string;
  amount_gnf: number;
  status: "requested" | "pending_review" | "rejected" | "cancelled" | "settled";
  channel: string;
  note: string | null;
  reject_reason: string | null;
  evidence_ref: string | null;
  settled_at: string | null;
  reviewed_at: string | null;
  created_at: string;
};

export async function fetchMerchantFinanceOverview(storeId?: string | null) {
  const { data, error } = await supabase.rpc("merchant_finance_overview" as never, {
    p_store_id: storeId ?? null,
  } as never);
  if (error) return null;
  return (data as unknown as MerchantFinanceOverview) ?? null;
}

export async function fetchMerchantSettlementRequests(storeId?: string | null, limit = 20) {
  const { data, error } = await supabase.rpc("merchant_settlement_requests_list" as never, {
    p_store_id: storeId ?? null, p_limit: limit,
  } as never);
  if (error) return [];
  return (data as unknown as MerchantSettlementRequest[]) ?? [];
}

export async function createMerchantSettlementRequest(args: {
  amountGnf: number; idempotencyKey: string; storeId?: string | null; note?: string | null;
}): Promise<{ ok: true; duplicate: boolean } | { ok: false; error: string }> {
  const { data, error } = await supabase.rpc("merchant_settlement_request_create" as never, {
    p_amount_gnf: args.amountGnf,
    p_idempotency_key: args.idempotencyKey,
    p_store_id: args.storeId ?? null,
    p_note: args.note ?? null,
  } as never);
  if (error) return { ok: false, error: error.message };
  const row = data as unknown as { duplicate?: boolean };
  return { ok: true, duplicate: !!row?.duplicate };
}

export function useMerchantFinance(storeId?: string | null) {
  const [overview, setOverview] = useState<MerchantFinanceOverview | null>(null);
  const [requests, setRequests] = useState<MerchantSettlementRequest[]>([]);
  const [loading, setLoading] = useState(true);

  const refresh = useCallback(async () => {
    setLoading(true);
    const [ov, rq] = await Promise.all([
      fetchMerchantFinanceOverview(storeId),
      fetchMerchantSettlementRequests(storeId),
    ]);
    setOverview(ov);
    setRequests(rq);
    setLoading(false);
  }, [storeId]);

  useEffect(() => { void refresh(); }, [refresh]);
  return { overview, requests, loading, refresh };
}
