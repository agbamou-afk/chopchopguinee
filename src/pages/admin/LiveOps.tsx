import { ModulePage } from "@/components/admin/ModulePage";
import { StatGrid, FilterChip } from "@/components/admin/AdminMock";
import { Card } from "@/components/ui/card";
import {
  Bike, AlertTriangle, WifiOff, Hourglass, CheckCircle2, Search, Navigation, MapPin, Flag,
} from "lucide-react";
import { useState } from "react";
import { AdminLiveOpsMap } from "@/components/admin/AdminLiveOpsMap";

/**
 * Canonical ride lifecycle phases as understood by ops.
 * Each maps to a label + color so the wall is scannable at a glance.
 */
type RidePhase =
  | "searching"   // pending, no driver yet
  | "assigned"    // driver assigned, en route to pickup
  | "arrived"     // driver at pickup, awaiting client confirmation
  | "in_trip"     // ride started
  | "completed"
  | "cancelled";

interface OpsRide {
  id: string;
  driver: string;
  driverOnline: boolean;
  from: string;
  to: string;
  phase: RidePhase;
  etaMin: number | null;
  waitingMin: number; // age since creation OR since pickup-arrived
}

const RIDES: OpsRide[] = [
  { id: "CC-RD-9881", driver: "Amadou D.", driverOnline: true,  from: "Kipé",            to: "Kaloum",   phase: "in_trip",   etaMin: 8,  waitingMin: 4 },
  { id: "CC-RD-9882", driver: "Sékou C.",  driverOnline: true,  from: "Madina",          to: "Ratoma",   phase: "assigned",  etaMin: 12, waitingMin: 2 },
  { id: "CC-RD-9883", driver: "—",         driverOnline: false, from: "Hamdallaye",      to: "Coyah",    phase: "searching", etaMin: null, waitingMin: 6 },
  { id: "CC-LV-7720", driver: "Fatou T.",  driverOnline: true,  from: "Le Damier",       to: "Dixinn",   phase: "arrived",   etaMin: 0,  waitingMin: 9 },
  { id: "CC-LV-7721", driver: "Ibrahima B.", driverOnline: false, from: "Pharmacie Niger", to: "Lambanyi", phase: "in_trip",   etaMin: null, waitingMin: 14 },
];

const PHASE_META: Record<RidePhase, { label: string; chip: string; icon: typeof Bike }> = {
  searching: { label: "Recherche",   chip: "chip-warn",   icon: Search },
  assigned:  { label: "En approche", chip: "chip-info",   icon: Navigation },
  arrived:   { label: "Au point",    chip: "chip-violet", icon: MapPin },
  in_trip:   { label: "En course",   chip: "chip-ok",     icon: Bike },
  completed: { label: "Terminée",    chip: "chip-mute",   icon: CheckCircle2 },
  cancelled: { label: "Annulée",     chip: "chip-err",    icon: Flag },
};

/** Risk thresholds (minutes) */
const STUCK_SEARCH_MIN = 5;     // pending without driver too long
const LONG_PICKUP_MIN  = 7;     // driver "arrived" but client hasn't confirmed
const LONG_TRIP_MIN    = 12;    // trip running unusually long

function classifyRisk(r: OpsRide): { kind: "stuck" | "long_wait" | "offline_active" | null; label: string } {
  if (!r.driverOnline && (r.phase === "assigned" || r.phase === "arrived" || r.phase === "in_trip")) {
    return { kind: "offline_active", label: "Chauffeur hors ligne" };
  }
  if (r.phase === "searching" && r.waitingMin >= STUCK_SEARCH_MIN) {
    return { kind: "stuck", label: `Sans chauffeur depuis ${r.waitingMin} min` };
  }
  if (r.phase === "arrived" && r.waitingMin >= LONG_PICKUP_MIN) {
    return { kind: "long_wait", label: `Pickup en attente ${r.waitingMin} min` };
  }
  if (r.phase === "in_trip" && r.waitingMin >= LONG_TRIP_MIN) {
    return { kind: "long_wait", label: `Course longue ${r.waitingMin} min` };
  }
  return { kind: null, label: "" };
}

