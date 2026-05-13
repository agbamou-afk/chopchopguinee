import { motion } from "framer-motion";
import { formatGNF } from "@/lib/format";
import { useState } from "react";
import { Link } from "react-router-dom";
import {
  ArrowUpRight,
  ArrowDownLeft,
  History,
  CreditCard,
  QrCode,
  Plus,
  Loader2,
  LogIn,
  ShieldCheck,
  AlertTriangle,
} from "lucide-react";
import { WalletCard } from "@/components/home/WalletCard";
import { useWallet, type WalletTransaction } from "@/hooks/useWallet";
import { PinSetup } from "@/components/wallet/PinSetup";
import { MyQrModal } from "@/components/wallet/MyQrModal";
import { Button } from "@/components/ui/button";
import { toast } from "sonner";
import { ScreenHeader } from "@/components/ui/ScreenHeader";
import { LiveStrip } from "@/components/ui/LiveStrip";
import { Timer, Users } from "lucide-react";

type ActionId = "send" | "receive" | "scan" | "add";

const quickActions: {
  id: ActionId;
  icon: typeof ArrowUpRight;
  label: string;
  color: string;
}[] = [
  { id: "send", icon: ArrowUpRight, label: "Envoyer", color: "gradient-primary" },
  { id: "receive", icon: ArrowDownLeft, label: "Recevoir", color: "gradient-secondary" },
  { id: "scan", icon: QrCode, label: "Mon QR", color: "bg-foreground" },
  { id: "add", icon: Plus, label: "Recharger", color: "bg-primary" },
];

const TX_LABEL: Record<string, string> = {
  topup: "Recharge",
  payment: "Paiement",
  refund: "Remboursement",
  commission: "Commission",
  payout: "Versement",
  hold: "Réservation",
  capture: "Débit",
  release: "Libération",
  transfer: "Transfert",
  adjustment: "Ajustement",
};

function formatMoney(amount: number) {
  return formatGNF(Math.abs(amount));
}

