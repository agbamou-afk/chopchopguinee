import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { toast } from "@/hooks/use-toast";
import { Inbox, HandCoins, Package, History as HistoryIcon, Check, X, Repeat2, Loader2 } from "lucide-react";
import { listSellerInterests, respondToInterest } from "@/lib/merchant/operations";
import { listMerchantOffers, respondOffer, offerStatusLabel, type MarketplaceOffer } from "@/lib/marche/offers";
import { formatGNF } from "@/lib/marche";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";

type Section = "new" | "offers" | "prep" | "history";

export function MerchantCommandesView({ merchantUserId }: { merchantUserId: string }) {
  const [tab, setTab] = useState<Section>("new");
  const [interests, setInterests] = useState<any[]>([]);
  const [offers, setOffers] = useState<MarketplaceOffer[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string | null>(null);
  const [counterFor, setCounterFor] = useState<string | null>(null);
  const [counterAmt, setCounterAmt] = useState("");
  const [counterMsg, setCounterMsg] = useState("");

  const refresh = async () => {
    setLoading(true);
    const [iRes, oRes] = await Promise.allSettled([
      listSellerInterests(merchantUserId, 80),
      listMerchantOffers(merchantUserId),
    ]);
    if (iRes.status === "fulfilled") {
      setInterests(iRes.value);
    } else {
      setInterests([]);
      if (import.meta.env.DEV) console.warn("[merchant] interests load failed", iRes.reason);
      toast({ title: "Demandes indisponibles pour le moment" });
    }
    if (oRes.status === "fulfilled") {
      setOffers(oRes.value);
    } else {
      setOffers([]);
      if (import.meta.env.DEV) console.warn("[merchant] offers load failed", oRes.reason);
    }
    setLoading(false);
  };

  useEffect(() => { refresh(); /* eslint-disable-next-line */ }, [merchantUserId]);

  const newInterests = interests.filter((i) => i.state === "pending");
  const prepInterests = interests.filter((i) => i.state === "accepted");
  const histInterests = interests.filter((i) => ["declined", "fulfilled", "expired"].includes(i.state));
  const openOffers = offers.filter((o) => ["pending", "countered"].includes(o.status));
  const histOffers = offers.filter((o) => ["accepted", "rejected", "expired", "withdrawn"].includes(o.status));

  const respondInt = async (id: string, state: "accepted" | "declined" | "fulfilled") => {
    setBusy(id);
    try { await respondToInterest(id, state); await refresh(); }
    catch (e: any) { toast({ title: "Erreur", description: e?.message }); }
    finally { setBusy(null); }
  };

  const actOffer = async (o: MarketplaceOffer, action: "accept" | "reject" | "counter") => {
    if (action === "counter" && counterFor !== o.id) {
      setCounterFor(o.id); setCounterAmt(""); setCounterMsg("");
      return;
    }
    setBusy(o.id);
    try {
      await respondOffer({
        offerId: o.id, action,
        counterAmountGnf: action === "counter" ? Number(counterAmt) : null,
        message: counterMsg || null,
      });
      setCounterFor(null);
      await refresh();
    } catch (e: any) { toast({ title: "Erreur", description: e?.message }); }
    finally { setBusy(null); }
  };

  const TABS: { key: Section; label: string; icon: typeof Inbox; badge: number }[] = [
    { key: "new", label: "Demandes", icon: Inbox, badge: newInterests.length },
    { key: "offers", label: "Offres", icon: HandCoins, badge: openOffers.length },
    { key: "prep", label: "À préparer", icon: Package, badge: prepInterests.length },
    { key: "history", label: "Historique", icon: HistoryIcon, badge: 0 },
  ];

  const InterestRow = ({ i, actions }: { i: any; actions?: React.ReactNode }) => (
    <div className="rounded-xl bg-card border border-border/60 p-3">
      <div className="flex items-center justify-between gap-2">
        <span className="text-xs font-semibold text-primary capitalize">
          {i.kind === "delivery" ? "Demande livraison" : i.kind === "reservation" ? "Réservation" : "Disponibilité"}
        </span>
        <span className="text-[10px] text-muted-foreground">{new Date(i.created_at).toLocaleString("fr-FR")}</span>
      </div>
      <p className="text-sm font-medium text-foreground mt-1 truncate">{i.marketplace_listings?.title ?? "Annonce"}</p>
      {i.note && <p className="text-xs text-muted-foreground italic mt-1">« {i.note} »</p>}
      {actions}
    </div>
  );

  return (
    <div className="space-y-3">
      <div className="grid grid-cols-4 gap-1 bg-muted/40 rounded-xl p-1">
        {TABS.map((t) => {
          const Icon = t.icon;
          const active = tab === t.key;
          return (
            <button key={t.key} onClick={() => setTab(t.key)}
              className={`flex flex-col items-center gap-0.5 py-1.5 rounded-lg text-[11px] font-semibold relative ${active ? "bg-card text-foreground shadow-sm" : "text-muted-foreground"}`}>
              <Icon className="w-4 h-4" />
              {t.label}
              {t.badge > 0 && (
                <span className="absolute top-0 right-1 text-[9px] bg-primary text-primary-foreground rounded-full px-1 min-w-[14px] h-[14px] flex items-center justify-center font-bold">
                  {t.badge}
                </span>
              )}
            </button>
          );
        })}
      </div>

      {loading && <p className="text-sm text-muted-foreground">Chargement…</p>}

      {!loading && tab === "new" && (
        newInterests.length === 0
          ? <p className="text-sm text-muted-foreground">Aucune nouvelle demande.</p>
          : <div className="space-y-2">
              {newInterests.map((i) => (
                <InterestRow key={i.id} i={i} actions={
                  <div className="flex gap-2 mt-2">
                    <Button size="sm" className="flex-1" disabled={busy === i.id} onClick={() => respondInt(i.id, "accepted")}>
                      <Check className="w-3 h-3 mr-1" /> Confirmer disponible
                    </Button>
                    <Button size="sm" variant="outline" className="flex-1" disabled={busy === i.id} onClick={() => respondInt(i.id, "declined")}>
                      <X className="w-3 h-3 mr-1" /> Refuser
                    </Button>
                  </div>
                } />
              ))}
            </div>
      )}

      {!loading && tab === "offers" && (
        openOffers.length === 0
          ? <p className="text-sm text-muted-foreground">Aucune offre en cours.</p>
          : <div className="space-y-2">
              {openOffers.map((o) => (
                <div key={o.id} className="rounded-xl bg-card border border-border/60 p-3">
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0">
                      <p className="text-sm font-semibold">Offre : {formatGNF(o.offer_amount_gnf)}</p>
                      {o.counter_amount_gnf != null && (
                        <p className="text-xs text-muted-foreground">Contre-proposition : {formatGNF(o.counter_amount_gnf)}</p>
                      )}
                      {o.buyer_message && <p className="text-xs italic mt-1">« {o.buyer_message} »</p>}
                      <p className="text-[10px] text-muted-foreground mt-1">{new Date(o.created_at).toLocaleString("fr-FR")}</p>
                    </div>
                    <span className="text-[10px] uppercase tracking-wide px-1.5 py-0.5 rounded bg-muted text-muted-foreground shrink-0">
                      {offerStatusLabel(o.status)}
                    </span>
                  </div>
                  {counterFor === o.id && (
                    <div className="mt-2 space-y-2">
                      <Input type="number" inputMode="numeric" min={1} value={counterAmt}
                        onChange={(e) => setCounterAmt(e.target.value)} placeholder="Contre-proposition (GNF)" />
                      <Textarea rows={2} value={counterMsg} onChange={(e) => setCounterMsg(e.target.value)}
                        placeholder="Message (optionnel)" />
                    </div>
                  )}
                  <div className="flex flex-wrap gap-1 mt-2">
                    <Button size="sm" disabled={busy === o.id} onClick={() => actOffer(o, "accept")}>
                      {busy === o.id ? <Loader2 className="w-3 h-3 animate-spin" /> : <><Check className="w-3 h-3 mr-1" /> Accepter</>}
                    </Button>
                    <Button size="sm" variant="outline" disabled={busy === o.id} onClick={() => actOffer(o, "counter")}>
                      <Repeat2 className="w-3 h-3 mr-1" /> {counterFor === o.id ? "Envoyer" : "Contre-proposer"}
                    </Button>
                    <Button size="sm" variant="outline" disabled={busy === o.id} onClick={() => actOffer(o, "reject")}>
                      <X className="w-3 h-3 mr-1" /> Refuser
                    </Button>
                  </div>
                </div>
              ))}
            </div>
      )}

      {!loading && tab === "prep" && (
        prepInterests.length === 0
          ? <p className="text-sm text-muted-foreground">Aucune commande à préparer.</p>
          : <div className="space-y-2">
              {prepInterests.map((i) => (
                <InterestRow key={i.id} i={i} actions={
                  <Button size="sm" variant="outline" className="mt-2 w-full"
                    disabled={busy === i.id} onClick={() => respondInt(i.id, "fulfilled")}>
                    Marquer terminé
                  </Button>
                } />
              ))}
            </div>
      )}

      {!loading && tab === "history" && (
        (histInterests.length + histOffers.length) === 0
          ? <p className="text-sm text-muted-foreground">Pas encore d'historique.</p>
          : <div className="space-y-2">
              {histInterests.map((i) => <InterestRow key={i.id} i={i} />)}
              {histOffers.map((o) => (
                <div key={o.id} className="rounded-xl bg-card border border-border/60 p-3">
                  <div className="flex items-center justify-between gap-2">
                    <span className="text-xs font-semibold">Offre : {formatGNF(o.offer_amount_gnf)}</span>
                    <span className="text-[10px] uppercase tracking-wide text-muted-foreground">{offerStatusLabel(o.status)}</span>
                  </div>
                  <p className="text-[10px] text-muted-foreground mt-1">{new Date(o.created_at).toLocaleString("fr-FR")}</p>
                </div>
              ))}
            </div>
      )}
    </div>
  );
}