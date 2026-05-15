import { motion } from "framer-motion";
import walletIcon from "@/assets/icons/wallet.png";
import motoIcon from "@/assets/icons/moto.png";
import repasIcon from "@/assets/icons/repas.png";
import marcheIcon from "@/assets/icons/marche.png";

export type PrimaryAction = "topup" | "ride" | "order" | "market";

interface Props {
  onAction: (a: PrimaryAction) => void;
}

/**
 * Uniform tile treatment: same card surface, same halo system. All tiles use
 * the canonical CHOP service icon family (raster PNGs) so the grid reads as
 * one authored set instead of mixed Lucide/PNG glyphs.
 */
const ACTIONS: Array<{
  id: PrimaryAction;
  label: string;
  subtitle: string;
  img: string;
  alt: string;
  halo: string;
}> = [
  {
    id: "topup",
    label: "CHOPWallet",
    subtitle: "Recharger en quelques secondes",
    img: walletIcon,
    alt: "Recharger CHOPWallet",
    halo: "bg-primary/12 ring-1 ring-primary/15",
  },
  {
    id: "ride",
    label: "Course",
    subtitle: "Moto ou TokTok",
    img: motoIcon,
    alt: "Réserver une course",
    halo: "bg-secondary/22 ring-1 ring-secondary/25",
  },
  {
    id: "order",
    label: "Repas",
    subtitle: "Livraison rapide",
    img: repasIcon,
    alt: "Commander un repas",
    halo: "bg-[hsl(var(--accent-repas)/0.14)] ring-1 ring-[hsl(var(--accent-repas)/0.20)]",
  },
  {
    id: "market",
    label: "Marché",
    subtitle: "Annonces près de vous",
    img: marcheIcon,
    alt: "Explorer le Marché",
    halo: "bg-[hsl(var(--accent-marche)/0.14)] ring-1 ring-[hsl(var(--accent-marche)/0.20)]",
  },
];

export function PrimaryActionGrid({ onAction }: Props) {
  return (
    <div className="grid grid-cols-2 gap-3">
      {ACTIONS.map(({ id, label, subtitle, img, alt, halo }) => (
        <motion.button
          key={id}
          whileTap={{ scale: 0.985 }}
          transition={{ duration: 0.2, ease: [0.22, 1, 0.36, 1] }}
          onClick={() => onAction(id)}
          aria-label={label}
          className="relative flex flex-col items-start gap-2.5 rounded-2xl border border-border/60 bg-card p-4 min-h-[112px] text-left shadow-card active:shadow-soft transition-shadow"
        >
          <div className={`w-11 h-11 rounded-xl ${halo} flex items-center justify-center overflow-hidden`}>
            <img
              src={img}
              alt={alt}
              loading="lazy"
              width={1024}
              height={1024}
              className="w-11 h-11 object-contain scale-[1.45] float-soft"
            />
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