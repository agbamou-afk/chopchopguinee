import { motion } from "framer-motion";
import { Plus, Bike, UtensilsCrossed, ShoppingBag, type LucideIcon } from "lucide-react";

export type PrimaryAction = "topup" | "ride" | "order" | "market";

interface Props {
  onAction: (a: PrimaryAction) => void;
}

const ACTIONS: Array<{
  id: PrimaryAction;
  label: string;
  subtitle: string;
  Icon: LucideIcon;
  /** soft accent surface */
  surface: string;
  /** icon halo */
  halo: string;
  /** icon color */
  iconClass: string;
}> = [
  {
    id: "topup",
    label: "CHOPWallet",
    subtitle: "Recharger en quelques secondes",
    Icon: Plus,
    surface: "bg-gradient-to-br from-primary/12 to-primary/4 border-primary/20",
    halo: "bg-primary/15 ring-1 ring-primary/20",
    iconClass: "text-primary",
  },
  {
    id: "ride",
    label: "Course",
    subtitle: "Moto ou TokTok",
    Icon: Bike,
    surface: "bg-gradient-to-br from-secondary/20 to-secondary/5 border-secondary/30",
    halo: "bg-secondary/30 ring-1 ring-secondary/30",
    iconClass: "text-secondary-foreground",
  },
  {
    id: "order",
    label: "Repas",
    subtitle: "Livraison rapide",
    Icon: UtensilsCrossed,
    surface: "bg-gradient-to-br from-[hsl(var(--accent-repas)/0.12)] to-[hsl(var(--accent-repas)/0.03)] border-[hsl(var(--accent-repas)/0.22)]",
    halo: "bg-[hsl(var(--accent-repas)/0.18)] ring-1 ring-[hsl(var(--accent-repas)/0.22)]",
    iconClass: "text-[hsl(var(--accent-repas))]",
  },
  {
    id: "market",
    label: "Marché",
    subtitle: "Annonces près de vous",
    Icon: ShoppingBag,
    surface: "bg-gradient-to-br from-[hsl(var(--accent-marche)/0.12)] to-[hsl(var(--accent-marche)/0.03)] border-[hsl(var(--accent-marche)/0.22)]",
    halo: "bg-[hsl(var(--accent-marche)/0.18)] ring-1 ring-[hsl(var(--accent-marche)/0.22)]",
    iconClass: "text-[hsl(var(--accent-marche))]",
  },
];

export function PrimaryActionGrid({ onAction }: Props) {
  return (
    <div className="grid grid-cols-2 gap-3.5">
      {ACTIONS.map(({ id, label, subtitle, Icon, surface, halo, iconClass }) => (
        <motion.button
          key={id}
          whileTap={{ scale: 0.985 }}
          onClick={() => onAction(id)}
          aria-label={label}
          className={`relative overflow-hidden flex flex-col items-start gap-2.5 rounded-[22px] border ${surface} p-4 min-h-[112px] text-left surface-card-elevated active:shadow-soft transition-shadow`}
        >
          <div className={`w-11 h-11 rounded-[14px] ${halo} flex items-center justify-center`}>
            <Icon className={`w-[19px] h-[19px] ${iconClass}`} strokeWidth={1.85} />
          </div>
          <div className="space-y-1">
            <p className="text-[14px] font-bold text-foreground leading-tight tracking-tight">{label}</p>
            <p className="text-[11px] text-muted-foreground leading-snug">{subtitle}</p>
          </div>
          <span className="pointer-events-none absolute inset-x-4 top-0 h-px bg-gradient-to-r from-transparent via-white/60 to-transparent" aria-hidden />
        </motion.button>
      ))}
    </div>
  );
}