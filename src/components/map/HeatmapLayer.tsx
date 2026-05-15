import React from 'react';
import { Source, Layer } from 'react-map-gl';
import type { LatLng } from '@/lib/maps/geo';
export function HeatmapLayer({ points }: { points: Array<LatLng & { weight?: number }> }) {
  const data = { type: 'FeatureCollection' as const, features: points.map(p => ({
    type: 'Feature' as const, properties: { mag: p.weight ?? 1 },
    geometry: { type: 'Point' as const, coordinates: [p.lng, p.lat] },
  })) };
  return (
    <Source id="heat" type="geojson" data={data}>
      <Layer
        id="heat-layer"
        type="heatmap"
        paint={{
          'heatmap-weight': ['get', 'mag'],
          'heatmap-intensity': 0.9,
          'heatmap-radius': 34,
          'heatmap-opacity': 0.55,
          // Brand ramp: cool emerald → mint → saffron → ember (operational, not "alarm")
          'heatmap-color': [
            'interpolate', ['linear'], ['heatmap-density'],
            0,    'rgba(13, 122, 95, 0)',
            0.25, 'rgba(13, 122, 95, 0.35)',
            0.5,  'rgba(92, 189, 185, 0.55)',
            0.75, 'rgba(232, 184, 74, 0.75)',
            1,    'rgba(232, 93, 58, 0.9)',
          ],
        }}
      />
    </Source>
  );
}
