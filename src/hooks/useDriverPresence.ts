import { useEffect, useRef } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";

interface Options {
  enabled: boolean;
  onTrip?: boolean;
}

/**
 * Streams the driver's geolocation to driver_locations while online.
 * - Throttles updates (8s idle, 3s on trip).
 * - Pauses when tab hidden, offline, or save-data low-bandwidth.
 * - Does nothing when `enabled` is false.
 */
export function useDriverPresence({ enabled, onTrip = false }: Options) {
  const { user } = useAuth();
  const lastSentRef = useRef(0);
  const watchIdRef = useRef<number | null>(null);

  useEffect(() => {
    if (!enabled || !user || typeof navigator === "undefined" || !("geolocation" in navigator)) {
      return;
    }

    const conn = (navigator as any).connection;
    const lowData = !!conn?.saveData;
    const minIntervalMs = onTrip ? 3000 : lowData ? 15000 : 8000;

    const shouldSend = () => {
      if (document.visibilityState === "hidden") return false;
      if (typeof navigator !== "undefined" && navigator.onLine === false) return false;
      return Date.now() - lastSentRef.current >= minIntervalMs;
    };

    const upsert = async (pos: GeolocationPosition) => {
      if (!shouldSend()) return;
      lastSentRef.current = Date.now();
      const { latitude, longitude, heading, speed } = pos.coords;
      try {
        await supabase.from("driver_locations").upsert(
          {
            user_id: user.id,
            lat: latitude,
            lng: longitude,
            heading: heading ?? null,
            speed: speed ?? null,
            status: onTrip ? "on_trip" : "online",
            updated_at: new Date().toISOString(),
          },
          { onConflict: "user_id" },
        );
      } catch {
        // ignore transient errors
      }
    };

    watchIdRef.current = navigator.geolocation.watchPosition(
      upsert,
      () => {},
      { enableHighAccuracy: true, maximumAge: 5000, timeout: 15000 },
    );

    return () => {
      if (watchIdRef.current !== null) {
        navigator.geolocation.clearWatch(watchIdRef.current);
        watchIdRef.current = null;
      }
    };
  }, [enabled, onTrip, user?.id]);
}