function formatDate(iso: string) {
  const d = new Date(iso);
  return d.toLocaleString("fr-FR", {
    day: "2-digit",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function txDirection(tx: WalletTransaction, walletId: string): "in" | "out" {
  return tx.to_wallet_id === walletId ? "in" : "out";
}

export function WalletView() {
  const { userId, wallet, transactions, profile, loading } = useWallet();
  const [qrOpen, setQrOpen] = useState(false);

  if (loading) {
    return (
      <div className="max-w-md mx-auto py-20 flex justify-center">
        <Loader2 className="w-6 h-6 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (!userId) {
    return (
      <div className="max-w-md mx-auto px-4 py-16 text-center">
        <div className="w-16 h-16 rounded-2xl gradient-primary mx-auto flex items-center justify-center mb-4">
          <LogIn className="w-7 h-7 text-primary-foreground" />
        </div>
        <h2 className="text-xl font-bold text-foreground mb-2">Portefeuille CHOP CHOP</h2>
        <p className="text-sm text-muted-foreground mb-6">
          Connectez-vous pour activer votre portefeuille et commencer à payer en GNF.
        </p>
        <Link to="/auth">
          <Button className="w-full h-12 gradient-primary">Se connecter</Button>
        </Link>
      </div>
    );
  }

  const available = wallet ? wallet.balance_gnf - wallet.held_gnf : 0;
  const needsPin = !profile?.has_pin;
  const lowBalance = wallet !== null && available < 50000;

  const onAction = (id: ActionId) => {
    if (id === "scan" || id === "add" || id === "receive") setQrOpen(true);
    else toast("Bientôt disponible");
  };

  return (
    <div className="max-w-md mx-auto">
      <ScreenHeader
        title="Portefeuille"
        subtitle={profile?.phone ?? "Vos paiements en GNF"}
      />

      <div className="px-4 mt-4">
        <WalletCard
          balance={available}
          onSend={() => onAction("send")}
          onReceive={() => onAction("receive")}
        />
        {wallet && wallet.held_gnf > 0 && (
          <p className="text-xs text-muted-foreground mt-2 text-center">
            {formatMoney(wallet.held_gnf)} en attente
          </p>
        )}
      </div>

      <div className="mt-4">
        <LiveStrip
          stats={[
            { icon: ShieldCheck, label: "Paiements sécurisés", bg: "bg-primary/10", tone: "text-primary" },
            { icon: Timer, label: "Recharge instantanée", bg: "bg-secondary/20", tone: "text-foreground" },
            { icon: Users, label: "Réseau d'agents CHOP CHOP", bg: "bg-success/10", tone: "text-success" },
          ]}
        />
      </div>

      {/* PIN setup */}
      {needsPin && (
        <div className="px-4 mt-4 mb-6">
          <PinSetup userId={userId} onDone={() => window.location.reload()} />
        </div>
      )}

      {/* Low balance alert */}
      {!needsPin && lowBalance && (
        <div className="px-4 mb-6">
          <div className="bg-brand-yellow-muted border border-secondary/40 rounded-2xl p-4 flex items-start gap-3">
            <div className="p-2 rounded-xl bg-secondary/20 shrink-0">
              <AlertTriangle className="w-5 h-5 text-secondary-foreground" />
            </div>
            <div className="flex-1">
              <p className="font-semibold text-foreground text-sm">Solde faible</p>
              <p className="text-xs text-muted-foreground">
                Rechargez chez un agent CHOP CHOP pour continuer à payer vos courses et vos repas.
              </p>
            </div>
            <Button size="sm" variant="outline" onClick={() => setQrOpen(true)}>
              Recharger
            </Button>
          </div>
        </div>
      )}

      {/* Quick actions */}
      <div className="px-4 mt-4 mb-6">
        <div className="grid grid-cols-4 gap-3">
          {quickActions.map((action, index) => (
            <motion.button
              key={action.id}
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: index * 0.05 }}
              whileHover={{ scale: 1.05 }}
              whileTap={{ scale: 0.95 }}
              onClick={() => onAction(action.id)}
              className="flex flex-col items-center"
            >
              <div className={`p-3 rounded-2xl ${action.color} shadow-soft mb-2`}>
                <action.icon className="w-5 h-5 text-primary-foreground" />
              </div>
              <span className="text-xs font-medium text-foreground">{action.label}</span>
            </motion.button>
          ))}
        </div>
      </div>

      {/* Status / security */}
      {!needsPin && (
        <div className="px-4 mb-6">
          <div className="bg-card rounded-2xl p-4 shadow-card flex items-center gap-3">
            <div className="p-2 rounded-xl bg-primary/10">
              <ShieldCheck className="w-5 h-5 text-primary" />
            </div>
            <div className="flex-1">
              <p className="font-medium text-foreground text-sm">Code PIN actif</p>
              <p className="text-xs text-muted-foreground">
                Votre portefeuille est sécurisé
              </p>
            </div>
          </div>
        </div>
      )}

      {/* Transaction history */}
      <div className="px-4 pb-6">
        <div className="flex items-center justify-between mb-3">
          <h2 className="text-lg font-bold text-foreground">Historique</h2>
          <button className="text-sm font-semibold text-primary flex items-center gap-1">
            <History className="w-4 h-4" />
            Voir tout
          </button>
        </div>

        {transactions.length === 0 ? (
          <div className="bg-card rounded-2xl p-8 text-center shadow-card">
            <CreditCard className="w-8 h-8 mx-auto text-muted-foreground mb-2" />
            <p className="text-sm text-muted-foreground">
              Aucune transaction pour le moment
            </p>
            <p className="text-xs text-muted-foreground mt-1">
              Rechargez votre portefeuille chez un agent CHOP CHOP
            </p>
          </div>
        ) : (
          <div className="space-y-3">
            {transactions.map((tx, index) => {
              const dir = wallet ? txDirection(tx, wallet.id) : "out";
              return (
                <motion.div
                  key={tx.id}
                  initial={{ opacity: 0, x: -20 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ delay: index * 0.03 }}
                  className="bg-card rounded-2xl p-4 shadow-card flex items-center gap-3"
                >
                  <div
                    className={`p-2 rounded-xl ${
                      dir === "in" ? "bg-success/10" : "bg-destructive/10"
                    }`}
                  >
                    {dir === "in" ? (
                      <ArrowDownLeft className="w-5 h-5 text-success" />
                    ) : (
                      <ArrowUpRight className="w-5 h-5 text-destructive" />
                    )}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="font-medium text-foreground text-sm">
                      {TX_LABEL[tx.type] ?? tx.type}
                    </p>
                    <p className="text-xs text-muted-foreground truncate">
                      {tx.description ?? tx.reference}
                    </p>
                  </div>
                  <div className="text-right">
                    <p
                      className={`font-semibold text-sm ${
                        dir === "in" ? "text-success" : "text-foreground"
                      }`}
                    >
                      {dir === "in" ? "+" : "-"}
                      {formatMoney(tx.amount_gnf)}
                    </p>
                    <p className="text-xs text-muted-foreground">
                      {formatDate(tx.created_at)}
                    </p>
                  </div>
                </motion.div>
              );
            })}
          </div>
        )}
      </div>

      <MyQrModal
        open={qrOpen}
        onClose={() => setQrOpen(false)}
        userId={userId}
        phone={profile?.phone ?? null}
      />
    </div>
  );
}
