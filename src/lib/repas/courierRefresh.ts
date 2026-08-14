/**
 * Node 3 / R7 — courier canonical refresh path.
 *
 * After any Repas custody mutation (or any reconnect / visibility return /
 * realtime signal) the courier card must NOT keep rendering the stale mission
 * object it was handed. This helper is the single canonical refresh:
 *
 *   1. `repas_order_tracking(orderId)` — the server read model is consulted
 *      FIRST. It is the authoritative statement of order/mission/custody truth.
 *   2. the safe mission row is re-read with the R7 column projection.
 *   3. the courier's entitled earning is hydrated through `mission_earnings`.
 *
 * Realtime payloads are treated as a *signal only*; nothing here trusts them.
 */
import { supabase } from "@/integrations/supabase/client";
import { MISSION_SAFE_COLS } from "@/lib/missions/columns";
import { hydrateMissionEarnings } from "@/lib/missions/missions";
import type { Mission } from "@/lib/missions/types";
import { getRepasTracking, type RepasTracking } from "./tracking";

export interface RepasCourierRefresh {
  mission: Mission;
  tracking: RepasTracking | null;
}

/** True when this mission is a Repas delivery bound to a food order. */
export function isRepasCourierMission(
  m: Pick<Mission, "type" | "ref_food_order_id">,
): boolean {
  return m.type === "food_delivery" && !!m.ref_food_order_id;
}

/**
 * Canonical refresh for a Repas courier mission.
 * Returns `null` when nothing authoritative could be read (offline, revoked
 * access): callers keep their previous state rather than inventing one.
 */
export async function refreshRepasCourierMission(
  mission: Mission,
): Promise<RepasCourierRefresh | null> {
  let tracking: RepasTracking | null = null;
  if (isRepasCourierMission(mission)) {
    // Canonical server read model FIRST.
    tracking = await getRepasTracking(mission.ref_food_order_id as string).catch(() => null);
  }

  const { data, error } = await supabase
    .from("missions")
    .select(MISSION_SAFE_COLS)
    .eq("id", mission.id)
    .maybeSingle();
  if (error || !data) return null;

  const [fresh] = await hydrateMissionEarnings([data as unknown as Mission]);
  return { mission: fresh, tracking };
}

/**
 * A custody sheet must not stay logically open once canonical truth has moved
 * past its boundary (e.g. a second device completed the handoff).
 */
export function custodyPhaseStillValid(
  phase: "pickup" | "delivery" | null,
  state: Mission["state"],
): boolean {
  if (!phase) return false;
  return phase === "pickup" ? state === "arrived_pickup" : state === "arrived_dropoff";
}
