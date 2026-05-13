import { useEffect, useRef, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { bearingDeg, lerpLatLng, type LatLng } from './geo';
export interface DriverPosition extends LatLng { heading: number; status: string; }

function isLowData(): boolean {
  const c: any = (navigator as any)?.connection;
  if (!c) return false;
  if (c.saveData) return true;
  return ['slow-2g', '2g'].includes(c.effectiveType ?? '');
}

export function useDriverLocation(driverId: string | null) {
  const [pos, setPos] = useState<DriverPosition | null>(null);
  const fromRef = useRef<DriverPosition | null>(null);
  const toRef = useRef<DriverPosition | null>(null);
  const t0Ref = useRef<number>(0);
  const interpMsRef = useRef<number>(1500);
  const rafRef = useRef<number>(0);
  useEffect(() => {
    if (!driverId) return;
    let alive = true;
    const lowData = isLowData();
    interpMsRef.current = lowData ? 2500 : 1500;
    supabase.from('driver_locations').select('*').eq('user_id', driverId).maybeSingle().then(({ data }) => {
      if (!alive || !data) return;
      const p: DriverPosition = { lat: data.lat, lng: data.lng, heading: data.heading ?? 0, status: data.status ?? 'online' };
      fromRef.current = p; toRef.current = p; setPos(p);
    });
    const channel = supabase.channel(`driver-loc-${driverId}`).on('postgres_changes',
      { event: '*', schema: 'public', table: 'driver_locations', filter: `user_id=eq.${driverId}` },
      (payload) => {
        const row = (payload.new ?? payload.old) as any;
        if (!row) return;
        const next: DriverPosition = {
          lat: row.lat, lng: row.lng,
          heading: row.heading ?? bearingDeg(toRef.current ?? row, row),
          status: row.status ?? 'online',
        };
        fromRef.current = toRef.current ?? next;
        toRef.current = next;
        t0Ref.current = performance.now();
      }).subscribe();
    const tick = () => {
      const from = fromRef.current, to = toRef.current;
      if (from && to) {
        const raw = Math.min(1, (performance.now() - t0Ref.current) / interpMsRef.current);
        // Ease-out cubic for natural deceleration (no teleporting)
        const t = 1 - Math.pow(1 - raw, 3);
        const interp = lerpLatLng(from, to, t);
        setPos({ ...interp, heading: to.heading, status: to.status });
      }
      rafRef.current = requestAnimationFrame(tick);
    };
    rafRef.current = requestAnimationFrame(tick);
    return () => { alive = false; cancelAnimationFrame(rafRef.current); supabase.removeChannel(channel); };
  }, [driverId]);
  return pos;
}
