import { useCallback, useEffect, useState } from "react";
import { ArrowLeft, PackageCheck, Star } from "lucide-react";
import { Button } from "@/components/ui/button";
import { LoadingState } from "@/components/ui/LoadingState";
import { formatGNF } from "@/lib/marche";
import { listMyMarcheOrders, orderDisplayTotalGnf, type MarcheOrder } from "@/lib/marche/orders";
import { fulfillmentStateLabel } from "@/lib/marche/fulfillment";
import { RatingSheet } from "./RatingSheet";

/**
 * Node 4 R9 — buyer view of their own Marché orders.
 * The only writable action here is rating, and only the server decides
 * whether an order is rateable.
 */
export function MarcheMyOrdersView({ onBack }: { onBack: () => void }) {
  const [orders, setOrders] = useState<MarcheOrder[]>([]);
  const [loading, setLoading] = useState(true);
  const [ratingOrderId, setRatingOrderId] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      setOrders(await listMyMarcheOrders(50, 0));
    } catch {
      setOrders([]);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <div className="max-w-md mx-auto min-h-screen bg-background pb-32">
      <header className="flex items-center gap-3 p-4 border-b sticky top-0 bg-background z-10">
        <button onClick={onBack} className="p-2 -ml-2 rounded-full hover:bg-muted" aria-label="Retour">
          <ArrowLeft className="w-5 h-5" />
        </button>
        <h1 className="font-semibold">Mes commandes Marché</h1>
      </header>

      {loading ? (
        <LoadingState />
      ) : orders.length === 0 ? (
        <div className="p-8 text-center text-muted-foreground">
          <PackageCheck className="w-10 h-10 mx-auto mb-2 opacity-50" />
          Aucune commande pour le moment.
        </div>
      ) : (
        <ul className="p-4 space-y-3">
          {orders.map((o) => (
            <li key={o.id} className="rounded-2xl border border-border/60 bg-card p-3 space-y-2">
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0">
                  <p className="text-sm font-semibold truncate">
                    {o.items[0]?.title ?? "Commande"}
                    {o.line_count > 1 ? ` +${o.line_count - 1}` : ""}
                  </p>
                  <p className="text-[11px] text-muted-foreground">
                    {new Date(o.created_at).toLocaleDateString("fr-FR")} ·{" "}
                    {fulfillmentStateLabel(o.fulfillment_state)}
                  </p>
                </div>
                <span className="text-sm font-bold shrink-0">{formatGNF(orderDisplayTotalGnf(o))}</span>
              </div>

              {o.fulfillment_state === "delivered" && (
                <Button
                  size="sm"
                  variant="outline"
                  className="w-full"
                  onClick={() => setRatingOrderId(o.id)}
                >
                  <Star className="w-3.5 h-3.5 mr-1" /> Noter cette commande
                </Button>
              )}
            </li>
          ))}
        </ul>
      )}

      {ratingOrderId && (
        <RatingSheet
          open
          onOpenChange={(v) => !v && setRatingOrderId(null)}
          transactionKind="merchant_order"
          transactionId={ratingOrderId}
        />
      )}
    </div>
  );
}