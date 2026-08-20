// Node 4 — Marché R10: discovery + ranking intelligence (client read surface).
// LAW: the server is the only ranking authority. This module never scores,
// re-orders, or invents evidence — it only reads and labels what the server says.
import { supabase } from "@/integrations/supabase/client";

export type MarcheSort = "recommended" | "recent" | "price_asc" | "price_desc";

export interface RankComponent {
  available: boolean;
  score: number | null;
  reason?: string | null;
  sample_count?: number | null;
  distance_m?: number | null;
  self_excluded?: boolean;
  method?: string | null;
}

export interface RankEvidence {
  ranked?: boolean;
  reason?: string | null;
  policy_version?: number | null;
  components?: Record<string, RankComponent>;
  components_available?: number;
  components_total?: number;
  evidence_completeness?: number;
  cold_start?: boolean;
  score?: number | null;
  score_bps?: number | null;
  /** Server-authored ranking reasons. The client never invents one. */
  why_ranked?: RankReason[] | null;
}

export interface DiscoverRow {
  id: string;
  title: string;
  price_gnf: number | null;
  is_negotiable: boolean;
  is_urgent: boolean;
  delivery_available: boolean;
  neighborhood: string | null;
  commune: string | null;
  created_at: string;
  kind: string;
  availability: string | null;
  fulfillment_options: string[] | null;
  photo_count: number | null;
  condition: string | null;
  description: string | null;
  category: string | null;
  store_id: string | null;
  cover_url: string | null;
  rank_score_bps: number | null;
  rank_distance_m: number | null;
  rank_evidence: RankEvidence | null;
}

export interface DiscoverParams {
  search?: string | null;
  category?: string | null;
  storeId?: string | null;
  sort?: MarcheSort;
  limit?: number;
  offset?: number;
  lat?: number | null;
  lng?: number | null;
}

type Rpc = {
  rpc: (n: string, a?: Record<string, unknown>) => Promise<{ data: unknown; error: unknown }>;
};

export async function discoverListings(p: DiscoverParams = {}): Promise<DiscoverRow[]> {
  const { data } = await (supabase as unknown as Rpc).rpc("marche_listings_discover", {
    p_search: p.search?.trim() || null,
    p_category: p.category ?? null,
    p_store_id: p.storeId ?? null,
    p_sort: p.sort ?? "recommended",
    p_limit: p.limit ?? 60,
    p_offset: p.offset ?? 0,
    p_lat: p.lat ?? null,
    p_lng: p.lng ?? null,
  });
  return (data ?? []) as DiscoverRow[];
}

/** Honest, server-sourced explanation of why one listing ranks where it does. */
export async function explainListingRank(
  listingId: string,
  lat?: number | null,
  lng?: number | null,
): Promise<RankEvidence | null> {
  const { data } = await (supabase as unknown as Rpc).rpc("marche_listing_rank_explain", {
    p_listing_id: listingId,
    p_lat: lat ?? null,
    p_lng: lng ?? null,
  });
  return (data ?? null) as RankEvidence | null;
}

/** The ranking policy currently in force — publicly disclosed, never secret. */
export async function getRankingPolicy(): Promise<Record<string, unknown> | null> {
  const { data } = await (supabase as unknown as Rpc).rpc("marche_ranking_policy_public");
  return (data ?? null) as Record<string, unknown> | null;
}

export interface RankReason {
  /** Server reason code, e.g. GOOD_VALUE, WELL_RATED, NEARBY. */
  code: string;
  /** Server-authored French label. */
  label: string;
}

/**
 * Returns the reasons the SERVER authored for this listing.
 * The client applies no threshold, no scoring and no judgement of its own:
 * missing evidence simply yields no chip, and a cold-start listing is never
 * labelled "bad" for lacking history.
 */
export function rankReasons(ev: RankEvidence | null | undefined): RankReason[] {
  const raw = ev?.why_ranked;
  if (!Array.isArray(raw)) return [];
  return raw
    .filter((r): r is RankReason =>
      !!r && typeof r.code === "string" && r.code.length > 0 &&
      typeof r.label === "string" && r.label.length > 0)
    .slice(0, 2);
}
