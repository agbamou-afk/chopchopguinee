import React, { useMemo } from 'react';
import { Source, Layer } from 'react-map-gl';
import { decodePolyline } from '@/lib/maps/geo';

export type RouteState = 'active' | 'approach' | 'completed';

const COLOR: Record<RouteState, string> = {
  active: 'hsl(138, 64%, 42%)',
  approach: 'hsl(45, 90%, 50%)',
  completed: 'hsl(0, 0%, 55%)',
};

export function RoutePolyline({
  encoded, id = 'chop-route', state = 'active', animated = true,
}: { encoded: string; id?: string; state?: RouteState; animated?: boolean }) {
  const geojson = useMemo(() => {
    if (!encoded) return { type: 'FeatureCollection' as const, features: [] };
    const coords = decodePolyline(encoded).map(p => [p.lng, p.lat]);
    if (coords.length < 2) return { type: 'FeatureCollection' as const, features: [] };
    return { type: 'FeatureCollection' as const, features: [{ type: 'Feature' as const, properties: {}, geometry: { type: 'LineString' as const, coordinates: coords } }] };
  }, [encoded]);
  const color = COLOR[state];
  const dash = state === 'approach' ? [2, 2] : undefined;
  return (
    <Source id={id} type="geojson" data={geojson}>
      <Layer id={`${id}-casing`} type="line" paint={{ 'line-color': '#ffffff', 'line-width': 8, 'line-opacity': 0.9 }} layout={{ 'line-cap': 'round', 'line-join': 'round' }} />
      <Layer
        id={`${id}-line`}
        type="line"
        paint={{
          'line-color': color,
          'line-width': 5,
          'line-opacity': state === 'completed' ? 0.6 : (animated ? 0.95 : 1),
          ...(dash ? { 'line-dasharray': dash } : {}),
        }}
        layout={{ 'line-cap': 'round', 'line-join': 'round' }}
      />
    </Source>
  );
}
