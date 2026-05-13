import { useState } from "react";
import { formatGNF } from "@/lib/format";
import { ArrowLeft, Camera, X, ChevronRight, Check } from "lucide-react";
import { motion } from "framer-motion";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Switch } from "@/components/ui/switch";
import { MARCHE_CATEGORIES } from "@/lib/marche";
import { toast } from "@/hooks/use-toast";
import { z } from "zod";

const schema = z.object({
  title: z.string().trim().min(3, "Titre trop court").max(120),
  description: z.string().trim().max(2000).optional(),
  price_gnf: z.number().int().nonnegative().nullable(),
  category: z.string().min(1, "Choisissez une catégorie"),
  neighborhood: z.string().trim().max(80).optional(),
  commune: z.string().trim().max(80).optional(),
  landmark: z.string().trim().max(120).optional(),
});

export function SellFlow({ onClose, onPosted }: { onClose: () => void; onPosted: (id: string) => void }) {
  const [step, setStep] = useState(1);
  const [files, setFiles] = useState<File[]>([]);
  const [previews, setPreviews] = useState<string[]>([]);
  const [category, setCategory] = useState("");
  const [title, setTitle] = useState("");
  const [priceMode, setPriceMode] = useState<"fixed" | "negotiable" | "free">("fixed");
  const [price, setPrice] = useState("");
  const [description, setDescription] = useState("");
  const [neighborhood, setNeighborhood] = useState("");
  const [commune, setCommune] = useState("");
  const [landmark, setLandmark] = useState("");
  const [delivery, setDelivery] = useState(true);
  const [urgent, setUrgent] = useState(false);
  const [busy, setBusy] = useState(false);

  const addFiles = (fl: FileList | null) => {
    if (!fl) return;
    const list = Array.from(fl).slice(0, 8 - files.length);
    setFiles((p) => [...p, ...list]);
    list.forEach((f) => {
      const reader = new FileReader();
      reader.onload = (e) => setPreviews((p) => [...p, e.target?.result as string]);
      reader.readAsDataURL(f);
    });
  };

  const removePhoto = (i: number) => {
    setFiles((p) => p.filter((_, idx) => idx !== i));
    setPreviews((p) => p.filter((_, idx) => idx !== i));
  };

  const next = () => setStep((s) => Math.min(8, s + 1));
  const back = () => (step === 1 ? onClose() : setStep((s) => s - 1));

  const publish = async () => {
    setBusy(true);
    const { data: sess } = await supabase.auth.getSession();
    if (!sess.session) {
      toast({ title: "Connexion requise", description: "Connectez-vous pour publier." });
      setBusy(false);
      return;
    }
    const uid = sess.session.user.id;
    const parsed = schema.safeParse({
      title,
      description: description || undefined,
      price_gnf: priceMode === "free" ? null : price ? parseInt(price.replace(/\D/g, ""), 10) : null,
      category,
      neighborhood: neighborhood || undefined,
      commune: commune || undefined,
      landmark: landmark || undefined,
    });
    if (!parsed.success) {
      toast({ title: "Vérifiez votre annonce", description: parsed.error.issues[0].message });
      setBusy(false);
      return;
    }

    const { data: listing, error } = await supabase
      .from("marketplace_listings")
      .insert({
        seller_id: uid,
        kind: "community",
        category: parsed.data.category,
        title: parsed.data.title,
        description: parsed.data.description ?? null,
        price_gnf: parsed.data.price_gnf,
        is_negotiable: priceMode === "negotiable",
        is_urgent: urgent,
        delivery_available: delivery,
        neighborhood: parsed.data.neighborhood ?? null,
        commune: parsed.data.commune ?? null,
        landmark: parsed.data.landmark ?? null,
      })
      .select("id")
      .single();
    if (error || !listing) {
      toast({ title: "Erreur", description: error?.message ?? "Publication échouée" });
      setBusy(false);
      return;
    }

    // Upload images
    const uploaded: { url: string; position: number }[] = [];
    for (let i = 0; i < files.length; i++) {
      const f = files[i];
      const ext = f.name.split(".").pop() || "jpg";
      const path = `${uid}/${listing.id}/${Date.now()}_${i}.${ext}`;
      const { error: upErr } = await supabase.storage.from("marche-listings").upload(path, f, { upsert: false });
      if (!upErr) {
        const { data: pub } = supabase.storage.from("marche-listings").getPublicUrl(path);
        uploaded.push({ url: pub.publicUrl, position: i });
      }
    }
    if (uploaded.length > 0) {
      await supabase.from("listing_images").insert(
        uploaded.map((u) => ({ listing_id: listing.id, url: u.url, position: u.position }))
      );
    }

    setBusy(false);
    toast({ title: "Annonce publiée", description: "Votre annonce est en ligne." });
    onPosted(listing.id);
  };

  const canNext = (() => {
    if (step === 1) return files.length > 0;
    if (step === 2) return !!category;
    if (step === 3) return title.trim().length >= 3;
    if (step === 4) return priceMode === "negotiable" || priceMode === "free" || !!price;
    if (step === 5) return true;
    if (step === 6) return !!neighborhood || !!commune;
    return true;
  })();

  return (
    <div className="fixed inset-0 z-[60] bg-background overflow-y-auto">
      <div className="max-w-md mx-auto pb-28">
        <header className="sticky top-0 z-10 bg-background flex items-center gap-3 p-4 border-b">
          <button onClick={back} className="p-2 -ml-2 rounded-full hover:bg-muted">
            <ArrowLeft className="w-5 h-5" />
          </button>
          <div className="flex-1">
            <p className="text-xs text-muted-foreground">Étape {step} / 8</p>
            <h1 className="font-semibold">Vendre sur Marché</h1>
          </div>
        </header>
        <div className="h-1 bg-muted">
          <motion.div
            className="h-full bg-primary"
            initial={false}
            animate={{ width: `${(step / 8) * 100}%` }}
          />
        </div>

        <div className="p-4 space-y-4">
          {step === 1 && (
            <section>
              <h2 className="font-semibold mb-1">Ajoutez des photos</h2>
              <p className="text-sm text-muted-foreground mb-4">Jusqu'à 8 photos. Les bonnes photos vendent plus vite.</p>
              <div className="grid grid-cols-3 gap-2">
                {previews.map((src, i) => (
                  <div key={i} className="relative aspect-square rounded-xl overflow-hidden bg-muted">
                    <img src={src} alt="" className="w-full h-full object-cover" />
                    <button onClick={() => removePhoto(i)} className="absolute top-1 right-1 bg-background/90 rounded-full p-1">
                      <X className="w-3 h-3" />
                    </button>
                  </div>
                ))}
                {files.length < 8 && (
                  <label className="aspect-square rounded-xl border-2 border-dashed border-border flex flex-col items-center justify-center text-muted-foreground cursor-pointer hover:bg-muted/50">
                    <Camera className="w-6 h-6" />
                    <span className="text-xs mt-1">Ajouter</span>
                    <input type="file" accept="image/*" multiple className="hidden" onChange={(e) => addFiles(e.target.files)} />
                  </label>
                )}
              </div>
            </section>
          )}
          {step === 2 && (
            <section>
              <h2 className="font-semibold mb-3">Choisissez une catégorie</h2>
              <div className="grid grid-cols-3 gap-2">
                {MARCHE_CATEGORIES.map((c) => {
                  const Icon = c.icon;
                  return (
                    <button
                      key={c.id}
                      onClick={() => setCategory(c.id)}
                      className={`flex flex-col items-center gap-1 p-3 rounded-2xl border ${
                        category === c.id ? "border-primary bg-primary/5" : "border-border bg-card"
                      }`}
                    >
                      <div className={`w-10 h-10 rounded-xl ${c.tint} flex items-center justify-center`}>
                        <Icon className={`w-5 h-5 ${c.fg}`} />
                      </div>
                      <span className="text-[11px] text-center leading-tight">{c.label}</span>
                    </button>
                  );
                })}
              </div>
            </section>
          )}
          {step === 3 && (
            <section className="space-y-2">
              <h2 className="font-semibold">Titre de l'annonce</h2>
              <Input
                placeholder="Ex : iPhone 13 Pro 256GB"
                value={title}
                maxLength={120}
                onChange={(e) => setTitle(e.target.value)}
              />
              <p className="text-xs text-muted-foreground">{title.length}/120</p>
            </section>
          )}
          {step === 4 && (
            <section className="space-y-3">
              <h2 className="font-semibold">Prix</h2>
              <div className="grid grid-cols-3 gap-2">
                {(["fixed", "negotiable", "free"] as const).map((m) => (
                  <button
                    key={m}
                    onClick={() => setPriceMode(m)}
                    className={`px-3 py-2 rounded-xl text-sm border ${
                      priceMode === m ? "bg-primary text-primary-foreground border-primary" : "bg-card border-border"
                    }`}
                  >
                    {m === "fixed" ? "Fixe" : m === "negotiable" ? "Négociable" : "Gratuit"}
                  </button>
                ))}
              </div>
              {priceMode !== "free" && (
                <div>
                  <Input
                    type="text"
                    inputMode="numeric"
                    placeholder="Prix en GNF"
                    value={price}
                    onChange={(e) => setPrice(e.target.value.replace(/\D/g, ""))}
                  />
                  <p className="text-xs text-muted-foreground mt-1">
                    {price ? formatGNF(parseInt(price, 10)) : ""}
                  </p>
                </div>
              )}
            </section>
          )}
          {step === 5 && (
            <section className="space-y-2">
              <h2 className="font-semibold">Description</h2>
              <Textarea
                placeholder="Décrivez votre produit (état, marque, accessoires, raison de la vente)…"
                value={description}
                maxLength={2000}
                onChange={(e) => setDescription(e.target.value)}
                rows={6}
              />
              <p className="text-xs text-muted-foreground">{description.length}/2000</p>
            </section>
          )}
          {step === 6 && (
            <section className="space-y-3">
              <h2 className="font-semibold">Localisation</h2>
              <Input placeholder="Quartier (ex : Kipé)" value={neighborhood} onChange={(e) => setNeighborhood(e.target.value)} />
              <Input placeholder="Commune (ex : Ratoma)" value={commune} onChange={(e) => setCommune(e.target.value)} />
              <Input placeholder="Repère (ex : près de la pharmacie)" value={landmark} onChange={(e) => setLandmark(e.target.value)} />
            </section>
          )}
          {step === 7 && (
            <section className="space-y-3">
              <h2 className="font-semibold">Options</h2>
              <label className="flex items-center justify-between p-4 rounded-2xl bg-card shadow-card">
                <div>
                  <p className="font-medium">Livraison CHOP CHOP disponible</p>
                  <p className="text-xs text-muted-foreground">Un livreur peut récupérer et livrer l'article.</p>
                </div>
                <Switch checked={delivery} onCheckedChange={setDelivery} />
              </label>
              <label className="flex items-center justify-between p-4 rounded-2xl bg-card shadow-card">
                <div>
                  <p className="font-medium">Vente urgente</p>
                  <p className="text-xs text-muted-foreground">Affiche un badge Urgent sur votre annonce.</p>
                </div>
                <Switch checked={urgent} onCheckedChange={setUrgent} />
              </label>
            </section>
          )}
          {step === 8 && (
            <section className="space-y-3">
              <h2 className="font-semibold">Récapitulatif</h2>
              <div className="bg-card rounded-2xl p-4 shadow-card space-y-1 text-sm">
                <p className="font-semibold">{title}</p>
                <p className="text-primary font-bold">
                  {priceMode === "free"
                    ? "Gratuit"
                    : price
                    ? formatGNF(parseInt(price, 10))
                    : "Prix à discuter"}
                  {priceMode === "negotiable" && <span className="ml-2 text-xs text-muted-foreground">Négociable</span>}
                </p>
                <p className="text-xs text-muted-foreground">
                  {[neighborhood, commune].filter(Boolean).join(", ") || "Conakry"}
                </p>
                <p className="text-xs text-muted-foreground">
                  {files.length} photo{files.length > 1 ? "s" : ""} · Livraison {delivery ? "oui" : "non"}
                </p>
              </div>
            </section>
          )}
        </div>

        <div className="fixed bottom-0 left-0 right-0 max-w-md mx-auto p-4 pb-[max(1rem,env(safe-area-inset-bottom))] bg-background border-t z-[70]">
          {step < 8 ? (
            <Button onClick={next} disabled={!canNext} className="w-full">
              Continuer <ChevronRight className="w-4 h-4 ml-1" />
            </Button>
          ) : (
            <Button onClick={publish} disabled={busy} className="w-full">
              {busy ? "Publication…" : (
                <>
                  <Check className="w-4 h-4 mr-1" /> Publier l'annonce
                </>
              )}
            </Button>
          )}
        </div>
      </div>
    </div>
  );
}