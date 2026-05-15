import { motion } from "framer-motion";
import { Eye, EyeOff, Plus, History, Wallet, AlertTriangle, Lock, QrCode } from "lucide-react";
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
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.45, ease: [0.22, 1, 0.36, 1] }}
      className="gradient-wallet-premium rounded-[28px] p-5 text-primary-foreground relative overflow-hidden shadow-wallet"
      aria-label="Solde CHOPWallet"
    >
      {/* Layered ambient highlights — restrained, no neon */}
      <div className="pointer-events-none absolute -top-20 -right-12 w-56 h-56 rounded-full bg-white/10 blur-3xl" aria-hidden />
      <div className="pointer-events-none absolute -bottom-20 -left-14 w-48 h-48 rounded-full bg-secondary/20 blur-3xl" aria-hidden />
      {/* Inner light edge */}
      <div className="pointer-events-none absolute inset-0 rounded-[28px] ring-1 ring-inset ring-white/10" aria-hidden />
      {/* Saffron flow seam — gold hairline anchoring the money surface */}
      <div className="pointer-events-none absolute inset-x-6 top-0 h-px saffron-seam" aria-hidden />

      <div className="flex items-start justify-between mb-4 relative">
        <div className="flex items-center gap-2.5 opacity-95">
          <span className="inline-flex items-center justify-center w-7 h-7 rounded-xl bg-white/12 ring-1 ring-white/15">
            <Wallet className="w-3.5 h-3.5" strokeWidth={2} />
          </span>
          <div className="leading-tight">
            <p className="text-[10.5px] uppercase tracking-[0.22em] font-semibold">CHOPWallet</p>
            <p className="text-[10px] opacity-75 tracking-wide">Compte CHOP CHOP · GNF</p>
          </div>
        </div>
        <button
          onClick={() => setShown((s) => !s)}
          className="p-2 rounded-full bg-white/12 ring-1 ring-white/12 hover:bg-white/20 transition-colors"
          aria-label={shown ? "Masquer le solde" : "Afficher le solde"}
        >
          {shown ? <EyeOff className="w-3.5 h-3.5" /> : <Eye className="w-3.5 h-3.5" />}
        </button>
      </div>

      <div className="mb-5 min-h-[44px] relative">
        {loading ? (
          <Skeleton className="h-10 w-44 rounded-lg bg-white/15" />
        ) : error ? (
          <p className="text-sm font-medium inline-flex items-center gap-2">
            <AlertTriangle className="w-4 h-4" /> Solde indisponible
          </p>
        ) : (
          <h2 className="text-[36px] font-extrabold leading-none tracking-tight tabular-nums">
            {shown ? formatGNF(balance) : "••••••••"}
          </h2>
        )}
        {frozen ? (
          <p className="text-[11px] opacity-85 mt-2 inline-flex items-center gap-1.5">
            <Lock className="w-3 h-3" />
            {status === "frozen"
              ? "CHOPWallet gelé — contactez le support"
              : "CHOPWallet restreint — vérifiez votre profil"}
          </p>
        ) : (
          <span className="mt-2 inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full bg-white/14 ring-1 ring-white/18 text-[10.5px] font-medium">
            <span className="w-1.5 h-1.5 rounded-full bg-secondary shadow-[0_0_6px_hsl(var(--secondary)/0.7)]" />
            {zero ? "Prêt à recharger" : "Disponible · sécurisé par CHOPPay"}
          </span>
        )}
      </div>

      <div className="flex gap-2 relative">
        <motion.button
          whileTap={{ scale: 0.985 }}
          onClick={onTopUp}
          disabled={frozen}
          className="flex-1 flex items-center justify-center gap-2 py-3 bg-white text-primary rounded-2xl font-semibold text-sm shadow-card hover:shadow-soft transition-shadow disabled:opacity-50"
        >
          {frozen ? <Lock className="w-4 h-4" /> : <Plus className="w-4 h-4" />}
          Recharger
        </motion.button>
        <motion.button
          whileTap={{ scale: 0.985 }}
          onClick={onHistory}
          className="flex-1 flex items-center justify-center gap-2 py-3 glass-surface hover:bg-white/22 rounded-2xl font-medium text-sm ring-1 ring-white/15"
        >
          <History className="w-4 h-4" /> Historique
        </motion.button>
        <motion.button
          whileTap={{ scale: 0.985 }}
          onClick={onHistory}
          aria-label="Mon QR CHOPPay"
          className="w-12 flex items-center justify-center py-3 rounded-2xl bg-secondary/90 text-secondary-foreground ring-1 ring-secondary/40 shadow-card"
        >
          <QrCode className="w-4 h-4" />
        </motion.button>
      </div>
    </motion.section>
  );
}