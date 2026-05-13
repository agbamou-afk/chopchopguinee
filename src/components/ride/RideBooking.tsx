import { motion } from "framer-motion";
import { formatGNF } from "@/lib/format";
import { MapPin, Navigation, X, Bike, Car, Clock, CreditCard, Loader2, LocateFixed, CheckCircle2 } from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { Marker } from "react-map-gl";
import { toast } from "@/hooks/use-toast";
import { supabase } from "@/integrations/supabase/client";
import { ChopMap, type ChopMapHandle, MapMarker, PinSet, RoutePolyline, DriverCluster } from "@/components/map";
import { RoutingService, decodePolyline, bbox as bboxOf, formatDistance, formatDuration } from "@/lib/maps";
import { EtaPricePreview } from "@/components/booking/EtaPricePreview";

function haversineKm(a: [number, number], b: [number, number]): number {
  const R = 6371;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(b[0] - a[0]);
  const dLng = toRad(b[1] - a[1]);
  const h = Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a[0])) * Math.cos(toRad(b[0])) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
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
  onBook: (trip: { pickupCoords: [number, number]; destCoords: [number, number]; fare: number }) => void;
  /** Prefilled destination text (the user still confirms via search). */
  initialDestination?: string;
}

const rideOptions = {
  moto: {
    title: "Moto",
    icon: Bike,
    eta: "3-5 min",
    speedKmh: 28,
  },
  toktok: {
    title: "TokTok",
    icon: Car,
    eta: "5-8 min",
    speedKmh: 22,
  },
};

