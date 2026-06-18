import { motion } from "framer-motion";
import { Store, MapPin, BadgeCheck, Navigation } from "lucide-react";
import type { MerchantStore } from "@/lib/marche/stores";
import { categoryLabel } from "@/lib/marche";
import { formatDistance } from "@/lib/maps/geo";

export function StoreCard({
  store,
  listingCount,
  samplePhotos,
  distanceMeters,
  locationTrust,
  onClick,
}: {
  store: MerchantStore;
  listingCount?: number;
  samplePhotos?: string[];
  /** Computed haversine distance in meters, or null if unknown. */
  distanceMeters?: number | null;
  /** "verified" if coordinates come from a trusted/verified source; otherwise treat as à confirmer. */
  locationTrust?: "verified" | "unverified" | "missing";
  onClick: () => void;
}) {
  const trust = locationTrust ?? (store.latitude != null && store.longitude != null ? "unverified" : "missing");
  const distanceLabel =
    typeof distanceMeters === "number" && Number.isFinite(distanceMeters)
      ? formatDistance(distanceMeters)
      : trust === "missing"
        ? "Distance à confirmer"
        : null;
  return (
    <motion.button
      whileTap={{ scale: 0.98 }}
      onClick={onClick}
      className="text-left bg-card rounded-2xl shadow-card hover:shadow-elevated transition-shadow p-3 w-full"
    >
      <div className="flex items-center gap-3">
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
        <div className="flex items-center gap-2 text-[11px] text-muted-foreground mt-0.5 flex-wrap">
          {store.category && (
            <span className="inline-flex items-center px-1.5 py-0.5 rounded-full bg-muted text-foreground/80">
              {categoryLabel(store.category)}
            </span>
          )}
          {store.district && (
            <span className="inline-flex items-center gap-0.5">
              <MapPin className="w-3 h-3" /> {store.district}
            </span>
          )}
          {typeof listingCount === "number" && (
            <span>{listingCount} annonce{listingCount > 1 ? "s" : ""}</span>
          )}
          {distanceLabel && (
            <span className="inline-flex items-center gap-0.5">
              <Navigation className="w-3 h-3" /> {distanceLabel}
            </span>
          )}
          {trust === "unverified" && distanceLabel && distanceLabel !== "Distance à confirmer" && (
            <span className="text-[10px] italic text-muted-foreground/80">à confirmer</span>
          )}
        </div>
      </div>
      {store.choppay_enabled && (
        <span className="chip-status chip-ok text-[10px] shrink-0">ChopPay</span>
      )}
      </div>
      {samplePhotos && samplePhotos.length > 0 && (
        <div className="grid grid-cols-3 gap-1 mt-2.5">
          {samplePhotos.slice(0, 3).map((src, i) => (
            <div key={i} className="aspect-square rounded-lg overflow-hidden bg-muted">
              <img
                src={src}
                alt=""
                loading="lazy"
                onError={(e) => {
                  (e.currentTarget as HTMLImageElement).style.display = "none";
                }}
                className="w-full h-full object-cover"
              />
            </div>
          ))}
        </div>
      )}
    </motion.button>
  );
}