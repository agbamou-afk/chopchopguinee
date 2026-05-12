import { motion } from "framer-motion";
import { MapPin, Navigation, X, Bike, Car, Clock, CreditCard, Loader2, LocateFixed } from "lucide-react";
import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { MapContainer, TileLayer, Marker, useMap } from "react-leaflet";
import L from "leaflet";
import "leaflet/dist/leaflet.css";
import { toast } from "@/hooks/use-toast";

// Fix default marker icon paths (Leaflet+bundlers issue)
const pickupIcon = L.divIcon({
  className: "",
  html: `<div style="width:18px;height:18px;border-radius:9999px;background:hsl(var(--primary));border:3px solid white;box-shadow:0 2px 6px rgba(0,0,0,.3)"></div>`,
  iconSize: [18, 18],
  iconAnchor: [9, 9],
});

function Recenter({ position }: { position: [number, number] }) {
  const map = useMap();
  useEffect(() => {
    map.flyTo(position, 15, { duration: 0.8 });
  }, [position, map]);
  return null;
}

interface RideBookingProps {
  type: "moto" | "toktok";
  onClose: () => void;
  onBook: () => void;
}

const rideOptions = {
  moto: {
    title: "Moto",
    icon: Bike,
    basePrice: 5000,
    pricePerKm: 1000,
    eta: "3-5 min",
  },
  toktok: {
    title: "TokTok",
    icon: Car,
    basePrice: 8000,
    pricePerKm: 1500,
    eta: "5-8 min",
  },
};

export function RideBooking({ type, onClose, onBook }: RideBookingProps) {
  const [pickup, setPickup] = useState("");
  const [destination, setDestination] = useState("");
  // Default: Conakry, Guinea
  const [pickupCoords, setPickupCoords] = useState<[number, number]>([9.6412, -13.5784]);
  const [locating, setLocating] = useState(false);
  const option = rideOptions[type];
  const Icon = option.icon;

  const handleLocateMe = () => {
    if (!navigator.geolocation) {
      toast({ title: "Géolocalisation indisponible", description: "Votre navigateur ne supporte pas la géolocalisation." });
      return;
    }
    setLocating(true);
    navigator.geolocation.getCurrentPosition(
      async (pos) => {
        const coords: [number, number] = [pos.coords.latitude, pos.coords.longitude];
        setPickupCoords(coords);
        try {
          const res = await fetch(
            `https://nominatim.openstreetmap.org/reverse?format=json&lat=${coords[0]}&lon=${coords[1]}&zoom=16`,
          );
          const data = await res.json();
          setPickup(data.display_name?.split(",").slice(0, 2).join(",") ?? "Ma position");
        } catch {
          setPickup("Ma position");
        }
        setLocating(false);
      },
      () => {
        setLocating(false);
        toast({ title: "Position introuvable", description: "Veuillez autoriser la géolocalisation." });
      },
      { enableHighAccuracy: true, timeout: 10000 },
    );
  };

  const estimatedPrice = option.basePrice + option.pricePerKm * 5; // Assuming 5km

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      className="fixed inset-0 bg-background z-50 flex flex-col"
    >
      {/* Header */}
      <div className="gradient-primary p-4 pb-8 rounded-b-3xl">
        <div className="flex items-center justify-between mb-6">
          <button
            onClick={onClose}
            className="p-2 rounded-full bg-white/20 hover:bg-white/30 transition-colors"
          >
            <X className="w-5 h-5 text-primary-foreground" />
          </button>
          <h1 className="text-lg font-bold text-primary-foreground">Réserver un {option.title}</h1>
          <div className="w-9" />
        </div>

        <div className="bg-white/10 backdrop-blur-sm rounded-2xl p-4">
          <div className="flex items-center gap-3 pb-4 border-b border-white/20">
            <div className="w-3 h-3 rounded-full bg-primary-foreground" />
            <input
              type="text"
              placeholder="Point de départ"
              value={pickup}
              onChange={(e) => setPickup(e.target.value)}
              className="flex-1 bg-transparent text-primary-foreground placeholder:text-white/60 focus:outline-none"
            />
            <button
              type="button"
              onClick={handleLocateMe}
              disabled={locating}
              aria-label="Utiliser ma position actuelle"
              className="p-1.5 rounded-full bg-white/20 hover:bg-white/30 active:scale-95 transition"
            >
              {locating ? (
                <Loader2 className="w-4 h-4 text-primary-foreground animate-spin" />
              ) : (
                <LocateFixed className="w-4 h-4 text-primary-foreground" />
              )}
            </button>
          </div>
          <div className="flex items-center gap-3 pt-4">
            <div className="w-3 h-3 rounded-full bg-secondary" />
            <input
              type="text"
              placeholder="Destination"
              value={destination}
              onChange={(e) => setDestination(e.target.value)}
              className="flex-1 bg-transparent text-primary-foreground placeholder:text-white/60 focus:outline-none"
            />
            <Navigation className="w-5 h-5 text-white/60" />
          </div>
        </div>
      </div>

      {/* Interactive map */}
      <div className="flex-1 bg-muted relative overflow-hidden">
        <MapContainer
          center={pickupCoords}
          zoom={14}
          scrollWheelZoom
          className="w-full h-full z-0"
        >
          <TileLayer
            attribution='&copy; OpenStreetMap'
            url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
          />
          <Marker
            position={pickupCoords}
            icon={pickupIcon}
            draggable
            eventHandlers={{
              dragend: (e) => {
                const m = e.target as L.Marker;
                const ll = m.getLatLng();
                setPickupCoords([ll.lat, ll.lng]);
              },
            }}
          />
          <Recenter position={pickupCoords} />
        </MapContainer>
        <button
          type="button"
          onClick={handleLocateMe}
          disabled={locating}
          aria-label="Centrer sur ma position"
          className="absolute bottom-4 right-4 z-[400] w-12 h-12 rounded-full bg-card shadow-elevated flex items-center justify-center active:scale-95 transition"
        >
          {locating ? (
            <Loader2 className="w-5 h-5 text-primary animate-spin" />
          ) : (
            <LocateFixed className="w-5 h-5 text-primary" />
          )}
        </button>
      </div>

      {/* Bottom sheet */}
      <motion.div
        initial={{ y: 100 }}
        animate={{ y: 0 }}
        className="bg-card rounded-t-3xl p-6 shadow-elevated"
      >
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-xl gradient-primary">
              <Icon className="w-6 h-6 text-primary-foreground" />
            </div>
            <div>
              <h3 className="font-semibold text-foreground">{option.title}</h3>
              <div className="flex items-center gap-2 text-sm text-muted-foreground">
                <Clock className="w-4 h-4" />
                <span>{option.eta}</span>
              </div>
            </div>
          </div>
          <div className="text-right">
            <p className="text-lg font-bold text-foreground">
              {new Intl.NumberFormat("fr-GN").format(estimatedPrice)} GNF
            </p>
            <p className="text-xs text-muted-foreground">Estimation</p>
          </div>
        </div>

        <div className="flex items-center gap-2 p-3 bg-muted rounded-xl mb-4">
          <CreditCard className="w-5 h-5 text-muted-foreground" />
          <span className="text-sm text-foreground">Portefeuille CHOP CHOP</span>
          <span className="ml-auto text-sm font-medium text-primary">Changer</span>
        </div>

        <Button
          onClick={onBook}
          className="w-full h-14 text-lg font-semibold gradient-primary hover:opacity-90 transition-opacity"
        >
          Confirmer la course
        </Button>
      </motion.div>
    </motion.div>
  );
}
