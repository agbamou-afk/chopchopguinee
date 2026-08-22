import { useEffect, useRef } from "react";
import { Marker } from "react-map-gl";
import { MapPinOff } from "lucide-react";
import { ChopMap, type ChopMapHandle } from "@/components/map/ChopMap";
import { MapMarker } from "@/components/map/MapMarker";
import { StraightLineFallback } from "@/components/map/StraightLineFallback";
import type { PickedLocation } from "./LocationField";
import { reverseGeocode } from "@/lib/maps/placeSearch";
import {
  CONAKRY_CENTER,
  MANUAL_POINT_LABEL,
  roundCoord,
  routeFitBbox,
  singleFocus,
  type EndpointKey,
} from "@/lib/envoyer/routePoints";

interface Props {
  pickup: PickedLocation | null;
  destination: PickedLocation | null;
  active: EndpointKey;
  onChange: (key: EndpointKey, loc: PickedLocation) => void;
  className?: string;
}

/**
 * Envoyer itinerary map. The two location fields above remain the canonical
 * entry point; this map writes to the SAME state, so there is exactly one
 * coordinate per endpoint.
 *
 * The dashed line between endpoints is an as-the-crow-flies indicator only —
 * Envoyer has no client-side road routing, so no distance or ETA is shown.
 */
export function RouteMapPicker({ pickup, destination, active, onChange, className }: Props) {
  const mapRef = useRef<ChopMapHandle>(null);
  const revToken = useRef(0);

  // Auto-fit both points; otherwise focus the single known point.
  useEffect(() => {
    const box = routeFitBbox(pickup, destination);
    if (box) {
      mapRef.current?.fitBounds(box, 70);
      return;
    }
    if (pickup || destination) {
      const p = singleFocus(pickup, destination);
      mapRef.current?.flyTo(p.lng, p.lat, 15);
    }
  }, [pickup?.lat, pickup?.lng, destination?.lat, destination?.lng]);

  /**
   * Commit a manually picked coordinate immediately, then enrich the label
   * from the existing reverse-geocoder. A geocoder failure never discards
   * the coordinate.
   */
  const commit = (key: EndpointKey, lat: number, lng: number) => {
    const point = { lat: roundCoord(lat), lng: roundCoord(lng) };
    onChange(key, { ...point, label: MANUAL_POINT_LABEL });
    const token = ++revToken.current;
    void reverseGeocode(point.lat, point.lng).then((rev) => {
      if (token !== revToken.current || !rev?.label) return;
      onChange(key, { ...point, label: rev.label });
    });
  };

  const fallback = (
    <div
      className="h-full w-full rounded-2xl border border-border bg-muted/40 flex flex-col items-center justify-center gap-2 px-4 text-center"
      data-testid="envoyer-map-fallback"
    >
      <MapPinOff className="w-5 h-5 text-muted-foreground" aria-hidden />
      <p className="text-[12px] text-muted-foreground leading-snug">
        Carte temporairement indisponible. Vous pouvez toujours choisir vos points par recherche
        ci-dessus.
      </p>
    </div>
  );

  return (
    <div
      data-testid="envoyer-route-map"
      className={
        className ??
        "relative h-[42vh] min-h-[240px] max-h-[420px] w-full overflow-hidden rounded-2xl border border-border"
      }
    >
      <ChopMap
        ref={mapRef}
        className="h-full w-full"
        initialView={{
          longitude: singleFocus(pickup, destination).lng ?? CONAKRY_CENTER.lng,
          latitude: singleFocus(pickup, destination).lat ?? CONAKRY_CENTER.lat,
          zoom: pickup || destination ? 14 : 12,
        }}
        onClick={({ lng, lat }) => commit(active, lat, lng)}
        degradedFallback={() => fallback}
      >
        {pickup && (
          <Marker
            longitude={pickup.lng}
            latitude={pickup.lat}
            anchor="bottom"
            draggable
            onDragEnd={(e: any) => commit("pickup", e.lngLat.lat, e.lngLat.lng)}
          >
            <MapMarker
              variant="pickup"
              label="Point de retrait"
              selected={active === "pickup"}
              size={38}
            />
          </Marker>
        )}
        {destination && (
          <Marker
            longitude={destination.lng}
            latitude={destination.lat}
            anchor="bottom"
            draggable
            onDragEnd={(e: any) => commit("destination", e.lngLat.lat, e.lngLat.lng)}
          >
            <MapMarker
              variant="dropoff"
              label="Destination"
              selected={active === "destination"}
              size={38}
            />
          </Marker>
        )}
        {pickup && destination && (
          <StraightLineFallback
            from={{ lat: pickup.lat, lng: pickup.lng }}
            to={{ lat: destination.lat, lng: destination.lng }}
            id="envoyer-itinerary"
          />
        )}
      </ChopMap>
      <p className="pointer-events-none absolute inset-x-2 bottom-2 rounded-lg bg-background/85 px-2 py-1 text-center text-[11px] text-muted-foreground">
        Touchez la carte pour placer le point «{" "}
        {active === "pickup" ? "Retrait" : "Destination"} », ou déplacez le repère.
      </p>
    </div>
  );
}
