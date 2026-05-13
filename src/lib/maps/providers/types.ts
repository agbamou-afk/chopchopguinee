import type { LatLng } from '../geo';

export type RouteMode = 'driving' | 'walking' | 'bicycling' | 'two_wheeler';

export interface RouteStep {
  instruction: string;
  distanceM: number;
  durationS: number;
  polyline: string;
  maneuver: string | null;
  startLocation: { lat: number; lng: number };
  endLocation: { lat: number; lng: number };
}

export interface NormalizedRoute {
  polyline: string;
  distanceM: number;
  durationS: number;
  bbox: { northeast: LatLng; southwest: LatLng };
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