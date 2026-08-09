/**
 * Slice 2 — Finance policy control plane (client helpers).
 *
 * The database is the only authority: every value here is read back from
 * `finance_policies` and friends, and every write goes through an audited
 * God-Admin RPC. Nothing in this file computes economics.
 */
import { supabase } from "@/integrations/supabase/client";

export const MISSION_TYPES = ["ride", "bonbonna", "repas", "marche", "envoyer"] as const;
export type MissionType = (typeof MISSION_TYPES)[number];

export const MISSION_LABELS: Record<MissionType, string> = {
  ride: "Course Moto",
  bonbonna: "Bonbonna",
  repas: "Repas",
  marche: "Marché",
  envoyer: "Envoyer",
};

export interface FinancePolicyRow {
  id: string;
  mission_type: string;
  commission_bps: number;
  fixed_commission_gnf: number;
  min_driver_balance_gnf: number;
  collateral_mode: string;
  collateral_pct_bps: number;
  collateral_basis: string;
  collateral_fixed_gnf: number;
  collateral_min_gnf: number;
  collateral_max_gnf: number | null;
  require_collateral_before_offer: boolean;
  transaction_fee_bps: number;
  fee_basis: string;
  cash_funding_mode: string;
  cash_funding_pct_bps: number;
  cash_funding_max_gnf: number | null;
  cancel_before_dispatch_bps: number;
  cancel_after_dispatch_bps: number;
  cancel_basis: string;
  max_declared_value_gnf: number | null;
  claims_exposure_max_gnf: number | null;
  effective_from: string;
  enabled: boolean;
  note: string | null;
  created_by: string | null;
  created_at: string;
}

/** Fields the God Admin can schedule for FUTURE transactions. */
export type EditableField =
  | "commission_bps"
  | "fixed_commission_gnf"
  | "min_driver_balance_gnf"
  | "collateral_mode"
  | "collateral_pct_bps"
  | "collateral_basis"
  | "collateral_min_gnf"
  | "collateral_max_gnf"
  | "transaction_fee_bps"
  | "fee_basis"
  | "cash_funding_mode"
  | "cash_funding_pct_bps"
  | "cancel_before_dispatch_bps"
  | "cancel_after_dispatch_bps"
  | "cancel_basis"
  | "max_declared_value_gnf"
  | "claims_exposure_max_gnf";

export const FIELD_LABELS: Record<EditableField, string> = {
  commission_bps: "Commission chauffeur (%)",
  fixed_commission_gnf: "Commission fixe (GNF)",
  min_driver_balance_gnf: "Solde chauffeur minimum (GNF)",
  collateral_mode: "Mode de caution",
  collateral_pct_bps: "Caution (%)",
  collateral_basis: "Base de la caution",
  collateral_min_gnf: "Caution minimum (GNF)",
  collateral_max_gnf: "Caution maximum (GNF)",
  transaction_fee_bps: "Frais de transaction hors course (%)",
  fee_basis: "Base des frais",
  cash_funding_mode: "Mode de financement espèces",
  cash_funding_pct_bps: "Financement espèces (%)",
  cancel_before_dispatch_bps: "Annulation avant affectation (%)",
  cancel_after_dispatch_bps: "Annulation après affectation (%)",
  cancel_basis: "Base d'annulation",
  max_declared_value_gnf: "Valeur déclarée maximum (GNF)",
  claims_exposure_max_gnf: "Exposition sinistres CHOPCHOP max (GNF)",
};

/** bps fields are displayed as percentages. */
export const BPS_FIELDS: EditableField[] = [
  "commission_bps",
  "collateral_pct_bps",
  "transaction_fee_bps",
  "cash_funding_pct_bps",
  "cancel_before_dispatch_bps",
  "cancel_after_dispatch_bps",
];

export const BASIS_OPTIONS: Record<string, { value: string; label: string }[]> = {
  collateral_basis: [
    { value: "none", label: "Aucune" },
    { value: "fare", label: "Course" },
    { value: "merchandise_subtotal", label: "Sous-total marchandise" },
    { value: "declared_value", label: "Valeur déclarée" },
  ],
  fee_basis: [
    { value: "none", label: "Aucune" },
    { value: "fare", label: "Course" },
    { value: "merchandise_subtotal", label: "Sous-total marchandise" },
    { value: "declared_value", label: "Valeur déclarée" },
    { value: "delivery_fee", label: "Frais de livraison uniquement" },
    { value: "order_total", label: "Total commande" },
    { value: "transfer_amount", label: "Montant du transfert" },
  ],
  cancel_basis: [
    { value: "none", label: "Aucune" },
    { value: "fare", label: "Course" },
    { value: "merchandise_plus_delivery", label: "Marchandise + livraison" },
    { value: "delivery_fee", label: "Frais de livraison uniquement" },
  ],
  collateral_mode: [
    { value: "none", label: "Aucune" },
    { value: "fixed", label: "Fixe" },
    { value: "percentage", label: "Pourcentage" },
  ],
  cash_funding_mode: [
    { value: "none", label: "Aucun" },
    { value: "merchandise_subtotal", label: "Sous-total marchandise" },
  ],
};

