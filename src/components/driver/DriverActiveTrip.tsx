import { useEffect, useMemo, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import {
  ChopMap, type ChopMapHandle, PinSet, RoutePolyline,
} from "@/components/map";
import {
  bbox as bboxOf, formatDuration, formatDistance, type LatLng,
} from "@/lib/maps";
import { useRideRealtime } from "@/hooks/useRideRealtime";
import { useRideLifecycleNotifications } from "@/hooks/useRideLifecycleNotifications";
import { useConnectionRestored } from "@/hooks/useConnectionRestored";
import { useTurnByTurn } from "@/hooks/useTurnByTurn";
import { useGeolocation } from "@/hooks/useGeolocation";
import { NavigationHud } from "./NavigationHud";
import { DriverTripReceipt } from "./DriverTripReceipt";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  Phone, Navigation, CheckCircle2, AlertTriangle, X, Loader2, MapPin, Flag, QrCode, ExternalLink, Crosshair, ArrowRight,
} from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "@/hooks/use-toast";
import { formatGNF } from "@/lib/format";
import { Analytics } from "@/lib/analytics/AnalyticsService";
import QRCode from "react-qr-code";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { RidePhaseChip, deriveRidePhase } from "@/components/ride/RidePhaseChip";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { getRuntimeMode } from "@/lib/runtimeMode";
import { useAuth } from "@/contexts/AuthContext";
import { playArrivedAtPickup, playRideCompleted } from "@/lib/sound/driverSounds";

type Phase = "approach" | "arrived" | "on_trip" | "at_destination";

