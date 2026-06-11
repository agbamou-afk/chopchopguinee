import { useWallet } from "@/hooks/useWallet";
import { Wallet as WalletIcon, ArrowDownLeft, ArrowUpRight, Clock, Info } from "lucide-react";
import { Button } from "@/components/ui/button";

const fmt = (n: number) => `${(n ?? 0).toLocaleString("fr-FR")} GNF`;

export function MerchantWalletSection() {
  // Bound to the MERCHANT wallet (party_type='merchant'), never the
  // owner's personal client wallet. Until merchant sale settlement is
  // wired (Phase 2+), this stays at 0 with an honest empty state.
  const { wallet, balance, held, available, transactions, loading } = useWallet("merchant");

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
            <p className="text-xs text-muted-foreground">CHOP Wallet Marchand · Solde disponible</p>
            <p className="text-xl font-extrabold text-foreground">{loading ? "…" : fmt(balance)}</p>
          </div>
        </div>
        <div className="grid grid-cols-3 gap-2 mt-3">
          <div className="rounded-lg bg-muted/40 p-2 text-center">
            <p className="text-[10px] text-muted-foreground">Disponible</p>
            <p className="text-xs font-bold text-foreground">{fmt(available)}</p>
          </div>
          <div className="rounded-lg bg-muted/40 p-2 text-center">
            <p className="text-[10px] text-muted-foreground">En attente règlement</p>
            <p className="text-xs font-bold text-foreground">{fmt(held)}</p>
          </div>
          <div className="rounded-lg bg-muted/40 p-2 text-center">
            <p className="text-[10px] text-muted-foreground">Ventes aujourd'hui</p>
            <p className="text-xs font-bold text-foreground">{fmt(todayRevenue)}</p>
          </div>
        </div>
        <div className="flex gap-2 mt-3">
          <Button size="sm" variant="outline" className="flex-1" disabled title="Disponible après la mise en place du règlement marchand">
            <Clock className="w-3 h-3 mr-1" /> Retrait bientôt disponible
          </Button>
        </div>
      </div>

      <div className="bg-card rounded-2xl border border-border/60 p-4">
        <h3 className="font-bold text-foreground mb-2">Dernières transactions</h3>
        {transactions.length === 0 ? (
          <div className="rounded-xl bg-muted/40 border border-border/60 p-3 flex items-start gap-2">
            <Info className="w-4 h-4 text-muted-foreground mt-0.5 shrink-0" />
            <div className="text-xs text-muted-foreground">
              <p className="font-semibold text-foreground">Aucun paiement CHOP reçu pour l'instant.</p>
              <p className="mt-0.5">Les ventes payées via CHOP seront affichées ici après validation.</p>
            </div>
          </div>
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