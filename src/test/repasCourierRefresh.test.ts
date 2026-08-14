import { describe, it, expect, vi, beforeEach } from "vitest";

const calls: string[] = [];

vi.mock("@/integrations/supabase/client", () => {
  const missionRow = {
    id: "m1",
    type: "food_delivery",
    state: "picked_up",
    courier_id: "c1",
    ref_food_order_id: "o1",
  };
  return {
    supabase: {
      rpc: (name: string) => {
        calls.push(`rpc:${name}`);
        if (name === "repas_order_tracking") {
          return Promise.resolve({ data: { order_id: "o1", viewer_role: "courier", state: "out_for_delivery" }, error: null });
        }
        if (name === "mission_earnings") return Promise.resolve({ data: { m1: 7000 }, error: null });
        return Promise.resolve({ data: null, error: null });
      },
      from: () => ({
        select: (cols: string) => {
          calls.push(`select:${cols.includes("estimated_earning_gnf") ? "UNSAFE" : "safe"}`);
          return {
            eq: () => ({ maybeSingle: () => Promise.resolve({ data: missionRow, error: null }) }),
          };
        },
      }),
    },
  };
});

import { refreshRepasCourierMission, isRepasCourierMission, custodyPhaseStillValid } from "@/lib/repas/courierRefresh";

describe("R7 courier canonical refresh", () => {
  beforeEach(() => { calls.length = 0; });

  it("only treats food_delivery missions bound to an order as Repas", () => {
    expect(isRepasCourierMission({ type: "food_delivery", ref_food_order_id: "o1" } as never)).toBe(true);
    expect(isRepasCourierMission({ type: "food_delivery", ref_food_order_id: null } as never)).toBe(false);
    expect(isRepasCourierMission({ type: "ride", ref_food_order_id: "o1" } as never)).toBe(false);
  });

  it("calls canonical tracking BEFORE re-reading the mission row", async () => {
    await refreshRepasCourierMission({ id: "m1", type: "food_delivery", ref_food_order_id: "o1" } as never);
    const trackIdx = calls.indexOf("rpc:repas_order_tracking");
    const selIdx = calls.findIndex((c) => c.startsWith("select:"));
    expect(trackIdx).toBeGreaterThanOrEqual(0);
    expect(selIdx).toBeGreaterThan(trackIdx);
  });

  it("never selects the private earning column and hydrates it via the RPC", async () => {
    const res = await refreshRepasCourierMission({ id: "m1", type: "food_delivery", ref_food_order_id: "o1" } as never);
    expect(calls).not.toContain("select:UNSAFE");
    expect(calls).toContain("rpc:mission_earnings");
    expect(res?.mission.estimated_earning_gnf).toBe(7000);
    expect(res?.tracking?.state).toBe("out_for_delivery");
  });

  it("invalidates a custody phase once canonical state moved past it", () => {
    expect(custodyPhaseStillValid("pickup", "arrived_pickup" as never)).toBe(true);
    expect(custodyPhaseStillValid("pickup", "picked_up" as never)).toBe(false);
    expect(custodyPhaseStillValid("delivery", "arrived_dropoff" as never)).toBe(true);
    expect(custodyPhaseStillValid("delivery", "delivered" as never)).toBe(false);
    expect(custodyPhaseStillValid(null, "arrived_pickup" as never)).toBe(false);
  });
});
