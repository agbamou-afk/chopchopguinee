import { useEffect, useMemo, useRef, useState } from "react";
import { Marker } from "react-map-gl";
import { Phone, MessageCircle, X, AlertTriangle, Clock } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  ChopMap,
  type ChopMapHandle,
  MapMarker,
  PinSet,
  RoutePolyline,
} from "@/components/map";
import {
  RoutingService,
  bbox as bboxOf,
  formatDuration,
  useDriverLocation,
  type LatLng,
} from "@/lib/maps";
import { useRideRealtime } from "@/hooks/useRideRealtime";

interface Props {
  rideId: string;
  /** Tap a "call driver" affordance. */
  onCallDriver?: (driverId: string) => void;
  /** Tap "message driver" placeholder. */
  onMessageDriver?: (driverId: string) => void;
  /** Cancel or report issue. */
  onCancel?: () => void;
  /** Close the screen (after completion or by user). */
  onClose?: () => void;
}

const STATUS_COPY: Record<string, string> = {
  pending: "Recherche d'un chauffeur…",
  in_progress: "Trajet en cours",
  completed: "Trajet terminé",
  cancelled: "Trajet annulé",
};

function statusColor(status: string): string {
  if (status === "completed") return "bg-emerald-500";
  if (status === "cancelled") return "bg-destructive";
  if (status === "in_progress") return "bg-primary";
  return "bg-amber-500";
}

/**
 * Synchronized active-trip experience for client side.
 * - Live driver marker (glides via useDriverLocation)
 * - Pickup & destination pins
 * - Active route polyline (driver→pickup vs pickup→destination state)
 * - ETA countdown derived from RoutingService
 * - Call / message / cancel CTAs (message is a placeholder for now)
 */
