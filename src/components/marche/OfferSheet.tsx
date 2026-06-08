import { useState } from "react";
import { Sheet, SheetContent, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Loader2 } from "lucide-react";
import { toast } from "@/hooks/use-toast";
import { createOffer } from "@/lib/marche/offers";
import { formatGNF } from "@/lib/marche";

interface Props {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  listingId: string;
  askingPrice: number | null;
  onCreated?: () => void;
}

export function OfferSheet({ open, onOpenChange, listingId, askingPrice, onCreated }: Props) {
  const [amount, setAmount] = useState<string>("");
  const [message, setMessage] = useState("");
  const [saving, setSaving] = useState(false);

  const submit = async () => {
    const n = Number(amount);
    if (!n || n <= 0) {
      toast({ title: "Montant requis", description: "Indiquez votre offre en GNF." });
      return;
    }
    setSaving(true);
    try {
      await createOffer({ listingId, amountGnf: n, message });
      toast({ title: "Offre envoyée", description: "Le marchand sera notifié." });
      setAmount(""); setMessage("");
      onCreated?.();
      onOpenChange(false);
    } catch (e: any) {
      toast({ title: "Erreur", description: e?.message ?? "Action impossible" });
    } finally {
      setSaving(false);
    }
  };

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent side="bottom" className="max-h-[90vh] overflow-y-auto">
        <SheetHeader><SheetTitle>Faire une offre</SheetTitle></SheetHeader>
        <div className="mt-4 space-y-3">
          <p className="text-xs text-muted-foreground">
            1<sup>er</sup> prix affiché : <b>{formatGNF(askingPrice)}</b>
          </p>
          <div>
            <Label htmlFor="o-amt">Votre offre (GNF)</Label>
            <Input
              id="o-amt" type="number" inputMode="numeric" min={1}
              value={amount} onChange={(e) => setAmount(e.target.value)}
              placeholder="Ex. 75000"
            />
          </div>
          <div>
            <Label htmlFor="o-msg">Message (optionnel)</Label>
            <Textarea
              id="o-msg" rows={3} value={message}
              onChange={(e) => setMessage(e.target.value)}
              placeholder="Je peux payer aujourd'hui…"
            />
          </div>
          <p className="text-[11px] text-muted-foreground">
            Le marchand pourra accepter, refuser ou proposer un autre prix.
          </p>
          <Button className="w-full" onClick={submit} disabled={saving}>
            {saving ? <Loader2 className="w-4 h-4 animate-spin" /> : "Envoyer l'offre"}
          </Button>
        </div>
      </SheetContent>
    </Sheet>
  );
}