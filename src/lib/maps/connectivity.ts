import { useEffect, useState, useCallback } from "react";
import { isLowDataMode, subscribeLowData } from "@/lib/network/lowDataMode";

/**
 * Map Phase 2H — Connectivity / degradation signal bus.
 *
 * Lightweight detection of:
 *  - browser online / offline state
 *  - map tile loading status (ChopMap dispatches events)
 *  - routing provider failure / fallback usage
 *  - geolocation permission state
 *  - low-data mode preference
 *
 * Read-only — never mutates pricing, wallet, or route observation trust.
 * No polling. No realtime subscriptions. Just event listeners.
 */

export type TileStatus = "loading" | "ready" | "degraded" | "failed";
export type RoutingStatus = "ready" | "fallback" | "failed";
export type GeolocationStatus = "unknown" | "granted" | "denied" | "unavailable";

export interface MapConnectivityState {
  isOnline: boolean;
  isLowDataMode: boolean;
  tileStatus: TileStatus;
  routingStatus: RoutingStatus;
  geolocationStatus: GeolocationStatus;
  userMessage: string | null;
}

/* ----------------------------- Event bus -------------------------------- */

const EV_TILE = "cc:map_tile_status";
const EV_ROUTING = "cc:map_routing_status";
const EV_GEO = "cc:map_geo_status";

let lastTile: TileStatus = "loading";
let lastRouting: RoutingStatus = "ready";
let lastGeo: GeolocationStatus = "unknown";

export function reportTileStatus(s: TileStatus) {
  lastTile = s;
  if (typeof window !== "undefined") {
    window.dispatchEvent(new CustomEvent(EV_TILE, { detail: { status: s } }));
  }
}

export function reportRoutingStatus(s: RoutingStatus) {
  lastRouting = s;
  if (typeof window !== "undefined") {
    window.dispatchEvent(new CustomEvent(EV_ROUTING, { detail: { status: s } }));
  }
}

export function reportGeolocationStatus(s: GeolocationStatus) {
  lastGeo = s;
  if (typeof window !== "undefined") {
    window.dispatchEvent(new CustomEvent(EV_GEO, { detail: { status: s } }));
  }
}

/* --------------------------- Derived message ---------------------------- */

function deriveMessage(s: Omit<MapConnectivityState, "userMessage">): string | null {
  if (!s.isOnline) return "Mode hors-ligne — certaines fonctions cartographiques sont limitées.";
  if (s.tileStatus === "failed") return "Carte indisponible — vous pouvez continuer avec les informations disponibles.";
  if (s.tileStatus === "degraded") return "Carte dégradée — affichage simplifié.";
  if (s.routingStatus === "fallback") return "Trajet estimé approximatif.";
  if (s.routingStatus === "failed") return "Estimation de trajet indisponible.";
  if (s.isLowDataMode) return "Mode faible consommation activé.";
  if (s.geolocationStatus === "denied") return "Position non autorisée — saisissez votre adresse manuellement.";
  return null;
}

/* ------------------------------ Hook ------------------------------------ */

export function useMapConnectivityState(): MapConnectivityState {
  const isClient = typeof window !== "undefined";
  const [state, setState] = useState<MapConnectivityState>(() => {
    const base = {
      isOnline: !isClient ? true : navigator.onLine,
      isLowDataMode: isLowDataMode(),
      tileStatus: lastTile,
      routingStatus: lastRouting,
      geolocationStatus: lastGeo,
    };
    return { ...base, userMessage: deriveMessage(base) };
  });

  const recompute = useCallback((patch: Partial<MapConnectivityState>) => {
    setState((prev) => {
      const next = { ...prev, ...patch };
      return { ...next, userMessage: deriveMessage(next) };
    });
  }, []);

  useEffect(() => {
    if (!isClient) return;
    const onOnline = () => recompute({ isOnline: true });
    const onOffline = () => recompute({ isOnline: false });
    const onTile = (e: Event) => recompute({ tileStatus: (e as CustomEvent).detail?.status ?? lastTile });
    const onRouting = (e: Event) => recompute({ routingStatus: (e as CustomEvent).detail?.status ?? lastRouting });
    const onGeo = (e: Event) => recompute({ geolocationStatus: (e as CustomEvent).detail?.status ?? lastGeo });

    window.addEventListener("online", onOnline);
    window.addEventListener("offline", onOffline);
    window.addEventListener(EV_TILE, onTile as EventListener);
    window.addEventListener(EV_ROUTING, onRouting as EventListener);
    window.addEventListener(EV_GEO, onGeo as EventListener);
    const unsubLow = subscribeLowData(() => recompute({ isLowDataMode: isLowDataMode() }));

    // Best-effort permission probe (no prompt).
    try {
      const perms = (navigator as any).permissions;
      if (perms?.query) {
        perms.query({ name: "geolocation" as PermissionName }).then((p: any) => {
          const map: Record<string, GeolocationStatus> = {
            granted: "granted", denied: "denied", prompt: "unknown",
          };
          reportGeolocationStatus(map[p.state] ?? "unknown");
          p.onchange = () => reportGeolocationStatus(map[p.state] ?? "unknown");
        }).catch(() => { /* ignore */ });
      } else if (!("geolocation" in navigator)) {
        reportGeolocationStatus("unavailable");
      }
    } catch { /* ignore */ }

    return () => {
      window.removeEventListener("online", onOnline);
      window.removeEventListener("offline", onOffline);
      window.removeEventListener(EV_TILE, onTile as EventListener);
      window.removeEventListener(EV_ROUTING, onRouting as EventListener);
      window.removeEventListener(EV_GEO, onGeo as EventListener);
      unsubLow();
    };
  }, [isClient, recompute]);

  return state;
}