import { useEffect, useState } from "react";
import { Switch } from "@/components/ui/switch";
import { SectionCard } from "./SectionCard";
import { Button } from "@/components/ui/button";
import { toast } from "@/hooks/use-toast";
import {
  listRestaurantMenu,
  listSellerListings,
  setListingAvailability,
  toggleMenuItemAvailable,
} from "@/lib/merchant/operations";

interface Props {
  restaurantId?: string;
  sellerId?: string;
}

export function CatalogSection({ restaurantId, sellerId }: Props) {
  const [items, setItems] = useState<any[]>([]);
  const [listings, setListings] = useState<any[]>([]);

  useEffect(() => {
    (async () => {
      if (restaurantId) setItems(await listRestaurantMenu(restaurantId));
      if (sellerId) setListings(await listSellerListings(sellerId));
    })().catch(() => { /* calm */ });
  }, [restaurantId, sellerId]);

  const toggleItem = async (id: string, v: boolean) => {
    setItems((prev) => prev.map((x) => (x.id === id ? { ...x, is_available: v } : x)));
    try {
      await toggleMenuItemAvailable(id, v);
    } catch (e: any) {
      setItems((prev) => prev.map((x) => (x.id === id ? { ...x, is_available: !v } : x)));
      toast({ title: "Erreur", description: e?.message ?? "Action impossible" });
    }
  };

  const setAvail = async (id: string, av: "available" | "reserved" | "sold") => {
    const before = listings.find((l) => l.id === id)?.availability;
    setListings((prev) => prev.map((x) => (x.id === id ? { ...x, availability: av } : x)));
    try {
      await setListingAvailability(id, av);
    } catch (e: any) {
      setListings((prev) => prev.map((x) => (x.id === id ? { ...x, availability: before } : x)));
      toast({ title: "Erreur", description: e?.message ?? "Action impossible" });
    }
  };

  if (!restaurantId && !sellerId) return null;

  return (
    <SectionCard
      title={restaurantId ? "Menu" : "Mes annonces"}
      hint={restaurantId ? "Disponibilité des plats" : "Disponibilité des articles"}
    >
      {restaurantId && (
        <div className="divide-y divide-border/40">
          {items.length === 0 && <p className="text-sm text-muted-foreground">Aucun plat.</p>}
          {items.map((it) => (
            <div key={it.id} className="flex items-center justify-between py-2 gap-3">
              <div className="min-w-0">
                <p className="text-sm font-semibold text-foreground truncate">{it.name}</p>
                <p className="text-xs text-muted-foreground">{Number(it.price_gnf).toLocaleString("fr-FR")} GNF</p>
              </div>
              <Switch checked={!!it.is_available} onCheckedChange={(v) => toggleItem(it.id, v)} />
            </div>
          ))}
        </div>
      )}
      {sellerId && (
        <div className="space-y-2">
          {listings.length === 0 && <p className="text-sm text-muted-foreground">Aucune annonce.</p>}
          {listings.map((l) => (
            <div key={l.id} className="rounded-xl bg-muted/40 border border-border/50 p-3">
              <div className="flex items-center justify-between gap-2">
                <p className="text-sm font-semibold text-foreground truncate flex-1">{l.title}</p>
                <span className="text-xs text-muted-foreground capitalize">{l.availability}</span>
              </div>
              <div className="flex gap-2 mt-2">
                <Button size="sm" variant={l.availability === "available" || l.availability === "to_confirm" ? "default" : "outline"} className="flex-1" onClick={() => setAvail(l.id, "available")}>
                  Disponible
                </Button>
                <Button size="sm" variant={l.availability === "reserved" ? "default" : "outline"} className="flex-1" onClick={() => setAvail(l.id, "reserved")}>
                  Réservé
                </Button>
                <Button size="sm" variant={l.availability === "sold" ? "default" : "outline"} className="flex-1" onClick={() => setAvail(l.id, "sold")}>
                  Vendu
                </Button>
              </div>
            </div>
          ))}
        </div>
      )}
    </SectionCard>
  );
}