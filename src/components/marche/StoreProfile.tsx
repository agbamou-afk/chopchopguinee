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
      const { data } = await supabase
        .from("marketplace_listings")
        .select("id, title, price_gnf, is_negotiable, is_urgent, delivery_available, neighborhood, commune, created_at, kind, listing_images(url, position)")
        .eq("status", "active")
        .eq("visibility", "public")
        // store_id may not be in generated types; cast through
        .eq("store_id" as never, storeId as never)
        .order("created_at", { ascending: false })
        .limit(60);
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
        cover_url: r.listing_images?.slice().sort((a, b) => a.position - b.position)[0]?.url ?? null,
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