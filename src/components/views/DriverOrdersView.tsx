import { motion } from "framer-motion";
import { useRef } from "react";
import { Marker } from "react-map-gl";
import { formatGNF } from "@/lib/format";
import { useDriverSession } from "@/contexts/DriverSessionContext";
import { Users, Timer, BellRing, Flame, Navigation, Plus, Minus, LocateFixed } from "lucide-react";
import { IncomingRequestIsland } from "@/components/driver/IncomingRequestIsland";
import { MenuButton } from "@/components/ui/MainMenuSheet";
import { ChopMap, HeatmapLayer, type ChopMapHandle } from "@/components/map";
import { useGeolocation } from "@/hooks/useGeolocation";
import { toast } from "sonner";

const CONAKRY_HOTSPOTS = [
  { name: "Kaloum", lng: -13.7100, lat: 9.5100, weight: 1.0 },
  { name: "Madina", lng: -13.6650, lat: 9.5550, weight: 0.92 },
  { name: "Hamdallaye", lng: -13.6450, lat: 9.5800, weight: 0.78 },
  { name: "Ratoma", lng: -13.6800, lat: 9.6300, weight: 0.7 },
  { name: "Kipé", lng: -13.6300, lat: 9.6500, weight: 0.55 },
  { name: "Aéroport", lng: -13.6120, lat: 9.5770, weight: 0.5 },
] as const;

