import { useMemo } from "react";
import { Source, Layer } from "react-map-gl";
import type { LatLng } from "@/lib/maps/geo";
import { TONE_HSL, type ChopPinTone } from "./chopPinTypes";

/**
 * Dashed "as-the-crow-flies" fallback line drawn between two endpoints when
 * the routing provider is unreachable. Communicates direction without
 * implying real road geometry, ETA, or traffic.
 */
export function StraightLineFallback({
  from, to, id = "chop-route-fallback", tone,
}: { from: LatLng; to: LatLng; id?: string; tone?: ChopPinTone }) {
  const data = useMemo(() => ({
    type: "FeatureCollection" as const,
    features: [{
      type: "Feature" as const, properties: {},
      geometry: { type: "LineString" as const, coordinates: [[from.lng, from.lat], [to.lng, to.lat]] },
    }],
  }), [from.lat, from.lng, to.lat, to.lng]);
  const color = tone ? TONE_HSL[tone] : "hsl(30, 8%, 45%)";
  return (
    <Source id={id} type="geojson" data={data}>
      <Layer id={`${id}-line`} type="line"
        paint={{ "line-color": color, "line-width": 3, "line-opacity": 0.7, "line-dasharray": [1.5, 2] }}
        layout={{ "line-cap": "round", "line-join": "round" }} />
    </Source>
  );
}
