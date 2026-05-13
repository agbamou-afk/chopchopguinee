import { useEffect, useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";

export interface RideOffer {
  id: string;
  ride_id: string;
  pickup_zone: string | null;
  destination_zone: string | null;
  estimated_fare_gnf: number | null;
  estimated_earning_gnf: number | null;
  distance_to_pickup_m: number | null;
  expires_at: string;
  status: string;
}

/**
 * Subscribes to ride_offers for the current driver while `enabled`.
 * Returns currently pending offers (newest first) and helpers to refetch.
 */
export function useIncomingOffers(enabled: boolean) {
  const { user } = useAuth();
  const [offers, setOffers] = useState<RideOffer[]>([]);

  const refetch = useCallback(async () => {
    if (!user) { setOffers([]); return; }
    const { data } = await supabase
      .from("ride_offers")
      .select("id,ride_id,pickup_zone,destination_zone,estimated_fare_gnf,estimated_earning_gnf,distance_to_pickup_m,expires_at,status")
      .eq("driver_id", user.id)
      .eq("status", "pending")
      .gt("expires_at", new Date().toISOString())
      .order("sent_at", { ascending: false });
    setOffers((data as RideOffer[]) || []);
  }, [user?.id]);

  useEffect(() => {
    if (!enabled || !user) { setOffers([]); return; }
    refetch();

    let channel: ReturnType<typeof supabase.channel> | null = null;
    const subscribe = () => {
      channel = supabase
        .channel(`ride_offers:${user.id}`)
        .on(
          "postgres_changes",
          { event: "*", schema: "public", table: "ride_offers", filter: `driver_id=eq.${user.id}` },
          () => refetch(),
        )
        .subscribe();
    };
    const unsubscribe = () => {
      if (channel) { supabase.removeChannel(channel); channel = null; }
    };

    // Pause subscription when tab hidden / offline to save bandwidth.
    const onVisibility = () => {
      if (document.visibilityState === "visible" && navigator.onLine) {
        if (!channel) subscribe();
        refetch();
      } else {
        unsubscribe();
      }
    };
    document.addEventListener("visibilitychange", onVisibility);
    window.addEventListener("online", onVisibility);
    window.addEventListener("offline", onVisibility);
    onVisibility();

    return () => {
      document.removeEventListener("visibilitychange", onVisibility);
      window.removeEventListener("online", onVisibility);
      window.removeEventListener("offline", onVisibility);
      unsubscribe();
    };
  }, [enabled, user?.id, refetch]);

  return { offers, refetch };
}