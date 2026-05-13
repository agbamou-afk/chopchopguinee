import type { LatLng } from './geo';
import type { NormalizedRoute, RouteMode, RouteProvider, EtaMatrixCell } from './providers/types';
import { googleProvider } from './providers/googleProvider';
import { osrmProvider } from './providers/osrmProvider';
import { graphhopperProvider } from './providers/graphhopperProvider';
import { Analytics } from '@/lib/analytics/AnalyticsService';

const providers: Record<string, RouteProvider> = {
  google: googleProvider, osrm: osrmProvider, graphhopper: graphhopperProvider,
};
let activeProvider: RouteProvider = googleProvider;
let fallbackChain: Array<'google' | 'osrm' | 'graphhopper'> = ['google', 'osrm', 'graphhopper'];
const routeCache = new Map<string, { at: number; route: NormalizedRoute }>();
const etaCache = new Map<string, { at: number; rows: EtaMatrixCell[][] }>();
const inflightRoutes = new Map<string, Promise<NormalizedRoute>>();
const inflightEtas = new Map<string, Promise<EtaMatrixCell[][]>>();
const ROUTE_TTL = 60_000, ETA_TTL = 30_000;
function key(o: LatLng, d: LatLng, mode: string) {
  return `${o.lat.toFixed(5)},${o.lng.toFixed(5)}|${d.lat.toFixed(5)},${d.lng.toFixed(5)}|${mode}`;
}

function track(name: string, meta: Record<string, unknown>) {
  try { Analytics.track(name as any, meta); } catch {}
}

async function routeWithFallback(
  origin: LatLng, destination: LatLng, mode: RouteMode,
): Promise<NormalizedRoute> {
  const t0 = performance.now();
  let lastErr: unknown = null;
  // Put active provider first, then remaining in chain order
  const order = [activeProvider.name, ...fallbackChain.filter(n => n !== activeProvider.name)];
  for (const name of order) {
    const p = providers[name];
    if (!p) continue;
    try {
      const r = await p.route({ origin, destination, mode });
      const ms = Math.round(performance.now() - t0);
      track('route.success', { provider: name, distance_m: r.distanceM, duration_s: r.durationS, latency_ms: ms, mode });
      track('route.calculated', { provider: name, distance_m: r.distanceM, duration_s: r.durationS, mode });
      return r;
    } catch (e) {
      lastErr = e;
      track('route.failed', { provider: name, error: String((e as Error)?.message ?? e), mode });
    }
  }
  throw lastErr ?? new Error('All routing providers failed');
}

export const RoutingService = {
  setProvider(name: 'google' | 'osrm' | 'graphhopper') { activeProvider = providers[name] ?? googleProvider; },
  getProvider() { return activeProvider.name; },
  setFallbackChain(chain: Array<'google' | 'osrm' | 'graphhopper'>) { fallbackChain = chain; },
  async route(origin: LatLng, destination: LatLng, mode: RouteMode = 'driving'): Promise<NormalizedRoute> {
    const k = key(origin, destination, mode);
    const cached = routeCache.get(k);
    if (cached && Date.now() - cached.at < ROUTE_TTL) return cached.route;
    const inflight = inflightRoutes.get(k);
    if (inflight) return inflight;
    track('route.requested', { mode, provider: activeProvider.name });
    const p = routeWithFallback(origin, destination, mode)
      .then(route => { routeCache.set(k, { at: Date.now(), route }); return route; })
      .finally(() => { inflightRoutes.delete(k); });
    inflightRoutes.set(k, p);
    return p;
  },
  async eta(origins: LatLng[], destinations: LatLng[], mode: RouteMode = 'driving') {
    const k = origins.map(o => `${o.lat.toFixed(4)},${o.lng.toFixed(4)}`).join(';') + '||' +
      destinations.map(d => `${d.lat.toFixed(4)},${d.lng.toFixed(4)}`).join(';') + '|' + mode;
    const cached = etaCache.get(k);
    if (cached && Date.now() - cached.at < ETA_TTL) return cached.rows;
    const inflight = inflightEtas.get(k);
    if (inflight) return inflight;
    const t0 = performance.now();
    const p = activeProvider.eta(origins, destinations, mode)
      .then(rows => {
        etaCache.set(k, { at: Date.now(), rows });
        track('eta.calculated', {
          provider: activeProvider.name, mode,
          origin_count: origins.length, destination_count: destinations.length,
          latency_ms: Math.round(performance.now() - t0),
        });
        return rows;
      })
      .catch(err => { track('route.failed', { provider: activeProvider.name, error: String(err?.message ?? err), kind: 'eta' }); throw err; })
      .finally(() => { inflightEtas.delete(k); });
    inflightEtas.set(k, p);
    return p;
  },
  clearCache() { routeCache.clear(); etaCache.clear(); },
};
