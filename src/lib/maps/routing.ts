import { haversineMeters, decodePolyline, type LatLng } from "./geo";
import { RoutingService } from "./RoutingService";
import { supabase } from "@/integrations/supabase/client";

/**
 * Map Phase 2E — Routing + ETA Foundation
 *
 * Safe abstraction over provider routing with a conservative haversine
 * fallback. Intended for ETA / distance display only. NOT for final
 * customer pricing — see map_fare_troncons (internal observed only).
 */

export type RouteMode = "moto" | "car" | "walking" | "fallback";
export type TimeOfDay = "day" | "night";
export type RouteConfidence = "high" | "medium" | "fallback";

export interface RouteEstimate {
  distance_meters: number;
  duration_seconds: number;
  polyline_geojson: GeoJSON.LineString | null;
  provider: "google" | "osrm" | "graphhopper" | "chop_fallback";
  confidence: RouteConfidence;
  fallback_used: boolean;
  warning: string | null;
  mode: RouteMode;
}

/** Conservative road-factor multipliers vs straight-line distance. */
const ROAD_FACTOR: Record<RouteMode, number> = {
  moto: 1.35, car: 1.45, walking: 1.10, fallback: 1.35,
};

/** km/h averages used only in fallback. */
const AVG_SPEED_KMH: Record<RouteMode, { day: number; night: number }> = {
  moto:     { day: 22, night: 28 },
  car:      { day: 18, night: 24 },
  walking:  { day: 4.5, night: 4.5 },
  fallback: { day: 20, night: 25 },
};

export function timeOfDayNow(d: Date = new Date()): TimeOfDay {
  const h = d.getHours();
  return h >= 6 && h < 19 ? "day" : "night";
}

function providerToRouteMode(mode: RouteMode) {
  if (mode === "walking") return "walking" as const;
  if (mode === "moto") return "two_wheeler" as const;
  if (mode === "car") return "driving" as const;
  return "driving" as const;
}

/** Cheap in-memory memoization to avoid re-calling provider on every render. */
const cache = new Map<string, { at: number; value: RouteEstimate }>();
const TTL_MS = 60_000;
function cacheKey(o: LatLng, d: LatLng, m: RouteMode) {
  return `${o.lat.toFixed(5)},${o.lng.toFixed(5)}|${d.lat.toFixed(5)},${d.lng.toFixed(5)}|${m}`;
}

export function fallbackEstimate(
  origin: LatLng, destination: LatLng, mode: RouteMode, tod: TimeOfDay = timeOfDayNow(),
): RouteEstimate {
  const straight = haversineMeters(origin, destination);
  const distance_meters = Math.round(straight * ROAD_FACTOR[mode]);
  const kmh = AVG_SPEED_KMH[mode][tod];
  const duration_seconds = Math.max(30, Math.round((distance_meters / 1000) / kmh * 3600));
  return {
    distance_meters,
    duration_seconds,
    polyline_geojson: {
      type: "LineString",
      coordinates: [[origin.lng, origin.lat], [destination.lng, destination.lat]],
    },
    provider: "chop_fallback",
    confidence: "fallback",
    fallback_used: true,
    warning: "Estimation approximative — trajet à confirmer",
    mode,
  };
}

/** Decode Google polyline to GeoJSON LineString. */
function polylineToGeoJSON(encoded: string): GeoJSON.LineString | null {
  if (!encoded) return null;
  try {
    const pts = decodePolyline(encoded);
    if (pts.length < 2) return null;
    return { type: "LineString", coordinates: pts.map(p => [p.lng, p.lat]) };
  } catch { return null; }
}

