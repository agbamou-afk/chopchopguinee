import { useEffect, useRef, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { bearingDeg, haversineMeters, lerpLatLng, type LatLng } from './geo';

export interface DriverPosition extends LatLng { heading: number; status: string; }

function isLowData(): boolean {
  const c: any = (navigator as any)?.connection;
  if (!c) return false;
  if (c.saveData) return true;
  return ['slow-2g', '2g'].includes(c.effectiveType ?? '');
}

/** Shortest-arc angular interpolation in degrees. */
function lerpHeading(a: number, b: number, t: number): number {
  const diff = ((((b - a) % 360) + 540) % 360) - 180;
  return (a + diff * t + 360) % 360;
}

// Tunables — chosen for believable urban driving in Conakry.
const JITTER_METERS = 3;          // ignore GPS noise smaller than this
const MIN_HEADING_MOVE_M = 2;     // require this much movement before turning the marker
const OUTLIER_SPEED_MPS = 60;     // ~216 km/h — clamp absurd jumps
const MIN_INTERP_MS = 800;        // floor for animation duration
const MAX_INTERP_MS = 2500;       // ceiling so we never lag too far behind
const HEADING_SMOOTH_MS = 600;    // separate, faster animation for heading

export function useDriverLocation(driverId: string | null) {
  const [pos, setPos] = useState<DriverPosition | null>(null);
  // Position interpolation (separate from heading)
  const fromRef = useRef<LatLng | null>(null);
  const toRef = useRef<LatLng | null>(null);
  const tStartRef = useRef<number>(0);
  const interpMsRef = useRef<number>(1500);
  // Heading interpolation
  const headingFromRef = useRef<number>(0);
  const headingToRef = useRef<number>(0);
  const headingT0Ref = useRef<number>(0);
  // Latest known status
  const statusRef = useRef<string>('online');
  // Bookkeeping for jitter / outlier rejection
  const lastFixAtRef = useRef<number>(0);
  const lastFixPosRef = useRef<LatLng | null>(null);
  const rafRef = useRef<number>(0);
  // Mirror of the currently displayed marker — readable from event handlers
  // without going through stale React state closures.
  const visualRef = useRef<{ lat: number; lng: number; heading: number } | null>(null);

  useEffect(() => {
    if (!driverId) return;
    let alive = true;
    const lowDataMul = isLowData() ? 1.5 : 1;

    const ingest = (raw: { lat: number; lng: number; heading?: number | null; status?: string | null }) => {
      const now = performance.now();
      const incoming: LatLng = { lat: raw.lat, lng: raw.lng };

      // First fix — seed everything.
      if (!toRef.current) {
        fromRef.current = incoming;
        toRef.current = incoming;
        lastFixPosRef.current = incoming;
        lastFixAtRef.current = now;
        const h = raw.heading ?? 0;
        headingFromRef.current = h;
        headingToRef.current = h;
        headingT0Ref.current = now;
        statusRef.current = raw.status ?? 'online';
        visualRef.current = { ...incoming, heading: h };
        setPos({ ...incoming, heading: h, status: statusRef.current });
        return;
      }

      const last = lastFixPosRef.current ?? toRef.current;
      const dist = haversineMeters(last, incoming);
      const dt = Math.max(1, (now - lastFixAtRef.current)) / 1000;

      // 1) Jitter rejection — ignore micro-noise, but always update status.
      if (dist < JITTER_METERS) {
        statusRef.current = raw.status ?? statusRef.current;
        return;
      }

      // 2) Outlier dampening — implausible speed: snap with a short window so
      // the marker catches up quickly without teleport-flash.
      const speed = dist / dt;
      const isOutlier = speed > OUTLIER_SPEED_MPS;

      // 3) Continuous interpolation — start the new segment from where the
      // marker visually IS right now, not from the previous target. This
      // prevents back-and-forth jumps when fixes arrive mid-animation.
      const v = visualRef.current;
      const currentVisual = v ? { lat: v.lat, lng: v.lng } : (toRef.current ?? incoming);
      fromRef.current = currentVisual;
      toRef.current = incoming;
      tStartRef.current = now;

      // Adaptive window — track real cadence, clamped to sensible bounds.
      const cadence = (now - lastFixAtRef.current) * lowDataMul;
      interpMsRef.current = isOutlier
        ? MIN_INTERP_MS
        : Math.max(MIN_INTERP_MS, Math.min(MAX_INTERP_MS, cadence));

      // 4) Heading: only rotate when we actually moved enough; otherwise keep
      // current heading to avoid spinning on stationary jitter.
      let nextHeading = headingToRef.current;
      if (dist >= MIN_HEADING_MOVE_M) {
        nextHeading = raw.heading ?? bearingDeg(last, incoming);
      }
      // Start heading animation from the currently displayed heading.
      headingFromRef.current = visualRef.current?.heading ?? headingToRef.current;
      headingToRef.current = nextHeading;
      headingT0Ref.current = now;

      statusRef.current = raw.status ?? statusRef.current;
      lastFixPosRef.current = incoming;
      lastFixAtRef.current = now;
    };

    supabase
      .from('driver_locations')
      .select('*')
      .eq('user_id', driverId)
      .maybeSingle()
      .then(({ data }) => {
        if (!alive || !data) return;
        ingest(data);
      });

    const channel = supabase
      .channel(`driver-loc-${driverId}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'driver_locations', filter: `user_id=eq.${driverId}` },
        (payload) => {
          const row = (payload.new ?? payload.old) as any;
          if (!row || row.lat == null || row.lng == null) return;
          ingest(row);
        },
      )
      .subscribe();

    const tick = () => {
      const from = fromRef.current, to = toRef.current;
      if (from && to) {
        const now = performance.now();
        const rawT = Math.min(1, (now - tStartRef.current) / interpMsRef.current);
        // Ease-out cubic — natural deceleration, no overshoot, no teleport.
        const t = 1 - Math.pow(1 - rawT, 3);
        const interp = lerpLatLng(from, to, t);

        const rawH = Math.min(1, (now - headingT0Ref.current) / HEADING_SMOOTH_MS);
        const tH = 1 - Math.pow(1 - rawH, 3);
        const heading = lerpHeading(headingFromRef.current, headingToRef.current, tH);

        visualRef.current = { lat: interp.lat, lng: interp.lng, heading };
        setPos({ ...interp, heading, status: statusRef.current });
      }
      rafRef.current = requestAnimationFrame(tick);
    };
    rafRef.current = requestAnimationFrame(tick);

    return () => {
      alive = false;
      cancelAnimationFrame(rafRef.current);
      supabase.removeChannel(channel);
    };
  }, [driverId]);

  return pos;
}
