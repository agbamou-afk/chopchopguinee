import { useCallback, useEffect, useState } from "react";
import { Marker } from "react-map-gl";
import { MapMarker } from "./MapMarker";
import { Analytics } from "@/lib/analytics/AnalyticsService";

interface Props {
  lat: number;
  lng: number;
  /** Fired continuously while dragging (cheap update). */
  onDrag?: (next: { lat: number; lng: number }) => void;
  /** Fired once when the user releases the pin. */
  onDragEnd: (next: { lat: number; lng: number }) => void;
  /** Visual hint when GPS is poor. */
  lowAccuracy?: boolean;
  size?: number;
}

/**
 * A pickup pin the user can drag on the map. Emits `pickup.adjusted` when
 * the user finalizes a new position, so we can measure how often Conakry
 * users override GPS.
 */
export function DraggablePickupPin({
  lat,
  lng,
  onDrag,
  onDragEnd,
  lowAccuracy,
  size = 40,
}: Props) {
  const [coords, setCoords] = useState({ lat, lng });
  const [origin, setOrigin] = useState({ lat, lng });

  // Sync external position updates when not actively dragging
  useEffect(() => {
    setCoords({ lat, lng });
    setOrigin({ lat, lng });
  }, [lat, lng]);

  const handleDrag = useCallback(
    (e: { lngLat: { lat: number; lng: number } }) => {
      const next = { lat: e.lngLat.lat, lng: e.lngLat.lng };
      setCoords(next);
      onDrag?.(next);
    },
    [onDrag],
  );

  const handleDragEnd = useCallback(
    (e: { lngLat: { lat: number; lng: number } }) => {
      const next = { lat: e.lngLat.lat, lng: e.lngLat.lng };
      setCoords(next);
      onDragEnd(next);
      try {
        const dx = next.lat - origin.lat;
        const dy = next.lng - origin.lng;
        const movedDeg = Math.sqrt(dx * dx + dy * dy);
        Analytics.track("pickup.adjusted" as any, {
          metadata: {
            moved_degrees: Number(movedDeg.toFixed(5)),
            low_accuracy: !!lowAccuracy,
          },
        });
      } catch {}
      setOrigin(next);
    },
    [onDragEnd, origin.lat, origin.lng, lowAccuracy],
  );

  return (
    <Marker
      longitude={coords.lng}
      latitude={coords.lat}
      anchor="bottom"
      draggable
      onDrag={handleDrag as any}
      onDragEnd={handleDragEnd as any}
    >
      <div className="flex flex-col items-center pointer-events-none">
        <MapMarker
          variant="pickup"
          pulse={!!lowAccuracy}
          state={lowAccuracy ? "busy" : "online"}
          size={size}
          label="Point de départ"
        />
      </div>
    </Marker>
  );
}