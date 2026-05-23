import { motion } from "framer-motion";
import { Store, MapPin, BadgeCheck } from "lucide-react";
import type { MerchantStore } from "@/lib/marche/stores";

export function StoreCard({
  store,
  listingCount,
  onClick,
}: {
  store: MerchantStore;
  listingCount?: number;
  onClick: () => void;
}) {
  return (
    <motion.button
      whileTap={{ scale: 0.98 }}
      onClick={onClick}
      className="text-left bg-card rounded-2xl shadow-card hover:shadow-elevated transition-shadow p-3 flex items-center gap-3 w-full"
    >
      <div className="w-12 h-12 rounded-xl bg-muted overflow-hidden shrink-0 flex items-center justify-center">
        {store.avatar_url ? (
          <img src={store.avatar_url} alt="" className="w-full h-full object-cover" loading="lazy" />
        ) : (
          <Store className="w-5 h-5 text-muted-foreground" />
        )}
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-1.5">
          <p className="text-sm font-semibold text-foreground truncate">{store.name}</p>
          {store.verification_state === "verified" && (
            <BadgeCheck className="w-3.5 h-3.5 text-primary shrink-0" />
          )}
        </div>
        <div className="flex items-center gap-2 text-[11px] text-muted-foreground mt-0.5">
          {store.district && (
            <span className="inline-flex items-center gap-0.5">
              <MapPin className="w-3 h-3" /> {store.district}
            </span>
          )}
          {typeof listingCount === "number" && (
            <span>{listingCount} annonce{listingCount > 1 ? "s" : ""}</span>
          )}
        </div>
      </div>
      {store.choppay_enabled && (
        <span className="chip-status chip-ok text-[10px] shrink-0">ChopPay</span>
      )}
    </motion.button>
  );
}