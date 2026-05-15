import { motion } from "framer-motion";
import { formatGNF } from "@/lib/format";
import { useEffect, useMemo, useState } from "react";
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
  Clock,
  XCircle,
  Sparkles,
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
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetDescription,
} from "@/components/ui/sheet";
import { TopUpOrangeMoney } from "@/components/wallet/TopUpOrangeMoney";
import { Skeleton } from "@/components/ui/skeleton";
import { Analytics } from "@/lib/analytics/AnalyticsService";

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
  topup: "Recharge reçue",
  payment: "Paiement CHOPPay",
  refund: "Remboursement",
  commission: "Commission course",
  payout: "Versement chauffeur",
  hold: "Fonds réservés",
  capture: "Course payée",
  release: "Fonds libérés",
  transfer: "Transfert",
  adjustment: "Ajustement",
};

// Calm, plain-French status copy. We avoid banking jargon ("Pending",
// "Authorized", "Settled") in favor of confidence-building phrasing.
const TX_STATUS_BADGE: Record<string, { label: string; tone: string; Icon: React.ComponentType<{ className?: string }> }> = {
  pending:   { label: "En attente",  tone: "bg-secondary/15 text-secondary-foreground border-secondary/30", Icon: Clock },
  failed:    { label: "Échoué",      tone: "bg-destructive/10 text-destructive border-destructive/30",     Icon: XCircle },
  cancelled: { label: "Annulé",      tone: "bg-muted text-muted-foreground border-border",                  Icon: XCircle },
  reversed:  { label: "Annulé",      tone: "bg-muted text-muted-foreground border-border",                  Icon: XCircle },
};

function formatMoney(amount: number) {
  return formatGNF(Math.abs(amount));
}

