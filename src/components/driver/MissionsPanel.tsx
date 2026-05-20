import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { listCourierMissions } from "@/lib/missions/missions";
import { isTerminalState, type Mission } from "@/lib/missions/types";
import { ActiveMissionCard } from "./ActiveMissionCard";

/**
 * Lightweight courier missions list — displayed inside the driver dashboard.
 * Active (non-terminal) missions render as actionable cards. Realtime updates
 * via Postgres changes on the `missions` table.
 */
export function MissionsPanel({ userId }: { userId: string | null }) {
  const [missions, setMissions] = useState<Mission[]>([]);
  const [loaded, setLoaded] = useState(false);

  const reload = useCallback(async (uid: string) => {
    try {
      const rows = await listCourierMissions(uid);
      setMissions(rows);
    } catch {
      setMissions([]);
    } finally {
      setLoaded(true);
    }
  }, []);

  useEffect(() => {
    if (!userId) {
      setMissions([]);
      setLoaded(true);
      return;
    }
    reload(userId);
    const channel = supabase
      .channel(`courier-missions-${userId}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "missions", filter: `courier_id=eq.${userId}` },
        () => reload(userId),
      )
      .subscribe();
    return () => {
      supabase.removeChannel(channel);
    };
  }, [userId, reload]);

  const active = missions.filter((m) => !isTerminalState(m.state));
  if (!loaded || active.length === 0) return null;

  return (
    <section className="space-y-2">
      <h3 className="text-[10px] font-bold uppercase tracking-[0.2em] text-muted-foreground px-1">
        Mes missions actives
      </h3>
      <div className="space-y-2">
        {active.map((m) => (
          <ActiveMissionCard
            key={m.id}
            mission={m}
            onChange={(u) => setMissions((prev) => prev.map((x) => (x.id === u.id ? u : x)))}
          />
        ))}
      </div>
    </section>
  );
}