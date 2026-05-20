import { motion } from "framer-motion";
import { Bike, UtensilsCrossed, ShoppingBag, Package, MapPin, Navigation } from "lucide-react";
import { Button } from "@/components/ui/button";
import { formatGNF } from "@/lib/format";
import { MISSION_TYPE_SHORT, type Mission, type MissionType } from "@/lib/missions/types";

const ICONS: Record<MissionType, typeof Bike> = {
  ride: Bike,
  food_delivery: UtensilsCrossed,
  marketplace_delivery: ShoppingBag,
  package_delivery: Package,
};

interface MissionRequestCardProps {
  mission: Mission;
  onAccept?: (id: string) => void;
  onDecline?: (id: string) => void;
  busy?: boolean;
}

/**
 * Incoming-mission card for couriers — works for any mission type.
 * Mirrors the calm, operational tone of the ride request card.
 */
export function MissionRequestCard({ mission, onAccept, onDecline, busy }: MissionRequestCardProps) {
  const Icon = ICONS[mission.type] ?? Package;
  const km = mission.estimated_distance_m ? (mission.estimated_distance_m / 1000).toFixed(1) : null;
  const minutes = mission.estimated_duration_s ? Math.round(mission.estimated_duration_s / 60) : null;

  return (
    <motion.div
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      className="rounded-2xl bg-card border border-border p-4 shadow-card"
    >
      <div className="flex items-center justify-between mb-2">
        <span className="inline-flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wide text-primary">
          <Icon className="w-3.5 h-3.5" />
          {MISSION_TYPE_SHORT[mission.type]}
        </span>
        <span className="font-bold tabular-nums">{formatGNF(mission.estimated_earning_gnf)}</span>
      </div>

      <div className="space-y-1.5 mb-3">
        {mission.pickup_address && (
          <div className="flex items-start gap-2 text-sm text-foreground">
            <MapPin className="w-4 h-4 mt-0.5 text-primary shrink-0" />
            <span className="truncate"><span className="text-muted-foreground text-xs mr-1">Retrait</span>{mission.pickup_address}</span>
          </div>
        )}
        {mission.dropoff_address && (
          <div className="flex items-start gap-2 text-sm text-foreground">
            <Navigation className="w-4 h-4 mt-0.5 text-secondary shrink-0" />
            <span className="truncate"><span className="text-muted-foreground text-xs mr-1">Client</span>{mission.dropoff_address}</span>
          </div>
        )}
      </div>

      {(mission.payload_summary || km || minutes) && (
        <p className="text-xs text-muted-foreground mb-3 truncate">
          {[mission.payload_summary, km && `${km} km`, minutes && `${minutes} min`].filter(Boolean).join(" · ")}
        </p>
      )}

      <div className="flex gap-2">
        {onDecline && (
          <Button variant="ghost" className="flex-1 h-10" onClick={() => onDecline(mission.id)} disabled={busy}>
            Refuser
          </Button>
        )}
        {onAccept && (
          <Button className="flex-1 h-10" onClick={() => onAccept(mission.id)} disabled={busy}>
            Accepter
          </Button>
        )}
      </div>
    </motion.div>
  );
}