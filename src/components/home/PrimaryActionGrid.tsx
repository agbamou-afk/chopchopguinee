import { motion } from "framer-motion";
import { Plus, Bike, UtensilsCrossed, ShoppingBag, type LucideIcon } from "lucide-react";

export type PrimaryAction = "topup" | "ride" | "order" | "market";

interface Props {
  onAction: (a: PrimaryAction) => void;
}

/**
 * Uniform tile treatment: same card surface for all tiles. Tone is expressed
 * exclusively through the icon halo. No per-tile gradients — keeps the grid
 * calm and rhythmic.
 */
const ACTIONS: Array<{
  id: PrimaryAction;
  label: string;
  subtitle: string;
  Icon: LucideIcon;
  halo: string;
  iconClass: string;
}> = [
  {
    id: "topup",
    label: "CHOPWallet",
    subtitle: "Recharger en quelques secondes",
    Icon: Plus,
    halo: "bg-primary/12 ring-1 ring-primary/15",
    iconClass: "text-primary",
  },
  {
    id: "ride",
    label: "Course",
    subtitle: "Moto ou TokTok",
    Icon: Bike,
    halo: "bg-secondary/22 ring-1 ring-secondary/25",
    iconClass: "text-secondary-foreground",
  },
  {
    id: "order",
    label: "Repas",
    subtitle: "Livraison rapide",
    Icon: UtensilsCrossed,
    halo: "bg-[hsl(var(--accent-repas)/0.14)] ring-1 ring-[hsl(var(--accent-repas)/0.20)]",
    iconClass: "text-[hsl(var(--accent-repas))]",
  },
  {
    id: "market",
    label: "Marché",
    subtitle: "Annonces près de vous",
    Icon: ShoppingBag,
    halo: "bg-[hsl(var(--accent-marche)/0.14)] ring-1 ring-[hsl(var(--accent-marche)/0.20)]",
    iconClass: "text-[hsl(var(--accent-marche))]",
  },
];

export function PrimaryActionGrid({ onAction }: Props) {
  return (
    <div className="grid grid-cols-2 gap-3">
      {ACTIONS.map(({ id, label, subtitle, Icon, halo, iconClass }) => (
        <motion.button
          key={id}
          whileTap={{ scale: 0.985 }}
          transition={{ duration: 0.2, ease: [0.22, 1, 0.36, 1] }}
          onClick={() => onAction(id)}
          aria-label={label}
          className="relative flex flex-col items-start gap-2.5 rounded-2xl border border-border/60 bg-card p-4 min-h-[112px] text-left shadow-card active:shadow-soft transition-shadow"
        >
          <div className={`w-11 h-11 rounded-xl ${halo} flex items-center justify-center`}>
            <Icon className={`w-[19px] h-[19px] ${iconClass}`} strokeWidth={1.75} />
          </div>
          <div className="space-y-0.5">
            <p className="text-[14px] font-semibold text-foreground leading-tight tracking-tight">{label}</p>
            <p className="text-[11px] text-muted-foreground leading-snug">{subtitle}</p>
          </div>
        </motion.button>
      ))}
    </div>
  );
}