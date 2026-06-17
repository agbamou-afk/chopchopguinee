import { supabase } from "@/integrations/supabase/client";

/**
 * Map Phase 2G — Trusted merchant location resolver.
 *
 * Returns the safest coordinates to use for a merchant pickup, preferring
 * trusted/admin-verified `map_places` before falling back to legacy
 * `merchant_stores` or `food_restaurants` coordinates. Never blocks an
 * order — callers must treat `missing` as a soft-warn case.
 */

export type TrustedLocationSource =
  | "trusted_map_place"
  | "admin_verified_map_place"
  | "submitted_map_place"
  | "merchant_store_coordinates"
  | "restaurant_coordinates"
  | "listing_coordinates"
  | "missing";

export interface TrustedMerchantLocation {
  lat: number | null;
  lng: number | null;
  source: TrustedLocationSource;
  verification_status: string | null;
  confidence_score: number;
  warning: string | null;
}

const MISSING: TrustedMerchantLocation = {
  lat: null,
  lng: null,
  source: "missing",
  verification_status: null,
  confidence_score: 0,
  warning: "Position marchand manquante — À confirmer",
};

function fromMapPlace(p: { lat: number | null; lng: number | null; verification_status: string | null; confidence_score?: number | null }): TrustedMerchantLocation | null {
  if (p.lat == null || p.lng == null) return null;
  const vs = (p.verification_status ?? "submitted").toLowerCase();
  if (vs === "trusted") return { lat: p.lat, lng: p.lng, source: "trusted_map_place", verification_status: vs, confidence_score: p.confidence_score ?? 90, warning: null };
  if (vs === "admin_verified" || vs === "verified") return { lat: p.lat, lng: p.lng, source: "admin_verified_map_place", verification_status: vs, confidence_score: p.confidence_score ?? 70, warning: null };
  return { lat: p.lat, lng: p.lng, source: "submitted_map_place", verification_status: vs, confidence_score: p.confidence_score ?? 35, warning: "Position non vérifiée — À confirmer" };
}

export async function resolveTrustedMerchantLocation(args: {
  merchant_store_id?: string | null;
  restaurant_id?: string | null;
  listing_id?: string | null;
}): Promise<TrustedMerchantLocation> {
  // 1. merchant_store -> map_place
  if (args.merchant_store_id) {
    const { data: store } = await supabase
      .from("merchant_stores")
      .select("latitude, longitude, map_place_id")
      .eq("id", args.merchant_store_id)
      .maybeSingle();
    if (store?.map_place_id) {
      const { data: place } = await (supabase as any)
        .from("map_places")
        .select("lat,lng,verification_status,confidence_score")
        .eq("id", store.map_place_id)
        .maybeSingle();
      const mp = place ? fromMapPlace(place) : null;
      if (mp) return mp;
    }
    if (store?.latitude != null && store?.longitude != null) {
      return { lat: store.latitude, lng: store.longitude, source: "merchant_store_coordinates", verification_status: "legacy", confidence_score: 30, warning: "Position héritée — À confirmer" };
    }
  }

  // 2. restaurant -> store -> map_place, or restaurant coords
  if (args.restaurant_id) {
    const { data: rest } = await supabase
      .from("food_restaurants")
      .select("latitude, longitude, merchant_store_id")
      .eq("id", args.restaurant_id)
      .maybeSingle();
    if (rest?.merchant_store_id) {
      const sub = await resolveTrustedMerchantLocation({ merchant_store_id: rest.merchant_store_id });
      if (sub.source !== "missing") return sub;
    }
    if (rest?.latitude != null && rest?.longitude != null) {
      return { lat: rest.latitude, lng: rest.longitude, source: "restaurant_coordinates", verification_status: "legacy", confidence_score: 25, warning: "Position restaurant — À confirmer" };
    }
  }

  // 3. listing fallback (latitude/longitude if present on marketplace_listings)
  if (args.listing_id) {
    const { data: listing } = await (supabase as any)
      .from("marketplace_listings")
      .select("latitude, longitude, store_id")
      .eq("id", args.listing_id)
      .maybeSingle();
    if (listing?.store_id) {
      const sub = await resolveTrustedMerchantLocation({ merchant_store_id: listing.store_id });
      if (sub.source !== "missing") return sub;
    }
    if (listing?.latitude != null && listing?.longitude != null) {
      return { lat: listing.latitude, lng: listing.longitude, source: "listing_coordinates", verification_status: "legacy", confidence_score: 20, warning: "Position annonce — À confirmer" };
    }
  }

  return MISSING;
}