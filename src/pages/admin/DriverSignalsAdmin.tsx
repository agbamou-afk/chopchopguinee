import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Loader2, RefreshCw, Radio, Bike, Package, Wifi, WifiOff } from "lucide-react";

interface SignalRow {
  driver_user_id: string;
  lat: number;
  lng: number;
  status: "online_idle" | "active_ride" | "active_mission" | "offline";
  source: string;
  active_ride_id: string | null;
  active_mission_id: string | null;
  service_zone_id: string | null;
  accuracy_meters: number | null;
  last_ping_at: string;
}

function freshness(ts: string): "live" | "recent" | "stale" {
  const age = Date.now() - new Date(ts).getTime();
  if (age < 2 * 60_000) return "live";
  if (age < 10 * 60_000) return "recent";
  return "stale";
}

const STATUS_LABEL: Record<SignalRow["status"], string> = {
  online_idle: "En ligne",
  active_ride: "Course",
  active_mission: "Mission",
  offline: "Hors-ligne",
};

/**
 * Map Phase 2F — admin-only driver/courier signal layer.
 * Read-only. Polls every 30s. No public exposure.
 */
export default function DriverSignalsAdmin() {
  const [rows, setRows] = useState<SignalRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState<"all" | "live" | "stale" | "active">("all");

  const load = async () => {
    setLoading(true);
    const { data } = await (supabase as any)
      .from("driver_location_signals")
      .select(
        "driver_user_id,lat,lng,status,source,active_ride_id,active_mission_id,service_zone_id,accuracy_meters,last_ping_at",
      )
      .order("last_ping_at", { ascending: false })
      .limit(500);
    setRows((data as SignalRow[]) ?? []);
    setLoading(false);
  };

  useEffect(() => {
    load();
    const t = setInterval(load, 30_000);
    return () => clearInterval(t);
  }, []);

  const stats = useMemo(() => {
    const live = rows.filter((r) => freshness(r.last_ping_at) === "live" && r.status !== "offline").length;
    const onRide = rows.filter((r) => r.status === "active_ride").length;
    const onMission = rows.filter((r) => r.status === "active_mission").length;
    const stale = rows.filter((r) => freshness(r.last_ping_at) === "stale").length;
    return { live, onRide, onMission, stale, total: rows.length };
  }, [rows]);

  const filtered = useMemo(() => {
    return rows.filter((r) => {
      const f = freshness(r.last_ping_at);
      if (filter === "live") return f === "live" && r.status !== "offline";
      if (filter === "stale") return f === "stale";
      if (filter === "active") return r.status === "active_ride" || r.status === "active_mission";
      return true;
    });
  }, [rows, filter]);

  return (
    <div className="space-y-4 p-4">
      <header className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold flex items-center gap-2">
            <Radio className="w-5 h-5 text-primary" /> Signaux chauffeurs
          </h1>
          <p className="text-sm text-muted-foreground">
            Données opérationnelles internes. Non exposé aux clients.
          </p>
        </div>
        <Button variant="outline" size="sm" onClick={load} disabled={loading}>
          <RefreshCw className={`w-4 h-4 mr-2 ${loading ? "animate-spin" : ""}`} />
          Rafraîchir
        </Button>
      </header>

      <div className="grid grid-cols-2 md:grid-cols-5 gap-2">
        {[
          { k: "all", label: "Total", v: stats.total, icon: Wifi },
          { k: "live", label: "Live <2m", v: stats.live, icon: Radio },
          { k: "active", label: "En course/mission", v: stats.onRide + stats.onMission, icon: Bike },
          { k: "stale", label: "Stale >10m", v: stats.stale, icon: WifiOff },
        ].map((s) => (
          <button
            key={s.k}
            onClick={() => setFilter(s.k as any)}
            className={`text-left p-3 rounded-md border transition-colors ${
              filter === s.k ? "border-primary bg-primary/5" : "border-border hover:bg-muted/50"
            }`}
          >
            <div className="text-xs text-muted-foreground uppercase tracking-wider">{s.label}</div>
            <div className="text-2xl font-mono tabular-nums">{s.v}</div>
          </button>
        ))}
      </div>

      <Card className="overflow-hidden">
        {loading && rows.length === 0 ? (
          <div className="p-10 flex items-center justify-center">
            <Loader2 className="w-5 h-5 animate-spin text-primary" />
          </div>
        ) : filtered.length === 0 ? (
          <div className="p-10 text-center text-sm text-muted-foreground">
            Aucun signal chauffeur pour ce filtre.
          </div>
        ) : (
          <table className="w-full text-sm">
            <thead className="bg-muted/40 text-xs uppercase tracking-wider text-muted-foreground">
              <tr>
                <th className="text-left p-2">Chauffeur</th>
                <th className="text-left p-2">Statut</th>
                <th className="text-left p-2">Fraîcheur</th>
                <th className="text-left p-2">Position</th>
                <th className="text-left p-2">Précision</th>
                <th className="text-left p-2">Source</th>
                <th className="text-left p-2">Réf.</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map((r) => {
                const f = freshness(r.last_ping_at);
                return (
                  <tr key={r.driver_user_id} className="border-t border-border/60">
                    <td className="p-2 font-mono text-xs">{r.driver_user_id.slice(0, 8)}…</td>
                    <td className="p-2">
                      <Badge
                        variant={
                          r.status === "active_ride" || r.status === "active_mission"
                            ? "default"
                            : r.status === "offline"
                              ? "outline"
                              : "secondary"
                        }
                      >
                        {STATUS_LABEL[r.status]}
                      </Badge>
                    </td>
                    <td className="p-2">
                      <span
                        className={`text-xs font-mono px-1.5 py-0.5 rounded ${
                          f === "live"
                            ? "bg-emerald-500/15 text-emerald-700 dark:text-emerald-400"
                            : f === "recent"
                              ? "bg-amber-500/15 text-amber-700 dark:text-amber-400"
                              : "bg-muted text-muted-foreground"
                        }`}
                      >
                        {f}
                      </span>
                    </td>
                    <td className="p-2 font-mono text-xs tabular-nums">
                      {r.lat.toFixed(4)}, {r.lng.toFixed(4)}
                    </td>
                    <td className="p-2 font-mono text-xs tabular-nums">
                      {r.accuracy_meters != null ? `${Math.round(r.accuracy_meters)}m` : "—"}
                    </td>
                    <td className="p-2 text-xs text-muted-foreground">{r.source}</td>
                    <td className="p-2 text-xs">
                      {r.active_ride_id ? (
                        <span className="inline-flex items-center gap-1">
                          <Bike className="w-3 h-3" /> ride
                        </span>
                      ) : r.active_mission_id ? (
                        <span className="inline-flex items-center gap-1">
                          <Package className="w-3 h-3" /> mission
                        </span>
                      ) : (
                        "—"
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </Card>
    </div>
  );
}
