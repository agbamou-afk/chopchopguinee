import { useEffect, useMemo, useRef, useState } from "react";
import { Loader2, ShoppingBag, Minus, Plus, CheckCircle2, WifiOff, AlertTriangle, MapPin } from "lucide-react";
import { Sheet, SheetContent, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { toast } from "@/hooks/use-toast";
import { formatGNF } from "@/lib/marche";
import {
  commitMarcheOrderResilient,
  destinationQualityLabel,
  orderDisplayTotalGnf,
  revalidateMarcheBasket,
  revalidationMessage,
  type BasketRevalidation,
  type MarcheOrder,
} from "@/lib/marche/orders";
import { createOrderRequestIdStore, type OrderCommitIntent } from "@/lib/marche/orderRequestId";
import { useAppEnv } from "@/contexts/AppEnvContext";

/**
 * Node 4 — Marché R3 order review, hardened for Conakry in R13.
 *
 * Single-store basket. Local quantities and any last-seen price are a
 * convenience only: the basket is revalidated against live server truth before
 * commitment, the server reprices everything at commit, and the confirmation
 * below shows the frozen server snapshot — never local arithmetic.
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
  const { online } = useAppEnv();
  const [qty, setQty] = useState(1);
  const [address, setAddress] = useState("");
  const [landmark, setLandmark] = useState("");
  const [instructions, setInstructions] = useState("");
  const [busy, setBusy] = useState(false);
  const [checking, setChecking] = useState(false);
  const [check, setCheck] = useState<BasketRevalidation | null>(null);
  const [order, setOrder] = useState<MarcheOrder | null>(null);
  const keys = useRef(createOrderRequestIdStore("listing-detail"));

  const maxQty = listing.quantity_in_stock ?? 99;

  const intent: OrderCommitIntent = useMemo(
    () => ({
      storeId: listing.store_id,
      lines: [{ listingId: listing.id, qty, offerId: offerId ?? null }],
      deliveryAddress: address.trim() || null,
      destinationLandmark: landmark.trim() || null,
      destinationInstructions: instructions.trim() || null,
      locationSource: address.trim() || landmark.trim() ? "typed" : null,
    }),
    [listing.store_id, listing.id, qty, offerId, address, landmark, instructions],
  );

  // A changed quantity invalidates the previous server verdict.
  useEffect(() => { setCheck(null); }, [qty, listing.id]);

  const runCheck = async (): Promise<BasketRevalidation | null> => {
    setChecking(true);
    try {
      const r = await revalidateMarcheBasket([
        {
          listingId: listing.id,
          qty,
          offerId: offerId ?? null,
          cachedUnitPriceGnf: listing.price_gnf ?? null,
        },
      ]);
      setCheck(r);
      return r;
    } catch (e) {
      toast({ title: "Vérification impossible", description: (e as Error)?.message });
      return null;
    } finally {
      setChecking(false);
    }
  };

  const submit = async () => {
    if (!online) {
      toast({ title: "Hors ligne", description: "Reconnectez-vous pour confirmer la commande." });
      return;
    }
    setBusy(true);
    try {
      // R13: never commit a basket composed offline without re-checking it.
      const fresh = check ?? (await runCheck());
      if (!fresh) return;
      if (!fresh.ok) {
        toast({ title: "Commande impossible", description: revalidationMessage(fresh) ?? undefined });
        return;
      }
      if (fresh.material_change) {
        // Show the new server truth first; the customer confirms knowingly.
        toast({ title: "Le prix a changé", description: revalidationMessage(fresh) ?? undefined });
        return;
      }
      const key = keys.current.idFor(intent);
      const { order: committed, recovered } = await commitMarcheOrderResilient(intent, key);
      keys.current.reset(intent);
      setOrder(committed);
      onCommitted?.(committed);
      toast({
        title: recovered ? "Commande déjà enregistrée" : "Commande confirmée",
        description: recovered ? "Votre commande avait bien été reçue malgré la coupure." : undefined,
      });
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
      setCheck(null);
    }
    onOpenChange(v);
  };

  const checkMessage = check ? revalidationMessage(check) : null;
  const priceLine = check?.lines?.[0];

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
            {order.destination_quality ? (
              <p className="flex items-center gap-1.5 text-[11px] text-muted-foreground">
                <MapPin className="w-3 h-3" />
                {destinationQualityLabel(order.destination_quality)}
                {order.destination_landmark ? ` — ${order.destination_landmark}` : ""}
              </p>
            ) : null}
            <p className="text-[11px] text-muted-foreground">
              Frais de service et livraison : à connecter (non facturés pour l'instant).
            </p>
            <Button className="w-full" onClick={() => close(false)}>Fermer</Button>
          </div>
        ) : (
          <div className="space-y-3 py-3">
            {!online && (
              <div className="flex items-start gap-2 rounded-xl border border-warning/40 bg-warning/10 p-3 text-xs">
                <WifiOff className="w-4 h-4 mt-0.5 shrink-0" />
                <span>
                  Hors ligne. Vous pouvez préparer votre commande : elle sera vérifiée et confirmée dès le retour du réseau.
                </span>
              </div>
            )}
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
              placeholder="Quartier / adresse (optionnel)"
              maxLength={200}
            />
            <Input
              value={landmark}
              onChange={(e) => setLandmark(e.target.value)}
              placeholder="Repère : « près du marché Madina » (optionnel)"
              maxLength={200}
            />
            <Input
              value={instructions}
              onChange={(e) => setInstructions(e.target.value)}
              placeholder="Indications au livreur (optionnel)"
              maxLength={300}
            />

            {checkMessage && (
              <div className="flex items-start gap-2 rounded-xl border border-border/60 bg-muted/40 p-3 text-xs">
                <AlertTriangle className="w-4 h-4 mt-0.5 shrink-0 text-warning" />
                <span>{checkMessage}</span>
              </div>
            )}
            {check?.ok && priceLine?.unit_price_gnf != null && (
              <div className="flex items-center justify-between text-sm">
                <span className="text-muted-foreground">Total vérifié</span>
                <span className="font-bold">{formatGNF(check.merchandise_subtotal_gnf ?? 0)}</span>
              </div>
            )}

            <div className="flex gap-2">
              <Button variant="outline" className="flex-1" onClick={runCheck} disabled={!online || checking || busy}>
                {checking ? <Loader2 className="w-4 h-4 animate-spin" /> : "Vérifier le prix"}
              </Button>
              <Button className="flex-1" onClick={submit} disabled={busy || !online}>
                {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : "Confirmer la commande"}
              </Button>
            </div>
            <p className="text-[11px] text-muted-foreground text-center">
              Le montant final est calculé par CHOP CHOP au moment de la confirmation.
            </p>
          </div>
        )}
      </SheetContent>
    </Sheet>
  );
}
