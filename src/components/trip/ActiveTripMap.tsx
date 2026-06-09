import { useEffect, useMemo, useRef, useState } from "react";
import { Marker } from "react-map-gl";
import {
  Phone,
  MessageCircle,
  X,
  AlertTriangle,
  Clock,
  Search,
  KeyRound,
  RotateCcw,
  Bike,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  ChopMap,
  type ChopMapHandle,
  MapMarker,
  PinSet,
  RoutePolyline,
  StraightLineFallback,
} from "@/components/map";
import {
  RoutingService,
  bbox as bboxOf,
  formatDuration,
  useDriverLocation,
  type LatLng,
} from "@/lib/maps";
import { useRideRealtime } from "@/hooks/useRideRealtime";
import { supabase } from "@/integrations/supabase/client";
import { formatGNF } from "@/lib/format";

interface Props {
  rideId: string;
  /** Optional driver display name (already fetched upstream). */
  driverName?: string | null;
  /** Tap a "call driver" affordance. */
  onCallDriver?: (driverId: string) => void;
  /** Tap "message driver" placeholder. */
  onMessageDriver?: (driverId: string) => void;
  /** Cancel or report issue. */
  onCancel?: () => void;
  /** Close the screen (after completion or by user). */
  onClose?: () => void;
  /** When true, hide the in-map bottom sheet so an overlay panel
   *  (e.g. PickupConfirmCard during 'arrived') can dominate without
   *  competing for vertical space. */
  hideBottomSheet?: boolean;
}

/**
 * Resolve a customer-facing label for the current ride state.
 * We treat pending+no-driver as "searching", and lean on metadata.phase to
 * distinguish approach / arrived / on-trip once a driver is assigned.
 */
function resolveStatusCopy(
  status: string,
  phase: string,
  hasDriver: boolean,
): { label: string; color: string } {
  if (status === "completed") return { label: "Trajet terminé", color: "bg-emerald-500" };
  if (status === "cancelled") return { label: "Trajet annulé", color: "bg-destructive" };
  if (status === "pending" && !hasDriver) {
    return { label: "Recherche d'un chauffeur…", color: "bg-amber-500" };
  }
  if (phase === "arrived") return { label: "Chauffeur arrivé", color: "bg-emerald-500" };
  if (phase === "on_trip") return { label: "Course en cours", color: "bg-primary" };
  return { label: "Votre chauffeur arrive", color: "bg-primary" };
}

