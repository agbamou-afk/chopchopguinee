import { useEffect, useState } from "react";
import { getRouteEstimate, type RouteEstimate, type RouteMode } from "./routing";
import { districtFor } from "./zones";
import type { LatLng } from "./geo";
import { startObservationIfEligible, type ObservationSource } from "./observationLifecycle";

/**
 * Map Phase 2G — Service-flow route estimate wrapper.
 *
 * Wraps `getRouteEstimate` and, when given an active job context with a
 * driver assignment, opportunistically starts a route observation if the
 * provider fell back. Observation insert is fire-and-forget and never
 * affects the returned estimate or the calling flow.
 */
export async function getEstimateForActiveJob(args: {
  origin: LatLng;
  destination: LatLng;
  mode?: RouteMode;
  activeJob?: {
    sourceModule: ObservationSource;
    sourceId: string;
    driverUserId: string;
  } | null;
}): Promise<RouteEstimate> {
  const est = await getRouteEstimate({
    origin: args.origin,
    destination: args.destination,
    mode: args.mode ?? "moto",
  });
  if (args.activeJob && est.fallback_used) {
    void startObservationIfEligible({
      sourceModule: args.activeJob.sourceModule,
      sourceId: args.activeJob.sourceId,
      driverUserId: args.activeJob.driverUserId,
      origin: args.origin,
      destination: args.destination,
      providerUsed: est.provider,
      fallbackUsed: true,
    });
  }
  return est;
}

/** React hook for service flows. Returns null while loading or when coords missing. */
export function useServiceRouteEstimate(input: {
  origin: LatLng | null;
  destination: LatLng | null;
  mode?: RouteMode;
  activeJob?: { sourceModule: ObservationSource; sourceId: string; driverUserId: string } | null;
  enabled?: boolean;
}): { estimate: RouteEstimate | null; loading: boolean } {
  const { origin, destination, mode = "moto", activeJob, enabled = true } = input;
  const [estimate, setEstimate] = useState<RouteEstimate | null>(null);
  const [loading, setLoading] = useState(false);
  useEffect(() => {
    if (!enabled || !origin || !destination) return;
    let cancelled = false;
    setLoading(true);
    getEstimateForActiveJob({ origin, destination, mode, activeJob: activeJob ?? null })
      .then((e) => { if (!cancelled) setEstimate(e); })
      .catch(() => { if (!cancelled) setEstimate(null); })
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [enabled, origin?.lat, origin?.lng, destination?.lat, destination?.lng, mode,
      activeJob?.sourceModule, activeJob?.sourceId, activeJob?.driverUserId]);
  return { estimate, loading };
}

/** Lightweight origin/destination zone labels for internal display. */
export function zoneContext(origin: LatLng | null, destination: LatLng | null): {
  origin_zone: string | null;
  destination_zone: string | null;
  out_of_zone: boolean;
  label: string;
} {
  const o = origin ? districtFor(origin) : null;
  const d = destination ? districtFor(destination) : null;
  const out_of_zone = !!(origin && destination) && (!o || !d);
  const label = out_of_zone
    ? "Hors zone — À confirmer"
    : o && d ? `${o} → ${d}` : "Zone à confirmer";
  return { origin_zone: o, destination_zone: d, out_of_zone, label };
}