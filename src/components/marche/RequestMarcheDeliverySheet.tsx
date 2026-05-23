import { useState } from "react";
import { Truck, Loader2 } from "lucide-react";
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetDescription,
} from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { toast } from "@/hooks/use-toast";
import {
  requestMarcheDelivery,
  type RequestMarcheDeliveryInput,
} from "@/lib/marche/delivery";

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  listing: RequestMarcheDeliveryInput["listing"];
  buyerId: string;
  sellerName?: string | null;
  storeId?: string | null;
  storeName?: string | null;
  defaultDropoff?: string | null;
  onRequested?: (missionId: string) => void;
}

/**
 * Lightweight buyer-facing sheet to ask CHOPCHOP for delivery on a Marché
 * listing. Stays opt-in and trust-based — no fake ETA, no fake fee.
 */
export function RequestMarcheDeliverySheet({
  open,
  onOpenChange,
  listing,
  buyerId,
  sellerName,
  storeId,
  storeName,
  defaultDropoff,
  onRequested,
}: Props) {
  const [dropoff, setDropoff] = useState(defaultDropoff ?? "");
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);

  const submit = async () => {
    const trimmed = dropoff.trim();
    if (!trimmed) {
      toast({ title: "Adresse manquante", description: "Précisez où livrer." });
      return;
    }
    setBusy(true);
    try {
      const m = await requestMarcheDelivery({
        listing,
        buyerId,
        sellerName,
        storeId,
        storeName,
        dropoffAddress: trimmed,
        notes: note,
      });
      toast({
        title: "Livraison CHOPCHOP demandée",
        description: "Un coursier va prendre en charge votre demande.",
      });
      onRequested?.(m.id);
      onOpenChange(false);
    } catch (e) {
      toast({
        title: "Demande impossible",
        description: (e as Error).message ?? "Réessayez plus tard.",
      });
    } finally {
      setBusy(false);
    }
  };

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="bottom" className="rounded-t-3xl">
        <SheetHeader className="text-left">
          <SheetTitle className="flex items-center gap-2">
            <Truck className="w-5 h-5 text-primary" />
            Demander une livraison CHOPCHOP
          </SheetTitle>
          <SheetDescription>
            Optionnel — votre vendeur peut aussi vous remettre l’article en main propre.
          </SheetDescription>
        </SheetHeader>
        <div className="space-y-3 py-4">
          <div className="rounded-2xl bg-muted/60 p-3 text-sm">
            <p className="font-medium truncate">{listing.title}</p>
            {(storeName || sellerName) && (
              <p className="text-xs text-muted-foreground mt-0.5 truncate">
                {storeName ?? sellerName}
              </p>
            )}
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="dropoff">Adresse de livraison</Label>
            <Input
              id="dropoff"
              value={dropoff}
              onChange={(e) => setDropoff(e.target.value)}
              placeholder="Quartier, repère, n°…"
              maxLength={140}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="note">Instructions (optionnel)</Label>
            <Textarea
              id="note"
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="Étage, contact, créneau…"
              maxLength={240}
              rows={3}
            />
          </div>
          <p className="text-[11px] text-muted-foreground">
            CHOPCHOP cherche un coursier disponible. Aucun engagement de prix ni d’horaire
            tant que le vendeur n’a pas confirmé.
          </p>
        </div>
        <div className="flex gap-2 pb-2">
          <Button variant="outline" className="flex-1" onClick={() => onOpenChange(false)} disabled={busy}>
            Annuler
          </Button>
          <Button className="flex-1" onClick={submit} disabled={busy}>
            {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : "Demander"}
          </Button>
        </div>
      </SheetContent>
    </Sheet>
  );
}