export function RideBooking({ type, onClose, onBook, initialDestination }: RideBookingProps) {
  const [pickup, setPickup] = useState("");
  const [destination, setDestination] = useState(initialDestination ?? "");
  // Default: Conakry, Guinea
  const [pickupCoords, setPickupCoords] = useState<[number, number]>([9.6412, -13.5784]);
  const [destCoords, setDestCoords] = useState<[number, number] | null>(null);
  const [locating, setLocating] = useState(false);
  const [activeField, setActiveField] = useState<"pickup" | "destination" | null>(null);
  const [suggestions, setSuggestions] = useState<Suggestion[]>([]);
  const [searching, setSearching] = useState(false);
  const [routePolyline, setRoutePolyline] = useState<string | null>(null);
  const [distanceKm, setDistanceKm] = useState<number | null>(null);
  const [durationMin, setDurationMin] = useState<number | null>(null);
  const [confirmed, setConfirmed] = useState(false);
  const [routing, setRouting] = useState(false);
  const [routeError, setRouteError] = useState<string | null>(null);
  const [fare, setFare] = useState<{ base: number; perKm: number; currency: string }>({
    base: type === "moto" ? 5000 : 8000,
    perKm: type === "moto" ? 1000 : 1500,
    currency: "GNF",
  });
  const debounceRef = useRef<number | null>(null);
  const mapRef = useRef<ChopMapHandle>(null);
  const option = rideOptions[type];
  const Icon = option.icon;

  // Load admin-managed fare for this ride type
  useEffect(() => {
    supabase
      .from("fare_settings")
      .select("base_price, price_per_km, currency")
      .eq("ride_type", type)
      .maybeSingle()
      .then(({ data }) => {
        if (data) setFare({ base: Number(data.base_price), perKm: Number(data.price_per_km), currency: data.currency });
      });
  }, [type]);

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

  // Fetch route via RoutingService (Google Directions proxy) when both ends are set
  useEffect(() => {
    if (!destCoords) {
      setRoutePolyline(null);
      setDistanceKm(null);
      setDurationMin(null);
      setRouteError(null);
      return;
    }
    let cancelled = false;
    setRouting(true);
    setRouteError(null);
    RoutingService.route(
      { lat: pickupCoords[0], lng: pickupCoords[1] },
      { lat: destCoords[0], lng: destCoords[1] },
      type === "moto" ? "two_wheeler" : "driving",
    )
      .then((r) => {
        if (cancelled) return;
        setRoutePolyline(r.polyline);
        setDistanceKm(r.distanceM / 1000);
        setDurationMin(Math.max(1, Math.round(r.durationS / 60)));
        // Fit map to route bounds
        const ne = r.bbox.northeast, sw = r.bbox.southwest;
        mapRef.current?.fitBounds([sw.lng, sw.lat, ne.lng, ne.lat], 80);
      })
      .catch((e) => {
        if (cancelled) return;
        setRouteError(e?.message ?? "Itinéraire indisponible");
        // Fallback: straight-line estimate so the user still sees a price
        const km = haversineKm(pickupCoords, destCoords);
        setDistanceKm(km);
        setDurationMin(Math.max(2, Math.round((km / option.speedKmh) * 60)));
      })
      .finally(() => { if (!cancelled) setRouting(false); });
    return () => { cancelled = true; };
  }, [pickupCoords, destCoords, type, option.speedKmh]);

  // Recenter map when pickup changes alone (no destination yet)
  useEffect(() => {
    if (!destCoords) {
      mapRef.current?.flyTo(pickupCoords[1], pickupCoords[0], 14);
    }
  }, [pickupCoords, destCoords]);

  const estimatedPrice = fare.base + fare.perKm * (distanceKm ?? 5);

  const previewState: "idle" | "calculating" | "ready" | "unavailable" | "network" =
    !destCoords ? "idle"
    : routing ? "calculating"
    : routeError && distanceKm == null ? "unavailable"
    : routeError ? "network"
    : distanceKm != null ? "ready"
    : "calculating";
  const fareLow = Math.round(estimatedPrice * 0.95);
  const fareHigh = Math.round(estimatedPrice * 1.1);

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      className="fixed inset-0 bg-background z-50 flex flex-col"
    >
      {/* Header */}
      <div className="gradient-primary p-4 pb-8 rounded-b-3xl relative z-[1000]">
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

        <div className="bg-white/10 backdrop-blur-sm rounded-2xl p-4 relative z-[1100]">
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
            <div className="absolute left-2 right-2 top-full mt-2 bg-card text-foreground rounded-2xl shadow-elevated max-h-72 overflow-y-auto z-[1200] ring-1 ring-border">
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
        <ChopMap
          ref={mapRef}
          className="absolute inset-0 w-full h-full"
          initialView={{ longitude: pickupCoords[1], latitude: pickupCoords[0], zoom: 14 }}
        >
          {routePolyline && <RoutePolyline encoded={routePolyline} />}
          <DriverCluster variant={type === "toktok" ? "toktok" : "moto"} />
          {/* Draggable pickup */}
          <Marker
            longitude={pickupCoords[1]}
            latitude={pickupCoords[0]}
            anchor="bottom"
            draggable
            onDragEnd={(e) => setPickupCoords([e.lngLat.lat, e.lngLat.lng])}
          >
            <MapMarker variant="pickup" pulse={!destCoords} label="Départ" size={36} />
          </Marker>
          {destCoords && (
            <PinSet dropoff={{ lat: destCoords[0], lng: destCoords[1] }} pulseActive="dropoff" />
          )}
        </ChopMap>
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
        {routing && (
          <div className="absolute top-4 left-4 z-[400] bg-card/95 backdrop-blur shadow-card rounded-full px-3 py-1.5 text-xs font-medium text-foreground flex items-center gap-2">
            <Loader2 className="w-3.5 h-3.5 animate-spin text-primary" />
            Calcul de l'itinéraire…
          </div>
        )}
        {!routing && distanceKm !== null && durationMin !== null && (
          <div className="absolute top-4 left-4 z-[400] bg-card/95 backdrop-blur shadow-card rounded-full px-3 py-1.5 text-xs font-medium text-foreground">
            {formatDuration(durationMin * 60)} • {formatDistance((distanceKm ?? 0) * 1000)}
          </div>
        )}
        {routeError && (
          <div className="absolute top-14 left-4 z-[400] bg-destructive/10 text-destructive shadow-card rounded-full px-3 py-1 text-[11px]">
            Itinéraire estimé
          </div>
        )}
      </div>

      {/* Bottom sheet */}
      <motion.div
        initial={{ y: 100 }}
        animate={{ y: 0 }}
        className="bg-card rounded-t-3xl p-5 pb-6 shadow-elevated space-y-4"
      >
        <EtaPricePreview
          state={previewState}
          serviceType={type}
          durationS={durationMin != null ? durationMin * 60 : undefined}
          distanceM={distanceKm != null ? distanceKm * 1000 : undefined}
          fareLowGnf={previewState === "ready" ? fareLow : undefined}
          fareHighGnf={previewState === "ready" ? fareHigh : undefined}
          paymentMethod="wallet"
          onRetry={() => destCoords && setDestCoords([...destCoords] as [number, number])}
        />

        {!confirmed ? (
          <Button
            onClick={() => {
              if (!destCoords) {
                toast({ title: "Choisissez une destination" });
                return;
              }
              setConfirmed(true);
              toast({ title: "Itinéraire confirmé", description: "Le tarif appliqué est défini par l'administrateur." });
            }}
            className="w-full h-14 text-lg font-semibold gradient-primary hover:opacity-90 transition-opacity"
          >
            <CheckCircle2 className="w-5 h-5 mr-2" /> Confirmer l'itinéraire
          </Button>
        ) : (
          <Button
            onClick={() => destCoords && onBook({ pickupCoords, destCoords, fare: estimatedPrice })}
            className="w-full h-14 text-lg font-semibold gradient-primary hover:opacity-90 transition-opacity"
          >
            Réserver pour {formatGNF(Math.round(estimatedPrice))}
          </Button>
        )}
      </motion.div>
    </motion.div>
  );
}
