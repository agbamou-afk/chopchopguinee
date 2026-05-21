import { Switch } from "@/components/ui/switch";
import { SectionCard } from "./SectionCard";
import { toast } from "@/hooks/use-toast";
import {
  setRestaurantFulfillment,
  setStoreDelivery,
} from "@/lib/merchant/operations";
import type { MerchantStore } from "@/hooks/useMerchantIdentity";
import type { FoodRestaurant } from "@/lib/repas/types";
import { useState } from "react";

interface Props {
  store: MerchantStore | null;
  restaurant: FoodRestaurant | null;
  onChanged: () => Promise<void> | void;
}

function Row({ label, hint, checked, onChange }: { label: string; hint?: string; checked: boolean; onChange: (b: boolean) => void }) {
  return (
    <div className="flex items-center justify-between gap-3 py-2">
      <div className="min-w-0">
        <p className="text-sm font-semibold text-foreground">{label}</p>
        {hint && <p className="text-xs text-muted-foreground">{hint}</p>}
      </div>
      <Switch checked={checked} onCheckedChange={onChange} />
    </div>
  );
}

export function AvailabilitySection({ store, restaurant, onChanged }: Props) {
  const [delivery, setDelivery] = useState(restaurant?.delivery_available ?? store?.delivery_available ?? false);
  const [pickup, setPickup] = useState(restaurant?.pickup_available ?? true);

  const updateDelivery = async (v: boolean) => {
    setDelivery(v);
    try {
      if (restaurant) await setRestaurantFulfillment(restaurant.id, { delivery_available: v });
      if (store) await setStoreDelivery(store.id, v);
      await onChanged();
    } catch (e: any) {
      setDelivery(!v);
      toast({ title: "Erreur", description: e?.message ?? "Action impossible" });
    }
  };

  const updatePickup = async (v: boolean) => {
    if (!restaurant) return;
    setPickup(v);
    try {
      await setRestaurantFulfillment(restaurant.id, { pickup_available: v });
      await onChanged();
    } catch (e: any) {
      setPickup(!v);
      toast({ title: "Erreur", description: e?.message ?? "Action impossible" });
    }
  };

  return (
    <SectionCard title="Disponibilité" hint="Contrôle rapide des options">
      <Row
        label="Livraison WONGO"
        hint="Les coursiers reçoivent vos missions"
        checked={delivery}
        onChange={updateDelivery}
      />
      {restaurant && (
        <Row
          label="Retrait sur place"
          hint="Les clients peuvent venir retirer"
          checked={pickup}
          onChange={updatePickup}
        />
      )}
    </SectionCard>
  );
}