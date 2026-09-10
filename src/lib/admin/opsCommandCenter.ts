import { supabase } from "@/integrations/supabase/client";

/**
 * G4 — Operations Command Center read model.
 *
 * Single canonical source: `public.ops_command_overview()`, a read-only,
 * capability-gated RPC (`ops.liveops.view`). No mutation path lives here and no
 * value is invented client-side: a failed read stays `null` (data unavailable)
 * and is never rendered as a zero.
 */

export interface OpsSnapshot {
  rides_active: number;
  rides_today: number;
  rides_unassigned: number;
  missions_active: number;
  repas_active: number;
  marche_active: number;
  envoyer_active: number;
  drivers_online: number;
  drivers_approved: number;
  driver_apps_pending: number;
  merchant_apps_pending: number;
  ops_cases_open: number;
  support_open: number;
  support_critical: number;
  map_duplicates_open: number;
}

export type OpsSeverity = "critical" | "high" | "normal";

export interface OpsAttentionItem {
  kind: string;
  service: string;
  label: string;
  reference: string;
  state: string | null;
  since: string | null;
  severity: OpsSeverity;
  finance_context: string | null;
  href: string;
}

export interface OpsOverview {
  generated_at: string;
  role: string | null;
  mode: string | null;
  snapshot: OpsSnapshot;
  attention: OpsAttentionItem[];
}

export type OpsOverviewResult =
  | { ok: true; data: OpsOverview }
  | { ok: false; error: string; denied: boolean };

export async function fetchOpsOverview(): Promise<OpsOverviewResult> {
  try {
    const { data, error } = await (supabase.rpc as any)("ops_command_overview");
    if (error) {
      const denied = /capability_denied|permission denied|not authorized/i.test(error.message ?? "");
      return { ok: false, denied, error: denied ? OPS_DENIED_MESSAGE : OPS_UNAVAILABLE_MESSAGE };
    }
    if (!data || typeof data !== "object") {
      return { ok: false, denied: false, error: OPS_UNAVAILABLE_MESSAGE };
    }
    const raw = data as any;
    return {
      ok: true,
      data: {
        generated_at: String(raw.generated_at ?? ""),
        role: raw.role ?? null,
        mode: raw.mode ?? null,
        snapshot: raw.snapshot ?? ({} as OpsSnapshot),
        attention: Array.isArray(raw.attention) ? (raw.attention as OpsAttentionItem[]) : [],
      },
    };
  } catch {
    return { ok: false, denied: false, error: OPS_UNAVAILABLE_MESSAGE };
  }
}

export const OPS_DENIED_MESSAGE =
  "Accès refusé : votre rôle ne dispose pas de la capacité « ops.liveops.view ».";
export const OPS_UNAVAILABLE_MESSAGE =
  "Données indisponibles. Le chiffre affiché n'est pas fiable — réessayez.";

/** Read-only finance escalation copy. Operations never mutates money. */
export const FINANCE_ESCALATION = "Intervention Finance requise";

export const SEVERITY_LABEL: Record<OpsSeverity, string> = {
  critical: "Critique",
  high: "Prioritaire",
  normal: "À traiter",
};

export const SEVERITY_CLASS: Record<OpsSeverity, string> = {
  critical: "bg-destructive/10 text-destructive border-destructive/30",
  high: "bg-amber-500/10 text-amber-700 dark:text-amber-300 border-amber-500/30",
  normal: "bg-muted text-muted-foreground border-border",
};

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
