import { useWallet } from "@/hooks/useWallet";
import { Wallet as WalletIcon, ArrowDownLeft, ArrowUpRight, Clock } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useNavigate } from "react-router-dom";

const fmt = (n: number) => `${(n ?? 0).toLocaleString("fr-FR")} GNF`;

export function MerchantWalletSection() {
  const { wallet, balance, held, available, transactions, loading } = useWallet("client");
  const navigate = useNavigate();

  const today = new Date(); today.setHours(0, 0, 0, 0);
  const todayRevenue = transactions
    .filter((t) => t.status === "completed" && t.to_wallet_id === wallet?.id && new Date(t.created_at) >= today)
    .reduce((s, t) => s + (t.amount_gnf ?? 0), 0);

  return (
    <div className="space-y-3">
      <div className="bg-card rounded-2xl border border-border/60 p-4">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl gradient-wallet flex items-center justify-center">
            <WalletIcon className="w-5 h-5 text-primary-foreground" />
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-xs text-muted-foreground">Solde CHOP Wallet</p>
            <p className="text-xl font-extrabold text-foreground">{loading ? "…" : fmt(balance)}</p>
          </div>
        </div>
        <div className="grid grid-cols-3 gap-2 mt-3">
          <div className="rounded-lg bg-muted/40 p-2 text-center">
            <p className="text-[10px] text-muted-foreground">Disponible</p>
            <p className="text-xs font-bold text-foreground">{fmt(available)}</p>
          </div>
          <div className="rounded-lg bg-muted/40 p-2 text-center">
            <p className="text-[10px] text-muted-foreground">En attente</p>
            <p className="text-xs font-bold text-foreground">{fmt(held)}</p>
          </div>
          <div className="rounded-lg bg-muted/40 p-2 text-center">
            <p className="text-[10px] text-muted-foreground">Aujourd'hui</p>
            <p className="text-xs font-bold text-foreground">{fmt(todayRevenue)}</p>
          </div>
        </div>
        <div className="flex gap-2 mt-3">
          <Button size="sm" variant="outline" className="flex-1" onClick={() => navigate("/?tab=wallet")}>
            Voir CHOP Wallet
          </Button>
          <Button size="sm" variant="outline" className="flex-1" disabled title="Bientôt disponible">
            <Clock className="w-3 h-3 mr-1" /> Retrait bientôt
          </Button>
        </div>
      </div>

      <div className="bg-card rounded-2xl border border-border/60 p-4">
        <h3 className="font-bold text-foreground mb-2">Dernières transactions</h3>
        {transactions.length === 0 ? (
          <p className="text-sm text-muted-foreground">Aucune transaction pour l'instant.</p>
        ) : (
          <div className="space-y-2">
            {transactions.slice(0, 8).map((t) => {
              const incoming = t.to_wallet_id === wallet?.id;
              const Icon = incoming ? ArrowDownLeft : ArrowUpRight;
              return (
                <div key={t.id} className="flex items-center gap-3">
                  <div className={`w-8 h-8 rounded-full flex items-center justify-center ${incoming ? "bg-emerald-500/15 text-emerald-600" : "bg-muted text-muted-foreground"}`}>
                    <Icon className="w-4 h-4" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-foreground truncate">{t.description ?? t.type}</p>
                    <p className="text-[11px] text-muted-foreground">{new Date(t.created_at).toLocaleString("fr-FR")}</p>
                  </div>
                  <p className={`text-sm font-bold ${incoming ? "text-emerald-600" : "text-foreground"}`}>
                    {incoming ? "+" : "-"}{fmt(t.amount_gnf)}
                  </p>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}