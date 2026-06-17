/**
 * Map Phase 2H — Lightweight TTL cache for stable map reference data.
 *
 * Stored in localStorage under namespaced keys. Designed for safe,
 * non-sensitive reference data only:
 *   - service zones
 *   - recently used map_places
 *   - selected pickup / destination labels
 *   - recent route estimate response (short TTL)
 *   - recent merchant location resolution
 *   - last admin map filter state
 *
 * Never store: driver location traces, route observations, auth tokens,
 * provider keys, or any other sensitive data.
 */

const PREFIX = "cc:map_cache:";

interface Entry<T> { v: T; e: number }

function safeWindow(): Storage | null {
  try { return typeof window !== "undefined" ? window.localStorage : null; } catch { return null; }
}

export function setCached<T>(key: string, value: T, ttlMs: number): void {
  const ls = safeWindow();
  if (!ls) return;
  try {
    const entry: Entry<T> = { v: value, e: Date.now() + Math.max(0, ttlMs) };
    ls.setItem(PREFIX + key, JSON.stringify(entry));
  } catch { /* quota / serialization — ignore */ }
}

export function getCached<T>(key: string): T | null {
  const ls = safeWindow();
  if (!ls) return null;
  try {
    const raw = ls.getItem(PREFIX + key);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Entry<T>;
    if (!parsed || typeof parsed.e !== "number") return null;
    if (Date.now() > parsed.e) {
      ls.removeItem(PREFIX + key);
      return null;
    }
    return parsed.v;
  } catch {
    return null;
  }
}

export function clearCached(key: string): void {
  const ls = safeWindow();
  if (!ls) return;
  try { ls.removeItem(PREFIX + key); } catch { /* ignore */ }
}

export function clearAllMapCache(): void {
  const ls = safeWindow();
  if (!ls) return;
  try {
    const remove: string[] = [];
    for (let i = 0; i < ls.length; i++) {
      const k = ls.key(i);
      if (k && k.startsWith(PREFIX)) remove.push(k);
    }
    remove.forEach((k) => ls.removeItem(k));
  } catch { /* ignore */ }
}

/** Suggested TTLs (ms). Callers may pass other values. */
export const TTL = {
  serviceZones: 24 * 60 * 60 * 1000,
  verifiedPlace: 12 * 60 * 60 * 1000,
  routeEstimate: 5 * 60 * 1000,
  merchantLocation: 60 * 60 * 1000,
  adminFilters: 7 * 24 * 60 * 60 * 1000,
} as const;