import { supabase } from "@/integrations/supabase/client";

export type MapVerificationStatus =
  | "unverified" | "submitted" | "field_checked" | "admin_verified"
  | "trusted" | "needs_review" | "duplicate" | "closed";

export const VERIFICATION_LABEL: Record<MapVerificationStatus, string> = {
  unverified: "Non vérifié",
  submitted: "Soumis",
  field_checked: "Vérifié terrain",
  admin_verified: "Vérifié admin",
  trusted: "Confiance",
  needs_review: "À revoir",
  duplicate: "Doublon",
  closed: "Fermé",
};

export const DEFAULT_CONFIDENCE: Record<MapVerificationStatus, number> = {
  unverified: 20, submitted: 35, field_checked: 60, admin_verified: 80,
  trusted: 95, needs_review: 30, duplicate: 10, closed: 0,
};

export type ZoneStatus = "pilot" | "active" | "paused" | "inactive" | "needs_review";
export type ZonePriority = "low" | "normal" | "high" | "critical";
export type ZoneServices = {
  moto?: boolean; repas?: boolean; marche?: boolean; envoyer?: boolean; agents?: boolean;
};

export const ZONE_SERVICE_KEYS: Array<keyof ZoneServices> = [
  "moto", "repas", "marche", "envoyer", "agents",
];

/* ------------------------------ service zones ------------------------------ */

export async function listServiceZones() {
  const { data, error } = await supabase
    .from("map_service_zones")
    .select("*")
    .order("priority", { ascending: false })
    .order("name", { ascending: true })
    .limit(200);
  if (error) throw error;
  return data ?? [];
}

export async function upsertServiceZone(payload: any) {
  const { data, error } = await supabase
    .from("map_service_zones")
    .upsert(payload)
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function updateServiceZoneVerification(
  id: string,
  status: MapVerificationStatus,
) {
  const patch: Record<string, any> = {
    verification_status: status,
    confidence_score: DEFAULT_CONFIDENCE[status],
  };
  if (["admin_verified","trusted","field_checked"].includes(status)) {
    patch.verified_at = new Date().toISOString();
  }
  const { error } = await supabase.from("map_service_zones").update(patch).eq("id", id);
  if (error) throw error;
}

/* --------------------------------- places ---------------------------------- */

export async function listPlaces() {
  const { data, error } = await supabase
    .from("map_places")
    .select("*")
    .order("updated_at", { ascending: false })
    .limit(500);
  if (error) throw error;
  return data ?? [];
}

export async function updatePlaceVerification(
  id: string,
  status: MapVerificationStatus,
) {
  const patch: Record<string, any> = {
    verification_status: status,
    confidence_score: DEFAULT_CONFIDENCE[status],
  };
  if (["admin_verified", "trusted", "field_checked"].includes(status)) {
    patch.verified_at = new Date().toISOString();
  }
  if (status === "closed") patch.active = false;
  const { error } = await supabase.from("map_places").update(patch).eq("id", id);
  if (error) throw error;
}

/* ------------------------------ tarif tronçons ----------------------------- */

export async function listFareTroncons() {
  const { data, error } = await supabase
    .from("map_fare_troncons")
    .select("*")
    .order("departure_name", { ascending: true })
    .limit(500);
  if (error) throw error;
  return data ?? [];
}

export async function updateFareTroncon(id: string, patch: Record<string, any>) {
  const { error } = await supabase.from("map_fare_troncons").update(patch).eq("id", id);
  if (error) throw error;
}

/** Internal-only fare lookup. Exact match on normalized names, both directions when bidirectional. */
export async function estimateMotoFareByTroncon(args: {
  departure: string; destination: string; timeOfDay: "day" | "night";
}): Promise<{ price_gnf: number; troncon_id: string } | null> {
  const dep = args.departure.trim().toLowerCase();
  const dest = args.destination.trim().toLowerCase();
  const { data, error } = await supabase
    .from("map_fare_troncons")
    .select("id,departure_name,destination_name,day_price_gnf,night_price_gnf,is_bidirectional,is_active")
    .eq("is_active", true);
  if (error || !data) return null;
  const match = data.find((t) => {
    const a = (t.departure_name ?? "").toLowerCase();
    const b = (t.destination_name ?? "").toLowerCase();
    return (a === dep && b === dest) || (t.is_bidirectional && a === dest && b === dep);
  });
  if (!match) return null;
  const price = args.timeOfDay === "night" ? match.night_price_gnf : match.day_price_gnf;
  return price ? { price_gnf: price, troncon_id: match.id } : null;
}

/* -------------------------------- geojson safe ----------------------------- */

export function parseBoundaryGeoJSON(raw: string | null | undefined):
  | { ok: true; value: any }
  | { ok: false; error: string } {
  if (!raw || !raw.trim()) return { ok: true, value: null };
  try {
    const v = JSON.parse(raw);
    const t = v?.type;
    if (t !== "Polygon" && t !== "MultiPolygon" && t !== "Feature" && t !== "FeatureCollection") {
      return { ok: false, error: "Type attendu: Polygon / MultiPolygon / Feature(Collection)" };
    }
    return { ok: true, value: v };
  } catch {
    return { ok: false, error: "JSON invalide" };
  }
}