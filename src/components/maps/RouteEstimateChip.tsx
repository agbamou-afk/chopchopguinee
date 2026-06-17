import { Route, AlertTriangle } from "lucide-react";
import { useServiceRouteEstimate } from "@/lib/maps/serviceRouting";
import type { ObservationSource } from "@/lib/maps/observationLifecycle";
import type { RouteMode } from "@/lib/maps/routing";

interface Props {
  origin: { lat: number; lng: number } | null;
  destination: { lat: number; lng: number } | null;
  mode?: RouteMode;
  /** Provide when this is an active assigned job to enable observation start. */
  activeJob?: { sourceModule: ObservationSource; sourceId: string; driverUserId: string } | null;
  /** Soft warning to render when coordinates are unverified. */
  locationWarning?: string | null;
  className?: string;
  compact?: boolean;
}

function fmtKm(m: number) {
  return m >= 1000 ? `${(m / 1000).toFixed(1)} km` : `${Math.round(m)} m`;
}
function fmtMin(s: number) {
  const m = Math.max(1, Math.round(s / 60));
  return m >= 60 ? `${Math.floor(m / 60)} h ${m % 60} min` : `${m} min`;
}

/**
 * Map Phase 2G.1 — Non-breaking route estimate chip.
 *
 * Customer-safe: never exposes raw observations or learning data — just
 * the distance/ETA plus an "Estimation approximative" hint when the
 * provider fell back. Hides itself silently if coords are missing or the
 * estimate could not be computed.
 */
export function RouteEstimateChip({
  origin, destination, mode = "moto", activeJob = null,
  locationWarning = null, className = "", compact = false,
}: Props) {
  const { estimate, loading } = useServiceRouteEstimate({
    origin, destination, mode, activeJob,
  });
  if (!origin || !destination) return null;
  if (loading && !estimate) {
    return (
      <div className={`text-[10px] uppercase tracking-wider text-muted-foreground ${className}`}>
        Estimation…
      </div>
    );
  }
  if (!estimate) {
    return (
      <div className={`text-[10px] uppercase tracking-wider text-muted-foreground ${className}`}>
        Trajet à confirmer
      </div>
    );
  }
  const approx = estimate.fallback_used;
  return (
    <div
      className={`inline-flex flex-wrap items-center gap-x-2 gap-y-1 ${
        compact ? "text-[11px]" : "text-xs"
      } text-foreground ${className}`}
    >
      <span className="inline-flex items-center gap-1 font-medium">
        <Route className="w-3.5 h-3.5 text-primary" />
        {fmtKm(estimate.distance_meters)} · {fmtMin(estimate.duration_seconds)}
      </span>
      {approx && (
        <span className="inline-flex items-center gap-1 text-[10px] uppercase tracking-wider text-muted-foreground">
          <AlertTriangle className="w-3 h-3" /> Estimation approximative
        </span>
      )}
      {locationWarning && (
        <span className="inline-flex items-center gap-1 text-[10px] uppercase tracking-wider text-muted-foreground">
          <AlertTriangle className="w-3 h-3" /> {locationWarning}
        </span>
      )}
    </div>
  );
}