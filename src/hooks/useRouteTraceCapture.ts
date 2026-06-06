import { useEffect, useRef, useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { haversineMeters, type LatLng } from "@/lib/maps/geo";

type Phase = "to_pickup" | "to_destination";

interface Options {
  rideId: string | null | undefined;
  /** Driver-side ride phase; the hook only captures during active phases. */
  phase: Phase | null;
  enabled?: boolean;
  /** Minimum interval between captured points in ms. */
  minIntervalMs?: number;
  /** Optional hash of the planned route (so we can correlate later). */
  plannedRouteHash?: string | null;
  /** Planned route distance/duration if available (for off-route detection). */
  plannedRoute?: { distanceM?: number; durationS?: number } | null;
  /** Polyline points of the planned route, for deviation detection. */
  plannedPath?: LatLng[] | null;
  /** Meters away from planned path that counts as a deviation. */
  deviationThresholdM?: number;
  provider?: string;
}

/**
 * Route Learning v0 — driver-side trace capture.
 *
 * Buffers geolocation samples and persists them to `driver_route_traces`
 * while the driver is on an active assigned ride. Strictly opt-in:
 * does nothing without `rideId`, `phase`, and an authenticated driver.
 *
 * Returned counters power admin honest collection status; we deliberately
 * do NOT expose traces to customers.
 */
export function useRouteTraceCapture(opts: Options) {
  const {
    rideId,
    phase,
    enabled = true,
    minIntervalMs = 5000,
    plannedRouteHash,
    plannedRoute,
    plannedPath,
    deviationThresholdM = 80,
    provider,
  } = opts;

  const { user } = useAuth();
  const [pointCount, setPointCount] = useState(0);
  const [actualDistanceM, setActualDistanceM] = useState(0);
  const [deviationCount, setDeviationCount] = useState(0);
  const startedAtRef = useRef<number | null>(null);
  const lastSentRef = useRef(0);
  const lastPosRef = useRef<LatLng | null>(null);
  const watchIdRef = useRef<number | null>(null);
  const wasOffRouteRef = useRef(false);

  const active = !!(enabled && user && rideId && phase &&
    typeof navigator !== "undefined" && "geolocation" in navigator);

  useEffect(() => {
    if (!active) return;
    if (startedAtRef.current == null) startedAtRef.current = Date.now();

    const onPos = async (pos: GeolocationPosition) => {
      if (document.visibilityState === "hidden") return;
      const now = Date.now();
      if (now - lastSentRef.current < minIntervalMs) return;
      lastSentRef.current = now;

      const { latitude, longitude, accuracy, heading, speed } = pos.coords;
      const here: LatLng = { lat: latitude, lng: longitude };

      // Accumulate ground-truth distance locally.
      if (lastPosRef.current) {
        const d = haversineMeters(lastPosRef.current, here);
        if (d < 500) setActualDistanceM((m) => m + d); // ignore GPS jumps > 500m
      }
      lastPosRef.current = here;

      // Lightweight off-route detection (closest planned vertex).
      if (plannedPath && plannedPath.length > 1) {
        let minD = Infinity;
        for (const p of plannedPath) {
          const d = haversineMeters(here, p);
          if (d < minD) minD = d;
        }
        const off = minD > deviationThresholdM;
        if (off && !wasOffRouteRef.current) setDeviationCount((c) => c + 1);
        wasOffRouteRef.current = off;
      }

      try {
        const { error } = await supabase.from("driver_route_traces").insert({
          ride_id: rideId!,
          driver_id: user!.id,
          phase: phase!,
          lat: latitude,
          lng: longitude,
          accuracy_m: accuracy ?? null,
          heading: heading ?? null,
          speed_mps: speed ?? null,
          planned_route_hash: plannedRouteHash ?? null,
          provider: provider ?? null,
        });
        if (!error) setPointCount((n) => n + 1);
      } catch {
        // Never block the ride on telemetry failures.
      }
    };

    watchIdRef.current = navigator.geolocation.watchPosition(
      onPos,
      () => {},
      { enableHighAccuracy: true, maximumAge: 4000, timeout: 15000 },
    );
    return () => {
      if (watchIdRef.current !== null) {
        navigator.geolocation.clearWatch(watchIdRef.current);
        watchIdRef.current = null;
      }
    };
  }, [active, rideId, phase, user?.id, minIntervalMs, plannedRouteHash, provider,
      plannedPath, deviationThresholdM]);

  /**
   * Persist a planned-vs-actual summary for the ride. Safe to call multiple
   * times; failures are swallowed so they never block ride completion.
   */
  const finalize = useCallback(async (extra?: {
    startDistrict?: string | null;
    endDistrict?: string | null;
    timeWindow?: string | null;
  }) => {
    if (!user || !rideId) return;
    const startedAt = startedAtRef.current ?? Date.now();
    const durationS = Math.max(1, Math.round((Date.now() - startedAt) / 1000));
    const avgKmh = actualDistanceM > 0
      ? Number(((actualDistanceM / durationS) * 3.6).toFixed(2))
      : null;
    try {
      await supabase.from("ride_route_summaries").upsert({
        ride_id: rideId,
        driver_id: user.id,
        planned_route_distance_m: plannedRoute?.distanceM ?? null,
        planned_route_duration_s: plannedRoute?.durationS ?? null,
        actual_route_distance_m: Math.round(actualDistanceM) || null,
        actual_route_duration_s: durationS,
        deviation_count: deviationCount,
        average_speed_kmh: avgKmh,
        point_count: pointCount,
        start_district: extra?.startDistrict ?? null,
        end_district: extra?.endDistrict ?? null,
        time_window: extra?.timeWindow ?? null,
        route_confidence: pointCount >= 10 ? 0.5 : 0.2,
        metadata: { source: "route_learning_v0", provider: provider ?? null },
      }, { onConflict: "ride_id" });
    } catch {
      // Telemetry only — never block ride completion.
    }
  }, [user?.id, rideId, actualDistanceM, deviationCount, pointCount, plannedRoute, provider]);

  return { pointCount, actualDistanceM, deviationCount, finalize, active };
}