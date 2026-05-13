import { useEffect, useState, useCallback } from "react";
import { motion } from "framer-motion";
import { ArrowLeft, Search, MapPin, Bell, Plus, MessageSquare, X, Heart, ArrowUpDown } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { CategoryGrid } from "@/components/marche/CategoryGrid";
import { FeaturedBanners } from "@/components/marche/FeaturedBanners";
import { ListingCard, type ListingCardData } from "@/components/marche/ListingCard";
import { ListingDetail } from "@/components/marche/ListingDetail";
import { SellFlow } from "@/components/marche/SellFlow";
import { InboxView } from "@/components/marche/InboxView";
import { categoryLabel } from "@/lib/marche";
import { useAuthGuard } from "@/hooks/useAuthGuard";

interface MarketViewProps {
  onBack: () => void;
}

type Screen = "home" | "detail" | "sell" | "inbox";
type SortKey = "recent" | "price_asc" | "price_desc";
type Tab = "all" | "saved";

interface RawListing extends Omit<ListingCardData, "cover_url"> {
  listing_images?: { url: string; position: number }[];
}

export function MarketView({ onBack }: MarketViewProps) {
  const [screen, setScreen] = useState<Screen>("home");
  const [activeListing, setActiveListing] = useState<string | null>(null);
  const [category, setCategory] = useState<string | null>(null);
  const [search, setSearch] = useState("");
  const [listings, setListings] = useState<ListingCardData[]>([]);
  const [loading, setLoading] = useState(true);
  const [sort, setSort] = useState<SortKey>("recent");
  const [tab, setTab] = useState<Tab>("all");
  const [savedIds, setSavedIds] = useState<Set<string>>(new Set());
  const { requireAuth } = useAuthGuard();

  const load = useCallback(async () => {
    setLoading(true);
    let q = supabase
      .from("marketplace_listings")
      .select(
        "id, title, price_gnf, is_negotiable, is_urgent, delivery_available, neighborhood, commune, created_at, kind, listing_images(url, position)"
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
      cover_url:
        r.listing_images?.slice().sort((a, b) => a.position - b.position)[0]?.url ?? null,
    }));
    setListings(mapped);
    setLoading(false);
  }, [category, search, sort]);

  useEffect(() => {
    load();
  }, [load]);

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
    <div className="max-w-md mx-auto pb-24">
      {/* Header */}
      <header className="bg-card px-4 pt-6 pb-4 sticky top-0 z-30 shadow-card">
        <div className="flex items-center justify-between mb-3">
          <button onClick={onBack} className="p-2 -ml-2 rounded-full hover:bg-muted">
            <ArrowLeft className="w-5 h-5 text-foreground" />
          </button>
          <div className="text-center flex-1">
            <h1 className="text-lg font-bold text-foreground">Marché</h1>
            <div className="flex items-center justify-center gap-1 text-[11px] text-muted-foreground">
              <MapPin className="w-3 h-3 text-primary" />
              <span>Kipé, Conakry</span>
            </div>
          </div>
          <div className="flex items-center gap-1">
            <button onClick={() => requireAuth(() => setScreen("inbox"))} className="p-2 rounded-full hover:bg-muted relative">
              <MessageSquare className="w-5 h-5" />
            </button>
            <button className="p-2 rounded-full hover:bg-muted">
              <Bell className="w-5 h-5" />
            </button>
          </div>
        </div>

        <div className="flex items-center gap-2 bg-muted rounded-2xl px-4 py-3">
          <Search className="w-5 h-5 text-muted-foreground shrink-0" />
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Que cherchez-vous ?"
            className="flex-1 bg-transparent placeholder:text-muted-foreground focus:outline-none text-sm text-foreground"
          />
          {search && (
            <button onClick={() => setSearch("")}>
              <X className="w-4 h-4 text-muted-foreground" />
            </button>
          )}
        </div>
      </header>

      <div className="px-4 pt-4 space-y-5">
        {/* Tabs */}
        <div className="flex gap-2">
          <button
            onClick={() => setTab("all")}
            className={`flex-1 py-2 rounded-xl text-sm font-medium transition ${
              tab === "all" ? "bg-primary text-primary-foreground" : "bg-muted text-muted-foreground"
            }`}
          >
            Toutes les annonces
          </button>
          <button
            onClick={() => requireAuth(() => setTab("saved"))}
            className={`flex-1 py-2 rounded-xl text-sm font-medium transition flex items-center justify-center gap-1.5 ${
              tab === "saved" ? "bg-primary text-primary-foreground" : "bg-muted text-muted-foreground"
            }`}
          >
            <Heart className="w-4 h-4" /> Sauvegardées
            {savedIds.size > 0 && (
              <span className="text-[10px] bg-card text-foreground rounded-full px-1.5 ml-1">
                {savedIds.size}
              </span>
            )}
          </button>
        </div>

        <section>
          <h2 className="text-sm font-semibold text-foreground mb-3">Catégories</h2>
          <CategoryGrid active={category} onSelect={(id) => setCategory(category === id ? null : id)} />
        </section>

        <FeaturedBanners />

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
                  className={`shrink-0 px-3 py-1 rounded-full text-[11px] font-medium ${
                    sort === k
                      ? "bg-primary text-primary-foreground"
                      : "bg-muted text-muted-foreground"
                  }`}
                >
                  {label}
                </button>
              ))}
            </div>
          )}

          {loading ? (
            <div className="grid grid-cols-2 gap-3">
              {Array.from({ length: 4 }).map((_, i) => (
                <div key={i} className="aspect-square rounded-2xl bg-muted animate-pulse" />
              ))}
            </div>
          ) : visible.length === 0 ? (
            <div className="bg-card rounded-2xl p-8 text-center text-muted-foreground shadow-card">
              <p className="font-medium">
                {tab === "saved"
                  ? "Aucune annonce sauvegardée."
                  : "Aucune annonce pour le moment."}
              </p>
              <p className="text-xs mt-1">
                {tab === "saved"
                  ? "Touchez le cœur sur une annonce pour la retrouver ici."
                  : "Soyez le premier à publier dans votre quartier."}
              </p>
            </div>
          ) : (
            <div className="grid grid-cols-2 gap-3">
              {visible.map((l) => (
                <ListingCard key={l.id} l={l} onClick={() => { setActiveListing(l.id); setScreen("detail"); }} />
              ))}
            </div>
          )}
        </section>
      </div>

      {/* FAB Sell */}
      <motion.button
        whileTap={{ scale: 0.9 }}
        onClick={() => requireAuth(() => setScreen("sell"))}
        className="fixed bottom-24 right-4 z-40 gradient-primary text-primary-foreground rounded-full px-5 py-3.5 shadow-elevated flex items-center gap-2 font-semibold"
      >
        <Plus className="w-5 h-5" /> Vendre
      </motion.button>
    </div>
  );
}