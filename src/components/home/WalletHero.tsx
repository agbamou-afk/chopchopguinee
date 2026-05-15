import { motion } from "framer-motion";
import { Eye, EyeOff, Plus, History, Wallet, AlertTriangle, Lock } from "lucide-react";
import { useState } from "react";
import { formatGNF } from "@/lib/format";
import { Skeleton } from "@/components/ui/skeleton";

interface Props {
  balance: number;
  loading?: boolean;
  error?: string | null;
  status?: "active" | "frozen" | "restricted";
  onTopUp: () => void;
  onHistory: () => void;
}

export function WalletHero({ balance, loading, error, status = "active", onTopUp, onHistory }: Props) {
  const [shown, setShown] = useState(true);
  const frozen = status !== "active";
  const zero = !loading && !error && balance === 0;

  return (
    <motion.section
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      className="gradient-wallet rounded-3xl p-5 text-primary-foreground shadow-soft ring-glow-primary relative overflow-hidden"
      aria-label="Solde CHOP CHOP"
    >
      <div className="pointer-events-none absolute -top-12 -right-10 w-44 h-44 rounded-full bg-white/10 blur-2xl" aria-hidden />

      <div className="flex items-start justify-between mb-3">
        <div className="flex items-center gap-2 opacity-90">
          <Wallet className="w-4 h-4" />
          <p className="text-[11px] uppercase tracking-wider">Solde CHOP CHOP</p>
        </div>
        <button
          onClick={() => setShown((s) => !s)}
          className="p-1.5 rounded-full bg-white/15 hover:bg-white/25 transition-colors"
          aria-label={shown ? "Masquer le solde" : "Afficher le solde"}
        >
          {shown ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
        </button>
      </div>

      <div className="mb-4 min-h-[40px]">
        {loading ? (
          <Skeleton className="h-9 w-40 rounded-md bg-white/20" />
        ) : error ? (
          <p className="text-sm font-medium inline-flex items-center gap-2">
            <AlertTriangle className="w-4 h-4" /> Solde indisponible
          </p>
        ) : (
          <h2 className="text-3xl font-extrabold leading-none">
            {shown ? formatGNF(balance) : "••••••••"}
          </h2>
        )}
        <p className="text-[11px] opacity-80 mt-1">
          {frozen
            ? status === "frozen"
              ? "CHOPWallet gelé — contactez le support"
              : "CHOPWallet restreint — vérifiez votre profil"
            : zero
            ? "Rechargez pour commencer à payer en GNF"
            : "Paiements sécurisés · GNF"}
        </p>
      </div>

      <div className="flex gap-2">
        <motion.button
          whileTap={{ scale: 0.97 }}
          onClick={onTopUp}
          disabled={frozen}
          className="flex-1 flex items-center justify-center gap-2 py-3 bg-white text-primary rounded-2xl font-semibold text-sm disabled:opacity-50"
        >
          {frozen ? <Lock className="w-4 h-4" /> : <Plus className="w-4 h-4" />}
          Recharger
        </motion.button>
        <motion.button
          whileTap={{ scale: 0.97 }}
          onClick={onHistory}
          className="flex-1 flex items-center justify-center gap-2 py-3 glass-surface hover:bg-white/25 rounded-2xl font-medium text-sm"
        >
          <History className="w-4 h-4" /> Historique
        </motion.button>
      </div>
    </motion.section>
  );
}