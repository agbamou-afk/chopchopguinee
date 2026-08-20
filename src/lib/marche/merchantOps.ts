/**
 * Node 4 — Marché R11: merchant operations + settlement client bindings.
 *
 * HARD RULE (same as Slice 7 / Slice 11): no lifecycle inference and no
 * financial arithmetic here or in any consumer. Allowed actions, tender
 * truth, payable state and settlement evidence are all returned verbatim by
 * participant-scoped SECURITY DEFINER RPCs grounded in canonical
 * merchant_payables / payout_orders / payout_provider_evidence truth.
 * The client only renders.
 */
import { supabase } from "@/integrations/supabase/client";
import { translateOrderError } from "./orders";

type Rpc = { rpc: (n: string, a?: Record<string, unknown>) => Promise<{ data: unknown; error: { message: string } | null }> };
const db = supabase as unknown as Rpc;

export type MerchantOrderAction = "accept" | "prepare" | "ready" | "reject" | "request_dispatch";

export type MarcheOpsBucket =
  | "action_required" | "preparing" | "in_delivery" | "completed" | "cancelled";

export interface MarcheOrderTender {
  tender_kind: "chop_pay" | "cash" | "payment_intent" | "none";
  tender_state: string | null;
  evidence_source: string | null;
  label: string;
  recorded: boolean;
}

export type MarcheSettlementState =
  | "not_yet_payable" | "pending_funding" | "funded_or_due"
  | "partially_settled" | "settled" | "settlement_held"
  | "reversed" | "disputed" | "verification_required" | "unknown";

export interface MarcheOrderMoney {
  merchandise_subtotal_gnf: number;
  merchant_fee_gnf: number | null;
  merchant_payable_gnf: number | null;
  payable_present: boolean;
  payable_id?: string;
  payable_state: string | null;
  payable_amount_gnf: number | null;
  funding_source?: string;
  funded_gnf: number;
  settled_gnf: number;
  allocated_gnf: number;
  proven_settled_gnf?: number;
  payable_identity?: "none" | "order_id" | "source_offer";
  payable_source_id?: string | null;
  payment_connected?: boolean;
  reason?: string | null;
  outstanding_gnf: number | null;
  settlement_state: MarcheSettlementState;
  settlement_label: string;
  settled: boolean;
}

export interface MarcheOrderOpsItem {
  id: string;
  listing_id: string;
  title: string;
  category: string | null;
  qty: number;
  unit_price_gnf: number;
  line_total_gnf: number;
}

export interface MarcheOrderOps {
  order_id: string;
  status: string;
  fulfillment_state: string;
  ops_bucket: MarcheOpsBucket;
  allowed_actions: MerchantOrderAction[];
  courier_assigned: boolean;
  item_count: number;
  line_count: number;
  items: MarcheOrderOpsItem[];
  delivery_address: string | null;
  created_at: string;
  accepted_at: string | null;
  ready_at: string | null;
  delivered_at: string | null;
  rejected_at: string | null;
  cancelled_at: string | null;
  tender: MarcheOrderTender;
  money: MarcheOrderMoney;
}

export interface MarcheMerchantCockpit {
  counts: Partial<Record<MarcheOpsBucket, number>>;
  bucket: MarcheOpsBucket | null;
  items: MarcheOrderOps[];
}

export interface MarcheSettlementAllocation {
  allocation_id: string;
  amount_gnf: number;
  allocated_at: string;
  payout_order_id: string;
  payout_status: string;
  provider: string | null;
  destination_msisdn: string | null;
  settled_at: string | null;
  provider_reference: string | null;
  provider_status: string | null;
  evidence_state: string | null;
  transferred_at: string | null;
  evidence_backed: boolean;
}

export type MarcheOrderSettlementReceipt = {
  order_id: string;
  payable_id?: string;
  receipt_available: boolean;
  settled: boolean;
  provider_verified?: boolean;
  money: MarcheOrderMoney;
  message?: string;
  allocations?: MarcheSettlementAllocation[];
};

export interface MarcheFinanceOrderAudit {
  order_id: string;
  merchant_store_id: string;
  fulfillment_state: string;
  frozen_merchant_payable_gnf: number | null;
  frozen_merchant_fee_gnf: number | null;
  payable_present: boolean;
  payable_state: string | null;
  payable_amount_gnf: number | null;
  funded_gnf: number | null;
  settled_gnf: number | null;
  allocated_gnf: number;
  unproven_settled_gnf: number;
  proven_settled_gnf?: number;
  payable_identity?: "none" | "order_id" | "source_offer";
  tender: MarcheOrderTender;
  mismatch_codes: string[];
  clean: boolean;
}

async function call<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await db.rpc(fn, args);
  if (error) throw new Error(translateOrderError(error.message));
  return data as T;
}

/** Server-authoritative operations view for a single Marché order. */
export function fetchMarcheOrderOps(orderId: string) {
  return call<MarcheOrderOps>("marche_merchant_order_ops", { p_order_id: orderId });
}

/** Server-bucketed merchant cockpit. Buckets and counts are never client-derived. */
export function fetchMarcheMerchantCockpit(args?: {
  storeId?: string | null; bucket?: MarcheOpsBucket | null; limit?: number; offset?: number;
}) {
  return call<MarcheMerchantCockpit>("marche_merchant_orders_cockpit", {
    p_store_id: args?.storeId ?? null,
    p_bucket: args?.bucket ?? null,
    p_limit: args?.limit ?? 40,
    p_offset: args?.offset ?? 0,
  });
}

/** Per-order settlement truth. "Réglé" only ever comes from reconciled evidence. */
export function fetchMarcheOrderSettlementReceipt(orderId: string) {
  return call<MarcheOrderSettlementReceipt>("marche_order_settlement_receipt", { p_order_id: orderId });
}

/** Finance / god admin only — server-computed mismatch codes. */
export function fetchMarcheFinanceOrderAudit(orderId: string) {
  return call<MarcheFinanceOrderAudit>("marche_finance_order_audit", { p_order_id: orderId });
}

export const MERCHANT_ORDER_ACTION_LABEL: Record<MerchantOrderAction, string> = {
  accept: "Accepter",
  prepare: "Préparer",
  ready: "Prête",
  reject: "Refuser",
  request_dispatch: "Demander un coursier",
};

export const OPS_BUCKET_LABEL: Record<MarcheOpsBucket, string> = {
  action_required: "À traiter",
  preparing: "En préparation",
  in_delivery: "En livraison",
  completed: "Terminées",
  cancelled: "Annulées",
};

export const OPS_BUCKET_ORDER: MarcheOpsBucket[] = [
  "action_required", "preparing", "in_delivery", "completed", "cancelled",
];
