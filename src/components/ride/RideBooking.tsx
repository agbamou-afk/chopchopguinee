import { motion } from "framer-motion";
import { MapPin, Navigation, X, Bike, Car, Clock, CreditCard, Loader2, LocateFixed } from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { MapContainer, TileLayer, Marker, Polyline, useMap } from "react-leaflet";
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

const destIcon = L.divIcon({
  className: "",
  html: `<div style="width:18px;height:18px;border-radius:9999px;background:hsl(var(--secondary));border:3px solid white;box-shadow:0 2px 6px rgba(0,0,0,.3)"></div>`,
  iconSize: [18, 18],
  iconAnchor: [9, 9],
});

const driverIcon = L.divIcon({
  className: "",
  html: `<div style="width:28px;height:28px;border-radius:9999px;background:white;border:2px solid hsl(var(--primary));display:flex;align-items:center;justify-content:center;box-shadow:0 2px 6px rgba(0,0,0,.25);font-size:14px">🛵</div>`,
  iconSize: [28, 28],
  iconAnchor: [14, 14],
});

function Recenter({ position }: { position: [number, number] }) {
  const map = useMap();
  useEffect(() => {
    map.flyTo(position, 15, { duration: 0.8 });
  }, [position, map]);
  return null;
}

function FitBounds({ a, b }: { a: [number, number]; b: [number, number] | null }) {
  const map = useMap();
  useEffect(() => {
    if (!b) return;
    const bounds = L.latLngBounds([a, b]);
    map.fitBounds(bounds, { padding: [60, 60], maxZoom: 15 });
  }, [a, b, map]);
  return null;
}

interface Suggestion {
  label: string;
  sub: string;
  coords: [number, number];
  kind: string;
}

const POI_KEYWORDS = ["rond-point", "marché", "carrefour", "commune", "quartier", "place"];

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
    speedKmh: 28,
  },
  toktok: {
    title: "TokTok",
    icon: Car,
    basePrice: 8000,
    pricePerKm: 1500,
    eta: "5-8 min",
    speedKmh: 22,
  },
};