/** Which fields make sense per service — avoids silent defaults on irrelevant fields. */
export const FIELDS_BY_SERVICE: Record<MissionType, EditableField[]> = {
  ride: [
    "commission_bps", "fixed_commission_gnf", "min_driver_balance_gnf",
    "cancel_before_dispatch_bps", "cancel_after_dispatch_bps", "cancel_basis",
  ],
  bonbonna: [
    "commission_bps", "fixed_commission_gnf", "min_driver_balance_gnf",
    "cancel_before_dispatch_bps", "cancel_after_dispatch_bps", "cancel_basis",
  ],
  repas: [
    "commission_bps", "min_driver_balance_gnf",
    "collateral_mode", "collateral_pct_bps", "collateral_basis", "collateral_max_gnf",
    "cash_funding_mode", "cash_funding_pct_bps",
    "transaction_fee_bps", "fee_basis",
    "cancel_before_dispatch_bps", "cancel_after_dispatch_bps", "cancel_basis",
  ],
  marche: [
    "commission_bps", "min_driver_balance_gnf",
    "collateral_mode", "collateral_pct_bps", "collateral_basis", "collateral_max_gnf",
    "cash_funding_mode", "cash_funding_pct_bps",
    "transaction_fee_bps", "fee_basis",
    "cancel_before_dispatch_bps", "cancel_after_dispatch_bps", "cancel_basis",
  ],
  envoyer: [
    "commission_bps", "min_driver_balance_gnf",
    "collateral_mode", "collateral_pct_bps", "collateral_basis", "collateral_max_gnf",
    "max_declared_value_gnf", "claims_exposure_max_gnf",
    "transaction_fee_bps", "fee_basis",
    "cancel_before_dispatch_bps", "cancel_after_dispatch_bps", "cancel_basis",
  ],
};

export function formatFieldValue(field: string, value: unknown): string {
  if (value === null || value === undefined || value === "") return "—";
  if (BPS_FIELDS.includes(field as EditableField)) return `${(Number(value) / 100).toFixed(2)} %`;
  const options = BASIS_OPTIONS[field];
  if (options) return options.find((o) => o.value === value)?.label ?? String(value);
  if (typeof value === "boolean") return value ? "Oui" : "Non";
  if (field.endsWith("_gnf")) return `${Number(value).toLocaleString("fr-FR")} GNF`;
  return String(value);
}

export interface DiffEntry {
  field: string;
  before: unknown;
  after: unknown;
  /** Optional override when the field is not part of the service policy model. */
  label?: string;
  format?: (v: unknown) => string;
}

/** Generic before/after diff for the control-plane forms (payout, settlement, fees…). */
export interface DiffSpec {
  key: string;
  label: string;
  format?: (v: unknown) => string;
}

export function diffRecords(
  before: Record<string, unknown> | null | undefined,
  draft: Record<string, unknown>,
  specs: DiffSpec[],
): DiffEntry[] {
  const norm = (v: unknown) => (v === null || v === undefined || v === "" ? null : String(v));
  const out: DiffEntry[] = [];
  for (const s of specs) {
    if (!(s.key in draft)) continue;
    const b = before ? before[s.key] : null;
    const a = draft[s.key];
    if (norm(b) !== norm(a)) out.push({ field: s.key, before: b, after: a, label: s.label, format: s.format });
  }
  return out;
}

export function diffPolicy(
  current: FinancePolicyRow | undefined,
  draft: Partial<Record<EditableField, unknown>>,
  fields: EditableField[],
): DiffEntry[] {
  const out: DiffEntry[] = [];
  for (const f of fields) {
    const before = current ? (current as unknown as Record<string, unknown>)[f] : null;
    const after = draft[f];
    if (after === undefined) continue;
    const norm = (v: unknown) => (v === null || v === undefined || v === "" ? null : String(v));
    if (norm(before) !== norm(after)) out.push({ field: f, before, after });
  }
  return out;
}

/** Platform claim exposure is the remainder of the declared value, never additive. */
export function claimExposureBps(collateralPctBps: number): number {
  return Math.max(0, 10000 - (collateralPctBps ?? 0));
}

export async function loadPolicies(): Promise<FinancePolicyRow[]> {
  const { data, error } = await supabase
    .from("finance_policies")
    .select("*")
    .order("mission_type")
    .order("effective_from", { ascending: false });
  if (error) throw error;
  return (data ?? []) as unknown as FinancePolicyRow[];
}

export function currentPolicy(rows: FinancePolicyRow[], t: MissionType, now = new Date()) {
  return rows.find((r) => r.mission_type === t && r.enabled && new Date(r.effective_from) <= now);
}

/**
 * The row that will be in force immediately BEFORE `at` — mirrors
 * `public.finance_policy_predecessor`. A policy scheduled after another
 * scheduled policy must inherit from that predecessor, never from today's
 * active policy.
 */
export function predecessorPolicy(rows: FinancePolicyRow[], t: MissionType, at: Date) {
  return rows
    .filter((r) => r.mission_type === t && r.enabled && new Date(r.effective_from) < at)
    .sort((a, b) => +new Date(b.effective_from) - +new Date(a.effective_from))[0];
}

/** Same predecessor semantics for the single-row control-plane policy tables. */
export function predecessorRow<T extends { effective_from: string }>(rows: T[], at: Date): T | undefined {
  return rows
    .filter((r) => new Date(r.effective_from) < at)
    .sort((a, b) => +new Date(b.effective_from) - +new Date(a.effective_from))[0];
}

export function scheduledPolicies(rows: FinancePolicyRow[], t: MissionType, now = new Date()) {
  return rows
    .filter((r) => r.mission_type === t && new Date(r.effective_from) > now)
    .sort((a, b) => +new Date(a.effective_from) - +new Date(b.effective_from));
}

export function historyPolicies(rows: FinancePolicyRow[], t: MissionType, now = new Date()) {
  return rows
    .filter((r) => r.mission_type === t && new Date(r.effective_from) <= now)
    .sort((a, b) => +new Date(b.effective_from) - +new Date(a.effective_from));
}

export const fmtDateTime = (iso: string) =>
  new Date(iso).toLocaleString("fr-FR", { dateStyle: "short", timeStyle: "short" });
