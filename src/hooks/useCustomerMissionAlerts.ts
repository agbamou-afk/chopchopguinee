import { useEffect, useRef } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import type { Mission } from "@/lib/missions/types";
import { customerMessage } from "@/lib/missions/pipelines";

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
          const msg = customerMessage(m);
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