/**
 * Slice 11 — payout / merchant settlement engine client bindings.
 *
 * HARD RULE (same as Slice 7): no financial arithmetic here or in any
 * consumer. Every amount below is returned verbatim by a SECURITY DEFINER
 * RPC grounded in payout-order, provider-evidence and ledger truth.
 * "Settled" is only ever a server statement backed by reconciled evidence.
 */
import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";

export type PayoutQueueBucket =
  | "requested"
  | "awaiting_proof"
  | "manual_review"
  | "settled"
  | "rejected";

export type PayoutEvidence = {
  evidence_id: string;
  provider_reference: string;
  state: "recorded" | "evidence_incomplete" | "mismatch" | "reconciled" | "rejected";
  reason: string | null;
  amount_gnf: number | null;
  recipient_msisdn: string | null;
  provider_status: string | null;
  environment: string | null;
  transferred_at: string | null;
  evidence_source?: string | null;
  evidence_kind?: string | null;
  provider_verified?: boolean;
};

export type PayoutQueueItem = {
  payout_order_id: string;
  status: "reserved" | "needs_review" | "mismatch" | "rejected" | "released" | "settled";
  party_type: string;
  source_kind: string | null;
  merchant_store_id: string | null;
  store_name: string | null;
  destination_msisdn: string;
  provider: string;
  environment: string;
  requested_principal_gnf: number;
  provider_fee_gnf: number;
  fee_borne_by: "recipient" | "platform";
  merchant_liability_debit_gnf: number;
  recipient_net_gnf: number;
  expected_provider_transfer_gnf: number;
  reservation_gnf: number;
  settled_gnf: number;
  request_id: string | null;
  reject_reason: string | null;
  settled_at: string | null;
  created_at: string;
  evidence: PayoutEvidence[];
};

export type MerchantSettlementReceipt =
  | {
      kind: "request_confirmation";
      receipt_available: false;
      settled: false;
      request_id: string;
      status: string;
      requested_amount_gnf: number;
      message: string;
    }
  | {
      kind: "settlement_receipt";
      receipt_available: true;
      settled: true;
      request_id: string;
      payout_order_id: string;
      requested_principal_gnf: number;
      provider_fee_gnf: number;
      fee_borne_by: "recipient" | "platform";
      merchant_liability_debit_gnf: number;
      recipient_net_gnf: number;
      provider: string;
      provider_reference: string;
      destination_msisdn: string;
      provider_status: string | null;
      transferred_at: string | null;
      settled_at: string;
      environment: string;
      ledger: { journal_id?: string; journal_key?: string; posted_at?: string };
    };

export async function fetchPayoutQueue(bucket: PayoutQueueBucket, limit = 50) {
  const { data, error } = await supabase.rpc("finance_payout_queue" as never, {
    p_bucket: bucket, p_limit: limit,
  } as never);
  if (error) return { items: [] as PayoutQueueItem[], error: error.message };
  const payload = data as unknown as { items: PayoutQueueItem[] };
  return { items: payload?.items ?? [], error: null as string | null };
}

export async function recordPayoutEvidence(args: {
  payoutOrderId: string;
  provider: string;
  providerReference: string;
  recipientMsisdn: string;
  amountGnf: number;
  providerStatus: string;
  environment: "production" | "sandbox";
  transferredAt?: string | null;
  feeGnf?: number | null;
}): Promise<{ ok: true; result: Record<string, unknown> } | { ok: false; error: string }> {
  const { data, error } = await supabase.rpc("payout_record_provider_evidence" as never, {
    p_payout_order_id: args.payoutOrderId,
    p_provider: args.provider,
    p_provider_reference: args.providerReference,
    p_recipient_msisdn: args.recipientMsisdn,
    p_amount_gnf: args.amountGnf,
    p_provider_status: args.providerStatus,
    p_environment: args.environment,
    p_transferred_at: args.transferredAt ?? null,
    p_fee_gnf: args.feeGnf ?? null,
    p_raw: {},
  } as never);
  if (error) return { ok: false, error: error.message };
  return { ok: true, result: (data as Record<string, unknown>) ?? {} };
}

export async function reconcilePayoutEvidence(evidenceId: string) {
  const { data, error } = await supabase.rpc("payout_reconcile_evidence" as never, {
    p_evidence_id: evidenceId,
  } as never);
  if (error) return { ok: false as const, error: error.message };
  return { ok: true as const, result: (data as Record<string, unknown>) ?? {} };
}

export async function rejectPayoutOrder(payoutOrderId: string, reason: string) {
  const { data, error } = await supabase.rpc("payout_reject_release" as never, {
    p_payout_order_id: payoutOrderId, p_reason: reason,
  } as never);
  if (error) return { ok: false as const, error: error.message };
  return { ok: true as const, result: (data as Record<string, unknown>) ?? {} };
}

export async function generateSettlementSchedule() {
  const { data, error } = await supabase.rpc("merchant_settlement_schedule_generate" as never, {
    p_as_of: new Date().toISOString(),
  } as never);
  if (error) return { ok: false as const, error: error.message };
  return { ok: true as const, result: (data as Record<string, unknown>) ?? {} };
}

export async function fetchMerchantSettlementReceipt(requestId: string) {
  const { data, error } = await supabase.rpc("merchant_settlement_receipt" as never, {
    p_request_id: requestId,
  } as never);
  if (error) return null;
  return (data as unknown as MerchantSettlementReceipt) ?? null;
}

export function usePayoutQueue(bucket: PayoutQueueBucket) {
  const [items, setItems] = useState<PayoutQueueItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    setLoading(true);
    const res = await fetchPayoutQueue(bucket);
    setItems(res.items);
    setError(res.error);
    setLoading(false);
  }, [bucket]);

  useEffect(() => { void refresh(); }, [refresh]);
  return { items, loading, error, refresh };
}
