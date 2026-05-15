import { Marker } from "react-map-gl";
import { useLowDataMode } from "@/hooks/useLowDataMode";

interface Props {
  lng: number;
  lat: number;
  /** Optional heading in degrees (0 = north). */
  heading?: number | null;
}

/**
 * Branded driver position marker — directional emerald arrow with a
 * subtle pulse ring. Low-data mode renders a static dot.
 */
export function DriverPositionMarker({ lng, lat, heading = 0 }: Props) {
  const { low } = useLowDataMode();
  return (
    <Marker longitude={lng} latitude={lat} anchor="center">
      <div className="relative" style={{ width: 36, height: 36 }}>
        {!low && (
          <span
            className="absolute inset-0 rounded-full animate-ping"
            style={{ background: "hsl(var(--primary) / 0.25)" }}
            aria-hidden
          />
        )}
        <span
          className="absolute inset-[6px] rounded-full"
          style={{
            background: "hsl(var(--primary) / 0.18)",
            boxShadow: "0 0 0 2px hsl(var(--background)) inset",
          }}
          aria-hidden
        />
        <div
          className="absolute inset-0 flex items-center justify-center"
          style={{ transform: `rotate(${heading ?? 0}deg)`, transition: "transform 400ms ease" }}
        >
          <svg width="20" height="20" viewBox="0 0 24 24" aria-hidden>
            <path
              d="M12 2 L19 20 L12 16 L5 20 Z"
              fill="hsl(var(--primary))"
              stroke="hsl(var(--background))"
              strokeWidth="1.6"
              strokeLinejoin="round"
            />
          </svg>
        </div>
      </div>
    </Marker>
  );
}