export function DriverOrdersView() {
  const { queue, current, currentExpiresAt, accept, decline, showCurrent, isOnline, activeTrip } =
    useDriverSession();
  const mapRef = useRef<ChopMapHandle>(null);
  const geo = useGeolocation();
  const displayedRequest = !activeTrip ? current ?? queue[0] ?? null : null;
  const offerTimeoutSec = currentExpiresAt
    ? Math.max(1, Math.ceil((new Date(currentExpiresAt).getTime() - Date.now()) / 1000))
    : 20;

  const sorted = [...CONAKRY_HOTSPOTS].sort((a, b) => b.weight - a.weight);
  const top = sorted[0];

  const zoomBy = (delta: number) => {
    const m = mapRef.current?.getMap();
    if (!m) return;
    const z = m.getZoom();
    m.easeTo({ zoom: z + delta, duration: 250 });
  };
  const recenter = () => {
    const m = mapRef.current?.getMap();
    if (!m) return;
    if (geo.position) {
      m.flyTo({
        center: [geo.position.lng, geo.position.lat],
        zoom: 15.5,
        bearing: 0,
        essential: true,
        duration: 800,
      });
    } else if (!geo.isReady) {
      geo.request();
      toast("Position chauffeur indisponible.");
    } else {
      toast("Position chauffeur indisponible.");
    }
  };

  return (
    <div className="fixed inset-0 overflow-hidden">
      {/* Full-bleed map background */}
      <div className="absolute inset-0">
        <ChopMap
          ref={mapRef}
          className="absolute inset-0 w-full h-full"
          interactive={true}
          initialView={{ longitude: -13.6773, latitude: 9.5900, zoom: 11.4 }}
        >
          <HeatmapLayer
            points={CONAKRY_HOTSPOTS.map((h) => ({ lng: h.lng, lat: h.lat, weight: h.weight }))}
          />
          {sorted.slice(0, 3).map((h, i) => (
            <Marker key={h.name} longitude={h.lng} latitude={h.lat} anchor="bottom">
              <div className="flex flex-col items-center pointer-events-none">
                <div
                  className={`px-2 py-0.5 rounded-full text-[10px] font-bold shadow-card ${
                    i === 0
                      ? "bg-destructive text-destructive-foreground"
                      : "bg-card text-foreground border border-border"
                  }`}
                >
                  {h.name}
                </div>
                <div
                  className={`w-2 h-2 rounded-full mt-0.5 ${
                    i === 0 ? "bg-destructive" : "bg-foreground/60"
                  }`}
                />
              </div>
            </Marker>
          ))}
        </ChopMap>
        {/* Soft top + bottom fades so floating UI stays legible over the map */}
        <div className="pointer-events-none absolute inset-x-0 top-0 h-32 bg-gradient-to-b from-background/85 to-transparent" />
        <div className="pointer-events-none absolute inset-x-0 bottom-0 h-40 bg-gradient-to-t from-background/85 to-transparent" />
      </div>

      {/* Top floating header (translucent, no opaque card) */}
      <div
        className="absolute left-0 right-0 px-4 z-10"
        style={{ top: "max(0.75rem, env(safe-area-inset-top))" }}
      >
        <div className="max-w-md mx-auto flex items-center gap-3">
          <MenuButton floating />
          <div className="min-w-0 flex-1">
            <h1 className="text-lg font-extrabold text-foreground leading-tight">Mes courses</h1>
            <p className="text-[11px] text-muted-foreground">Zones actives · Conakry</p>
          </div>
          <div className="inline-flex items-center gap-1.5 rounded-full bg-card/90 backdrop-blur px-2.5 py-1 border border-border/60 shadow-card">
            <span className="relative flex h-1.5 w-1.5">
              <span
                className={`absolute inline-flex h-full w-full rounded-full ${
                  isOnline ? "bg-success/70" : "bg-muted-foreground/40"
                } ${isOnline ? "animate-ping" : ""}`}
              />
              <span
                className={`relative inline-flex h-1.5 w-1.5 rounded-full ${
                  isOnline ? "bg-success" : "bg-muted-foreground"
                }`}
              />
            </span>
            <Timer className="w-3 h-3 text-foreground" />
            <span className="text-[11px] font-semibold text-foreground">
              {isOnline ? "En ligne" : "Hors ligne"}
            </span>
          </div>
        </div>
      </div>

      {/* Active-trip floating card (centered) */}
      {activeTrip && (
        <motion.div
          initial={{ opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          className="absolute left-0 right-0 px-4 z-10"
          style={{ bottom: "calc(6rem + env(safe-area-inset-bottom))" }}
        >
          <div className="max-w-md mx-auto bg-card/95 backdrop-blur rounded-2xl shadow-elevated border border-primary/30 overflow-hidden">
            <div className="gradient-wallet px-4 py-2.5 flex items-center justify-between text-primary-foreground">
              <span className="text-sm font-bold inline-flex items-center gap-1.5">
                <Navigation className="w-4 h-4" /> Course active
              </span>
              <span className="text-[11px] opacity-80">Navigation ouverte</span>
            </div>
            <div className="p-4 space-y-3">
              <div className="flex items-start gap-3">
                <div className="mt-1 w-2.5 h-2.5 rounded-full bg-primary" />
                <div className="flex-1 min-w-0">
                  <p className="text-[10px] uppercase text-muted-foreground">Départ</p>
                  <p className="text-sm font-semibold text-foreground truncate">
                    {activeTrip.pickup}
                  </p>
                </div>
              </div>
              <div className="flex items-start gap-3">
                <div className="mt-1 w-2.5 h-2.5 rounded-full bg-secondary" />
                <div className="flex-1 min-w-0">
                  <p className="text-[10px] uppercase text-muted-foreground">Destination</p>
                  <p className="text-sm font-semibold text-foreground truncate">
                    {activeTrip.destination}
                  </p>
                </div>
              </div>
              <div className="flex items-center justify-between py-2 px-3 bg-muted rounded-xl">
                <span className="text-xs text-muted-foreground">Estimé</span>
                <span className="text-base font-bold text-foreground">
                  {formatGNF(activeTrip.estimatedPrice)}
                </span>
              </div>
            </div>
          </div>
        </motion.div>
      )}

      {/* Bottom floating status pill: demand count + top zone (idle state) */}
      {!activeTrip && (
        <div
          className="absolute left-0 right-0 px-4 z-10"
          style={{ bottom: "calc(5.5rem + env(safe-area-inset-bottom))" }}
        >
          <div className="max-w-md mx-auto">
            {isOnline && queue.length > 0 ? (
              <button
                onClick={showCurrent}
                className="w-full flex items-center gap-3 p-3 rounded-2xl bg-card/95 backdrop-blur border border-primary/40 shadow-elevated text-left active:scale-[0.99] transition"
              >
                <div className="p-2 rounded-xl bg-primary/15">
                  <BellRing className="w-4 h-4 text-primary" />
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-semibold text-foreground truncate">
                    {queue.length} demande{queue.length > 1 ? "s" : ""} en attente
                  </p>
                  <p className="text-[11px] text-muted-foreground">Touchez pour voir la suivante</p>
                </div>
              </button>
            ) : (
              <div className="w-full flex items-center gap-3 p-2.5 rounded-2xl bg-card/90 backdrop-blur border border-border/60 shadow-card">
                <div className="p-1.5 rounded-lg bg-primary/10">
                  <Users className="w-3.5 h-3.5 text-primary" />
                </div>
                <p className="text-[12px] font-medium text-foreground flex-1 truncate">
                  {isOnline
                    ? queue.length === 0
                      ? "Aucune demande proche · à l'écoute"
                      : `${queue.length} demande${queue.length > 1 ? "s" : ""} proche${queue.length > 1 ? "s" : ""}`
                    : "Hors ligne — passez en ligne pour recevoir des courses"}
                </p>
                <div className="inline-flex items-center gap-1 text-[11px] font-bold text-destructive whitespace-nowrap">
                  <Flame className="w-3 h-3" />
                  {top.name}
                </div>
              </div>
            )}
          </div>
        </div>
      )}

      {/* Floating island popup lives in the Courses tab only */}
      <IncomingRequestIsland
        request={displayedRequest}
        onAccept={accept}
        onDecline={decline}
        timeoutSec={offerTimeoutSec}
      />
    </div>
  );
}
