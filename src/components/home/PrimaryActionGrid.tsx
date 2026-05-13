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
    label: "Recharger",
    subtitle: "Mobile money ou agent",
    Icon: Plus,
    surface: "bg-primary/8 border-primary/15",
    halo: "bg-primary/15",
    iconClass: "text-primary",
  },
  {
    id: "ride",
    label: "Course",
    subtitle: "Moto ou TokTok",
    Icon: Bike,
    surface: "bg-secondary/15 border-secondary/25",
    halo: "bg-secondary/30",
    iconClass: "text-foreground",
  },
  {
    id: "order",
    label: "Commander",
    subtitle: "Repas livrés",
    Icon: UtensilsCrossed,
    surface: "bg-[hsl(8_78%_55%/0.10)] border-[hsl(8_78%_55%/0.18)]",
    halo: "bg-[hsl(8_78%_55%/0.18)]",
    iconClass: "text-[hsl(8_78%_45%)]",
  },
  {
    id: "market",
    label: "Marché",
    subtitle: "Annonces près de vous",
    Icon: ShoppingBag,
    surface: "bg-[hsl(45_90%_55%/0.12)] border-[hsl(45_90%_55%/0.22)]",
    halo: "bg-[hsl(45_90%_55%/0.22)]",
    iconClass: "text-[hsl(38_80%_38%)]",
  },
];

export function PrimaryActionGrid({ onAction }: Props) {
  return (
    <div className="grid grid-cols-2 gap-3">
      {ACTIONS.map(({ id, label, subtitle, Icon, surface, halo, iconClass }) => (
        <motion.button
          key={id}
          whileTap={{ scale: 0.97 }}
          onClick={() => onAction(id)}
          aria-label={label}
          className={`relative flex flex-col items-start gap-2 rounded-2xl border ${surface} p-4 min-h-[96px] text-left shadow-card active:shadow-soft transition-shadow`}
        >
          <div className={`w-11 h-11 rounded-2xl ${halo} flex items-center justify-center`}>
            <Icon className={`w-5 h-5 ${iconClass}`} />
          </div>
          <div className="space-y-0.5">
            <p className="text-sm font-bold text-foreground leading-tight">{label}</p>
            <p className="text-[11px] text-muted-foreground leading-snug">{subtitle}</p>
          </div>
        </motion.button>
      ))}
    </div>
  );
}