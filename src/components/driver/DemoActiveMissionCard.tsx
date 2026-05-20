import { useState } from "react";
import { motion } from "framer-motion";
import { Bike, UtensilsCrossed, ShoppingBag, Package, MapPin, Navigation, ShieldCheck, Check, AlertTriangle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { formatGNF } from "@/lib/format";
import {
  MISSION_NEXT_LABEL,
  MISSION_NEXT_STATE,
  MISSION_STATE_LABEL,
  MISSION_TYPE_SHORT,
  isTerminalState,
  type Mission,
  type MissionState,
  type MissionType,
} from "@/lib/missions/types";
import { toast } from "sonner";

const ICONS: Record<MissionType, typeof Bike> = {
  ride: Bike,
  food_delivery: UtensilsCrossed,
  marketplace_delivery: ShoppingBag,
  package_delivery: Package,
};

const STEPS: { key: MissionState; label: string }[] = [
  { key: "heading_to_pickup", label: "Vers retrait" },
  { key: "arrived_pickup", label: "Au retrait" },
  { key: "picked_up", label: "Récupéré" },
  { key: "heading_to_dropoff", label: "Vers client" },
  { key: "delivered", label: "Livré" },
];

const STEP_INDEX: Record<MissionState, number> = {
  assigned: 0,
  heading_to_pickup: 0,
  arrived_pickup: 1,
  picked_up: 2,
  heading_to_dropoff: 3,
  arrived_dropoff: 4,
  delivered: 4,
  failed: -1,
};

interface DemoActiveMissionCardProps {
  mission: Mission;
  onChange: (m: Mission) => void;
  onClose: () => void;
}

/**
 * Demo-only active mission card. Mirrors the visual language of
 * ActiveMissionCard but advances the lifecycle locally — never touches the
 * database. Used exclusively by the Driver Demo launcher.
 */
export function DemoActiveMissionCard({ mission, onChange, onClose }: DemoActiveMissionCardProps) {
  const [busy, setBusy] = useState(false);
  const Icon = ICONS[mission.type] ?? Package;
  const ctaLabel = MISSION_NEXT_LABEL[mission.state];
  const terminal = isTerminalState(mission.state);
  const activeIdx = STEP_INDEX[mission.state];

  const handleNext = () => {
    if (busy) return;
    setBusy(true);
    const next = MISSION_NEXT_STATE[mission.state];
    if (!next) {
      setBusy(false);
      return;
    }
    window.setTimeout(() => {
      const updated: Mission = {
        ...mission,
        state: next,
        pickup_confirmed_at:
          next === "picked_up" ? new Date().toISOString() : mission.pickup_confirmed_at,
        dropoff_confirmed_at:
          next === "delivered" ? new Date().toISOString() : mission.dropoff_confirmed_at,
        updated_at: new Date().toISOString(),
      };
      onChange(updated);
      if (next === "picked_up") toast.success("Retrait confirmé (démo)");
      if (next === "delivered") toast.success("Livraison confirmée (démo)");
      setBusy(false);
    }, 250);
  };

  const handleIssue = () => {
    onChange({ ...mission, state: "failed", issue_reason: "Problème signalé (démo)" });
    toast.info("Problème enregistré (démo)");
  };

  return (
    <motion.div
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      className="rounded-2xl bg-card border border-primary/30 p-4 shadow-card"
    >
      <div className="flex items-center justify-between mb-2">
        <span className="inline-flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wide text-primary">
          <Icon className="w-3.5 h-3.5" />
          {MISSION_TYPE_SHORT[mission.type]} · démo
        </span>
        <span className="text-[10px] font-bold uppercase tracking-wider text-muted-foreground">
          {MISSION_STATE_LABEL[mission.state]}
        </span>
      </div>

      <div className="space-y-1.5 mb-3">
        {mission.pickup_address && (
          <div className="flex items-start gap-2 text-sm text-foreground">
            <MapPin className="w-4 h-4 mt-0.5 text-primary shrink-0" />
            <span className="truncate">{mission.pickup_address}</span>
          </div>
        )}
        {mission.dropoff_address && (
          <div className="flex items-start gap-2 text-sm text-foreground">
            <Navigation className="w-4 h-4 mt-0.5 text-secondary shrink-0" />
            <span className="truncate">{mission.dropoff_address}</span>
          </div>
        )}
      </div>

      {!terminal && activeIdx >= 0 && (
        <div className="flex items-center justify-between mb-3 px-0.5">
          {STEPS.map((s, i) => {
            const done = i < activeIdx;
            const active = i === activeIdx;
            return (
              <div key={s.key} className="flex-1 flex flex-col items-center gap-1">
                <span
                  className={`w-5 h-5 rounded-full flex items-center justify-center text-[9px] font-bold ${
                    done
                      ? "bg-primary text-primary-foreground"
                      : active
                        ? "bg-primary/15 text-primary ring-2 ring-primary"
                        : "bg-muted text-muted-foreground"
                  }`}
                >
                  {done ? <Check className="w-3 h-3" /> : i + 1}
                </span>
                <span className={`text-[9px] leading-tight text-center ${active ? "text-foreground font-semibold" : "text-muted-foreground"}`}>
                  {s.label}
                </span>
              </div>
            );
          })}
        </div>
      )}

      <div className="flex items-center justify-between mb-3">
        <span className="text-xs text-muted-foreground">Gain estimé</span>
        <span className="text-sm font-bold tabular-nums">
          {formatGNF(mission.estimated_earning_gnf)}
        </span>
      </div>

      {!terminal && ctaLabel && (
        <Button className="w-full h-12" onClick={handleNext} disabled={busy}>
          {ctaLabel}
        </Button>
      )}

      {terminal && (
        <Button variant="outline" className="w-full h-11" onClick={onClose}>
          Terminer la démo
        </Button>
      )}

      {!terminal && (
        <button
          type="button"
          onClick={handleIssue}
          className="mt-2 w-full inline-flex items-center justify-center gap-1.5 h-10 rounded-xl border border-border text-sm font-semibold text-muted-foreground hover:text-destructive hover:border-destructive/40"
        >
          <AlertTriangle className="w-4 h-4" />
          Signaler un problème
        </button>
      )}

      <p className="mt-2 inline-flex items-center gap-1 text-[10px] text-muted-foreground">
        <ShieldCheck className="w-3 h-3 text-primary" /> Mission suivie par CHOP CHOP · mode démo
      </p>
    </motion.div>
  );
}