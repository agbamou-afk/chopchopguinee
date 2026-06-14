import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { ArrowLeft, Home, ShoppingBag, Package, Wallet as WalletIcon, Store as StoreIcon } from "lucide-react";
import { ExternalLink } from "lucide-react";
import { useMerchantIdentity } from "@/hooks/useMerchantIdentity";
import { useAuth } from "@/contexts/AuthContext";
import { supabase } from "@/integrations/supabase/client";
import { MerchantIdentityStrip } from "./MerchantIdentityStrip";
import { OrdersSection } from "./OrdersSection";
import { AvailabilitySection } from "./AvailabilitySection";
import { CatalogSection } from "./CatalogSection";
import { ProductCatalogSection } from "./ProductCatalogSection";
import { DeliverySection } from "./DeliverySection";
import { ChopPayActivitySection } from "./ChopPayActivitySection";
import { setRestaurantOpen, setStoreOpen } from "@/lib/merchant/operations";
import { toast } from "@/hooks/use-toast";
import { MerchantActivationPanel } from "./MerchantActivationPanel";
import { MerchantPendingBanner } from "./MerchantPendingBanner";
import { MerchantModeToggle } from "./ModeToggle";
import { MerchantVerificationChecklist } from "./MerchantVerificationChecklist";
import { MerchantWalletSection } from "./MerchantWalletSection";
import { MerchantSnapshot } from "./MerchantSnapshot";
import { MerchantCommandesView } from "./MerchantCommandesView";
import { ServiceAgentCashInPanel } from "./ServiceAgentCashInPanel";

type Tab = "home" | "orders" | "catalog" | "wallet" | "store";

const TABS: { key: Tab; label: string; icon: typeof Home }[] = [
  { key: "home", label: "Accueil", icon: Home },
  { key: "orders", label: "Commandes", icon: ShoppingBag },
  { key: "catalog", label: "Catalogue", icon: Package },
  { key: "wallet", label: "Wallet", icon: WalletIcon },
  { key: "store", label: "Boutique", icon: StoreIcon },
];

