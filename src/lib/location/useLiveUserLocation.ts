import { useCallback, useEffect, useMemo, useState } from "react";
import { useGeolocation } from "@/hooks/useGeolocation";

/**
 * Conakry fallback center — used only as map initialization center.
 * It is NEVER returned as `coords` (callers must not treat it as the user's
 * position). Use `fallbackCenter` instead and label the UI as fallback.
 */
export const CONAKRY_FALLBACK = { lat: 9.6412, lng: -13.5784 } as const;

const STALE_THRESHOLD_MS = 10 * 60 * 1000; // 10 minutes
const CACHE_KEY = "cc:last-known-location";

export type LiveLocationStatus =
  | "idle"
  | "requesting"
  | "granted"
  | "denied"
  | "unavailable"
  | "stale"
  | "fallback";

export type LiveLocationSource = "gps" | "browser" | "cached" | "fallback" | null;

export interface LiveUserLocation {
  coords: { lat: number; lng: number } | null;
  accuracy: number | null;
  status: LiveLocationStatus;
  source: LiveLocationSource;
  updatedAt: string | null;
  error: string | null;
  /** Always-defined center for map initialization. Falls back to Conakry. */
  fallbackCenter: { lat: number; lng: number };
  /** True when `coords` reflects the user's real device location. */
  isRealLocation: boolean;
  /** True when we are only showing the fallback (no real coords). */
  isFallback: boolean;
  /** True when the live location is older than the stale threshold. */
  isStale: boolean;
  requestLocation: () => Promise<void>;
  refreshLocation: () => Promise<void>;
}

function readCache(): { lat: number; lng: number; ts: number; accuracy: number } | null {
  try {
    const raw = localStorage.getItem(CACHE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    if (typeof parsed?.lat !== "number" || typeof parsed?.lng !== "number") return null;
    return parsed;
  } catch {
    return null;
  }
}

function writeCache(c: { lat: number; lng: number; accuracy: number }) {
  try {
    localStorage.setItem(
      CACHE_KEY,
      JSON.stringify({ ...c, ts: Date.now() }),
    );
  } catch {}
}

/**
 * Single source of truth for the logged-in user's live location.
 *
 * Guarantees:
 *  - `coords` is null unless we have real GPS / browser geolocation.
 *  - We never label the Conakry fallback as the user's position.
 *  - Callers can use `fallbackCenter` to initialize a map without lying
 *    about where the user is.
 */
export function useLiveUserLocation(opts: { autoRequest?: boolean } = {}): LiveUserLocation {
  const { autoRequest = true } = opts;
  const geo = useGeolocation();
  const [cached] = useState(() => readCache());

  useEffect(() => {
    if (!autoRequest) return;
    if (geo.status === "idle") {
      geo.request();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [autoRequest, geo.status]);

  useEffect(() => {
    if (geo.position && (geo.status === "ready" || geo.status === "low_accuracy")) {
      writeCache({
        lat: geo.position.lat,
        lng: geo.position.lng,
        accuracy: geo.position.accuracy,
      });
    }
  }, [geo.position, geo.status]);

  return useMemo<LiveUserLocation>(() => {
    const hasLive = !!geo.position && (geo.status === "ready" || geo.status === "low_accuracy");
    const cachedFresh = cached && Date.now() - cached.ts < STALE_THRESHOLD_MS;

    let status: LiveLocationStatus = "idle";
    let source: LiveLocationSource = null;
    let coords: { lat: number; lng: number } | null = null;
    let accuracy: number | null = null;
    let updatedAt: string | null = null;

    if (hasLive && geo.position) {
      status = "granted";
      source = "gps";
      coords = { lat: geo.position.lat, lng: geo.position.lng };
      accuracy = geo.position.accuracy;
      updatedAt = new Date(geo.position.timestamp).toISOString();
    } else if (geo.status === "loading") {
      status = "requesting";
    } else if (geo.status === "denied" || geo.status === "blocked") {
      status = "denied";
    } else if (geo.status === "unavailable") {
      status = "unavailable";
    } else if (cached) {
      // We have a cached position but no current live one.
      coords = { lat: cached.lat, lng: cached.lng };
      accuracy = cached.accuracy;
      updatedAt = new Date(cached.ts).toISOString();
      source = "cached";
      status = cachedFresh ? "granted" : "stale";
    } else {
      status = "fallback";
      source = "fallback";
    }

    const isRealLocation = !!coords && (source === "gps" || source === "cached");
    const isFallback = !coords;
    const isStale = status === "stale";

    return {
      coords,
      accuracy,
      status,
      source,
      updatedAt,
      error: geo.error,
      fallbackCenter: CONAKRY_FALLBACK,
      isRealLocation,
      isFallback,
      isStale,
      requestLocation: async () => geo.request(),
      refreshLocation: async () => geo.request(),
    };
  }, [geo.position, geo.status, geo.error, cached, geo.request]);
}