/** Soft window after which we surface a no-driver fallback. */
const NO_DRIVER_TIMEOUT_S = 90;

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
  driverName,
  onCallDriver,
  onMessageDriver,
  onCancel,
  onClose,
  hideBottomSheet = false,
}: Props) {
  const { ride, loading } = useRideRealtime(rideId);
  const driverPos = useDriverLocation(ride?.driver_id ?? null);
  const mapRef = useRef<ChopMapHandle>(null);
  const [route, setRoute] = useState<{ polyline: string; durationS: number } | null>(
    null,
  );
  const [searchElapsed, setSearchElapsed] = useState(0);
  const [retrying, setRetrying] = useState(false);

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
  const meta = (ride?.metadata ?? {}) as Record<string, unknown>;
  const phaseRaw = (meta.phase as string | undefined) ?? "approach";
  const phase: "approach" | "on_trip" = phaseRaw === "on_trip" ? "on_trip" : "approach";
  const pickupCode = (meta.pickup_code as string | undefined) ?? null;
  const isSearching = !!ride && ride.status === "pending" && !ride.driver_id;

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

  // Searching timer — drives the no-driver fallback. Reset whenever the
  // ride leaves the searching state so we don't surface a stale timeout.
  useEffect(() => {
    if (!isSearching) {
      setSearchElapsed(0);
      return;
    }
    const start = Date.now();
    const id = window.setInterval(() => {
      setSearchElapsed(Math.floor((Date.now() - start) / 1000));
    }, 1000);
    return () => window.clearInterval(id);
  }, [isSearching]);

  if (!ride) {
    return (
      <div className="flex h-full items-center justify-center text-sm text-muted-foreground animate-pulse">
        Chargement du trajet…
      </div>
    );
  }

  const status = ride.status;
  const { label: statusLabel, color: statusColorClass } = resolveStatusCopy(
    status,
    phaseRaw,
    !!ride.driver_id,
  );
  const isFinished = status === "completed" || status === "cancelled";
  const showNoDriverFallback = isSearching && searchElapsed >= NO_DRIVER_TIMEOUT_S;
  const vehicleLabel = ride.mode === "toktok" ? "TokTok" : "Moto";

  const handleRetryDispatch = async () => {
    setRetrying(true);
    try {
      await supabase.rpc("ride_dispatch", { p_ride_id: rideId });
      setSearchElapsed(0);
    } finally {
      setRetrying(false);
    }
  };

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

          {!route && pickup && (phase === "approach" ? (driverPos ?? pickup) : pickup) && (phase === "approach" ? pickup : dropoff) && (
            <StraightLineFallback
              id={`client-ride-${rideId}-fallback-route`}
              from={phase === "approach" ? (driverPos ?? pickup) : pickup}
              to={phase === "approach" ? pickup : dropoff!}
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
          <span className={`h-2 w-2 rounded-full ${statusColorClass} animate-pulse`} />
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
      {hideBottomSheet ? null : (
      <div className="rounded-t-3xl border-t border-border bg-card p-4 space-y-3 shadow-lg">
        {isSearching ? (
          <div className="space-y-3">
            <div className="flex items-center gap-3">
              <div className="relative h-12 w-12 shrink-0">
                <span className="absolute inset-0 rounded-full bg-primary/20 animate-ping" />
                <span className="absolute inset-2 rounded-full bg-primary/30 animate-pulse" />
                <div className="absolute inset-0 flex items-center justify-center">
                  <Search className="h-5 w-5 text-primary" />
                </div>
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold">Recherche d'un chauffeur {vehicleLabel}…</p>
                <p className="text-xs text-muted-foreground">
                  Nous pingons les chauffeurs les plus proches.
                </p>
              </div>
              <span className="text-xs text-muted-foreground tabular-nums">{searchElapsed}s</span>
            </div>
            <div className="grid grid-cols-2 gap-2 text-xs">
              <div className="rounded-xl bg-muted/40 p-2">
                <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Véhicule</p>
                <p className="font-semibold">{vehicleLabel}</p>
              </div>
              <div className="rounded-xl bg-muted/40 p-2">
                <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Tarif estimé</p>
                <p className="font-semibold tabular-nums">{formatGNF(ride.fare_gnf)}</p>
              </div>
            </div>
            {showNoDriverFallback && (
              <div className="rounded-xl border border-amber-500/30 bg-amber-500/5 p-3 space-y-2">
                <div className="flex items-start gap-2">
                  <AlertTriangle className="h-4 w-4 text-amber-600 mt-0.5 shrink-0" />
                  <p className="text-xs">
                    Aucun chauffeur n'a répondu pour le moment. Vous pouvez relancer la recherche
                    ou annuler.
                  </p>
                </div>
                <div className="flex gap-2">
                  <Button
                    size="sm"
                    onClick={handleRetryDispatch}
                    disabled={retrying}
                    className="flex-1 gap-1.5"
                  >
                    <RotateCcw className="h-3.5 w-3.5" />
                    {retrying ? "Relance…" : "Relancer la recherche"}
                  </Button>
                  {onCancel && (
                    <Button size="sm" variant="outline" onClick={onCancel}>
                      Annuler
                    </Button>
                  )}
                </div>
              </div>
            )}
          </div>
        ) : (
          <>
            {ride.driver_id && !isFinished && (
              <div className="flex items-center gap-3">
                <div className="h-10 w-10 rounded-full bg-primary/10 flex items-center justify-center">
                  <Bike className="h-5 w-5 text-primary" />
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-semibold truncate">
                    {driverName ?? "Votre chauffeur"}
                  </p>
                  <p className="text-xs text-muted-foreground truncate">
                    {vehicleLabel}
                    {driverPos
                      ? null
                      : <> · <span className="text-amber-600">Position en attente…</span></>}
                  </p>
                </div>
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
              </div>
            )}

            <div className="flex items-center gap-3">
              <div className="flex-1 min-w-0">
                <p className="text-[10px] uppercase tracking-wide text-muted-foreground">
                  {phase === "approach" ? "Arrivée du chauffeur" : "Arrivée à destination"}
                </p>
                <p className="text-2xl font-bold tabular-nums flex items-center gap-1.5">
                  <Clock className="h-5 w-5 text-primary" />
                  {route ? formatDuration(route.durationS) : isFinished ? "—" : "Calcul…"}
                </p>
              </div>
              <div className="text-right">
                <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Tarif</p>
                <p className="text-sm font-semibold tabular-nums">{formatGNF(ride.fare_gnf)}</p>
              </div>
            </div>

            {!isFinished && phase !== "on_trip" && phaseRaw !== "arrived" && ride.driver_id && (
              <div className="rounded-xl border border-primary/20 bg-primary/5 p-3 flex items-center gap-3">
                <KeyRound className="h-4 w-4 text-primary shrink-0" />
                <p className="text-[11px] text-muted-foreground leading-tight">
                  À l'arrivée, scannez le code affiché sur l'application du chauffeur pour démarrer la course.
                </p>
              </div>
            )}
          </>
        )}

        {!isFinished && onCancel && !showNoDriverFallback && (
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
      )}
    </div>
  );
}