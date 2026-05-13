import React, { useEffect, useState } from 'react';
import { Source, Layer } from 'react-map-gl';
import { supabase } from '@/integrations/supabase/client';
interface DriverRow { user_id: string; lat: number; lng: number; status: string }
export function DriverCluster({
  variant = 'moto' as 'moto' | 'toktok',
  statusFilter,
}: { variant?: 'moto' | 'toktok'; statusFilter?: string[] }) {
  const [rows, setRows] = useState<DriverRow[]>([]);
  useEffect(() => {
    let alive = true;
    const load = async () => {
      let q = supabase.from('driver_locations').select('user_id,lat,lng,status');
      if (statusFilter && statusFilter.length) q = q.in('status', statusFilter);
      const { data } = await q;
      if (alive && data) setRows(data as any);
    };
    load();
    const channel = supabase
      .channel(`driver-cluster-${Math.random().toString(36).slice(2)}`)
      .on('postgres_changes',
        { event: '*', schema: 'public', table: 'driver_locations' },
        load)
      .subscribe();
    return () => { alive = false; supabase.removeChannel(channel); };
  }, [statusFilter?.join(',')]);
  const data = { type: 'FeatureCollection' as const, features: rows.map(r => ({
    type: 'Feature' as const, properties: { id: r.user_id, status: r.status },
    geometry: { type: 'Point' as const, coordinates: [r.lng, r.lat] },
  })) };
  const color = variant === 'moto' ? 'hsl(138, 64%, 39%)' : 'hsl(45, 90%, 55%)';
  return (
    <Source id="drivers" type="geojson" data={data} cluster clusterRadius={50}>
      <Layer id="drivers-cluster" type="circle" filter={['has', 'point_count']}
        paint={{ 'circle-color': color, 'circle-opacity': 0.85,
          'circle-radius': ['step', ['get', 'point_count'], 16, 10, 22, 30, 28],
          'circle-stroke-width': 2, 'circle-stroke-color': '#ffffff' }} />
      <Layer id="drivers-cluster-count" type="symbol" filter={['has', 'point_count']}
        layout={{ 'text-field': ['get', 'point_count_abbreviated'], 'text-size': 13,
          'text-font': ['Open Sans Bold', 'Arial Unicode MS Bold'] }}
        paint={{ 'text-color': '#ffffff' }} />
      <Layer id="drivers-point" type="circle" filter={['!', ['has', 'point_count']]}
        paint={{ 'circle-color': color, 'circle-radius': 7, 'circle-stroke-width': 2, 'circle-stroke-color': '#ffffff' }} />
    </Source>
  );
}
