import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Loader2, Store, Sparkles } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { toast } from "@/hooks/use-toast";
import { Seo } from "@/components/Seo";
import { SecondaryPageHeader } from "@/components/ui/SecondaryPageHeader";
import { slugify } from "@/lib/marche";
import { normalizeGuineaPhone } from "@/lib/phone/guinea";
import { StoreLocationPicker, type StoreLocation } from "@/components/merchant/StoreLocationPicker";

export default function MerchantOnboarding() {
  const navigate = useNavigate();
  const { user, ready, isLoggedIn } = useAuth();
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [form, setForm] = useState({
    business_name: "",
    whatsapp: "",
    category: "",
    district: "",
  });
  const [location, setLocation] = useState<StoreLocation | null>(null);

  useEffect(() => {
    if (!ready) return;
    if (!isLoggedIn) {
      navigate("/auth", { replace: true });
      return;
    }
    (async () => {
      const { data } = await (supabase as any)
        .from("merchant_stores")
        .select("id")
        .eq("owner_user_id", user!.id)
        .maybeSingle();
      if (data) {
        navigate("/merchant/hub", { replace: true });
        return;
      }
      const meta = (user?.user_metadata as Record<string, unknown> | undefined) ?? {};
      setForm((f) => ({
        ...f,
        whatsapp: typeof meta.phone === "string" ? (meta.phone as string) : f.whatsapp,
      }));
      setLoading(false);
    })();
  }, [ready, isLoggedIn, user, navigate]);

  const setField = (k: keyof typeof form) => (v: string) =>
    setForm((f) => ({ ...f, [k]: v }));

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!user) return;
    if (!form.business_name.trim() || !form.whatsapp.trim()) {
      toast({ title: "Champs requis", description: "Nom de la boutique et WhatsApp." });
      return;
    }
    if (!location) {
      toast({ title: "Position requise", description: "Indiquez où se trouve votre boutique." });
      return;
    }
    setSubmitting(true);
    const normalizedPhone = normalizeGuineaPhone(form.whatsapp) || form.whatsapp.trim();
    const slug = `${slugify(form.business_name)}-${user.id.slice(0, 6)}`;
    const { error } = await (supabase as any).from("merchant_stores").insert({
      owner_user_id: user.id,
      created_by: user.id,
      name: form.business_name.trim(),
      slug,
      business_name: form.business_name.trim(),
      phone: normalizedPhone,
      whatsapp: normalizedPhone,
      district: (location.district || form.district.trim() || null),
      category: form.category.trim() || null,
      business_type: "shop",
      latitude: location.lat,
      longitude: location.lng,
      address_label: location.address_label ?? null,
      landmark: location.landmark ?? null,
      location_source: location.location_source,
      location_accuracy_m: location.location_accuracy_m ?? null,
      location_confirmed_at: new Date().toISOString(),
      status: "pending",
      onboarding_status: "submitted",
      submitted_at: new Date().toISOString(),
      verification_state: "pending",
      delivery_available: false,
      choppay_enabled: false,
    });
    setSubmitting(false);
    if (error) {
      toast({ title: "Erreur", description: error.message });
      return;
    }
    // Default mode to merchant after successful submission.
    try {
      await (supabase as any)
        .from("user_preferences")
        .upsert({ user_id: user.id, app_mode: "merchant" }, { onConflict: "user_id" });
    } catch { /* noop */ }
    toast({
      title: "Boutique créée",
      description: "Vérification en cours. Préparez votre catalogue dès maintenant.",
    });
    navigate("/merchant/hub", { replace: true });
  };

  if (!ready || loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <Loader2 className="w-6 h-6 animate-spin text-primary" />
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-background pb-16">
      <Seo
        title="Créer ma boutique — CHOPCHOP"
        description="Créez votre boutique CHOPCHOP Marché. Vos informations sont vérifiées par l'équipe avant publication."
        canonical="/merchant/onboarding"
      />
      <SecondaryPageHeader title="Créer ma boutique" subtitle="60 secondes pour ouvrir votre boutique CHOPCHOP." />
      <main className="max-w-md mx-auto px-4 -mt-5">
        <div className="bg-card border border-border/60 rounded-3xl shadow-card p-5">
          <div className="flex items-center gap-3 mb-4">
            <div className="w-10 h-10 rounded-2xl bg-primary/10 flex items-center justify-center">
              <Sparkles className="w-5 h-5 text-primary" />
            </div>
            <p className="text-xs text-muted-foreground">
              Créez votre boutique en quelques secondes. La vérification (pièce d'identité, selfie, photos) se fait ensuite depuis votre tableau de bord.
            </p>
          </div>
          <form onSubmit={submit} className="space-y-4">
            <div className="space-y-2">
              <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">1. Votre boutique</p>
              <div>
                <Label htmlFor="business_name">Nom de la boutique *</Label>
                <Input id="business_name" value={form.business_name} onChange={(e) => setField("business_name")(e.target.value)} placeholder="Ex. Chez Mariama" required />
              </div>
              <div className="grid grid-cols-2 gap-2">
                <div>
                  <Label htmlFor="category">Catégorie</Label>
                  <Input id="category" value={form.category} onChange={(e) => setField("category")(e.target.value)} placeholder="Ex. Alimentation" />
                </div>
                <div>
                  <Label htmlFor="whatsapp">WhatsApp *</Label>
                  <Input id="whatsapp" inputMode="tel" value={form.whatsapp} onChange={(e) => setField("whatsapp")(e.target.value)} placeholder="+224..." required />
                </div>
              </div>
            </div>

            <div className="space-y-2">
              <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">2. Où se trouve votre boutique ?</p>
              <div>
                <Label htmlFor="district">Marché / quartier</Label>
                <Input id="district" value={form.district} onChange={(e) => setField("district")(e.target.value)} placeholder="Ex. Madina, Ratoma" />
              </div>
              <StoreLocationPicker value={location} onChange={setLocation} />
            </div>

            <Button type="submit" className="w-full" disabled={submitting}>
              {submitting && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}
              <Store className="w-4 h-4 mr-2" /> Créer ma boutique
            </Button>
            <p className="text-[11px] text-muted-foreground text-center">
              Votre boutique sera en vérification. Vous pourrez préparer votre catalogue immédiatement — vos produits resteront privés jusqu'à l'approbation.
            </p>
          </form>
        </div>
      </main>
    </div>
  );
}