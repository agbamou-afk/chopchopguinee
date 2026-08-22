import { motion } from "framer-motion";
import { ServiceIcon } from "@/components/services/ServiceIcon";
import { getServiceIconAsset } from "@/lib/services/serviceIcons";
import {
  usePublicWalletEnabled,
  usePublicPaymentProductName,
  usePublicPaymentProductSubtitle,
} from "@/lib/flags/useFeatureFlag";

export type PrimaryAction = "topup" | "ride" | "order" | "market";

interface Props {
  onAction: (a: PrimaryAction) => void;
}

/**
 * Uniform tile treatment: same card surface, same halo system. All tiles are
 * Family A (transactional services) and render through the canonical
 * `ServiceIcon`, so artwork and optical tuning come from the shared registry.
 */
type ActionDef = {
  id: PrimaryAction;
  /** Canonical service icon id in `@/lib/services/serviceIcons`. */
  iconId: string;
  label: string;
  subtitle: string;
  halo: string;
};

const WALLET_TILE: ActionDef = {
  id: "topup",
  iconId: "wallet",
  label: "ChopWallet",
  subtitle: "Recharger en quelques secondes",
  halo: "w-11 h-11 rounded-xl bg-primary/12 ring-1 ring-primary/15 flex items-center justify-center overflow-hidden shrink-0",
};

const OM_TILE_BASE: Omit<ActionDef, "label" | "subtitle"> = {
  id: "topup",
  iconId: "wallet",
  halo: "w-11 h-11 rounded-xl bg-primary/12 ring-1 ring-primary/15 flex items-center justify-center overflow-hidden shrink-0",
};

const RIDE_TILES: ActionDef[] = [
  {
    id: "ride",
    iconId: "moto",
    label: "Course",
    subtitle: "Moto ou Bonbonna",
    halo: "w-11 h-11 rounded-xl bg-secondary/22 ring-1 ring-secondary/25 flex items-center justify-center overflow-hidden shrink-0",
  },
  {
    id: "order",
    iconId: "food",
    label: "Repas",
    subtitle: "Livraison rapide",
    halo: "w-11 h-11 rounded-xl bg-[hsl(var(--accent-repas)/0.14)] ring-1 ring-[hsl(var(--accent-repas)/0.20)] flex items-center justify-center overflow-hidden shrink-0",
  },
  {
    id: "market",
    iconId: "market",
    label: "Marché",
    subtitle: "Annonces près de vous",
    halo: "w-11 h-11 rounded-xl bg-[hsl(var(--accent-marche)/0.14)] ring-1 ring-[hsl(var(--accent-marche)/0.20)] flex items-center justify-center overflow-hidden shrink-0",
  },
];

export function PrimaryActionGrid({ onAction }: Props) {
  const publicWalletEnabled = usePublicWalletEnabled();
  const publicName = usePublicPaymentProductName();
  const publicSubtitle = usePublicPaymentProductSubtitle();
  const omTile: ActionDef = {
    ...OM_TILE_BASE,
    label: publicName,
    subtitle: publicSubtitle,
  };
  const actions: ActionDef[] = [
    publicWalletEnabled ? WALLET_TILE : omTile,
    ...RIDE_TILES,
  ];
  return (
    <div className="grid grid-cols-2 gap-3">
      {actions.map(({ id, iconId, label, subtitle, halo }) => (
        <motion.button
          key={id}
          whileTap={{ scale: 0.985 }}
          transition={{ duration: 0.2, ease: [0.22, 1, 0.36, 1] }}
          onClick={() => onAction(id)}
          aria-label={label}
          data-service-id={iconId}
          data-icon-family="service"
          data-icon-asset={getServiceIconAsset(iconId) ? "branded" : "glyph"}
          className="relative flex flex-col items-start gap-2.5 rounded-2xl card-warm p-4 min-h-[116px] text-left active:shadow-soft transition-shadow overflow-hidden"
        >
          <div className="pointer-events-none absolute inset-x-3 top-0 h-px saffron-seam opacity-70" aria-hidden />
          <ServiceIcon id={iconId} family="service" chipClassName={halo} imgClassName="w-11 h-11 float-soft" />
          <div className="space-y-0.5">
            <p className="text-[14px] font-semibold text-foreground leading-tight tracking-tight">{label}</p>
            <p className="text-[11px] text-muted-foreground leading-snug">{subtitle}</p>
          </div>
        </motion.button>
      ))}
    </div>
  );
}
