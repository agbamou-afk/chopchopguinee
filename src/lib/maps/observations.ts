import { supabase } from "@/integrations/supabase/client";

/**
 * Map Phase 2F — route observation hooks.
 *
 * Observations are LEARNING data only:
 *   - admin-readable, never customer-visible
 *   - never auto-trusted
 *   - never used for pricing
 *
 * Called by ride/mission lifecycle when fallback was used or the provider
 * polyline is missing, so we can compare predicted vs. real durations later.
 */
export interface StartObservationInput {
  sourceModule: "rides" | "missions";
  sourceId: string;
  driverUserId: string;
  origin: { lat: number; lng: number };
  destination: { lat: number; lng: number };
  providerUsed?: string | null;
  fallbackUsed?: boolean;
}

export async function startRouteObservation(input: StartObservationInput): Promise<string | null> {
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
}

export async function finalizeRouteObservation(
  observationId: string,
  result: {
    durationSeconds?: number | null;
    distanceMeters?: number | null;
    simplifiedPolylineGeoJson?: unknown;
  },
): Promise<void> {
  await (supabase as any)
    .from("map_route_observations")
    .update({
      observed_duration_seconds: result.durationSeconds ?? null,
      observed_distance_meters: result.distanceMeters ?? null,
      simplified_polyline_geojson: result.simplifiedPolylineGeoJson ?? null,
      status: "recorded",
    })
    .eq("id", observationId);
}
