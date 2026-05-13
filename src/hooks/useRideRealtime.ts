import { useEffect, useState } from "react";
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

  useEffect(() => {
    if (!rideId) {
      setRide(null);
      setLoading(false);
      return;
    }
    let alive = true;
    setLoading(true);

    supabase
      .from("rides")
      .select("*")
      .eq("id", rideId)
      .maybeSingle()
      .then(({ data }) => {
        if (!alive) return;
        if (data) setRide(data as unknown as RideRealtime);
        setLoading(false);
      });

    const channel = supabase
      .channel(`ride-${rideId}`)
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

    return () => {
      alive = false;
      supabase.removeChannel(channel);
    };
  }, [rideId]);

  return { ride, loading };
}