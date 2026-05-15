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
    <Card className={`relative overflow-hidden p-0 admin-card ${className ?? ''}`}>
      <div className="absolute z-10 top-2 left-2 right-2 flex items-start justify-between gap-2 pointer-events-none">
        <div className="flex flex-wrap gap-1 pointer-events-auto bg-background/90 backdrop-blur rounded-md border border-border/70 p-1">
          {FILTERS.map((f) => (
            <button
              key={f.id}
              onClick={() => setFilter(f.id)}
              className={`h-6 px-2 rounded-sm text-[11px] font-medium font-mono inline-flex items-center gap-1.5 transition-colors ${
                filter === f.id
                  ? 'bg-primary/10 text-primary'
                  : 'text-foreground/70 hover:bg-muted'
              }`}
            >
              {f.id === 'all' && <Bike className="w-3 h-3" />}
              {f.id === 'on_trip' && <Activity className="w-3 h-3" />}
              <span className="uppercase tracking-wider">{f.label}</span>
              <span className="tabular-nums opacity-70">{f.count}</span>
            </button>
          ))}
        </div>
        <div className="flex items-center gap-1 pointer-events-auto bg-background/90 backdrop-blur rounded-md border border-border/70 p-1">
          <button
            onClick={() => setPref(pref === 'on' ? 'auto' : 'on')}
            title="Mode données réduites"
            className={`h-6 px-2 rounded-sm font-mono text-[10px] uppercase tracking-wider inline-flex items-center gap-1 transition-colors ${
              low ? 'bg-secondary/15 text-secondary' : 'text-foreground/70 hover:bg-muted'
            }`}
          >
            <Wifi className="w-3 h-3" /> {low ? 'éco' : 'auto'}
          </button>
          <span className={`h-6 px-2 inline-flex items-center font-mono text-[10px] tabular-nums ${degraded ? 'text-destructive' : 'text-muted-foreground'}`}>
            {fps}fps
          </span>
          <button onClick={recenter} aria-label="Recentrer" className="h-6 w-6 rounded-sm inline-flex items-center justify-center text-foreground/70 hover:bg-muted">
            <RefreshCw className={`w-3.5 h-3.5 ${loading ? 'animate-spin' : ''}`} />
          </button>
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