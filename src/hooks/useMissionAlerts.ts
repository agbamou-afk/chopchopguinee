import { useEffect, useRef } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { MISSION_TYPE_LABEL, type Mission } from "@/lib/missions/types";
import { formatGNF } from "@/lib/format";

const CAPABILITY_TO_TYPE: Record<string, Mission["type"]> = {
  rides_moto: "ride",
  rides_toktok: "ride",
  repas_delivery: "food_delivery",
  marche_delivery: "marketplace_delivery",
  package_delivery: "package_delivery",
};

/**
 * Courier-side calm alert: toast when a new unassigned mission appears that
 * matches the driver's capabilities and the driver is not already engaged.
 *
 * Deduped per mission id. Suppressed entirely while a mission is active so
 * we never spam the courier mid-trip or overlap with the ride request banner.
 */
export function useMissionAlerts({
  userId,
  capabilities,
  hasActiveMission,
  enabled = true,
}: {
  userId: string | null;
  capabilities: string[];
  hasActiveMission: boolean;
  enabled?: boolean;
}) {
  const seen = useRef<Set<string>>(new Set());
  const allowedTypes = useRef<Set<Mission["type"]>>(new Set());

  useEffect(() => {
    allowedTypes.current = new Set(
      capabilities
        .map((c) => CAPABILITY_TO_TYPE[c])
        .filter((t): t is Mission["type"] => !!t),
    );
  }, [capabilities]);

  useEffect(() => {
    if (!enabled || !userId || allowedTypes.current.size === 0) return;
    const channel = supabase
      .channel(`mission-alerts-${userId}`)
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "missions" },
        (payload) => {
          const m = payload.new as Mission;
          if (!m || seen.current.has(m.id)) return;
          if (m.courier_id) return; // already assigned
          if (!allowedTypes.current.has(m.type)) return;
          if (hasActiveMission) return;
          seen.current.add(m.id);
          toast(`Nouvelle ${MISSION_TYPE_LABEL[m.type]}`, {
            description: `Gain estimé ${formatGNF(m.estimated_earning_gnf)}`,
            duration: 6000,
          });
        },
      )
      .subscribe();
    return () => {
      supabase.removeChannel(channel);
    };
  }, [userId, enabled, hasActiveMission]);
}