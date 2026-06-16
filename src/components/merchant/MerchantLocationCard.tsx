import { useEffect, useState } from "react";
import { MapPin, Locate, Loader2, Check, AlertTriangle, ShieldCheck, Pencil } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { toast } from "@/hooks/use-toast";
import { supabase } from "@/integrations/supabase/client";
import {
  merchantSubmitLocation,
  MERCHANT_LOC_LABEL,
  type MerchantLocationStatus,
} from "@/lib/maps/canonical";

type Props = {
  store: {
    id: string;
    name: string;
    latitude?: number | null;
    longitude?: number | null;
    landmark_note?: string | null;
    location_submission_status?: MerchantLocationStatus | null;
    location_notes?: string | null;
    map_place_id?: string | null;
  };
  onChanged?: () => void;
};

function tone(s: MerchantLocationStatus) {
  switch (s) {
    case "trusted":
    case "admin_verified":
      return "bg-emerald-500/15 text-emerald-700 dark:text-emerald-400";
    case "needs_review":
      return "bg-amber-500/15 text-amber-800 dark:text-amber-400";
    case "rejected":
      return "bg-destructive/15 text-destructive";
    case "submitted":
      return "bg-primary/15 text-primary";
    default:
      return "bg-muted text-muted-foreground";
  }
}

