import { useEffect, useState } from "react";
import { SectionCard } from "./SectionCard";
import { Button } from "@/components/ui/button";
import { toast } from "@/hooks/use-toast";
import { FOOD_ORDER_STATE_LABEL, type FoodOrder, type FoodOrderState } from "@/lib/repas/types";
import {
  advanceRestaurantOrder,
  listRestaurantOrders,
  listSellerInterests,
  respondToInterest,
  RESTAURANT_NEXT_LABEL,
  RESTAURANT_NEXT_STATE,
} from "@/lib/merchant/operations";

interface Props {
  restaurantId?: string;
  sellerId?: string;
}

export function OrdersSection({ restaurantId, sellerId }: Props) {
  const [orders, setOrders] = useState<FoodOrder[]>([]);
  const [interests, setInterests] = useState<any[]>([]);
  const [busy, setBusy] = useState<string | null>(null);

  const load = async () => {
    if (restaurantId) setOrders(await listRestaurantOrders(restaurantId));
    if (sellerId) setInterests(await listSellerInterests(sellerId));
  };

  useEffect(() => {
    load().catch(() => { /* calm */ });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [restaurantId, sellerId]);

  const advance = async (o: FoodOrder) => {
    if (!RESTAURANT_NEXT_STATE[o.state]) return;
    setBusy(o.id);
    try {
      const next = await advanceRestaurantOrder(o.id, o.state);
      setOrders((prev) => prev.map((x) => (x.id === o.id ? { ...x, state: next } : x)));
    } catch (e: any) {
      toast({ title: "Erreur", description: e?.message ?? "Action impossible" });
    } finally {
      setBusy(null);
    }
  };

  const respond = async (id: string, state: "accepted" | "declined" | "fulfilled") => {
    setBusy(id);
    try {
      await respondToInterest(id, state);
      setInterests((prev) => prev.map((x) => (x.id === id ? { ...x, state } : x)));
    } catch (e: any) {
      toast({ title: "Erreur", description: e?.message ?? "Action impossible" });
    } finally {
      setBusy(null);
    }
  };

  const repas = restaurantId ? orders.filter((o) => o.state !== "completed" && o.state !== "cancelled") : [];
  const marche = sellerId ? interests.filter((i) => i.state === "pending" || i.state === "accepted") : [];

  return (
    <SectionCard title="Commandes" hint="En cours et en attente">
      {repas.length === 0 && marche.length === 0 && (
        <p className="text-sm text-muted-foreground">Aucune commande en cours.</p>
      )}

      {repas.length > 0 && (
        <div className="space-y-2">
          {repas.map((o) => (
            <div key={o.id} className="rounded-xl bg-muted/40 border border-border/50 p-3">
              <div className="flex items-center justify-between gap-2">
                <span className="text-xs font-semibold text-primary">
                  {FOOD_ORDER_STATE_LABEL[o.state]}
                </span>
                <span className="text-xs text-muted-foreground">
                  {o.subtotal_gnf.toLocaleString("fr-FR")} GNF
                </span>
              </div>
              <p className="text-sm text-foreground mt-1">
                {o.fulfillment === "delivery" ? "Livraison" : "Retrait"}
                {o.notes ? ` · ${o.notes}` : ""}
              </p>
              {RESTAURANT_NEXT_STATE[o.state] && (
                <Button
                  size="sm"
                  className="mt-2 w-full"
                  onClick={() => advance(o)}
                  disabled={busy === o.id}
                >
                  {RESTAURANT_NEXT_LABEL[o.state]}
                </Button>
              )}
            </div>
          ))}
        </div>
      )}

      {marche.length > 0 && (
        <div className="space-y-2 mt-2">
          {marche.map((i) => (
            <div key={i.id} className="rounded-xl bg-muted/40 border border-border/50 p-3">
              <div className="flex items-center justify-between gap-2">
                <span className="text-xs font-semibold text-primary capitalize">
                  {i.kind === "delivery" ? "Demande livraison" : i.kind === "reservation" ? "Réservation" : "Demande"}
                </span>
                <span className="text-xs text-muted-foreground capitalize">{i.state}</span>
              </div>
              <p className="text-sm text-foreground mt-1 truncate">
                {i.marketplace_listings?.title ?? "Annonce"}
              </p>
              {i.note && <p className="text-xs text-muted-foreground mt-1">{i.note}</p>}
              {i.state === "pending" && (
                <div className="flex gap-2 mt-2">
                  <Button size="sm" className="flex-1" onClick={() => respond(i.id, "accepted")} disabled={busy === i.id}>
                    Accepter
                  </Button>
                  <Button size="sm" variant="outline" className="flex-1" onClick={() => respond(i.id, "declined")} disabled={busy === i.id}>
                    Refuser
                  </Button>
                </div>
              )}
              {i.state === "accepted" && (
                <Button size="sm" variant="outline" className="mt-2 w-full" onClick={() => respond(i.id, "fulfilled")} disabled={busy === i.id}>
                  Marquer terminé
                </Button>
              )}
            </div>
          ))}
        </div>
      )}
    </SectionCard>
  );
}