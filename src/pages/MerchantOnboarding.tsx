import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Loader2, Store } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "@/hooks/use-toast";
import { Seo } from "@/components/Seo";
import { SecondaryPageHeader } from "@/components/ui/SecondaryPageHeader";
import { slugify } from "@/lib/marche";
import { normalizeGuineaPhone } from "@/lib/phone/guinea";

const BUSINESS_TYPES = [
  { id: "market_stall", label: "Étal de marché" },
  { id: "shop", label: "Boutique" },
  { id: "wholesaler", label: "Grossiste" },
  { id: "home_seller", label: "Vente à domicile" },
  { id: "other", label: "Autre" },
];

export default function MerchantOnboarding() {
  const navigate = useNavigate();
  const { user, ready, isLoggedIn } = useAuth();
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [form, setForm] = useState({
    business_name: "",
    owner_name: "",
    phone: "",
    whatsapp: "",
    district: "",
    category: "",
    business_type: "market_stall",
    stall_number: "",
    operating_hours: "",
    description: "",
  });

  useEffect(() => {
    if (!ready) return;
    if (!isLoggedIn) {
      navigate("/auth", { replace: true });
      return;
    }
    (async () => {
      const { data } = await (supabase as any)
        .from("merchant_stores")
        .select("id, onboarding_status")
        .eq("owner_user_id", user!.id)
        .maybeSingle();
      if (data) {
        navigate("/merchant/hub", { replace: true });
        return;
      }
      const meta = (user?.user_metadata as Record<string, unknown> | undefined) ?? {};
      setForm((f) => ({
        ...f,
        owner_name: typeof meta.full_name === "string" ? (meta.full_name as string) : f.owner_name,
        phone: typeof meta.phone === "string" ? (meta.phone as string) : f.phone,
      }));
      setLoading(false);
    })();
  }, [ready, isLoggedIn, user, navigate]);

  const setField = (k: keyof typeof form) => (v: string) =>
    setForm((f) => ({ ...f, [k]: v }));

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!user) return;
    if (!form.business_name.trim() || !form.owner_name.trim() || !form.phone.trim()) {
      toast({ title: "Champs requis", description: "Nom de la boutique, propriétaire et téléphone." });
      return;
    }
    setSubmitting(true);
    const normalizedPhone = normalizeGuineaPhone(form.phone) || form.phone.trim();
    const slug = `${slugify(form.business_name)}-${user.id.slice(0, 6)}`;
    const { error } = await (supabase as any).from("merchant_stores").insert({
      owner_user_id: user.id,
      created_by: user.id,
      name: form.business_name.trim(),
      slug,
      business_name: form.business_name.trim(),
      owner_name: form.owner_name.trim(),
      phone: normalizedPhone,
      whatsapp: form.whatsapp.trim() || null,
      district: form.district.trim() || null,
      category: form.category.trim() || null,
      business_type: form.business_type,
      stall_number: form.stall_number.trim() || null,
      operating_hours: form.operating_hours.trim() || null,
      bio: form.description.trim() || null,
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
    toast({
      title: "Boutique envoyée",
      description: "Votre boutique est en vérification. Vous pouvez préparer votre catalogue.",
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
      <SecondaryPageHeader title="Créer ma boutique" subtitle="Présentez votre activité pour rejoindre CHOPCHOP Marché." />
      <main className="max-w-md mx-auto px-4 -mt-5">
        <div className="bg-card border border-border/60 rounded-3xl shadow-card p-5">
          <div className="flex items-center gap-3 mb-4">
            <div className="w-10 h-10 rounded-2xl bg-primary/10 flex items-center justify-center">
              <Store className="w-5 h-5 text-primary" />
            </div>
            <p className="text-xs text-muted-foreground">
              Votre boutique sera vérifiée par l'équipe CHOPCHOP avant d'être pleinement visible sur Marché.
            </p>
          </div>
          <form onSubmit={submit} className="space-y-3">
            <div>
              <Label htmlFor="business_name">Nom de la boutique *</Label>
              <Input id="business_name" value={form.business_name} onChange={(e) => setField("business_name")(e.target.value)} required />
            </div>
            <div className="grid grid-cols-2 gap-2">
              <div>
                <Label htmlFor="owner_name">Propriétaire *</Label>
                <Input id="owner_name" value={form.owner_name} onChange={(e) => setField("owner_name")(e.target.value)} required />
              </div>
              <div>
                <Label htmlFor="phone">Téléphone *</Label>
                <Input id="phone" inputMode="tel" value={form.phone} onChange={(e) => setField("phone")(e.target.value)} required />
              </div>
            </div>
            <div>
              <Label htmlFor="business_type">Type d'activité</Label>
              <select
                id="business_type"
                value={form.business_type}
                onChange={(e) => setField("business_type")(e.target.value)}
                className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm"
              >
                {BUSINESS_TYPES.map((t) => (
                  <option key={t.id} value={t.id}>{t.label}</option>
                ))}
              </select>
            </div>
            <div className="grid grid-cols-2 gap-2">
              <div>
                <Label htmlFor="district">Quartier / marché</Label>
                <Input id="district" value={form.district} onChange={(e) => setField("district")(e.target.value)} placeholder="Ex. Madina" />
              </div>
              <div>
                <Label htmlFor="stall_number">Étal / repère</Label>
                <Input id="stall_number" value={form.stall_number} onChange={(e) => setField("stall_number")(e.target.value)} placeholder="Étal 12B" />
              </div>
            </div>
            <div>
              <Label htmlFor="category">Catégorie principale</Label>
              <Input id="category" value={form.category} onChange={(e) => setField("category")(e.target.value)} placeholder="Ex. Alimentation, Mode, Électronique" />
            </div>
            <div className="grid grid-cols-2 gap-2">
              <div>
                <Label htmlFor="whatsapp">WhatsApp</Label>
                <Input id="whatsapp" inputMode="tel" value={form.whatsapp} onChange={(e) => setField("whatsapp")(e.target.value)} />
              </div>
              <div>
                <Label htmlFor="operating_hours">Horaires</Label>
                <Input id="operating_hours" value={form.operating_hours} onChange={(e) => setField("operating_hours")(e.target.value)} placeholder="Lun-Sam 8h-18h" />
              </div>
            </div>
            <div>
              <Label htmlFor="description">Description (optionnel)</Label>
              <Textarea id="description" value={form.description} onChange={(e) => setField("description")(e.target.value)} rows={3} />
            </div>
            <Button type="submit" className="w-full" disabled={submitting}>
              {submitting && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}
              Envoyer pour vérification
            </Button>
            <p className="text-[11px] text-muted-foreground text-center">
              Vous pourrez préparer votre catalogue immédiatement. Vos produits resteront privés jusqu'à l'approbation.
            </p>
          </form>
        </div>
      </main>
    </div>
  );
}