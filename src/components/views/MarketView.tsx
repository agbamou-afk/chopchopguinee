import { useEffect, useState, useCallback } from "react";
import { motion } from "framer-motion";
import { Search, MapPin, Bell, Plus, MessageSquare, X, Heart, ArrowUpDown, ShoppingBag, Timer, Store, ClipboardList } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { CategoryGrid } from "@/components/marche/CategoryGrid";
import { FeaturedBanners } from "@/components/marche/FeaturedBanners";
import { ListingCard, type ListingCardData } from "@/components/marche/ListingCard";
import { ListingDetail } from "@/components/marche/ListingDetail";
import { SellFlow } from "@/components/marche/SellFlow";
import { InboxView } from "@/components/marche/InboxView";
import { StoreCard } from "@/components/marche/StoreCard";
import { StoreProfile } from "@/components/marche/StoreProfile";
import { StoreOnboardingSheet } from "@/components/marche/StoreOnboardingSheet";
import { MyListingsView } from "@/components/marche/MyListingsView";
import { PromotedSlot } from "@/components/marche/PromotedSlot";
import { MarcheEmpty } from "@/components/marche/MarcheEmpty";
import { listStoresWithSummary, type StoreSummary } from "@/lib/marche/stores";
import { categoryLabel, MARCHE_CATEGORIES } from "@/lib/marche";
import { useAuthGuard } from "@/hooks/useAuthGuard";
import { ScreenHeader } from "@/components/ui/ScreenHeader";
import { LiveStrip } from "@/components/ui/LiveStrip";
import { LoadingState } from "@/components/ui/LoadingState";
import { EmptyState } from "@/components/ui/EmptyState";
import { Link } from "react-router-dom";

interface MarketViewProps {
  onBack: () => void;
}

type Screen = "home" | "detail" | "sell" | "inbox" | "store" | "mine";
type SortKey = "recent" | "price_asc" | "price_desc";
type Tab = "all" | "saved" | "stores";

interface RawListing extends Omit<ListingCardData, "cover_url"> {
  listing_images?: { url: string; position: number }[];
}

