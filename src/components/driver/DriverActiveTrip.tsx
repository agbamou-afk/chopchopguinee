import { useEffect, useMemo, useRef, useState } from "react";
import { motion } from "framer-motion";
import {
  ChopMap, type ChopMapHandle, PinSet, RoutePolyline,
} from "@/components/map";
import {
  bbox as bboxOf, formatDuration, formatDistance, type LatLng,
} from "@/lib/maps";
import { useRideRealtime } from "@/hooks/useRideRealtime";
import { useRideLifecycleNotifications } from "@/hooks/useRideLifecycleNotifications";
import { useTurnByTurn } from "@/hooks/useTurnByTurn";
import { useGeolocation } from "@/hooks/useGeolocation";
import { NavigationHud } from "./NavigationHud";
import { DriverTripReceipt } from "./DriverTripReceipt";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  Phone, Navigation, CheckCircle2, AlertTriangle, X, Loader2, MapPin, Flag,
} from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "@/hooks/use-toast";
import { formatGNF } from "@/lib/format";
import { Analytics } from "@/lib/analytics/AnalyticsService";

type Phase = "approach" | "arrived" | "on_trip" | "at_destination";

interface Props {
  rideId: string;
  onClose: () => void;
}

const PHASE_LABEL: Record<Phase, string> = {
  approach: "En route vers le client",
  arrived: "Arrivé au point de prise en charge",
  on_trip: "Course en cours",
  at_destination: "Arrivé à destination",
};

/**
 * Driver-side active trip screen.
 * - Live map (pickup, dropoff, dynamic route via RoutingService)
 * - Single primary action that advances through the ride lifecycle:
 *     approach → arrived → on_trip → at_destination → completed
 * - Backed by ride_set_phase / ride_start / ride_complete / ride_cancel RPCs.
 */
