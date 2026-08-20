import { supabase } from "@/integrations/supabase/client";

/**
 * Node 4 — Marché R8: Market Price Intelligence (read-only client surface).
 *
 * Every value rendered here is SERVER-DERIVED. The client never computes,
 * estimates, extrapolates or invents a price, a confidence or a freshness
 * state. The only allowed client work is mapping the exact server vocabulary
 * to honest French copy.
 *
 * Server contract (public.marche_price_freshness / marche_price_confidence):
 *   freshness  : 'none' | 'fresh' | 'aging' | 'stale'
 *   confidence : 'insufficient' | 'low' | 'medium' | 'high'
 */

/** Exact server freshness vocabulary — no client-invented state. */
export const PRICE_FRESHNESS_VALUES = ["none", "fresh", "aging", "stale"] as const;
export type PriceFreshness = (typeof PRICE_FRESHNESS_VALUES)[number];

/** Exact server confidence vocabulary. */
export const PRICE_CONFIDENCE_VALUES = ["insufficient", "low", "medium", "high"] as const;
export type PriceConfidence = (typeof PRICE_CONFIDENCE_VALUES)[number];

export interface PriceMovement {
  comparable: boolean;
  reason?: string | null;
  previous_median_gnf?: number | null;
  current_median_gnf?: number | null;
  delta_gnf?: number | null;
  delta_pct?: number | null;
}

export interface PriceCohort {
  variant_id: string;
  variant_code?: string | null;
  variant_name_fr?: string | null;
  canonical_base_unit: string;
  /** Server zone context: a commune, or the sentinels 'all' / 'unknown'. */
  zone: string;
  sample_count: number;
  insufficient_data: boolean;
  confidence: PriceConfidence;
  freshness: PriceFreshness;
  reason?: string | null;
  min_samples?: number | null;
  p25_gnf?: number | null;
  median_gnf?: number | null;
  p75_gnf?: number | null;
  min_gnf?: number | null;
  max_gnf?: number | null;
  first_observed_at?: string | null;
  latest_observed_at?: string | null;
  window_hours?: number | null;
  source_mix?: { merchant_ask?: number; verified_procurement?: number } | null;
  movement?: PriceMovement | null;
}

export interface ObservedPriceResult {
  commodity_code: string;
  zone: string;
  cohorts: PriceCohort[];
  doctrine: string;
}

type RpcClient = {
  rpc: (name: string, args?: Record<string, unknown>) => Promise<{ data: unknown; error: unknown }>;
};
const rpc = supabase as unknown as RpcClient;

const cache = new Map<string, Promise<ObservedPriceResult | null>>();

/** Zone sentinels that carry no specific place meaning. */
export function isSpecificZone(zone: string | null | undefined): boolean {
  if (!zone) return false;
  const z = zone.trim().toLowerCase();
  return z.length > 0 && z !== "all" && z !== "unknown";
}

/** Honest French zone context, or null when the server has no specific zone. */
export function zoneLabel(zone: string | null | undefined): string | null {
  if (isSpecificZone(zone)) return `Zone : ${zone}`;
  if ((zone ?? "").trim().toLowerCase() === "all") return "Toutes zones";
  return null;
}

/** Maps the EXACT server freshness vocabulary to honest French copy. */
export function freshnessLabel(freshness: PriceFreshness | string | null | undefined): string {
  switch (freshness) {
    case "fresh":
      return "Observé récemment";
    case "aging":
      return "Observation vieillissante";
    case "stale":
      return "Observation ancienne";
    case "none":
      return "Aucune date d'observation";
    default:
      // Unknown server value: stay honest, never guess a freshness state.
      return "Aucune date d'observation";
  }
}

export function confidenceLabel(confidence: PriceConfidence | string | null | undefined): string {
  switch (confidence) {
    case "high":
      return "Fiabilité élevée";
    case "medium":
      return "Fiabilité moyenne";
    case "low":
      return "Fiabilité faible";
    case "insufficient":
      return "Données insuffisantes";
    default:
      return "Données insuffisantes";
  }
}

export function formatGnf(value: number | null | undefined): string {
  if (value == null || !Number.isFinite(value)) return "—";
  return `${Math.floor(value).toLocaleString("fr-FR")} GNF`;
}

/** Server-sourced observed prices for a staple commodity. */
export async function fetchObservedPrices(
  commodityCode: string,
  zone?: string | null,
): Promise<ObservedPriceResult | null> {
  const key = `${commodityCode}|${zone ?? ""}`;
  const hit = cache.get(key);
  if (hit) return hit;
  const pending = (async () => {
    const { data, error } = await rpc.rpc("marche_price_observed_public", {
      p_commodity_code: commodityCode,
      p_zone: zone ?? null,
    });
    if (error || !data) return null;
    return data as ObservedPriceResult;
  })().catch(() => null);
  cache.set(key, pending);
  return pending;
}

export function clearObservedPriceCache(): void {
  cache.clear();
}

/** Picks the cohort matching a variant code, if the server returned one. */
export function pickVariantCohort(
  result: ObservedPriceResult | null,
  variantCode: string,
): PriceCohort | null {
  if (!result) return null;
  return result.cohorts.find((c) => c.variant_code === variantCode) ?? null;
}