import { supabase } from "@/integrations/supabase/client";

/**
 * G5 — Finance Command Center read model.
 *
 * Single canonical source: `public.finance_command_overview()`, a read-only,
 * capability-gated RPC (`finance.wallet.read`). No mutation lives here and no
 * value is invented client-side: a failed read stays `null` (data unavailable)
 * and is never rendered as a zero. Every action stays on its canonical governed
 * surface; this console only routes to them.
 */

export interface FinanceSnapshot {
  topups_pending: number;
  topups_review: number;
  provider_events_open: number;
  cashouts_pending: number;
  settlements_pending: number;
  payables_open: number;
  payouts_open: number;
  refunds_pending: number;
  intents_review: number;
  wallets_frozen: number;
}

export type FinanceSeverity = "critical" | "high" | "normal" | "warning";

/** Server capability mode. `null` = no grant at all → the action is not offered. */
export type CapabilityMode = "allow" | "approval_required" | "read" | null;

export interface FinanceAttentionItem {
  kind: string;
  queue: string;
  label: string;
  reference: string;
  amount_gnf: number | null;
  state: string | null;
  since: string | null;
  severity: FinanceSeverity;
  mode: CapabilityMode;
  href: string;
}

export interface FinanceException {
  code: string;
  severity: FinanceSeverity;
  amount_gnf: number | null;
  entity_count: number | null;
  source_module: string | null;
  account_code: string | null;
  detail: string | null;
  state: string | null;
}

export interface FinanceOverview {
  generated_at: string;
  role: string | null;
  snapshot: FinanceSnapshot;
  attention: FinanceAttentionItem[];
  exceptions: FinanceException[];
  exceptions_total: number;
  exceptions_critical: number;
}

export type FinanceOverviewResult =
  | { ok: true; data: FinanceOverview }
  | { ok: false; error: string; denied: boolean };

export const FINANCE_DENIED_MESSAGE =
  "Accès refusé : votre rôle ne dispose pas de la capacité « finance.wallet.read ».";
export const FINANCE_UNAVAILABLE_MESSAGE =
  "Données indisponibles. Le chiffre affiché n'est pas fiable — réessayez.";

/** Operations owns the operational case; Finance never mutates it. */
export const OPS_ESCALATION = "Intervention Opérations requise";

export async function fetchFinanceOverview(): Promise<FinanceOverviewResult> {
  try {
    const { data, error } = await (supabase.rpc as any)("finance_command_overview");
    if (error) {
      const denied = /capability_denied|permission denied|not authorized|NOT_AUTHENTICATED/i.test(
        error.message ?? "",
      );
      return { ok: false, denied, error: denied ? FINANCE_DENIED_MESSAGE : FINANCE_UNAVAILABLE_MESSAGE };
    }
    if (!data || typeof data !== "object") {
      return { ok: false, denied: false, error: FINANCE_UNAVAILABLE_MESSAGE };
    }
    const raw = data as any;
    return {
      ok: true,
      data: {
        generated_at: String(raw.generated_at ?? ""),
        role: raw.role ?? null,
        snapshot: (raw.snapshot ?? {}) as FinanceSnapshot,
        attention: Array.isArray(raw.attention) ? (raw.attention as FinanceAttentionItem[]) : [],
        exceptions: Array.isArray(raw.exceptions) ? (raw.exceptions as FinanceException[]) : [],
        exceptions_total: Number(raw.exceptions_total ?? 0),
        exceptions_critical: Number(raw.exceptions_critical ?? 0),
      },
    };
  } catch {
    return { ok: false, denied: false, error: FINANCE_UNAVAILABLE_MESSAGE };
  }
}

export const SEVERITY_LABEL: Record<FinanceSeverity, string> = {
  critical: "Critique",
  high: "Prioritaire",
  warning: "À surveiller",
  normal: "À traiter",
};

export const SEVERITY_CLASS: Record<FinanceSeverity, string> = {
  critical: "bg-destructive/10 text-destructive border-destructive/30",
  high: "bg-amber-500/10 text-amber-700 dark:text-amber-300 border-amber-500/30",
  warning: "bg-amber-500/10 text-amber-700 dark:text-amber-300 border-amber-500/30",
  normal: "bg-muted text-muted-foreground border-border",
};

/** Honest execution label. An ungranted capability is never shown as executable. */
export function modeLabel(mode: CapabilityMode): string {
  if (mode === "allow") return "Exécution directe";
  if (mode === "approval_required") return "Approbation requise";
  if (mode === "read") return "Lecture seule";
  return "Non autorisé";
}

export function formatGnf(v: number | null | undefined): string {
  if (v === null || v === undefined || Number.isNaN(Number(v))) return "—";
  return `${new Intl.NumberFormat("fr-FR").format(Number(v))} GNF`;
}

export function relativeAge(iso: string | null | undefined, now: number = Date.now()): string {
  if (!iso) return "—";
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return "—";
  const mins = Math.max(0, Math.round((now - t) / 60000));
  if (mins < 60) return `${mins} min`;
  const hours = Math.floor(mins / 60);
  if (hours < 48) return `${hours} h`;
  return `${Math.floor(hours / 24)} j`;
}
