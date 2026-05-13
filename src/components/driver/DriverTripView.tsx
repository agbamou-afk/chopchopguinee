import { useEffect, useMemo, useRef, useState } from "react";
import { formatGNF } from "@/lib/format";
import { motion, AnimatePresence } from "framer-motion";
import { MapContainer, TileLayer, Marker, Polyline, useMap } from "react-leaflet";
import L from "leaflet";
import "leaflet/dist/leaflet.css";
import QRCode from "react-qr-code";
import { Navigation, MapPin, CheckCircle2, X, QrCode } from "lucide-react";
import { Button } from "@/components/ui/button";
import { toast } from "sonner";
import type { IncomingRequest } from "@/components/driver/IncomingRequestPopup";

interface Props {
  request: IncomingRequest;
  onClose: () => void;
}

type Phase =
  | "enrouteToClient"
  | "atClient"
  | "enrouteToDest"
  | "atDest"
  | "completed";

const CONAKRY: [number, number] = [9.6412, -13.5784];

const clientIcon = L.divIcon({
  className: "",
  html: `<div style="width:18px;height:18px;border-radius:9999px;background:hsl(var(--secondary));border:3px solid white;box-shadow:0 2px 6px rgba(0,0,0,.3)"></div>`,
  iconSize: [18, 18],
  iconAnchor: [9, 9],
});
const destIcon = L.divIcon({
  className: "",
  html: `<div style="width:18px;height:18px;border-radius:9999px;background:hsl(var(--destructive));border:3px solid white;box-shadow:0 2px 6px rgba(0,0,0,.3)"></div>`,
  iconSize: [18, 18],
  iconAnchor: [9, 9],
});
const driverIcon = L.divIcon({
  className: "",
  html: `<div style="width:34px;height:34px;border-radius:9999px;background:white;border:2px solid hsl(var(--primary));display:flex;align-items:center;justify-content:center;box-shadow:0 2px 8px rgba(0,0,0,.3);font-size:18px">🛵</div>`,
  iconSize: [34, 34],
  iconAnchor: [17, 17],
});

function FitTo({ a, b }: { a: [number, number]; b: [number, number] }) {
  const map = useMap();
  useEffect(() => {
    map.fitBounds(L.latLngBounds([a, b]), { padding: [60, 60], maxZoom: 16 });
  }, [a[0], a[1], b[0], b[1], map]);
  return null;
}