export function DriverActiveTrip({ rideId, onClose }: Props) {
  const { ride, loading } = useRideRealtime(rideId);
  useRideLifecycleNotifications(ride, "driver");
  const mapRef = useRef<ChopMapHandle>(null);
  const [busy, setBusy] = useState(false);
  const [clientPhone, setClientPhone] = useState<string | null>(null);
  const [clientName, setClientName] = useState<string | null>(null);
  const [showReceipt, setShowReceipt] = useState(false);
  const [receiptFare, setReceiptFare] = useState<number>(0);
  const [muted, setMuted] = useState(false);
  const { position: driverPos, request: requestGeo, isReady: geoReady } = useGeolocation({ watch: true });

  useEffect(() => { if (!geoReady) requestGeo(); }, [geoReady, requestGeo]);

  const pickup: LatLng | null = ride ? { lat: ride.pickup_lat, lng: ride.pickup_lng } : null;
  const dropoff: LatLng | null = ride?.dest_lat != null && ride?.dest_lng != null
    ? { lat: ride.dest_lat, lng: ride.dest_lng } : null;

  const phase: Phase = useMemo(() => {
    if (!ride) return "approach";
    if (ride.status === "in_progress") {
      const p = (ride.metadata as any)?.phase;
      return p === "at_destination" ? "at_destination" : "on_trip";
    }
    const p = (ride.metadata as any)?.phase;
    return p === "arrived" ? "arrived" : "approach";
  }, [ride]);

  // Lookup client phone for the call button
  useEffect(() => {
    if (!ride?.client_id) return;
    supabase.from("profiles").select("phone, full_name, display_name")
      .eq("user_id", ride.client_id).maybeSingle()
      .then(({ data }) => {
        setClientPhone(data?.phone ?? null);
        setClientName(data?.display_name ?? data?.full_name ?? null);
      });
  }, [ride?.client_id]);

  // Turn-by-turn navigation: origin/destination flip with the trip phase.
  const navOrigin: LatLng | null = (phase === "on_trip" || phase === "at_destination")
    ? pickup
    : (driverPos ? { lat: driverPos.lat, lng: driverPos.lng } : pickup);
  const navDestination: LatLng | null =
    (phase === "on_trip" || phase === "at_destination") ? dropoff : pickup;
  const navMode = ride?.mode === "moto" ? "two_wheeler" : "driving";
  const nav = useTurnByTurn({
    origin: navOrigin,
    destination: navDestination,
    driverPos: driverPos ? { lat: driverPos.lat, lng: driverPos.lng } : null,
    mode: navMode,
    enabled: !!ride && phase !== "at_destination",
    mute: muted,
  });

  // Fit bounds whenever endpoints arrive
  useEffect(() => {
    if (!pickup || !mapRef.current) return;
    const pts: LatLng[] = [pickup];
    if (dropoff) pts.push(dropoff);
    if (pts.length < 2) { mapRef.current.flyTo(pickup.lng, pickup.lat, 15); return; }
    mapRef.current.fitBounds(bboxOf(pts), 80);
  }, [pickup?.lat, pickup?.lng, dropoff?.lat, dropoff?.lng]);

  if (loading || !ride) {
    return (
      <div className="fixed inset-0 z-50 flex items-center justify-center bg-background">
        <Loader2 className="w-6 h-6 animate-spin text-primary" />
      </div>
    );
  }

  const setPhaseRpc = async (p: Phase) => {
    setBusy(true);
    const { error } = await supabase.rpc("ride_set_phase", { p_ride_id: rideId, p_phase: p });
    setBusy(false);
    if (error) { toast({ title: "Erreur", description: error.message }); return false; }
    try { Analytics.track("driver.ride.completed" as any, { metadata: { phase: p, rideId } }); } catch {}
    return true;
  };

  const startTrip = async () => {
    setBusy(true);
    const { error } = await supabase.rpc("ride_start", { p_ride_id: rideId });
    setBusy(false);
    if (error) { toast({ title: "Impossible de démarrer", description: error.message }); return; }
    toast({ title: "Course démarrée", description: "Bonne route !" });
  };

  const completeTrip = async () => {
    setBusy(true);
    const { error } = await supabase.rpc("ride_complete", {
      p_ride_id: rideId, p_actual_fare_gnf: ride.fare_gnf, p_commission_bps: 1500,
    });
    setBusy(false);
    if (error) { toast({ title: "Erreur", description: error.message }); return; }
    try { Analytics.track("driver.ride.completed" as any, { metadata: { rideId } }); } catch {}
    setReceiptFare(ride.fare_gnf ?? 0);
    setShowReceipt(true);
  };

  const cancelTrip = async () => {
    if (!confirm("Annuler cette course ?")) return;
    setBusy(true);
    const { error } = await supabase.rpc("ride_cancel", { p_ride_id: rideId, p_reason: "Annulée par le chauffeur" });
    setBusy(false);
    if (error) { toast({ title: "Erreur", description: error.message }); return; }
    try { Analytics.track("driver.ride.declined" as any, { metadata: { rideId, after: "accepted" } }); } catch {}
    onClose();
  };

  const primary = (() => {
    if (phase === "approach") return { label: "Je suis arrivé", icon: MapPin, action: () => setPhaseRpc("arrived") };
    if (phase === "arrived") return { label: "Démarrer la course", icon: Navigation, action: startTrip };
    if (phase === "on_trip") return { label: "Arrivé à destination", icon: Flag, action: () => setPhaseRpc("at_destination") };
    return { label: "Terminer & encaisser", icon: CheckCircle2, action: completeTrip };
  })();
  const PrimaryIcon = primary.icon;

  return (
    <motion.div
      initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
      className="fixed inset-0 z-50 bg-background flex flex-col"
    >
      {showReceipt && (
        <DriverTripReceipt
          rideId={rideId}
          fareGnf={receiptFare}
          commissionBps={1500}
          clientName={clientName}
          paymentLabel="Espèces"
          onClose={onClose}
        />
      )}
      <div className="gradient-primary px-4 py-3 flex items-center justify-between shrink-0">
        <button onClick={onClose} aria-label="Fermer"
          className="p-2 rounded-full bg-white/20 hover:bg-white/30 transition">
          <X className="w-5 h-5 text-primary-foreground" />
        </button>
        <div className="text-primary-foreground text-sm font-semibold">
          {ride.mode === "moto" ? "Moto" : "TokTok"} · Conducteur
        </div>
        <Badge variant="secondary" className="text-[10px]">
          {formatGNF(ride.fare_gnf ?? 0)}
        </Badge>
      </div>

      <div className="relative flex-1">
        <ChopMap ref={mapRef} className="absolute inset-0"
          initialView={pickup ? { latitude: pickup.lat, longitude: pickup.lng, zoom: 14 } : undefined}>
          {pickup && (
            <PinSet pickup={pickup} dropoff={dropoff ?? undefined}
              pulseActive={phase === "approach" || phase === "arrived" ? "pickup" : "dropoff"} />
          )}
          {nav.route && (
            <RoutePolyline encoded={nav.route.polyline}
              state={phase === "on_trip" || phase === "at_destination" ? "active" : "approach"} animated />
          )}
        </ChopMap>

        <NavigationHud state={nav} muted={muted} onToggleMute={() => setMuted(m => !m)} />

        <div className="absolute left-1/2 bottom-3 -translate-x-1/2 rounded-full bg-card/95 backdrop-blur border border-border px-3 py-1.5 shadow-md">
          <span className="text-xs font-semibold">{PHASE_LABEL[phase]}</span>
        </div>
      </div>

      <div className="rounded-t-3xl border-t border-border bg-card p-4 space-y-3 shadow-lg">
        <div className="flex items-center gap-3">
          <div className="flex-1 min-w-0">
            <p className="text-[10px] uppercase tracking-wide text-muted-foreground">
              {phase === "on_trip" || phase === "at_destination" ? "Vers destination" : "Vers client"}
            </p>
            <p className="text-2xl font-bold tabular-nums">
              {nav.route ? formatDuration(nav.remainingDurationS || nav.route.durationS) : "—"}
              {nav.route && (
                <span className="text-sm font-normal text-muted-foreground ml-2">
                  {formatDistance(nav.remainingDistanceM || nav.route.distanceM)}
                </span>
              )}
            </p>
          </div>
          {clientPhone && (
            <Button size="icon" variant="outline" className="h-11 w-11 rounded-full"
              onClick={() => { window.location.href = `tel:${clientPhone}`; }}
              aria-label="Appeler le client">
              <Phone className="h-4 w-4" />
            </Button>
          )}
        </div>

        <Button onClick={primary.action} disabled={busy}
          className="w-full h-14 text-base font-semibold gradient-primary">
          {busy ? <Loader2 className="w-5 h-5 mr-2 animate-spin" /> : <PrimaryIcon className="w-5 h-5 mr-2" />}
          {primary.label}
        </Button>

        {phase !== "at_destination" && (
          <Button variant="ghost" size="sm" onClick={cancelTrip} disabled={busy}
            className="w-full text-destructive hover:text-destructive hover:bg-destructive/10 gap-1.5">
            <AlertTriangle className="h-4 w-4" /> Annuler la course
          </Button>
        )}
      </div>
    </motion.div>
  );
}