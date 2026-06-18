import { useEffect, useState } from "react";
import { ChevronRight, Phone, Truck, ShoppingBag, MapPin } from "lucide-react";
import { SectionCard } from "../SectionCard";
import { Button } from "@/components/ui/button";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import { toast } from "@/hooks/use-toast";
import {
  advanceRestaurantOrder,
  listRestaurantOrders,
  RESTAURANT_NEXT_LABEL,
  RESTAURANT_NEXT_STATE,
} from "@/lib/merchant/operations";
import {
  getRestaurantOrderDetail,
  RESTAURANT_MISSION_LABEL,
  RESTAURANT_STATE_LABEL,
  type FoodOrderDetail,
} from "@/lib/repas/merchantOps";
import {
  FOOD_PAYMENT_STATUS_LABEL,
  type FoodOrder,
  type FoodOrderState,
} from "@/lib/repas/types";
import { OrderMessagingPanel } from "@/components/repas/OrderMessagingPanel";
import { useAuth } from "@/contexts/AuthContext";

interface Props {
  restaurantId: string;
}

const ACTIVE_STATES: FoodOrderState[] = [
  "placed",
  "confirmed",
  "preparing",
  "ready",
  "out_for_delivery",
];

const STATE_TONE: Record<FoodOrderState, string> = {
  placed: "bg-primary/15 text-primary",
  confirmed: "bg-primary/15 text-primary",
  preparing: "bg-amber-500/15 text-amber-700",
  ready: "bg-emerald-500/15 text-emerald-700",
  out_for_delivery: "bg-emerald-500/15 text-emerald-700",
  completed: "bg-muted text-muted-foreground",
  cancelled: "bg-destructive/15 text-destructive",
};

