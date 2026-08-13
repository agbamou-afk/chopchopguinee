import { describe, it, expect } from "vitest";
import { rideModeLabel, rideServiceTitle, RIDE_MODE_SUBTITLE, RIDE_MODE_PRODUCT } from "@/lib/rides/rideModeLabel";
import { MISSION_KIND_LABEL } from "@/lib/wallet/labels";

/**
 * Node 2 / T7 section I: Taxi must never surface as Moto or as a raw
 * internal identifier. These are UI-only truths, proven statically.
 */
describe("Node 2 Taxi label truth", () => {
  it("names the `auto` mode Taxi everywhere the customer sees it", () => {
    expect(rideModeLabel("auto")).toBe("Taxi");
    expect(rideServiceTitle("auto")).toBe("Course Taxi");
  });

  it("never leaks the internal `auto` identifier or a Moto label", () => {
    for (const s of [rideModeLabel("auto"), rideServiceTitle("auto"), RIDE_MODE_SUBTITLE.auto]) {
      expect(s.toLowerCase()).not.toContain("auto");
      expect(s.toLowerCase()).not.toContain("moto");
    }
  });

  it("keeps Taxi distinct from Moto and Bonbonna", () => {
    expect(rideModeLabel("moto")).toBe("Moto");
    expect(rideModeLabel("toktok")).toBe("Bonbonna");
    expect(RIDE_MODE_PRODUCT.auto).toBeDefined();
  });

  it("labels a Taxi wallet earning as a Taxi course", () => {
    expect(MISSION_KIND_LABEL.taxi).toBe("Course Taxi");
  });
});
