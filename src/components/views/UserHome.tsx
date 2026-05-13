import { QuickActions } from "@/components/home/QuickActions";
import { MapPin, Home as HomeIcon, Briefcase, Clock, Users, Timer, ShoppingBag, ShieldCheck, Bike } from "lucide-react";
import { PromoCarousel } from "@/components/home/PromoCarousel";
import { RestaurantCard } from "@/components/food/RestaurantCard";
import { AppHeader } from "@/components/ui/AppHeader";
import { SmartSearchBar } from "@/components/ui/SmartSearchBar";
import { motion } from "framer-motion";
import { lazy, Suspense } from "react";
import { useWallet } from "@/hooks/useWallet";
import { useAppEnv } from "@/contexts/AppEnvContext";
import { Skeleton } from "@/components/ui/skeleton";

const NearbyDriversMap = lazy(() => import("@/components/home/NearbyDriversMap"));

interface UserHomeProps {
  onActionClick: (action: string, params?: { destination?: string }) => void;
  onToggleDriverMode: () => void;
}

const popularRestaurants = [
  {
    name: "Chez Mama Fatoumata",
    image: "https://images.unsplash.com/photo-1555939594-58d7cb561ad1?w=400&h=300&fit=crop",
    rating: 4.8,
    deliveryTime: "20-30 min",
    distance: "1.2 km",
    category: "Cuisine locale",
  },
  {
    name: "Grillades du Port",
    image: "https://images.unsplash.com/photo-1544025162-d76694265947?w=400&h=300&fit=crop",
    rating: 4.6,
    deliveryTime: "25-35 min",
    distance: "2.1 km",
    category: "Grillades",
  },
];

