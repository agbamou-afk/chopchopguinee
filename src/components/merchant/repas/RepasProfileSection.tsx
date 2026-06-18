import { useRef, useState } from "react";
import { ImagePlus, Loader2 } from "lucide-react";
import { SectionCard } from "../SectionCard";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { toast } from "@/hooks/use-toast";
import {
  updateRestaurantProfile,
  uploadRestaurantImage,
} from "@/lib/repas/merchantOps";
import type { FoodRestaurant } from "@/lib/repas/types";

interface Props {
  restaurant: FoodRestaurant;
  ownerUserId: string;
  onChanged: () => void | Promise<void>;
}

export function RepasProfileSection({ restaurant, ownerUserId, onChanged }: Props) {
  const [name, setName] = useState(restaurant.name);
  const [cuisine, setCuisine] = useState(restaurant.cuisine ?? "");
  const [district, setDistrict] = useState(restaurant.district ?? "");
  const [prep, setPrep] = useState(String(restaurant.prep_time_min ?? 20));
  const [delivery, setDelivery] = useState(restaurant.delivery_available);
  const [pickup, setPickup] = useState(restaurant.pickup_available);
  const [saving, setSaving] = useState(false);
  const [uploading, setUploading] = useState<"avatar" | "cover" | null>(null);
  const avatarRef = useRef<HTMLInputElement>(null);
  const coverRef = useRef<HTMLInputElement>(null);

  const save = async () => {
    const prepNum = Number(prep);
    setSaving(true);
    try {
      await updateRestaurantProfile(restaurant.id, {
        name: name.trim() || restaurant.name,
        cuisine: cuisine.trim() || null,
        district: district.trim() || null,
        prep_time_min: Number.isFinite(prepNum) && prepNum > 0 ? prepNum : 20,
        delivery_available: delivery,
        pickup_available: pickup,
      });
      toast({ title: "Profil enregistré" });
      await onChanged();
    } catch (e: any) {
      toast({ title: "Erreur", description: e?.message ?? "Action impossible." });
    } finally {
      setSaving(false);
    }
  };

  const upload = async (file: File, kind: "avatar" | "cover") => {
    setUploading(kind);
    try {
      await uploadRestaurantImage({
        ownerUserId,
        restaurantId: restaurant.id,
        file,
        kind,
      });
      toast({ title: "Image enregistrée" });
      await onChanged();
    } catch (e: any) {
      toast({ title: "Erreur", description: e?.message ?? "Téléversement impossible." });
    } finally {
      setUploading(null);
    }
  };

  return (
    <SectionCard title="Profil restaurant" hint="Informations visibles par les clients">
      <div className="space-y-3">
        <div className="rounded-xl overflow-hidden border border-border/50 bg-muted/30">
          <button
            onClick={() => coverRef.current?.click()}
            className="relative block w-full h-28 bg-muted"
          >
            {restaurant.cover_url ? (
              <img
                src={restaurant.cover_url}
                alt=""
                className="w-full h-full object-cover"
              />
            ) : (
              <div className="w-full h-full flex items-center justify-center text-xs text-muted-foreground">
                Ajouter une bannière
              </div>
            )}
            <div className="absolute bottom-1.5 right-1.5 bg-background/90 rounded-full p-1.5 shadow">
              {uploading === "cover" ? (
                <Loader2 className="w-3.5 h-3.5 animate-spin" />
              ) : (
                <ImagePlus className="w-3.5 h-3.5" />
              )}
            </div>
          </button>
          <div className="flex items-center gap-3 p-3">
            <button
              onClick={() => avatarRef.current?.click()}
              className="relative w-14 h-14 rounded-full bg-muted overflow-hidden border border-border/60 shrink-0"
            >
              {restaurant.avatar_url ? (
                <img
                  src={restaurant.avatar_url}
                  alt=""
                  className="w-full h-full object-cover"
                />
              ) : (
                <div className="w-full h-full flex items-center justify-center text-[10px] text-muted-foreground">
                  Logo
                </div>
              )}
              <div className="absolute bottom-0 right-0 bg-background/90 rounded-full p-1 shadow">
                {uploading === "avatar" ? (
                  <Loader2 className="w-3 h-3 animate-spin" />
                ) : (
                  <ImagePlus className="w-3 h-3" />
                )}
              </div>
            </button>
            <p className="text-xs text-muted-foreground">
              Logo et bannière (JPEG/PNG/WebP, 5 Mo max).
            </p>
          </div>
          <input
            ref={avatarRef}
            type="file"
            accept="image/jpeg,image/png,image/webp"
            className="hidden"
            onChange={(e) => {
              const f = e.target.files?.[0];
              if (f) upload(f, "avatar");
              e.currentTarget.value = "";
            }}
          />
          <input
            ref={coverRef}
            type="file"
            accept="image/jpeg,image/png,image/webp"
            className="hidden"
            onChange={(e) => {
              const f = e.target.files?.[0];
              if (f) upload(f, "cover");
              e.currentTarget.value = "";
            }}
          />
        </div>

        <div>
          <Label className="text-xs">Nom du restaurant</Label>
          <Input value={name} onChange={(e) => setName(e.target.value)} maxLength={80} />
        </div>
        <div className="grid grid-cols-2 gap-2">
          <div>
            <Label className="text-xs">Cuisine</Label>
            <Input
              value={cuisine}
              onChange={(e) => setCuisine(e.target.value)}
              placeholder="Guinéenne, grillades…"
              maxLength={60}
            />
          </div>
          <div>
            <Label className="text-xs">Quartier</Label>
            <Input
              value={district}
              onChange={(e) => setDistrict(e.target.value)}
              placeholder="Kipé"
              maxLength={60}
            />
          </div>
        </div>
        <div>
          <Label className="text-xs">Temps de préparation moyen (min)</Label>
          <Input
            inputMode="numeric"
            value={prep}
            onChange={(e) => setPrep(e.target.value.replace(/[^\d]/g, ""))}
            placeholder="25"
          />
        </div>
        <div className="flex items-center justify-between rounded-xl bg-muted/40 px-3 py-2">
          <div>
            <p className="text-sm font-medium">Retrait sur place</p>
            <p className="text-[11px] text-muted-foreground">Les clients viennent chercher.</p>
          </div>
          <Switch checked={pickup} onCheckedChange={setPickup} />
        </div>
        <div className="flex items-center justify-between rounded-xl bg-muted/40 px-3 py-2">
          <div>
            <p className="text-sm font-medium">Livraison disponible</p>
            <p className="text-[11px] text-muted-foreground">
              Un coursier CHOP est dispatché si possible.
            </p>
          </div>
          <Switch checked={delivery} onCheckedChange={setDelivery} />
        </div>
        <Button onClick={save} disabled={saving} className="w-full">
          {saving ? "Enregistrement…" : "Enregistrer le profil"}
        </Button>
      </div>
    </SectionCard>
  );
}