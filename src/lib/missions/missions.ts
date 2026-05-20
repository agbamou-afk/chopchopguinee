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
  const { data, error } = await supabase
    .from("missions")
    .update({ state })
    .eq("id", missionId)
    .select("*")
    .single();
  if (error) throw error;
  const ev = missionStateToEvent(state);
  if (ev) await logEvent(missionId, ev);
  return data as Mission;
}

export async function confirmPickup(
  missionId: string,
  method: ConfirmationMethod = "manual",
): Promise<Mission> {
  const { data: u } = await supabase.auth.getUser();
  const { data, error } = await supabase
    .from("missions")
    .update({
      state: "picked_up",
      pickup_confirmed_at: new Date().toISOString(),
      pickup_confirmed_by: u.user?.id ?? null,
    })
    .eq("id", missionId)
    .select("*")
    .single();
  if (error) throw error;
  await logEvent(missionId, "picked_up", `method:${method}`);
  return data as Mission;
}

export async function confirmDropoff(
  missionId: string,
  method: ConfirmationMethod = "manual",
): Promise<Mission> {
  const { data: u } = await supabase.auth.getUser();
  const { data, error } = await supabase
    .from("missions")
    .update({
      state: "delivered",
      dropoff_confirmed_at: new Date().toISOString(),
      dropoff_confirmed_by: u.user?.id ?? null,
    })
    .eq("id", missionId)
    .select("*")
    .single();
  if (error) throw error;
  await logEvent(missionId, "delivered", `method:${method}`);
  return data as Mission;
}

export async function reportIssue(missionId: string, reason: string): Promise<Mission> {
  const { data, error } = await supabase
    .from("missions")
    .update({ state: "failed", issue_reason: reason })
    .eq("id", missionId)
    .select("*")
    .single();
  if (error) throw error;
  await logEvent(missionId, "issue", reason);
  return data as Mission;
}

/**
 * Update the current driver's capabilities list.
 */
export async function updateDriverCapabilities(
  userId: string,
  capabilities: string[],
): Promise<void> {
  const { error } = await supabase
    .from("driver_profiles")
    .update({ capabilities })
    .eq("user_id", userId);
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