export function UserHome({ onActionClick, onToggleDriverMode }: UserHomeProps) {
  const { available: walletBalance, loading: walletLoading } = useWallet("client");
  const { lowDataMode } = useAppEnv();
  const userLocation = "Kaloum";
  const userCoords = { lat: 9.5092, lng: -13.7122 };
  const recents = [
    { icon: HomeIcon, label: "Maison", sub: "Ratoma" },
    { icon: Briefcase, label: "Travail", sub: "Kaloum" },
    { icon: Clock, label: "Madina", sub: "Récent" },
    { icon: Clock, label: "Aéroport", sub: "Récent" },
  ];
  const liveStats = [
    { icon: Users, label: "24 chauffeurs actifs", tone: "text-primary", bg: "bg-primary/10" },
    { icon: Timer, label: "Livraison en 15 min", tone: "text-[hsl(8_78%_45%)]", bg: "bg-[hsl(8_78%_55%/0.10)]" },
    { icon: ShoppingBag, label: "120 nouvelles annonces", tone: "text-foreground", bg: "bg-secondary/20" },
    { icon: ShieldCheck, label: "Paiements sécurisés", tone: "text-primary", bg: "bg-primary/10" },
  ];
  return (
    <div className="max-w-md mx-auto">
      <AppHeader
        isDriverMode={false}
        onToggleDriverMode={onToggleDriverMode}
        amountLabel="Solde portefeuille"
        amountValue={walletBalance}
        amountLoading={walletLoading}
        notificationCount={1}
        onAmountClick={() => onActionClick("send")}
        onRecharge={() => onActionClick("send")}
        location={`${userLocation}, Conakry`}
      />

      {/* Content */}
      <div className="px-4 mt-5 space-y-6">
        {/* Universal search — dynamic, inviting */}
        <SmartSearchBar onAction={onActionClick} location={`${userLocation}, Conakry`} />

        {/* Live system pulse — ecosystem gravity */}
        <div className="flex gap-2 overflow-x-auto scrollbar-hide -mx-4 px-4">
          {liveStats.map((s) => (
            <motion.div
              key={s.label}
              initial={{ opacity: 0, y: 8 }}
              animate={{ opacity: 1, y: 0 }}
              className={`shrink-0 inline-flex items-center gap-2 ${s.bg} rounded-full pl-2 pr-3 py-1.5`}
            >
              <span className="relative flex h-1.5 w-1.5">
                <span className="absolute inline-flex h-full w-full rounded-full bg-success opacity-70 pulse-dot" />
                <span className="relative inline-flex rounded-full h-1.5 w-1.5 bg-success" />
              </span>
              <s.icon className={`w-3.5 h-3.5 ${s.tone}`} />
              <span className="text-[11px] font-semibold text-foreground whitespace-nowrap">{s.label}</span>
            </motion.div>
          ))}
        </div>

        {/* Quick Actions */}
        <section>
          <div className="flex items-end justify-between mb-3">
            <div>
              <h2 className="text-lg font-bold text-foreground leading-tight">Services</h2>
              <p className="text-xs text-muted-foreground">Connecté à votre ville</p>
            </div>
          </div>
          <div className="bg-card rounded-3xl shadow-card p-4 border border-border/60">
            <QuickActions onActionClick={onActionClick} />
          </div>
        </section>

        {/* Nearby drivers — live map preview */}
        <section>
          <div className="flex items-end justify-between mb-3">
            <div>
              <h2 className="text-lg font-bold text-foreground leading-tight">Chauffeurs près de vous</h2>
              <p className="text-xs text-muted-foreground">Mis à jour en temps réel</p>
            </div>
            <button
              onClick={() => onActionClick("moto")}
              className="text-sm font-semibold text-primary"
            >
              Réserver
            </button>
          </div>
          <button
            type="button"
            onClick={() => onActionClick("moto")}
            className="relative block w-full h-44 rounded-3xl overflow-hidden shadow-card border border-border/60 active:scale-[0.99] transition-transform"
            aria-label="Voir les chauffeurs disponibles"
          >
            {lowDataMode ? (
              <div className="absolute inset-0 w-full h-full bg-gradient-to-br from-primary/15 via-muted to-secondary/20 flex items-center justify-center">
                <span className="text-xs font-semibold text-foreground/80">Carte désactivée — mode données réduites</span>
              </div>
            ) : (
              <Suspense fallback={<Skeleton className="absolute inset-0 w-full h-full" />}>
                <NearbyDriversMap lng={userCoords.lng} lat={userCoords.lat} />
              </Suspense>
            )}
            <div className="absolute top-3 left-3 inline-flex items-center gap-1.5 bg-card/95 backdrop-blur rounded-full px-2.5 py-1 shadow-card">
              <span className="relative flex h-1.5 w-1.5">
                <span className="absolute inline-flex h-full w-full rounded-full bg-success opacity-70 pulse-dot" />
                <span className="relative inline-flex rounded-full h-1.5 w-1.5 bg-success" />
              </span>
              <Bike className="w-3 h-3 text-primary" />
              <span className="text-[11px] font-semibold text-foreground">En direct</span>
            </div>
          </button>
        </section>

        {/* Recent destinations */}
        <section>
          <h2 className="text-lg font-bold text-foreground mb-3">Récents</h2>
          <div className="flex gap-2 overflow-x-auto pb-1 -mx-4 px-4 scrollbar-none">
            {recents.map((r) => (
              <button
                key={r.label}
                onClick={() => onActionClick("moto")}
                className="shrink-0 flex items-center gap-2 px-3 py-2.5 bg-card rounded-2xl shadow-card hover:bg-muted/50 transition-colors"
              >
                <div className="w-8 h-8 rounded-full bg-primary/10 flex items-center justify-center">
                  <r.icon className="w-4 h-4 text-primary" />
                </div>
                <div className="text-left">
                  <p className="text-sm font-medium text-foreground leading-tight">{r.label}</p>
                  <p className="text-[10px] text-muted-foreground leading-tight font-light">{r.sub}</p>
                </div>
              </button>
            ))}
          </div>
        </section>

        {/* Promos */}
        <section>
          <div className="flex items-end justify-between mb-3">
            <h2 className="text-lg font-bold text-foreground leading-tight">Offres spéciales</h2>
            <span className="text-[11px] text-muted-foreground">Mises à jour en direct</span>
          </div>
          <PromoCarousel />
        </section>

        {/* Popular restaurants */}
        <section className="pb-6">
          <div className="flex items-center justify-between mb-4">
            <div>
              <h2 className="text-lg font-bold text-foreground leading-tight">Populaire à {userLocation}</h2>
              <div className="flex items-center gap-1 text-xs text-muted-foreground mt-0.5">
                <MapPin className="w-3 h-3 text-primary" />
                <span>Livraison rapide aujourd'hui · près de vous</span>
              </div>
            </div>
            <button 
              onClick={() => onActionClick("food")}
              className="text-sm font-semibold text-primary"
            >
              Voir tout
            </button>
          </div>
          <div className="grid grid-cols-2 gap-3">
            {popularRestaurants.map((restaurant) => (
              <RestaurantCard
                key={restaurant.name}
                {...restaurant}
                onClick={() => onActionClick("food")}
              />
            ))}
          </div>
          <p className="text-center text-[11px] text-muted-foreground mt-5">
            CHOP CHOP · Partout à Conakry, services près de vous
          </p>
        </section>
      </div>
    </div>
  );
}