export function MerchantHub() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const { loading, store, restaurant, hasAny, refresh } = useMerchantIdentity();
  const [isOpen, setIsOpen] = useState(false);
  const [tab, setTab] = useState<Tab>("home");

  useEffect(() => {
    setIsOpen(restaurant ? !!restaurant.is_open : store ? store.status === "active" : false);
  }, [restaurant, store]);

  // Phase 1a — bootstrap the merchant wallet (party_type='merchant',
  // owner_user_id=auth.uid()) once the user has an actual merchant
  // store or restaurant. Idempotent via wallet_ensure RPC; never
  // creates a duplicate wallet and never credits funds.
  useEffect(() => {
    if (!user?.id || !hasAny) return;
    supabase.rpc("wallet_ensure", { _party_type: "merchant" }).then(() => {
      // intentional: silent best-effort bootstrap. Wallet is read
      // separately by MerchantWalletSection/MerchantSnapshot.
    });
  }, [user?.id, hasAny]);

  if (loading) {
    return <div className="p-6 text-center text-sm text-muted-foreground">Chargement…</div>;
  }
  if (!user) {
    navigate("/auth", { replace: true });
    return null;
  }

  const handleOpenToggle = async (next: boolean) => {
    setIsOpen(next);
    try {
      if (restaurant) await setRestaurantOpen(restaurant.id, next);
      if (store) await setStoreOpen(store.id, next);
      await refresh();
    } catch (e: unknown) {
      setIsOpen(!next);
      toast({ title: "Erreur", description: e instanceof Error ? e.message : "Action impossible" });
    }
  };

  const pendingStore = store?.onboarding_status && store.onboarding_status !== "approved";
  const statusBadge = !store
    ? null
    : store.onboarding_status === "approved"
    ? { label: "Active", tone: "bg-emerald-500/15 text-emerald-700" }
    : store.onboarding_status === "needs_info"
    ? { label: "À corriger", tone: "bg-amber-500/15 text-amber-800" }
    : store.onboarding_status === "rejected"
    ? { label: "Suspendue", tone: "bg-destructive/15 text-destructive" }
    : { label: "En vérification", tone: "bg-primary/15 text-primary" };

  return (
    <div className="min-h-screen bg-background pb-28">
      <header
        className="px-4 pt-4 flex items-center gap-3"
        style={{ paddingTop: "max(1rem, env(safe-area-inset-top))" }}
      >
        <button
          onClick={() => navigate(-1)}
          className="w-10 h-10 rounded-full bg-card border border-border/60 flex items-center justify-center"
          aria-label="Retour"
        >
          <ArrowLeft className="w-5 h-5 text-foreground" />
        </button>
        <div className="flex-1 min-w-0">
          <h1 className="text-lg font-extrabold text-foreground truncate">
            {store?.name ?? restaurant?.name ?? "Espace marchand"}
          </h1>
          {statusBadge && (
            <span className={`inline-block mt-0.5 text-[10px] font-semibold px-2 py-0.5 rounded-full ${statusBadge.tone}`}>
              {statusBadge.label}
            </span>
          )}
        </div>
        <MerchantModeToggle compact forceVisible />
      </header>

      {/* Always-visible mode switch banner so merchants can return to client mode at a glance */}
      <div className="px-4 mt-3">
        <div className="max-w-md mx-auto rounded-2xl border border-primary/30 bg-primary/5 px-3 py-2 flex items-center justify-between gap-3">
          <div className="min-w-0">
            <p className="text-[11px] font-semibold uppercase tracking-wide text-primary">Mode actuel</p>
            <p className="text-sm font-bold text-foreground truncate">Tableau de bord marchand</p>
          </div>
          <MerchantModeToggle compact forceVisible />
        </div>
      </div>

      {!hasAny ? (
        <MerchantActivationPanel onActivated={refresh} />
      ) : (
        <>
          {/* Sub-tab nav */}
          <nav className="sticky top-0 z-30 bg-background/95 backdrop-blur border-b border-border/40 px-2 py-2 mt-2">
            <div className="max-w-md mx-auto flex gap-1 overflow-x-auto no-scrollbar">
              {TABS.map((t) => {
                const Icon = t.icon;
                const active = tab === t.key;
                return (
                  <button
                    key={t.key}
                    onClick={() => setTab(t.key)}
                    className={`flex-1 min-w-[64px] flex flex-col items-center gap-0.5 px-2 py-1.5 rounded-xl text-[11px] font-semibold transition ${
                      active ? "bg-primary text-primary-foreground" : "text-muted-foreground hover:bg-muted/50"
                    }`}
                    aria-current={active}
                  >
                    <Icon className="w-4 h-4" />
                    {t.label}
                  </button>
                );
              })}
            </div>
          </nav>

          <main className="max-w-md mx-auto px-4 pt-4 space-y-3">
            {pendingStore && tab !== "store" && (
              <MerchantPendingBanner
                status={store!.onboarding_status!}
                reason={store!.rejection_reason ?? null}
              />
            )}

            {tab === "home" && (
              <>
                <MerchantSnapshot
                  userId={user.id}
                  store={store ?? null}
                  onGo={(t) => setTab(t)}
                />
              </>
            )}

            {tab === "orders" && (
              <>
                {store && <MerchantCommandesView merchantUserId={user.id} />}
                {restaurant && (
                  <OrdersSection restaurantId={restaurant.id} sellerId={undefined} />
                )}
              </>
            )}

            {tab === "catalog" && (
              <>
                <CatalogSection
                  restaurantId={restaurant?.id}
                  sellerId={store ? user.id : undefined}
                />
                {store && (
                  <ProductCatalogSection
                    userId={user.id}
                    storeId={store.id}
                    approved={store.onboarding_status === "approved" && store.status === "active"}
                  />
                )}
              </>
            )}

            {tab === "wallet" && (
              <>
                <MerchantWalletSection />
                {store?.service_agent_status === "approved" && <ServiceAgentCashInPanel />}
                {store?.service_agent_status === "pending" && (
                  <div className="bg-card rounded-2xl border border-border/60 p-4 text-sm">
                    <p className="font-bold text-foreground">Demande Agent CHOP Wallet en vérification</p>
                    <p className="text-xs text-muted-foreground mt-1">
                      Vous pourrez recharger des clients dès l'approbation.
                    </p>
                  </div>
                )}
                {store?.service_agent_status === "rejected" && (
                  <div className="bg-card rounded-2xl border border-destructive/40 p-4 text-sm">
                    <p className="font-bold text-destructive">Demande Agent CHOP Wallet refusée</p>
                    <p className="text-xs text-muted-foreground mt-1">
                      {store?.service_agent_notes ?? "Contactez le support pour plus d'informations."}
                    </p>
                  </div>
                )}
              </>
            )}

            {tab === "store" && (
              <>
                <MerchantIdentityStrip
                  store={store}
                  restaurant={restaurant}
                  isOpen={isOpen}
                  onToggleOpen={handleOpenToggle}
                />
                {store && (
                  <button
                    onClick={() => {
                      if (store.onboarding_status === "approved" && store.status === "active") {
                        navigate(`/marche/boutique/${store.slug}`);
                      } else {
                        toast({ title: "Boutique en vérification", description: "Votre boutique publique sera accessible après validation." });
                      }
                    }}
                    className="w-full rounded-xl border border-border/60 bg-card px-4 py-3 flex items-center justify-between gap-2 hover:bg-muted/40 transition"
                  >
                    <span className="text-sm font-semibold text-foreground">Voir ma boutique publique</span>
                    <ExternalLink className="w-4 h-4 text-muted-foreground" />
                  </button>
                )}
                <AvailabilitySection store={store} restaurant={restaurant} onChanged={refresh} />
                <DeliverySection merchantUserId={user.id} />
                <ChopPayActivitySection
                  enabled={!!(restaurant?.choppay_enabled || store?.choppay_enabled)}
                />
                {store && (
                  <MerchantVerificationChecklist store={store as Parameters<typeof MerchantVerificationChecklist>[0]["store"]} onChanged={refresh} />
                )}
              </>
            )}
          </main>
        </>
      )}
    </div>
  );
}