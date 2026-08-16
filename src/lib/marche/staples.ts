import { supabase } from "@/integrations/supabase/client";

/**
 * Node 4 — Marché R6: ChopChop Staples Catalog (read-only client surface).
 * This is a ChopChop-managed reference catalog, NOT marketplace supply.
 * No price, no ordering, no cart: R6 is identity + unit truth only.
 */

export type StapleNormalizationKind = "exact" | "unit_native" | "non_comparable";

export interface StaplePurchaseOption {
  option_code: string;
  sale_unit: string;
  label_fr: string;
  normalization_kind: StapleNormalizationKind;
  canonical_base_unit: "kg" | "l" | "piece" | null;
  canonical_quantity: number | null;
  min_qty: number;
  max_qty: number;
  step_qty: number;
}

export interface StapleVariant {
  variant_code: string;
  name_fr: string;
  grade_note_fr: string | null;
  is_default: boolean;
  sort_order: number;
  purchase_options: StaplePurchaseOption[];
}

export interface StapleSummary {
  commodity_id: string;
  commodity_code: string;
  name_fr: string;
  short_label_fr: string | null;
  description_fr: string | null;
  icon_key: string | null;
  unit_family: string;
  category_code: string;
  category_name_fr: string;
  aliases: string[] | null;
  option_count: number;
  sale_units: string[] | null;
}

export interface StapleDetail extends Omit<StapleSummary, "commodity_id" | "option_count" | "sale_units"> {
  variants: StapleVariant[];
}

export interface StapleCategory {
  code: string;
  name_fr: string;
  sort_order: number;
  commodity_count: number;
}

type RpcClient = {
  rpc: (name: string, args?: Record<string, unknown>) => Promise<{ data: unknown; error: unknown }>;
};
const rpc = supabase as unknown as RpcClient;

export async function listStapleCategories(): Promise<StapleCategory[]> {
  const { data } = await rpc.rpc("marche_staple_categories_public", {});
  return ((data ?? []) as StapleCategory[]).slice().sort((a, b) => a.sort_order - b.sort_order);
}

export async function discoverStaples(params: {
  search?: string | null;
  category?: string | null;
  limit?: number;
  offset?: number;
}): Promise<StapleSummary[]> {
  const { data } = await rpc.rpc("marche_staples_discover", {
    p_search: params.search?.trim() || null,
    p_category: params.category ?? null,
    p_limit: params.limit ?? 60,
    p_offset: params.offset ?? 0,
  });
  return (data ?? []) as StapleSummary[];
}

export async function getStaple(commodityCode: string): Promise<StapleDetail | null> {
  const { data } = await rpc.rpc("marche_staple_get", { p_commodity_code: commodityCode });
  return (data as StapleDetail | null) ?? null;
}

/** Honest French label for how a sale unit compares — never invents a conversion. */
export function normalizationLabel(o: StaplePurchaseOption): string {
  if (o.normalization_kind === "exact" && o.canonical_quantity && o.canonical_base_unit) {
    const unit = o.canonical_base_unit === "l" ? "L" : o.canonical_base_unit === "kg" ? "kg" : "pièce";
    return `≈ ${o.canonical_quantity} ${unit}`;
  }
  if (o.normalization_kind === "unit_native") return "Vendu à l'unité locale";
  return "Quantité variable — non comparable";
}
