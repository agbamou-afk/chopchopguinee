import { supabase } from "@/integrations/supabase/client";

/**
 * WONGO — district hub model (future-ready).
 *
 * Hubs are lightweight physical anchors per district: a vendor partner, a
 * restaurant, a fuel station, a kiosk, or — later — an internal CHOP site.
 * This module is groundwork: types + read helpers. No UI surface beyond a
 * single "Point CHOP proche · bientôt" hint on the driver dashboard.
 */

export type HubPartnerType =
  | "partner"
  | "restaurant"
  | "cafe"
  | "fuel_station"
  | "kiosk"
  | "boutique"
  | "pharmacy"
  | "chop_internal";

export type HubService =
  | "driver_rest"
  | "issue_reporting"
  | "parcel_relay"
  | "pickup_point"
  | "charging"
  | "onboarding"
  | "support";

export interface DistrictHub {
  id: string;
  district: string;
  name: string;
  partner_type: HubPartnerType;
  address: string | null;
  lat: number | null;
  lng: number | null;
  phone: string | null;
  available_services: HubService[];
  merchant_id: string | null;
  status: "active" | "paused" | "draft";
  created_at: string;
  updated_at: string;
}

export async function listHubsByDistrict(district: string): Promise<DistrictHub[]> {
  const { data, error } = await supabase
    .from("district_hubs")
    .select("*")
    .eq("district", district)
    .eq("status", "active")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return (data ?? []) as DistrictHub[];
}

export async function findNearestHub(
  district: string,
  service?: HubService,
): Promise<DistrictHub | null> {
  const hubs = await listHubsByDistrict(district);
  if (service) {
    const match = hubs.find((h) => h.available_services?.includes(service));
    return match ?? hubs[0] ?? null;
  }
  return hubs[0] ?? null;
}