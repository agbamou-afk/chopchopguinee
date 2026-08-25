import { Suspense, lazy, useState } from "react";
import { useNavigate } from "react-router-dom";
import { MapPin, Maximize2, Store, X } from "lucide-react";
import { Skeleton } from "@/components/ui/skeleton";
import type { DiscoveryVendor } from "@/lib/locations/useVendorDiscovery";

const ChopContextMap = lazy(() => import("./ChopContextMap"));

interface Props {
  lng: number;
  lat: number;
  userPresent: boolean;
  lowDataMode: boolean;
  showRestaurants: boolean;
  showStores: boolean;
  /** Opens the Repas ordering surface for a given restaurant. */
  onOpenRestaurant: (restaurantId: string) => void;
  onRequestLocation?: () => void;
}

/**
 * Home local-commerce directory map.
 *
 * Law: this surface carries NO ride semantics. Taps never book a ride; pins
 * open the existing public commerce surfaces (`/marche/boutique/:slug` and the
 * existing Repas restaurant detail/ordering flow).
 */
export function LocalCommerceMap({
  lng, lat, userPresent, lowDataMode, showRestaurants, showStores, onOpenRestaurant, onRequestLocation,
}: Props) {
  const navigate = useNavigate();
  const [expanded, setExpanded] = useState(false);

  const handleVendor = (v: DiscoveryVendor) => {
    setExpanded(false);
    if (v.kind === "store") {
      if (v.slug) navigate(`/marche/boutique/${v.slug}`);
      return;
    }
    onOpenRestaurant(v.id);
  };

  return (
    <section data-testid="home-commerce-map">
      <div className="flex items-center justify-between mb-2 px-0.5">
        <h2 className="text-[11px] font-semibold uppercase tracking-[0.18em] text-muted-foreground">
          Commerces près de vous
        </h2>
        <button
          type="button"
          data-testid="commerce-map-expand"
          onClick={() => setExpanded(true)}
          className="inline-flex items-center gap-1 text-xs font-semibold text-primary min-h-[32px] px-1"
        >
          Agrandir
          <Maximize2 className="w-3 h-3" />
        </button>
      </div>

      <div className="relative block w-full h-44 rounded-3xl overflow-hidden shadow-card border border-border/60">
        {lowDataMode ? (
          <div className="absolute inset-0 w-full h-full bg-gradient-to-br from-primary/15 via-muted to-secondary/20 flex items-center justify-center">
            <span className="text-xs font-semibold text-foreground/80">
              Carte désactivée — mode données réduites
            </span>
          </div>
        ) : (
          <Suspense fallback={<Skeleton className="absolute inset-0 w-full h-full" />}>
            <ChopContextMap
              mode="directory"
              lng={lng}
              lat={lat}
              userPresent={userPresent}
              showRestaurants={showRestaurants}
              showStores={showStores}
              onVendorSelect={handleVendor}
            />
          </Suspense>
        )}
        <div className="absolute top-3 left-3 inline-flex items-center gap-1.5 bg-card/95 backdrop-blur rounded-full px-2.5 py-1 shadow-card">
          <Store className="w-3 h-3 text-primary" />
          <span className="text-[11px] font-semibold text-foreground">Autour de vous</span>
        </div>
        {!userPresent && !lowDataMode && (
          <div className="absolute inset-x-3 bottom-3 flex items-center justify-between gap-2 bg-card/95 backdrop-blur rounded-2xl px-3 py-2 shadow-card">
            <div className="flex items-center gap-2 text-left min-w-0">
              <MapPin className="w-3.5 h-3.5 text-amber-600 shrink-0" />
              <div className="min-w-0">
                <p className="text-[11px] font-semibold text-foreground truncate">Position non activée</p>
                <p className="text-[10px] text-muted-foreground truncate">Carte centrée sur Conakry</p>
              </div>
            </div>
            {onRequestLocation && (
              <button
                type="button"
                onClick={onRequestLocation}
                className="text-[11px] font-semibold text-primary shrink-0 px-2 py-1 rounded-full bg-primary/10"
              >
                Activer
              </button>
            )}
          </div>
        )}
      </div>

      {expanded && (
        <div className="fixed inset-0 z-[60] bg-background" data-testid="commerce-map-fullscreen">
          <div className="absolute inset-0">
            <Suspense fallback={<Skeleton className="absolute inset-0 w-full h-full" />}>
              <ChopContextMap
                mode="directory"
                interactive
                zoom={14}
                lng={lng}
                lat={lat}
                userPresent={userPresent}
                showRestaurants={showRestaurants}
                showStores={showStores}
                onVendorSelect={handleVendor}
              />
            </Suspense>
          </div>
          <button
            type="button"
            data-testid="commerce-map-close"
            onClick={() => setExpanded(false)}
            aria-label="Fermer la carte"
            className="absolute top-4 right-4 z-10 inline-flex items-center justify-center w-10 h-10 rounded-full bg-card/95 shadow-card"
          >
            <X className="w-4 h-4" />
          </button>
        </div>
      )}
    </section>
  );
}