function formatDate(iso: string) {
  const d = new Date(iso);
  const now = new Date();
  const sameDay = d.toDateString() === now.toDateString();
  const yest = new Date(now); yest.setDate(now.getDate() - 1);
  const isYesterday = d.toDateString() === yest.toDateString();
  const time = d.toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" });
  if (sameDay) return `Aujourd'hui · ${time}`;
  if (isYesterday) return `Hier · ${time}`;
  return d.toLocaleString("fr-FR", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" });
}

function txDirection(tx: WalletTransaction, walletId: string): "in" | "out" {
  return tx.to_wallet_id === walletId ? "in" : "out";
}

export function WalletView() {
  const { userId, wallet, transactions, profile, loading } = useWallet();
  const [qrOpen, setQrOpen] = useState(false);
  const [topUpOpen, setTopUpOpen] = useState(false);
  const [filterType, setFilterType] = useState<string>("all");
  const [filterRange, setFilterRange] = useState<"all" | "7d" | "30d">("all");

  useEffect(() => {
    if (userId) Analytics.track("wallet.history.viewed", { metadata: { count: transactions.length } });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [userId]);

  const filteredTransactions = useMemo(() => {
    const now = Date.now();
    return transactions.filter((tx) => {
      if (filterType !== "all" && tx.type !== filterType) return false;
      if (filterRange !== "all") {
        const cutoff = filterRange === "7d" ? 7 : 30;
        if (now - new Date(tx.created_at).getTime() > cutoff * 86400000) return false;
      }
      return true;
    });
  }, [transactions, filterType, filterRange]);

  // Lightweight retention metric — total inflow over the last 30 days
  // surfaced as "Vous économisez avec CHOPWallet". No casino mechanics.
  const inflowLast30 = useMemo(() => {
    if (!wallet) return 0;
    const cutoff = Date.now() - 30 * 86400000;
    return transactions.reduce((sum, tx) => {
      if (tx.status !== "completed" && tx.status !== "captured") return sum;
      if (new Date(tx.created_at).getTime() < cutoff) return sum;
      if (txDirection(tx, wallet.id) !== "in") return sum;
      return sum + Math.abs(tx.amount_gnf);
    }, 0);
  }, [transactions, wallet]);

  if (loading) {
    return (
      <div className="max-w-md mx-auto px-4 py-6 space-y-4">
        <Skeleton className="h-32 w-full rounded-3xl" />
        <div className="grid grid-cols-4 gap-2">
          {Array.from({ length: 4 }).map((_, i) => (
            <Skeleton key={i} className="h-16 rounded-2xl" />
          ))}
        </div>
        <Skeleton className="h-48 w-full rounded-2xl" />
      </div>
    );
  }

  if (!userId) {
    return (
      <div className="max-w-md mx-auto px-4 py-16 text-center">
        <div className="w-16 h-16 rounded-2xl gradient-primary mx-auto flex items-center justify-center mb-4">
          <LogIn className="w-7 h-7 text-primary-foreground" />
        </div>
        <h2 className="text-xl font-bold text-foreground mb-2">CHOPWallet</h2>
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
    if (id === "add") setTopUpOpen(true);
    else if (id === "scan" || id === "receive") setQrOpen(true);
    else toast("Bientôt disponible");
  };

  return (
    <div className="max-w-md mx-auto">
      <ScreenHeader
        title="CHOPWallet"
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
        {inflowLast30 > 0 && (
          <div className="mt-3 mx-auto max-w-[22rem] flex items-center gap-2 rounded-full border border-primary/15 bg-primary/[0.06] px-3 py-1.5">
            <Sparkles className="w-3.5 h-3.5 text-primary shrink-0" />
            <p className="text-[11px] text-foreground/80">
              <span className="font-semibold">{formatMoney(inflowLast30)}</span> reçus sur 30 jours via CHOPWallet
            </p>
          </div>
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
            <Button size="sm" variant="outline" onClick={() => setTopUpOpen(true)}>
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
      <div className="px-4 pb-28">
        <div className="flex items-center justify-between mb-3">
          <h2 className="text-lg font-bold text-foreground">Historique</h2>
          <button className="text-sm font-semibold text-primary flex items-center gap-1">
            <History className="w-4 h-4" />
            Voir tout
          </button>
        </div>

        {/* Filters */}
        <div className="flex gap-2 mb-3 overflow-x-auto scrollbar-hide -mx-4 px-4">
          {[
            { v: "all", l: "Tous" },
            { v: "topup", l: "Recharges" },
            { v: "payment", l: "Paiements" },
            { v: "refund", l: "Remboursements" },
            { v: "transfer", l: "Transferts" },
            { v: "adjustment", l: "Ajustements" },
          ].map((o) => (
            <button
              key={o.v}
              onClick={() => setFilterType(o.v)}
              className={`shrink-0 text-xs font-medium px-3 py-1.5 rounded-full border transition ${
                filterType === o.v
                  ? "bg-primary text-primary-foreground border-primary"
                  : "bg-card text-foreground border-border hover:bg-muted"
              }`}
            >
              {o.l}
            </button>
          ))}
          <div className="w-px bg-border mx-1" />
          {[
            { v: "all", l: "Tout" },
            { v: "7d", l: "7j" },
            { v: "30d", l: "30j" },
          ].map((o) => (
            <button
              key={o.v}
              onClick={() => setFilterRange(o.v as any)}
              className={`shrink-0 text-xs font-medium px-3 py-1.5 rounded-full border transition ${
                filterRange === o.v
                  ? "bg-foreground text-background border-foreground"
                  : "bg-card text-foreground border-border hover:bg-muted"
              }`}
            >
              {o.l}
            </button>
          ))}
        </div>

        {filteredTransactions.length === 0 ? (
          <EmptyHistory
            empty={transactions.length === 0}
            onTopUp={() => setTopUpOpen(true)}
          />
        ) : (
          <div className="space-y-3">
            {filteredTransactions.map((tx, index) => {
              const dir = wallet ? txDirection(tx, wallet.id) : "out";
              const statusBadge =
                tx.status && TX_STATUS_BADGE[tx.status] ? TX_STATUS_BADGE[tx.status] : null;
              const dimmed = tx.status === "failed" || tx.status === "cancelled" || tx.status === "reversed";
              return (
                <motion.div
                  key={tx.id}
                  initial={{ opacity: 0, x: -20 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ delay: index * 0.03 }}
                  className={`bg-card rounded-2xl p-4 shadow-card flex items-center gap-3 ${dimmed ? "opacity-70" : ""}`}
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
                    <div className="flex items-center gap-2">
                      <p className="font-medium text-foreground text-sm truncate">
                        {TX_LABEL[tx.type] ?? tx.type}
                      </p>
                      {statusBadge && (
                        <span className={`inline-flex items-center gap-1 text-[10px] font-semibold px-1.5 py-0.5 rounded-full border ${statusBadge.tone}`}>
                          <statusBadge.Icon className="w-2.5 h-2.5" />
                          {statusBadge.label}
                        </span>
                      )}
                    </div>
                    <p className="text-xs text-muted-foreground truncate">
                      {tx.description ?? tx.reference}
                    </p>
                  </div>
                  <div className="text-right">
                    <p
                      className={`font-semibold text-sm ${
                        dimmed ? "text-muted-foreground line-through" : dir === "in" ? "text-success" : "text-foreground"
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

      <Sheet open={topUpOpen} onOpenChange={setTopUpOpen}>
        <SheetContent side="bottom" className="rounded-t-3xl max-h-[92vh] overflow-y-auto">
          <SheetHeader className="text-left">
            <SheetTitle>Recharger via Orange Money</SheetTitle>
            <SheetDescription>
              Payez le compte marchand CHOP CHOP — votre portefeuille est crédité automatiquement.
            </SheetDescription>
          </SheetHeader>
          <div className="mt-4">
            <TopUpOrangeMoney onClose={() => setTopUpOpen(false)} />
          </div>
        </SheetContent>
      </Sheet>
    </div>
  );
}

function EmptyHistory({ empty, onTopUp }: { empty: boolean; onTopUp: () => void }) {
  useEffect(() => {
    if (empty) Analytics.track("wallet.empty_state.viewed");
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [empty]);
  return (
    <div className="bg-card rounded-2xl p-8 text-center shadow-card border border-border/60">
      <div className="w-12 h-12 mx-auto rounded-2xl bg-primary/10 flex items-center justify-center mb-3">
        <CreditCard className="w-5 h-5 text-primary" />
      </div>
      <p className="text-sm font-semibold text-foreground">
        {empty ? "Bienvenue dans CHOPWallet" : "Aucune transaction pour ce filtre"}
      </p>
      <p className="text-xs text-muted-foreground mt-1 max-w-[16rem] mx-auto">
        {empty
          ? "Rechargez chez un agent CHOP CHOP pour commencer à payer vos courses et vos repas avec CHOPPay."
          : "Essayez un autre filtre pour voir vos paiements."}
      </p>
      {empty && (
        <Button size="sm" className="mt-4 gradient-primary" onClick={onTopUp}>
          Recharger maintenant
        </Button>
      )}
    </div>
  );
}
