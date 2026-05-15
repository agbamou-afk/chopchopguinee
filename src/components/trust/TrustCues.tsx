import { ShieldCheck, Lock, Radio, LifeBuoy, BadgeCheck } from "lucide-react";
import { cn } from "@/lib/utils";

/**
 * Small, calm trust cues used across ride & driver surfaces.
 * Renders as a single-line wrap of pills — no layout shift, no animation.
 * Use a focused subset per surface (don't stack all 4 everywhere).
 */

export type TrustCueKey = "verified" | "choppay" | "live" | "support" | "merchant_verified" | "instant_credit";

const SPECS: Record<TrustCueKey, { icon: typeof ShieldCheck; label: string }> = {
  verified: { icon: BadgeCheck, label: "Chauffeur vérifié" },
  choppay: { icon: Lock, label: "Paiement sécurisé · CHOPPay" },
  live: { icon: Radio, label: "Course suivie en direct" },
  support: { icon: LifeBuoy, label: "Support 24/7" },
  merchant_verified: { icon: BadgeCheck, label: "Marchand vérifié" },
  instant_credit: { icon: Radio, label: "Crédité instantanément" },
};

interface Props {
  cues: TrustCueKey[];
  className?: string;
  /** Compact = smaller pills for dense surfaces (driver island, receipts). */
  compact?: boolean;
}

export function TrustCues({ cues, className, compact }: Props) {
  if (!cues.length) return null;
  return (
    <ul
      className={cn(
        "flex flex-wrap items-center gap-1.5",
        className,
      )}
      aria-label="Garanties CHOP CHOP"
    >
      {cues.map((k) => {
        const { icon: Icon, label } = SPECS[k];
        return (
          <li
            key={k}
            className={cn(
              "inline-flex items-center gap-1 rounded-full border border-border/60 bg-muted/40 text-muted-foreground",
              compact ? "px-1.5 py-0.5 text-[10px]" : "px-2 py-0.5 text-[11px]",
            )}
          >
            <Icon className={compact ? "w-2.5 h-2.5" : "w-3 h-3"} aria-hidden />
            <span className="leading-none">{label}</span>
          </li>
        );
      })}
    </ul>
  );
}

/** Single inline secured-by-CHOPPay line (used in receipts). */
export function SecuredByChopPay({ className }: { className?: string }) {
  return (
    <p
      className={cn(
        "inline-flex items-center gap-1.5 text-[11px] text-muted-foreground",
        className,
      )}
    >
      <ShieldCheck className="w-3.5 h-3.5 text-success" aria-hidden />
      Paiement sécurisé par <span className="font-semibold text-foreground">CHOPPay</span>
    </p>
  );
}