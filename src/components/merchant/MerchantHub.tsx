import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { ArrowLeft, Home, ShoppingBag, Package, Wallet as WalletIcon, Store as StoreIcon, UtensilsCrossed } from "lucide-react";
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
import { RepasMenuSection } from "./repas/RepasMenuSection";
import { RepasOrdersSection } from "./repas/RepasOrdersSection";
import { RepasProfileSection } from "./repas/RepasProfileSection";
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
import { MerchantLocationCard } from "./MerchantLocationCard";
import { RestaurantOnboardingSheet } from "@/components/food/RestaurantOnboardingSheet";
import { ChefHat } from "lucide-react";
import { createOrUpdateRestaurant } from "@/lib/repas/restaurants";

type Tab = "home" | "orders" | "catalog" | "wallet" | "store";
type TabSpec = { key: Tab; label: string; icon: typeof Home };

const MARCHE_TABS: TabSpec[] = [
  { key: "home", label: "Accueil", icon: Home },
  { key: "orders", label: "Commandes", icon: ShoppingBag },
  { key: "catalog", label: "Catalogue", icon: Package },
  { key: "wallet", label: "Wallet", icon: WalletIcon },
  { key: "store", label: "Boutique", icon: StoreIcon },
];

const REPAS_TABS: TabSpec[] = [
  { key: "home", label: "Accueil", icon: Home },
  { key: "orders", label: "Commandes", icon: ShoppingBag },
  { key: "catalog", label: "Menu", icon: UtensilsCrossed },
  { key: "wallet", label: "Wallet", icon: WalletIcon },
  { key: "store", label: "Restaurant", icon: ChefHat },
];

