import { useEffect, useState } from "react";
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetDescription } from "@/components/ui/sheet";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Switch } from "@/components/ui/switch";
import { Button } from "@/components/ui/button";
import { DISTRICTS } from "@/lib/marche";
import { createOrUpdateStore, getOwnStore, type MerchantStore } from "@/lib/marche/stores";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "@/hooks/use-toast";

export function StoreOnboardingSheet({
  open,
  onOpenChange,
  onCreated,
}: {
  open: boolean;
  onOpenChange: (v: boolean) => void;
  onCreated?: (s: MerchantStore) => void;
}) {
  const [name, setName] = useState("");
  const [district, setDistrict] = useState<string>("");
  const [bio, setBio] = useState("");
  const [delivery, setDelivery] = useState(true);
  const [choppay, setWONGO Pay] = useState(false);
  const [busy, setBusy] = useState(false);
  const [existing, setExisting] = useState<MerchantStore | null>(null);

  useEffect(() => {
    if (!open) return;
    (async () => {
      const { data } = await supabase.auth.getSession();
      const uid = data.session?.user.id;
      if (!uid) return;
      const own = await getOwnStore(uid);
      if (own) {
        setExisting(own);
        setName(own.name);
        setDistrict(own.district ?? "");
        setBio(own.bio ?? "");
        setDelivery(own.delivery_available);
        setWONGO Pay(own.choppay_enabled);
      }
    })();
  }, [open]);

  const submit = async () => {
    if (name.trim().length < 2) {
      toast({ title: "Nom requis", description: "Entrez le nom de votre boutique." });
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
      const store = await createOrUpdateStore({
        ownerUserId: uid,
        name: name.trim(),
        district: district || null,
        bio: bio.trim() || null,
        delivery_available: delivery,
        choppay_enabled: choppay,
      });
      toast({ title: existing ? "Boutique mise à jour" : "Boutique créée" });
      onCreated?.(store);
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
          <SheetTitle>{existing ? "Modifier ma boutique" : "Créer une boutique"}</SheetTitle>
          <SheetDescription className="text-xs">
            Une boutique vous donne une identité reconnaissable et regroupe vos annonces.
          </SheetDescription>
        </SheetHeader>
        <div className="space-y-3 mt-4">
          <div>
            <label className="text-xs font-medium text-foreground">Nom de la boutique</label>
            <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="Ex : Mariama Cosmétiques" maxLength={80} />
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
          <div>
            <label className="text-xs font-medium text-foreground">Présentation (optionnelle)</label>
            <Textarea value={bio} onChange={(e) => setBio(e.target.value)} maxLength={280} rows={3} placeholder="Ce que vous vendez, vos horaires, votre style…" />
          </div>
          <label className="flex items-center justify-between p-3 rounded-2xl bg-card shadow-card">
            <div>
              <p className="text-sm font-medium">Livraison disponible</p>
              <p className="text-[11px] text-muted-foreground">Activez si vous proposez la livraison.</p>
            </div>
            <Switch checked={delivery} onCheckedChange={setDelivery} />
          </label>
          <label className="flex items-center justify-between p-3 rounded-2xl bg-card shadow-card">
            <div>
              <p className="text-sm font-medium">WONGO Pay accepté</p>
              <p className="text-[11px] text-muted-foreground">Affiche un badge WONGO Pay sur votre boutique.</p>
            </div>
            <Switch checked={choppay} onCheckedChange={setWONGO Pay} />
          </label>
          <Button onClick={submit} disabled={busy} className="w-full">
            {busy ? "Enregistrement…" : existing ? "Mettre à jour" : "Créer ma boutique"}
          </Button>
        </div>
      </SheetContent>
    </Sheet>
  );
}