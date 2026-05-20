import { motion } from "framer-motion";
import { MapPin, Navigation, ShieldCheck, Sparkles } from "lucide-react";
import { Button } from "@/components/ui/button";
import { formatGNF } from "@/lib/format";
import type { Mission } from "@/lib/missions/types";
import { MISSION_IDENTITY } from "@/lib/missions/pipelines";
import { resolveDistrict, districtChipClasses } from "@/lib/districts";
import { formatDistrictPair } from "@/lib/maps/zones";

interface MissionRequestCardProps {
  mission: Mission;
  onAccept?: (id: string) => void;
  onDecline?: (id: string) => void;
  busy?: boolean;
  /** Driver's preferred operating district. When the mission's pickup
   *  matches, we surface a "Mission dans votre zone" hint. */
  preferredDistrict?: string | null;
}

/**
 * Incoming-mission card for couriers — works for any mission type.
 * Mirrors the calm, operational tone of the ride request card.
 */
export function MissionRequestCard({
  mission,
  onAccept,
  onDecline,
  busy,
  preferredDistrict,
}: MissionRequestCardProps) {
  const identity = MISSION_IDENTITY[mission.type];
  const Icon = identity.icon;
  const { pickup: pickupLabel, dropoff: dropoffLabel } = identity.endpointLabels;
  const km = mission.estimated_distance_m ? (mission.estimated_distance_m / 1000).toFixed(1) : null;
  const minutes = mission.estimated_duration_s ? Math.round(mission.estimated_duration_s / 60) : null;

  const pickupDistrict = resolveDistrict({
    point: mission.pickup_lat != null && mission.pickup_lng != null
      ? { lat: mission.pickup_lat, lng: mission.pickup_lng } : null,
    text: mission.pickup_address,
  });
  const dropoffDistrict = resolveDistrict({
    point: mission.dropoff_lat != null && mission.dropoff_lng != null
      ? { lat: mission.dropoff_lat, lng: mission.dropoff_lng } : null,
    text: mission.dropoff_address,
  });
  const districtPair = formatDistrictPair(
    mission.pickup_lat != null && mission.pickup_lng != null
      ? { lat: mission.pickup_lat, lng: mission.pickup_lng } : null,
    mission.dropoff_lat != null && mission.dropoff_lng != null
      ? { lat: mission.dropoff_lat, lng: mission.dropoff_lng } : null,
  ) ?? (pickupDistrict && dropoffDistrict
      ? (pickupDistrict.name === dropoffDistrict.name ? pickupDistrict.name : `${pickupDistrict.name} → ${dropoffDistrict.name}`)
      : pickupDistrict?.name ?? dropoffDistrict?.name ?? null);
  const inPreferredZone = !!(
    preferredDistrict && pickupDistrict && pickupDistrict.name === preferredDistrict
  );

  return (
    <motion.div
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      className={`rounded-2xl bg-card border ${identity.accent.border} p-4 shadow-card`}
    >
      {/* Primary: type identity + earning */}
      <div className="flex items-start justify-between gap-3 mb-3">
        <div className="flex items-start gap-2.5 min-w-0">
          <span
            className={`w-9 h-9 rounded-xl ${identity.accent.iconBg} ${identity.accent.iconText} flex items-center justify-center shrink-0`}
            aria-hidden
          >
            <Icon className="w-4.5 h-4.5" />
          </span>
          <div className="min-w-0">
            <span className={`block text-[10px] font-bold uppercase tracking-[0.15em] ${identity.accent.chipText}`}>
              {identity.label}
            </span>
            <span className="block text-[11px] text-muted-foreground truncate">
              {identity.subtitle}
            </span>
          </div>
        </div>
        <div className="text-right shrink-0">
          <p className="text-[10px] text-muted-foreground">Gain estimé</p>
          <span className="text-lg font-extrabold tabular-nums text-foreground">
            {formatGNF(mission.estimated_earning_gnf)}
          </span>
        </div>
      </div>

      {/* District continuity row */}
      {(districtPair || inPreferredZone) && (
        <div className="flex flex-wrap items-center gap-1.5 mb-2">
          {districtPair && pickupDistrict && (
            <span className={districtChipClasses(pickupDistrict.tone)}>{districtPair}</span>
          )}
          {inPreferredZone && (
            <span className="inline-flex items-center gap-1 text-[10px] font-semibold text-primary">
              <Sparkles className="w-3 h-3" /> Mission dans votre zone
            </span>
          )}
        </div>
      )}

      {/* Pickup + dropoff */}
      <div className="space-y-1.5 mb-2">
        {mission.pickup_address && (
          <div className="flex items-start gap-2 text-sm text-foreground">
            <MapPin className="w-4 h-4 mt-0.5 text-primary shrink-0" />
            <span className="truncate">
              <span className="text-muted-foreground text-[10px] uppercase tracking-wide mr-1">{pickupLabel}</span>
              {mission.pickup_address}
            </span>
          </div>
        )}
        {mission.dropoff_address && (
          <div className="flex items-start gap-2 text-sm text-foreground">
            <Navigation className="w-4 h-4 mt-0.5 text-secondary shrink-0" />
            <span className="truncate">
              <span className="text-muted-foreground text-[10px] uppercase tracking-wide mr-1">{dropoffLabel}</span>
              {mission.dropoff_address}
            </span>
          </div>
        )}
      </div>

      {/* Secondary: summary */}
      {(mission.payload_summary || km || minutes) && (
        <p className="text-xs text-muted-foreground mb-3 line-clamp-2">
          {[mission.payload_summary, km && `${km} km`, minutes && `${minutes} min`].filter(Boolean).join(" · ")}
        </p>
      )}

      <div className="flex gap-2">
        {onDecline && (
          <Button variant="ghost" className="flex-1 h-12" onClick={() => onDecline(mission.id)} disabled={busy}>
            Refuser
          </Button>
        )}
        {onAccept && (
          <Button className="flex-1 h-12 font-bold" onClick={() => onAccept(mission.id)} disabled={busy}>
            {identity.acceptCta}
          </Button>
        )}
      </div>

      <p className="mt-2 inline-flex items-center gap-1 text-[10px] text-muted-foreground">
        <ShieldCheck className={`w-3 h-3 ${identity.accent.iconText}`} /> {identity.trustHint}
      </p>
    </motion.div>
  );
}