export function MarketView({ onBack }: MarketViewProps) {
  const [screen, setScreen] = useState<Screen>("home");
  const [activeListing, setActiveListing] = useState<string | null>(null);
  const [activeStoreId, setActiveStoreId] = useState<string | null>(null);
  const [storeSheetOpen, setStoreSheetOpen] = useState(false);
  const [category, setCategory] = useState<string | null>(null);
  const [search, setSearch] = useState("");
  const [listings, setListings] = useState<ListingCardData[]>([]);
  const [loading, setLoading] = useState(true);
  const [sort, setSort] = useState<SortKey>("recent");
  const [tab, setTab] = useState<Tab>("all");
  const [savedIds, setSavedIds] = useState<Set<string>>(new Set());
  const [stores, setStores] = useState<StoreSummary[]>([]);
  const [storesLoading, setStoresLoading] = useState(false);
  const [storeCategory, setStoreCategory] = useState<string | null>(null);
  const { requireAuth } = useAuthGuard();

  const load = useCallback(async () => {
    setLoading(true);
    let q = supabase
      .from("marketplace_listings")
      .select(
        "id, title, price_gnf, is_negotiable, is_urgent, delivery_available, neighborhood, commune, created_at, kind, availability, fulfillment_options, photo_count, condition, description, listing_images(url, position)"
      )
      .eq("status", "active")
      .limit(60);
    if (sort === "recent") q = q.order("created_at", { ascending: false });
    if (sort === "price_asc") q = q.order("price_gnf", { ascending: true, nullsFirst: false });
    if (sort === "price_desc") q = q.order("price_gnf", { ascending: false, nullsFirst: false });
    if (category) q = q.eq("category", category);
    if (search.trim()) q = q.ilike("title", `%${search.trim()}%`);
    const { data } = await q;
    const mapped: ListingCardData[] = ((data ?? []) as unknown as RawListing[]).map((r) => ({
      id: r.id,
      title: r.title,
      price_gnf: r.price_gnf,
      is_negotiable: r.is_negotiable,
      is_urgent: r.is_urgent,
      delivery_available: r.delivery_available,
      neighborhood: r.neighborhood,
      commune: r.commune,
      created_at: r.created_at,
      kind: r.kind,
      availability: (r as unknown as { availability?: string }).availability ?? null,
      fulfillment_options:
        (r as unknown as { fulfillment_options?: string[] }).fulfillment_options ?? null,
      photo_count: (r as unknown as { photo_count?: number }).photo_count ?? null,
      condition: (r as unknown as { condition?: string | null }).condition ?? null,
      description: (r as unknown as { description?: string | null }).description ?? null,
      cover_url:
        r.listing_images?.slice().sort((a, b) => a.position - b.position)[0]?.url ?? null,
    }));
    setListings(mapped);
    setLoading(false);
  }, [category, search, sort]);

  useEffect(() => {
    load();
  }, [load]);

  // Load stores when Boutiques tab becomes active or filters change.
  useEffect(() => {
    if (tab !== "stores") return;
    let alive = true;
    (async () => {
      setStoresLoading(true);
      const data = await listStoresWithSummary({
        q: search || undefined,
        category: storeCategory,
        limit: 40,
      });
      if (!alive) return;
      setStores(data);
      setStoresLoading(false);
    })();
    return () => {
      alive = false;
    };
  }, [tab, search, storeCategory]);

  // Load saved listings for the current user (if signed in)
  useEffect(() => {
    let active = true;
    (async () => {
      const { data: sess } = await supabase.auth.getSession();
      const uid = sess.session?.user.id;
      if (!uid) return;
      const { data } = await supabase
        .from("saved_listings")
        .select("listing_id")
        .eq("user_id", uid);
      if (!active) return;
      setSavedIds(new Set((data ?? []).map((r) => r.listing_id)));
    })();
    return () => {
      active = false;
    };
  }, [screen]);

  if (screen === "detail" && activeListing) {
    return <ListingDetail listingId={activeListing} onBack={() => setScreen("home")} />;
  }
  if (screen === "store" && activeStoreId) {
    return (
      <StoreProfile
        storeId={activeStoreId}
        onBack={() => setScreen("home")}
        onOpenListing={(id) => {
          setActiveListing(id);
          setScreen("detail");
        }}
      />
    );
  }
  if (screen === "mine") {
    return (
      <MyListingsView
        onBack={() => setScreen("home")}
        onCreate={() => requireAuth(() => setScreen("sell"))}
        onOpenListing={(id) => {
          setActiveListing(id);
          setScreen("detail");
        }}
        onOpenStore={() => setStoreSheetOpen(true)}
      />
    );
  }
  if (screen === "sell") {
    return (
      <SellFlow
        onClose={() => setScreen("home")}
        onPosted={(id) => {
          setActiveListing(id);
          setScreen("detail");
          load();
        }}
      />
    );
  }
  if (screen === "inbox") {
    return <InboxView onBack={() => setScreen("home")} />;
  }

  const visible = tab === "saved" ? listings.filter((l) => savedIds.has(l.id)) : listings;

  return (
    <div className="max-w-md mx-auto pb-40">
      <ScreenHeader
        title="Marché"
        subtitle="Kipé, Conakry · annonces près de vous"
        onBack={onBack}
        right={
          <div className="flex items-center gap-1">
            <button onClick={() => requireAuth(() => setScreen("mine"))} aria-label="Mes annonces" className="w-10 h-10 rounded-full bg-card border border-border/60 hover:bg-muted flex items-center justify-center">
              <ClipboardList className="w-5 h-5 text-foreground" />
            </button>
            <button onClick={() => requireAuth(() => setScreen("inbox"))} aria-label="Messages" className="w-10 h-10 rounded-full bg-card border border-border/60 hover:bg-muted flex items-center justify-center">
              <MessageSquare className="w-5 h-5 text-foreground" />
            </button>
            <button aria-label="Notifications" className="w-10 h-10 rounded-full bg-card border border-border/60 hover:bg-muted flex items-center justify-center">
              <Bell className="w-5 h-5 text-foreground" />
            </button>
          </div>
        }
      />

      <div className="px-4 mt-3">
        <div className="h-14 flex items-center gap-3 px-4 bg-card rounded-2xl shadow-soft border border-border/60">
          <div className="w-9 h-9 rounded-xl bg-secondary/20 flex items-center justify-center">
            <Search className="w-4 h-4 text-foreground" />
          </div>
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Que cherchez-vous ?"
            className="flex-1 bg-transparent placeholder:text-muted-foreground focus:outline-none text-sm text-foreground"
          />
          {search && (
            <button onClick={() => setSearch("")} aria-label="Effacer">
              <X className="w-4 h-4 text-muted-foreground" />
            </button>
          )}
        </div>
      </div>

      <div className="mt-3">
        <LiveStrip
          stats={[
            { icon: ShoppingBag, label: "120 nouvelles annonces", bg: "bg-secondary/20", tone: "text-foreground" },
            { icon: Timer, label: "Mises à jour en direct", bg: "bg-primary/10", tone: "text-primary" },
            { icon: MapPin, label: "Près de Kipé", bg: "bg-success/10", tone: "text-success" },
          ]}
        />
      </div>

      {/* Merchant acquisition banner — public */}
      <div className="px-4 pt-3">
        <Link
          to="/merchant/apply"
          className="flex items-center gap-3 rounded-2xl card-warm p-3 active:scale-[0.99] transition-transform"
        >
          <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center shrink-0">
            <Store className="w-5 h-5 text-primary" />
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-sm font-semibold text-foreground leading-tight">
              Vous êtes marchand ?
            </p>
            <p className="text-[11px] text-muted-foreground leading-snug">
              Vendez sur CHOPCHOP — créez votre boutique en quelques minutes.
            </p>
          </div>
          <span className="text-[11px] font-semibold text-primary shrink-0">Commencer</span>
        </Link>
      </div>

      <div className="px-4 pt-4 space-y-5">
        {/* Tabs */}
        <div className="flex gap-2">
          <button
            onClick={() => setTab("all")}
            className={`flex-1 py-2.5 rounded-2xl text-sm font-semibold transition ${
              tab === "all" ? "gradient-wallet text-primary-foreground" : "bg-card border border-border text-muted-foreground"
            }`}
          >
            Annonces
          </button>
          <button
            onClick={() => setTab("stores")}
            className={`flex-1 py-2.5 rounded-2xl text-sm font-semibold transition flex items-center justify-center gap-1.5 ${
              tab === "stores" ? "gradient-wallet text-primary-foreground" : "bg-card border border-border text-muted-foreground"
            }`}
          >
            <Store className="w-4 h-4" /> Boutiques
          </button>
          <button
            onClick={() => requireAuth(() => setTab("saved"))}
            className={`flex-1 py-2.5 rounded-2xl text-sm font-semibold transition flex items-center justify-center gap-1.5 ${
              tab === "saved" ? "gradient-wallet text-primary-foreground" : "bg-card border border-border text-muted-foreground"
            }`}
          >
            <Heart className="w-4 h-4" />
            {savedIds.size > 0 && (
              <span className="text-[10px] bg-card text-foreground rounded-full px-1.5 ml-1">
                {savedIds.size}
              </span>
            )}
          </button>
        </div>

        {tab !== "stores" && (
          <section className="pb-1">
            <h2 className="text-sm font-semibold text-foreground mb-4">Catégories</h2>
            <CategoryGrid active={category} onSelect={(id) => setCategory(category === id ? null : id)} />
          </section>
        )}

        {tab !== "stores" && <FeaturedBanners />}

        {tab === "stores" && (
          <section>
            <div className="flex items-center justify-between mb-3">
              <h2 className="text-sm font-semibold text-foreground">Boutiques</h2>
              <button onClick={() => requireAuth(() => setStoreSheetOpen(true))} className="text-xs text-primary font-medium">
                + Créer la mienne
              </button>
            </div>
            {storesLoading ? (
              <LoadingState variant="cards" rows={3} />
            ) : stores.length === 0 ? (
              <MarcheEmpty variant="stores" />
            ) : (
              <div className="space-y-2">
                {stores.map((s) => (
                  <StoreCard
                    key={s.id}
                    store={s}
                    listingCount={s.listing_count}
                    samplePhotos={s.sample_photos}
                    onClick={() => {
                      setActiveStoreId(s.id);
                      setScreen("store");
                    }}
                  />
                ))}
              </div>
            )}
          </section>
        )}

        {tab !== "stores" && (
        <section>
          <div className="flex items-center justify-between mb-3">
            <h2 className="text-sm font-semibold text-foreground">
              {tab === "saved"
                ? "Sauvegardées"
                : category
                  ? categoryLabel(category)
                  : search
                    ? `Résultats : ${search}`
                    : "Près de vous"}
            </h2>
            {tab === "all" && (category || search) && (
              <button
                onClick={() => {
                  setCategory(null);
                  setSearch("");
                }}
                className="text-xs text-primary font-medium"
              >
                Réinitialiser
              </button>
            )}
          </div>

          {/* Sort chips */}
          {tab === "all" && (
            <div className="flex items-center gap-2 mb-3 overflow-x-auto scrollbar-none">
              <span className="flex items-center gap-1 text-[11px] text-muted-foreground shrink-0">
                <ArrowUpDown className="w-3 h-3" /> Trier :
              </span>
              {([
                ["recent", "Récents"],
                ["price_asc", "Prix ↑"],
                ["price_desc", "Prix ↓"],
              ] as const).map(([k, label]) => (
                <button
                  key={k}
                  onClick={() => setSort(k)}
                  className={`shrink-0 px-3 py-1.5 rounded-full text-[11px] font-semibold ${
                    sort === k
                      ? "gradient-wallet text-primary-foreground"
                      : "bg-card border border-border text-muted-foreground"
                  }`}
                >
                  {label}
                </button>
              ))}
            </div>
          )}

          {loading ? (
            <LoadingState variant="cards" rows={2} />
          ) : visible.length === 0 ? (
            <EmptyState
              icon={ShoppingBag}
              title={tab === "saved" ? "Aucune annonce sauvegardée" : "Aucune annonce pour le moment"}
              description={tab === "saved"
                ? "Touchez le cœur sur une annonce pour la retrouver ici."
                : "Soyez le premier à publier dans votre quartier."}
            />
          ) : (
            <div className="grid grid-cols-2 gap-3">
              {visible.flatMap((l, idx) => {
                const card = (
                  <ListingCard key={l.id} l={l} onClick={() => { setActiveListing(l.id); setScreen("detail"); }} />
                );
                // Interleave a reserved promoted slot every ~6 cards (not active ad).
                if (tab === "all" && idx > 0 && (idx + 1) % 6 === 0) {
                  return [card, <PromotedSlot key={`promo-${idx}`} />];
                }
                return [card];
              })}
            </div>
          )}
        </section>
        )}
      </div>

      {/* FAB Sell */}
      <motion.button
        whileTap={{ scale: 0.9 }}
        onClick={() => requireAuth(() => setScreen("sell"))}
        style={{ bottom: "calc(env(safe-area-inset-bottom) + 6.25rem)" }}
        className="fixed right-4 z-40 gradient-primary text-primary-foreground rounded-full px-5 py-3.5 shadow-elevated flex items-center gap-2 font-semibold"
      >
        <Plus className="w-5 h-5" /> Vendre
      </motion.button>

      <StoreOnboardingSheet open={storeSheetOpen} onOpenChange={setStoreSheetOpen} />
    </div>
  );
}