export function MerchantLocationCard({ store, onChanged }: Props) {
  const status: MerchantLocationStatus = (store.location_submission_status ?? "none") as MerchantLocationStatus;
  const hasCoords = Number.isFinite(store.latitude) && Number.isFinite(store.longitude);
  const [editing, setEditing] = useState<boolean>(status === "none");
  const [busy, setBusy] = useState<"locate" | "submit" | null>(null);
  const [lat, setLat] = useState<string>(store.latitude?.toString() ?? "");
  const [lng, setLng] = useState<string>(store.longitude?.toString() ?? "");
  const [landmark, setLandmark] = useState<string>(store.landmark_note ?? "");
  const [entrance, setEntrance] = useState<string>("");
  const [pickup, setPickup] = useState<string>("");
  const [address, setAddress] = useState<string>("");
  const [opNote, setOpNote] = useState<string>("");
  const [adminNote, setAdminNote] = useState<string | null>(store.location_notes ?? null);

  useEffect(() => {
    // Fetch latest place notes if linked, for "validée" display
    let cancel = false;
    if (store.map_place_id) {
      (supabase as any)
        .from("map_places")
        .select("entrance_note,pickup_note,landmark_note,operational_note")
        .eq("id", store.map_place_id)
        .maybeSingle()
        .then(({ data }: any) => {
          if (cancel || !data) return;
          setEntrance(data.entrance_note ?? "");
          setPickup(data.pickup_note ?? "");
          setLandmark((cur) => cur || data.landmark_note || "");
          setOpNote(data.operational_note ?? "");
        });
    }
    return () => { cancel = true; };
  }, [store.map_place_id]);

  const useCurrent = () => {
    if (!("geolocation" in navigator)) {
      toast({ title: "Indisponible", description: "Géolocalisation non disponible." });
      return;
    }
    setBusy("locate");
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setBusy(null);
        setLat(pos.coords.latitude.toFixed(6));
        setLng(pos.coords.longitude.toFixed(6));
        toast({ title: "Position détectée", description: "Vérifiez et envoyez pour validation." });
      },
      () => {
        setBusy(null);
        toast({
          title: "Position refusée",
          description: "Autorisez la géolocalisation ou saisissez les coordonnées manuellement.",
        });
      },
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 },
    );
  };

  const submit = async () => {
    const la = Number(lat);
    const ln = Number(lng);
    if (!Number.isFinite(la) || !Number.isFinite(ln) || Math.abs(la) > 90 || Math.abs(ln) > 180) {
      toast({ title: "Coordonnées invalides", description: "Vérifiez la latitude et la longitude.", variant: "destructive" });
      return;
    }
    setBusy("submit");
    try {
      await merchantSubmitLocation({
        storeId: store.id,
        lat: la,
        lng: ln,
        addressText: address || null,
        landmarkNote: landmark || null,
        entranceNote: entrance || null,
        pickupNote: pickup || null,
        operationalNote: opNote || null,
      });
      toast({ title: "Localisation envoyée", description: "Un admin va la vérifier." });
      setEditing(false);
      onChanged?.();
    } catch (e: any) {
      toast({ title: "Erreur", description: e?.message ?? "Envoi impossible", variant: "destructive" });
    } finally {
      setBusy(null);
    }
  };

  const StatusBadge = (
    <Badge variant="outline" className={`text-[10px] ${tone(status)}`}>
      {status === "trusted" || status === "admin_verified" ? (
        <ShieldCheck className="w-3 h-3 mr-1" />
      ) : status === "needs_review" || status === "rejected" ? (
        <AlertTriangle className="w-3 h-3 mr-1" />
      ) : (
        <MapPin className="w-3 h-3 mr-1" />
      )}
      {MERCHANT_LOC_LABEL[status]}
    </Badge>
  );

  const Header = (
    <div className="flex items-start justify-between gap-2">
      <div className="flex items-center gap-2">
        <MapPin className="w-4 h-4 text-primary" />
        <p className="text-sm font-semibold text-foreground">Localisation du commerce</p>
      </div>
      {StatusBadge}
    </div>
  );

  // Read-only view (verified / submitted / needs_review / rejected) when not editing
  if (!editing) {
    return (
      <div className="space-y-3 rounded-2xl border border-border/60 p-3 bg-card">
        {Header}
        {status === "submitted" && (
          <p className="text-xs text-muted-foreground">
            Localisation envoyée — en attente de validation par notre équipe.
          </p>
        )}
        {status === "needs_review" && (
          <p className="text-xs text-amber-700 dark:text-amber-400">
            Localisation à corriger. {adminNote ? `Note : ${adminNote}` : ""}
          </p>
        )}
        {status === "rejected" && (
          <p className="text-xs text-destructive">
            Localisation refusée. {adminNote ? `Note : ${adminNote}` : "Soumettez à nouveau."}
          </p>
        )}
        {(status === "admin_verified" || status === "trusted") && (
          <p className="text-xs text-emerald-700 dark:text-emerald-400">
            Localisation validée par CHOP CHOP.
          </p>
        )}
        {hasCoords && (
          <div className="rounded-xl bg-muted/40 p-2.5 text-xs space-y-1">
            <p className="text-muted-foreground">
              <span className="font-semibold text-foreground">Coordonnées :</span>{" "}
              {store.latitude!.toFixed(5)}, {store.longitude!.toFixed(5)}
            </p>
            {landmark && <p><span className="font-semibold">Repère :</span> {landmark}</p>}
            {entrance && <p><span className="font-semibold">Entrée :</span> {entrance}</p>}
            {pickup && <p><span className="font-semibold">Retrait :</span> {pickup}</p>}
          </div>
        )}
        <Button type="button" variant="outline" size="sm" className="w-full" onClick={() => setEditing(true)}>
          <Pencil className="w-4 h-4 mr-2" />
          {status === "admin_verified" || status === "trusted"
            ? "Demander une modification"
            : status === "rejected"
            ? "Soumettre à nouveau"
            : "Modifier la position"}
        </Button>
      </div>
    );
  }

  // Edit / submit form
  return (
    <div className="space-y-3 rounded-2xl border border-border/60 p-3 bg-card">
      {Header}
      {status === "none" && (
        <p className="text-xs text-muted-foreground">
          Ajoutez l'emplacement de votre commerce pour faciliter les livraisons.
        </p>
      )}
      <div className="grid grid-cols-1 gap-2">
        <Button type="button" variant="outline" onClick={useCurrent} disabled={busy !== null} className="w-full justify-start">
          {busy === "locate" ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <Locate className="w-4 h-4 mr-2" />}
          Utiliser ma position actuelle
        </Button>
        <p className="text-[11px] text-muted-foreground -mt-1 px-1">
          À utiliser si vous êtes actuellement dans votre boutique.
        </p>
      </div>
      <div className="grid grid-cols-2 gap-2">
        <div>
          <Label htmlFor="mlc-lat" className="text-xs">Latitude</Label>
          <Input id="mlc-lat" value={lat} onChange={(e) => setLat(e.target.value)} placeholder="9.5092" />
        </div>
        <div>
          <Label htmlFor="mlc-lng" className="text-xs">Longitude</Label>
          <Input id="mlc-lng" value={lng} onChange={(e) => setLng(e.target.value)} placeholder="-13.7122" />
        </div>
      </div>
      <div>
        <Label htmlFor="mlc-addr" className="text-xs">Adresse / description</Label>
        <Input id="mlc-addr" value={address} onChange={(e) => setAddress(e.target.value)} placeholder="Madina, marché Niger" />
      </div>
      <div>
        <Label htmlFor="mlc-landmark" className="text-xs">Près de…</Label>
        <Input id="mlc-landmark" value={landmark} onChange={(e) => setLandmark(e.target.value)} placeholder="En face de la mosquée" />
      </div>
      <div>
        <Label htmlFor="mlc-entrance" className="text-xs">Entrée par…</Label>
        <Input id="mlc-entrance" value={entrance} onChange={(e) => setEntrance(e.target.value)} placeholder="Porte bleue côté rue" />
      </div>
      <div>
        <Label htmlFor="mlc-pickup" className="text-xs">Point de retrait</Label>
        <Input id="mlc-pickup" value={pickup} onChange={(e) => setPickup(e.target.value)} placeholder="Comptoir à l'entrée" />
      </div>
      <div>
        <Label htmlFor="mlc-op" className="text-xs">Note opérationnelle (optionnel)</Label>
        <Textarea
          id="mlc-op"
          value={opNote}
          onChange={(e) => setOpNote(e.target.value)}
          placeholder="Heures de pointe, accès livreur, etc."
          rows={2}
        />
      </div>
      <div className="flex gap-2">
        <Button type="button" onClick={submit} disabled={busy !== null} className="flex-1">
          {busy === "submit" ? <Loader2 className="w-4 h-4 mr-2 animate-spin" /> : <Check className="w-4 h-4 mr-2" />}
          Envoyer pour validation
        </Button>
        {status !== "none" && (
          <Button type="button" variant="ghost" onClick={() => setEditing(false)} disabled={busy !== null}>
            Annuler
          </Button>
        )}
      </div>
      <p className="text-[10px] text-muted-foreground">
        Votre position sera marquée comme « soumise » jusqu'à validation par CHOP CHOP.
      </p>
    </div>
  );
}