import { Store, UtensilsCrossed, ShieldCheck } from "lucide-react";
import { Switch } from "@/components/ui/switch";
import { motion } from "framer-motion";
import type { MerchantStore } from "@/hooks/useMerchantIdentity";
import type { FoodRestaurant } from "@/lib/repas/types";

interface Props {
  store: MerchantStore | null;
  restaurant: FoodRestaurant | null;
  isOpen: boolean;
  onToggleOpen: (next: boolean) => void;
}

export function MerchantIdentityStrip({ store, restaurant, isOpen, onToggleOpen }: Props) {
  const name = restaurant?.name ?? store?.name ?? "Mon commerce";
  const Icon = restaurant ? UtensilsCrossed : Store;
  const typeLabel = restaurant && store
    ? "Repas · Marché"
    : restaurant
      ? "Repas"
      : "Marché";
  const verified =
    (restaurant?.verification_state && restaurant.verification_state !== "none") ||
    (store?.verification_state && store.verification_state !== "none");

  return (
    <motion.div
      initial={{ opacity: 0, y: -8 }}
      animate={{ opacity: 1, y: 0 }}
      className="bg-card rounded-2xl shadow-soft border border-border/60 p-4 flex items-center gap-3"
    >
      <div className="w-14 h-14 rounded-2xl bg-primary/10 flex items-center justify-center shrink-0">
        <Icon className="w-7 h-7 text-primary" />
      </div>
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-1.5">
          <h2 className="text-base font-extrabold text-foreground truncate">{name}</h2>
          {verified && <ShieldCheck className="w-4 h-4 text-primary shrink-0" />}
        </div>
        <p className="text-xs text-muted-foreground truncate">{typeLabel}</p>
      </div>
      <div className="flex flex-col items-end gap-1">
        <span className="text-xs font-semibold text-muted-foreground">{isOpen ? "Ouvert" : "Fermé"}</span>
        <Switch checked={isOpen} onCheckedChange={onToggleOpen} />
      </div>
    </motion.div>
  );
}