import { motion } from "framer-motion";
import { Eye, EyeOff, ArrowUpRight, ArrowDownLeft } from "lucide-react";
import { useState } from "react";

interface WalletCardProps {
  balance: number;
  currency?: string;
  onSend?: () => void;
  onReceive?: () => void;
}

export function WalletCard({ balance, currency = "GNF", onSend, onReceive }: WalletCardProps) {
  const [showBalance, setShowBalance] = useState(true);

  const formatBalance = (amount: number) => {
    return new Intl.NumberFormat("fr-GN").format(amount);
  };

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      className="gradient-primary rounded-2xl p-5 text-primary-foreground shadow-soft"
    >
      <div className="flex justify-between items-start mb-4">
        <div>
          <p className="text-sm opacity-80">Solde disponible</p>
          <div className="flex items-center gap-2 mt-1">
            <h2 className="text-2xl font-bold">
              {showBalance ? `${formatBalance(balance)} ${currency}` : "••••••••"}
            </h2>
            <button
              onClick={() => setShowBalance(!showBalance)}
              className="p-1 rounded-full bg-white/20 hover:bg-white/30 transition-colors"
            >
              {showBalance ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
            </button>
          </div>
        </div>
        <div className="w-10 h-10 rounded-full bg-white/20 flex items-center justify-center">
          <span className="text-lg font-bold">C</span>
        </div>
      </div>

      <div className="flex gap-3">
        <motion.button
          whileHover={{ scale: 1.02 }}
          whileTap={{ scale: 0.98 }}
          onClick={onSend}
          className="flex-1 flex items-center justify-center gap-2 py-3 bg-white/20 hover:bg-white/30 rounded-xl transition-colors"
        >
          <ArrowUpRight className="w-4 h-4" />
          <span className="font-medium text-sm">Envoyer</span>
        </motion.button>
        <motion.button
          whileHover={{ scale: 1.02 }}
          whileTap={{ scale: 0.98 }}
          onClick={onReceive}
          className="flex-1 flex items-center justify-center gap-2 py-3 bg-white/20 hover:bg-white/30 rounded-xl transition-colors"
        >
          <ArrowDownLeft className="w-4 h-4" />
          <span className="font-medium text-sm">Recevoir</span>
        </motion.button>
      </div>
    </motion.div>
  );
}
