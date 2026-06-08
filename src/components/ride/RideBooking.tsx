import { motion } from "framer-motion";
import { formatGNF } from "@/lib/format";
import { MapPin, Navigation, X, Bike, Car, Loader2, LocateFixed, CheckCircle2, Map as MapIcon } from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { toast } from "@/hooks/use-toast";
import { supabase } from "@/integrations/supabase/client";
import { ChopMap, type ChopMapHandle, RoutePolyline, NearbyAvailableDrivers, DraggablePickupPin } from "@/components/map";
import { Marker } from "react-map-gl";
import { MapMarker } from "@/components/map/MapMarker";
import { RoutingService, formatDistance, formatDuration, searchPlaces, reverseGeocode } from "@/lib/maps";
import { EtaPricePreview } from "@/components/booking/EtaPricePreview";
import { searchConakryPlaces, categoryLabel, confidenceLabel } from "@/lib/locations/searchPlaces";
import { useLiveUserLocation, CONAKRY_FALLBACK } from "@/lib/location/useLiveUserLocation";
import { logLocationSearchEvent } from "@/lib/locations/locationSearchTelemetry";

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
  source?: 'gazetteer' | 'nominatim' | 'google';
  placeId?: string;
  confidenceLabel?: string | null;
  category?: string;
  district?: string | null;
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
  // Pickup is intentionally null until we have either a real GPS fix or the
  // user picks a place. The Conakry fallback is ONLY a visual map center —
  // never a pickup coordinate (see CHOPCHOP_MAP_STRATEGY.md).
  const live = useLiveUserLocation();
  const [pickupCoords, setPickupCoords] = useState<[number, number] | null>(null);
  const [pickupIsReal, setPickupIsReal] = useState(false);
  const [destCoords, setDestCoords] = useState<[number, number] | null>(null);
  const [locating, setLocating] = useState(false);
  const [activeField, setActiveField] = useState<"pickup" | "destination" | null>(null);
  // When set, the next map tap assigns to this field. Survives blur so the
  // user can dismiss the keyboard and tap the map.
  const [mapPickMode, setMapPickMode] = useState<"pickup" | "destination" | null>(null);
  const [searchUnavailable, setSearchUnavailable] = useState(false);
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

  // Reverse-geocode through the backend (Google → Nominatim). Always returns
  // a usable label so map taps never appear to fail.
  const reverseLabel = async (lat: number, lng: number): Promise<string> => {
    const r = await reverseGeocode(lat, lng);
    return r?.label ?? "Position sélectionnée";
  };

  const handleMapTap = async ({ lat, lng }: { lat: number; lng: number }) => {
    // Priority: explicit "choose on map" mode > focused input > first-empty heuristic.
    const target = mapPickMode ?? activeField ?? (!pickupCoords ? "pickup" : "destination");
    if (target === "pickup") {
      setPickupCoords([lat, lng]);
      setPickupIsReal(true);
      const label = await reverseLabel(lat, lng);
      setPickup(label);
      setActiveField(null);
      setMapPickMode(null);
      return;
    }
    setDestCoords([lat, lng]);
    const label = await reverseLabel(lat, lng);
    setDestination(label);
    setActiveField(null);
    setMapPickMode(null);
  };

  // Visual map center — falls back to Conakry but is never sent as pickup.
  const mapCenter: [number, number] = pickupCoords
    ? pickupCoords
    : live.coords
      ? [live.coords.lat, live.coords.lng]
      : [CONAKRY_FALLBACK.lat, CONAKRY_FALLBACK.lng];

  // Auto-prefill pickup from live GPS the first time we get a real fix.
  useEffect(() => {
    if (pickupCoords) return;
    if (live.isRealLocation && live.coords) {
      setPickupCoords([live.coords.lat, live.coords.lng]);
      setPickupIsReal(true);
      if (!pickup) setPickup("Ma position");
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [live.isRealLocation, live.coords?.lat, live.coords?.lng]);

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
        setPickupIsReal(true);
        setPickup(await reverseLabel(coords[0], coords[1]) || "Ma position");
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
    setSearchUnavailable(false);
    try {
      // 1) Local Conakry gazetteer first — handles "km5", "kippe", "hamdalaye", etc.
      const local = searchConakryPlaces(q, { limit: 6 }).filter(
        (p) => p.latitude != null && p.longitude != null,
      );
      const localItems: Suggestion[] = local.map((p) => ({
        label: p.name,
        sub: [p.commune, categoryLabel(p.category)].filter(Boolean).join(' · '),
        coords: [p.latitude as number, p.longitude as number],
        kind: p.category,
        source: 'gazetteer',
        placeId: p.id,
        confidenceLabel: confidenceLabel(p.confidence),
        category: categoryLabel(p.category),
        district: p.commune,
      }));
      // 2) Backend provider search (Google → Nominatim fallback). Never exposes keys.
      let remote: Suggestion[] = [];
      if (q.trim().length >= 2) {
        const proximity = pickupCoords
          ? { lat: pickupCoords[0], lng: pickupCoords[1] }
          : live.coords
            ? { lat: live.coords.lat, lng: live.coords.lng }
            : undefined;
        const { results, provider } = await searchPlaces(q, { proximity, limit: 8 });
        if (provider === 'error') setSearchUnavailable(true);
        remote = results.map((r) => ({
          label: r.label,
          sub: r.secondary_label ?? '',
          coords: [r.lat, r.lng],
          kind: r.category ?? '',
          source: r.source,
          placeId: r.id,
          confidenceLabel: r.confidence === 'approximate' ? 'Position approximative' : null,
        }));
      }
      const localLabels = new Set(localItems.map((i) => i.label.toLowerCase()));
      setSuggestions([...localItems, ...remote.filter((r) => !localLabels.has(r.label.toLowerCase()))]);
    } catch {
      // Network failure — still surface gazetteer matches and offer manual pin.
      setSearchUnavailable(true);
      const local = searchConakryPlaces(q, { limit: 6 }).filter(
        (p) => p.latitude != null && p.longitude != null,
      );
      setSuggestions(local.map((p) => ({
        label: p.name,
        sub: [p.commune, categoryLabel(p.category)].filter(Boolean).join(' · '),
        coords: [p.latitude as number, p.longitude as number],
        kind: p.category,
        source: 'gazetteer',
        placeId: p.id,
        confidenceLabel: confidenceLabel(p.confidence),
        category: categoryLabel(p.category),
        district: p.commune,
      })));
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
      setPickupIsReal(true);
    } else if (activeField === "destination") {
      setDestination(s.label);
      setDestCoords(s.coords);
    }
    // Discrete telemetry — never blocks selection
    logLocationSearchEvent({
      query: activeField === 'pickup' ? pickup : destination,
      context: activeField === 'pickup' ? 'pickup' : 'dropoff',
      selected_place_id: s.placeId ?? null,
      selected_label: s.label,
      selected_source: s.source ?? 'typed',
      district: s.district ?? null,
      latitude: s.coords[0], longitude: s.coords[1],
      confidence: s.confidenceLabel ? 'approximate' : null,
    });
    setSuggestions([]);
    setActiveField(null);
  };

  // Fetch route via RoutingService (Google Directions proxy) when both ends are set
  useEffect(() => {
    if (!destCoords || !pickupCoords) {
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
        // Fit map to route bounds (some providers omit bbox; tolerate that).
        if (r.bbox) {
          const ne = r.bbox.northeast, sw = r.bbox.southwest;
          mapRef.current?.fitBounds([sw.lng, sw.lat, ne.lng, ne.lat], 80);
        }
      })
      .catch((e) => {
        if (cancelled) return;
        setRouteError(e?.message ?? "Itinéraire indisponible");
        // Fallback: straight-line estimate so the user still sees a price
        const km = haversineKm(pickupCoords!, destCoords);
        setDistanceKm(km);
        setDurationMin(Math.max(2, Math.round((km / option.speedKmh) * 60)));
      })
      .finally(() => { if (!cancelled) setRouting(false); });
    return () => { cancelled = true; };
  }, [pickupCoords, destCoords, type, option.speedKmh]);

  // Recenter map when pickup changes alone (no destination yet)
  useEffect(() => {
    if (!destCoords && pickupCoords) {
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
                  Tapez un rond-point, marché, KM, commune ou quartier
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
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2">
                      <p className="text-sm font-medium truncate">{s.label}</p>
                      {s.source === 'gazetteer' && (
                        <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-primary/10 text-primary shrink-0">
                          Local
                        </span>
                      )}
                    </div>
                    {s.sub && <p className="text-xs text-muted-foreground truncate">{s.sub}</p>}
                    {s.confidenceLabel && (
                      <p className="text-[10px] text-amber-600 dark:text-amber-400 mt-0.5">
                        {s.confidenceLabel}
                      </p>
                    )}
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
      <div className="flex-1 min-h-0 bg-muted relative overflow-hidden touch-none">
        <ChopMap
          ref={mapRef}
          className="absolute inset-0 w-full h-full"
          initialView={{ longitude: mapCenter[1], latitude: mapCenter[0], zoom: 14 }}
          interactive
          onClick={handleMapTap}
        >
          {routePolyline && <RoutePolyline encoded={routePolyline} />}
          {/* Privacy-safe nearby driver markers, biased around pickup or live position. */}
          <NearbyAvailableDrivers
            lat={pickupCoords ? pickupCoords[0] : (live.isRealLocation && live.coords ? live.coords.lat : null)}
            lng={pickupCoords ? pickupCoords[1] : (live.isRealLocation && live.coords ? live.coords.lng : null)}
            vehicleType={type}
            radiusM={4000}
          />
          {/* Draggable pickup — only rendered once we have a real or chosen pickup. */}
          {pickupCoords && (
            <DraggablePickupPin
              lat={pickupCoords[0]}
              lng={pickupCoords[1]}
              onDragEnd={(next) => {
                setPickupCoords([next.lat, next.lng]);
                setPickupIsReal(true);
                reverseLabel(next.lat, next.lng).then(setPickup);
              }}
              size={36}
            />
          )}
          {destCoords && (
            <Marker
              longitude={destCoords[1]}
              latitude={destCoords[0]}
              anchor="bottom"
              draggable
              onDragEnd={(e: any) => {
                const ll = e?.lngLat;
                if (!ll) return;
                setDestCoords([ll.lat, ll.lng]);
                reverseLabel(ll.lat, ll.lng).then(setDestination);
              }}
            >
              <MapMarker variant="dropoff" pulse size={36} label="Destination" />
            </Marker>
          )}
        </ChopMap>
        {!pickupCoords && (
          <div className="pointer-events-none absolute top-4 left-1/2 -translate-x-1/2 z-[400] bg-card/95 backdrop-blur shadow-card rounded-full px-3 py-1.5 text-[11px] font-medium text-foreground max-w-[88%] text-center">
            Touchez la carte pour choisir votre point de départ.
          </div>
        )}
        {pickupCoords && !destCoords && (
          <div className="pointer-events-none absolute top-4 left-1/2 -translate-x-1/2 z-[400] bg-card/95 backdrop-blur shadow-card rounded-full px-3 py-1.5 text-[11px] font-medium text-foreground max-w-[88%] text-center">
            Touchez la carte pour placer la destination.
          </div>
        )}
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
          <div className="pointer-events-none absolute top-4 left-4 z-[400] bg-card/95 backdrop-blur shadow-card rounded-full px-3 py-1.5 text-xs font-medium text-foreground flex items-center gap-2">
            <Loader2 className="w-3.5 h-3.5 animate-spin text-primary" />
            Calcul de l'itinéraire…
          </div>
        )}
        {!routing && distanceKm !== null && durationMin !== null && (
          <div className="pointer-events-none absolute top-4 left-4 z-[400] bg-card/95 backdrop-blur shadow-card rounded-full px-3 py-1.5 text-xs font-medium text-foreground">
            {formatDuration(durationMin * 60)} • {formatDistance((distanceKm ?? 0) * 1000)}
          </div>
        )}
        {routeError && (
          <div className="pointer-events-none absolute top-14 left-4 z-[400] bg-destructive/10 text-destructive shadow-card rounded-full px-3 py-1 text-[11px]">
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
              if (!pickupCoords) {
                toast({ title: "Point de départ requis", description: "Activez votre localisation ou choisissez un lieu." });
                return;
              }
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
            onClick={() => pickupCoords && destCoords && onBook({ pickupCoords, destCoords, fare: estimatedPrice })}
            className="w-full h-14 text-lg font-semibold gradient-primary hover:opacity-90 transition-opacity"
          >
            Réserver pour {formatGNF(Math.round(estimatedPrice))}
          </Button>
        )}
      </motion.div>
    </motion.div>
  );
}
