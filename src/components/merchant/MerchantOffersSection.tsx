import { useEffect, useState } from "react";
import { SectionCard } from "./SectionCard";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Check, X, Repeat2, Loader2 } from "lucide-react";
import { toast } from "@/hooks/use-toast";
import {
  listMerchantOffers,
  respondOffer,
  offerStatusLabel,
  type MarketplaceOffer,
} from "@/lib/marche/offers";
import { formatGNF } from "@/lib/marche";

export function MerchantOffersSection({ merchantId }: { merchantId: string }) {
  const [items, setItems] = useState<MarketplaceOffer[]>([]);
  const [loading, setLoading] = useState(true);
  const [counterFor, setCounterFor] = useState<string | null>(null);
  const [counterAmt, setCounterAmt] = useState("");
  const [counterMsg, setCounterMsg] = useState("");
  const [busy, setBusy] = useState<string | null>(null);

  const refresh = async () => {
    setLoading(true);
    setItems(await listMerchantOffers(merchantId));
    setLoading(false);
  };

  useEffect(() => { refresh(); /* eslint-disable-next-line */ }, [merchantId]);

  const act = async (o: MarketplaceOffer, action: "accept" | "reject" | "counter") => {
    if (action === "counter" && counterFor !== o.id) {
      setCounterFor(o.id); setCounterAmt(""); setCounterMsg("");
      return;
    }
    setBusy(o.id);
    try {
      await respondOffer({
        offerId: o.id,
        action,
        counterAmountGnf: action === "counter" ? Number(counterAmt) : null,
        message: counterMsg || null,
      });
      toast({ title: "Offre mise à jour" });
      setCounterFor(null);
      await refresh();
    } catch (e: any) {
      toast({ title: "Erreur", description: e?.message ?? "Action impossible" });
    } finally {
      setBusy(null);
    }
  };

  return (
    <SectionCard title="Offres reçues" hint="Négociations en cours sur vos produits">
      {loading ? (
        <p className="text-sm text-muted-foreground">Chargement…</p>
      ) : items.length === 0 ? (
        <p className="text-sm text-muted-foreground">Aucune offre pour le moment.</p>
      ) : (
        <div className="space-y-2">
          {items.map((o) => {
            const open = o.status === "pending" || o.status === "countered";
            return (
              <div key={o.id} className="rounded-xl bg-muted/40 border border-border/50 p-3">
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0">
                    <p className="text-sm font-semibold">
                      Offre : {formatGNF(o.offer_amount_gnf)}
                    </p>
                    {o.counter_amount_gnf && (
                      <p className="text-xs text-muted-foreground">
                        Contre-proposition : {formatGNF(o.counter_amount_gnf)}
                      </p>
                    )}
                    {o.buyer_message && (
                      <p className="text-xs text-foreground italic mt-1">« {o.buyer_message} »</p>
                    )}
                    <p className="text-[10px] text-muted-foreground mt-1">
                      {new Date(o.created_at).toLocaleString("fr-FR")}
                    </p>
                  </div>
                  <span className="text-[10px] uppercase tracking-wide px-1.5 py-0.5 rounded bg-card border border-border/60 text-muted-foreground shrink-0">
                    {offerStatusLabel(o.status)}
                  </span>
                </div>

                {open && (
                  <>
                    {counterFor === o.id && (
                      <div className="mt-2 space-y-2">
                        <Input
                          type="number" inputMode="numeric" min={1}
                          value={counterAmt} onChange={(e) => setCounterAmt(e.target.value)}
                          placeholder="Votre contre-proposition (GNF)"
                        />
                        <Textarea
                          rows={2} value={counterMsg}
                          onChange={(e) => setCounterMsg(e.target.value)}
                          placeholder="Message (optionnel)"
                        />
                      </div>
                    )}
                    <div className="flex flex-wrap gap-1 mt-3">
                      <Button size="sm" disabled={busy === o.id} onClick={() => act(o, "accept")}>
                        {busy === o.id ? <Loader2 className="w-3 h-3 animate-spin" /> : <><Check className="w-3 h-3 mr-1" /> Accepter</>}
                      </Button>
                      <Button size="sm" variant="outline" disabled={busy === o.id} onClick={() => act(o, "counter")}>
                        <Repeat2 className="w-3 h-3 mr-1" />
                        {counterFor === o.id ? "Envoyer la contre-offre" : "Contre-proposer"}
                      </Button>
                      <Button size="sm" variant="outline" disabled={busy === o.id} onClick={() => act(o, "reject")}>
                        <X className="w-3 h-3 mr-1" /> Refuser
                      </Button>
                    </div>
                  </>
                )}
                {o.status === "accepted" && (
                  <div className="mt-2 rounded-lg bg-background/60 border border-border/60 p-2 text-[11px] space-y-0.5">
                    {o.payment_status === "authorized" ? (
                      <p className="text-success">
                        Paiement autorisé — en attente de remise/livraison.
                      </p>
                    ) : o.payment_status === "paid" ? (
                      <p className="text-success">Paiement réglé.</p>
                    ) : o.payment_status === "failed" ? (
                      <p className="text-destructive">Paiement échoué côté acheteur.</p>
                    ) : (
                      <p className="text-muted-foreground">
                        En attente du paiement de l'acheteur.
                      </p>
                    )}
                    <p className="text-muted-foreground/80 text-[10px]">
                      Le paiement sera réglé après confirmation.
                    </p>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
    </SectionCard>
  );
}