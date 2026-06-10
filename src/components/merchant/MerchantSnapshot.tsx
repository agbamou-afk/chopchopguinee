import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Plus, ShoppingBag, Wallet as WalletIcon, ShieldCheck, AlertTriangle, Package, MessageSquare, HandCoins, Store, CheckCircle2 } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { useWallet } from "@/hooks/useWallet";
import type { MerchantStore } from "@/hooks/useMerchantIdentity";

type Props = {
  userId: string;
  store: MerchantStore | null;
  onGo: (tab: "orders" | "catalog" | "wallet" | "store") => void;
};

const fmt = (n: number) => `${(n ?? 0).toLocaleString("fr-FR")} GNF`;

export function MerchantSnapshot({ userId, store, onGo }: Props) {
  const navigate = useNavigate();
  const { balance, loading: walletLoading } = useWallet("client");
  const [counts, setCounts] = useState({
    activeProducts: 0,
    oos: 0,
    pendingInterests: 0,
    pendingOffers: 0,
  });
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let alive = true;
    (async () => {
      setLoading(true);
      const results = await Promise.allSettled([
        (supabase as any).from("marketplace_listings").select("id", { head: true, count: "exact" })
          .eq("seller_id", userId).eq("status", "active").eq("visibility", "public"),
        (supabase as any).from("marketplace_listings").select("id", { head: true, count: "exact" })
          .eq("seller_id", userId).lte("quantity_in_stock", 0).neq("status", "removed"),
        (supabase as any).from("listing_interests").select("id", { head: true, count: "exact" })
          .eq("seller_id", userId).eq("state", "pending"),
        (supabase as any).from("marketplace_offers").select("id", { head: true, count: "exact" })
          .eq("merchant_user_id", userId).in("status", ["pending", "countered"]),
      ]);
      if (!alive) return;
      const c = (i: number) =>
        results[i].status === "fulfilled" ? ((results[i] as any).value.count ?? 0) : 0;
      setCounts({
        activeProducts: c(0),
        oos: c(1),
        pendingInterests: c(2),
        pendingOffers: c(3),
      });
      setLoading(false);
    })();
    return () => { alive = false; };
  }, [userId]);

  const status = store?.onboarding_status ?? "submitted";
  const statusBlock =
    status === "approved" ? { tone: "bg-emerald-500/10 text-emerald-900 border-emerald-500/20", label: "Boutique active", body: "Vos produits sont visibles sur CHOP Marché." } :
    status === "needs_info" ? { tone: "bg-amber-500/10 text-amber-900 border-amber-500/30", label: "À corriger", body: store?.rejection_reason ?? "Complétez la vérification pour publier." } :
    status === "rejected" ? { tone: "bg-destructive/10 text-destructive border-destructive/20", label: "Suspendue", body: store?.rejection_reason ?? "Contactez le support." } :
    { tone: "bg-primary/10 text-primary border-primary/20", label: "En vérification", body: "Préparez votre catalogue — il sera visible après validation." };

  const urgent: Array<{ key: string; label: string; tone: string; action: () => void; icon: typeof AlertTriangle }> = [];
  if (counts.pendingInterests > 0) urgent.push({ key: "int", label: `${counts.pendingInterests} demande(s) à traiter`, tone: "text-primary", icon: MessageSquare, action: () => onGo("orders") });
  if (counts.pendingOffers > 0) urgent.push({ key: "off", label: `${counts.pendingOffers} offre(s) en attente`, tone: "text-primary", icon: HandCoins, action: () => onGo("orders") });
  if (counts.oos > 0) urgent.push({ key: "oos", label: `${counts.oos} produit(s) en rupture`, tone: "text-amber-700", icon: AlertTriangle, action: () => onGo("catalog") });
  if (status !== "approved") urgent.push({ key: "ver", label: "Compléter la vérification", tone: "text-primary", icon: ShieldCheck, action: () => onGo("store") });
  if (counts.activeProducts === 0 && status === "approved") urgent.push({ key: "noProd", label: "Ajouter votre premier produit", tone: "text-primary", icon: Plus, action: () => onGo("catalog") });

  const Stat = ({ icon: Icon, label, value, tone = "text-foreground" }: { icon: typeof Package; label: string; value: string; tone?: string }) => (
    <div className="rounded-xl bg-card border border-border/60 p-3">
      <div className="flex items-center gap-2 text-muted-foreground mb-1">
        <Icon className="w-3.5 h-3.5" />
        <span className="text-[10px] uppercase tracking-wide">{label}</span>
      </div>
      <p className={`text-base font-extrabold ${tone}`}>{value}</p>
    </div>
  );

  return (
    <div className="space-y-3">
      <div className={`rounded-2xl border p-3 ${statusBlock.tone}`}>
        <div className="flex items-center gap-2">
          <Store className="w-4 h-4" />
          <span className="text-sm font-bold">{statusBlock.label}</span>
        </div>
        <p className="text-xs mt-1 opacity-90">{statusBlock.body}</p>
      </div>

      <div className="grid grid-cols-2 gap-2">
        <Stat icon={MessageSquare} label="Demandes" value={loading ? "…" : String(counts.pendingInterests)} tone={counts.pendingInterests > 0 ? "text-primary" : "text-foreground"} />
        <Stat icon={HandCoins} label="Offres" value={loading ? "…" : String(counts.pendingOffers)} tone={counts.pendingOffers > 0 ? "text-primary" : "text-foreground"} />
        <Stat icon={Package} label="Produits actifs" value={loading ? "…" : String(counts.activeProducts)} />
        <Stat icon={AlertTriangle} label="Rupture" value={loading ? "…" : String(counts.oos)} tone={counts.oos > 0 ? "text-amber-700" : "text-foreground"} />
        <div className="col-span-2 rounded-xl bg-card border border-border/60 p-3 flex items-center gap-3">
          <div className="w-9 h-9 rounded-xl gradient-wallet flex items-center justify-center">
            <WalletIcon className="w-4 h-4 text-primary-foreground" />
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Solde CHOP Wallet</p>
            <p className="text-base font-extrabold text-foreground">{walletLoading ? "…" : fmt(balance)}</p>
          </div>
          <button onClick={() => onGo("wallet")} className="text-xs font-semibold text-primary">Ouvrir</button>
        </div>
      </div>

      {urgent.length > 0 && (
        <div className="rounded-2xl bg-card border border-border/60 p-3">
          <p className="text-xs font-bold text-foreground mb-2">À faire maintenant</p>
          <div className="space-y-1.5">
            {urgent.map((u) => {
              const Icon = u.icon;
              return (
                <button key={u.key} onClick={u.action} className={`w-full flex items-center gap-2 text-left text-sm ${u.tone} hover:underline`}>
                  <Icon className="w-4 h-4 shrink-0" />
                  <span className="flex-1">{u.label}</span>
                </button>
              );
            })}
          </div>
        </div>
      )}

      {urgent.length === 0 && !loading && (
        <div className="rounded-2xl bg-emerald-500/5 border border-emerald-500/20 p-3 flex items-center gap-2 text-emerald-800">
          <CheckCircle2 className="w-4 h-4" />
          <span className="text-sm">Tout est à jour. Bonne journée !</span>
        </div>
      )}

      <div className="grid grid-cols-2 gap-2">
        <button onClick={() => onGo("catalog")} className="rounded-2xl bg-card border border-border/60 p-3 flex items-center gap-2 text-left">
          <div className="p-2 rounded-xl bg-primary/10"><Plus className="w-4 h-4 text-primary" /></div>
          <span className="text-sm font-semibold text-foreground">Ajouter un produit</span>
        </button>
        <button onClick={() => onGo("orders")} className="rounded-2xl bg-card border border-border/60 p-3 flex items-center gap-2 text-left">
          <div className="p-2 rounded-xl bg-primary/10"><ShoppingBag className="w-4 h-4 text-primary" /></div>
          <span className="text-sm font-semibold text-foreground">Voir commandes</span>
        </button>
        <button onClick={() => onGo("wallet")} className="rounded-2xl bg-card border border-border/60 p-3 flex items-center gap-2 text-left">
          <div className="p-2 rounded-xl bg-primary/10"><WalletIcon className="w-4 h-4 text-primary" /></div>
          <span className="text-sm font-semibold text-foreground">CHOP Wallet</span>
        </button>
        <button onClick={() => onGo("store")} className="rounded-2xl bg-card border border-border/60 p-3 flex items-center gap-2 text-left">
          <div className="p-2 rounded-xl bg-primary/10"><ShieldCheck className="w-4 h-4 text-primary" /></div>
          <span className="text-sm font-semibold text-foreground">Vérification</span>
        </button>
      </div>
    </div>
  );
}