import { motion } from "framer-motion";
import { formatGNF } from "@/lib/format";
import { Eye, EyeOff, ArrowUpRight, ArrowDownLeft, Wallet } from "lucide-react";
import { useState } from "react";

interface WalletCardProps {
  balance: number;
  currency?: string;
  onSend?: () => void;
  onReceive?: () => void;
}

export function WalletCard({ balance, onSend, onReceive }: WalletCardProps) {
  const [showBalance, setShowBalance] = useState(true);

  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      className="gradient-wallet rounded-3xl p-5 text-primary-foreground shadow-soft ring-glow-primary relative overflow-hidden"
    >
      <div className="pointer-events-none absolute -top-12 -right-10 w-44 h-44 rounded-full bg-white/10 blur-2xl" aria-hidden />
      <div className="flex justify-between items-start mb-4">
        <div>
          <div className="flex items-center gap-2 opacity-90">
            <Wallet className="w-4 h-4" />
            <p className="text-[11px] uppercase tracking-wider">Solde disponible</p>
          </div>
          <div className="flex items-center gap-2 mt-1">
            <h2 className="text-3xl font-extrabold leading-none">
              {showBalance ? formatGNF(balance) : "••••••••"}
            </h2>
            <button
              onClick={() => setShowBalance(!showBalance)}
              className="p-1 rounded-full bg-white/20 hover:bg-white/30 transition-colors"
            >
              {showBalance ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
            </button>
          </div>
          <p className="text-[11px] opacity-80 mt-1">Paiements sécurisés · GNF</p>
        </div>
        <div className="w-11 h-11 rounded-2xl glass-surface flex items-center justify-center font-extrabold">
          C
        </div>
      </div>

      <div className="flex gap-3">
        <motion.button
          whileHover={{ scale: 1.02 }}
          whileTap={{ scale: 0.98 }}
          onClick={onSend}
          className="flex-1 flex items-center justify-center gap-2 py-3 glass-surface hover:bg-white/25 rounded-2xl transition-colors"
        >
          <ArrowUpRight className="w-4 h-4" />
          <span className="font-medium text-sm">Envoyer</span>
        </motion.button>
        <motion.button
          whileHover={{ scale: 1.02 }}
          whileTap={{ scale: 0.98 }}
          onClick={onReceive}
          className="flex-1 flex items-center justify-center gap-2 py-3 glass-surface hover:bg-white/25 rounded-2xl transition-colors"
        >
          <ArrowDownLeft className="w-4 h-4" />
          <span className="font-medium text-sm">Recevoir</span>
        </motion.button>
      </div>
    </motion.div>
  );
}
