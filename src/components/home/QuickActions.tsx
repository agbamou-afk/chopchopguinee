import { motion } from "framer-motion";
import motoIcon from "@/assets/icons/moto.png";
import toktokIcon from "@/assets/icons/toktok.png";
import repasIcon from "@/assets/icons/repas.png";
import marcheIcon from "@/assets/icons/marche.png";
import envoyerIcon from "@/assets/icons/envoyer.png";
import scannerIcon from "@/assets/icons/scanner.png";

interface QuickActionsProps {
  onActionClick: (action: string) => void;
}

const actions = [
  { id: "moto", img: motoIcon, label: "Moto", tint: "bg-[hsl(var(--accent-moto)/0.10)]" },
  { id: "toktok", img: toktokIcon, label: "TokTok", tint: "bg-[hsl(var(--accent-toktok)/0.18)]" },
  { id: "food", img: repasIcon, label: "Repas", tint: "bg-transparent" },
  { id: "market", img: marcheIcon, label: "Marché", tint: "bg-[hsl(var(--accent-marche)/0.10)]" },
  { id: "send", img: envoyerIcon, label: "Envoyer", tint: "bg-[hsl(var(--accent-envoyer)/0.15)]" },
  { id: "scan", img: scannerIcon, label: "Scanner", tint: "bg-muted" },
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
      className="grid grid-cols-3 gap-x-4 gap-y-3"
    >
      {actions.map((action) => (
        <motion.button
          key={action.id}
          variants={item}
          whileHover={{ scale: 1.05 }}
          whileTap={{ scale: 0.95 }}
          onClick={() => onActionClick(action.id)}
          className="flex flex-col items-center transition-transform"
        >
          <div className={`w-20 h-20 rounded-2xl ${action.tint} flex items-center justify-center mb-2 shadow-card overflow-hidden`}>
            <img
              src={action.img}
              alt={action.label}
              loading="lazy"
              width={1024}
              height={1024}
              className="w-20 h-20 object-contain scale-150"
            />
          </div>
          <span className="text-xs font-semibold text-foreground">{action.label}</span>
        </motion.button>
      ))}
    </motion.div>
  );
}
