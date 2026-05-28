import { supabase } from "@/integrations/supabase/client";
import {
  type Mission,
  type MissionEvent,
  type MissionEventName,
  type MissionState,
  type ConfirmationMethod,
  MISSION_NEXT_STATE,
  missionStateToEvent,
} from "./types";
import { resolveDistrict } from "@/lib/districts";
import { findNearestHub } from "@/lib/districts/hubs";

/**
 * Lightweight mission ops. All writes also log a `mission_events` row so the
 * ActivityTimeline gets a uniform stream regardless of mission type.
 *
 * Compatibility note: this layer is additive — the legacy `rides` table and
 * its RPCs remain authoritative. Missions become the unified surface once
 * Repas/Marché checkouts opt in.
 */

export async function listCourierMissions(courierId: string): Promise<Mission[]> {
  const { data, error } = await supabase
    .from("missions")
    .select("*")
    .eq("courier_id", courierId)
    .order("created_at", { ascending: false })
    .limit(40);
  if (error) throw error;
  return (data ?? []) as Mission[];
}

export async function listCustomerMissions(customerId: string): Promise<Mission[]> {
  const { data, error } = await supabase
    .from("missions")
    .select("*")
    .eq("customer_id", customerId)
    .order("created_at", { ascending: false })
    .limit(40);
  if (error) throw error;
  return (data ?? []) as Mission[];
}

/**
 * Available (unassigned) missions visible to the current courier.
 * RLS already filters by capability; we additionally narrow by mission type
 * derived from the driver's capability list so the UI is calm.
 */
const CAPABILITY_TO_TYPE: Record<string, Mission["type"]> = {
  rides_moto: "ride",
  rides_toktok: "ride",
  repas_delivery: "food_delivery",
  marche_delivery: "marketplace_delivery",
  package_delivery: "package_delivery",
};

export async function listAvailableMissions(capabilities: string[]): Promise<Mission[]> {
  const types = Array.from(
    new Set(
      capabilities.map((c) => CAPABILITY_TO_TYPE[c]).filter((t): t is Mission["type"] => !!t),
    ),
  );
  if (types.length === 0) return [];
  const { data, error } = await supabase
    .from("missions")
    .select("*")
    .is("courier_id", null)
    .eq("state", "assigned")
    .in("type", types)
    .order("created_at", { ascending: false })
    .limit(20);
  if (error) throw error;
  return (data ?? []) as Mission[];
}

/** Courier claims an unassigned mission. */
export async function claimMission(missionId: string): Promise<Mission> {
  const { data, error } = await (supabase as any).rpc("mission_claim", { _mission_id: missionId });
  if (error) throw error;
  await logEvent(missionId, "accepted");
  await logEvent(missionId, "en_route_pickup");
  return (Array.isArray(data) ? data[0] : data) as Mission;
}

export async function listMissionEvents(missionId: string): Promise<MissionEvent[]> {
  const { data, error } = await supabase
    .from("mission_events")
    .select("*")
    .eq("mission_id", missionId)
    .order("created_at", { ascending: true });
  if (error) throw error;
  return (data ?? []) as MissionEvent[];
}

async function logEvent(
  missionId: string,
  event: MissionEventName,
  note?: string,
): Promise<void> {
  const { data: u } = await supabase.auth.getUser();
  const actorId = u.user?.id ?? null;
  await supabase.from("mission_events").insert({
    mission_id: missionId,
    event,
    actor_id: actorId,
    note: note ?? null,
  });
}

/**
 * Advance a mission to the next state in the courier flow.
 * Returns the updated mission row.
 */
export async function advanceMission(
  missionId: string,
  currentState: MissionState,
): Promise<Mission> {
  const next = MISSION_NEXT_STATE[currentState];
  if (!next) throw new Error("Aucune étape suivante");
  return setMissionState(missionId, next);
}

export async function setMissionState(
  missionId: string,
  state: MissionState,
): Promise<Mission> {
  const { data, error } = await (supabase as any).rpc("mission_set_state", {
    _mission_id: missionId,
    _state: state,
  });
  if (error) throw error;
  const ev = missionStateToEvent(state);
  if (ev) await logEvent(missionId, ev);
  return (Array.isArray(data) ? data[0] : data) as Mission;
}

