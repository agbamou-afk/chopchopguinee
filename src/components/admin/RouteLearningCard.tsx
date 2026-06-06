import { useEffect, useState } from "react";
import { Card } from "@/components/ui/card";
import { Route, Activity } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";

interface Stats {
  tracePoints24h: number;
  ridesWithSummary24h: number;
  contributingDrivers24h: number;
  loading: boolean;
}

/**
 * Honest visibility for Route Learning v0.
 *
 * Shows raw collection counters only — no fake "optimized route" claims.
 * If nothing has been collected yet, renders an honest empty state.
 */
export function RouteLearningCard() {
  const [stats, setStats] = useState<Stats>({
    tracePoints24h: 0, ridesWithSummary24h: 0, contributingDrivers24h: 0, loading: true,
  });

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const since = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
      const [pointsRes, summariesRes, driversRes] = await Promise.all([
        supabase.from("driver_route_traces")
          .select("id", { count: "exact", head: true })
          .gte("observed_at", since),
        supabase.from("ride_route_summaries")
          .select("ride_id", { count: "exact", head: true })
          .gte("created_at", since),
        supabase.from("driver_route_traces")
          .select("driver_id")
          .gte("observed_at", since)
          .limit(2000),
      ]);
      if (cancelled) return;
      const drivers = new Set<string>();
      (driversRes.data ?? []).forEach((r: any) => r?.driver_id && drivers.add(r.driver_id));
      setStats({
        tracePoints24h: pointsRes.count ?? 0,
        ridesWithSummary24h: summariesRes.count ?? 0,
        contributingDrivers24h: drivers.size,
        loading: false,
      });
    })();
    return () => { cancelled = true; };
  }, []);

  const empty = !stats.loading
    && stats.tracePoints24h === 0
    && stats.ridesWithSummary24h === 0;

  return (
    <Card className="p-4 space-y-3 border-dashed">
      <div className="flex items-center gap-2">
        <Route className="w-4 h-4 text-primary" />
        <h3 className="text-sm font-semibold">Apprentissage de trajets</h3>
        <span className="chip-status chip-mute text-[10px]">collecte en cours</span>
      </div>
      <p className="text-[11.5px] text-muted-foreground leading-snug">
        CHOPCHOP enregistre les trajets réels des chauffeurs en mission afin d'améliorer
        les ETA et la fiabilité du routage local. Aucune optimisation IA n'est encore
        active — il s'agit uniquement de collecte de données.
      </p>
      {empty ? (
        <p className="text-xs text-muted-foreground italic">Aucune donnée de trajet collectée.</p>
      ) : (
        <div className="grid grid-cols-3 gap-2 text-center">
          <Stat label="Points GPS 24h" value={stats.tracePoints24h} />
          <Stat label="Courses résumées 24h" value={stats.ridesWithSummary24h} />
          <Stat label="Chauffeurs contributeurs" value={stats.contributingDrivers24h} />
        </div>
      )}
    </Card>
  );
}

function Stat({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded-md bg-muted/40 p-2">
      <div className="flex items-center justify-center gap-1 text-[10px] uppercase tracking-wider text-muted-foreground/80">
        <Activity className="w-3 h-3" />
        {label}
      </div>
      <div className="text-base font-semibold tabular-nums mt-0.5">{value}</div>
    </div>
  );
}