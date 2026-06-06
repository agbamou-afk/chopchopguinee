import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { ArrowLeft } from "lucide-react";
import { useMerchantIdentity } from "@/hooks/useMerchantIdentity";
import { useAuth } from "@/contexts/AuthContext";
import { MerchantIdentityStrip } from "./MerchantIdentityStrip";
import { OrdersSection } from "./OrdersSection";
import { AvailabilitySection } from "./AvailabilitySection";
import { CatalogSection } from "./CatalogSection";
import { DeliverySection } from "./DeliverySection";
import { ChopPayActivitySection } from "./ChopPayActivitySection";
import { AnalyticsStrip } from "./AnalyticsStrip";
import { setRestaurantOpen, setStoreOpen } from "@/lib/merchant/operations";
import { toast } from "@/hooks/use-toast";
import { MerchantActivationPanel } from "./MerchantActivationPanel";
import { MerchantPendingBanner } from "./MerchantPendingBanner";
import { MerchantModeToggle } from "./ModeToggle";

export function MerchantHub() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const { loading, store, restaurant, hasAny, refresh } = useMerchantIdentity();
  const [isOpen, setIsOpen] = useState(false);

  useEffect(() => {
    setIsOpen(restaurant ? !!restaurant.is_open : store ? store.status === "active" : false);
  }, [restaurant, store]);

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
    } catch (e: any) {
      setIsOpen(!next);
      toast({ title: "Erreur", description: e?.message ?? "Action impossible" });
    }
  };

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
        <h1 className="text-lg font-extrabold text-foreground">Espace marchand</h1>
        <div className="ml-auto">
          <MerchantModeToggle compact />
        </div>
      </header>

      {!hasAny ? (
        <MerchantActivationPanel onActivated={refresh} />
      ) : (
      <main className="max-w-md mx-auto px-4 pt-4 space-y-3">
        {store?.onboarding_status && store.onboarding_status !== "approved" && (
          <MerchantPendingBanner
            status={store.onboarding_status}
            reason={store.rejection_reason ?? null}
          />
        )}
        <MerchantIdentityStrip
          store={store}
          restaurant={restaurant}
          isOpen={isOpen}
          onToggleOpen={handleOpenToggle}
        />
        <OrdersSection
          restaurantId={restaurant?.id}
          sellerId={store ? user.id : undefined}
        />
        <AvailabilitySection store={store} restaurant={restaurant} onChanged={refresh} />
        <CatalogSection
          restaurantId={restaurant?.id}
          sellerId={store ? user.id : undefined}
        />
        <DeliverySection merchantUserId={user.id} />
        <ChopPayActivitySection
          enabled={!!(restaurant?.choppay_enabled || store?.choppay_enabled)}
        />
        <AnalyticsStrip
          restaurantId={restaurant?.id}
          sellerId={store ? user.id : undefined}
        />
      </main>
      )}
    </div>
  );
}