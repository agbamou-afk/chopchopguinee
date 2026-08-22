import { bbox, haversineMeters, type LatLng } from "@/lib/maps/geo";

/** Which endpoint a map interaction should write to. */
export type EndpointKey = "pickup" | "destination";

/**
 * Neutral label used when a coordinate is picked manually on the map and
 * reverse geocoding is unavailable. We never erase a valid coordinate just
 * because the geocoder failed.
 */
export const MANUAL_POINT_LABEL = "Point sélectionné";

/**
 * Two Conakry endpoints closer than this are treated as the same spot —
 * a courier mission needs a real trip, not a 5 m hop.
 */
export const SAME_POINT_MIN_METERS = 30;

export const SAME_POINT_MESSAGE =
  "Le retrait et la destination sont au même endroit. Choisissez deux points différents.";

/** Conakry fallback centre (matches maps-config default). */
export const CONAKRY_CENTER: LatLng = { lat: 9.6412, lng: -13.5784 };

/**
 * ~11 cm precision. Enough for doorway-level Conakry pickup/delivery while
 * keeping payloads stable across map drags.
 */
export function roundCoord(n: number): number {
  return Math.round(n * 1e6) / 1e6;
}

export function isSamePoint(a: LatLng | null, b: LatLng | null): boolean {
  if (!a || !b) return false;
  return haversineMeters(a, b) < SAME_POINT_MIN_METERS;
}

/** Bounds to fit, or null when there is nothing (or only one point) to fit. */
export function routeFitBbox(
  pickup: LatLng | null,
  destination: LatLng | null,
): [number, number, number, number] | null {
  if (!pickup || !destination) return null;
  return bbox([pickup, destination]);
}

/** Centre used when only one (or no) point exists. */
export function singleFocus(pickup: LatLng | null, destination: LatLng | null): LatLng {
  return pickup ?? destination ?? CONAKRY_CENTER;
}

/** Step 1 can advance only with two distinct, valid coordinates. */
export function canAdvanceItinerary(
  pickup: LatLng | null,
  destination: LatLng | null,
): boolean {
  if (!pickup || !destination) return false;
  return !isSamePoint(pickup, destination);
}