export default function LiveOps() {
  const [f, setF] = useState("Tous");

  const filtered = RIDES.filter((r) => {
    if (f === "Tous") return true;
    if (f === "Alertes") return classifyRisk(r).kind !== null;
    if (f === "Recherche") return r.phase === "searching";
    if (f === "En course") return r.phase === "in_trip";
    if (f === "Hors ligne") return !r.driverOnline && r.phase !== "searching";
    return true;
  });

  const counts = {
    active: RIDES.filter((r) => r.phase === "in_trip" || r.phase === "assigned").length,
    arrived: RIDES.filter((r) => r.phase === "arrived").length,
    searching: RIDES.filter((r) => r.phase === "searching").length,
    alerts: RIDES.filter((r) => classifyRisk(r).kind !== null).length,
  };

  return (
    <ModulePage module="live_ops" title="Live Operations" subtitle="Centre de commande en temps réel">
      <StatGrid items={[
        { label: "Courses actives",      value: String(counts.active),    icon: Bike,          tone: "text-primary" },
        { label: "Pickups en attente",   value: String(counts.arrived),   icon: Hourglass,     tone: "text-muted-foreground/70" },
        { label: "Recherche chauffeur",  value: String(counts.searching), icon: Search,        tone: "text-secondary" },
        { label: "Alertes",              value: String(counts.alerts),    icon: AlertTriangle, tone: "text-destructive" },
      ]} />
      <AdminLiveOpsMap variant="moto" />
      <div className="flex gap-2 flex-wrap">
        {["Tous", "Alertes", "Recherche", "En course", "Hors ligne"].map((x) => (
          <FilterChip key={x} label={x} active={f === x} onClick={() => setF(x)} />
        ))}
      </div>
      <div className="space-y-1.5">
        {filtered.length === 0 && (
          <Card className="p-6 text-center text-sm text-muted-foreground border-dashed">
            Aucune course ne correspond à ce filtre.
          </Card>
        )}
        {filtered.map((r) => {
          const meta = PHASE_META[r.phase];
          const PhaseIcon = meta.icon;
          const risk = classifyRisk(r);
          const isAlert = risk.kind !== null;
          const accent = isAlert
            ? risk.kind === "offline_active" ? "border-l-destructive"
              : risk.kind === "stuck"        ? "border-l-secondary"
              :                                 "border-l-[hsl(265_50%_55%)]"
            : "border-l-transparent";
          return (
            <div key={r.id} className={`admin-card p-2.5 border-l-2 ${accent} transition-colors hover:bg-muted/40`}>
              <div className="flex items-center gap-3">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <p className="font-mono text-[12px] font-medium tracking-tight">{r.id}</p>
                    <span className={`chip-status ${meta.chip}`}>
                      <PhaseIcon className="w-3 h-3 -ml-0.5" /> {meta.label}
                    </span>
                    {r.driver !== "—" && (
                      <span className={`chip-status ${r.driverOnline ? "chip-ok" : "chip-err"}`}>
                        {r.driverOnline ? "En ligne" : "Hors ligne"}
                      </span>
                    )}
                  </div>
                  <p className="text-[11.5px] text-muted-foreground truncate mt-0.5 font-mono">
                    {r.from} → {r.to} · {r.driver}
                  </p>
                </div>
                <div className="text-right shrink-0">
                  <p className="font-mono text-[9.5px] uppercase tracking-wider text-muted-foreground/70">
                    {r.phase === "in_trip" ? "ETA" : r.phase === "assigned" ? "Arrivée" : "Attente"}
                  </p>
                  <p className="text-[13px] font-semibold tabular-nums">
                    {r.etaMin != null ? `${r.etaMin}m` : `${r.waitingMin}m`}
                  </p>
                </div>
              </div>
              {isAlert && (
                <div className="mt-2 flex items-center gap-1.5 text-[11px] text-foreground/75">
                  {risk.kind === "offline_active" ? <WifiOff className="w-3 h-3 text-destructive" />
                   : risk.kind === "stuck"        ? <Hourglass className="w-3 h-3 text-secondary" />
                   :                                 <AlertTriangle className="w-3 h-3 text-[hsl(265_50%_55%)]" />}
                  <span className="font-mono tracking-tight">{risk.label}</span>
                </div>
              )}
            </div>
          );
        })}
      </div>
    </ModulePage>
  );
}
