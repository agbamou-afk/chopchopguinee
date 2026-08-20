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
  key: string;
  label: string;
  tone: "price" | "trust" | "distance" | "fresh";
}

const PRICE_STRONG = 0.7;
const TRUST_STRONG = 0.7;

/**
 * Turns server evidence into short French chips.
 * Missing evidence produces NO chip — a listing is never labelled "bad"
 * for lacking history.
 */
export function rankReasons(ev: RankEvidence | null | undefined, distanceM?: number | null): RankReason[] {
  const c = ev?.components;
  if (!c) return [];
  const out: RankReason[] = [];

  const price = c.price;
  if (price?.available && (price.score ?? 0) >= PRICE_STRONG) {
    out.push({ key: "price", label: "Bon prix observé", tone: "price" });
  }

  const rep = c.reputation;
  if (rep?.available && (rep.score ?? 0) >= TRUST_STRONG) {
    out.push({ key: "reputation", label: "Bien noté", tone: "trust" });
  }

  const rel = c.reliability;
  if (rel?.available && (rel.score ?? 0) >= TRUST_STRONG) {
    out.push({ key: "reliability", label: "Livre de façon fiable", tone: "trust" });
  }

  const dm = distanceM ?? c.distance?.distance_m ?? null;
  if (c.distance?.available && dm != null) {
    out.push({
      key: "distance",
      label: dm < 1000 ? `À ${Math.round(dm)} m` : `À ${(dm / 1000).toFixed(1)} km`,
      tone: "distance",
    });
  }

  if (ev?.cold_start) {
    out.push({ key: "new", label: "Nouvelle boutique", tone: "fresh" });
  }

  return out.slice(0, 3);
}
