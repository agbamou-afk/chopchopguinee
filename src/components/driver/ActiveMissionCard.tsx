import { useState } from "react";
import { motion } from "framer-motion";
import { Bike, UtensilsCrossed, ShoppingBag, Package, MapPin, Navigation, Loader2, AlertTriangle, Phone, ShieldCheck, Check } from "lucide-react";
import { Button } from "@/components/ui/button";
import { formatGNF } from "@/lib/format";
import { toast } from "sonner";
import {
  MISSION_NEXT_LABEL,
  MISSION_STATE_LABEL,
  MISSION_TYPE_SHORT,
  isTerminalState,
  type Mission,
  type MissionType,
  type MissionState,
} from "@/lib/missions/types";
import {
  advanceMission,
  confirmDropoff,
  confirmPickup,
} from "@/lib/missions/missions";
import { MissionIssueSheet } from "./MissionIssueSheet";

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
  const Icon = ICONS[mission.type] ?? Package;
  const ctaLabel = MISSION_NEXT_LABEL[mission.state];
  const terminal = isTerminalState(mission.state);
  const phone = extractPhone(mission.payload_summary);
  const activeIdx = STEP_INDEX[mission.state];

  const handleNext = async () => {
    if (busy) return;
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
      className="rounded-2xl bg-card border border-primary/30 p-4 shadow-card"
    >
      <div className="flex items-center justify-between mb-2">
        <span className="inline-flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wide text-primary">
          <Icon className="w-3.5 h-3.5" />
          {MISSION_TYPE_SHORT[mission.type]}
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
          {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : ctaLabel}
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