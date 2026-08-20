import { TrendingDown, Star, ShieldCheck, MapPin, Sparkles } from "lucide-react";
import type { RankReason } from "@/lib/marche/ranking";

const ICONS = {
  price: TrendingDown,
  reputation: Star,
  reliability: ShieldCheck,
  distance: MapPin,
  new: Sparkles,
} as const;

/** Honest, server-derived ranking reasons. Never rendered when evidence is missing. */
export function RankReasonChips({ reasons }: { reasons: RankReason[] }) {
  if (!reasons.length) return null;
  return (
    <div className="flex flex-wrap items-center gap-1 mt-1.5">
      {reasons.map((r) => {
        const Icon = ICONS[r.key as keyof typeof ICONS] ?? Sparkles;
        return (
          <span
            key={r.key}
            className="inline-flex items-center gap-1 rounded-full bg-muted px-1.5 py-0.5 text-[9px] font-semibold text-muted-foreground"
          >
            <Icon className="w-2.5 h-2.5" />
            {r.label}
          </span>
        );
      })}
    </div>
  );
}
