import { motion } from "framer-motion";
import {
  ArrowUp, ArrowUpLeft, ArrowUpRight, CornerUpLeft, CornerUpRight,
  RotateCcw, Flag, Volume2, VolumeX, Loader2, AlertTriangle,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";
import type { TurnByTurnState } from "@/hooks/useTurnByTurn";
import { formatDistance, formatDuration } from "@/lib/maps/geo";
import { Button } from "@/components/ui/button";

function maneuverIcon(maneuver: string | null | undefined): LucideIcon {
  const m = (maneuver ?? "").toLowerCase();
  if (m.includes("uturn")) return RotateCcw;
  if (m.includes("sharp-left") || m.includes("turn-left")) return CornerUpLeft;
  if (m.includes("sharp-right") || m.includes("turn-right")) return CornerUpRight;
  if (m.includes("slight-left") || m.includes("fork-left")) return ArrowUpLeft;
  if (m.includes("slight-right") || m.includes("fork-right")) return ArrowUpRight;
  if (m.includes("destination") || m.includes("arrive")) return Flag;
  return ArrowUp;
}

function stripHtml(s: string): string {
  return s.replace(/<[^>]+>/g, "");
}

interface Props {
  state: TurnByTurnState & { reroute: () => void };
  muted: boolean;
  onToggleMute: () => void;
}

/**
 * Compact turn-by-turn HUD pinned above the action sheet.
 * Shows current maneuver + distance, next instruction, remaining ETA,
 * and a manual reroute button.
 */
export function NavigationHud({ state, muted, onToggleMute }: Props) {
  const { currentStep, nextStep, distanceToManeuverM, remainingDistanceM,
    remainingDurationS, offRoute, rerouting, reroute } = state;
  if (!currentStep) return null;
  const Icon = maneuverIcon(currentStep.maneuver);

  return (
    <motion.div
      initial={{ y: -16, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      className="absolute left-3 right-3 top-3 rounded-2xl border border-border bg-card/95 backdrop-blur shadow-lg overflow-hidden"
    >
      <div className="flex items-stretch">
        <div className="flex items-center justify-center bg-primary/10 px-4 shrink-0">
          <Icon className="w-9 h-9 text-primary" />
        </div>
        <div className="flex-1 min-w-0 px-3 py-2">
          <div className="flex items-baseline gap-2">
            <span className="text-xl font-bold tabular-nums">
              {distanceToManeuverM != null ? formatDistance(distanceToManeuverM) : "—"}
            </span>
            {(rerouting || offRoute) && (
              <span className="text-[10px] uppercase tracking-wide text-amber-600 dark:text-amber-400 inline-flex items-center gap-1">
                {rerouting ? <Loader2 className="w-3 h-3 animate-spin" /> : <AlertTriangle className="w-3 h-3" />}
                {rerouting ? "Recalcul…" : "Hors itinéraire"}
              </span>
            )}
          </div>
          <p className="text-sm font-medium leading-tight line-clamp-2">
            {stripHtml(currentStep.instruction)}
          </p>
          {nextStep && (
            <p className="text-[11px] text-muted-foreground mt-0.5 line-clamp-1">
              Puis : {stripHtml(nextStep.instruction)}
            </p>
          )}
        </div>
        <div className="flex flex-col items-end justify-between gap-1 px-2 py-2 shrink-0">
          <Button size="icon" variant="ghost" className="h-7 w-7" onClick={onToggleMute}
            aria-label={muted ? "Activer la voix" : "Couper la voix"}>
            {muted ? <VolumeX className="w-4 h-4" /> : <Volume2 className="w-4 h-4" />}
          </Button>
          <div className="text-right leading-tight">
            <div className="text-xs font-semibold tabular-nums">{formatDuration(remainingDurationS)}</div>
            <div className="text-[10px] text-muted-foreground tabular-nums">{formatDistance(remainingDistanceM)}</div>
          </div>
        </div>
      </div>
      {offRoute && !rerouting && (
        <button type="button" onClick={reroute}
          className="w-full text-[11px] py-1 bg-amber-500/10 text-amber-700 dark:text-amber-400 hover:bg-amber-500/20 transition">
          Recalculer l'itinéraire
        </button>
      )}
    </motion.div>
  );
}