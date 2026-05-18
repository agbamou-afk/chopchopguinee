import { useEffect, useState } from "react";
import { Inbox, Check, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Sheet, SheetContent, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { toast } from "@/hooks/use-toast";
import { timeAgo } from "@/lib/marche";
import {
  listSellerInterests,
  respondInterest,
  INTEREST_KIND_LABEL,
  INTEREST_STATE_LABEL,
  type ListingInterest,
  type InterestState,
} from "@/lib/marche/interests";
import { supabase } from "@/integrations/supabase/client";

// Lightweight seller-side response surface. Lists pending requests with
// per-row response shortcuts. No realtime — refresh on open.
export function SellerRequestsSheet({
  open,
  onOpenChange,
  sellerId,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  sellerId: string;
}) {
  const [items, setItems] = useState<ListingInterest[]>([]);
  const [titles, setTitles] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    let alive = true;
    (async () => {
      setLoading(true);
      const list = await listSellerInterests(sellerId);
      const ids = Array.from(new Set(list.map((i) => i.listing_id)));
      let titleMap: Record<string, string> = {};
      if (ids.length > 0) {
        const { data } = await supabase
          .from("marketplace_listings")
          .select("id, title")
          .in("id", ids);
        titleMap = Object.fromEntries(((data ?? []) as Array<{ id: string; title: string }>).map((r) => [r.id, r.title]));
      }
      if (alive) {
        setItems(list);
        setTitles(titleMap);
        setLoading(false);
      }
    })();
    return () => {
      alive = false;
    };
  }, [open, sellerId]);

  const respond = async (it: ListingInterest, state: Exclude<InterestState, "pending">, label: string) => {
    setBusy(it.id);
    try {
      await respondInterest(it.id, state);
      setItems((cur) => cur.map((x) => (x.id === it.id ? { ...x, state } : x)));
      toast({ title: label, description: "Acheteur notifié." });
    } catch (e) {
      toast({ title: "Erreur", description: (e as Error).message });
    } finally {
      setBusy(null);
    }
  };

  const pending = items.filter((i) => i.state === "pending");
  const recent = items.filter((i) => i.state !== "pending").slice(0, 12);

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="bottom" className="max-h-[85vh] overflow-y-auto">
        <SheetHeader>
          <SheetTitle className="flex items-center gap-2">
            <Inbox className="w-4 h-4" /> Demandes des acheteurs
          </SheetTitle>
        </SheetHeader>
        <div className="mt-4 space-y-4">
          {loading ? (
            <p className="text-sm text-muted-foreground py-6 text-center">Chargement…</p>
          ) : items.length === 0 ? (
            <p className="text-sm text-muted-foreground py-6 text-center">
              Aucune demande pour l'instant.
            </p>
          ) : (
            <>
              {pending.length > 0 && (
                <section className="space-y-2">
                  <p className="text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
                    En attente
                  </p>
                  {pending.map((it) => (
                    <div key={it.id} className="bg-card rounded-2xl p-3 shadow-card">
                      <p className="text-sm font-medium">{titles[it.listing_id] ?? "Annonce"}</p>
                      <p className="text-[11px] text-muted-foreground mt-0.5">
                        {INTEREST_KIND_LABEL[it.kind]} · {timeAgo(it.created_at)}
                      </p>
                      <div className="flex flex-wrap gap-2 mt-2">
                        <Button
                          size="sm"
                          variant="outline"
                          disabled={busy === it.id}
                          onClick={() => respond(it, "available", "Disponible confirmé")}
                        >
                          <Check className="w-3 h-3 mr-1" /> Disponible
                        </Button>
                        <Button
                          size="sm"
                          variant="outline"
                          disabled={busy === it.id}
                          onClick={() => respond(it, "reserved", "Marqué réservé")}
                        >
                          Réservé
                        </Button>
                        <Button
                          size="sm"
                          variant="outline"
                          disabled={busy === it.id}
                          onClick={() => respond(it, "sold", "Marqué vendu")}
                        >
                          Vendu
                        </Button>
                        <Button
                          size="sm"
                          variant="ghost"
                          disabled={busy === it.id}
                          onClick={() => respond(it, "declined", "Demande refusée")}
                        >
                          <X className="w-3 h-3 mr-1" /> Refuser
                        </Button>
                      </div>
                    </div>
                  ))}
                </section>
              )}
              {recent.length > 0 && (
                <section className="space-y-2">
                  <p className="text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
                    Réponses récentes
                  </p>
                  {recent.map((it) => (
                    <div key={it.id} className="bg-card/60 rounded-2xl p-3 border border-border/40">
                      <p className="text-sm">{titles[it.listing_id] ?? "Annonce"}</p>
                      <p className="text-[11px] text-muted-foreground mt-0.5">
                        {INTEREST_KIND_LABEL[it.kind]} · {timeAgo(it.updated_at)} · {INTEREST_STATE_LABEL[it.state]}
                      </p>
                    </div>
                  ))}
                </section>
              )}
            </>
          )}
        </div>
      </SheetContent>
    </Sheet>
  );
}