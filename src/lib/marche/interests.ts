import { supabase } from "@/integrations/supabase/client";

// Marché Phase 3 — Interest pipeline.
// Lightweight buyer signal table; types not yet in generated Supabase types,
// so we cast at call sites with narrow shapes.

export type InterestKind = "availability" | "delivery" | "reservation" | "offer";
export type InterestState =
  | "pending"
  | "available"
  | "reserved"
  | "sold"
  | "responded"
  | "declined";

export type ListingInterest = {
  id: string;
  listing_id: string;
  buyer_id: string;
  seller_id: string;
  kind: InterestKind;
  state: InterestState;
  note: string | null;
  response: string | null;
  created_at: string;
  updated_at: string;
};

type AnyBuilder = {
  select: (s: string) => AnyBuilder;
  insert: (p: Record<string, unknown>) => AnyBuilder;
  update: (p: Record<string, unknown>) => AnyBuilder;
  eq: (c: string, v: unknown) => AnyBuilder;
  in: (c: string, v: unknown[]) => AnyBuilder;
  order: (c: string, o: { ascending: boolean }) => AnyBuilder;
  limit: (n: number) => AnyBuilder;
  maybeSingle: () => Promise<{ data: unknown; error: { message: string } | null }>;
  single: () => Promise<{ data: unknown; error: { message: string } | null }>;
  then: <T>(r: (v: { data: unknown; error: { message: string } | null }) => T) => Promise<T>;
};
const table = () =>
  (supabase as unknown as { from: (n: string) => AnyBuilder }).from("listing_interests");

export async function createInterest(input: {
  listingId: string;
  buyerId: string;
  sellerId: string;
  kind: InterestKind;
  note?: string | null;
}) {
  const { data, error } = await table()
    .insert({
      listing_id: input.listingId,
      buyer_id: input.buyerId,
      seller_id: input.sellerId,
      kind: input.kind,
      note: input.note ?? null,
    })
    .select("*")
    .single();
  if (error) throw error;
  return data as ListingInterest;
}

export async function listInterestsForListing(listingId: string) {
  const { data } = await table()
    .select("*")
    .eq("listing_id", listingId)
    .order("created_at", { ascending: false });
  return ((data as ListingInterest[] | null) ?? []);
}

export async function listSellerInterests(sellerId: string, limit = 50) {
  const { data } = await table()
    .select("*")
    .eq("seller_id", sellerId)
    .order("created_at", { ascending: false })
    .limit(limit);
  return ((data as ListingInterest[] | null) ?? []);
}

export async function listBuyerInterests(buyerId: string, limit = 50) {
  const { data } = await table()
    .select("*")
    .eq("buyer_id", buyerId)
    .order("created_at", { ascending: false })
    .limit(limit);
  return ((data as ListingInterest[] | null) ?? []);
}

export async function respondInterest(
  id: string,
  state: Exclude<InterestState, "pending">,
  response?: string | null,
) {
  const { data, error } = await table()
    .update({ state, response: response ?? null })
    .eq("id", id)
    .select("*")
    .single();
  if (error) throw error;
  return data as ListingInterest;
}

export async function countInterestsByListing(listingIds: string[]) {
  if (listingIds.length === 0) return new Map<string, { total: number; pending: number }>();
  const { data } = await table()
    .select("listing_id, state")
    .in("listing_id", listingIds);
  const rows = (data as Array<{ listing_id: string; state: InterestState }> | null) ?? [];
  const map = new Map<string, { total: number; pending: number }>();
  for (const r of rows) {
    const cur = map.get(r.listing_id) ?? { total: 0, pending: 0 };
    cur.total += 1;
    if (r.state === "pending") cur.pending += 1;
    map.set(r.listing_id, cur);
  }
  return map;
}

export const INTEREST_KIND_LABEL: Record<InterestKind, string> = {
  availability: "Demande de disponibilité",
  delivery: "Demande de livraison",
  reservation: "Demande de réservation",
  offer: "Offre",
};

export const INTEREST_STATE_LABEL: Record<InterestState, string> = {
  pending: "En attente",
  available: "Disponible confirmé",
  reserved: "Réservé",
  sold: "Vendu",
  responded: "Réponse envoyée",
  declined: "Refusé",
};