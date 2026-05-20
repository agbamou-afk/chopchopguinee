import type { Mission, MissionType } from "./types";

/**
 * Local-only demo missions used by the Driver Demo launcher. These NEVER
 * touch the database — they exist purely in component state so the demo
 * driver can showcase the full mission lifecycle (ride / repas / marché /
 * colis) without polluting live data or affecting real users.
 */

export interface DemoMissionTemplate {
  type: MissionType;
  pickup_address: string;
  dropoff_address: string;
  payload_summary: string;
  estimated_earning_gnf: number;
  estimated_distance_m: number;
  estimated_duration_s: number;
}

export const DEMO_MISSION_TEMPLATES: Record<MissionType, DemoMissionTemplate> = {
  ride: {
    type: "ride",
    pickup_address: "Kaloum · Avenue de la République",
    dropoff_address: "Ratoma · Cité des Nations",
    payload_summary: "1 passager · Moto",
    estimated_earning_gnf: 35_000,
    estimated_distance_m: 9_200,
    estimated_duration_s: 22 * 60,
  },
  food_delivery: {
    type: "food_delivery",
    pickup_address: "Chez Mama Fatoumata · Kipé",
    dropoff_address: "Résidence client · Ratoma",
    payload_summary: "2 plats · CHOPPay · Paiement réglé",
    estimated_earning_gnf: 18_000,
    estimated_distance_m: 4_100,
    estimated_duration_s: 14 * 60,
  },
  marketplace_delivery: {
    type: "marketplace_delivery",
    pickup_address: "Boutique Diallo · Madina",
    dropoff_address: "Client · Dixinn",
    payload_summary: "Téléphone + accessoire · CHOPPay",
    estimated_earning_gnf: 22_000,
    estimated_distance_m: 5_600,
    estimated_duration_s: 18 * 60,
  },
  package_delivery: {
    type: "package_delivery",
    pickup_address: "Matoto · Marché Niger",
    dropoff_address: "Kaloum · Boulbinet",
    payload_summary: "Petit colis · à remettre en main propre",
    estimated_earning_gnf: 28_000,
    estimated_distance_m: 12_400,
    estimated_duration_s: 30 * 60,
  },
};

/** Build an in-memory Mission row for the demo launcher. */
export function buildDemoMission(type: MissionType): Mission {
  const t = DEMO_MISSION_TEMPLATES[type];
  const now = new Date().toISOString();
  return {
    id: `demo-${type}-${Date.now()}`,
    type: t.type,
    state: "assigned",
    courier_id: null,
    customer_id: "demo-customer",
    merchant_id: null,
    pickup_address: t.pickup_address,
    pickup_lat: null,
    pickup_lng: null,
    dropoff_address: t.dropoff_address,
    dropoff_lat: null,
    dropoff_lng: null,
    payload_summary: t.payload_summary,
    estimated_earning_gnf: t.estimated_earning_gnf,
    estimated_distance_m: t.estimated_distance_m,
    estimated_duration_s: t.estimated_duration_s,
    ref_ride_id: null,
    ref_food_order_id: null,
    ref_market_order_id: null,
    pickup_confirmed_at: null,
    pickup_confirmed_by: null,
    dropoff_confirmed_at: null,
    dropoff_confirmed_by: null,
    issue_reason: null,
    created_at: now,
    updated_at: now,
  };
}