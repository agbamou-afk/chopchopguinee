import { supabase } from "@/integrations/supabase/client";

/**
 * Map Phase 2G — Route observation lifecycle helpers.
 *
 * Idempotent start + finalize keyed on (source_module, source_id).
 * Observations remain LEARNING data only:
 *   - admin-readable
 *   - never customer-visible
 *   - never auto-trusted
 *   - never used for pricing
 *
 * All functions are fire-and-forget — they must never throw to a caller in
 * a ride/mission lifecycle path. Errors are swallowed silently.
 */

export type ObservationSource = "ride" | "mission" | "repas" | "marche";

export interface StartIfEligibleInput {
  sourceModule: ObservationSource;
  sourceId: string;
  driverUserId: string;
  origin: { lat: number; lng: number };
  destination: { lat: number; lng: number };
  providerUsed?: string | null;
  fallbackUsed?: boolean;
}

async function findExisting(sourceModule: ObservationSource, sourceId: string): Promise<string | null> {
  try {
    const { data } = await (supabase as any)
      .from("map_route_observations")
      .select("id")
      .eq("source_module", sourceModule)
      .eq("source_id", sourceId)
      .maybeSingle();
    return data?.id ?? null;
  } catch {
    return null;
  }
}

/**
 * Insert a route observation only when:
 *   - none exists yet for this source
 *   - fallback was used OR no provider polyline (caller's judgement)
 *   - origin/destination both valid
 *   - driver is actively assigned (caller responsibility)
 */
export async function startObservationIfEligible(input: StartIfEligibleInput): Promise<string | null> {
  try {
    if (!Number.isFinite(input.origin.lat) || !Number.isFinite(input.origin.lng)) return null;
    if (!Number.isFinite(input.destination.lat) || !Number.isFinite(input.destination.lng)) return null;
    const existing = await findExisting(input.sourceModule, input.sourceId);
    if (existing) return existing;
    const { data, error } = await (supabase as any)
      .from("map_route_observations")
      .insert({
        source_module: input.sourceModule,
        source_id: input.sourceId,
        driver_user_id: input.driverUserId,
        origin_lat: input.origin.lat,
        origin_lng: input.origin.lng,
        destination_lat: input.destination.lat,
        destination_lng: input.destination.lng,
        provider_used: input.providerUsed ?? "fallback",
        fallback_used: input.fallbackUsed ?? true,
        confidence_score: 35,
        verification_status: "submitted",
        status: "recorded",
      })
      .select("id")
      .maybeSingle();
    if (error || !data) return null;
    return data.id;
  } catch {
    return null;
  }
}

export interface FinalizeInput {
  durationSeconds?: number | null;
  distanceMeters?: number | null;
  simplifiedPolylineGeoJson?: unknown;
  /** Pass true for cancelled-after-movement / cancelled-after-pickup. */
  needsReview?: boolean;
}

/**
 * Update the observation for (source_module, source_id) with terminal data.
 * Safe to call when no observation exists — silently no-ops.
 */
export async function finalizeObservationForSource(
  sourceModule: ObservationSource,
  sourceId: string,
  result: FinalizeInput = {},
): Promise<void> {
  try {
    const id = await findExisting(sourceModule, sourceId);
    if (!id) return;
    await (supabase as any)
      .from("map_route_observations")
      .update({
        observed_duration_seconds: result.durationSeconds ?? null,
        observed_distance_meters: result.distanceMeters ?? null,
        simplified_polyline_geojson: result.simplifiedPolylineGeoJson ?? null,
        status: "recorded",
        verification_status: result.needsReview ? "needs_review" : "submitted",
      })
      .eq("id", id);
  } catch {
    /* fire-and-forget */
  }
}