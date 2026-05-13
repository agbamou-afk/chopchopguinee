import { useEffect, useMemo, useRef, useState } from 'react';
import { ChopMap, type ChopMapHandle, DriverCluster } from '@/components/map';
import { supabase } from '@/integrations/supabase/client';
import { Card } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Activity, Bike, Loader2, RefreshCw, Wifi } from 'lucide-react';
import { useMapPerfMonitor } from '@/hooks/useMapPerfMonitor';
import { useLowDataMode } from '@/hooks/useLowDataMode';

interface DriverRow { user_id: string; lat: number; lng: number; status: string; updated_at: string }

/**
 * Live-ops map for the admin console: shows clustered drivers in real time,
 * surfaces presence stats and a perf indicator. Read-only.
 */
export function AdminLiveOpsMap({ variant = 'moto', className }: { variant?: 'moto' | 'toktok'; className?: string }) {
  const mapRef = useRef<ChopMapHandle>(null);
  const [rows, setRows] = useState<DriverRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState<'all' | 'online' | 'on_trip' | 'stale'>('all');
  const { fps, degraded } = useMapPerfMonitor(true);
  const { low, pref, setPref } = useLowDataMode();

  const load = async () => {
    setLoading(true);
    const { data } = await supabase
      .from('driver_locations')
      .select('user_id,lat,lng,status,updated_at')
      .in('status', ['online', 'on_trip']);
    if (data) setRows(data as any);
    setLoading(false);
  };

  useEffect(() => {
    load();
    const ch = supabase
      .channel(`admin-liveops-${Math.random().toString(36).slice(2)}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'driver_locations' }, load)
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, []);

  const stats = useMemo(() => {
    const online = rows.filter(r => r.status === 'online').length;
    const onTrip = rows.filter(r => r.status === 'on_trip').length;
    const stale = rows.filter(r => Date.now() - new Date(r.updated_at).getTime() > 120_000).length;
    return { online, onTrip, stale };
  }, [rows]);

  const clusterStatuses = useMemo<string[] | undefined>(() => {
    if (filter === 'online') return ['online'];
    if (filter === 'on_trip') return ['on_trip'];
    if (filter === 'stale' || filter === 'all') return ['online', 'on_trip'];
    return undefined;
  }, [filter]);

  const FILTERS: { id: typeof filter; label: string; count: number }[] = [
    { id: 'all', label: 'Tous', count: rows.length },
    { id: 'online', label: 'En ligne', count: stats.online },
    { id: 'on_trip', label: 'En course', count: stats.onTrip },
    { id: 'stale', label: 'GPS perdu', count: stats.stale },
  ];

  const recenter = () => mapRef.current?.flyTo(-13.5784, 9.6412, 12);

  return (
    <Card className={`relative overflow-hidden p-0 ${className ?? ''}`}>
      <div className="absolute z-10 top-3 left-3 right-3 flex items-start justify-between gap-2 pointer-events-none">
        <div className="flex flex-wrap gap-2 pointer-events-auto">
          {FILTERS.map((f) => (
            <Button
              key={f.id}
              size="sm"
              variant={filter === f.id ? 'default' : 'secondary'}
              className="h-7 px-2.5 text-xs gap-1.5"
              onClick={() => setFilter(f.id)}
            >
              {f.id === 'all' && <Bike className="w-3 h-3" />}
              {f.id === 'on_trip' && <Activity className="w-3 h-3" />}
              {f.label}
              <span className="opacity-70">{f.count}</span>
            </Button>
          ))}
        </div>
        <div className="flex items-center gap-2 pointer-events-auto">
          <Button
            size="sm"
            variant={low ? 'default' : 'outline'}
            className="h-7 gap-1.5 text-xs"
            onClick={() => setPref(pref === 'on' ? 'auto' : 'on')}
            title="Mode données réduites"
          >
            <Wifi className="w-3 h-3" /> {low ? 'Économie' : 'Auto'}
          </Button>
          <Badge variant={degraded ? 'destructive' : 'outline'} className="font-mono">
            {fps} fps
          </Badge>
          <Button size="icon" variant="secondary" onClick={recenter} aria-label="Recentrer">
            <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
          </Button>
        </div>
      </div>
      {loading && rows.length === 0 && (
        <div className="absolute inset-0 z-[5] flex items-center justify-center bg-background/60">
          <Loader2 className="w-5 h-5 animate-spin text-primary" />
        </div>
      )}
      <ChopMap ref={mapRef} className="w-full h-[420px]">
        <DriverCluster variant={variant} statusFilter={clusterStatuses} />
      </ChopMap>
    </Card>
  );
}