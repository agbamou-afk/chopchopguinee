import { describe, it, expect } from "vitest";
import {
  isReportableCohort,
  describeCohort,
  cohortHistoryLabel,
  type FulfillmentCohortRow,
} from "@/lib/marche/fulfillmentIntelligence";

const row = (over: Partial<FulfillmentCohortRow> = {}): FulfillmentCohortRow => ({
  metric_name: "PICKUP_TO_DELIVERED",
  fulfillment_mode: "delivery",
  distance_bucket: "1-3km",
  basket_bucket: "single",
  sample_count: 10,
  p50_seconds: 550,
  p75_seconds: 775,
  p90_seconds: 910,
  min_duration_seconds: 100,
  max_duration_seconds: 1000,
  first_observed_at: "2026-08-16T00:00:00Z",
  latest_observed_at: "2026-08-16T01:00:00Z",
  freshness: "fresh",
  confidence: "medium",
  insufficient_data: false,
  ...over,
});

describe("Node4 R3.5 — descriptive history only", () => {
  it("surfaces the server percentiles verbatim", () => {
    const d = describeCohort(row())!;
    expect(d.observedMedianSeconds).toBe(550);
    expect(d.observedP75Seconds).toBe(775);
    expect(d.observedP90Seconds).toBe(910);
  });

  it("never emits an ETA or prediction field", () => {
    const keys = Object.keys(describeCohort(row())!).join(",").toLowerCase();
    expect(keys).not.toMatch(/eta|predict|estimate|forecast|promise/);
  });

  it("never emits money", () => {
    const keys = Object.keys(describeCohort(row())!).join(",").toLowerCase();
    expect(keys).not.toMatch(/gnf|price|fee|payout|amount/);
  });

  it("labels history, not an estimate", () => {
    expect(cohortHistoryLabel(row())).toMatch(/observ/i);
    expect(cohortHistoryLabel(row())).not.toMatch(/arriv|livr.*dans|estim/i);
  });
});

describe("Node4 R3.5 — insufficient data is honest", () => {
  it("suppresses a cohort the server flagged insufficient", () => {
    expect(describeCohort(row({ insufficient_data: true, confidence: "insufficient", sample_count: 2 }))).toBeNull();
  });

  it("suppresses a cohort with insufficient confidence even if the flag is off", () => {
    expect(isReportableCohort({ confidence: "insufficient", insufficient_data: false })).toBe(false);
  });

  it("suppresses a cohort with no median rather than inventing one", () => {
    expect(describeCohort(row({ p50_seconds: null }))).toBeNull();
  });

  it("says so in the label instead of showing a number", () => {
    expect(cohortHistoryLabel(row({ insufficient_data: true, confidence: "insufficient" }))).toBe(
      "Historique insuffisant",
    );
  });

  it("still reports low/aging cohorts, which are honest history", () => {
    expect(isReportableCohort({ confidence: "low", insufficient_data: false })).toBe(true);
  });
});
