import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { StoreHeader } from "./StoreHeader";
import { ListingCard, type ListingCardData } from "./ListingCard";
import { MarcheEmpty } from "./MarcheEmpty";
import { LoadingState } from "@/components/ui/LoadingState";
import { getStoreById, type MerchantStore } from "@/lib/marche/stores";

interface RawListing extends Omit<ListingCardData, "cover_url"> {
  listing_images?: { url: string; position: number }[];
}

export function StoreProfile({
  storeId,
  onBack,
  onOpenListing,
}: {
  storeId: string;
  onBack: () => void;
  onOpenListing: (id: string) => void;
}) {
  const [store, setStore] = useState<MerchantStore | null>(null);
  const [listings, setListings] = useState<ListingCardData[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let alive = true;
    (async () => {
      setLoading(true);
      const s = await getStoreById(storeId);
      if (!alive) return;
      setStore(s);
      const { data } = await (
        supabase as unknown as {
          rpc: (n: string, a: Record<string, unknown>) => Promise<{ data: unknown }>;
        }
      ).rpc("marche_listings_discover", {
        p_search: null,
        p_category: null,
        p_store_id: storeId,
        p_sort: "recent",
        p_limit: 60,
        p_offset: 0,
      });
      if (!alive) return;
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
        cover_url: (r as unknown as { cover_url?: string | null }).cover_url ?? null,
      }));
      setListings(mapped);
      setLoading(false);
    })();
    return () => {
      alive = false;
    };
  }, [storeId]);

  if (loading || !store) {
    return (
      <div className="max-w-md mx-auto pb-24">
        <LoadingState variant="cards" rows={3} />
      </div>
    );
  }

  return (
    <div className="max-w-md mx-auto pb-24 bg-background min-h-screen">
      <StoreHeader store={store} listingCount={listings.length} onBack={onBack} />
      <div className="px-4 mt-5">
        <h2 className="text-sm font-semibold mb-3">Annonces de la boutique</h2>
        {listings.length === 0 ? (
          <MarcheEmpty variant="listings" />
        ) : (
          <div className="grid grid-cols-2 gap-3">
            {listings.map((l) => (
              <ListingCard key={l.id} l={l} onClick={() => onOpenListing(l.id)} />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}