import { motion } from "framer-motion";
import { ServiceIcon } from "@/components/services/ServiceIcon";
import { getServiceIconAsset } from "@/lib/services/serviceIcons";
import {
  usePublicPaymentProductName,
  usePublicPaymentProductSubtitle,
} from "@/lib/flags/useFeatureFlag";
import { useServiceExposure } from "@/lib/services/serviceExposure";

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
  /** Canonical exposure action id (PASS 2 law). */
  exposureId: string;
  /** Canonical service icon id in `@/lib/services/serviceIcons`. */
  iconId: string;
  label: string;
  subtitle: string;
  halo: string;
};

const WALLET_TILE: ActionDef = {
  id: "topup",
  exposureId: "wallet",
  iconId: "wallet",
  label: "ChopWallet",
  subtitle: "Recharger en quelques secondes",
  halo: "w-11 h-11 rounded-xl bg-primary/12 ring-1 ring-primary/15 flex items-center justify-center overflow-hidden shrink-0",
};

const OM_TILE_BASE: Omit<ActionDef, "label" | "subtitle"> = {
  id: "topup",
  exposureId: "wallet",
  iconId: "wallet",
  halo: "w-11 h-11 rounded-xl bg-primary/12 ring-1 ring-primary/15 flex items-center justify-center overflow-hidden shrink-0",
};

const RIDE_TILES: ActionDef[] = [
  {
    id: "ride",
    // Umbrella card — represents Moto OR Bonbonna (composite exposure rule).
    exposureId: "ride",
    iconId: "moto",
    label: "Course",
    subtitle: "Moto ou Bonbonna",
    halo: "w-11 h-11 rounded-xl bg-secondary/22 ring-1 ring-secondary/25 flex items-center justify-center overflow-hidden shrink-0",
  },
  {
    id: "order",
    exposureId: "food",
    iconId: "food",
    label: "Repas",
    subtitle: "Livraison rapide",
    halo: "w-11 h-11 rounded-xl bg-[hsl(var(--accent-repas)/0.14)] ring-1 ring-[hsl(var(--accent-repas)/0.20)] flex items-center justify-center overflow-hidden shrink-0",
  },
  {
    id: "market",
    exposureId: "market",
    iconId: "market",
    label: "Marché",
    subtitle: "Annonces près de vous",
    halo: "w-11 h-11 rounded-xl bg-[hsl(var(--accent-marche)/0.14)] ring-1 ring-[hsl(var(--accent-marche)/0.20)] flex items-center justify-center overflow-hidden shrink-0",
  },
];

export function PrimaryActionGrid({ onAction }: Props) {
  const exposure = useServiceExposure();
  const publicName = usePublicPaymentProductName();
  const publicSubtitle = usePublicPaymentProductSubtitle();
  // PASS 2: the public payment tile appears only when the PUBLIC Chop Pay /
  // wallet product itself is exposed. `om_*` provider readiness never
  // controls this tile. Otherwise it is not rendered at all.
  const walletTile: ActionDef = {
    ...WALLET_TILE,
    ...OM_TILE_BASE,
    label: publicName,
    subtitle: publicSubtitle,
  };
  const actions: ActionDef[] = exposure.filter(
    [walletTile, ...RIDE_TILES],
    (a) => a.exposureId,
  );

  if (!exposure.ready) {
    return (
      <div className="grid grid-cols-2 gap-3" aria-busy="true" data-testid="primary-actions-skeleton">
        {[0, 1].map((k) => (
          <div key={k} className="rounded-2xl card-warm p-4 min-h-[116px] animate-pulse" aria-hidden />
        ))}
      </div>
    );
  }

  return (
    <div className="grid grid-cols-2 gap-3">
      {actions.map(({ id, exposureId, iconId, label, subtitle, halo }) => (
        <motion.button
          key={exposureId}
          whileTap={{ scale: 0.985 }}
          transition={{ duration: 0.2, ease: [0.22, 1, 0.36, 1] }}
          onClick={() => onAction(id)}
          aria-label={label}
          data-service-id={iconId}
          data-exposure-id={exposureId}
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
