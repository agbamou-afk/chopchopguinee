import React, { useMemo, useRef } from 'react';
import { Source, Layer } from 'react-map-gl';
import { decodePolyline } from '@/lib/maps/geo';

export type RouteState = 'active' | 'approach' | 'completed';

// Warmer, CHOP-native route palette — emerald → saffron → graphite.
const COLOR: Record<RouteState, string> = {
  active:    'hsl(146, 70%, 34%)',
  approach:  'hsl(38, 92%, 52%)',
  completed: 'hsl(30, 8%, 50%)',
};

export function RoutePolyline({
  encoded, id = 'chop-route', state = 'active', animated = true,
}: { encoded: string; id?: string; state?: RouteState; animated?: boolean }) {
  // Retain the last good polyline while parents refetch — prevents the line
  // from disappearing for a frame and flickering back in.
  const lastEncodedRef = useRef<string>('');
  if (encoded) lastEncodedRef.current = encoded;
  const effective = encoded || lastEncodedRef.current;

  const geojson = useMemo(() => {
    if (!effective) return { type: 'FeatureCollection' as const, features: [] };
    const coords = decodePolyline(effective).map(p => [p.lng, p.lat]);
    if (coords.length < 2) return { type: 'FeatureCollection' as const, features: [] };
    return { type: 'FeatureCollection' as const, features: [{ type: 'Feature' as const, properties: {}, geometry: { type: 'LineString' as const, coordinates: coords } }] };
  }, [effective]);
  const color = COLOR[state];
  const dash = state === 'approach' ? [2, 2] : undefined;
  return (
    <Source id={id} type="geojson" data={geojson}>
      {/* Soft cream casing for a branded, infrastructural feel */}
      <Layer id={`${id}-casing`} type="line" paint={{ 'line-color': 'hsl(36, 35%, 97%)', 'line-width': 9, 'line-opacity': 0.95 }} layout={{ 'line-cap': 'round', 'line-join': 'round' }} />
      <Layer
        id={`${id}-line`}
        type="line"
        paint={{
          'line-color': color,
          'line-width': 4.5,
          'line-opacity': state === 'completed' ? 0.55 : (animated ? 0.92 : 1),
          ...(dash ? { 'line-dasharray': dash } : {}),
        }}
        layout={{ 'line-cap': 'round', 'line-join': 'round' }}
      />
    </Source>
  );
}
