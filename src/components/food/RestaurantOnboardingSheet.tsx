import { useEffect, useState } from "react";
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription } from "@/components/ui/sheet";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { Button } from "@/components/ui/button";
import { DISTRICTS } from "@/lib/marche";
import { createOrUpdateRestaurant, getOwnRestaurant } from "@/lib/repas/restaurants";
import type { FoodRestaurant } from "@/lib/repas/types";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "@/hooks/use-toast";

const CUISINES = ["Cuisine locale", "Grillades", "Fast food", "Boissons", "Pâtisserie", "Petit-déj"];

export function RestaurantOnboardingSheet({
  open,
  onOpenChange,
  onCreated,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  onCreated?: (r: FoodRestaurant) => void;
}) {
  const [name, setName] = useState("");
  const [cuisine, setCuisine] = useState<string>("");
  const [district, setDistrict] = useState<string>("");
  const [delivery, setDelivery] = useState(false);
  const [choppay, setWONGO Pay] = useState(false);
  const [busy, setBusy] = useState(false);
  const [existing, setExisting] = useState<FoodRestaurant | null>(null);

  useEffect(() => {
    if (!open) return;
    (async () => {
      const { data } = await supabase.auth.getSession();
      const uid = data.session?.user.id;
      if (!uid) return;
      const own = await getOwnRestaurant(uid);
      if (own) {
        setExisting(own);
        setName(own.name);
        setCuisine(own.cuisine ?? "");
        setDistrict(own.district ?? "");
        setDelivery(own.delivery_available);
        setWONGO Pay(own.choppay_enabled);
      }
    })();
  }, [open]);

  const submit = async () => {
    if (name.trim().length < 2) {
      toast({ title: "Nom requis", description: "Entrez le nom de votre restaurant." });
      return;
    }
    setBusy(true);
    const { data: sess } = await supabase.auth.getSession();
    const uid = sess.session?.user.id;
    if (!uid) {
      setBusy(false);
      toast({ title: "Connexion requise" });
      return;
    }
    try {
      const r = await createOrUpdateRestaurant({
        ownerUserId: uid,
        name: name.trim(),
        cuisine: cuisine || null,
        district: district || null,
        delivery_available: delivery,
        choppay_enabled: choppay,
      });
      toast({ title: existing ? "Restaurant mis à jour" : "Restaurant créé" });
      onCreated?.(r);
      onOpenChange(false);
    } catch (e) {
      const msg = e instanceof Error ? e.message : "Erreur";
      toast({ title: "Erreur", description: msg });
    } finally {
      setBusy(false);
    }
  };

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="bottom" className="rounded-t-3xl max-h-[90vh] overflow-y-auto">
        <SheetHeader className="text-left">
          <SheetTitle>{existing ? "Modifier mon restaurant" : "Créer un restaurant"}</SheetTitle>
          <SheetDescription className="text-xs">
            Configuration rapide. Vous pourrez ajouter votre menu après.
          </SheetDescription>
        </SheetHeader>
        <div className="space-y-3 mt-4">
          <div>
            <label className="text-xs font-medium text-foreground">Nom du restaurant</label>
            <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="Ex : Chez Mama Fatoumata" maxLength={80} />
          </div>
          <div>
            <label className="text-xs font-medium text-foreground">Type de cuisine</label>
            <div className="flex gap-2 flex-wrap mt-1">
              {CUISINES.map((c) => (
                <button
                  key={c}
                  type="button"
                  onClick={() => setCuisine(cuisine === c ? "" : c)}
                  className={`px-3 py-1.5 rounded-full text-xs border ${
                    cuisine === c ? "bg-primary text-primary-foreground border-primary" : "bg-card border-border text-muted-foreground"
                  }`}
                >
                  {c}
                </button>
              ))}
            </div>
          </div>
          <div>
            <label className="text-xs font-medium text-foreground">Quartier / Commune</label>
            <div className="flex gap-2 flex-wrap mt-1">
              {DISTRICTS.map((d) => (
                <button
                  key={d}
                  type="button"
                  onClick={() => setDistrict(district === d ? "" : d)}
                  className={`px-3 py-1.5 rounded-full text-xs border ${
                    district === d ? "bg-primary text-primary-foreground border-primary" : "bg-card border-border text-muted-foreground"
                  }`}
                >
                  {d}
                </button>
              ))}
            </div>
          </div>
          <label className="flex items-center justify-between p-3 rounded-2xl bg-card shadow-card">
            <div>
              <p className="text-sm font-medium">Livraison CHOP disponible</p>
              <p className="text-[11px] text-muted-foreground">Activez pour recevoir des commandes en livraison.</p>
            </div>
            <Switch checked={delivery} onCheckedChange={setDelivery} />
          </label>
          <label className="flex items-center justify-between p-3 rounded-2xl bg-card shadow-card">
            <div>
              <p className="text-sm font-medium">WONGO Pay accepté</p>
              <p className="text-[11px] text-muted-foreground">Affiche un badge WONGO Pay sur votre restaurant.</p>
            </div>
            <Switch checked={choppay} onCheckedChange={setWONGO Pay} />
          </label>
          <Button onClick={submit} disabled={busy} className="w-full">
            {busy ? "Enregistrement…" : existing ? "Mettre à jour" : "Créer mon restaurant"}
          </Button>
        </div>
      </SheetContent>
    </Sheet>
  );
}