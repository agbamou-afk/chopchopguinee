import { useEffect, useRef, useState } from 'react';
import { Analytics } from '@/lib/analytics/AnalyticsService';

/**
 * Lightweight FPS monitor for the active map view.
 * Samples once per second, reports degraded performance if avg FPS < 30
 * over a 5s window. Emits perf events sparingly (max once per minute).
 */
export function useMapPerfMonitor(enabled: boolean = true) {
  const [fps, setFps] = useState<number>(60);
  const [degraded, setDegraded] = useState(false);
  const frames = useRef(0);
  const lastTick = useRef(performance.now());
  const samples = useRef<number[]>([]);
  const lastReport = useRef(0);

  useEffect(() => {
    if (!enabled) return;
    let raf = 0;
    let alive = true;
    const loop = () => {
      if (!alive) return;
      frames.current += 1;
      const now = performance.now();
      if (now - lastTick.current >= 1000) {
        const v = Math.round((frames.current * 1000) / (now - lastTick.current));
        setFps(v);
        samples.current.push(v);
        if (samples.current.length > 5) samples.current.shift();
        const avg = samples.current.reduce((a, b) => a + b, 0) / samples.current.length;
        const isDegraded = samples.current.length === 5 && avg < 30;
        setDegraded(isDegraded);
        if (now - lastReport.current > 60_000) {
          lastReport.current = now;
          try { Analytics.track('map.perf.fps' as any, { metadata: { fps: v, avg: Math.round(avg) } }); } catch {}
          if (isDegraded) {
            try { Analytics.track('map.perf.degraded' as any, { metadata: { avg: Math.round(avg) } }); } catch {}
          }
        }
        frames.current = 0;
        lastTick.current = now;
      }
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => { alive = false; cancelAnimationFrame(raf); };
  }, [enabled]);

  return { fps, degraded };
}