export async function getRouteEstimate(args: {
  origin: LatLng;
  destination: LatLng;
  mode?: RouteMode;
  providerPreference?: "google" | "osrm" | "graphhopper";
  timeOfDay?: TimeOfDay;
  bypassCache?: boolean;
}): Promise<RouteEstimate> {
  const mode: RouteMode = args.mode ?? "moto";
  const k = cacheKey(args.origin, args.destination, mode);
  if (!args.bypassCache) {
    const hit = cache.get(k);
    if (hit && Date.now() - hit.at < TTL_MS) return hit.value;
  }

  // If straight-line distance is sub-50m, skip the provider call.
  const straight = haversineMeters(args.origin, args.destination);
  if (straight < 50) {
    const v = fallbackEstimate(args.origin, args.destination, mode, args.timeOfDay);
    cache.set(k, { at: Date.now(), value: v });
    return v;
  }

  try {
    if (args.providerPreference) RoutingService.setProvider(args.providerPreference);
    const r = await RoutingService.route(args.origin, args.destination, providerToRouteMode(mode));
    const value: RouteEstimate = {
      distance_meters: r.distanceM,
      duration_seconds: r.durationS,
      polyline_geojson: polylineToGeoJSON(r.polyline),
      provider: r.provider,
      confidence: r.provider === "google" ? "high" : "medium",
      fallback_used: false,
      warning: null,
      mode,
    };
    cache.set(k, { at: Date.now(), value });
    return value;
  } catch (e) {
    const value = fallbackEstimate(args.origin, args.destination, mode, args.timeOfDay);
    value.warning = `Fournisseur indisponible — estimation approximative (${(e as Error)?.message ?? "erreur"})`;
    cache.set(k, { at: Date.now(), value });
    return value;
  }
}

export function clearRouteEstimateCache() { cache.clear(); }

/* ----------------------- Tronçon internal comparison ---------------------- */

/**
 * Exact-match comparison against observed map_fare_troncons.
 * Internal/admin-only display. NOT customer-facing pricing.
 */
export async function compareRouteToObservedTroncons(args: {
  originName: string; destinationName: string; timeOfDay: TimeOfDay;
}): Promise<{
  price_gnf: number; troncon_id: string; verification_status: string;
  label: "Tarif local observé — Non officiel — À vérifier";
} | null> {
  const dep = args.originName.trim().toLowerCase();
  const dest = args.destinationName.trim().toLowerCase();
  if (!dep || !dest) return null;
  const { data, error } = await supabase
    .from("map_fare_troncons")
    .select("id,departure_name,destination_name,day_price_gnf,night_price_gnf,is_bidirectional,is_active,verification_status")
    .eq("is_active", true);
  if (error || !data) return null;
  const match = data.find((t: any) => {
    const a = (t.departure_name ?? "").toLowerCase();
    const b = (t.destination_name ?? "").toLowerCase();
    return (a === dep && b === dest) || (t.is_bidirectional && a === dest && b === dep);
  });
  if (!match) return null;
  const price = args.timeOfDay === "night" ? match.night_price_gnf : match.day_price_gnf;
  if (!price) return null;
  return {
    price_gnf: price,
    troncon_id: match.id,
    verification_status: match.verification_status ?? "unverified",
    label: "Tarif local observé — Non officiel — À vérifier",
  };
}

/* ----------------------- Route observation (learning) --------------------- */

export interface RouteObservationInput {
  sourceModule: "ride" | "mission" | "repas" | "marche" | "manual";
  sourceId?: string | null;
  origin: LatLng;
  destination: LatLng;
  observedDistanceMeters?: number | null;
  observedDurationSeconds?: number | null;
  observedPolyline?: GeoJSON.LineString | null;
  providerUsed?: string | null;
  fallbackUsed?: boolean;
  notes?: string | null;
}

/**
 * Lightweight insert. Caller is responsible for guarding so this is only
 * called during an active trip/mission where collection is appropriate.
 */
export async function recordRouteObservation(args: RouteObservationInput): Promise<string | null> {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return null;
  const { data, error } = await (supabase as any)
    .from("map_route_observations")
    .insert({
      source_module: args.sourceModule,
      source_id: args.sourceId ?? null,
      driver_user_id: user.id,
      origin_lat: args.origin.lat,
      origin_lng: args.origin.lng,
      destination_lat: args.destination.lat,
      destination_lng: args.destination.lng,
      observed_distance_meters: args.observedDistanceMeters ?? null,
      observed_duration_seconds: args.observedDurationSeconds ?? null,
      observed_polyline_geojson: args.observedPolyline ?? null,
      provider_used: args.providerUsed ?? null,
      fallback_used: args.fallbackUsed ?? false,
      notes: args.notes ?? null,
    })
    .select("id")
    .single();
  if (error) return null;
  return (data as any)?.id ?? null;
}

export async function listRouteObservations(limit = 100) {
  const { data, error } = await (supabase as any)
    .from("map_route_observations")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(limit);
  if (error) throw error;
  return (data ?? []) as any[];
}

export async function updateRouteObservationStatus(
  id: string,
  patch: { status?: string; verification_status?: string; notes?: string | null },
) {
  const { error } = await (supabase as any)
    .from("map_route_observations").update(patch).eq("id", id);
  if (error) throw error;
}