export function RideBooking({ type, onClose, onBook }: RideBookingProps) {
  const [pickup, setPickup] = useState("");
  const [destination, setDestination] = useState("");
  // Default: Conakry, Guinea
  const [pickupCoords, setPickupCoords] = useState<[number, number]>([9.6412, -13.5784]);
  const [destCoords, setDestCoords] = useState<[number, number] | null>(null);
  const [locating, setLocating] = useState(false);
  const [activeField, setActiveField] = useState<"pickup" | "destination" | null>(null);
  const [suggestions, setSuggestions] = useState<Suggestion[]>([]);
  const [searching, setSearching] = useState(false);
  const [route, setRoute] = useState<[number, number][]>([]);
  const [distanceKm, setDistanceKm] = useState<number | null>(null);
  const [durationMin, setDurationMin] = useState<number | null>(null);
  const debounceRef = useRef<number | null>(null);
  const option = rideOptions[type];
  const Icon = option.icon;

  // Mock 4 nearby drivers within ~800m of pickup
  const drivers = useMemo(() => {
    const list: [number, number][] = [];
    for (let i = 0; i < 4; i++) {
      const dLat = (Math.random() - 0.5) * 0.012;
      const dLng = (Math.random() - 0.5) * 0.012;
      list.push([pickupCoords[0] + dLat, pickupCoords[1] + dLng]);
    }
    return list;
    // re-roll when pickup changes meaningfully
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pickupCoords[0].toFixed(3), pickupCoords[1].toFixed(3)]);

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

  // Search Nominatim biased around pickup
  const runSearch = async (q: string) => {
    setSearching(true);
    try {
      const [lat, lng] = pickupCoords;
      const delta = 0.25;
      const viewbox = `${lng - delta},${lat + delta},${lng + delta},${lat - delta}`;
      const query = q.trim().length < 2 ? POI_KEYWORDS.join(" OR ") : q;
      const url = `https://nominatim.openstreetmap.org/search?format=json&addressdetails=1&limit=8&countrycodes=gn&viewbox=${viewbox}&bounded=1&q=${encodeURIComponent(query)}`;
      const res = await fetch(url, { headers: { "Accept-Language": "fr" } });
      const data = await res.json();
      const items: Suggestion[] = (data as Array<Record<string, unknown>>).map((d) => {
        const a = (d.address ?? {}) as Record<string, string>;
        const sub = [a.suburb, a.city_district, a.city, a.town, a.village, a.county]
          .filter(Boolean)
          .slice(0, 2)
          .join(" • ");
        return {
          label: (d.name as string) || (d.display_name as string).split(",")[0],
          sub: sub || (d.display_name as string).split(",").slice(1, 3).join(", "),
          coords: [parseFloat(d.lat as string), parseFloat(d.lon as string)],
          kind: (d.type as string) ?? "",
        };
      });
      setSuggestions(items);
    } catch {
      setSuggestions([]);
    } finally {
      setSearching(false);
    }
  };

  // Debounced search on input change
  useEffect(() => {
    if (!activeField) return;
    const q = activeField === "pickup" ? pickup : destination;
    if (debounceRef.current) window.clearTimeout(debounceRef.current);
    debounceRef.current = window.setTimeout(() => runSearch(q), 300);
    return () => {
      if (debounceRef.current) window.clearTimeout(debounceRef.current);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pickup, destination, activeField]);

  const pickSuggestion = (s: Suggestion) => {
    if (activeField === "pickup") {
      setPickup(s.label);
      setPickupCoords(s.coords);
    } else if (activeField === "destination") {
      setDestination(s.label);
      setDestCoords(s.coords);
    }
    setSuggestions([]);
    setActiveField(null);
  };

  // Fetch route when both ends set
  useEffect(() => {
    if (!destCoords) {
      setRoute([]);
      setDistanceKm(null);
      setDurationMin(null);
      return;
    }
    const [a, b] = [pickupCoords, destCoords];
    const url = `https://router.project-osrm.org/route/v1/driving/${a[1]},${a[0]};${b[1]},${b[0]}?overview=full&geometries=geojson`;
    fetch(url)
      .then((r) => r.json())
      .then((data) => {
        const r0 = data.routes?.[0];
        if (!r0) return;
        const coords: [number, number][] = r0.geometry.coordinates.map(
          (c: [number, number]) => [c[1], c[0]],
        );
        setRoute(coords);
        const km = r0.distance / 1000;
        setDistanceKm(km);
        setDurationMin(Math.max(2, Math.round((km / option.speedKmh) * 60)));
      })
      .catch(() => {});
  }, [pickupCoords, destCoords, option.speedKmh]);

  const estimatedPrice = option.basePrice + option.pricePerKm * (distanceKm ?? 5);

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

        <div className="bg-white/10 backdrop-blur-sm rounded-2xl p-4 relative">
          <div className="flex items-center gap-3 pb-4 border-b border-white/20">
            <div className="w-3 h-3 rounded-full bg-primary-foreground" />
            <input
              type="text"
              placeholder="Point de départ"
              value={pickup}
              onChange={(e) => setPickup(e.target.value)}
              onFocus={() => { setActiveField("pickup"); runSearch(pickup); }}
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
              onFocus={() => { setActiveField("destination"); runSearch(destination); }}
              className="flex-1 bg-transparent text-primary-foreground placeholder:text-white/60 focus:outline-none"
            />
            <Navigation className="w-5 h-5 text-white/60" />
          </div>

          {activeField && (
            <div className="absolute left-0 right-0 top-full mt-2 mx-2 bg-card text-foreground rounded-2xl shadow-elevated max-h-72 overflow-y-auto z-[500]">
              {searching && (
                <div className="flex items-center gap-2 p-3 text-sm text-muted-foreground">
                  <Loader2 className="w-4 h-4 animate-spin" /> Recherche…
                </div>
              )}
              {!searching && suggestions.length === 0 && (
                <div className="p-3 text-sm text-muted-foreground">
                  Tapez un rond-point, marché, commune ou quartier
                </div>
              )}
              {suggestions.map((s, i) => (
                <button
                  key={i}
                  type="button"
                  onClick={() => pickSuggestion(s)}
                  className="w-full flex items-start gap-3 p-3 hover:bg-muted text-left border-b last:border-b-0 border-border/60"
                >
                  <MapPin className="w-4 h-4 mt-0.5 text-primary shrink-0" />
                  <div className="min-w-0">
                    <p className="text-sm font-medium truncate">{s.label}</p>
                    {s.sub && <p className="text-xs text-muted-foreground truncate">{s.sub}</p>}
                  </div>
                </button>
              ))}
              <button
                type="button"
                onClick={() => setActiveField(null)}
                className="w-full p-2 text-xs text-muted-foreground hover:bg-muted"
              >
                Fermer
              </button>
            </div>
          )}
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
          {destCoords && <Marker position={destCoords} icon={destIcon} />}
          {drivers.map((d, i) => (
            <Marker key={i} position={d} icon={driverIcon} />
          ))}
          {route.length > 0 && (
            <Polyline
              positions={route}
              pathOptions={{ color: "hsl(138, 64%, 39%)", weight: 5, opacity: 0.85 }}
            />
          )}
          {destCoords ? (
            <FitBounds a={pickupCoords} b={destCoords} />
          ) : (
            <Recenter position={pickupCoords} />
          )}
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
        <div className="absolute top-4 left-4 z-[400] bg-card/95 backdrop-blur shadow-card rounded-full px-3 py-1.5 text-xs font-medium text-foreground">
          {drivers.length} chauffeurs à proximité
        </div>
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
                <span>
                  {durationMin ? `${durationMin} min` : option.eta}
                  {distanceKm ? ` • ${distanceKm.toFixed(1)} km` : ""}
                </span>
              </div>
            </div>
          </div>
          <div className="text-right">
            <p className="text-lg font-bold text-foreground">
              {new Intl.NumberFormat("fr-GN").format(Math.round(estimatedPrice))} GNF
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
