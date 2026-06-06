import { supabase } from "@/integrations/supabase/client";
import { slugify } from "@/lib/marche";

// Note: types for merchant_stores / listing_metrics aren't in the generated
// Supabase types yet, so we cast `supabase` to a permissive shape at call sites.

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
  const { data } = await (supabase as unknown as {
    from: (t: string) => { select: (s: string) => { eq: (c: string, v: unknown) => { maybeSingle: () => Promise<{ data: unknown }> } } };
  }).from("merchant_stores").select("*").eq("slug", slug).maybeSingle();
  return (data as MerchantStore | null) ?? null;
}

export async function getStoreById(id: string) {
  const { data } = await (supabase as unknown as {
    from: (t: string) => { select: (s: string) => { eq: (c: string, v: unknown) => { maybeSingle: () => Promise<{ data: unknown }> } } };
  }).from("merchant_stores").select("*").eq("id", id).maybeSingle();
  return (data as MerchantStore | null) ?? null;
}

export async function getOwnStore(userId: string) {
  const { data } = await (supabase as unknown as {
    from: (t: string) => { select: (s: string) => { eq: (c: string, v: unknown) => { maybeSingle: () => Promise<{ data: unknown }> } } };
  }).from("merchant_stores").select("*").eq("owner_user_id", userId).maybeSingle();
  return (data as MerchantStore | null) ?? null;
}

export async function listStores(opts: { q?: string; district?: string; limit?: number } = {}) {
  type Builder = {
    eq: (c: string, v: unknown) => Builder;
    ilike: (c: string, v: string) => Builder;
    order: (c: string, o: { ascending: boolean }) => Builder;
    limit: (n: number) => Builder;
    then: <T>(r: (v: { data: unknown }) => T) => Promise<T>;
  };
  let q = (supabase as unknown as {
    from: (t: string) => { select: (s: string) => Builder };
  })
    .from("merchant_stores")
    .select("*")
    .eq("status", "active")
    .eq("onboarding_status", "approved")
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
  type WriteBuilder = {
    insert: (p: Record<string, unknown>) => { select: (s: string) => { single: () => Promise<{ data: unknown; error: { message: string } | null }> } };
    update: (p: Record<string, unknown>) => { eq: (c: string, v: unknown) => { select: (s: string) => { single: () => Promise<{ data: unknown; error: { message: string } | null }> } } };
  };
  const t = (supabase as unknown as { from: (n: string) => WriteBuilder }).from("merchant_stores");
  if (existing) {
    const { data, error } = await t.update(payload).eq("id", existing.id).select("*").single();
    if (error) throw error;
    return data as unknown as MerchantStore;
  }
  const { data, error } = await t.insert(payload).select("*").single();
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
    await (supabase.rpc as unknown as (n: string, a: Record<string, unknown>) => Promise<unknown>)(
      "marche_increment_listing_metric",
      { _listing_id: listingId, _kind: kind },
    );
  } catch {
    /* non-blocking */
  }
}

export async function getListingMetrics(listingId: string) {
  const { data } = await (supabase as unknown as {
    from: (t: string) => { select: (s: string) => { eq: (c: string, v: unknown) => { maybeSingle: () => Promise<{ data: unknown }> } } };
  }).from("listing_metrics").select("views, clicks, saves, messages").eq("listing_id", listingId).maybeSingle();
  return (data as { views: number; clicks: number; saves: number; messages: number } | null) ?? {
    views: 0,
    clicks: 0,
    saves: 0,
    messages: 0,
  };
}