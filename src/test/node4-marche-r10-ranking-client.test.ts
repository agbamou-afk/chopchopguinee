import { describe, it, expect } from "vitest";
import { rankReasons, type RankEvidence } from "@/lib/marche/ranking";

/**
 * Node 4 — Marché R10 client law:
 * the server is the ONLY ranking authority. The client renders the reasons the
 * server authored, never its own thresholds, never an invented label.
 */
describe("R10 ranking client laws", () => {
  it("renders nothing when the server authored no reason", () => {
    expect(rankReasons(null)).toEqual([]);
    expect(rankReasons({} as RankEvidence)).toEqual([]);
    expect(rankReasons({ why_ranked: [] })).toEqual([]);
  });

  it("never invents a reason from raw component scores", () => {
    const ev: RankEvidence = {
      components: {
        price: { available: true, score: 0.99 },
        reputation: { available: true, score: 0.99 },
        distance: { available: true, score: 0.9, distance_m: 120 },
      },
      why_ranked: [],
    };
    expect(rankReasons(ev)).toEqual([]);
  });

  it("passes through server reason codes and labels unchanged", () => {
    const ev: RankEvidence = {
      why_ranked: [
        { code: "GOOD_VALUE", label: "Bon rapport qualité-prix" },
        { code: "NEARBY", label: "Proche de vous" },
      ],
    };
    expect(rankReasons(ev)).toEqual(ev.why_ranked);
  });

  it("shows at most two chips", () => {
    const ev: RankEvidence = {
      why_ranked: [
        { code: "GOOD_VALUE", label: "A" },
        { code: "WELL_RATED", label: "B" },
        { code: "NEARBY", label: "C" },
      ],
    };
    expect(rankReasons(ev)).toHaveLength(2);
  });

  it("drops malformed server entries instead of guessing", () => {
    const ev = {
      why_ranked: [
        { code: "", label: "x" },
        { code: "NEARBY" },
        null,
        { code: "WELL_RATED", label: "Très bien noté" },
      ],
    } as unknown as RankEvidence;
    expect(rankReasons(ev)).toEqual([{ code: "WELL_RATED", label: "Très bien noté" }]);
  });

  it("does not label a cold-start listing as bad", () => {
    expect(rankReasons({ cold_start: true, score_bps: null, why_ranked: [] })).toEqual([]);
  });
});
