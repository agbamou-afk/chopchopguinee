import { BadgeCheck, Users, Briefcase } from "lucide-react";
import type { SellerKind } from "@/lib/marche";

export function SellerBadge({ kind }: { kind: SellerKind }) {
  if (kind === "merchant")
    return (
      <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-emerald-50 text-emerald-700 text-[10px] font-semibold">
        <BadgeCheck className="w-3 h-3" /> Marchand vérifié
      </span>
    );
  if (kind === "service")
    return (
      <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-teal-50 text-teal-700 text-[10px] font-semibold">
        <Briefcase className="w-3 h-3" /> Prestataire
      </span>
    );
  return (
    <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-muted text-foreground/70 text-[10px] font-semibold">
      <Users className="w-3 h-3" /> Communauté
    </span>
  );
}