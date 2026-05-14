import { ModulePage } from "@/components/admin/ModulePage";
import { StatGrid, FilterChip } from "@/components/admin/AdminMock";
import { Card } from "@/components/ui/card";
import {
  Activity, Bike, Package, Clock, AlertTriangle, WifiOff, Hourglass, CheckCircle2, Search, Navigation, MapPin, Flag,
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

const PHASE_META: Record<RidePhase, { label: string; tone: string; icon: typeof Bike }> = {
  searching:  { label: "Recherche",    tone: "bg-amber-100 text-amber-800 border-amber-200",       icon: Search },
  assigned:   { label: "En approche",  tone: "bg-blue-100 text-blue-700 border-blue-200",          icon: Navigation },
  arrived:    { label: "Au point",     tone: "bg-violet-100 text-violet-700 border-violet-200",    icon: MapPin },
  in_trip:    { label: "En course",    tone: "bg-emerald-100 text-emerald-700 border-emerald-200", icon: Bike },
  completed:  { label: "Terminée",     tone: "bg-muted text-muted-foreground border-border",       icon: CheckCircle2 },
  cancelled:  { label: "Annulée",      tone: "bg-rose-100 text-rose-700 border-rose-200",          icon: Flag },
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
        { label: "Courses actives",      value: String(counts.active),    icon: Bike,      tone: "text-emerald-600" },
        { label: "Pickups en attente",   value: String(counts.arrived),   icon: Hourglass, tone: "text-violet-600" },
        { label: "Recherche chauffeur",  value: String(counts.searching), icon: Search,    tone: "text-amber-600" },
        { label: "Alertes",              value: String(counts.alerts),    icon: AlertTriangle, tone: "text-rose-600" },
      ]} />
      <AdminLiveOpsMap variant="moto" />
      <div className="flex gap-2 flex-wrap">
        {["Tous", "Alertes", "Recherche", "En course", "Hors ligne"].map((x) => (
          <FilterChip key={x} label={x} active={f === x} onClick={() => setF(x)} />
        ))}
      </div>
      <div className="space-y-2">
        {filtered.length === 0 && (
          <Card className="p-6 text-center text-sm text-muted-foreground">
            Aucune course ne correspond à ce filtre.
          </Card>
        )}
        {filtered.map((r) => {
          const meta = PHASE_META[r.phase];
          const PhaseIcon = meta.icon;
          const risk = classifyRisk(r);
          const isAlert = risk.kind !== null;
          const cardTone = isAlert
            ? risk.kind === "offline_active"
              ? "border-rose-300 bg-rose-50/60"
              : risk.kind === "stuck"
                ? "border-amber-300 bg-amber-50/60"
                : "border-violet-300 bg-violet-50/60"
            : "";
          return (
            <Card key={r.id} className={`p-3 transition-all hover:shadow-soft ${cardTone}`}>
              <div className="flex items-center gap-3">
                <div className="w-9 h-9 rounded-xl gradient-primary flex items-center justify-center shrink-0">
                  <Bike className="w-4 h-4 text-primary-foreground" />
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <p className="font-medium text-sm">{r.id}</p>
                    <span className={`inline-flex items-center gap-1 text-[11px] px-2 py-0.5 rounded-full border font-medium ${meta.tone}`}>
                      <PhaseIcon className="w-3 h-3" /> {meta.label}
                    </span>
                    {/* Driver presence chip */}
                    {r.driver !== "—" && (
                      <span className={`inline-flex items-center gap-1 text-[11px] px-2 py-0.5 rounded-full border font-medium ${
                        r.driverOnline
                          ? "bg-emerald-50 text-emerald-700 border-emerald-200"
                          : "bg-rose-50 text-rose-700 border-rose-200"
                      }`}>
                        <span className="relative inline-flex h-1.5 w-1.5">
                          {r.driverOnline && (
                            <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-emerald-400/70" />
                          )}
                          <span className={`relative inline-flex h-1.5 w-1.5 rounded-full ${r.driverOnline ? "bg-emerald-500" : "bg-rose-500"}`} />
                        </span>
                        {r.driverOnline ? "En ligne" : "Hors ligne"}
                      </span>
                    )}
                  </div>
                  <p className="text-xs text-muted-foreground truncate mt-0.5">
                    {r.from} → {r.to} · {r.driver}
                  </p>
                </div>
                <div className="text-right shrink-0">
                  <p className="text-[10px] uppercase tracking-wide text-muted-foreground">
                    {r.phase === "in_trip" ? "ETA" : r.phase === "assigned" ? "Arrivée" : "Attente"}
                  </p>
                  <p className="text-sm font-semibold tabular-nums">
                    {r.etaMin != null ? `${r.etaMin} min` : `${r.waitingMin}′`}
                  </p>
                </div>
              </div>
              {isAlert && (
                <div className={`mt-2 flex items-center gap-2 text-[11px] font-medium px-2 py-1.5 rounded-md ${
                  risk.kind === "offline_active" ? "bg-rose-100 text-rose-800"
                  : risk.kind === "stuck"        ? "bg-amber-100 text-amber-800"
                  :                                "bg-violet-100 text-violet-800"
                }`}>
                  {risk.kind === "offline_active" ? <WifiOff className="w-3.5 h-3.5" />
                   : risk.kind === "stuck"        ? <Hourglass className="w-3.5 h-3.5" />
                   :                                 <AlertTriangle className="w-3.5 h-3.5" />}
                  {risk.label}
                </div>
              )}
            </Card>
          );
        })}
      </div>
    </ModulePage>
  );
}
