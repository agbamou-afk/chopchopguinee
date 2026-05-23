import { ArrowLeft, BadgeCheck, MapPin, Store, Truck } from "lucide-react";
import type { MerchantStore } from "@/lib/marche/stores";

export function StoreHeader({
  store,
  listingCount,
  onBack,
  action,
}: {
  store: MerchantStore;
  listingCount: number;
  onBack: () => void;
  action?: React.ReactNode;
}) {
  return (
    <div className="relative">
      <div className="h-28 bg-muted overflow-hidden">
        {store.cover_url && (
          <img src={store.cover_url} alt="" className="w-full h-full object-cover" loading="lazy" />
        )}
      </div>
      <button
        onClick={onBack}
        aria-label="Retour"
        className="absolute top-3 left-3 w-9 h-9 rounded-full bg-background/85 backdrop-blur flex items-center justify-center shadow-card"
      >
        <ArrowLeft className="w-4 h-4" />
      </button>
      <div className="px-4 -mt-8">
        <div className="flex items-end gap-3">
          <div className="w-16 h-16 rounded-2xl bg-card shadow-card overflow-hidden flex items-center justify-center border border-border">
            {store.avatar_url ? (
              <img src={store.avatar_url} alt="" className="w-full h-full object-cover" />
            ) : (
              <Store className="w-6 h-6 text-muted-foreground" />
            )}
          </div>
          <div className="flex-1 min-w-0 pb-1">
            <div className="flex items-center gap-1.5">
              <h1 className="text-base font-bold text-foreground truncate">{store.name}</h1>
              {store.verification_state === "verified" && (
                <BadgeCheck className="w-4 h-4 text-primary" />
              )}
            </div>
            <div className="flex flex-wrap items-center gap-2 text-[11px] text-muted-foreground mt-0.5">
              {store.district && (
                <span className="inline-flex items-center gap-0.5">
                  <MapPin className="w-3 h-3" /> {store.district}
                </span>
              )}
              <span>{listingCount} annonce{listingCount > 1 ? "s" : ""}</span>
              {store.delivery_available && (
                <span className="inline-flex items-center gap-0.5">
                  <Truck className="w-3 h-3" /> Livraison
                </span>
              )}
            </div>
          </div>
        </div>
        {store.bio && (
          <p className="text-xs text-muted-foreground mt-3 leading-relaxed">{store.bio}</p>
        )}
        <div className="flex flex-wrap gap-2 mt-3">
          {store.choppay_enabled && (
            <span className="chip-status chip-ok text-[10px]">ChopPay accepté</span>
          )}
          {store.verification_state === "verified" && (
            <span className="chip-status chip-info text-[10px]">Vérifié</span>
          )}
        </div>
        {action && <div className="mt-3">{action}</div>}
      </div>
    </div>
  );
}