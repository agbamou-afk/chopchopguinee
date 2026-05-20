export type MissionType =
  | "ride"
  | "food_delivery"
  | "marketplace_delivery"
  | "package_delivery";

export type MissionState =
  | "assigned"
  | "heading_to_pickup"
  | "arrived_pickup"
  | "picked_up"
  | "heading_to_dropoff"
  | "arrived_dropoff"
  | "delivered"
  | "failed";

export type MissionEventName =
  | "accepted"
  | "en_route_pickup"
  | "arrived_pickup"
  | "picked_up"
  | "en_route_dropoff"
  | "arrived_dropoff"
  | "delivered"
  | "issue";

export type ConfirmationMethod = "manual" | "qr" | "pin" | "photo" | "signature";

export interface Mission {
  id: string;
  type: MissionType;
  state: MissionState;
  courier_id: string | null;
  customer_id: string;
  merchant_id: string | null;
  pickup_address: string | null;
  pickup_lat: number | null;
  pickup_lng: number | null;
  dropoff_address: string | null;
  dropoff_lat: number | null;
  dropoff_lng: number | null;
  payload_summary: string | null;
  estimated_earning_gnf: number;
  estimated_distance_m: number | null;
  estimated_duration_s: number | null;
  ref_ride_id: string | null;
  ref_food_order_id: string | null;
  ref_market_order_id: string | null;
  pickup_confirmed_at: string | null;
  pickup_confirmed_by: string | null;
  dropoff_confirmed_at: string | null;
  dropoff_confirmed_by: string | null;
  issue_reason: string | null;
  created_at: string;
  updated_at: string;
}

export interface MissionEvent {
  id: string;
  mission_id: string;
  event: MissionEventName;
  actor_id: string | null;
  note: string | null;
  created_at: string;
}

export const MISSION_TYPE_LABEL: Record<MissionType, string> = {
  ride: "Course",
  food_delivery: "Livraison Repas",
  marketplace_delivery: "Livraison Marché",
  package_delivery: "Envoyer un colis",
};

export const MISSION_TYPE_SHORT: Record<MissionType, string> = {
  ride: "Course",
  food_delivery: "Repas",
  marketplace_delivery: "Marché",
  package_delivery: "Colis",
};

export const MISSION_STATE_LABEL: Record<MissionState, string> = {
  assigned: "Mission attribuée",
  heading_to_pickup: "En route vers le retrait",
  arrived_pickup: "Arrivé au point de retrait",
  picked_up: "Colis récupéré",
  heading_to_dropoff: "En route vers le client",
  arrived_dropoff: "Arrivé chez le client",
  delivered: "Livré",
  failed: "Problème signalé",
};

/** Courier-facing CTA label for advancing from a given state. */
export const MISSION_NEXT_LABEL: Partial<Record<MissionState, string>> = {
  assigned: "Je pars vers le retrait",
  heading_to_pickup: "Je suis arrivé",
  arrived_pickup: "Confirmer le retrait",
  picked_up: "En route vers le client",
  heading_to_dropoff: "Je suis arrivé",
  arrived_dropoff: "Confirmer la livraison",
};

/** State machine — next state after the courier taps the CTA. */
export const MISSION_NEXT_STATE: Partial<Record<MissionState, MissionState>> = {
  assigned: "heading_to_pickup",
  heading_to_pickup: "arrived_pickup",
  arrived_pickup: "picked_up",
  picked_up: "heading_to_dropoff",
  heading_to_dropoff: "arrived_dropoff",
  arrived_dropoff: "delivered",
};

export const MISSION_EVENT_LABEL: Record<MissionEventName, string> = {
  accepted: "Mission acceptée",
  en_route_pickup: "Coursier en route",
  arrived_pickup: "Arrivé au retrait",
  picked_up: "Colis récupéré",
  en_route_dropoff: "En route vers vous",
  arrived_dropoff: "Coursier arrivé",
  delivered: "Livré",
  issue: "Problème signalé",
};

export function isTerminalState(s: MissionState): boolean {
  return s === "delivered" || s === "failed";
}

export function missionStateToEvent(s: MissionState): MissionEventName | null {
  switch (s) {
    case "heading_to_pickup": return "en_route_pickup";
    case "arrived_pickup": return "arrived_pickup";
    case "picked_up": return "picked_up";
    case "heading_to_dropoff": return "en_route_dropoff";
    case "arrived_dropoff": return "arrived_dropoff";
    case "delivered": return "delivered";
    case "failed": return "issue";
    default: return null;
  }
}