import { useEffect, useMemo, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { MapContainer, TileLayer, Marker, Polyline, useMap } from "react-leaflet";
import L from "leaflet";
import "leaflet/dist/leaflet.css";
import QRCode from "react-qr-code";
import { Loader2, Phone, MessageCircle, Star, ScanLine, CheckCircle2, X, QrCode } from "lucide-react";
import { Button } from "@/components/ui/button";
import { toast } from "@/hooks/use-toast";
import { supabase } from "@/integrations/supabase/client";
import { QrScanner } from "@/components/scanner/QrScanner";
import { RatingPrompt } from "@/components/tracking/RatingPrompt";

export type TrackingMode = "moto" | "toktok" | "food";

interface LiveTrackingProps {
  mode: TrackingMode;
  pickupCoords: [number, number];
  destCoords?: [number, number] | null;
  fare: number;
  onClose: () => void;
  holdId?: string | null;
  rideId?: string | null;
}

const MODE_LABELS: Record<TrackingMode, { title: string; emoji: string }> = {
  moto: { title: "Moto", emoji: "🛵" },
  toktok: { title: "TokTok", emoji: "🛺" },
  food: { title: "Repas", emoji: "🍱" },
};

const clientIcon = L.divIcon({
  className: "",
  html: `<div style="width:18px;height:18px;border-radius:9999px;background:hsl(var(--primary));border:3px solid white;box-shadow:0 2px 6px rgba(0,0,0,.3)"></div>`,
  iconSize: [18, 18],
  iconAnchor: [9, 9],
});

function makeDriverIcon(emoji: string) {
  return L.divIcon({
    className: "",
    html: `<div style="width:34px;height:34px;border-radius:9999px;background:white;border:2px solid hsl(var(--primary));display:flex;align-items:center;justify-content:center;box-shadow:0 2px 8px rgba(0,0,0,.3);font-size:18px">${emoji}</div>`,
    iconSize: [34, 34],
    iconAnchor: [17, 17],
  });
}

function FitTo({ a, b }: { a: [number, number]; b: [number, number] }) {
  const map = useMap();
  useEffect(() => {
    map.fitBounds(L.latLngBounds([a, b]), { padding: [60, 60], maxZoom: 16 });
  }, [a[0], a[1], b[0], b[1], map]);
  return null;
}

type Phase =
  | "searching"
  | "assigned"
  | "enroute"
  | "arrived"
  | "startScan"
  | "inTrip"
  | "atDestination"
  | "endScan"
  | "rating"
  | "completed";

const DRIVERS = [
  { name: "Mamadou Camara", rating: 4.9, plate: "RC-2384-A", trips: 1284 },
  { name: "Ibrahima Sow", rating: 4.8, plate: "RC-7712-B", trips: 932 },
  { name: "Aïssatou Barry", rating: 4.95, plate: "RC-1051-C", trips: 2104 },
];

export function LiveTracking({ mode, pickupCoords, destCoords, fare, onClose, holdId, rideId }: LiveTrackingProps) {
  const [phase, setPhase] = useState<Phase>("searching");
  const [driverPos, setDriverPos] = useState<[number, number]>(() => [
    pickupCoords[0] + (Math.random() - 0.5) * 0.012,
    pickupCoords[1] + (Math.random() - 0.5) * 0.012,
  ]);
  const [etaSec, setEtaSec] = useState(180);
  const [showScanner, setShowScanner] = useState<null | "start" | "end">(null);
  const [showDriverQR, setShowDriverQR] = useState<null | "start" | "end">(null);
  const tickRef = useRef<number | null>(null);
  const settledRef = useRef(false);

  const driver = useMemo(() => DRIVERS[Math.floor(Math.random() * DRIVERS.length)], []);
  const driverEmoji = mode === "moto" ? "🛵" : mode === "toktok" ? "🛺" : "🛵";
  const driverIcon = useMemo(() => makeDriverIcon(driverEmoji), [driverEmoji]);
  const tripId = useMemo(
    () => Math.random().toString(36).slice(2, 8).toUpperCase(),
    [],
  );
  const startCode = useMemo(
    () => `CHOP-START-${driver.plate.replace(/-/g, "")}-${tripId}`,
    [driver.plate, tripId],
  );
  const endCode = useMemo(
    () => `CHOP-END-${driver.plate.replace(/-/g, "")}-${tripId}`,
    [driver.plate, tripId],
  );

  // Searching → assigned
  useEffect(() => {
    if (phase !== "searching") return;
    const t = setTimeout(() => setPhase("assigned"), 2500);
    return () => clearTimeout(t);
  }, [phase]);

  // Driver moves toward client during enroute
  useEffect(() => {
    if (phase !== "enroute") return;
    tickRef.current = window.setInterval(() => {
      setDriverPos((p) => {
        const [lat, lng] = p;
        const dLat = pickupCoords[0] - lat;
        const dLng = pickupCoords[1] - lng;
        const dist = Math.hypot(dLat, dLng);
        if (dist < 0.0003) {
          setPhase("arrived");
          return pickupCoords;
        }
        return [lat + dLat * 0.08, lng + dLng * 0.08];
      });
      setEtaSec((s) => Math.max(0, s - 5));
    }, 1000);
    return () => {
      if (tickRef.current) clearInterval(tickRef.current);
    };
  }, [phase, pickupCoords]);

  // In-trip simulation: drive from pickup → destination (or timer if no dest)
  useEffect(() => {
    if (phase !== "inTrip") return;
    setEtaSec(240);
    const target = destCoords ?? [
      pickupCoords[0] + 0.01,
      pickupCoords[1] + 0.01,
    ] as [number, number];
    tickRef.current = window.setInterval(() => {
      setDriverPos((p) => {
        const [lat, lng] = p;
        const dLat = target[0] - lat;
        const dLng = target[1] - lng;
        const dist = Math.hypot(dLat, dLng);
        if (dist < 0.0003) {
          setPhase("atDestination");
          return target;
        }
        return [lat + dLat * 0.06, lng + dLng * 0.06];
      });
      setEtaSec((s) => Math.max(0, s - 5));
    }, 1000);
    return () => {
      if (tickRef.current) clearInterval(tickRef.current);
    };
  }, [phase, pickupCoords, destCoords]);

  const formatEta = (s: number) => {
    const m = Math.floor(s / 60);
    const r = s % 60;
    return `${m}:${r.toString().padStart(2, "0")}`;
  };

  const fmt = (n: number) => new Intl.NumberFormat("fr-GN").format(Math.round(n));

  const handleScanResult = (text: string) => {
    const code = text.trim().toUpperCase();
    if (showScanner === "start") {
      if (code !== startCode.toUpperCase()) {
        toast({ title: "QR invalide", description: "Ce code ne correspond pas au démarrage de votre course." });
        return;
      }
      setShowScanner(null);
      setPhase("inTrip");
      toast({ title: "Course démarrée", description: "Bon voyage avec CHOP CHOP." });
    } else if (showScanner === "end") {
      if (code !== endCode.toUpperCase()) {
        toast({ title: "QR invalide", description: "Ce code ne correspond pas à la fin de course." });
        return;
      }
      setShowScanner(null);
      setPhase("rating");
    }
  };

  const handleRatingSubmit = (rating: number, review: string) => {
    void review;
    (async () => {
      if (!settledRef.current && (rideId || holdId)) {
        settledRef.current = true;
        const { error } = rideId
          ? await supabase.rpc("ride_complete", {
              p_ride_id: rideId,
              p_actual_fare_gnf: Math.round(fare),
              p_commission_bps: 1500,
            })
          : await supabase.rpc("wallet_capture", {
              p_hold_id: holdId!,
              p_to_user_id: null,
              p_to_party_type: "master",
              p_actual_amount_gnf: Math.round(fare),
              p_description: `Course ${MODE_LABELS[mode].title}`,
            });
        if (error) {
          toast({ title: "Paiement échoué", description: error.message });
          return;
        }
      }
      setPhase("completed");
      toast({
        title: "Transaction validée",
        description: `${fmt(fare)} GNF débité · Note ${rating.toFixed(2)}★`,
      });
    })();
  };

  const handleClose = async () => {
    if (!settledRef.current && phase !== "completed" && (rideId || holdId)) {
      settledRef.current = true;
      if (rideId) {
        await supabase.rpc("ride_cancel", { p_ride_id: rideId, p_reason: "Course annulée" });
      } else {
        await supabase.rpc("wallet_release", { p_hold_id: holdId!, p_reason: "Course annulée" });
      }
      toast({ title: "Réservation libérée", description: "Aucun montant débité." });
    }
    onClose();
  };

  const driverFar: [number, number] = driverPos;

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      className="fixed inset-0 z-50 bg-background flex flex-col"
    >
      {/* Header */}
      <div className="gradient-primary px-4 py-3 flex items-center justify-between">
        <button
          onClick={handleClose}
          className="p-2 rounded-full bg-white/20 hover:bg-white/30 transition"
          aria-label="Fermer"
        >
          <X className="w-5 h-5 text-primary-foreground" />
        </button>
        <div className="text-primary-foreground text-sm font-semibold">
          {MODE_LABELS[mode].title} · Suivi en direct
        </div>
        <div className="w-9" />
      </div>

      {/* Map */}
      <div className="flex-1 relative">
        <MapContainer center={pickupCoords} zoom={15} scrollWheelZoom className="w-full h-full z-0">
          <TileLayer
            attribution="&copy; OpenStreetMap"
            url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
          />
          <Marker position={pickupCoords} icon={clientIcon} />
          {phase !== "searching" && <Marker position={driverFar} icon={driverIcon} />}
          {(phase === "enroute" || phase === "inTrip") && (
            <Polyline
              positions={[
                driverFar,
                phase === "inTrip" && destCoords ? destCoords : pickupCoords,
              ]}
              pathOptions={{ color: "hsl(138, 64%, 39%)", weight: 4, opacity: 0.7, dashArray: "6 8" }}
            />
          )}
          {phase !== "searching" && <FitTo a={pickupCoords} b={driverFar} />}
        </MapContainer>

        {/* Status pill */}
        <div className="absolute top-3 left-1/2 -translate-x-1/2 bg-card/95 backdrop-blur shadow-elevated rounded-full px-4 py-1.5 text-xs font-semibold text-foreground z-[400]">
          {phase === "searching" && "Recherche du chauffeur le plus proche…"}
          {phase === "assigned" && "Chauffeur trouvé"}
          {phase === "enroute" && `Arrivée dans ${formatEta(etaSec)}`}
          {phase === "arrived" && "Le chauffeur est arrivé"}
          {phase === "startScan" && "Scannez le QR de départ"}
          {phase === "inTrip" && `Destination dans ${formatEta(etaSec)}`}
          {phase === "atDestination" && "Vous êtes arrivés"}
          {phase === "endScan" && "Scannez le QR de fin"}
          {phase === "rating" && "Notez votre course"}
          {phase === "completed" && "Course terminée"}
        </div>
      </div>

      {/* Bottom sheet */}
      <motion.div
        layout
        className="bg-card rounded-t-3xl shadow-elevated p-5 pb-7"
      >
        <AnimatePresence mode="wait">
          {phase === "searching" && (
            <motion.div
              key="searching"
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -10 }}
              className="flex items-center gap-3"
            >
              <Loader2 className="w-6 h-6 text-primary animate-spin" />
              <div>
                <p className="font-semibold text-foreground">Notification envoyée</p>
                <p className="text-sm text-muted-foreground">
                  Recherche du chauffeur {MODE_LABELS[mode].title.toLowerCase()} le plus proche…
                </p>
              </div>
            </motion.div>
          )}

          {(phase === "assigned" || phase === "enroute" || phase === "arrived" || phase === "inTrip" || phase === "atDestination") && (
            <motion.div
              key="driver"
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -10 }}
            >
              <div className="flex items-center gap-3">
                <div className="w-14 h-14 rounded-full bg-muted flex items-center justify-center text-3xl">
                  {MODE_LABELS[mode].emoji}
                </div>
                <div className="flex-1 min-w-0">
                  <p className="font-semibold text-foreground truncate">{driver.name}</p>
                  <div className="flex items-center gap-2 text-xs text-muted-foreground">
                    <Star className="w-3 h-3 fill-secondary text-secondary" />
                    <span className="font-medium text-foreground">{driver.rating}</span>
                    <span>·</span>
                    <span>{driver.trips} courses</span>
                  </div>
                  <p className="text-xs text-muted-foreground mt-0.5">Plaque {driver.plate}</p>
                </div>
                <div className="text-right">
                  <p className="text-lg font-bold text-foreground">{fmt(fare)} GNF</p>
                  <p className="text-xs text-muted-foreground">
                    {phase === "atDestination" ? "À régler" : "Tarif fixe"}
                  </p>
                </div>
              </div>

              <div className="grid grid-cols-2 gap-2 mt-4">
                <Button variant="outline" className="h-11">
                  <Phone className="w-4 h-4 mr-2" /> Appeler
                </Button>
                <Button variant="outline" className="h-11">
                  <MessageCircle className="w-4 h-4 mr-2" /> Message
                </Button>
              </div>

              {phase === "assigned" && (
                <Button
                  onClick={() => setPhase("enroute")}
                  className="w-full h-12 mt-3 gradient-primary"
                >
                  Suivre le chauffeur
                </Button>
              )}

              {phase === "arrived" && (
                <div className="grid grid-cols-1 gap-2 mt-3">
                  <Button
                    onClick={() => {
                      setPhase("startScan");
                      setShowScanner("start");
                    }}
                    className="w-full h-12 gradient-primary"
                  >
                    <ScanLine className="w-5 h-5 mr-2" /> Scanner le QR de départ
                  </Button>
                  <Button
                    variant="outline"
                    onClick={() => setShowDriverQR("start")}
                    className="w-full h-10"
                  >
                    <QrCode className="w-4 h-4 mr-2" /> Voir le QR du chauffeur (démo)
                  </Button>
                </div>
              )}

              {phase === "atDestination" && (
                <div className="grid grid-cols-1 gap-2 mt-3">
                  <Button
                    onClick={() => {
                      setPhase("endScan");
                      setShowScanner("end");
                    }}
                    className="w-full h-12 gradient-primary"
                  >
                    <ScanLine className="w-5 h-5 mr-2" /> Scanner le QR de fin
                  </Button>
                  <Button
                    variant="outline"
                    onClick={() => setShowDriverQR("end")}
                    className="w-full h-10"
                  >
                    <QrCode className="w-4 h-4 mr-2" /> Voir le QR du chauffeur (démo)
                  </Button>
                </div>
              )}
            </motion.div>
          )}

          {phase === "rating" && (
            <RatingPrompt driverName={driver.name} onSubmit={handleRatingSubmit} />
          )}

          {phase === "completed" && (
            <motion.div
              key="done"
              initial={{ opacity: 0, scale: 0.9 }}
              animate={{ opacity: 1, scale: 1 }}
              className="text-center py-2"
            >
              <div className="w-16 h-16 rounded-full bg-success/15 mx-auto flex items-center justify-center mb-3">
                <CheckCircle2 className="w-9 h-9 text-success" />
              </div>
              <p className="font-semibold text-foreground">Transaction terminée</p>
              <p className="text-sm text-muted-foreground mb-4">
                Merci d'avoir voyagé avec CHOP CHOP
              </p>
              <Button onClick={onClose} className="w-full h-12 gradient-primary">
                Retour à l'accueil
              </Button>
            </motion.div>
          )}
        </AnimatePresence>
      </motion.div>

      {/* Camera scanner overlay */}
      {showScanner && (
        <QrScanner
          title={showScanner === "start" ? "Scanner le QR de départ" : "Scanner le QR de fin"}
          subtitle={`Chauffeur ${driver.name} · ${driver.plate}`}
          expectedHint={showScanner === "start" ? startCode : endCode}
          onResult={handleScanResult}
          onClose={() => {
            setShowScanner(null);
            // revert to previous step if cancelled
            setPhase((p) => (p === "startScan" ? "arrived" : p === "endScan" ? "atDestination" : p));
          }}
        />
      )}

      {/* Demo driver QR (would normally be on the driver phone) */}
      {showDriverQR && (
        <div
          className="fixed inset-0 z-[55] bg-black/70 flex items-center justify-center p-6"
          onClick={() => setShowDriverQR(null)}
        >
          <div className="bg-card rounded-2xl p-6 max-w-xs w-full text-center" onClick={(e) => e.stopPropagation()}>
            <p className="text-xs text-muted-foreground mb-1">Écran chauffeur (démo)</p>
            <p className="font-semibold text-foreground mb-4">
              QR {showDriverQR === "start" ? "de départ" : "de fin"}
            </p>
            <div className="bg-white p-3 rounded-xl inline-block">
              <QRCode value={showDriverQR === "start" ? startCode : endCode} size={180} />
            </div>
            <p className="text-[10px] text-muted-foreground mt-3 break-all">
              {showDriverQR === "start" ? startCode : endCode}
            </p>
            <Button variant="outline" className="w-full mt-4" onClick={() => setShowDriverQR(null)}>
              Fermer
            </Button>
          </div>
        </div>
      )}
    </motion.div>
  );
}
