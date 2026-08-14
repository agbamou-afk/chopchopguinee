import { motion } from "framer-motion";
import { Clock, MapPin, UtensilsCrossed, Truck, Package, ShieldCheck } from "lucide-react";
import { cn } from "@/lib/utils";
import {
  repasAvailabilityLabel,
  type RepasDiscoveryRestaurant,
} from "@/lib/repas/discovery";

interface RestaurantCardProps {
  restaurant: RepasDiscoveryRestaurant;
  onClick?: () => void;
}

/**
 * R8 — a discovery card shows only server truth. No invented rating,
 * ETA or distance: those dimensions do not exist in the read model.
 */
export function RestaurantCard({ restaurant: r, onClick }: RestaurantCardProps) {
  const image = r.cover_url || r.avatar_url;
  return (
    <motion.button
      whileHover={{ scale: 1.02 }}
      whileTap={{ scale: 0.98 }}
      onClick={onClick}
      className="w-full bg-card rounded-2xl overflow-hidden shadow-card hover:shadow-elevated transition-shadow text-left"
    >
      <div className="relative h-32 bg-muted">
        {image ? (
          <img
            src={image}
            alt={r.name}
            loading="lazy"
            decoding="async"
            className="w-full h-full object-cover"
          />
        ) : (
          <div className="w-full h-full flex items-center justify-center">
            <UtensilsCrossed className="w-6 h-6 text-muted-foreground" />
          </div>
        )}
        <span
          className={cn(
            "absolute top-2 right-2 px-2 py-1 rounded-full text-[10px] font-semibold backdrop-blur-sm",
            r.orderable_now
              ? "bg-primary text-primary-foreground"
              : "bg-card/90 text-muted-foreground",
          )}
        >
          {repasAvailabilityLabel(r)}
        </span>
      </div>
      <div className="p-3">
        <h3 className="font-semibold text-foreground text-sm truncate">{r.name}</h3>
        <p className="text-xs text-muted-foreground truncate">
          {r.cuisine ?? "Cuisine locale"}
        </p>
        <div className="flex items-center gap-3 text-[11px] text-muted-foreground mt-2">
          <span className="flex items-center gap-1">
            <Clock className="w-3 h-3" />~{r.prep_time_min} min
          </span>
          {r.district && (
            <span className="flex items-center gap-1 truncate">
              <MapPin className="w-3 h-3 shrink-0" />
              <span className="truncate">{r.district}</span>
            </span>
          )}
        </div>
        <div className="flex items-center gap-1.5 mt-2 text-[10px] text-muted-foreground">
          {r.delivery_ready && (
            <span className="inline-flex items-center gap-1">
              <Truck className="w-3 h-3" />
              Livraison
            </span>
          )}
          {r.pickup_ready && (
            <span className="inline-flex items-center gap-1">
              <Package className="w-3 h-3" />
              Retrait
            </span>
          )}
          {r.choppay_enabled && (
            <span className="inline-flex items-center gap-1 text-primary">
              <ShieldCheck className="w-3 h-3" />
              Chop Pay
            </span>
          )}
        </div>
      </div>
    </motion.button>
  );
}
