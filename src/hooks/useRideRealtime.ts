import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";

export interface RideRealtime {
  id: string;
  status: string;
  driver_id: string | null;
  client_id: string;
  pickup_lat: number;
  pickup_lng: number;
  dest_lat: number | null;
  dest_lng: number | null;
  fare_gnf: number;
  mode: string;
  completed_at: string | null;
  metadata: Record<string, unknown> | null;
}

/**
 * Subscribes to a single ride row and keeps it in sync.
 * Both the client and the driver mount this — they see the same status.
 */
export function useRideRealtime(rideId: string | null) {
  const [ride, setRide] = useState<RideRealtime | null>(null);
  const [loading, setLoading] = useState(true);

  const fetchRide = useCallback(async () => {
    if (!rideId) return null;
    const { data } = await supabase.from("rides").select("*").eq("id", rideId).maybeSingle();
    if (data) setRide(data as unknown as RideRealtime);
    return data;
  }, [rideId]);

  useEffect(() => {
    if (!rideId) {
      setRide(null);
      setLoading(false);
      return;
    }
    let alive = true;
    // Stale-while-revalidate: keep the previous ride visible while we refetch.
    // Only flip to "loading" when we have nothing to show yet, which avoids
    // skeleton flashes between phase transitions and reconnects.
    setRide((prev) => {
      if (prev && prev.id === rideId) {
        setLoading(false);
      } else {
        setLoading(true);
      }
      return prev;
    });

    fetchRide().finally(() => {
      if (alive) setLoading(false);
    });

    const channel = supabase
      .channel(`ride-${rideId}-${Math.random().toString(36).slice(2, 8)}`)
      .on(
        "postgres_changes",
        {
          event: "UPDATE",
          schema: "public",
          table: "rides",
          filter: `id=eq.${rideId}`,
        },
        (payload) => {
          if (!alive) return;
          setRide(payload.new as unknown as RideRealtime);
        },
      )
      .subscribe();

    // Resync after the tab becomes visible again or the network comes back.
    // Realtime auto-reconnects, but events that fired while we were offline
    // would otherwise be missed.
    const resync = () => { if (alive) fetchRide(); };
    const onVisible = () => { if (document.visibilityState === "visible") resync(); };
    window.addEventListener("online", resync);
    document.addEventListener("visibilitychange", onVisible);

    return () => {
      alive = false;
      supabase.removeChannel(channel);
      window.removeEventListener("online", resync);
      document.removeEventListener("visibilitychange", onVisible);
    };
    // Intentionally omit `ride` to avoid re-subscribing on every update.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [rideId, fetchRide]);

  return { ride, loading, refetch: fetchRide };
}