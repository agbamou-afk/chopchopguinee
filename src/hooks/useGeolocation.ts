import { useCallback, useEffect, useRef, useState } from "react";
import { Analytics } from "@/lib/analytics/AnalyticsService";

export type GeoStatus =
  | "idle"
  | "prompting"
  | "loading"
  | "ready"
  | "low_accuracy"
  | "denied"
  | "blocked"
  | "unavailable";

export interface GeoPosition {
  lat: number;
  lng: number;
  accuracy: number;
  timestamp: number;
}

const ACCURACY_THRESHOLD_M = 80; // anything above ~80m flagged as low accuracy

interface UseGeolocationOptions {
  /** Auto-start a watch as soon as permission is granted. */
  watch?: boolean;
  /** Skip the initial permissions check. */
  manualOnly?: boolean;
}

/**
 * Single source of truth for browser geolocation in CHOP CHOP.
 * Models the real permission lifecycle (denied vs blocked, low accuracy…)
 * and emits analytics so we can track field testing behavior in Conakry.
 */
export function useGeolocation(opts: UseGeolocationOptions = {}) {
  const { watch = false, manualOnly = false } = opts;
  const [status, setStatus] = useState<GeoStatus>("idle");
  const [position, setPosition] = useState<GeoPosition | null>(null);
  const [error, setError] = useState<string | null>(null);
  const watchIdRef = useRef<number | null>(null);
  const deniedOnceRef = useRef(false);

  const supported = typeof navigator !== "undefined" && !!navigator.geolocation;

  // Probe Permissions API once
  useEffect(() => {
    if (manualOnly || !supported) return;
    const perms = (navigator as any).permissions;
    if (!perms?.query) return;
    perms
      .query({ name: "geolocation" })
      .then((res: PermissionStatus) => {
        if (res.state === "denied") {
          setStatus(deniedOnceRef.current ? "blocked" : "denied");
        } else if (res.state === "granted") {
          setStatus("ready");
        } else {
          setStatus("idle");
        }
        res.onchange = () => {
          if (res.state === "denied") setStatus("blocked");
          if (res.state === "granted") setStatus("ready");
        };
      })
      .catch(() => {});
  }, [supported, manualOnly]);

  const handleSuccess = useCallback((p: GeolocationPosition) => {
    const next: GeoPosition = {
      lat: p.coords.latitude,
      lng: p.coords.longitude,
      accuracy: p.coords.accuracy,
      timestamp: p.timestamp,
    };
    setPosition(next);
    setError(null);
    if (next.accuracy > ACCURACY_THRESHOLD_M) {
      setStatus("low_accuracy");
      try {
        Analytics.track("location.low_accuracy" as any, {
          metadata: { accuracy_m: Math.round(next.accuracy) },
        });
      } catch {}
    } else {
      setStatus("ready");
    }
  }, []);

  const handleError = useCallback((err: GeolocationPositionError) => {
    if (err.code === err.PERMISSION_DENIED) {
      const blocked = deniedOnceRef.current;
      deniedOnceRef.current = true;
      setStatus(blocked ? "blocked" : "denied");
      setError("Permission refusée");
      try {
        Analytics.track("location.permission.denied" as any, {
          metadata: { blocked },
        });
      } catch {}
    } else if (err.code === err.POSITION_UNAVAILABLE) {
      setStatus("unavailable");
      setError("Position indisponible");
    } else if (err.code === err.TIMEOUT) {
      setStatus("unavailable");
      setError("Délai dépassé");
    } else {
      setStatus("unavailable");
      setError(err.message ?? "Erreur de géolocalisation");
    }
  }, []);

  const request = useCallback(() => {
    if (!supported) {
      setStatus("unavailable");
      return;
    }
    setStatus("loading");
    try {
      Analytics.track("location.permission.requested" as any, { metadata: {} });
    } catch {}
    navigator.geolocation.getCurrentPosition(
      (p) => {
        try {
          Analytics.track("location.permission.granted" as any, {
            metadata: { accuracy_m: Math.round(p.coords.accuracy) },
          });
        } catch {}
        handleSuccess(p);
        if (watch && watchIdRef.current == null) {
          watchIdRef.current = navigator.geolocation.watchPosition(
            handleSuccess,
            handleError,
            { enableHighAccuracy: true, maximumAge: 5000, timeout: 15000 },
          );
        }
      },
      handleError,
      { enableHighAccuracy: true, maximumAge: 0, timeout: 12000 },
    );
  }, [supported, watch, handleSuccess, handleError]);

  const stop = useCallback(() => {
    if (watchIdRef.current != null) {
      navigator.geolocation.clearWatch(watchIdRef.current);
      watchIdRef.current = null;
    }
  }, []);

  useEffect(() => () => stop(), [stop]);

  return {
    supported,
    status,
    position,
    error,
    request,
    stop,
    isReady: status === "ready" || status === "low_accuracy",
    isLowAccuracy: status === "low_accuracy",
  };
}