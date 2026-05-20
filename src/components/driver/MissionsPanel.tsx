import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import {
  claimMission,
  listAvailableMissions,
  listCourierMissions,
} from "@/lib/missions/missions";
import { isTerminalState, type Mission } from "@/lib/missions/types";
import { ActiveMissionCard } from "./ActiveMissionCard";
import { MissionRequestCard } from "./MissionRequestCard";

/**
 * Courier missions surface — combines:
 *  - "Mes missions actives": missions already assigned to this courier
 *  - "Missions disponibles": unassigned missions matching the courier's
 *    capabilities (Repas, Marché, Colis...). RLS does the heavy filtering.
 */
export function MissionsPanel({
  userId,
  capabilities = [],
}: {
  userId: string | null;
  capabilities?: string[];
}) {
  const [missions, setMissions] = useState<Mission[]>([]);
  const [available, setAvailable] = useState<Mission[]>([]);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [loaded, setLoaded] = useState(false);

  const reload = useCallback(
    async (uid: string) => {
      try {
        const [mine, avail] = await Promise.all([
          listCourierMissions(uid),
          capabilities.length
            ? listAvailableMissions(capabilities)
            : Promise.resolve([] as Mission[]),
        ]);
        setMissions(mine);
        setAvailable(avail);
      } catch {
        setMissions([]);
        setAvailable([]);
      } finally {
        setLoaded(true);
      }
    },
    [capabilities],
  );

  useEffect(() => {
    if (!userId) {
      setMissions([]);
      setAvailable([]);
      setLoaded(true);
      return;
    }
    reload(userId);
    const channel = supabase
      .channel(`courier-missions-${userId}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "missions" },
        () => reload(userId),
      )
      .subscribe();
    return () => {
      supabase.removeChannel(channel);
    };
  }, [userId, reload]);

  const handleAccept = async (id: string) => {
    setBusyId(id);
    try {
      await claimMission(id);
      toast.success("Mission acceptée");
      if (userId) await reload(userId);
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : "Impossible d'accepter la mission";
      toast.error(msg);
    } finally {
      setBusyId(null);
    }
  };

  const active = missions.filter((m) => !isTerminalState(m.state));
  if (!loaded || (active.length === 0 && available.length === 0)) return null;

  return (
    <div className="space-y-4">
      {active.length > 0 && (
        <section className="space-y-2">
          <h3 className="text-[10px] font-bold uppercase tracking-[0.2em] text-muted-foreground px-1">
            Mes missions actives
          </h3>
          <div className="space-y-2">
            {active.map((m) => (
              <ActiveMissionCard
                key={m.id}
                mission={m}
                onChange={(u) =>
                  setMissions((prev) => prev.map((x) => (x.id === u.id ? u : x)))
                }
              />
            ))}
          </div>
        </section>
      )}
      {available.length > 0 && (
        <section className="space-y-2">
          <h3 className="text-[10px] font-bold uppercase tracking-[0.2em] text-muted-foreground px-1">
            Missions disponibles
          </h3>
          <div className="space-y-2">
            {available.map((m) => (
              <MissionRequestCard
                key={m.id}
                mission={m}
                onAccept={handleAccept}
                busy={busyId === m.id}
              />
            ))}
          </div>
        </section>
      )}
    </div>
  );
}