/**
 * Slice 8 — canonical cancellation client layer.
 *
 * HARD RULE: this file, and every component consuming it, is forbidden from
 * computing a cancellation amount. There is exactly ONE calculator and it lives
 * in the database (`public._cancellation_compute`). The client asks
 * `cancellation_quote(...)` for the frozen, policy-snapshotted numbers and only
 * formats them. The execution RPCs re-derive the same values from the same
 * snapshot, so preview and execution can never disagree.
 *
 * No percentages, no basis arithmetic, no `* 0.05`, no `/ 10000` here. Ever.
 */
import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";

export type CancellationService = "ride" | "cash_order" | "chop_pay_order" | "package";

export type CancellationLockReason =
  | "already_closed"
  | "already_cancelled"
  | "ride_in_progress"
  | "preparation_started"
  | "merchandise_funded"
  | "custody_established"
  | "claim_open"
  | null;

export type CancellationQuote = {
  schema: "chopchop.finance.cancellation_quote";
  version: number;
  service: CancellationService;
  source_module: string;
  source_id: string;
  mission_type: string;
  payment_mode: "cash" | "chop_pay" | string;
  cancelable: boolean;
  lock_reason: CancellationLockReason;
  stage: "before_dispatch" | "after_dispatch";
  responsible_party: string;
  cancel_basis_kind: string;
  basis_gnf: number;
  fee_bps: number;
  /** Authoritative amount to display. Never recompute it. */
  fee_gnf: number;
  debt_if_cash_gnf: number;
  refundable_gnf: number;
  policy_id: string | null;
  policy_effective_from: string | null;
  snapshot_version: string | null;
  quoted_at: string;
};

export async function fetchCancellationQuote(
  service: CancellationService,
  sourceId: string,
  sourceModule?: string,
): Promise<CancellationQuote> {
  const { data, error } = await (supabase as any).rpc("cancellation_quote", {
    p_service: service,
    p_source_id: sourceId,
    p_source_module: sourceModule ?? null,
  });
  if (error) throw error;
  return data as CancellationQuote;
}

/** Lazily loads the server quote when `enabled` flips true. */
export function useCancellationQuote(
  service: CancellationService,
  sourceId: string | null,
  sourceModule?: string,
  enabled = true,
) {
  const [quote, setQuote] = useState<CancellationQuote | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const reload = useCallback(async () => {
    if (!sourceId || !enabled) return;
    setLoading(true);
    setError(null);
    try {
      setQuote(await fetchCancellationQuote(service, sourceId, sourceModule));
    } catch (e) {
      setError((e as Error).message);
      setQuote(null);
    } finally {
      setLoading(false);
    }
  }, [service, sourceId, sourceModule, enabled]);

  useEffect(() => {
    void reload();
  }, [reload]);

  return { quote, loading, error, reload };
}

/* ------------------------- outstanding cash debt ------------------------- */

export type CancellationDebtItem = {
  debt_id: string;
  source_module: string;
  source_id: string;
  mission_type: string;
  stage: string;
  state: string;
  basis_gnf: number;
  applied_bps: number;
  amount_gnf: number;
  paid_gnf: number;
  waived_gnf: number;
  outstanding_gnf: number;
  created_at: string;
  resolved_at: string | null;
};

export type CancellationDebtsOverview = {
  schema: "chopchop.finance.cancellation_debts";
  version: number;
  outstanding_total_gnf: number;
  available_gnf: number;
  /** Server truth. Never infer this from a displayed amount. */
  cash_orders_allowed: boolean;
  account_locked: boolean;
  items: CancellationDebtItem[];
  generated_at: string;
};

export async function fetchCancellationDebts(): Promise<CancellationDebtsOverview> {
  const { data, error } = await (supabase as any).rpc("customer_cancellation_debts_overview");
  if (error) throw error;
  return data as CancellationDebtsOverview;
}

export type RepaymentResult = {
  status: string;
  collected_gnf?: number;
  outstanding_gnf?: number;
  fully_paid?: boolean;
};

/** Server-authoritative repayment. The amount collected is decided server-side. */
export async function repayCancellationDebt(
  debtId: string,
  amountGnf?: number,
): Promise<RepaymentResult> {
  const { data, error } = await (supabase as any).rpc("customer_cancellation_debt_repay", {
    p_debt_id: debtId,
    p_amount_gnf: amountGnf ?? null,
  });
  if (error) throw error;
  return data as RepaymentResult;
}

export function useCancellationDebts() {
  const [data, setData] = useState<CancellationDebtsOverview | null>(null);
  const [loading, setLoading] = useState(true);

  const reload = useCallback(async () => {
    setLoading(true);
    try {
      setData(await fetchCancellationDebts());
    } catch {
      setData(null);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void reload();
  }, [reload]);

  return { data, loading, reload };
}

/* ------------------------------- copy ----------------------------------- */

/** Truthful French copy for a blocked cancellation. Text only — no amounts. */
export const CANCELLATION_LOCK_COPY: Record<string, string> = {
  already_closed: "Cette course est déjà terminée ou annulée.",
  already_cancelled: "Cette commande est déjà annulée.",
  ride_in_progress: "Votre course a déjà commencé et ne peut plus être annulée normalement.",
  preparation_started:
    "Cette commande est déjà en préparation et ne peut plus être annulée normalement.",
  merchandise_funded:
    "Le marchand a déjà été payé pour cette commande. Passez par le support pour un litige.",
  custody_established:
    "Le coursier a déjà pris le colis en charge. Passez par le support pour ouvrir un litige.",
  claim_open: "Une réclamation est déjà ouverte sur cet envoi.",
};

export function cancellationLockCopy(reason: CancellationLockReason): string {
  if (!reason) return "Annulation indisponible pour le moment.";
  return CANCELLATION_LOCK_COPY[reason] ?? "Annulation indisponible pour le moment.";
}