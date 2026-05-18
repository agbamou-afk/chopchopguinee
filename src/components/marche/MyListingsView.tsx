import { useEffect, useState } from "react";
import { ArrowLeft, Eye, Heart, MessageSquare, Plus, Store, Inbox } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { formatGNF, timeAgo } from "@/lib/marche";
import { MarcheEmpty } from "./MarcheEmpty";
import { LoadingState } from "@/components/ui/LoadingState";
import { Button } from "@/components/ui/button";
import { getOwnStore, type MerchantStore } from "@/lib/marche/stores";
import { listSellerInterests } from "@/lib/marche/interests";
import { SellerRequestsSheet } from "./SellerRequestsSheet";

interface MyListing {
  id: string;
  title: string;
  price_gnf: number | null;
  status: string;
  created_at: string;
  cover_url: string | null;
  metrics: { views: number; saves: number; messages: number };
}

export function MyListingsView({
  onBack,
  onCreate,
  onOpenListing,
  onOpenStore,
}: {
  onBack: () => void;
  onCreate: () => void;
  onOpenListing: (id: string) => void;
  onOpenStore: () => void;
}) {
  const [items, setItems] = useState<MyListing[]>([]);
  const [loading, setLoading] = useState(true);
  const [store, setStore] = useState<MerchantStore | null>(null);
  const [sellerId, setSellerId] = useState<string | null>(null);
  const [pendingCount, setPendingCount] = useState(0);
  const [requestsByListing, setRequestsByListing] = useState<Record<string, number>>({});
  const [requestsOpen, setRequestsOpen] = useState(false);

  useEffect(() => {
    let alive = true;
    (async () => {
      setLoading(true);
      const { data: sess } = await supabase.auth.getSession();
      const uid = sess.session?.user.id;
      if (!uid) {
        setLoading(false);
        return;
      }
      if (alive) setSellerId(uid);
      const own = await getOwnStore(uid);
      if (alive) setStore(own);
      const { data } = await supabase
        .from("marketplace_listings")
        .select("id, title, price_gnf, status, created_at, listing_images(url, position)")
        .eq("seller_id", uid)
        .order("created_at", { ascending: false })
        .limit(80);
      const rows = (data ?? []) as unknown as Array<{
        id: string;
        title: string;
        price_gnf: number | null;
        status: string;
        created_at: string;
        listing_images?: { url: string; position: number }[];
      }>;
      const ids = rows.map((r) => r.id);
      let metricsMap = new Map<string, { views: number; saves: number; messages: number }>();
      if (ids.length > 0) {
        const { data: mdata } = await (supabase as unknown as {
          from: (t: string) => {
            select: (s: string) => {
              in: (c: string, v: unknown[]) => Promise<{ data: unknown }>;
            };
          };
        })
          .from("listing_metrics")
          .select("listing_id, views, saves, messages")
          .in("listing_id", ids);
        const mrows = (mdata as Array<{ listing_id: string; views: number; saves: number; messages: number }> | null) ?? [];
        metricsMap = new Map(mrows.map((m) => [m.listing_id, { views: m.views, saves: m.saves, messages: m.messages }]));
      }
      if (!alive) return;
      setItems(
        rows.map((r) => ({
          id: r.id,
          title: r.title,
          price_gnf: r.price_gnf,
          status: r.status,
          created_at: r.created_at,
          cover_url: r.listing_images?.slice().sort((a, b) => a.position - b.position)[0]?.url ?? null,
          metrics: metricsMap.get(r.id) ?? { views: 0, saves: 0, messages: 0 },
        })),
      );
      const interests = await listSellerInterests(uid, 100);
      if (!alive) return;
      const perListing: Record<string, number> = {};
      let pending = 0;
      for (const i of interests) {
        if (i.state === "pending") {
          pending += 1;
          perListing[i.listing_id] = (perListing[i.listing_id] ?? 0) + 1;
        }
      }
      setPendingCount(pending);
      setRequestsByListing(perListing);
      setLoading(false);
    })();
    return () => {
      alive = false;
    };
  }, []);

  return (
    <div className="max-w-md mx-auto pb-24 bg-background min-h-screen">
      <header className="flex items-center gap-3 p-4 border-b sticky top-0 bg-background z-10">
        <button onClick={onBack} className="p-2 -ml-2 rounded-full hover:bg-muted">
          <ArrowLeft className="w-5 h-5" />
        </button>
        <div className="flex-1 min-w-0">
          <h1 className="font-semibold">Mes annonces</h1>
          {store ? (
            <p className="text-[11px] text-muted-foreground truncate">
              Boutique : {store.name}
            </p>
          ) : (
            <p className="text-[11px] text-muted-foreground">Vendeur communauté</p>
          )}
        </div>
        {sellerId && (
          <button
            onClick={() => setRequestsOpen(true)}
            aria-label={pendingCount > 0 ? `${pendingCount} demande${pendingCount > 1 ? "s" : ""} en attente` : "Demandes des acheteurs"}
            className="relative p-2 rounded-full bg-card border border-border/60"
          >
            <Inbox className="w-4 h-4 text-foreground" />
            {pendingCount > 0 && (
              <span className="absolute -top-1 -right-1 min-w-4 h-4 px-1 rounded-full bg-primary text-primary-foreground text-[10px] font-semibold flex items-center justify-center">
                {pendingCount}
              </span>
            )}
          </button>
        )}
        <button
          onClick={onOpenStore}
          aria-label="Boutique"
          className="p-2 rounded-full bg-card border border-border/60"
        >
          <Store className="w-4 h-4 text-foreground" />
        </button>
      </header>

      <div className="px-4 pt-4 space-y-3">
        {loading ? (
          <LoadingState variant="cards" rows={3} />
        ) : items.length === 0 ? (
          <MarcheEmpty
            variant="listings"
            action={
              <Button onClick={onCreate} size="sm">
                <Plus className="w-4 h-4 mr-1" /> Publier
              </Button>
            }
          />
        ) : (
          items.map((l) => (
            <button
              key={l.id}
              onClick={() => onOpenListing(l.id)}
              className="w-full text-left bg-card rounded-2xl p-3 shadow-card hover:shadow-elevated transition-shadow flex gap-3"
            >
              <div className="w-16 h-16 rounded-xl bg-muted overflow-hidden shrink-0">
                {l.cover_url ? (
                  <img src={l.cover_url} alt="" className="w-full h-full object-cover" loading="lazy" />
                ) : null}
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold text-foreground truncate">{l.title}</p>
                <p className="text-sm font-bold text-primary">{formatGNF(l.price_gnf)}</p>
                <div className="flex items-center gap-3 text-[11px] text-muted-foreground mt-1">
                  <span className="inline-flex items-center gap-1"><Eye className="w-3 h-3" />{l.metrics.views} vues</span>
                  <span className="inline-flex items-center gap-1"><Heart className="w-3 h-3" />{l.metrics.saves}</span>
                  <span className="inline-flex items-center gap-1"><MessageSquare className="w-3 h-3" />{l.metrics.messages}</span>
                  {requestsByListing[l.id] > 0 && (
                    <span className="inline-flex items-center gap-1 text-primary">
                      <Inbox className="w-3 h-3" />{requestsByListing[l.id]}
                    </span>
                  )}
                </div>
                <p className="text-[10px] text-muted-foreground mt-0.5">{timeAgo(l.created_at)} · {l.status}</p>
              </div>
            </button>
          ))
        )}
      </div>
      {sellerId && (
        <SellerRequestsSheet
          open={requestsOpen}
          onOpenChange={setRequestsOpen}
          sellerId={sellerId}
        />
      )}
    </div>
  );
}