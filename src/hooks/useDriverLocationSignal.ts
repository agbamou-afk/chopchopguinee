import { useEffect, useRef } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";

interface Opts {
  enabled: boolean;
  activeRideId?: string | null;
  activeMissionId?: string | null;
}

/**
 * Map Phase 2F — writes driver location to public.driver_location_signals via
 * the secure RPC. Battery-conscious:
 *   - 60s when idle online
 *   - 20s during active ride/mission
 *   - paused when tab hidden, offline, or save-data
 *   - sends `offline` mark when disabled
 * Does nothing when `enabled` is false.
 */
export function useDriverLocationSignal({ enabled, activeRideId, activeMissionId }: Opts) {
  const { user } = useAuth();
  const lastSentRef = useRef(0);
  const watchIdRef = useRef<number | null>(null);
  const wasEnabledRef = useRef(false);

  useEffect(() => {
    if (!user) return;
    if (!enabled) {
      if (wasEnabledRef.current) {
        wasEnabledRef.current = false;
        // best-effort offline mark
        supabase.rpc("driver_mark_offline_signal" as any).then(() => {}, () => {});
      }
      return;
    }
    if (typeof navigator === "undefined" || !("geolocation" in navigator)) return;

    wasEnabledRef.current = true;
    const conn = (navigator as any).connection;
    const lowData = !!conn?.saveData;
    const onTrip = !!(activeRideId || activeMissionId);
    const minIntervalMs = onTrip ? 20_000 : lowData ? 90_000 : 60_000;

    const shouldSend = () => {
      if (document.visibilityState === "hidden" && !onTrip) return false;
      if (typeof navigator !== "undefined" && navigator.onLine === false) return false;
      return Date.now() - lastSentRef.current >= minIntervalMs;
    };

    const push = async (pos: GeolocationPosition) => {
      if (!shouldSend()) return;
      lastSentRef.current = Date.now();
      const { latitude, longitude, accuracy, heading, speed } = pos.coords;
      try {
        await supabase.rpc("driver_update_location_signal" as any, {
          p_lat: latitude,
          p_lng: longitude,
          p_accuracy_meters: accuracy ?? null,
          p_heading: heading ?? null,
          p_speed_mps: speed ?? null,
          p_active_ride_id: activeRideId ?? null,
          p_active_mission_id: activeMissionId ?? null,
          p_source: activeRideId ? "ride" : activeMissionId ? "mission" : "driver_app",
        });
      } catch {
        // soft-fail: never break driver mode on a signal write
      }
    };

    watchIdRef.current = navigator.geolocation.watchPosition(
      push,
      () => {},
      { enableHighAccuracy: onTrip, maximumAge: 5000, timeout: 15000 },
    );

    return () => {
      if (watchIdRef.current !== null) {
        navigator.geolocation.clearWatch(watchIdRef.current);
        watchIdRef.current = null;
      }
    };
  }, [enabled, user?.id, activeRideId, activeMissionId]);
}