export async function confirmPickup(
  missionId: string,
  method: ConfirmationMethod = "manual",
): Promise<Mission> {
  const { data, error } = await (supabase as any).rpc("mission_confirm_pickup", { _mission_id: missionId });
  if (error) throw error;
  await logEvent(missionId, "picked_up", `method:${method}`);
  return (Array.isArray(data) ? data[0] : data) as Mission;
}

export async function confirmDropoff(
  missionId: string,
  method: ConfirmationMethod = "manual",
): Promise<Mission> {
  const { data, error } = await (supabase as any).rpc("mission_confirm_dropoff", { _mission_id: missionId });
  if (error) throw error;
  await logEvent(missionId, "delivered", `method:${method}`);
  return (Array.isArray(data) ? data[0] : data) as Mission;
}

export async function reportIssue(missionId: string, reason: string): Promise<Mission> {
  // Best-effort district enrichment so support can locate the courier.
  let issue_district: string | null = null;
  let issue_hub_id: string | null = null;
  try {
    const { data: m } = await supabase
      .from("missions")
      .select("pickup_lat,pickup_lng,dropoff_lat,dropoff_lng,pickup_address,dropoff_address")
      .eq("id", missionId)
      .maybeSingle();
    if (m) {
      const d =
        resolveDistrict({
          point: m.pickup_lat != null && m.pickup_lng != null
            ? { lat: m.pickup_lat as number, lng: m.pickup_lng as number } : null,
          text: (m.pickup_address as string | null) ?? null,
        }) ??
        resolveDistrict({
          point: m.dropoff_lat != null && m.dropoff_lng != null
            ? { lat: m.dropoff_lat as number, lng: m.dropoff_lng as number } : null,
          text: (m.dropoff_address as string | null) ?? null,
        });
      if (d) {
        issue_district = d.name;
        try {
          const hub = await findNearestHub(d.name, "issue_reporting");
          issue_hub_id = hub?.id ?? null;
        } catch { /* hubs table optional */ }
      }
    }
  } catch { /* enrichment is best-effort */ }

  const { data, error } = await (supabase as any).rpc("mission_report_issue", {
    _mission_id: missionId,
    _reason: reason,
    _district: issue_district,
    _hub_id: issue_hub_id,
  });
  if (error) throw error;
  await logEvent(missionId, "issue", issue_district ? `${reason} · ${issue_district}` : reason);
  return (Array.isArray(data) ? data[0] : data) as Mission;
}

/**
 * Update the current driver's capabilities list.
 */
export async function updateDriverCapabilities(
  userId: string,
  capabilities: string[],
): Promise<void> {
  // Route through SECURITY DEFINER RPC: drivers can only toggle within the
  // capability set their admin already granted. `userId` is kept for API
  // compatibility but ignored server-side (RPC uses auth.uid()).
  void userId;
  const { error } = await (supabase as any).rpc("driver_set_capabilities", {
    _caps: capabilities,
  });
  if (error) throw error;
}

/**
 * Compatibility helper — create a mission from a confirmed delivery order.
 * Not wired into Repas/Marché checkout in this sprint; ready for the dispatch
 * sprint.
 */
export async function createMission(input: {
  type: Mission["type"];
  customer_id: string;
  merchant_id?: string | null;
  pickup_address?: string;
  pickup_lat?: number;
  pickup_lng?: number;
  dropoff_address?: string;
  dropoff_lat?: number;
  dropoff_lng?: number;
  payload_summary?: string;
  estimated_earning_gnf?: number;
  ref_food_order_id?: string;
  ref_market_order_id?: string;
  ref_ride_id?: string;
}): Promise<Mission> {
  const { data, error } = await supabase
    .from("missions")
    .insert({
      type: input.type,
      customer_id: input.customer_id,
      merchant_id: input.merchant_id ?? null,
      pickup_address: input.pickup_address ?? null,
      pickup_lat: input.pickup_lat ?? null,
      pickup_lng: input.pickup_lng ?? null,
      dropoff_address: input.dropoff_address ?? null,
      dropoff_lat: input.dropoff_lat ?? null,
      dropoff_lng: input.dropoff_lng ?? null,
      payload_summary: input.payload_summary ?? null,
      estimated_earning_gnf: input.estimated_earning_gnf ?? 0,
      ref_food_order_id: input.ref_food_order_id ?? null,
      ref_market_order_id: input.ref_market_order_id ?? null,
      ref_ride_id: input.ref_ride_id ?? null,
    })
    .select("*")
    .single();
  if (error) throw error;
  return data as Mission;
}