import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Loader2, Store, Sparkles, ShieldCheck } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/contexts/AuthContext";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Checkbox } from "@/components/ui/checkbox";
import { toast } from "@/hooks/use-toast";
import { Seo } from "@/components/Seo";
import { SecondaryPageHeader } from "@/components/ui/SecondaryPageHeader";
import { slugify } from "@/lib/marche";
import { normalizeGuineaPhone } from "@/lib/phone/guinea";
import { StoreLocationPicker, type StoreLocation } from "@/components/merchant/StoreLocationPicker";
import { MERCHANT_PRODUCT_CATEGORIES } from "@/lib/merchant/categories";
import { createOrUpdateRestaurant } from "@/lib/repas/restaurants";

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
    commune: "",
    market_name: "",
    landmark_note: "",
  });
  const [location, setLocation] = useState<StoreLocation | null>(null);
  const [categories, setCategories] = useState<string[]>([]);
  const [biz, setBiz] = useState({
    wants_marketplace: true,
    wants_food: false,
    wants_wallet_agent: false,
  });
  const [serviceAgentOptIn, setServiceAgentOptIn] = useState(false);

  useEffect(() => {
    if (!ready) return;
    if (!isLoggedIn) {
      navigate("/auth", { replace: true });
      return;
    }
    (async () => {
      const [{ data: storeRow }, { data: restoRow }] = await Promise.all([
        (supabase as any)
          .from("merchant_stores")
          .select("id")
          .eq("owner_user_id", user!.id)
          .maybeSingle(),
        (supabase as any)
          .from("food_restaurants")
          .select("id")
          .eq("owner_user_id", user!.id)
          .maybeSingle(),
      ]);
      if (storeRow || restoRow) {
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

  const toggleCategory = (id: string) =>
    setCategories((prev) => (prev.includes(id) ? prev.filter((c) => c !== id) : [...prev, id]));

  const captureMethod = (loc: StoreLocation): "gps" | "map_pin" | "manual" =>
    loc.location_source === "current_location" ? "gps" : "map_pin";

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
    const isRepasOnly = biz.wants_food && !biz.wants_marketplace && !biz.wants_wallet_agent;
    if (!isRepasOnly && categories.length === 0) {
      toast({ title: "Catégories requises", description: "Sélectionnez au moins une catégorie de produits." });
      return;
    }
    if (!biz.wants_marketplace && !biz.wants_food && !biz.wants_wallet_agent) {
      toast({ title: "Type d'activité", description: "Choisissez au moins un type d'activité." });
      return;
    }
    setSubmitting(true);
    const normalizedPhone = normalizeGuineaPhone(form.whatsapp) || form.whatsapp.trim();
    const slug = `${slugify(form.business_name)}-${user.id.slice(0, 6)}`;

    // Repas-only signups skip the merchant_stores row entirely so the
    // dashboard renders the dedicated restaurant layout, not the product
    // marketplace shell. Mixed and Marché-only signups still create a store.
    if (!isRepasOnly) {
      const { error } = await (supabase as any).from("merchant_stores").insert({
      owner_user_id: user.id,
      created_by: user.id,
      name: form.business_name.trim(),
      slug,
      business_name: form.business_name.trim(),
      phone: normalizedPhone,
      whatsapp: normalizedPhone,
      district: (location.district || form.district.trim() || null),
      category: categories[0] ?? null,
      business_type: "shop",
      latitude: location.lat,
      longitude: location.lng,
      address_label: location.address_label ?? null,
      landmark: location.landmark ?? form.landmark_note.trim() ?? null,
      location_source: location.location_source,
      location_accuracy_m: location.location_accuracy_m ?? null,
      location_confirmed_at: new Date().toISOString(),
      status: "pending",
      onboarding_status: "submitted",
      submitted_at: new Date().toISOString(),
      verification_state: "pending",
      delivery_available: false,
      choppay_enabled: false,
      // Phase 1 — Merchant pipeline foundation
      commune: form.commune.trim() || null,
      market_name: form.market_name.trim() || null,
      landmark_note: form.landmark_note.trim() || null,
      location_capture_method: captureMethod(location),
      product_categories: categories,
      wants_marketplace: biz.wants_marketplace,
      wants_food: biz.wants_food,
      wants_wallet_agent: biz.wants_wallet_agent,
      service_agent_requested: serviceAgentOptIn,
      service_agent_status: serviceAgentOptIn ? "pending" : "not_requested",
      onboarding_branch: "merchant",
      merchant_status: "pending",
      });
      if (error) {
        setSubmitting(false);
        toast({ title: "Erreur", description: error.message });
        return;
      }
    }

    // Provision the Repas restaurant when the user opted into "Vendre des
    // repas" — both for Repas-only and mixed signups. Without this the user
    // lands on the product-merchant dashboard with no menu/orders surface.
    if (biz.wants_food) {
      try {
        await createOrUpdateRestaurant({
          ownerUserId: user.id,
          name: form.business_name.trim(),
          district: location.district || form.district.trim() || null,
          delivery_available: false,
          pickup_available: true,
        });
      } catch (e) {
        // Non-fatal: store/onboarding still succeeded. User can finish
        // setup from the Repas profile section.
        if (import.meta.env.DEV) console.warn("[onboarding] repas restaurant create failed", e);
      }
    }
    setSubmitting(false);
    // Default mode to merchant after successful submission.
    try {
      await (supabase as any)
        .from("user_preferences")
        .upsert({ user_id: user.id, app_mode: "merchant" }, { onConflict: "user_id" });
    } catch { /* noop */ }
    toast({
      title: isRepasOnly ? "Restaurant créé" : "Boutique créée",
      description: isRepasOnly
        ? "Préparez votre menu et activez les commandes dès maintenant."
        : "Vérification en cours. Préparez votre catalogue dès maintenant.",
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
              <div>
                <Label htmlFor="whatsapp">WhatsApp *</Label>
                <Input id="whatsapp" inputMode="tel" value={form.whatsapp} onChange={(e) => setField("whatsapp")(e.target.value)} placeholder="+224..." required />
              </div>
            </div>

            <div className="space-y-2">
              <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">2. Catégories de produits *</p>
              <p className="text-[11px] text-muted-foreground">Sélectionnez ce que vous vendez. Modifiable plus tard.</p>
              <div className="flex flex-wrap gap-1.5">
                {MERCHANT_PRODUCT_CATEGORIES.map((c) => {
                  const active = categories.includes(c.id);
                  return (
                    <button
                      type="button"
                      key={c.id}
                      onClick={() => toggleCategory(c.id)}
                      className={`text-xs px-3 py-1.5 rounded-full border transition ${
                        active
                          ? "bg-primary text-primary-foreground border-primary"
                          : "bg-card text-foreground border-border/60 hover:border-primary/40"
                      }`}
                    >
                      {c.label}
                    </button>
                  );
                })}
              </div>
            </div>

            <div className="space-y-2">
              <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">3. Où se trouve votre boutique ?</p>
              <p className="text-[11px] text-muted-foreground">
                Astuce : tenez-vous dans ou devant votre boutique puis touchez « Utiliser ma position actuelle ».
              </p>
              <div className="grid grid-cols-2 gap-2">
                <div>
                  <Label htmlFor="commune">Commune</Label>
                  <Input id="commune" value={form.commune} onChange={(e) => setField("commune")(e.target.value)} placeholder="Ex. Kaloum" />
                </div>
                <div>
                  <Label htmlFor="market_name">Marché</Label>
                  <Input id="market_name" value={form.market_name} onChange={(e) => setField("market_name")(e.target.value)} placeholder="Ex. Madina" />
                </div>
              </div>
              <div>
                <Label htmlFor="district">Quartier</Label>
                <Input id="district" value={form.district} onChange={(e) => setField("district")(e.target.value)} placeholder="Ex. Ratoma" />
              </div>
              <div>
                <Label htmlFor="landmark_note">Repère</Label>
                <Input id="landmark_note" value={form.landmark_note} onChange={(e) => setField("landmark_note")(e.target.value)} placeholder="Ex. En face de la mosquée" />
              </div>
              <StoreLocationPicker value={location} onChange={setLocation} />
            </div>

            <div className="space-y-2">
              <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">4. Que voulez-vous faire sur CHOPCHOP ?</p>
              <div className="space-y-2">
                <label className="flex items-start gap-3 p-3 rounded-2xl border border-border/60 bg-card cursor-pointer">
                  <Checkbox checked={biz.wants_marketplace} onCheckedChange={(v) => setBiz((b) => ({ ...b, wants_marketplace: !!v }))} />
                  <div className="text-sm">
                    <p className="font-semibold">Vendre des produits (Marché)</p>
                    <p className="text-[11px] text-muted-foreground">Cataloguez et vendez vos articles avec CHOP Livraison.</p>
                  </div>
                </label>
                <label className="flex items-start gap-3 p-3 rounded-2xl border border-border/60 bg-card cursor-pointer">
                  <Checkbox checked={biz.wants_food} onCheckedChange={(v) => setBiz((b) => ({ ...b, wants_food: !!v }))} />
                  <div className="text-sm">
                    <p className="font-semibold">Vendre des repas</p>
                    <p className="text-[11px] text-muted-foreground">Restaurant / cuisine. Tableau de bord Repas avec menu et commandes.</p>
                  </div>
                </label>
                <label className="flex items-start gap-3 p-3 rounded-2xl border border-border/60 bg-card cursor-pointer">
                  <Checkbox
                    checked={serviceAgentOptIn}
                    onCheckedChange={(v) => {
                      const checked = !!v;
                      setServiceAgentOptIn(checked);
                      setBiz((b) => ({ ...b, wants_wallet_agent: checked }));
                    }}
                  />
                  <div className="text-sm">
                    <p className="font-semibold flex items-center gap-1.5">
                      Devenir Agent CHOP Wallet <ShieldCheck className="w-3.5 h-3.5 text-primary" />
                    </p>
                    <p className="text-[11px] text-muted-foreground">
                      Aidez les clients à recharger leur wallet. <strong>Validation admin requise</strong> avant activation.
                    </p>
                  </div>
                </label>
              </div>
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