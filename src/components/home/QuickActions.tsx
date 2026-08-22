import { motion, useReducedMotion } from "framer-motion";
import { ServiceIcon } from "@/components/services/ServiceIcon";
import { getServiceIconAsset } from "@/lib/services/serviceIcons";
import { useServiceExposure } from "@/lib/services/serviceExposure";

interface QuickActionsProps {
  onActionClick: (action: string) => void;
}

/**
 * Single source of truth for the Home quick-service rail. Every entry maps
 * to a canonical `Index.handleAction` id — the exact same router the bottom
 * Services destination uses, so Home and Services can never diverge.
 * The archived public wallet is intentionally absent.
 *
 * Artwork and optical tuning come from `@/lib/services/serviceIcons` — never
 * inline here — so this rail can never drift from Services / PrimaryActionGrid.
 */
type RailService = {
  id: string;
  label: string;
  alt: string;
  /** Accessible action label, e.g. "Ouvrir Envoyer". */
  aria: string;
};

const HOME_RAIL: RailService[] = [
  { id: "moto",   label: "Course",   alt: "Réserver une course moto",       aria: "Ouvrir Course" },
  { id: "toktok", label: "Bonbonna", alt: "Réserver un tricycle Bonbonna",  aria: "Ouvrir Bonbonna" },
  { id: "food",   label: "Repas",    alt: "Commander un repas à domicile",  aria: "Ouvrir Repas" },
  { id: "market", label: "Marché",   alt: "Acheter au marché en ligne",     aria: "Ouvrir Marché" },
  { id: "parcel", label: "Envoyer",  alt: "Envoyer un colis ou un pli",     aria: "Ouvrir Envoyer" },
  { id: "scan",   label: "Scanner",  alt: "Scanner un QR CHOPCHOP",         aria: "Ouvrir Scanner" },
];


const container = {
  hidden: { opacity: 0 },
  show: { opacity: 1, transition: { staggerChildren: 0.04 } },
};

const item = {
  hidden: { opacity: 0, y: 12 },
  show: { opacity: 1, y: 0 },
};

export function QuickActions({ onActionClick }: QuickActionsProps) {
  const exposure = useServiceExposure();
  const reduceMotion = useReducedMotion();
  // Exposure law: a product whose flag is OFF is not rendered at all.
  const visible = exposure.filter(HOME_RAIL, (a) => a.id);

  if (!exposure.ready) {
    // Anti-flicker: neutral rail skeleton until live flags resolve.
    return (
      <div className="relative -mx-4" aria-busy="true" data-testid="quick-actions-skeleton">
        <div className="flex gap-3 px-4 pb-1">
          {[0, 1, 2, 3].map((k) => (
            <div key={k} className="shrink-0 w-[96px] h-[96px] rounded-2xl bg-white/15 animate-pulse" aria-hidden />
          ))}
        </div>
      </div>
    );
  }

  return (
    <div className="relative -mx-4">
      <motion.div
        variants={reduceMotion ? undefined : container}
        initial={reduceMotion ? undefined : "hidden"}
        animate={reduceMotion ? undefined : "show"}
        role="list"
        aria-label="Services CHOPCHOP"
        tabIndex={0}
        className="flex gap-3 overflow-x-auto overscroll-x-contain scroll-smooth snap-x snap-mandatory scrollbar-hide px-4 pb-1 pr-10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/70 rounded-2xl"
      >
        {visible.map((action) => {
          return (
            <motion.button
              key={action.id}
              type="button"
              role="listitem"
              variants={reduceMotion ? undefined : item}
              whileTap={reduceMotion ? undefined : { scale: 0.95 }}
              onClick={() => onActionClick(action.id)}
              aria-label={action.aria}
              data-service-id={action.id}
              data-icon-family="service"
              data-icon-asset={getServiceIconAsset(action.id) ? "branded" : "glyph"}
              className="group snap-start shrink-0 w-[96px] min-h-[96px] flex flex-col items-center gap-1.5 rounded-2xl py-1 transition-transform focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/80"
            >
              <ServiceIcon
                id={action.id}
                family="service"
                chipClassName="service-icon-holder"
                imgClassName="service-icon-asset float-soft"
              />

              <span className="text-[12.5px] font-semibold text-foreground text-center leading-tight">
                {action.label}
              </span>
            </motion.button>
          );
        })}
      </motion.div>
      {/* Right-edge affordance: purely decorative, never blocks touch. */}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-y-0 right-0 w-8 bg-gradient-to-l from-black/10 to-transparent rounded-r-2xl"
      />
    </div>
  );
}
