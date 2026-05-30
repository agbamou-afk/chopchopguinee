import { useEffect, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
export interface MapConfig {
  mapboxToken: string; styleUrl: string;
  defaultCenter: { lat: number; lng: number };
  defaultZoom: number;
  flags: { heatmap: boolean; surge: boolean; clustering: boolean };
  provider: 'google' | 'osrm' | 'graphhopper';
}
let cached: MapConfig | null = null;
let inflight: Promise<MapConfig> | null = null;
async function fetchConfig(): Promise<MapConfig> {
  if (cached) return cached;
  if (inflight) return inflight;
  inflight = (async () => {
    try {
      // maps-config requires JWT — bail early if no session, so we don't
      // produce a noisy 401 and the caller can render a fallback.
      const { data: sess } = await supabase.auth.getSession();
      if (!sess?.session?.access_token) {
        throw new Error('unauthenticated');
      }
      const { data, error } = await supabase.functions.invoke('maps-config');
      if (error) throw error;
      cached = data as MapConfig;
      return cached!;
    } finally {
      inflight = null;
    }
  })();
  return inflight;
}
export function useMapConfig() {
  const [config, setConfig] = useState<MapConfig | null>(cached);
  const [error, setError] = useState<Error | null>(null);
  useEffect(() => {
    if (cached) return;
    let cancelled = false;
    const attempt = async () => {
      try {
        const cfg = await fetchConfig();
        if (!cancelled) setConfig(cfg);
      } catch (e) {
        if (!cancelled) setError(e as Error);
      }
    };
    attempt();
    // Retry once auth becomes available (e.g. user logs in after mount).
    const { data: sub } = supabase.auth.onAuthStateChange((_evt, session) => {
      if (session?.access_token && !cached && !cancelled) {
        setError(null);
        attempt();
      }
    });
    return () => { cancelled = true; sub.subscription.unsubscribe(); };
  }, []);
  return { config, error, loading: !config && !error };
}
