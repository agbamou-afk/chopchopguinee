import { useState } from "react";
import { motion } from "framer-motion";
import { Bike, UtensilsCrossed, ShoppingBag, Package, MapPin, Navigation, Loader2, AlertTriangle } from "lucide-react";
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
} from "@/lib/missions/types";
import {
  advanceMission,
  confirmDropoff,
  confirmPickup,
  reportIssue,
} from "@/lib/missions/missions";

const ICONS: Record<MissionType, typeof Bike> = {
  ride: Bike,
  food_delivery: UtensilsCrossed,
  marketplace_delivery: ShoppingBag,
  package_delivery: Package,
};

interface ActiveMissionCardProps {
  mission: Mission;
  onChange?: (m: Mission) => void;
}

export function ActiveMissionCard({ mission, onChange }: ActiveMissionCardProps) {
  const [busy, setBusy] = useState(false);
  const Icon = ICONS[mission.type] ?? Package;
  const ctaLabel = MISSION_NEXT_LABEL[mission.state];
  const terminal = isTerminalState(mission.state);

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

  const handleIssue = async () => {
    if (busy) return;
    const reason = window.prompt("Décrivez brièvement le problème", "");
    if (!reason) return;
    setBusy(true);
    try {
      const updated = await reportIssue(mission.id, reason);
      onChange?.(updated);
      toast.success("Problème signalé");
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

      <div className="flex items-center justify-between mb-3">
        <span className="text-xs text-muted-foreground">Gain estimé</span>
        <span className="text-sm font-bold tabular-nums">
          {formatGNF(mission.estimated_earning_gnf)}
        </span>
      </div>

      {!terminal && ctaLabel && (
        <Button className="w-full h-10" onClick={handleNext} disabled={busy}>
          {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : ctaLabel}
        </Button>
      )}

      {!terminal && (
        <button
          type="button"
          onClick={handleIssue}
          disabled={busy}
          className="mt-2 w-full inline-flex items-center justify-center gap-1.5 text-[11px] text-muted-foreground hover:text-destructive transition-colors disabled:opacity-50"
        >
          <AlertTriangle className="w-3 h-3" />
          Signaler un problème
        </button>
      )}
    </motion.div>
  );
}