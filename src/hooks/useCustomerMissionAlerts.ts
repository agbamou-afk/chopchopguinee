import { useEffect, useRef } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import type { Mission, MissionState } from "@/lib/missions/types";

const CUSTOMER_MESSAGES: Partial<Record<MissionState, string>> = {
  heading_to_pickup: "Un coursier a accepté votre livraison.",
  picked_up: "Votre commande a été récupérée.",
  heading_to_dropoff: "Votre commande est en route.",
  arrived_dropoff: "Le coursier est arrivé.",
  delivered: "Commande livrée. Bon appétit !",
  failed: "Un problème a été signalé sur votre livraison.",
};

/**
 * Customer-side calm alerts on their own missions. Deduped per (id,state)
 * so we never repeat the same message — even if Postgres replays.
 */
export function useCustomerMissionAlerts(userId: string | null) {
  const seen = useRef<Set<string>>(new Set());

  useEffect(() => {
    if (!userId) return;
    const channel = supabase
      .channel(`customer-missions-${userId}`)
      .on(
        "postgres_changes",
        {
          event: "UPDATE",
          schema: "public",
          table: "missions",
          filter: `customer_id=eq.${userId}`,
        },
        (payload) => {
          const m = payload.new as Mission;
          const prev = payload.old as Mission | null;
          if (!m || prev?.state === m.state) return;
          const msg = CUSTOMER_MESSAGES[m.state];
          if (!msg) return;
          const key = `${m.id}:${m.state}`;
          if (seen.current.has(key)) return;
          seen.current.add(key);
          if (m.state === "failed") toast.error(msg);
          else if (m.state === "delivered") toast.success(msg);
          else toast(msg);
        },
      )
      .subscribe();
    return () => {
      supabase.removeChannel(channel);
    };
  }, [userId]);
}