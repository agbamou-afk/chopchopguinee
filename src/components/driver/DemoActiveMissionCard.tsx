import { useMemo, useState } from "react";
import { motion } from "framer-motion";
import { MapPin, Navigation, ShieldCheck, Check, AlertTriangle, Camera, Route } from "lucide-react";
import { Button } from "@/components/ui/button";
import { formatGNF } from "@/lib/format";
import {
  MISSION_NEXT_STATE,
  MISSION_STATE_LABEL,
  isTerminalState,
  type Mission,
} from "@/lib/missions/types";
import {
  MISSION_IDENTITY,
  MISSION_PIPELINES,
  currentStep,
  directionsLabel,
  stepIndex,
} from "@/lib/missions/pipelines";
import { toast } from "sonner";

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
  const [proofTaken, setProofTaken] = useState(false);
  const identity = MISSION_IDENTITY[mission.type];
  const pipeline = MISSION_PIPELINES[mission.type];
  const Icon = identity.icon;
  const step = currentStep(mission);
  const activeIdx = stepIndex(mission);
  const terminal = isTerminalState(mission.state);
  const dirLabel = useMemo(() => directionsLabel(mission), [mission]);

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
      setProofTaken(false);
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
      className={`rounded-2xl bg-card border ${identity.accent.border} p-4 shadow-card`}
    >
      <div className="flex items-center justify-between mb-2">
        <span className={`inline-flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wide ${identity.accent.chipText}`}>
          <Icon className="w-3.5 h-3.5" />
          {identity.label} · démo
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
          {pipeline.steps.map((s, i) => {
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
                  {s.short}
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

      {!terminal && (
        <Button
          variant="outline"
          className="w-full h-10 mb-2 gap-2"
          onClick={() => toast("Itinéraire (démo)", { description: dirLabel })}
        >
          <Route className="w-4 h-4" /> {dirLabel}
        </Button>
      )}

      {!terminal && step?.proof && (
        <button
          type="button"
          onClick={() => {
            setProofTaken(true);
            toast.success("Photo enregistrée (démo)", { description: step.proof?.label });
          }}
          className={`w-full mb-2 inline-flex items-center justify-center gap-2 h-11 rounded-xl border text-sm font-semibold transition-colors ${
            proofTaken
              ? "border-primary/40 bg-primary/10 text-primary"
              : "border-border text-foreground hover:bg-muted"
          }`}
        >
          {proofTaken ? <Check className="w-4 h-4" /> : <Camera className="w-4 h-4" />}
          {proofTaken ? "Photo prête" : step.proof.label}
          {step.proof.requirement === "optional" && !proofTaken && (
            <span className="text-[10px] text-muted-foreground ml-1">(facultatif)</span>
          )}
        </button>
      )}

      {!terminal && step && (
        <Button
          className="w-full h-12"
          onClick={handleNext}
          disabled={busy || (step.proof?.requirement === "required" && !proofTaken)}
        >
          {step.cta}
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