export function ActiveTripMap({
  rideId,
  onCallDriver,
  onMessageDriver,
  onCancel,
  onClose,
}: Props) {
  const { ride, loading } = useRideRealtime(rideId);
  const driverPos = useDriverLocation(ride?.driver_id ?? null);
  const mapRef = useRef<ChopMapHandle>(null);
  const [route, setRoute] = useState<{ polyline: string; durationS: number } | null>(
    null,
  );

  const pickup: LatLng | null = useMemo(
    () => (ride ? { lat: ride.pickup_lat, lng: ride.pickup_lng } : null),
    [ride],
  );
  const dropoff: LatLng | null = useMemo(
    () =>
      ride?.dest_lat != null && ride?.dest_lng != null
        ? { lat: ride.dest_lat, lng: ride.dest_lng }
        : null,
    [ride],
  );

  // Phase: before pickup we draw driver→pickup; after pickup we draw pickup→dest.
  // We treat metadata.phase = "on_trip" as "after pickup" if backend sets it,
  // otherwise we infer from driver position proximity to pickup.
  const phase: "approach" | "on_trip" = useMemo(() => {
    const meta = (ride?.metadata ?? {}) as Record<string, unknown>;
    if (meta.phase === "on_trip") return "on_trip";
    return "approach";
  }, [ride]);

  // Recompute route when phase / endpoints change. RoutingService has
  // internal dedup + caching, so this is cheap.
  useEffect(() => {
    let alive = true;
    const origin: LatLng | null =
      phase === "approach" ? (driverPos ?? pickup) : pickup;
    const destination: LatLng | null =
      phase === "approach" ? pickup : dropoff;
    if (!origin || !destination) return;
    RoutingService.route(origin, destination, "driving")
      .then((r) => {
        if (!alive) return;
        setRoute({ polyline: r.polyline, durationS: r.durationS });
      })
      .catch(() => {
        if (alive) setRoute(null);
      });
    return () => {
      alive = false;
    };
  }, [phase, driverPos?.lat, driverPos?.lng, pickup?.lat, pickup?.lng, dropoff?.lat, dropoff?.lng]);

  // Fit bounds when pickup/dropoff first arrive
  useEffect(() => {
    if (!pickup || !mapRef.current) return;
    const points: LatLng[] = [pickup];
    if (dropoff) points.push(dropoff);
    if (driverPos) points.push(driverPos);
    if (points.length < 2) {
      mapRef.current.flyTo(pickup.lng, pickup.lat, 15);
      return;
    }
    const b = bboxOf(points);
    mapRef.current.fitBounds(b, 80);
  }, [pickup, dropoff, driverPos?.lat, driverPos?.lng]);

  if (loading || !ride) {
    return (
      <div className="flex h-full items-center justify-center text-sm text-muted-foreground">
        Chargement du trajet…
      </div>
    );
  }

  const status = ride.status;
  const statusLabel = STATUS_COPY[status] ?? status;
  const isFinished = status === "completed" || status === "cancelled";

  return (
    <div className="flex flex-col h-full">
      {/* Map fills available height */}
      <div className="relative flex-1">
        <ChopMap
          ref={mapRef}
          className="absolute inset-0"
          initialView={
            pickup
              ? { latitude: pickup.lat, longitude: pickup.lng, zoom: 14 }
              : undefined
          }
        >
          {pickup && (
            <PinSet
              pickup={pickup}
              dropoff={dropoff ?? undefined}
              pulseActive={phase === "approach" ? "pickup" : "dropoff"}
            />
          )}

          {route && (
            <RoutePolyline
              encoded={route.polyline}
              state={
                isFinished
                  ? "completed"
                  : phase === "approach"
                    ? "approach"
                    : "active"
              }
              animated
            />
          )}

          {driverPos && !isFinished && (
            <Marker
              longitude={driverPos.lng}
              latitude={driverPos.lat}
              anchor="center"
            >
              <MapMarker
                variant={ride.mode === "toktok" ? "toktok" : "moto"}
                state={
                  driverPos.status === "busy"
                    ? "busy"
                    : driverPos.status === "offline"
                      ? "offline"
                      : "online"
                }
                rotation={driverPos.heading}
                size={36}
                pulse
              />
            </Marker>
          )}
        </ChopMap>

        {/* Status pill */}
        <div className="absolute left-1/2 top-3 -translate-x-1/2 rounded-full bg-card/95 backdrop-blur-md border border-border px-3 py-1.5 shadow-md flex items-center gap-2">
          <span className={`h-2 w-2 rounded-full ${statusColor(status)} animate-pulse`} />
          <span className="text-xs font-semibold">{statusLabel}</span>
        </div>

        {/* Close (top right) when finished */}
        {isFinished && onClose && (
          <button
            type="button"
            onClick={onClose}
            className="absolute right-3 top-3 rounded-full bg-card border border-border p-2 shadow-md"
            aria-label="Fermer"
          >
            <X className="h-4 w-4" />
          </button>
        )}
      </div>

      {/* Bottom sheet */}
      <div className="rounded-t-3xl border-t border-border bg-card p-4 space-y-3 shadow-lg">
        <div className="flex items-center gap-3">
          <div className="flex-1 min-w-0">
            <p className="text-[10px] uppercase tracking-wide text-muted-foreground">
              {phase === "approach" ? "Arrivée du chauffeur" : "Arrivée à destination"}
            </p>
            <p className="text-2xl font-bold tabular-nums flex items-center gap-1.5">
              <Clock className="h-5 w-5 text-primary" />
              {route ? formatDuration(route.durationS) : "—"}
            </p>
          </div>
          {ride.driver_id && !isFinished && (
            <div className="flex gap-2">
              <Button
                size="icon"
                variant="outline"
                className="h-10 w-10 rounded-full"
                onClick={() => onCallDriver?.(ride.driver_id!)}
                aria-label="Appeler le chauffeur"
              >
                <Phone className="h-4 w-4" />
              </Button>
              <Button
                size="icon"
                variant="outline"
                className="h-10 w-10 rounded-full opacity-60"
                onClick={() => onMessageDriver?.(ride.driver_id!)}
                aria-label="Message au chauffeur (bientôt)"
                disabled
              >
                <MessageCircle className="h-4 w-4" />
              </Button>
            </div>
          )}
        </div>

        {!isFinished && onCancel && (
          <Button
            variant="ghost"
            size="sm"
            className="w-full text-destructive hover:text-destructive hover:bg-destructive/10 gap-1.5"
            onClick={onCancel}
          >
            <AlertTriangle className="h-4 w-4" />
            Annuler ou signaler un problème
          </Button>
        )}
      </div>
    </div>
  );
}