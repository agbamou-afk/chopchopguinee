import { motion } from "framer-motion";
import motoIcon from "@/assets/icons/moto.png";
import toktokIcon from "@/assets/icons/toktok.png";
import repasIcon from "@/assets/icons/repas.png";
import marcheIcon from "@/assets/icons/marche.png";
import envoyerIcon from "@/assets/icons/envoyer.png";

interface QuickActionsProps {
  onActionClick: (action: string) => void;
}

// Per-icon optical tuning. Each artwork has a slightly different inner
// bounding box, so we balance the family by adjusting scale + nudges
// inside the shared holder. Values tuned visually, not mathematically.
type IconTuning = { scale: number; x: number; y: number };
const SERVICE_ICON_TUNING: Record<string, IconTuning> = {
  moto:    { scale: 1.57, x: 0, y: 0 },
  toktok:  { scale: 1.43, x: 0, y: 0 },
  food:    { scale: 1.59, x: 0, y: 0 },
  market:  { scale: 1.49, x: 0, y: 0 },
  parcel:  { scale: 1.42, x: 0, y: 0 },
};

/**
 * Home shows a compact, high-frequency subset only. The full service
 * catalogue (scanner, paiements, onboarding marchand/chauffeur, aide)
 * lives in the Services destination so we never duplicate it twice.
 */
const HOME_ACTIONS = [
  { id: "moto",   img: motoIcon,    label: "Course",  alt: "Réserver une course moto" },
  { id: "food",   img: repasIcon,   label: "Repas",   alt: "Commander un repas à domicile" },
  { id: "market", img: marcheIcon,  label: "Marché",  alt: "Acheter au marché en ligne" },
  { id: "parcel", img: envoyerIcon, label: "Envoyer", alt: "Envoyer un colis ou un pli" },
];

const container = {
  hidden: { opacity: 0 },
  show: {
    opacity: 1,
    transition: {
      staggerChildren: 0.05,
    },
  },
};

const item = {
  hidden: { opacity: 0, y: 20 },
  show: { opacity: 1, y: 0 },
};

export function QuickActions({ onActionClick }: QuickActionsProps) {
  const actions = HOME_ACTIONS;
  return (
    <motion.div
      variants={container}
      initial="hidden"
      animate="show"
      className="grid grid-cols-4 gap-x-2 gap-y-5"
    >
      {actions.map((action) => {
        const t = SERVICE_ICON_TUNING[action.id] ?? { scale: 1, x: 0, y: 0 };
        return (
        <motion.button
          key={action.id}
          variants={item}
          whileHover={{ scale: 1.05, y: -2 }}
          whileTap={{ scale: 0.95 }}
          onClick={() => onActionClick(action.id)}
          className="flex flex-col items-center gap-1.5 transition-transform group"
        >
          <div className="service-icon-holder">
            <img
              src={action.img}
              alt={action.alt}
              loading="lazy"
              width={1024}
              height={1024}
              className="service-icon-asset float-soft my-0 pl-0 ml-0 border-0 mb-0 mr-0 pr-0 object-contain"
              style={{
                transform: `translate(${t.x}px, ${t.y}px) scale(${t.scale})`,
              }}
            />
          </div>
          <span className="text-[12.5px] font-semibold text-foreground text-center leading-tight">
            {action.label}
          </span>
        </motion.button>
        );
      })}
    </motion.div>
  );
}
