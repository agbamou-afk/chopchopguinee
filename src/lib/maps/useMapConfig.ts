import { useCallback, useEffect, useState } from 'react';
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
      // maps-config serves only publishable values (style + pk. token), so it
      // works for signed-out visitors too. Privacy layers stay authenticated.
      const { data, error } = await supabase.functions.invoke('maps-config');
      if (error) throw error;
      if (!data?.mapboxToken) throw new Error('map_token_missing');
      cached = data as MapConfig;
      return cached!;
    } finally {
      inflight = null;
    }
  })();
  return inflight;
}

/** Clears the cached config so the next fetch hits the backend again. */
export function resetMapConfigCache() {
  cached = null;
  inflight = null;
}

export function useMapConfig() {
  const [config, setConfig] = useState<MapConfig | null>(cached);
  const [error, setError] = useState<Error | null>(null);
  const [nonce, setNonce] = useState(0);

  const retry = useCallback(() => {
    resetMapConfigCache();
    setError(null);
    setConfig(null);
    setNonce((n) => n + 1);
  }, []);

  useEffect(() => {
    let cancelled = false;
    const attempt = async () => {
      try {
        const cfg = await fetchConfig();
        if (!cancelled) setConfig(cfg);
      } catch (e) {
        if (!cancelled) setError(e as Error);
      }
    };
    if (cached) { setConfig(cached); return; }
    attempt();
    // Re-attempt when auth state changes (config may become richer once signed in).
    const { data: sub } = supabase.auth.onAuthStateChange(() => {
      if (!cached && !cancelled) {
        setError(null);
        attempt();
      }
    });
    return () => { cancelled = true; sub.subscription.unsubscribe(); };
  }, [nonce]);

  return { config, error, loading: !config && !error, retry };
}
