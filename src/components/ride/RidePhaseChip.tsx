import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";
import {
  Search, UserCheck, MapPin, Navigation, Flag, CheckCircle2, XCircle,
  type LucideIcon,
} from "lucide-react";

/**
 * Canonical, role-agnostic ride phases. Both client and driver views map their
 * raw `ride.status + metadata.phase` into one of these — so the chip is
 * always identical on both sides.
 */
export type CanonicalRidePhase =
  | "searching"
  | "assigned"
  | "arrived"
  | "in_trip"
  | "at_destination"
  | "completed"
  | "cancelled";

interface PhaseSpec {
  label: string;
  Icon: LucideIcon;
  /** Tailwind classes built from semantic tokens — never raw colors. */
  className: string;
  /** Optional pulse indicator for live, in-motion states. */
  live?: boolean;
}

const SPECS: Record<CanonicalRidePhase, PhaseSpec> = {
  searching: {
    label: "Recherche",
    Icon: Search,
    className:
      "bg-[hsl(var(--brand-yellow-muted))] text-[hsl(var(--brand-black))] border-[hsl(var(--brand-yellow))]/40",
    live: true,
  },
  assigned: {
    label: "Chauffeur assigné",
    Icon: UserCheck,
    className:
      "bg-[hsl(var(--brand-green-muted))] text-[hsl(var(--brand-green))] border-[hsl(var(--brand-green))]/30",
  },
  arrived: {
    label: "Chauffeur arrivé",
    Icon: MapPin,
    className:
      "bg-[hsl(var(--brand-green))] text-[hsl(var(--primary-foreground))] border-[hsl(var(--brand-green))]",
    live: true,
  },
  in_trip: {
    label: "En cours",
    Icon: Navigation,
    className:
      "bg-[hsl(var(--primary))] text-[hsl(var(--primary-foreground))] border-[hsl(var(--primary))]",
    live: true,
  },
  at_destination: {
    label: "Arrivé à destination",
    Icon: Flag,
    className:
      "bg-[hsl(var(--brand-yellow))] text-[hsl(var(--brand-black))] border-[hsl(var(--brand-yellow))]",
  },
  completed: {
    label: "Terminée",
    Icon: CheckCircle2,
    className:
      "bg-[hsl(var(--muted))] text-[hsl(var(--muted-foreground))] border-[hsl(var(--border))]",
  },
  cancelled: {
    label: "Annulée",
    Icon: XCircle,
    className:
      "bg-[hsl(var(--brand-red-muted))] text-[hsl(var(--brand-red))] border-[hsl(var(--brand-red))]/40",
  },
};

/**
 * Derive the canonical phase from a ride row. Single source of truth used by
 * every ride surface so client and driver always see the same chip.
 */
export function deriveRidePhase(input: {
  status?: string | null;
  driver_id?: string | null;
  metadata?: Record<string, unknown> | null;
}): CanonicalRidePhase {
  const status = input.status ?? "pending";
  if (status === "completed") return "completed";
  if (status === "cancelled") return "cancelled";

  const phase = (input.metadata as { phase?: string } | null)?.phase;
  if (phase === "at_destination") return "at_destination";
  if (phase === "on_trip") return "in_trip";
  if (phase === "arrived") return "arrived";
  if (phase === "approach") return "assigned";

  if (status === "in_progress") return input.driver_id ? "in_trip" : "assigned";
  // pending
  return input.driver_id ? "assigned" : "searching";
}

interface ChipProps {
  phase: CanonicalRidePhase;
  size?: "sm" | "md";
  className?: string;
}

export function RidePhaseChip({ phase, size = "md", className }: ChipProps) {
  const spec = SPECS[phase];
  const { Icon, label, live } = spec;
  return (
    <Badge
      variant="outline"
      className={cn(
        "gap-1.5 font-semibold border shadow-sm",
        size === "sm" ? "text-[11px] px-2 py-0.5" : "text-xs px-2.5 py-1",
        spec.className,
        className,
      )}
      aria-label={`État de la course : ${label}`}
    >
      {live ? (
        <span
          aria-hidden
          className="relative flex h-1.5 w-1.5"
        >
          <span className="absolute inline-flex h-full w-full rounded-full bg-current opacity-60 animate-ping" />
          <span className="relative inline-flex h-1.5 w-1.5 rounded-full bg-current" />
        </span>
      ) : (
        <Icon className={size === "sm" ? "w-3 h-3" : "w-3.5 h-3.5"} aria-hidden />
      )}
      {label}
    </Badge>
  );
}