export function MerchantHub() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const { loading, store, restaurant, hasAny, refresh } = useMerchantIdentity();
  const [isOpen, setIsOpen] = useState(false);
  const [tab, setTab] = useState<Tab>("home");
  const [createRepasOpen, setCreateRepasOpen] = useState(false);

  // Repas-only operator: dashboard surfaces are restaurant-native, not
  // product-marketplace. Mixed (store + restaurant) keeps the Marché tab
  // labels and surfaces Repas sections alongside product ones.
  const isRepasOnly = !!restaurant && !store;
  const tabs = isRepasOnly ? REPAS_TABS : MARCHE_TABS;

  // Backfill for legacy Repas-only signups: when the user opted into Repas
  // (`wants_food`) but no `food_restaurants` row exists yet — typically
  // because they signed up before the Repas dashboard split — provision one
  // from the store's name/district so they immediately land on the Repas
  // tabs. Idempotent; runs once after identity loads.
  useEffect(() => {
    if (!user?.id || loading) return;
    if (restaurant) return;
    if (!store?.wants_food) return;
    let cancelled = false;
    (async () => {
      try {
        await createOrUpdateRestaurant({
          ownerUserId: user.id,
          name: store.name,
          district: store.district ?? null,
          delivery_available: !!store.delivery_available,
          pickup_available: true,
        });
        if (!cancelled) await refresh();
      } catch (e) {
        if (import.meta.env.DEV) console.warn("[merchant-hub] repas backfill failed", e);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [user?.id, loading, restaurant, store?.id, store?.wants_food]);

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
            {restaurant?.name ?? store?.name ?? "Espace marchand"}
          </h1>
          {statusBadge && (
            <span className={`inline-block mt-0.5 text-[10px] font-semibold px-2 py-0.5 rounded-full ${statusBadge.tone}`}>
              {statusBadge.label}
            </span>
          )}
          {isRepasOnly && !statusBadge && (
            <span className="inline-block mt-0.5 text-[10px] font-semibold px-2 py-0.5 rounded-full bg-amber-500/15 text-amber-800">
              Restaurant Repas
            </span>
          )}
        </div>
      </header>

      {/* Always-visible mode switch banner so merchants can return to client mode at a glance */}
      <div className="px-4 mt-3">
        <div className="max-w-md mx-auto rounded-2xl border border-primary/30 bg-primary/5 px-3 py-2 flex items-center justify-between gap-3">
          <div className="min-w-0">
            <p className="text-[11px] font-semibold uppercase tracking-wide text-primary">Mode actuel</p>
            <p className="text-sm font-bold text-foreground truncate">
              {isRepasOnly ? "Tableau de bord restaurant" : "Tableau de bord marchand"}
            </p>
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
              {tabs.map((t) => {
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

            {tab === "home" && !isRepasOnly && (
              <>
                <MerchantSnapshot
                  userId={user.id}
                  store={store ?? null}
                  onGo={(t) => setTab(t)}
                />
              </>
            )}

            {tab === "home" && isRepasOnly && restaurant && (
              <div className="space-y-3">
                <div className="rounded-2xl border border-border/60 bg-card p-4">
                  <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Statut</p>
                  <p className="text-sm font-bold text-foreground mt-1">
                    {isOpen ? "Restaurant ouvert" : "Restaurant fermé"}
                  </p>
                  <p className="text-[11px] text-muted-foreground mt-1">
                    {restaurant.district ? `${restaurant.district} · ` : ""}
                    {restaurant.cuisine ?? "Cuisine non précisée"}
                  </p>
                </div>
                <div className="grid grid-cols-2 gap-2">
                  <button
                    onClick={() => setTab("orders")}
                    className="rounded-2xl border border-border/60 bg-card p-4 text-left hover:bg-muted/40"
                  >
                    <ShoppingBag className="w-5 h-5 text-primary mb-2" />
                    <p className="text-sm font-bold text-foreground">Commandes</p>
                    <p className="text-[11px] text-muted-foreground">Voir et préparer</p>
                  </button>
                  <button
                    onClick={() => setTab("catalog")}
                    className="rounded-2xl border border-border/60 bg-card p-4 text-left hover:bg-muted/40"
                  >
                    <UtensilsCrossed className="w-5 h-5 text-primary mb-2" />
                    <p className="text-sm font-bold text-foreground">Menu</p>
                    <p className="text-[11px] text-muted-foreground">Plats et boissons</p>
                  </button>
                </div>
              </div>
            )}

            {tab === "orders" && (
              <>
                {store && <MerchantCommandesView merchantUserId={user.id} />}
                {restaurant && (
                  <RepasOrdersSection restaurantId={restaurant.id} />
                )}
              </>
            )}

            {tab === "catalog" && (
              <>
                {restaurant && (
                  <RepasMenuSection
                    restaurantId={restaurant.id}
                    ownerUserId={user.id}
                  />
                )}
                {store && !restaurant && (
                  <CatalogSection sellerId={user.id} />
                )}
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
                {restaurant && (
                  <RepasProfileSection
                    restaurant={restaurant}
                    ownerUserId={user.id}
                    onChanged={refresh}
                  />
                )}
                {!restaurant && (
                  <div className="rounded-2xl border border-dashed border-primary/40 bg-primary/5 p-4">
                    <div className="flex items-start gap-3">
                      <div className="w-10 h-10 rounded-full bg-primary/15 flex items-center justify-center shrink-0">
                        <ChefHat className="w-5 h-5 text-primary" />
                      </div>
                      <div className="min-w-0">
                        <p className="text-sm font-bold text-foreground">Vous proposez des repas ?</p>
                        <p className="text-xs text-muted-foreground mt-0.5">
                          Créez votre restaurant Repas pour activer le menu, recevoir des commandes et discuter avec vos clients.
                        </p>
                        <button
                          onClick={() => setCreateRepasOpen(true)}
                          className="mt-2 inline-flex items-center gap-1.5 rounded-xl bg-primary text-primary-foreground text-xs font-semibold px-3 py-2"
                        >
                          Créer mon restaurant
                        </button>
                      </div>
                    </div>
                  </div>
                )}
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
                {store && (
                  <MerchantLocationCard store={store as any} onChanged={refresh} />
                )}
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
      <RestaurantOnboardingSheet
        open={createRepasOpen}
        onOpenChange={setCreateRepasOpen}
        onCreated={() => {
          refresh();
          setTab("store");
        }}
      />
    </div>
  );
}