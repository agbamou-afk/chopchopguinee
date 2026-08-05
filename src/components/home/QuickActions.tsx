import { motion, useReducedMotion } from "framer-motion";
import motoIcon from "@/assets/icons/moto.png";
import toktokIcon from "@/assets/icons/toktok.png";
import repasIcon from "@/assets/icons/repas.png";
import marcheIcon from "@/assets/icons/marche.png";
import envoyerIcon from "@/assets/icons/envoyer.png";
import scannerIcon from "@/assets/icons/scanner.png";
import { useEnvoyerEnabled } from "@/lib/flags/useFeatureFlag";

interface QuickActionsProps {
  onActionClick: (action: string) => void;
}

// Per-icon optical tuning. Each artwork has a slightly different inner
// bounding box, so we balance the family by adjusting scale + nudges
// inside the shared holder. Values tuned visually, not mathematically.
type IconTuning = { scale: number; x: number; y: number };
const SERVICE_ICON_TUNING: Record<string, IconTuning> = {
  moto:    { scale: 1.57, x: 0, y: 0 },
  toktok:  { scale: 1.5,  x: 0, y: 0 },
  food:    { scale: 1.59, x: 0, y: 0 },
  market:  { scale: 1.49, x: 0, y: 0 },
  parcel:  { scale: 1.42, x: 0, y: 0 },
  scan:    { scale: 1.42, x: 0, y: 0 },
};

/**
 * Single source of truth for the Home quick-service rail. Every entry maps
 * to a canonical `Index.handleAction` id — the exact same router the bottom
 * Services destination uses, so Home and Services can never diverge.
 * The archived public wallet is intentionally absent.
 */
type RailService = {
  id: string;
  label: string;
  img: string;
  alt: string;
  /** Accessible action label, e.g. "Ouvrir Envoyer". */
  aria: string;
};

const HOME_RAIL: RailService[] = [
  { id: "moto",   img: motoIcon,    label: "Course",   alt: "Réserver une course moto",       aria: "Ouvrir Course" },
  { id: "toktok", img: toktokIcon,  label: "Bonbonna", alt: "Réserver un tricycle Bonbonna",  aria: "Ouvrir Bonbonna" },
  { id: "food",   img: repasIcon,   label: "Repas",    alt: "Commander un repas à domicile",  aria: "Ouvrir Repas" },
  { id: "market", img: marcheIcon,  label: "Marché",   alt: "Acheter au marché en ligne",     aria: "Ouvrir Marché" },
  { id: "parcel", img: envoyerIcon, label: "Envoyer",  alt: "Envoyer un colis ou un pli",     aria: "Ouvrir Envoyer" },
  { id: "scan",   img: scannerIcon, label: "Scanner",  alt: "Scanner un QR CHOPCHOP",         aria: "Ouvrir Scanner" },
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
          const t = SERVICE_ICON_TUNING[action.id] ?? { scale: 1, x: 0, y: 0 };
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
              className={`snap-start shrink-0 w-[96px] min-h-[96px] flex flex-col items-center gap-1.5 rounded-2xl py-1 transition-transform focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/80 ${
                disabled ? "opacity-60" : "group"
              }`}
            >
              <div className="service-icon-holder">
                <img
                  src={action.img}
                  alt={action.alt}
                  loading="lazy"
                  width={1024}
                  height={1024}
                  className="service-icon-asset float-soft my-0 pl-0 ml-0 border-0 mb-0 mr-0 pr-0 object-contain"
                  style={{ transform: `translate(${t.x}px, ${t.y}px) scale(${t.scale})` }}
                />
              </div>
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
