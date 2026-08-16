import { useMemo, useRef, useState } from "react";
import { Loader2, ShoppingBag, Minus, Plus, CheckCircle2 } from "lucide-react";
import { Sheet, SheetContent, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { toast } from "@/hooks/use-toast";
import { formatGNF } from "@/lib/marche";
import { commitMarcheOrder, orderDisplayTotalGnf, type MarcheOrder } from "@/lib/marche/orders";
import { createOrderRequestIdStore, type OrderCommitIntent } from "@/lib/marche/orderRequestId";

/**
 * Node 4 — Marché R3 order review.
 *
 * Single-store basket. Local quantities are a convenience only: the server
 * reprices everything at commit and the confirmation below shows the frozen
 * server snapshot, never local arithmetic.
 */
export function MarcheOrderReview({
  open,
  onOpenChange,
  listing,
  offerId,
  onCommitted,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  listing: { id: string; title: string; store_id: string; price_gnf: number | null; quantity_in_stock?: number | null };
  offerId?: string | null;
  onCommitted?: (order: MarcheOrder) => void;
}) {
  const [qty, setQty] = useState(1);
  const [address, setAddress] = useState("");
  const [busy, setBusy] = useState(false);
  const [order, setOrder] = useState<MarcheOrder | null>(null);
  const keys = useRef(createOrderRequestIdStore("listing-detail"));

  const maxQty = listing.quantity_in_stock ?? 99;

  const intent: OrderCommitIntent = useMemo(
    () => ({
      storeId: listing.store_id,
      lines: [{ listingId: listing.id, qty, offerId: offerId ?? null }],
      deliveryAddress: address.trim() || null,
    }),
    [listing.store_id, listing.id, qty, offerId, address],
  );

  const submit = async () => {
    setBusy(true);
    try {
      const key = keys.current.idFor(intent);
      const committed = await commitMarcheOrder(intent, key);
      keys.current.reset(intent);
      setOrder(committed);
      onCommitted?.(committed);
      toast({ title: "Commande confirmée" });
    } catch (e) {
      toast({ title: "Commande refusée", description: (e as Error)?.message });
    } finally {
      setBusy(false);
    }
  };

  const close = (v: boolean) => {
    if (!v) {
      setOrder(null);
      setQty(1);
    }
    onOpenChange(v);
  };

  return (
    <Sheet open={open} onOpenChange={close}>
      <SheetContent side="bottom" className="rounded-t-2xl">
        <SheetHeader>
          <SheetTitle className="flex items-center gap-2">
            <ShoppingBag className="w-4 h-4 text-primary" /> Votre commande
          </SheetTitle>
        </SheetHeader>

        {order ? (
          <div className="space-y-3 py-3">
            <div className="flex items-center gap-2 text-sm font-semibold text-primary">
              <CheckCircle2 className="w-4 h-4" /> Commande confirmée
            </div>
            {order.items.map((it) => (
              <div key={it.id} className="rounded-xl border border-border/60 bg-card p-3 text-sm">
                <p className="font-medium truncate">{it.title}</p>
                <p className="text-xs text-muted-foreground">
                  {it.qty} × {formatGNF(it.unit_price_gnf)}
                </p>
                <p className="text-sm font-semibold mt-1">{formatGNF(it.line_total_gnf)}</p>
              </div>
            ))}
            <div className="flex items-center justify-between border-t border-border/60 pt-2">
              <span className="text-sm text-muted-foreground">Total marchandise</span>
              <span className="text-base font-bold">{formatGNF(orderDisplayTotalGnf(order))}</span>
            </div>
            <p className="text-[11px] text-muted-foreground">
              Frais de service et livraison : à connecter (non facturés pour l'instant).
            </p>
            <Button className="w-full" onClick={() => close(false)}>Fermer</Button>
          </div>
        ) : (
          <div className="space-y-3 py-3">
            <div>
              <p className="text-sm font-medium truncate">{listing.title}</p>
              <p className="text-xs text-muted-foreground">
                {offerId ? "Prix convenu appliqué par CHOP CHOP" : "Prix boutique appliqué par CHOP CHOP"}
              </p>
            </div>
            <div className="flex items-center gap-3">
              <span className="text-sm text-muted-foreground">Quantité</span>
              <div className="flex items-center gap-2">
                <Button size="icon" variant="outline" onClick={() => setQty((q) => Math.max(1, q - 1))} disabled={qty <= 1}>
                  <Minus className="w-4 h-4" />
                </Button>
                <span className="w-8 text-center font-semibold">{qty}</span>
                <Button size="icon" variant="outline" onClick={() => setQty((q) => Math.min(maxQty, q + 1))} disabled={qty >= maxQty}>
                  <Plus className="w-4 h-4" />
                </Button>
              </div>
            </div>
            <Input
              value={address}
              onChange={(e) => setAddress(e.target.value)}
              placeholder="Adresse de livraison (optionnel)"
            />
            <Button className="w-full" onClick={submit} disabled={busy}>
              {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : "Confirmer la commande"}
            </Button>
            <p className="text-[11px] text-muted-foreground text-center">
              Le montant final est calculé par CHOP CHOP au moment de la confirmation.
            </p>
          </div>
        )}
      </SheetContent>
    </Sheet>
  );
}
