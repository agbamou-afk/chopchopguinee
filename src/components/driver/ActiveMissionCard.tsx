import { useMemo, useState } from "react";
import { motion } from "framer-motion";
import { MapPin, Navigation, Loader2, AlertTriangle, Phone, ShieldCheck, Check, Camera, Route } from "lucide-react";
import { Button } from "@/components/ui/button";
import { formatGNF } from "@/lib/format";
import { toast } from "sonner";
import {
  MISSION_STATE_LABEL,
  isTerminalState,
  type Mission,
} from "@/lib/missions/types";
import {
  advanceMission,
  confirmDropoff,
  confirmPickup,
} from "@/lib/missions/missions";
import {
  MISSION_IDENTITY,
  MISSION_PIPELINES,
  currentStep,
  directionsLabel,
  stepIndex,
} from "@/lib/missions/pipelines";
import { MissionIssueSheet } from "./MissionIssueSheet";

/** Extract a phone number from payload_summary (we embed ☎ +224... in Repas). */
function extractPhone(s: string | null): string | null {
  if (!s) return null;
  const m = s.match(/(\+?\d[\d\s.-]{6,})/);
  return m ? m[1].replace(/\s+/g, "") : null;
}

interface ActiveMissionCardProps {
  mission: Mission;
  onChange?: (m: Mission) => void;
}

export function ActiveMissionCard({ mission, onChange }: ActiveMissionCardProps) {
  const [busy, setBusy] = useState(false);
  const [issueOpen, setIssueOpen] = useState(false);
  const [proofTaken, setProofTaken] = useState(false);
  const identity = MISSION_IDENTITY[mission.type];
  const pipeline = MISSION_PIPELINES[mission.type];
  const Icon = identity.icon;
  const step = currentStep(mission);
  const activeIdx = stepIndex(mission);
  const terminal = isTerminalState(mission.state);
  const phone = extractPhone(mission.payload_summary);
  const proof = step?.proof;
  const proofBlocks =
    !!proof && proof.requirement === "required" && !proofTaken;
  const dirLabel = useMemo(() => directionsLabel(mission), [mission]);

  const openDirections = () => {
    if (mission.pickup_lat && mission.pickup_lng && activeIdx <= 1) {
      window.open(
        `https://www.google.com/maps/dir/?api=1&destination=${mission.pickup_lat},${mission.pickup_lng}`,
        "_blank",
      );
      return;
    }
    if (mission.dropoff_lat && mission.dropoff_lng) {
      window.open(
        `https://www.google.com/maps/dir/?api=1&destination=${mission.dropoff_lat},${mission.dropoff_lng}`,
        "_blank",
      );
      return;
    }
    toast("Itinéraire indisponible", { description: "Coordonnées manquantes." });
  };

  const handleNext = async () => {
    if (busy) return;
    if (proofBlocks) {
      toast("Photo requise", { description: proof?.label });
      return;
    }
    setBusy(true);
    try {
      let updated: Mission;
      if (mission.state === "arrived_pickup") {
        updated = await confirmPickup(mission.id, "manual");
        toast.success("Retrait confirmé");
      } else if (mission.state === "arrived_dropoff") {
        updated = await confirmDropoff(mission.id, "manual");
        toast.success("Livraison confirmée");
      } else {
        updated = await advanceMission(mission.id, mission.state);
      }
      setProofTaken(false);
      onChange?.(updated);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Action impossible");
    } finally {
      setBusy(false);
    }
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
          {identity.label}
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

      {/* Mini checklist timeline */}
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
          onClick={openDirections}
        >
          <Route className="w-4 h-4" />
          {dirLabel}
        </Button>
      )}

      {!terminal && proof && (
        <button
          type="button"
          onClick={() => {
            setProofTaken(true);
            toast.success("Photo enregistrée", { description: proof.label });
          }}
          className={`w-full mb-2 inline-flex items-center justify-center gap-2 h-11 rounded-xl border text-sm font-semibold transition-colors ${
            proofTaken
              ? "border-primary/40 bg-primary/10 text-primary"
              : "border-border text-foreground hover:bg-muted"
          }`}
        >
          {proofTaken ? <Check className="w-4 h-4" /> : <Camera className="w-4 h-4" />}
          {proofTaken ? "Photo prête" : proof.label}
          {proof.requirement === "optional" && !proofTaken && (
            <span className="text-[10px] text-muted-foreground ml-1">(facultatif)</span>
          )}
        </button>
      )}

      {!terminal && step && (
        <Button
          className="w-full h-12"
          onClick={handleNext}
          disabled={busy || proofBlocks}
        >
          {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : step.cta}
        </Button>
      )}

      {!terminal && (
        <div className="mt-2 flex items-center gap-2">
          {phone && (
            <a
              href={`tel:${phone}`}
              className="flex-1 inline-flex items-center justify-center gap-1.5 h-10 rounded-xl border border-border text-sm font-semibold text-foreground hover:bg-muted"
            >
              <Phone className="w-4 h-4" /> Appeler
            </a>
          )}
          <button
            type="button"
            onClick={() => setIssueOpen(true)}
            disabled={busy}
            className={`${phone ? "flex-1" : "w-full"} inline-flex items-center justify-center gap-1.5 h-10 rounded-xl border border-border text-sm font-semibold text-muted-foreground hover:text-destructive hover:border-destructive/40 disabled:opacity-50`}
          >
            <AlertTriangle className="w-4 h-4" />
            Problème
          </button>
        </div>
      )}

      {!terminal && (
        <p className="mt-2 inline-flex items-center gap-1 text-[10px] text-muted-foreground">
          <ShieldCheck className="w-3 h-3 text-primary" /> Mission suivie par CHOP CHOP
        </p>
      )}

      <MissionIssueSheet
        missionId={mission.id}
        open={issueOpen}
        onOpenChange={setIssueOpen}
        onReported={onChange}
      />
    </motion.div>
  );
}