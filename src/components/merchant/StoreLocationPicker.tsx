import { useState } from "react";
import { MapPin, Locate, Loader2, Check } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { toast } from "@/hooks/use-toast";

export type StoreLocation = {
  lat: number;
  lng: number;
  district?: string | null;
  address_label?: string | null;
  landmark?: string | null;
  location_source: "current_location" | "manual_pin";
  location_accuracy_m?: number | null;
};

type Props = {
  value: StoreLocation | null;
  onChange: (loc: StoreLocation) => void;
};

export function StoreLocationPicker({ value, onChange }: Props) {
  const [busy, setBusy] = useState(false);
  const [manual, setManual] = useState(false);
  const [lat, setLat] = useState(value?.lat?.toString() ?? "");
  const [lng, setLng] = useState(value?.lng?.toString() ?? "");
  const [district, setDistrict] = useState(value?.district ?? "");
  const [landmark, setLandmark] = useState(value?.landmark ?? "");

  const useCurrent = () => {
    if (!("geolocation" in navigator)) {
      toast({ title: "Indisponible", description: "Géolocalisation non disponible sur cet appareil." });
      setManual(true);
      return;
    }
    setBusy(true);
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setBusy(false);
        const loc: StoreLocation = {
          lat: pos.coords.latitude,
          lng: pos.coords.longitude,
          location_source: "current_location",
          location_accuracy_m: pos.coords.accuracy ?? null,
          district: district || null,
          landmark: landmark || null,
          address_label: null,
        };
        setLat(loc.lat.toString());
        setLng(loc.lng.toString());
        onChange(loc);
        toast({ title: "Position enregistrée", description: "Position actuelle utilisée comme emplacement de la boutique." });
      },
      (err) => {
        setBusy(false);
        toast({
          title: "Position refusée",
          description: "Autorisez la géolocalisation ou choisissez l'emplacement manuellement.",
        });
        setManual(true);
      },
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 },
    );
  };

  const saveManual = () => {
    const la = Number(lat);
    const ln = Number(lng);
    if (!Number.isFinite(la) || !Number.isFinite(ln) || Math.abs(la) > 90 || Math.abs(ln) > 180) {
      toast({ title: "Coordonnées invalides", description: "Entrez des coordonnées GPS valides." });
      return;
    }
    onChange({
      lat: la,
      lng: ln,
      location_source: "manual_pin",
      district: district || null,
      landmark: landmark || null,
      address_label: null,
    });
    toast({ title: "Position enregistrée" });
  };

  return (
    <div className="space-y-3 rounded-2xl border border-border/60 p-3 bg-card">
      <div className="flex items-center gap-2">
        <MapPin className="w-4 h-4 text-primary" />
        <p className="text-sm font-semibold text-foreground">Emplacement de la boutique</p>
      </div>
      <div className="grid grid-cols-1 gap-2">
        <Button type="button" variant="outline" onClick={useCurrent} disabled={busy} className="w-full justify-start">
          {busy ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <Locate className="w-4 h-4 mr-2" />}
          Utiliser ma position actuelle
        </Button>
        <p className="text-[11px] text-muted-foreground -mt-1 px-1">
          À utiliser si vous êtes actuellement dans votre boutique.
        </p>
        <Button type="button" variant="ghost" onClick={() => setManual((m) => !m)} className="w-full justify-start">
          <MapPin className="w-4 h-4 mr-2" />
          {manual ? "Masquer la saisie manuelle" : "Choisir sur la carte / saisir manuellement"}
        </Button>
      </div>
      {manual && (
        <div className="space-y-2 pt-2 border-t border-border/60">
          <div className="grid grid-cols-2 gap-2">
            <div>
              <Label htmlFor="lat" className="text-xs">Latitude</Label>
              <Input id="lat" value={lat} onChange={(e) => setLat(e.target.value)} placeholder="9.5092" />
            </div>
            <div>
              <Label htmlFor="lng" className="text-xs">Longitude</Label>
              <Input id="lng" value={lng} onChange={(e) => setLng(e.target.value)} placeholder="-13.7122" />
            </div>
          </div>
          <div>
            <Label htmlFor="district" className="text-xs">Quartier / commune</Label>
            <Input id="district" value={district} onChange={(e) => setDistrict(e.target.value)} placeholder="Madina, Conakry" />
          </div>
          <div>
            <Label htmlFor="landmark" className="text-xs">Repère</Label>
            <Input id="landmark" value={landmark} onChange={(e) => setLandmark(e.target.value)} placeholder="En face de la mosquée" />
          </div>
          <Button type="button" onClick={saveManual} size="sm" className="w-full">
            Enregistrer la position
          </Button>
        </div>
      )}
      {value && (
        <div className="flex items-start gap-2 rounded-xl bg-primary/5 p-2.5 text-xs">
          <Check className="w-4 h-4 text-primary mt-0.5" />
          <div className="flex-1">
            <p className="font-semibold text-foreground">Position confirmée</p>
            <p className="text-muted-foreground">
              {value.lat.toFixed(5)}, {value.lng.toFixed(5)} ·{" "}
              {value.location_source === "current_location" ? "Position actuelle" : "Pin manuel"}
              {value.location_accuracy_m ? ` · ±${Math.round(value.location_accuracy_m)}m` : ""}
            </p>
          </div>
        </div>
      )}
    </div>
  );
}