interface Props {
  rideId: string;
  onClose: () => void;
}

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
  useConnectionRestored({ context: "driver-active-trip" });
  const { user } = useAuth();
  const runtimeMode = getRuntimeMode(user?.email);
  const mapRef = useRef<ChopMapHandle>(null);
  const [busy, setBusy] = useState(false);
  const [clientPhone, setClientPhone] = useState<string | null>(null);
  const [clientName, setClientName] = useState<string | null>(null);
  const [clientAvatar, setClientAvatar] = useState<string | null>(null);
  const [showReceipt, setShowReceipt] = useState(false);
  const [receiptFare, setReceiptFare] = useState<number>(0);
  const [muted, setMuted] = useState(false);
  const { position: driverPos, request: requestGeo, isReady: geoReady } = useGeolocation({ watch: true });

  // External Google Maps fallback — useful when internal routing fails or
  // the driver simply prefers their familiar nav app.
  const openInGoogleMaps = () => {
    const target = (phase === "on_trip" || phase === "at_destination") ? dropoff : pickup;
    if (!target) return;
    const origin = driverPos ? `${driverPos.lat},${driverPos.lng}` : "";
    const dest = `${target.lat},${target.lng}`;
    const travel = ride?.mode === "moto" ? "two-wheeler" : "driving";
    const url = `https://www.google.com/maps/dir/?api=1&origin=${encodeURIComponent(origin)}&destination=${encodeURIComponent(dest)}&travelmode=${travel}`;
    try { Analytics.track("driver.nav.external_open" as any, { metadata: { rideId, phase } }); } catch {}
    window.open(url, "_blank", "noopener");
  };

  // Demo and sandbox both relax the strict "wait for client scan" gate.
  const isDemo = runtimeMode === "demo" || runtimeMode === "sandbox";
  const pickupCode = (ride?.metadata as any)?.pickup_code as string | undefined;

  // Auto-popup QR when driver confirms arrival, with a fresh token every 30s.
  const [qrOpen, setQrOpen] = useState(false);
  const [qrTick, setQrTick] = useState(() => Math.floor(Date.now() / 30000));
  const prevPhaseRef = useRef<Phase | null>(null);

  useEffect(() => { if (!geoReady) requestGeo(); }, [geoReady, requestGeo]);

  const pickup: LatLng | null = ride ? { lat: ride.pickup_lat, lng: ride.pickup_lng } : null;
  const dropoff: LatLng | null = ride?.dest_lat != null && ride?.dest_lng != null
    ? { lat: ride.dest_lat, lng: ride.dest_lng } : null;

  const phase: Phase = useMemo(() => {
    if (!ride) return "approach";
    const p = (ride.metadata as any)?.phase;
    if (p === "approach" || p === "arrived" || p === "on_trip" || p === "at_destination") {
      return p as Phase;
    }
    // Fallback for legacy rides without a phase tag.
    return ride.status === "in_progress" ? "on_trip" : "approach";
  }, [ride]);

  // Lookup client phone for the call button
  useEffect(() => {
    if (!ride?.client_id) return;
    supabase.from("profiles").select("phone, full_name, display_name, avatar_url")
      .eq("user_id", ride.client_id).maybeSingle()
      .then(({ data }) => {
        setClientPhone(data?.phone ?? null);
        setClientName(data?.display_name ?? data?.full_name ?? null);
        setClientAvatar((data as any)?.avatar_url ?? null);
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

  // Open the QR sheet automatically the moment we transition into "arrived"
  useEffect(() => {
    const prev = prevPhaseRef.current;
    prevPhaseRef.current = phase;
    if (phase === "arrived" && prev !== "arrived") {
      setQrOpen(true);
      // Subtle haptic + sound cue when arriving at pickup.
      try {
        if (typeof navigator !== "undefined" && "vibrate" in navigator) {
          (navigator as any).vibrate?.([30, 40, 30]);
        }
      } catch {}
      if (!muted) playArrivedAtPickup();
      try {
        if (!muted && typeof window !== "undefined" && "AudioContext" in window) {
          const Ctx = (window as any).AudioContext || (window as any).webkitAudioContext;
          const ctx = new Ctx();
          const o = ctx.createOscillator();
          const g = ctx.createGain();
          o.type = "sine";
          o.frequency.setValueAtTime(880, ctx.currentTime);
          o.frequency.exponentialRampToValueAtTime(1320, ctx.currentTime + 0.18);
          g.gain.setValueAtTime(0.0001, ctx.currentTime);
          g.gain.exponentialRampToValueAtTime(0.18, ctx.currentTime + 0.02);
          g.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + 0.35);
          o.connect(g).connect(ctx.destination);
          o.start();
          o.stop(ctx.currentTime + 0.4);
          setTimeout(() => { try { ctx.close(); } catch {} }, 600);
        }
      } catch {}
    }
    if (phase === "on_trip" || phase === "at_destination") setQrOpen(false);
  }, [phase, pickupCode]);

  // Defensive guard: if anything desyncs (refresh, tab switch, server-side
  // pickup confirm), make sure the QR sheet never lingers when phase is no
  // longer "arrived". Also closes when ride.status transitions to in_progress.
  useEffect(() => {
    if (qrOpen && phase !== "arrived") setQrOpen(false);
    if (qrOpen && ride?.status === "in_progress") setQrOpen(false);
  }, [qrOpen, phase, ride?.status]);

  // Rotate the QR token every 30 seconds while the popup is visible
  useEffect(() => {
    if (!qrOpen) return;
    const id = window.setInterval(
      () => setQrTick(Math.floor(Date.now() / 30000)),
      30000,
    );
    return () => window.clearInterval(id);
  }, [qrOpen]);

  const qrValue = pickupCode ? `CHOP-PICKUP-${pickupCode}-${qrTick}` : "";
  const secondsLeft = 30 - Math.floor((Date.now() / 1000) % 30);

  // Stale-while-revalidate: only show the spinner when we truly have nothing.
  // Re-renders during refetch keep the previous ride visible.
  if (!ride) {
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
    if (p === "arrived") setQrOpen(true);
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
    playRideCompleted();
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
    if (phase === "arrived") {
      // Real flow: client confirms pickup via QR/code. Driver waits.
      // Demo mode keeps a manual bypass so testing can continue end-to-end.
      if (isDemo) {
        return { label: "Commencer la course (démo)", icon: Navigation, action: startTrip };
      }
      return { label: "En attente de confirmation client…", icon: Loader2, action: async () => {}, disabled: true as boolean };
    }
    if (phase === "on_trip") return { label: "Arrivé à destination", icon: Flag, action: () => setPhaseRpc("at_destination") };
    return { label: "Terminer & encaisser", icon: CheckCircle2, action: completeTrip };
  })() as { label: string; icon: any; action: () => void | Promise<any>; disabled?: boolean };
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
        <div className="flex items-center gap-2 min-w-0">
          <span className="text-primary-foreground text-sm font-semibold truncate">
            {ride.mode === "moto" ? "Moto" : "TokTok"} · Conducteur
          </span>
          <RidePhaseChip phase={deriveRidePhase(ride)} size="sm" />
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

        <div className="absolute left-1/2 bottom-3 -translate-x-1/2">
          <RidePhaseChip phase={deriveRidePhase(ride)} />
        </div>
      </div>

      <div className="rounded-t-3xl border-t border-border bg-card p-4 space-y-3 shadow-lg">
        {phase === "arrived" && pickupCode && (
          <div className="rounded-2xl border border-border bg-muted/30 p-3 flex items-center gap-3">
            <div className="bg-white p-2 rounded-lg shrink-0">
              <QRCode value={qrValue} size={72} />
            </div>
            <div className="min-w-0">
              <p className="text-[10px] uppercase tracking-wide text-muted-foreground flex items-center gap-1">
                <QrCode className="h-3 w-3" /> Code de prise en charge
              </p>
              <p className="text-2xl font-bold tracking-[0.2em] tabular-nums">{pickupCode}</p>
              <p className="text-[11px] text-muted-foreground">Faites scanner ce QR ou dictez le code au client.</p>
              <button
                onClick={() => setQrOpen(true)}
                className="mt-1 text-[11px] font-semibold text-primary underline"
              >
                Agrandir le QR
              </button>
            </div>
          </div>
        )}
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

        <Button onClick={primary.action} disabled={busy || primary.disabled}
          className="w-full h-14 text-base font-semibold gradient-primary">
          {busy ? <Loader2 className="w-5 h-5 mr-2 animate-spin" /> : <PrimaryIcon className="w-5 h-5 mr-2" />}
          {primary.label}
        </Button>

        <div className="flex items-center gap-2">
          <Button variant="outline" size="sm" onClick={openInGoogleMaps}
            className="flex-1 gap-1.5">
            <ExternalLink className="h-4 w-4" /> Ouvrir dans Google Maps
          </Button>
          {!geoReady && (
            <Button variant="outline" size="sm" onClick={requestGeo} className="gap-1.5">
              <Crosshair className="h-4 w-4" /> Activer GPS
            </Button>
          )}
        </div>

        {!driverPos && (
          <p className="text-[11px] text-muted-foreground text-center">
            Position GPS indisponible — utilisez Google Maps pour la navigation détaillée.
          </p>
        )}

        {phase !== "at_destination" && (
          <Button variant="ghost" size="sm" onClick={cancelTrip} disabled={busy}
            className="w-full text-destructive hover:text-destructive hover:bg-destructive/10 gap-1.5">
            <AlertTriangle className="h-4 w-4" /> Annuler la course
          </Button>
        )}
      </div>

      <Dialog open={qrOpen} onOpenChange={setQrOpen}>
        <DialogContent className="sm:max-w-sm overflow-hidden">
          <AnimatePresence>
            {qrOpen && (
              <motion.div
                key="qr-body"
                initial={{ opacity: 0, scale: 0.92, y: 12 }}
                animate={{ opacity: 1, scale: 1, y: 0 }}
                exit={{ opacity: 0, scale: 0.96, y: 8 }}
                transition={{ type: "spring", stiffness: 320, damping: 26 }}
              >
                <DialogHeader>
                  <DialogTitle className="text-center">Faites scanner ce QR au client</DialogTitle>
                  <DialogDescription className="text-center">
                    Le QR se renouvelle toutes les 30 secondes pour la sécurité.
                  </DialogDescription>
                </DialogHeader>

                <div className="mt-3 flex items-center gap-3 rounded-xl border bg-muted/40 p-3">
                  <Avatar className="h-10 w-10">
                    {clientAvatar ? <AvatarImage src={clientAvatar} alt={clientName ?? "Client"} /> : null}
                    <AvatarFallback>
                      {(clientName ?? "C").trim().charAt(0).toUpperCase()}
                    </AvatarFallback>
                  </Avatar>
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium">{clientName ?? "Client"}</p>
                    <p className="flex items-center gap-1.5 text-[11px] text-muted-foreground">
                      <span className="relative inline-flex h-2 w-2">
                        <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-primary/60" />
                        <span className="relative inline-flex h-2 w-2 rounded-full bg-primary" />
                      </span>
                      En attente de confirmation client…
                    </p>
                  </div>
                </div>

                {pickupCode ? (
                  <motion.div
                    initial={{ opacity: 0, y: 8 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ delay: 0.08 }}
                    className="flex flex-col items-center gap-3 pb-2 pt-4"
                  >
                    <motion.div
                      key={qrTick}
                      initial={{ opacity: 0, scale: 0.96 }}
                      animate={{ opacity: 1, scale: 1 }}
                      transition={{ duration: 0.25 }}
                      className="bg-white p-4 rounded-2xl shadow-sm"
                    >
                      <QRCode value={qrValue} size={220} />
                    </motion.div>
                    <div className="flex flex-col items-center gap-1">
                      <p className="text-[10px] uppercase tracking-widest text-muted-foreground">
                        Code de prise en charge
                      </p>
                      <p className="text-3xl font-bold tracking-[0.3em] tabular-nums">{pickupCode}</p>
                    </div>
                    <p className="text-xs text-muted-foreground text-center">
                      Renouvellement dans {secondsLeft}s · le client peut aussi saisir le code à 6 caractères.
                    </p>
                    {isDemo && (
                      <div className="w-full pt-2 space-y-2">
                        <Button
                          onClick={async () => { setQrOpen(false); await startTrip(); }}
                          disabled={busy}
                          className="w-full h-12 gradient-primary text-base font-semibold"
                        >
                          {busy ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <ArrowRight className="w-5 h-5 mr-2" />}
                          Continuer la course démo
                        </Button>
                        <p className="text-[11px] text-muted-foreground text-center">
                          Mode démo — pas besoin que le client scanne.
                        </p>
                      </div>
                    )}
                  </motion.div>
                ) : (
                  <div className="flex flex-col items-center gap-3 py-8">
                    <Loader2 className="w-8 h-8 animate-spin text-primary" />
                    <p className="text-sm text-muted-foreground">Génération du code de prise en charge…</p>
                  </div>
                )}
              </motion.div>
            )}
          </AnimatePresence>
        </DialogContent>
      </Dialog>
    </motion.div>
  );
}