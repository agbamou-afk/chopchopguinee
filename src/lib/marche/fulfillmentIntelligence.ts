import { supabase } from "@/integrations/supabase/client";

/**
 * Node 4 — Marché R3.5 fulfillment intelligence (internal / admin only).
 *
 * OBSERVE BEFORE PREDICT. Everything here is DESCRIPTIVE history:
 *   - percentiles are what already happened, never a promise;
 *   - there is no ETA, no prediction, no money, no dispatch effect;
 *   - buckets, confidence and freshness are SERVER truth — this module
 *     never recomputes them, it only labels and gates what the server sent.
 *
 * There is deliberately no customer-facing surface for this data.
 */

export type FulfillmentMetric =
  | "COMMIT_TO_MERCHANT_ACCEPTED"
  | "MERCHANT_ACCEPTED_TO_READY"
  | "COURIER_ENGAGED_TO_STORE_ARRIVAL"
  | "SHOPPING_START_TO_COMPLETE"
  | "PICKUP_TO_DELIVERED"
  | "COMMIT_TO_DELIVERED";

export type FulfillmentConfidence = "insufficient" | "low" | "medium" | "high";
export type FulfillmentFreshness = "none" | "fresh" | "aging" | "stale";

export interface FulfillmentCohortRow {
  metric_name: FulfillmentMetric;
  fulfillment_mode: string;
  distance_bucket: string;
  basket_bucket: string;
  sample_count: number;
  p50_seconds: number | null;
  p75_seconds: number | null;
  p90_seconds: number | null;
  min_duration_seconds: number | null;
  max_duration_seconds: number | null;
  first_observed_at: string | null;
  latest_observed_at: string | null;
  freshness: FulfillmentFreshness;
  confidence: FulfillmentConfidence;
  insufficient_data: boolean;
}

/** A cohort may be shown as history only when the server says it is not insufficient. */
export function isReportableCohort(row: Pick<FulfillmentCohortRow, "confidence" | "insufficient_data">): boolean {
  return row.insufficient_data === false && row.confidence !== "insufficient";
}

/**
 * Descriptive summary of an observed cohort. Returns null when the sample is
 * too thin to say anything honest — we never fall back to an invented number.
 */
export function describeCohort(row: FulfillmentCohortRow): {
  metric: FulfillmentMetric;
  observedMedianSeconds: number;
  observedP75Seconds: number | null;
  observedP90Seconds: number | null;
  sampleCount: number;
  confidence: FulfillmentConfidence;
  freshness: FulfillmentFreshness;
} | null {
  if (!isReportableCohort(row) || row.p50_seconds == null) return null;
  return {
    metric: row.metric_name,
    observedMedianSeconds: row.p50_seconds,
    observedP75Seconds: row.p75_seconds,
    observedP90Seconds: row.p90_seconds,
    sampleCount: row.sample_count,
    confidence: row.confidence,
    freshness: row.freshness,
  };
}

/** French, history-framed label. Never phrased as an estimate or a promise. */
export function cohortHistoryLabel(row: FulfillmentCohortRow): string {
  const d = describeCohort(row);
  if (!d) return "Historique insuffisant";
  const min = Math.round(d.observedMedianSeconds / 60);
  return `Médiane observée ${min} min (${d.sampleCount} observations)`;
}

/** Admin-only reads. These RPCs refuse non-admin callers server-side. */
export async function fetchFulfillmentCohorts(params: {
  metric?: FulfillmentMetric | null;
  mode?: string | null;
  distanceBucket?: string | null;
  basketBucket?: string | null;
  includeUnspecified?: boolean;
} = {}): Promise<FulfillmentCohortRow[]> {
  const { data, error } = await (supabase as any).rpc("marche_fulfillment_cohorts_admin", {
    p_metric_name: params.metric ?? null,
    p_fulfillment_mode: params.mode ?? null,
    p_distance_bucket: params.distanceBucket ?? null,
    p_basket_bucket: params.basketBucket ?? null,
    p_include_unspecified: params.includeUnspecified ?? false,
  });
  if (error) throw new Error(error.message);
  return (data ?? []) as FulfillmentCohortRow[];
}

export async function fetchFulfillmentProfile(orderId: string): Promise<Record<string, unknown> | null> {
  const { data, error } = await (supabase as any).rpc("marche_fulfillment_profile_admin", { p_order_id: orderId });
  if (error) throw new Error(error.message);
  return (data ?? null) as Record<string, unknown> | null;
}

export async function fetchFulfillmentTimeline(orderId: string): Promise<Record<string, unknown>[]> {
  const { data, error } = await (supabase as any).rpc("marche_fulfillment_events_admin", { p_order_id: orderId });
  if (error) throw new Error(error.message);
  return (data ?? []) as Record<string, unknown>[];
}
