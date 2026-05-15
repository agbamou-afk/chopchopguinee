import { QuickActions } from "@/components/home/QuickActions";
import { MapPin, Home as HomeIcon, Briefcase, Clock, Bike, UtensilsCrossed } from "lucide-react";
import { PromoCarousel } from "@/components/home/PromoCarousel";
import { RestaurantCard } from "@/components/food/RestaurantCard";
import { AppHeader } from "@/components/ui/AppHeader";
import { SmartSearchBar } from "@/components/ui/SmartSearchBar";
import { lazy, Suspense, useEffect, useState } from "react";
import { useWallet } from "@/hooks/useWallet";
import { useAppEnv } from "@/contexts/AppEnvContext";
import { Skeleton } from "@/components/ui/skeleton";
import { PrimaryActionGrid, type PrimaryAction } from "@/components/home/PrimaryActionGrid";
import { WalletHero } from "@/components/home/WalletHero";
import { RecentActivityPeek } from "@/components/activity/RecentActivityPeek";
import { Analytics } from "@/lib/analytics/AnalyticsService";

const NearbyDriversMap = lazy(() => import("@/components/home/NearbyDriversMap"));

interface UserHomeProps {
  onActionClick: (action: string, params?: { destination?: string }) => void;
  onToggleDriverMode: () => void;
}

/** Real popular-restaurants data is wired in a later pass; until then we
 *  intentionally render an empty-state instead of fake listings. */
const popularRestaurants: Array<{
  name: string;
  image: string;
  rating: number;
  deliveryTime: string;
  distance: string;
  category: string;
}> = [];

