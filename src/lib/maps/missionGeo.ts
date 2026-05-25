import type { LatLng } from "./geo";

export interface GeoEndpoints {
  pickup: LatLng | null;
  dropoff: LatLng | null;
}

type MissionLike = {
  pickup_lat?: number | null; pickup_lng?: number | null;
  dropoff_lat?: number | null; dropoff_lng?: number | null;
};

type RideLike = {
  pickup_lat?: number | null; pickup_lng?: number | null;
  dest_lat?: number | null; dest_lng?: number | null;
};

function asPoint(lat?: number | null, lng?: number | null): LatLng | null {
  return typeof lat === "number" && typeof lng === "number" ? { lat, lng } : null;
}

/** Normalize a mission row to {pickup, dropoff} LatLng pair. */
export function missionEndpoints(m: MissionLike): GeoEndpoints {
  return { pickup: asPoint(m.pickup_lat, m.pickup_lng), dropoff: asPoint(m.dropoff_lat, m.dropoff_lng) };
}

/** Normalize a ride row to {pickup, dropoff} LatLng pair. */
export function rideEndpoints(r: RideLike): GeoEndpoints {
  return { pickup: asPoint(r.pickup_lat, r.pickup_lng), dropoff: asPoint(r.dest_lat, r.dest_lng) };
}
