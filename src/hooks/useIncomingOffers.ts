import { useEffect, useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { useLowDataMode } from "@/hooks/useLowDataMode";

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

export type RealtimeStatus = "disabled" | "connecting" | "SUBSCRIBED" | "CHANNEL_ERROR" | "TIMED_OUT" | "CLOSED";

/**
 * Subscribes to ride_offers for the current driver while `enabled`.
 * Returns currently pending offers (newest first) and helpers to refetch.
 */
export function useIncomingOffers(enabled: boolean) {
  const { user } = useAuth();
  const { low } = useLowDataMode();
  const [offers, setOffers] = useState<RideOffer[]>([]);
  const [latestOffer, setLatestOffer] = useState<RideOffer | null>(null);
  const [realtimeStatus, setRealtimeStatus] = useState<RealtimeStatus>("disabled");

  const refetch = useCallback(async () => {
    if (!user) { setOffers([]); setLatestOffer(null); return; }
    const selectCols = "id,ride_id,pickup_zone,destination_zone,estimated_fare_gnf,estimated_earning_gnf,distance_to_pickup_m,expires_at,status";
    const [{ data }, { data: latest }] = await Promise.all([
      supabase
      .from("ride_offers")
      .select(selectCols)
      .eq("driver_id", user.id)
      .eq("status", "pending")
      .gt("expires_at", new Date().toISOString())
      .order("sent_at", { ascending: false }),
      supabase
        .from("ride_offers")
        .select(selectCols)
        .eq("driver_id", user.id)
        .order("sent_at", { ascending: false })
        .limit(1)
        .maybeSingle(),
    ]);
    setOffers((data as RideOffer[]) || []);
    setLatestOffer((latest as RideOffer | null) || null);
  }, [user?.id]);

  useEffect(() => {
    if (!enabled || !user) { setOffers([]); setRealtimeStatus("disabled"); return; }
    refetch();

    let channel: ReturnType<typeof supabase.channel> | null = null;
    let pollId: number | null = null;
    const subscribe = () => {
      channel = supabase
        .channel(`ride_offers:${user.id}`)
        .on(
          "postgres_changes",
          { event: "*", schema: "public", table: "ride_offers", filter: `driver_id=eq.${user.id}` },
          () => refetch(),
        )
        .subscribe((status) => setRealtimeStatus(status as RealtimeStatus));
    };
    const unsubscribe = () => {
      if (channel) { supabase.removeChannel(channel); channel = null; }
      if (pollId) { window.clearInterval(pollId); pollId = null; }
      setRealtimeStatus("disabled");
    };

    // Pause subscription when tab hidden / offline to save bandwidth.
    const onVisibility = () => {
      if (document.visibilityState === "visible" && navigator.onLine) {
        if (!channel) subscribe();
        if (!pollId) pollId = window.setInterval(refetch, low ? 15000 : 5000);
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
  }, [enabled, user?.id, refetch, low]);

  return { offers, latestOffer, realtimeStatus, refetch };
}