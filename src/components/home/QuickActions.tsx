import { motion, useReducedMotion } from "framer-motion";
import { ServiceIcon } from "@/components/services/ServiceIcon";
import { getServiceIconAsset } from "@/lib/services/serviceIcons";
import { useEnvoyerEnabled } from "@/lib/flags/useFeatureFlag";

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
  const envoyerOn = useEnvoyerEnabled();
  const reduceMotion = useReducedMotion();

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
        {HOME_RAIL.map((action) => {
          // Envoyer stays visible but honestly gated, exactly like Services.
          const disabledReason =
            action.id === "parcel" && !envoyerOn ? "Bientôt disponible" : undefined;
          const disabled = !!disabledReason;
          return (
            <motion.button
              key={action.id}
              type="button"
              role="listitem"
              variants={reduceMotion ? undefined : item}
              whileTap={disabled || reduceMotion ? undefined : { scale: 0.95 }}
              onClick={disabled ? undefined : () => onActionClick(action.id)}
              aria-disabled={disabled}
              aria-label={disabled ? `${action.label} — ${disabledReason}` : action.aria}
              data-service-id={action.id}
              data-icon-family="service"
              data-icon-asset={getServiceIconAsset(action.id) ? "branded" : "glyph"}
              className={`snap-start shrink-0 w-[96px] min-h-[96px] flex flex-col items-center gap-1.5 rounded-2xl py-1 transition-transform focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/80 ${
                disabled ? "opacity-60" : "group"
              }`}
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
              {disabled && (
                <span className="text-[10px] text-foreground/70 leading-none text-center">
                  {disabledReason}
                </span>
              )}
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
