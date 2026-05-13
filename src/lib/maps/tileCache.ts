/**
 * Best-effort tile prefetch for the user's "home zone" so the map renders
 * instantly the next time the app opens, even on a flaky 2G connection.
 *
 * We:
 *  1. Open a CacheStorage bucket dedicated to map tiles.
 *  2. Fetch a small grid of Mapbox raster tiles around (lng, lat) at one
 *     zoom level, capped to keep total bytes < ~1.5 MB.
 *  3. Skip entirely in low-data mode unless the user explicitly opts in.
 *
 * This is purely additive — Mapbox-GL still requests tiles normally;
 * matching responses come from the cache when available (CacheStorage is
 * read by the runtime fetch automatically only if a Service Worker proxies
 * it, otherwise this acts as a warm-up signal for the browser's HTTP cache).
 */
import { Analytics } from '@/lib/analytics/AnalyticsService';
import { isLowDataMode } from '@/lib/network/lowDataMode';

const CACHE_NAME = 'cc-map-tiles-v1';
const MAX_TILES = 24; // 5x5 minus center duplicates ≈ 24

function lngLatToTile(lng: number, lat: number, z: number) {
  const x = Math.floor(((lng + 180) / 360) * 2 ** z);
  const y = Math.floor(
    ((1 - Math.log(Math.tan((lat * Math.PI) / 180) + 1 / Math.cos((lat * Math.PI) / 180)) / Math.PI) / 2) * 2 ** z,
  );
  return { x, y };
}

export interface PrefetchOpts {
  lng: number;
  lat: number;
  zoom?: number;
  styleId?: string;
  token: string;
  force?: boolean;
}

export async function prefetchHomeTiles({ lng, lat, zoom = 13, styleId = 'mapbox/light-v11', token, force }: PrefetchOpts) {
  if (typeof caches === 'undefined') return { cached: 0, skipped: true };
  if (!force && isLowDataMode()) return { cached: 0, skipped: true };
  try {
    const cache = await caches.open(CACHE_NAME);
    const z = Math.round(zoom);
    const center = lngLatToTile(lng, lat, z);
    const urls: string[] = [];
    for (let dx = -2; dx <= 2; dx++) {
      for (let dy = -2; dy <= 2; dy++) {
        const x = center.x + dx;
        const y = center.y + dy;
        urls.push(`https://api.mapbox.com/styles/v1/${styleId}/tiles/256/${z}/${x}/${y}@2x?access_token=${token}`);
      }
    }
    let cached = 0;
    for (const url of urls.slice(0, MAX_TILES)) {
      const hit = await cache.match(url);
      if (hit && !force) { cached++; continue; }
      try {
        const res = await fetch(url, { mode: 'cors', credentials: 'omit' });
        if (res.ok) { await cache.put(url, res.clone()); cached++; }
      } catch { /* offline / blocked — fine */ }
    }
    try { Analytics.track('map.loaded' as any, { metadata: { prefetch: true, cached, zoom: z } }); } catch {}
    return { cached, skipped: false };
  } catch {
    return { cached: 0, skipped: true };
  }
}

export async function clearTileCache() {
  if (typeof caches === 'undefined') return;
  try { await caches.delete(CACHE_NAME); } catch {}
}