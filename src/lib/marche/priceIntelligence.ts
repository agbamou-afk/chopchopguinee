import { supabase } from "@/integrations/supabase/client";

/**
 * Node 4 — Marché R8: Market Price Intelligence (read-only client surface).
 *
 * Doctrine: what we show is what ChopChop OBSERVED (approved merchant asks +
 * verified shopper purchases). It is never an official, guaranteed or predicted
 * price. When evidence is too thin or too old, the server refuses a headline
 * number and the UI must say so honestly.
 */

export type PriceConfidence = "insufficient" | "low" | "medium" | "high";
export type PriceFreshness = "fresh" | "recent" | "stale" | "unknown";

export interface ObservedPriceMovement {
  comparable: boolean;
  reason?: string;
  previous_median_gnf?: number;
  current_median_gnf?: number;
  delta_gnf?: number;
  delta_pct?: number;
}

export interface ObservedPriceCohort {
  variant_code: string;
  variant_name_fr: string;
  canonical_base_unit: string;
  zone: string;
  sample_count: number;
  insufficient_data: boolean;
  confidence: PriceConfidence;
  freshness: PriceFreshness;
  reason?: string;
  min_samples?: number;
  median_gnf?: number;
  p25_gnf?: number;
  p75_gnf?: number;
  min_gnf?: number;
  max_gnf?: number;
  window_hours?: number;
  first_observed_at?: string;
  latest_observed_at?: string;
  source_mix?: { merchant_ask?: number; verified_procurement?: number };
  movement?: ObservedPriceMovement;
}

export interface ObservedPriceRead {
  commodity_code: string;
  zone: string;
  doctrine: string;
  cohorts: ObservedPriceCohort[];
}

type RpcClient = {
  rpc: (name: string, args?: Record<string, unknown>) => Promise<{ data: unknown; error: unknown }>;
};
const rpc = supabase as unknown as RpcClient;

const EMPTY: ObservedPriceRead = {
  commodity_code: "",
  zone: "all",
  doctrine: "Prix observé sur ChopChop",
  cohorts: [],
};

const cache = new Map<string, Promise<ObservedPriceRead>>();

/** Server-sourced observed prices for a canonical commodity. Never computed client-side. */
export async function getObservedPrices(
  commodityCode: string,
  zone?: string | null,
): Promise<ObservedPriceRead> {
  const key = `${commodityCode}|${zone ?? ""}`;
  const hit = cache.get(key);
  if (hit) return hit;
  const p = (async () => {
    const { data } = await rpc.rpc("marche_price_observed_public", {
      p_commodity_code: commodityCode,
      p_zone: zone || null,
    });
    return ((data as ObservedPriceRead | null) ?? { ...EMPTY, commodity_code: commodityCode });
  })().catch(() => ({ ...EMPTY, commodity_code: commodityCode }));
  cache.set(key, p);
  return p;
}

export function clearObservedPriceCache() {
  cache.clear();
}

/** Pick the cohort for a variant, preferring a comparable weight/volume unit. */
export function pickVariantCohort(
  read: ObservedPriceRead | null,
  variantCode: string,
): ObservedPriceCohort | null {
  if (!read) return null;
  const rows = read.cohorts.filter((c) => c.variant_code === variantCode);
  if (rows.length === 0) return null;
  const usable = rows.filter((c) => !c.insufficient_data);
  const pool = usable.length > 0 ? usable : rows;
  return pool.slice().sort((a, b) => (b.sample_count ?? 0) - (a.sample_count ?? 0))[0] ?? null;
}

export function baseUnitLabel(unit: string | null | undefined): string {
  if (!unit) return "";
  if (unit === "kg") return "kg";
  if (unit === "l") return "L";
  if (unit === "piece") return "pièce";
  if (unit.startsWith("unit:")) return unit.slice(5);
  return unit;
}

export function confidenceLabelFr(c: PriceConfidence): string {
  switch (c) {
    case "high":
      return "Observations nombreuses";
    case "medium":
      return "Observations suffisantes";
    case "low":
      return "Peu d'observations";
    default:
      return "Pas assez d'observations";
  }
}

export function freshnessLabelFr(f: PriceFreshness): string {
  switch (f) {
    case "fresh":
      return "relevés récents";
    case "recent":
      return "relevés de ces derniers jours";
    case "stale":
      return "relevés anciens";
    default:
      return "date inconnue";
  }
}