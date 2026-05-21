import { motion } from "framer-motion";
import motoIcon from "@/assets/icons/moto.png";
import toktokIcon from "@/assets/icons/toktok.png";
import repasIcon from "@/assets/icons/repas.png";
import marcheIcon from "@/assets/icons/marche.png";
import scannerIcon from "@/assets/icons/scanner.png";
import walletIcon from "@/assets/icons/wallet.png";

interface QuickActionsProps {
  onActionClick: (action: string) => void;
}

// Normalized service-tile system: every tile shares the same holder size,
// background, padding and icon scale so the grid reads as one set.
const actions = [
  { id: "moto", img: motoIcon, label: "Moto", alt: "Réserver une moto-taxi" },
  { id: "toktok", img: toktokIcon, label: "TokTok", alt: "Réserver un TokTok tricycle" },
  { id: "food", img: repasIcon, label: "Repas", alt: "Commander un repas à domicile" },
  { id: "market", img: marcheIcon, label: "Marché", alt: "Acheter au marché en ligne" },
  { id: "scan", img: scannerIcon, label: "Scanner", alt: "Scanner un QR code marchand" },
  { id: "wallet", img: walletIcon, label: "WONGO Wallet", alt: "Ouvrir WONGO Wallet" },
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
  return (
    <motion.div
      variants={container}
      initial="hidden"
      animate="show"
      className="grid grid-cols-3 gap-x-3 gap-y-4"
    >
      {actions.map((action) => (
        <motion.button
          key={action.id}
          variants={item}
          whileHover={{ scale: 1.05, y: -2 }}
          whileTap={{ scale: 0.95 }}
          onClick={() => onActionClick(action.id)}
          className="flex flex-col items-center transition-transform group"
        >
          <div className="service-icon-holder mb-2">
            <img
              src={action.img}
              alt={action.alt}
              loading="lazy"
              width={1024}
              height={1024}
              className="service-icon-asset float-soft"
            />
          </div>
          <span className="text-[12px] font-semibold text-foreground text-center leading-tight">
            {action.label}
          </span>
        </motion.button>
      ))}
    </motion.div>
  );
}
