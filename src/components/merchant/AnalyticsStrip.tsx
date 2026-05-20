import { useEffect, useState } from "react";
import { SectionCard } from "./SectionCard";
import { Eye, Heart, Package, TrendingUp, ShoppingBag, MessageSquare } from "lucide-react";
import { getRestaurantAnalytics, getSellerAnalytics } from "@/lib/merchant/operations";

interface Props {
  sellerId?: string;
  restaurantId?: string;
}

function Stat({ icon: Icon, label, value }: { icon: any; label: string; value: string | number }) {
  return (
    <div className="flex items-center gap-2 rounded-xl bg-muted/40 border border-border/50 p-3 min-w-0">
      <Icon className="w-4 h-4 text-primary shrink-0" />
      <div className="min-w-0">
        <p className="text-xs text-muted-foreground truncate">{label}</p>
        <p className="text-sm font-bold text-foreground truncate">{value}</p>
      </div>
    </div>
  );
}

export function AnalyticsStrip({ sellerId, restaurantId }: Props) {
  const [seller, setSeller] = useState<any>(null);
  const [resto, setResto] = useState<any>(null);

  useEffect(() => {
    if (sellerId) getSellerAnalytics(sellerId).then(setSeller).catch(() => { /* calm */ });
    if (restaurantId) getRestaurantAnalytics(restaurantId).then(setResto).catch(() => { /* calm */ });
  }, [sellerId, restaurantId]);

  return (
    <SectionCard title="Activité" hint="Aperçu rapide">
      <div className="grid grid-cols-2 gap-2">
        {sellerId && seller && (
          <>
            <Stat icon={Eye} label="Vues" value={seller.views ?? 0} />
            <Stat icon={Heart} label="Sauvegardes" value={seller.saves ?? 0} />
            <Stat icon={MessageSquare} label="Messages" value={seller.messages ?? 0} />
            <Stat icon={Package} label="Annonces" value={seller.listings ?? 0} />
          </>
        )}
        {restaurantId && resto && (
          <>
            <Stat icon={ShoppingBag} label="Commandes 7j" value={resto.orders7d ?? 0} />
            <Stat icon={Package} label="Terminées" value={resto.completed7d ?? 0} />
            <Stat
              icon={TrendingUp}
              label="Revenus 7j"
              value={`${Number(resto.revenue7d ?? 0).toLocaleString("fr-FR")} GNF`}
            />
          </>
        )}
      </div>
    </SectionCard>
  );
}