export function RepasOrdersSection({ restaurantId }: Props) {
  const { user } = useAuth();
  const [orders, setOrders] = useState<FoodOrder[]>([]);
  const [loading, setLoading] = useState(true);
  const [openId, setOpenId] = useState<string | null>(null);
  const [detail, setDetail] = useState<FoodOrderDetail | null>(null);
  const [busy, setBusy] = useState<string | null>(null);

  const reload = async () => {
    setLoading(true);
    try {
      setOrders(await listRestaurantOrders(restaurantId, 40));
    } catch (e) {
      console.warn("[repas] orders load failed", e);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    reload();
    const t = setInterval(reload, 30_000);
    return () => clearInterval(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [restaurantId]);

  useEffect(() => {
    if (!openId) {
      setDetail(null);
      return;
    }
    let alive = true;
    (async () => {
      const d = await getRestaurantOrderDetail(openId);
      if (alive) setDetail(d);
    })();
    return () => {
      alive = false;
    };
  }, [openId]);

  const advance = async (o: FoodOrder) => {
    if (!RESTAURANT_NEXT_STATE[o.state]) return;
    setBusy(o.id);
    try {
      const next = await advanceRestaurantOrder(o.id, o.state);
      setOrders((prev) => prev.map((x) => (x.id === o.id ? { ...x, state: next } : x)));
      if (detail?.id === o.id) setDetail({ ...detail, state: next });
    } catch (e: any) {
      toast({ title: "Erreur", description: e?.message ?? "Action impossible" });
    } finally {
      setBusy(null);
    }
  };

  const active = orders.filter((o) => ACTIVE_STATES.includes(o.state));
  const done = orders.filter((o) => !ACTIVE_STATES.includes(o.state)).slice(0, 8);

  const renderCard = (o: FoodOrder) => (
    <button
      key={o.id}
      onClick={() => setOpenId(o.id)}
      className="w-full text-left rounded-xl bg-muted/40 border border-border/50 p-3 hover:bg-muted/60 transition"
    >
      <div className="flex items-center justify-between gap-2">
        <span
          className={`text-[11px] font-semibold px-2 py-0.5 rounded-full ${STATE_TONE[o.state]}`}
        >
          {RESTAURANT_STATE_LABEL[o.state]}
        </span>
        <span className="text-xs text-muted-foreground">
          {o.subtotal_gnf.toLocaleString("fr-FR")} GNF
        </span>
      </div>
      <div className="flex items-center justify-between gap-2 mt-1.5">
        <p className="text-sm text-foreground inline-flex items-center gap-1.5">
          {o.fulfillment === "delivery" ? (
            <Truck className="w-3.5 h-3.5 text-primary" />
          ) : (
            <ShoppingBag className="w-3.5 h-3.5 text-primary" />
          )}
          {o.fulfillment === "delivery" ? "Livraison" : "Retrait"}
          <span className="text-muted-foreground text-xs">
            · {new Date(o.created_at).toLocaleTimeString("fr-FR", {
              hour: "2-digit",
              minute: "2-digit",
            })}
          </span>
        </p>
        <ChevronRight className="w-4 h-4 text-muted-foreground" />
      </div>
      {RESTAURANT_NEXT_STATE[o.state] && (
        <Button
          size="sm"
          className="mt-2 w-full"
          onClick={(e) => {
            e.stopPropagation();
            advance(o);
          }}
          disabled={busy === o.id}
        >
          {RESTAURANT_NEXT_LABEL[o.state]}
        </Button>
      )}
    </button>
  );

  return (
    <>
      <SectionCard title="Commandes en cours" hint="Nouveaux, en préparation, prêts">
        {loading ? (
          <p className="text-sm text-muted-foreground">Chargement…</p>
        ) : active.length === 0 ? (
          <p className="text-sm text-muted-foreground">Aucune commande en cours.</p>
        ) : (
          <div className="space-y-2">{active.map(renderCard)}</div>
        )}
      </SectionCard>

      {done.length > 0 && (
        <SectionCard title="Récentes" hint="Dernières commandes terminées ou annulées">
          <div className="space-y-2">{done.map(renderCard)}</div>
        </SectionCard>
      )}

      <Sheet open={!!openId} onOpenChange={(o) => !o && setOpenId(null)}>
        <SheetContent side="bottom" className="max-w-md mx-auto rounded-t-3xl max-h-[90vh] overflow-y-auto">
          <SheetHeader>
            <SheetTitle>Détail de la commande</SheetTitle>
          </SheetHeader>
          {!detail ? (
            <p className="text-sm text-muted-foreground mt-4">Chargement…</p>
          ) : (
            <div className="space-y-3 mt-4">
              <div className="flex items-center justify-between">
                <span
                  className={`text-[11px] font-semibold px-2 py-0.5 rounded-full ${STATE_TONE[detail.state]}`}
                >
                  {RESTAURANT_STATE_LABEL[detail.state]}
                </span>
                <span className="text-xs text-muted-foreground">
                  {new Date(detail.created_at).toLocaleString("fr-FR")}
                </span>
              </div>

              <div className="rounded-xl bg-muted/40 border border-border/50 p-3">
                <p className="text-xs font-semibold text-muted-foreground uppercase">Client</p>
                <p className="text-sm font-medium text-foreground mt-0.5">
                  {detail.customer?.full_name ?? "Client"}
                </p>
                {detail.customer?.phone && (
                  <a
                    href={`tel:${detail.customer.phone}`}
                    className="inline-flex items-center gap-1 text-xs text-primary mt-1"
                  >
                    <Phone className="w-3 h-3" /> {detail.customer.phone}
                  </a>
                )}
              </div>

              <div className="rounded-xl bg-muted/40 border border-border/50 p-3">
                <p className="text-xs font-semibold text-muted-foreground uppercase">Articles</p>
                <ul className="mt-1.5 space-y-1">
                  {detail.items.map((i) => (
                    <li key={i.id} className="flex items-center justify-between text-sm">
                      <span className="text-foreground">
                        {i.qty}× {i.name_snapshot}
                      </span>
                      <span className="text-muted-foreground">
                        {(i.unit_price_gnf * i.qty).toLocaleString("fr-FR")} GNF
                      </span>
                    </li>
                  ))}
                </ul>
                <div className="mt-2 pt-2 border-t border-border/50 flex items-center justify-between text-sm font-semibold">
                  <span>Total</span>
                  <span>{detail.subtotal_gnf.toLocaleString("fr-FR")} GNF</span>
                </div>
                <p className="text-[11px] text-muted-foreground mt-1">
                  Paiement :{" "}
                  {detail.payment_method === "wallet"
                    ? "ChopWallet"
                    : detail.payment_method === "choppay"
                      ? "ChopPay"
                      : "Espèces"}
                  {detail.payment_status
                    ? ` · ${FOOD_PAYMENT_STATUS_LABEL[detail.payment_status]}`
                    : ""}
                </p>
              </div>

              {detail.fulfillment === "delivery" ? (
                <div className="rounded-xl bg-muted/40 border border-border/50 p-3">
                  <p className="text-xs font-semibold text-muted-foreground uppercase">Livraison</p>
                  {detail.delivery_address && (
                    <p className="text-sm text-foreground mt-1 inline-flex items-start gap-1">
                      <MapPin className="w-3.5 h-3.5 mt-0.5 text-primary shrink-0" />
                      <span>{detail.delivery_address}</span>
                    </p>
                  )}
                  {detail.mission ? (
                    <p className="text-xs text-foreground mt-2 inline-flex items-center gap-1">
                      <Truck className="w-3.5 h-3.5 text-primary" />
                      {RESTAURANT_MISSION_LABEL[detail.mission.state] ?? detail.mission.state}
                    </p>
                  ) : (
                    <p className="text-xs text-muted-foreground mt-2">
                      En attente d'un coursier.
                    </p>
                  )}
                </div>
              ) : (
                <div className="rounded-xl bg-muted/40 border border-border/50 p-3">
                  <p className="text-xs font-semibold text-muted-foreground uppercase">Retrait</p>
                  <p className="text-sm text-foreground mt-1">
                    Le client viendra chercher la commande sur place.
                  </p>
                </div>
              )}

              {detail.notes && (
                <div className="rounded-xl bg-muted/40 border border-border/50 p-3">
                  <p className="text-xs font-semibold text-muted-foreground uppercase">Note</p>
                  <p className="text-sm text-foreground mt-1">{detail.notes}</p>
                </div>
              )}

              <OrderMessagingPanel
                foodOrderId={detail.id}
                threadType="restaurant_client_order"
                senderRole="restaurant"
                selfUserId={user?.id ?? null}
                title="Conversation client"
              />

              {detail.fulfillment === "delivery" && (
                detail.mission?.courier_id ? (
                  <OrderMessagingPanel
                    foodOrderId={detail.id}
                    threadType="restaurant_courier_order"
                    senderRole="restaurant"
                    selfUserId={user?.id ?? null}
                    title="Conversation coursier"
                    manualOpen
                  />
                ) : (
                  <div className="rounded-xl border border-border/60 bg-muted/30 p-3 text-xs text-muted-foreground">
                    Coursier non assigné — la conversation s'ouvrira dès l'assignation.
                  </div>
                )
              )}

              {RESTAURANT_NEXT_STATE[detail.state] && (
                <Button
                  className="w-full"
                  disabled={busy === detail.id}
                  onClick={() => advance(detail)}
                >
                  {RESTAURANT_NEXT_LABEL[detail.state]}
                </Button>
              )}
            </div>
          )}
        </SheetContent>
      </Sheet>
    </>
  );
}