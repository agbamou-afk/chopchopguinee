import { motion, AnimatePresence } from "framer-motion";
import { Search, ChefHat, UtensilsCrossed, AlertCircle } from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { RestaurantCard } from "@/components/food/RestaurantCard";
import { RepasRestaurantDetail } from "@/components/food/RepasRestaurantDetail";
import { ScreenHeader } from "@/components/ui/ScreenHeader";
import { EmptyState } from "@/components/ui/EmptyState";
import { useAuth } from "@/contexts/AuthContext";
import { discoverRestaurants, type RepasDiscoveryRestaurant } from "@/lib/repas/discovery";
import { RestaurantOnboardingSheet } from "@/components/food/RestaurantOnboardingSheet";
import { useMerchantIdentity } from "@/hooks/useMerchantIdentity";

interface FoodViewProps {
  onBack: () => void;
}

export function FoodView({ onBack }: FoodViewProps) {
  const [searchQuery, setSearchQuery] = useState("");
  const [cuisine, setCuisine] = useState<string | null>(null);
  const [active, setActive] = useState<RepasDiscoveryRestaurant | null>(null);
  const [restaurants, setRestaurants] = useState<RepasDiscoveryRestaurant[] | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const { user } = useAuth();
  const { restaurant: ownRestaurant, refresh: refreshMerchant } = useMerchantIdentity();
  const [createOpen, setCreateOpen] = useState(false);

  useEffect(() => {
    let alive = true;
    setRestaurants(null);
    setLoadError(null);
    const t = setTimeout(() => {
      discoverRestaurants(searchQuery, 40)
        .then((r) => {
          if (!alive) return;
          setRestaurants(r);
        })
        .catch(() => {
          if (!alive) return;
          setRestaurants([]);
          setLoadError("Impossible de charger les restaurants pour le moment.");
        });
    }, searchQuery ? 250 : 0);
    return () => {
      alive = false;
      clearTimeout(t);
    };
  }, [searchQuery]);

  const cuisines = useMemo(() => {
    if (!restaurants) return [] as string[];
    return Array.from(
      new Set(restaurants.map((r) => r.cuisine).filter((c): c is string => !!c)),
    ).sort();
  }, [restaurants]);

  const visible = useMemo(() => {
    if (!restaurants) return null;
    const list = cuisine ? restaurants.filter((r) => r.cuisine === cuisine) : restaurants;
    // Server order is preserved; orderable supply simply surfaces first.
    return [...list].sort((a, b) => Number(b.orderable_now) - Number(a.orderable_now));
  }, [restaurants, cuisine]);

  const openCount = visible?.filter((r) => r.orderable_now).length ?? 0;

  return (
    <div className="max-w-md mx-auto">
      <ScreenHeader
        title="Commander un repas"
        subtitle="Restaurants partenaires publiés"
        onBack={onBack}
      />

      <div className="px-4 mt-3 space-y-3">
        {/* Search */}
        <div className="h-14 flex items-center gap-3 px-4 bg-card rounded-2xl shadow-soft border border-border/60">
          <div className="w-9 h-9 rounded-xl bg-[hsl(8_78%_55%/0.12)] flex items-center justify-center">
            <Search className="w-4 h-4 text-[hsl(8_78%_45%)]" />
          </div>
          <input
            type="text"
            placeholder="Rechercher un restaurant, une cuisine, un quartier…"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="flex-1 bg-transparent placeholder:text-muted-foreground focus:outline-none text-sm text-foreground"
          />
        </div>

        {visible !== null && visible.length > 0 && (
          <p className="text-[11px] text-muted-foreground">
            {visible.length} restaurant{visible.length > 1 ? "s" : ""} publié
            {visible.length > 1 ? "s" : ""} · {openCount} accepte
            {openCount > 1 ? "nt" : ""} des commandes maintenant
          </p>
        )}

        {/* R8 — "supply exists but nothing is orderable" is its own truthful state. */}
        {visible !== null && visible.length > 0 && openCount === 0 && (
          <div className="flex items-start gap-2 p-3 rounded-2xl bg-card border border-border text-[11px] text-muted-foreground">
            <AlertCircle className="w-3.5 h-3.5 mt-0.5 shrink-0" />
            <span>Aucun restaurant ouvert actuellement.</span>
          </div>
        )}

        {user && !ownRestaurant && (
          <button
            onClick={() => setCreateOpen(true)}
            className="w-full flex items-center gap-3 p-3 rounded-2xl bg-card border border-border/60 shadow-card text-left hover:bg-muted/40 transition"
          >
            <div className="p-2 rounded-xl bg-primary/10">
              <ChefHat className="w-4 h-4 text-primary" />
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-semibold text-foreground">Créer un restaurant</p>
              <p className="text-[11px] text-muted-foreground">
                Préparez votre menu, l’équipe CHOPCHOP valide la publication.
              </p>
            </div>
            <span className="text-xs text-primary font-medium">Activer</span>
          </button>
        )}

        {/* Cuisine filters — derived from real published supply */}
        {cuisines.length > 0 && (
          <div className="flex items-center gap-2 overflow-x-auto scrollbar-hide -mx-4 px-4">
            <button
              onClick={() => setCuisine(null)}
              className={`shrink-0 px-3 py-1.5 rounded-full text-xs font-semibold transition ${
                cuisine === null
                  ? "gradient-wallet text-primary-foreground"
                  : "bg-card border border-border text-muted-foreground"
              }`}
            >
              Tout
            </button>
            {cuisines.map((c) => (
              <button
                key={c}
                onClick={() => setCuisine(cuisine === c ? null : c)}
                className={`shrink-0 px-3 py-1.5 rounded-full text-xs font-semibold transition ${
                  cuisine === c
                    ? "gradient-wallet text-primary-foreground"
                    : "bg-card border border-border text-muted-foreground"
                }`}
              >
                {c}
              </button>
            ))}
          </div>
        )}
      </div>

      {/* Restaurant list */}
      <div className="px-4 pt-4 pb-28">
        {visible === null ? (
          <div className="grid grid-cols-2 gap-3">
            {[0, 1, 2, 3].map((i) => (
              <div key={i} className="h-44 rounded-2xl bg-muted animate-pulse" />
            ))}
          </div>
        ) : loadError ? (
          <div className="flex items-start gap-2 p-4 rounded-2xl bg-card border border-border text-sm text-muted-foreground">
            <AlertCircle className="w-4 h-4 mt-0.5 shrink-0" />
            <span>{loadError}</span>
          </div>
        ) : visible.length === 0 ? (
          <EmptyState
            icon={UtensilsCrossed}
            title={
              searchQuery || cuisine
                ? "Aucun résultat"
                : "Aucun restaurant disponible pour le moment"
            }
            description={
              searchQuery || cuisine
                ? "Aucun restaurant publié ne correspond à cette recherche."
                : "Les restaurants partenaires seront affichés ici dès leur publication."
            }
          />
        ) : (
          <div className="grid grid-cols-2 gap-3">
            {visible.map((r, index) => (
              <motion.div
                key={r.id}
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: index * 0.05 }}
              >
                <RestaurantCard restaurant={r} onClick={() => setActive(r)} />
              </motion.div>
            ))}
          </div>
        )}
      </div>

      <AnimatePresence>
        {active && (
          <RepasRestaurantDetail restaurant={active} onClose={() => setActive(null)} />
        )}
      </AnimatePresence>
      <RestaurantOnboardingSheet
        open={createOpen}
        onOpenChange={setCreateOpen}
        onCreated={() => refreshMerchant()}
      />
    </div>
  );
}