export function UserHome({ onActionClick, onToggleDriverMode }: UserHomeProps) {
  const { available: walletBalance, loading: walletLoading, error: walletError, wallet } = useWallet("client");
  const { lowDataMode } = useAppEnv();
  const userLocation = "Kaloum";
  const userCoords = { lat: 9.5092, lng: -13.7122 };
  const recents = [
    { icon: HomeIcon, label: "Maison", sub: "Ratoma" },
    { icon: Briefcase, label: "Travail", sub: "Kaloum" },
    { icon: Clock, label: "Madina", sub: "Récent" },
    { icon: Clock, label: "Aéroport", sub: "Récent" },
  ];

  useEffect(() => {
    Analytics.track("home.viewed", { metadata: { location: userLocation } });
  }, []);

  // Calm "welcome back" reassurance line — shows once per day, only after the
  // user has returned (>6h since last seen). No streaks, no gamification.
  const [welcomeBack, setWelcomeBack] = useState(false);
  useEffect(() => {
    try {
      const KEY = "cc:last-home-seen";
      const last = Number(localStorage.getItem(KEY) ?? "0");
      const now = Date.now();
      if (last && now - last > 6 * 3600_000) {
        setWelcomeBack(true);
        Analytics.track("home.welcome_back.viewed", { metadata: { hours_since: Math.round((now - last) / 3600_000) } });
        window.setTimeout(() => setWelcomeBack(false), 6000);
      }
      localStorage.setItem(KEY, String(now));
    } catch {}
  }, []);

  const walletStatus: "active" | "frozen" | "restricted" =
    wallet?.status === "frozen" ? "frozen" : wallet?.status === "restricted" ? "restricted" : "active";

  const handlePrimary = (a: PrimaryAction) => {
    Analytics.track("home.primary_action.clicked", { metadata: { action: a } });
    if (a === "topup") onActionClick("wallet");
    else if (a === "ride") onActionClick("moto");
    else if (a === "order") onActionClick("food");
    else if (a === "market") onActionClick("market");
  };

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
        showWalletCard={false}
      />

      {/* Content */}
      <div className="px-4 mt-4 space-y-6">
        {welcomeBack && (
          <div className="rounded-2xl card-warm px-3 py-2 text-[12px] text-foreground/80 flex items-center gap-2">
            <span className="inline-flex h-1.5 w-1.5 rounded-full bg-primary" />
            Bon retour sur CHOP CHOP — vos services sont prêts à {userLocation}.
          </div>
        )}
        {/* 1 — Wallet hero (trust anchor) */}
        <WalletHero
          balance={walletBalance}
          loading={walletLoading}
          error={walletError}
          status={walletStatus}
          onTopUp={() => handlePrimary("topup")}
          onHistory={() => onActionClick("wallet")}
        />

        {/* 2 — Four primary actions, visible above the fold */}
        <PrimaryActionGrid onAction={handlePrimary} />

        {/* Ecosystem continuity — last operational event */}
        <RecentActivityPeek onSeeAll={() => onActionClick("orders")} />

        {/* 3 — Smart command bar */}
        <SmartSearchBar onAction={onActionClick} location={`${userLocation}, Conakry`} />

        {/* 4 — Services secondaires */}
        <section>
          <div className="flex items-center justify-between mb-2 px-0.5">
            <h2 className="text-[11px] font-semibold uppercase tracking-[0.18em] text-muted-foreground">
              Plus de services
            </h2>
            <span className="text-[11px] text-muted-foreground">À {userLocation}</span>
          </div>
          <div className="card-warm rounded-3xl p-4 relative overflow-hidden">
            <div className="pointer-events-none absolute inset-x-6 top-0 h-px saffron-seam opacity-70" aria-hidden />
            <QuickActions onActionClick={onActionClick} />
          </div>
        </section>

        {/* Nearby drivers — live map preview */}
        <section>
          <div className="flex items-center justify-between mb-2 px-0.5">
            <h2 className="text-[11px] font-semibold uppercase tracking-[0.18em] text-muted-foreground">
              Chauffeurs près de vous
            </h2>
            <button
              onClick={() => onActionClick("moto")}
              className="text-xs font-semibold text-primary"
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
          <h2 className="text-[11px] font-semibold uppercase tracking-[0.18em] text-muted-foreground mb-2 px-0.5">
            Récents
          </h2>
          <div className="flex gap-2 overflow-x-auto pb-1 -mx-4 px-4 scrollbar-none">
            {recents.map((r) => (
              <button
                key={r.label}
                onClick={() => onActionClick("moto")}
                className="shrink-0 flex items-center gap-2 px-3 py-2.5 card-warm rounded-2xl hover:bg-muted/30 transition-colors"
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
          <div className="flex items-center justify-between mb-2 px-0.5">
            <h2 className="text-[11px] font-semibold uppercase tracking-[0.18em] text-muted-foreground">
              Offres spéciales
            </h2>
            <span className="text-[10px] text-muted-foreground">En direct</span>
          </div>
          <PromoCarousel />
        </section>

        {/* Popular restaurants */}
        <section className="pb-28">
          <div className="flex items-center justify-between mb-2 px-0.5">
            <h2 className="text-[11px] font-semibold uppercase tracking-[0.18em] text-muted-foreground">
              Populaire à {userLocation}
            </h2>
            <button 
              onClick={() => onActionClick("food")}
              className="text-xs font-semibold text-primary"
            >
              Voir tout
            </button>
          </div>
          {popularRestaurants.length > 0 ? (
            <div className="grid grid-cols-2 gap-3">
              {popularRestaurants.map((restaurant) => (
                <RestaurantCard
                  key={restaurant.name}
                  {...restaurant}
                  onClick={() => onActionClick("food")}
                />
              ))}
            </div>
          ) : (
            <div className="rounded-3xl card-warm p-6 text-center relative overflow-hidden">
              <div className="pointer-events-none absolute inset-x-8 top-0 h-px saffron-seam opacity-70" aria-hidden />
              <div className="w-14 h-14 mx-auto halo-conakry shadow-card flex items-center justify-center mb-3 relative">
                <UtensilsCrossed className="w-5 h-5 text-primary relative z-10" />
              </div>
              <p className="text-sm font-semibold text-foreground">
                Bientôt disponible à {userLocation}
              </p>
              <p className="text-xs text-muted-foreground mt-1">
                Les restaurants partenaires de votre quartier seront affichés ici dès leur ouverture.
              </p>
              <button
                onClick={() => onActionClick("food")}
                className="mt-4 inline-flex items-center gap-1 text-sm font-semibold text-primary"
              >
                Explorer Repas
              </button>
            </div>
          )}
          <p className="text-center text-[10px] uppercase tracking-[0.22em] text-muted-foreground/80 mt-6">
            CHOP CHOP · Conakry
          </p>
        </section>
      </div>
    </div>
  );
}
