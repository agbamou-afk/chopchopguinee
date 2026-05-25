import type { LatLng } from '../geo';

export type RouteMode = 'driving' | 'walking' | 'bicycling' | 'two_wheeler';

export interface RouteStep {
  instruction: string;
  distanceM: number;
  durationS: number;
  polyline: string;
  maneuver: string | null;
  /** Some providers (OSRM fallback) may omit this. Always guard before use. */
  startLocation: { lat: number; lng: number } | null;
  /** Some providers (OSRM fallback) may omit this. Always guard before use. */
  endLocation: { lat: number; lng: number } | null;
}

export interface NormalizedRoute {
  polyline: string;
  distanceM: number;
  durationS: number;
  /** Provider fallbacks may not return a viewport; derive from polyline when needed. */
  bbox: { northeast: LatLng; southwest: LatLng } | null;
  steps: RouteStep[];
  provider: 'google' | 'osrm' | 'graphhopper';
}

export interface EtaMatrixCell {
  status: string;
  distanceM: number | null;
  durationS: number | null;
}

export interface RouteRequest {
  origin: LatLng;
  destination: LatLng;
  mode?: RouteMode;
  waypoints?: LatLng[];
}

export interface RouteProvider {
  name: 'google' | 'osrm' | 'graphhopper';
  route(req: RouteRequest): Promise<NormalizedRoute>;
  eta(origins: LatLng[], destinations: LatLng[], mode?: RouteMode): Promise<EtaMatrixCell[][]>;
}