import { motion } from "framer-motion";
import { Bike, Car, UtensilsCrossed, ShoppingCart, Send, QrCode } from "lucide-react";

interface QuickActionsProps {
  onActionClick: (action: string) => void;
}

const actions = [
  { id: "moto", icon: Bike, label: "Moto", color: "bg-primary" },
  { id: "toktok", icon: Car, label: "TokTok", color: "gradient-secondary" },
  { id: "food", icon: UtensilsCrossed, label: "Repas", color: "bg-destructive" },
  { id: "market", icon: ShoppingCart, label: "Marché", color: "bg-primary" },
  { id: "send", icon: Send, label: "Envoyer", color: "gradient-secondary" },
  { id: "scan", icon: QrCode, label: "Scanner", color: "bg-foreground" },
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
      className="grid grid-cols-4 gap-4"
    >
      {actions.map((action) => (
        <motion.button
          key={action.id}
          variants={item}
          whileHover={{ scale: 1.05 }}
          whileTap={{ scale: 0.95 }}
          onClick={() => onActionClick(action.id)}
          className="flex flex-col items-center"
        >
          <div className={`p-3 rounded-2xl ${action.color} shadow-soft mb-2`}>
            <action.icon className="w-6 h-6 text-primary-foreground" />
          </div>
          <span className="text-xs font-medium text-foreground">{action.label}</span>
        </motion.button>
      ))}
    </motion.div>
  );
}
