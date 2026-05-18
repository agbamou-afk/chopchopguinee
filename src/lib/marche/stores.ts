import { supabase } from "@/integrations/supabase/client";
import { slugify } from "@/lib/marche";

export type MerchantStore = {
  id: string;
  owner_user_id: string;
  slug: string;
  name: string;
  avatar_url: string | null;
  cover_url: string | null;
  bio: string | null;
  district: string | null;
  category: string | null;
  delivery_available: boolean;
  choppay_enabled: boolean;
  verification_state: "none" | "pending" | "verified";
  member_since: string;
  status: string;
};

export async function getStoreBySlug(slug: string) {
  const { data } = await supabase
    .from("merchant_stores" as never)
    .select("*")
    .eq("slug", slug)
    .maybeSingle();
  return (data as MerchantStore | null) ?? null;
}

export async function getStoreById(id: string) {
  const { data } = await supabase
    .from("merchant_stores" as never)
    .select("*")
    .eq("id", id)
    .maybeSingle();
  return (data as MerchantStore | null) ?? null;
}

export async function getOwnStore(userId: string) {
  const { data } = await supabase
    .from("merchant_stores" as never)
    .select("*")
    .eq("owner_user_id", userId)
    .maybeSingle();
  return (data as MerchantStore | null) ?? null;
}

export async function listStores(opts: { q?: string; district?: string; limit?: number } = {}) {
  let q = supabase
    .from("merchant_stores" as never)
    .select("*")
    .eq("status", "active")
    .order("member_since", { ascending: false })
    .limit(opts.limit ?? 30);
  if (opts.q?.trim()) q = q.ilike("name", `%${opts.q.trim()}%`);
  if (opts.district) q = q.eq("district", opts.district);
  const { data } = await q;
  return (data as MerchantStore[] | null) ?? [];
}

export async function createOrUpdateStore(input: {
  ownerUserId: string;
  name: string;
  district?: string | null;
  bio?: string | null;
  delivery_available?: boolean;
  choppay_enabled?: boolean;
  avatar_url?: string | null;
}) {
  const existing = await getOwnStore(input.ownerUserId);
  const payload = {
    owner_user_id: input.ownerUserId,
    name: input.name,
    slug: existing?.slug ?? `${slugify(input.name)}-${input.ownerUserId.slice(0, 6)}`,
    district: input.district ?? null,
    bio: input.bio ?? null,
    avatar_url: input.avatar_url ?? null,
    delivery_available: !!input.delivery_available,
    choppay_enabled: !!input.choppay_enabled,
    status: "active",
  };
  if (existing) {
    const { data, error } = await supabase
      .from("merchant_stores" as never)
      .update(payload)
      .eq("id", existing.id)
      .select("*")
      .single();
    if (error) throw error;
    return data as unknown as MerchantStore;
  }
  const { data, error } = await supabase
    .from("merchant_stores" as never)
    .insert(payload)
    .select("*")
    .single();
  if (error) throw error;
  return data as unknown as MerchantStore;
}

export async function countActiveListingsForStore(storeId: string) {
  const { count } = await supabase
    .from("marketplace_listings")
    .select("id", { count: "exact", head: true })
    .eq("store_id", storeId)
    .eq("status", "active");
  return count ?? 0;
}

export async function incrementListingMetric(listingId: string, kind: "view" | "click" | "save" | "message") {
  try {
    // RPC name as defined in migration. Cast to never to bypass missing typing.
    await (supabase.rpc as unknown as (n: string, a: Record<string, unknown>) => Promise<unknown>)(
      "marche_increment_listing_metric",
      { _listing_id: listingId, _kind: kind },
    );
  } catch {
    /* non-blocking */
  }
}

export async function getListingMetrics(listingId: string) {
  const { data } = await supabase
    .from("listing_metrics" as never)
    .select("views, clicks, saves, messages")
    .eq("listing_id", listingId)
    .maybeSingle();
  return (data as { views: number; clicks: number; saves: number; messages: number } | null) ?? {
    views: 0,
    clicks: 0,
    saves: 0,
    messages: 0,
  };
}