export function DriverTripView({ request, onClose }: Props) {
  // Mock fixed coordinates near Conakry for client pickup & destination
  const clientPos = useMemo<[number, number]>(
    () => [CONAKRY[0] + (Math.random() - 0.5) * 0.02, CONAKRY[1] + (Math.random() - 0.5) * 0.02],
    [],
  );
  const destPos = useMemo<[number, number]>(
    () => [clientPos[0] + 0.015, clientPos[1] + 0.012],
    [clientPos],
  );

  const [phase, setPhase] = useState<Phase>("enrouteToClient");
  const [driverPos, setDriverPos] = useState<[number, number]>(() => [
    clientPos[0] + 0.012,
    clientPos[1] - 0.012,
  ]);
  const [etaSec, setEtaSec] = useState(180);
  const tickRef = useRef<number | null>(null);

  const tripId = useMemo(() => Math.random().toString(36).slice(2, 8).toUpperCase(), []);
  const startCode = `CHOP-START-${request.id}-${tripId}`;
  const endCode = `CHOP-END-${request.id}-${tripId}`;

  // Move driver toward target
  useEffect(() => {
    if (phase !== "enrouteToClient" && phase !== "enrouteToDest") return;
    const target = phase === "enrouteToClient" ? clientPos : destPos;
    setEtaSec(phase === "enrouteToClient" ? 180 : 240);
    tickRef.current = window.setInterval(() => {
      setDriverPos((p) => {
        const dLat = target[0] - p[0];
        const dLng = target[1] - p[1];
        const dist = Math.hypot(dLat, dLng);
        if (dist < 0.0003) {
          setPhase((cur) => (cur === "enrouteToClient" ? "atClient" : "atDest"));
          return target;
        }
        return [p[0] + dLat * 0.07, p[1] + dLng * 0.07];
      });
      setEtaSec((s) => Math.max(0, s - 5));
    }, 1000);
    return () => {
      if (tickRef.current) clearInterval(tickRef.current);
    };
  }, [phase, clientPos, destPos]);

  const focusB =
    phase === "enrouteToClient" || phase === "atClient" ? clientPos : destPos;

  const formatEta = (s: number) => {
    const m = Math.floor(s / 60);
    const r = s % 60;
    return `${m}:${r.toString().padStart(2, "0")}`;
  };

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      className="fixed inset-0 z-50 bg-background flex flex-col"
    >
      <div className="gradient-primary px-4 py-3 flex items-center justify-between">
        <button
          onClick={onClose}
          className="p-2 rounded-full bg-white/20 hover:bg-white/30 transition"
          aria-label="Fermer"
        >
          <X className="w-5 h-5 text-primary-foreground" />
        </button>
        <div className="text-primary-foreground text-sm font-semibold">
          Course en cours · {request.customerName}
        </div>
        <div className="w-9" />
      </div>

      <div className="flex-1 relative">
        <MapContainer center={clientPos} zoom={15} scrollWheelZoom className="w-full h-full z-0">
          <TileLayer
            attribution="&copy; OpenStreetMap"
            url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
          />
          <Marker position={driverPos} icon={driverIcon} />
          {(phase === "enrouteToClient" || phase === "atClient") && (
            <Marker position={clientPos} icon={clientIcon} />
          )}
          {(phase === "enrouteToDest" || phase === "atDest") && (
            <Marker position={destPos} icon={destIcon} />
          )}
          {(phase === "enrouteToClient" || phase === "enrouteToDest") && (
            <Polyline
              positions={[driverPos, focusB]}
              pathOptions={{
                color: "hsl(138, 64%, 39%)",
                weight: 4,
                opacity: 0.75,
                dashArray: "6 8",
              }}
            />
          )}
          <FitTo a={driverPos} b={focusB} />
        </MapContainer>

        <div className="absolute top-3 left-1/2 -translate-x-1/2 bg-card/95 backdrop-blur shadow-elevated rounded-full px-4 py-1.5 text-xs font-semibold text-foreground z-[400]">
          {phase === "enrouteToClient" && `Vers le client · ${formatEta(etaSec)}`}
          {phase === "atClient" && "Arrivé au client — scan requis"}
          {phase === "enrouteToDest" && `Vers la destination · ${formatEta(etaSec)}`}
          {phase === "atDest" && "Arrivé à destination — scan requis"}
          {phase === "completed" && "Course terminée"}
        </div>
      </div>

      <motion.div layout className="bg-card rounded-t-3xl shadow-elevated p-5 pb-7">
        <AnimatePresence mode="wait">
          {phase === "enrouteToClient" && (
            <motion.div key="toClient" initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }}>
              <div className="flex items-start gap-2 mb-2">
                <MapPin className="w-4 h-4 mt-0.5 text-secondary shrink-0" />
                <div className="min-w-0">
                  <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Récupération</p>
                  <p className="text-sm font-medium text-foreground truncate">{request.pickup}</p>
                </div>
              </div>
              <Button className="w-full h-12 gradient-primary mt-2">
                <Navigation className="w-5 h-5 mr-2" /> Navigation GPS active
              </Button>
            </motion.div>
          )}

          {phase === "atClient" && (
            <motion.div key="atClient" initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }} className="text-center">
              <p className="text-xs text-muted-foreground mb-1">Faites scanner ce code par {request.customerName}</p>
              <p className="font-semibold text-foreground mb-3">QR de départ</p>
              <div className="bg-white p-3 rounded-xl inline-block">
                <QRCode value={startCode} size={160} />
              </div>
              <p className="text-[10px] text-muted-foreground mt-2 break-all">{startCode}</p>
              <Button
                onClick={() => {
                  setPhase("enrouteToDest");
                  toast.success("Client confirmé — En route vers la destination");
                }}
                className="w-full h-12 gradient-primary mt-4"
              >
                <CheckCircle2 className="w-5 h-5 mr-2" /> Client a scanné (démo)
              </Button>
            </motion.div>
          )}

          {phase === "enrouteToDest" && (
            <motion.div key="toDest" initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }}>
              <div className="flex items-start gap-2 mb-2">
                <Navigation className="w-4 h-4 mt-0.5 text-primary shrink-0" />
                <div className="min-w-0">
                  <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Destination</p>
                  <p className="text-sm font-medium text-foreground truncate">{request.destination}</p>
                </div>
              </div>
              <Button className="w-full h-12 gradient-primary mt-2">
                <Navigation className="w-5 h-5 mr-2" /> Navigation GPS active
              </Button>
            </motion.div>
          )}

          {phase === "atDest" && (
            <motion.div key="atDest" initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0 }} className="text-center">
              <p className="text-xs text-muted-foreground mb-1">Faites scanner ce code par le client pour clôturer</p>
              <p className="font-semibold text-foreground mb-3">QR de fin</p>
              <div className="bg-white p-3 rounded-xl inline-block">
                <QRCode value={endCode} size={160} />
              </div>
              <p className="text-[10px] text-muted-foreground mt-2 break-all">{endCode}</p>
              <Button
                onClick={() => {
                  setPhase("completed");
                  toast.success("Course terminée — Paiement en attente de validation");
                }}
                className="w-full h-12 gradient-primary mt-4"
              >
                <CheckCircle2 className="w-5 h-5 mr-2" /> Client a scanné (démo)
              </Button>
            </motion.div>
          )}

          {phase === "completed" && (
            <motion.div key="done" initial={{ opacity: 0, scale: 0.95 }} animate={{ opacity: 1, scale: 1 }} className="text-center py-2">
              <div className="w-16 h-16 rounded-full bg-success/15 mx-auto flex items-center justify-center mb-3">
                <CheckCircle2 className="w-9 h-9 text-success" />
              </div>
              <p className="font-semibold text-foreground">Course terminée</p>
              <p className="text-sm text-muted-foreground mb-4">
                Gain : {formatGNF(request.estimatedPrice)}
              </p>
              <Button onClick={onClose} className="w-full h-12 gradient-primary">
                Retour au tableau
              </Button>
            </motion.div>
          )}
        </AnimatePresence>
      </motion.div>
    </motion.div>
  );
}
